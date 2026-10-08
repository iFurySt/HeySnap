import AppKit
import Carbon
import QuartzCore

/// The outcome of an interactive capture selection session.
enum CaptureSelection {
    case region(CGRect)
    case copyRegion(CGRect, [OverlayMarkupAnnotation], CapturedScreenshot?)
    case saveRegion(CGRect, [OverlayMarkupAnnotation], CapturedScreenshot?)
    case pinRegion(CGRect, [OverlayMarkupAnnotation], CapturedScreenshot?)
    case editRegion(CGRect, CapturedScreenshot?)
    case scrollingCapture(CapturedScreenshot)
    case window(WindowDescriptor)
    case cancelled
}

private extension CaptureSelection {
    var hasPreCapturedRegion: Bool {
        switch self {
        case .copyRegion(_, _, .some),
             .saveRegion(_, _, .some),
             .pinRegion(_, _, .some),
             .editRegion(_, .some):
            return true
        default:
            return false
        }
    }

    var requiresOverlayClearBeforeCompletion: Bool {
        switch self {
        case .copyRegion,
             .saveRegion,
             .pinRegion,
             .editRegion,
             .scrollingCapture:
            return true
        default:
            return false
        }
    }
}

/// Drives the interactive capture overlay: hover to highlight an app window and click to
/// select it, or press-and-drag to select a free-form region. The overlay is presented
/// without activating HeySnap, so the target app stays frontmost after capture.
@MainActor
final class AreaSelectionController {
    private var session: AreaSelectionSession?
    var isSelecting: Bool { session != nil }

    func beginSelection(
        quickMarkupEnabled: Bool = false,
        screenSnapshot: CapturedScreenshot? = nil,
        onScrollingCapture: @escaping (CGRect, ScrollingCaptureCancellation, @escaping (CapturedScreenshot?) -> Void) -> Void = { _, _, completion in completion(nil) },
        onComplete: @escaping (CaptureSelection) -> Void
    ) {
        guard session == nil else { return }

        let session = AreaSelectionSession(
            quickMarkupEnabled: quickMarkupEnabled,
            screenSnapshot: screenSnapshot,
            onScrollingCapture: onScrollingCapture
        ) { [weak self] selection in
            self?.session = nil
            onComplete(selection)
        }
        self.session = session
        session.start()
    }
}

/// Coordinates one selection session across all displays. Owns a borderless overlay window
/// per screen and the shared interaction state (hovered window, drag rectangle).
@MainActor
final class AreaSelectionSession {
    private let onComplete: (CaptureSelection) -> Void
    private let quickMarkupEnabled: Bool
    private let screenSnapshot: CapturedScreenshot?
    private let snapshotScreenFrame: CGRect?
    private let snapshotWindows: [WindowDescriptor]?
    private let onScrollingCapture: (CGRect, ScrollingCaptureCancellation, @escaping (CapturedScreenshot?) -> Void) -> Void
    private var windows: [AreaSelectionWindow] = []
    private var views: [AreaSelectionView] = []
    private weak var activeTextEditingView: AreaSelectionView?

    private var excludedWindowNumbers: Set<CGWindowID> = []

    /// Global (bottom-left origin) coordinates.
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var isDragging = false
    private var hoveredWindow: WindowDescriptor?
    private var didComplete = false
    private var markupRect: CGRect?
    private var isMovingMarkupRect = false
    private var movingMarkupOrigin: CGRect?
    private var markupBarRect: CGRect?
    private var isMovingMarkupBar = false
    private var markupBarOrigin: CGRect?
    private var hoveredBarIndex: Int?
    private var hoveredBarTooltipCandidateIndex: Int?
    private var hoveredTooltipBarIndex: Int?
    private var tooltipWorkItem: DispatchWorkItem?
    private var noticeMessage: String?
    private var noticeWorkItem: DispatchWorkItem?
    private var isScrollingCaptureInProgress = false
    private var scrollingCancellation: ScrollingCaptureCancellation?
    private var scrollingModeEnabled = false
    private var scrollingResult: CapturedScreenshot?
    private var scrollingDestination: ScrollingDestination?
    private var scrollingToolbarWindow: AreaSelectionWindow?
    private var scrollingToolbarView: AreaSelectionView?
    private var scrollingHUD: ScrollingCaptureHUD?

    private enum ScrollingDestination { case copy, save, pin, editor }
    private var pointerDownPoint: CGPoint?
    private var activeMarkupHandle: OverlaySelectionHandle?
    private var resizeMarkupOrigin: CGRect?
    private var activePropertyDrag: OverlayPropertyDrag?
    private var markupTool: OverlayMarkupTool = .select
    private var propertyTool: OverlayMarkupTool?
    private var hoveredPropertyIndex: Int?
    private var currentMarkupColor: NSColor = AnnotationDefaults.color
    private var currentMarkupAnnotationColor: NSColor = AnnotationDefaults.color
    private var currentMarkupTextColor: NSColor = AnnotationDefaults.color
    private var currentMarkupLineWidth: CGFloat = AnnotationDefaults.lineWidth
    private var currentMarkupFontSize: CGFloat = AnnotationDefaults.textFontSize
    private var currentMarkupTextFillColor: NSColor = .clear
    private var isConstrainedDrawing = false
    private var currentMosaicIntensity: CGFloat = 0.5
    private var currentHighlightOpacity: CGFloat = 0.5
    private var currentHighlightShape: OverlayHighlightShape = .rectangle
    private var markupAnnotations: [OverlayMarkupAnnotation] = []
    private var draftMarkupAnnotation: OverlayMarkupAnnotation?
    private var selectedMarkupAnnotationID: UUID?
    private var undoStack: [OverlayMarkupSnapshot] = []
    private var redoStack: [OverlayMarkupSnapshot] = []
    private var activeTextAnnotationID: UUID?
    private var activeTextInitialSnapshot: OverlayMarkupSnapshot?
    private var activeTextUndoStackCount = 0
    private var activeAnnotationHandle: OverlayAnnotationHandle?
    private var resizingAnnotationOrigin: OverlayMarkupAnnotation?
    private var movingAnnotationID: UUID?
    private var movingAnnotationOrigin: OverlayMarkupAnnotation?
    private var hasMarkupAnnotations: Bool {
        !markupAnnotations.isEmpty
    }

    /// Minimum pointer travel, in points, before a press becomes a region drag.
    private let dragThreshold: CGFloat = 4

    init(
        quickMarkupEnabled: Bool,
        screenSnapshot: CapturedScreenshot?,
        onScrollingCapture: @escaping (CGRect, ScrollingCaptureCancellation, @escaping (CapturedScreenshot?) -> Void) -> Void,
        onComplete: @escaping (CaptureSelection) -> Void
    ) {
        self.quickMarkupEnabled = quickMarkupEnabled
        self.screenSnapshot = screenSnapshot
        self.snapshotScreenFrame = Self.snapshotScreenFrame(for: screenSnapshot)
        self.snapshotWindows = screenSnapshot == nil ? nil : WindowEnumerator.onscreenWindows()
        self.onScrollingCapture = onScrollingCapture
        self.onComplete = onComplete
    }

    func start() {
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let view = AreaSelectionView(
                screenFrame: screen.frame,
                screenSnapshot: Self.screenSnapshotImage(screenSnapshot, for: screen.frame),
                session: self
            )
            let window = AreaSelectionWindow(screen: screen, contentView: view)
            windows.append(window)
            views.append(view)
        }

        excludedWindowNumbers = Set(windows.map { CGWindowID($0.windowNumber) })

        for window in windows {
            window.orderFrontRegardless()
        }

        // Make the window under the cursor key (without activating the app) so Escape works.
        if let keyWindow = windows.first(where: { $0.screen?.frame.contains(mouseLocation) ?? false })
            ?? windows.first {
            keyWindow.makeKeyAndOrderFront(nil)
        }

        updateHover(globalPoint: mouseLocation)
        NSCursor.crosshair.set()
    }

    private static func screenSnapshotImage(_ snapshot: CapturedScreenshot?, for screenFrame: CGRect) -> CGImage? {
        guard let snapshot,
              let snapshotScreenFrame = snapshotScreenFrame(for: snapshot) else {
            return nil
        }
        return CaptureSnapshotGeometry.crop(snapshot.image, sourceRect: snapshotScreenFrame, to: screenFrame)
    }

    private static func snapshotScreenFrame(for snapshot: CapturedScreenshot?) -> CGRect? {
        snapshot?.sourceRect
    }

    /// The rectangle currently highlighted in global coordinates, if any.
    var activeGlobalRect: CGRect? {
        if let markupRect {
            return markupRect
        }
        if isDragging {
            return dragRect
        }
        return hoveredWindow?.frame
    }

    /// Whether the active highlight represents a window (versus a region drag).
    var isHighlightingWindow: Bool {
        markupRect == nil && !isDragging && hoveredWindow != nil
    }

    var isInMarkupMode: Bool {
        markupRect != nil
    }

    var markupToolIndex: Int {
        scrollingModeEnabled ? QuickMarkupBarSlot.kinds.firstIndex(of: .scrolling) ?? markupTool.barIndex : markupTool.barIndex
    }

    var activePropertyTool: OverlayMarkupTool? {
        propertyTool
    }

    var currentPropertyLineWidth: CGFloat {
        currentMarkupLineWidth
    }

    var currentPropertyMosaicIntensity: CGFloat {
        currentMosaicIntensity
    }

    var currentPropertyHighlightOpacity: CGFloat {
        currentHighlightOpacity
    }

    var currentPropertyHighlightShape: OverlayHighlightShape {
        currentHighlightShape
    }

    var currentPropertyColor: NSColor {
        currentMarkupColor
    }

    var currentPropertyHoverIndex: Int? {
        hoveredPropertyIndex
    }

    func markupBarRect(in screenFrame: CGRect) -> CGRect? {
        guard let markupBarRect else { return nil }
        let intersection = markupBarRect.intersection(screenFrame)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return nil }
        return CGRect(
            x: intersection.minX - screenFrame.minX,
            y: intersection.minY - screenFrame.minY,
            width: intersection.width,
            height: intersection.height
        )
    }

    func markupPropertyBarRect(in screenFrame: CGRect) -> CGRect? {
        guard !scrollingModeEnabled, propertyTool != nil, let markupBarRect else { return nil }
        let size = propertyBarSize
        let gap: CGFloat = 8
        let globalScreenFrame = NSScreen.screens.first(where: { $0.frame.intersects(markupBarRect) })?.frame ?? screenFrame
        let x = min(max(markupBarRect.midX - size.width / 2, globalScreenFrame.minX + 8), globalScreenFrame.maxX - size.width - 8)
        let above = markupBarRect.maxY + gap
        let below = markupBarRect.minY - size.height - gap
        let y = above + size.height <= globalScreenFrame.maxY - 8 ? above : max(globalScreenFrame.minY + 8, below)
        let global = CGRect(origin: CGPoint(x: x, y: y), size: size)
        let intersection = global.intersection(screenFrame)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return nil }
        return CGRect(x: intersection.minX - screenFrame.minX, y: intersection.minY - screenFrame.minY, width: intersection.width, height: intersection.height)
    }

    func markupAnnotations(in screenFrame: CGRect) -> [OverlayMarkupAnnotation] {
        markupAnnotations.compactMap { $0.inViewCoordinates(screenFrame: screenFrame) }
    }

    func draftMarkupAnnotation(in screenFrame: CGRect) -> OverlayMarkupAnnotation? {
        draftMarkupAnnotation?.inViewCoordinates(screenFrame: screenFrame)
    }

    func selectedMarkupAnnotation(in screenFrame: CGRect) -> OverlayMarkupAnnotation? {
        guard let selectedMarkupAnnotationID,
              let annotation = markupAnnotations.first(where: { $0.id == selectedMarkupAnnotationID }) else {
            return nil
        }
        return annotation.inViewCoordinates(screenFrame: screenFrame)
    }

    func isActiveTextAnnotation(_ id: UUID) -> Bool {
        activeTextAnnotationID == id
    }

    func activeTextAnnotation(in screenFrame: CGRect) -> OverlayMarkupAnnotation? {
        guard let activeTextAnnotationID,
              let annotation = markupAnnotations.first(where: { $0.id == activeTextAnnotationID }) else {
            return nil
        }
        return annotation.inViewCoordinates(screenFrame: screenFrame)
    }

    func handleMouseDown(globalPoint: CGPoint, clickCount: Int = 1, modifiers: NSEvent.ModifierFlags = []) {
        isConstrainedDrawing = modifiers.contains(.shift)
        if let markupRect {
            pointerDownPoint = globalPoint
            if let propertyBarRect = propertyBarRectGlobal(), propertyBarRect.contains(globalPoint) {
                activePropertyDrag = propertyDrag(at: globalPoint, rect: propertyBarRect)
                if selectedMarkupAnnotationID != nil {
                    pushUndoSnapshot()
                }
                handlePropertyBarClick(globalPoint: globalPoint, rect: propertyBarRect)
                return
            }
            if let markupBarRect, markupBarRect.contains(globalPoint) {
                isMovingMarkupBar = true
                markupBarOrigin = markupBarRect
                return
            }
            guard !scrollingModeEnabled else { return }
            commitActiveTextIfNeeded()
            if let hit = hitAnnotationHandle(at: globalPoint) {
                selectMarkupAnnotation(hit.id)
                activeAnnotationHandle = hit.handle
                resizingAnnotationOrigin = hit.annotation
                pushUndoSnapshot()
                return
            }
            if let id = hitAnnotation(at: globalPoint) {
                if let annotation = markupAnnotations.first(where: { $0.id == id }),
                   annotation.tool == .text,
                   clickCount >= 2 {
                    selectMarkupAnnotation(id)
                    beginTextEditing(annotationID: id, recordUndo: true)
                    refreshOverlays()
                    return
                }
                selectMarkupAnnotation(id)
                movingAnnotationID = id
                movingAnnotationOrigin = markupAnnotations.first(where: { $0.id == id })
                pushUndoSnapshot()
                refreshOverlays()
                return
            }
            if clickCount >= 2, markupRect.contains(globalPoint) {
                completeMarkup(.copy)
                return
            }
            if !hasMarkupAnnotations, let handle = hitMarkupHandle(at: globalPoint, in: markupRect) {
                selectedMarkupAnnotationID = nil
                activeMarkupHandle = handle
                resizeMarkupOrigin = markupRect
                return
            }
            if markupRect.contains(globalPoint), selectedMarkupAnnotationID != nil {
                selectedMarkupAnnotationID = nil
                refreshOverlays()
                return
            }
            if markupTool != .select, markupRect.contains(globalPoint) {
                dragStart = globalPoint
                dragCurrent = globalPoint
                draftMarkupAnnotation = nil
                return
            }
            if !hasMarkupAnnotations, markupRect.contains(globalPoint) {
                selectedMarkupAnnotationID = nil
                isMovingMarkupRect = true
                movingMarkupOrigin = markupRect
                return
            }
        }

        dragStart = globalPoint
        dragCurrent = globalPoint
        isDragging = false
        refreshOverlays()
    }

    func handleMouseDragged(globalPoint: CGPoint, modifiers: NSEvent.ModifierFlags = []) {
        isConstrainedDrawing = modifiers.contains(.shift)
        if let activePropertyDrag,
           let propertyBarRect = propertyBarRectGlobal() {
            updatePropertyDrag(activePropertyDrag, globalPoint: globalPoint, rect: propertyBarRect)
            return
        }

        if isMovingMarkupBar, let origin = markupBarOrigin, let start = pointerDownPoint {
            guard hypot(globalPoint.x - start.x, globalPoint.y - start.y) > dragThreshold else { return }
            markupBarRect = clampedBarRect(origin.offsetBy(dx: globalPoint.x - start.x, dy: globalPoint.y - start.y))
            refreshOverlays()
            return
        }

        if let handle = activeMarkupHandle, let origin = resizeMarkupOrigin {
            markupRect = resizedMarkupRect(origin, handle: handle, to: globalPoint)
            refreshOverlays()
            return
        }

        if let activeAnnotationHandle, let selectedMarkupAnnotationID {
            markupAnnotations = markupAnnotations.map { annotation in
                annotation.id == selectedMarkupAnnotationID
                    ? (resizingAnnotationOrigin ?? annotation).updating(handle: activeAnnotationHandle, to: globalPoint, within: markupRect ?? annotation.rect, constrained: isConstrainedDrawing)
                    : annotation
            }
            refreshOverlays()
            return
        }

        if let movingAnnotationID, let movingAnnotationOrigin, let start = pointerDownPoint {
            let dx = globalPoint.x - start.x
            let dy = globalPoint.y - start.y
            markupAnnotations = markupAnnotations.map { annotation in
                annotation.id == movingAnnotationID
                    ? (movingAnnotationOrigin.tool.sharesEditorGeometry
                        ? movingAnnotationOrigin.offsetBy(dx: dx, dy: dy)
                        : movingAnnotationOrigin.offsetBy(dx: dx, dy: dy).clamped(to: markupRect ?? movingAnnotationOrigin.rect))
                    : annotation
            }
            refreshOverlays()
            return
        }

        if isMovingMarkupRect, let origin = movingMarkupOrigin, let start = pointerDownPoint {
            guard hypot(globalPoint.x - start.x, globalPoint.y - start.y) > dragThreshold else { return }
            markupRect = clampedRect(origin.offsetBy(dx: globalPoint.x - start.x, dy: globalPoint.y - start.y))
            if let markupRect {
                markupBarRect = markupBarRect ?? defaultBarRect(near: markupRect)
            }
            refreshOverlays()
            return
        }

        if markupRect != nil, markupTool != .select, let start = dragStart {
            dragCurrent = globalPoint
            draftMarkupAnnotation = makeAnnotation(tool: markupTool, start: start, end: globalPoint)
            refreshOverlays()
            return
        }

        dragCurrent = globalPoint
        if let start = dragStart,
           hypot(globalPoint.x - start.x, globalPoint.y - start.y) > dragThreshold {
            isDragging = true
        }
        refreshOverlays()
    }

    func handleModifiersChanged(_ modifiers: NSEvent.ModifierFlags) {
        isConstrainedDrawing = modifiers.contains(.shift)
        if activeAnnotationHandle != nil {
            handleMouseDragged(globalPoint: NSEvent.mouseLocation, modifiers: modifiers)
            return
        }
        if let start = dragStart, let end = dragCurrent, draftMarkupAnnotation != nil {
            draftMarkupAnnotation = makeAnnotation(tool: markupTool, start: start, end: end)
            refreshOverlays()
        }
    }

    func handleMouseUp(globalPoint: CGPoint, modifiers: NSEvent.ModifierFlags = []) {
        isConstrainedDrawing = modifiers.contains(.shift)
        if activePropertyDrag != nil {
            activePropertyDrag = nil
            pointerDownPoint = nil
            return
        }

        if isMovingMarkupBar {
            if let start = pointerDownPoint,
               hypot(globalPoint.x - start.x, globalPoint.y - start.y) <= dragThreshold,
               let markupBarRect,
               markupBarRect.contains(globalPoint) {
                handleMarkupBarClick(globalPoint: globalPoint)
            }
            isMovingMarkupBar = false
            markupBarOrigin = nil
            pointerDownPoint = nil
            return
        }

        if activeMarkupHandle != nil {
            activeMarkupHandle = nil
            resizeMarkupOrigin = nil
            pointerDownPoint = nil
            return
        }

        if activeAnnotationHandle != nil {
            activeAnnotationHandle = nil
            resizingAnnotationOrigin = nil
            pointerDownPoint = nil
            return
        }

        if movingAnnotationID != nil {
            movingAnnotationID = nil
            movingAnnotationOrigin = nil
            pointerDownPoint = nil
            return
        }

        if isMovingMarkupRect {
            isMovingMarkupBar = false
            isMovingMarkupRect = false
            markupBarOrigin = nil
            movingMarkupOrigin = nil
            activeMarkupHandle = nil
            resizeMarkupOrigin = nil
            pointerDownPoint = nil
            return
        }

        if let markupRect {
            if markupTool == .text, draftMarkupAnnotation == nil, let start = dragStart {
                draftMarkupAnnotation = makeAnnotation(tool: .text, start: start, end: globalPoint)
            }
            if markupTool != .select, let draftMarkupAnnotation {
                let rect = draftMarkupAnnotation.rect
                let isValid = (markupTool == .rectangle || markupTool == .oval) ? (rect.width > 3 && rect.height > 3) : (rect.width > 3 || rect.height > 3 || markupTool == .text)
                if isValid {
                    let annotation = draftMarkupAnnotation.tool.sharesEditorGeometry ? draftMarkupAnnotation : draftMarkupAnnotation.clamped(to: markupRect)
                    pushUndoSnapshot()
                    markupAnnotations.append(annotation)
                    selectedMarkupAnnotationID = annotation.id
                    if annotation.tool == .text {
                        beginTextEditing(annotationID: annotation.id, recordUndo: false)
                    }
                }
                self.draftMarkupAnnotation = nil
                dragStart = nil
                dragCurrent = nil
                refreshOverlays()
                return
            }
            if let markupBarRect, markupBarRect.contains(globalPoint) {
                handleMarkupBarClick(globalPoint: globalPoint)
            } else if !markupRect.contains(globalPoint) {
                // Keep the selection alive; clicks outside should not restart capture.
                refreshOverlays()
            }
            return
        }

        dragCurrent = globalPoint

        if isDragging, let rect = dragRect, rect.width > 2, rect.height > 2 {
            if quickMarkupEnabled {
                enterMarkupMode(rect: rect.integral)
                return
            }
            finish(.region(rect.integral))
            return
        }

        // A click (no meaningful drag): capture the window under the cursor.
        if let window = window(at: globalPoint) {
            if quickMarkupEnabled {
                enterMarkupMode(rect: window.frame.integral)
                return
            }
            finish(.window(window))
            return
        }

        finish(.cancelled)
    }

    func handleRightMouseDown(globalPoint: CGPoint) {
        guard let markupRect,
              markupRect.contains(globalPoint),
              markupBarRect?.contains(globalPoint) != true,
              propertyBarRectGlobal()?.contains(globalPoint) != true else {
            return
        }
        completeMarkup(.save)
    }

    func handleMouseMoved(globalPoint: CGPoint) {
        refreshCursor(globalPoint: globalPoint)
    }

    func refreshCursor(globalPoint: CGPoint) {
        if markupRect != nil {
            updateBarHover(at: globalPoint)
            updatePropertyHover(at: globalPoint)
            cursor(at: globalPoint).set()
            return
        }
        guard !isDragging else { return }
        updateHover(globalPoint: globalPoint)
    }

    func cancel() {
        if isScrollingCaptureInProgress {
            scrollingCancellation?.onPreview = nil
            scrollingCancellation?.onChange = nil
            scrollingCancellation?.onMessage = nil
            scrollingCancellation?.cancel()
            isScrollingCaptureInProgress = false
            scrollingCancellation = nil
            setOverlayInteractionEnabled(true)
        }
        finish(.cancelled)
    }

    func confirmMarkupToClipboard() {
        completeMarkup(.copy)
    }

    private func completeMarkup(_ action: OverlayMarkupCompletionAction) {
        guard let markupRect else { return }
        if scrollingModeEnabled {
            completeScrolling(action == .copy ? .copy : .save)
            return
        }
        commitActiveTextIfNeeded()
        let rect = markupRect.integral
        switch action {
        case .copy:
            finish(.copyRegion(rect, markupAnnotations, preCapturedRegion(for: rect)))
        case .save:
            finish(.saveRegion(rect, markupAnnotations, preCapturedRegion(for: rect)))
        }
    }

    private func updateHover(globalPoint: CGPoint) {
        let window = window(at: globalPoint)
        guard window != hoveredWindow else { return }
        hoveredWindow = window
        refreshOverlays()
    }

    private func window(at point: CGPoint) -> WindowDescriptor? {
        if let snapshotWindows { return snapshotWindows.first { $0.frame.contains(point) } }
        return WindowEnumerator.window(at: point, excludedWindowNumbers: excludedWindowNumbers)
    }

    var showsFrozenDesktop: Bool { !scrollingModeEnabled }
    var showsScrollingOptions: Bool { scrollingModeEnabled }
    var isAutomaticScrolling: Bool { scrollingCancellation?.isAutomatic == true }

    private var dragRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragStart.x - dragCurrent.x),
            height: abs(dragStart.y - dragCurrent.y)
        )
    }

    private func refreshOverlays() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        updateScrollingToolbarWindow()
        for view in views {
            view.needsDisplay = true
            view.displayIfNeeded()
            view.window?.invalidateCursorRects(for: view)
        }
    }

    private func enterMarkupMode(rect: CGRect) {
        hoveredWindow = nil
        isDragging = false
        dragStart = nil
        dragCurrent = nil
        markupRect = clampedRect(rect)
        if let markupRect {
            markupBarRect = defaultBarRect(near: markupRect)
        }
        refreshOverlays()
    }

    private func handleMarkupBarClick(globalPoint: CGPoint) {
        defer {
            cursor(at: globalPoint).set()
        }
        guard let markupBarRect else { return }
        guard let slot = QuickMarkupBarSlot.slot(at: globalPoint, in: markupBarRect) else {
            refreshOverlays()
            return
        }
        if scrollingModeEnabled {
            switch slot.kind {
            case .done: completeScrolling(.copy)
            case .save: completeScrolling(.save)
            case .pin: completeScrolling(.pin)
            case .editor: completeScrolling(.editor)
            case .cancel: cancel()
            default: refreshOverlays()
            }
            return
        }
        switch slot.kind {
        case .dragHandle, .separator:
            refreshOverlays()
        case .rectangle:
            markupTool = .rectangle
            setPropertyTool(.rectangle)
            refreshOverlays()
        case .oval:
            markupTool = .oval
            setPropertyTool(.oval)
            refreshOverlays()
        case .line:
            markupTool = .line
            setPropertyTool(.line)
            refreshOverlays()
        case .arrow:
            markupTool = .arrow
            setPropertyTool(.arrow)
            refreshOverlays()
        case .text:
            markupTool = .text
            setPropertyTool(.text)
            refreshOverlays()
        case .mosaic:
            markupTool = .blur
            setPropertyTool(.blur)
            refreshOverlays()
        case .highlight:
            markupTool = .highlighter
            setPropertyTool(.highlighter)
            refreshOverlays()
        case .scrolling:
            guard !isScrollingCaptureInProgress else {
                showNotice("Scrolling capture is already running.")
                refreshOverlays()
                return
            }
            if let markupRect {
                commitActiveTextIfNeeded()
                beginScrollingCapture(rect: markupRect.integral)
            }
        case .pin:
            if let markupRect {
                commitActiveTextIfNeeded()
                let rect = markupRect.integral
                finish(.pinRegion(rect, markupAnnotations, preCapturedRegion(for: rect)))
            }
        case .editor:
            if let markupRect {
                commitActiveTextIfNeeded()
                let rect = markupRect.integral
                finish(.editRegion(rect, preCapturedRegion(for: rect)))
            }
        case .save:
            completeMarkup(.save)
        case .cancel:
            cancel()
        case .done:
            completeMarkup(.copy)
        }
    }

    private func setPropertyTool(_ tool: OverlayMarkupTool) {
        commitActiveTextIfNeeded()
        if let id = selectedMarkupAnnotationID, markupAnnotations.first(where: { $0.id == id })?.tool != tool {
            selectedMarkupAnnotationID = nil
        }
        currentMarkupColor = tool == .text ? currentMarkupTextColor : currentMarkupAnnotationColor
        propertyTool = tool
        if tool.usesStrokeWidthDots {
            currentMarkupLineWidth = nearestLineWidthDotValue(to: currentMarkupLineWidth)
            updateSelectedAnnotationStyle()
        }
    }

    private func nearestLineWidthDotValue(to value: CGFloat) -> CGFloat {
        AnnotationDefaults.quickMarkupLineWidths.min { abs($0 - value) < abs($1 - value) } ?? AnnotationDefaults.lineWidth
    }

    private var propertyBarSize: CGSize {
        if propertyTool == .text { return CGSize(width: 330, height: 76) }
        if propertyTool?.usesStrokeWidthDots == true {
            return QuickMarkupPropertyBarLayout(sizeCount: AnnotationDefaults.quickMarkupLineWidths.count).size
        }
        return CGSize(width: 330, height: 42)
    }

    var currentPropertyTextFilled: Bool { currentMarkupTextFillColor.alphaComponent > 0 }
    var currentPropertyFontSize: CGFloat { currentMarkupFontSize }

    private func propertyBarRectGlobal() -> CGRect? {
        guard !scrollingModeEnabled, propertyTool != nil, let markupBarRect else { return nil }
        let size = propertyBarSize
        let gap: CGFloat = 8
        let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(markupBarRect) })?.frame
            ?? NSScreen.main?.frame
            ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let x = min(max(markupBarRect.midX - size.width / 2, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        let above = markupBarRect.maxY + gap
        let below = markupBarRect.minY - size.height - gap
        let y = above + size.height <= screenFrame.maxY - 8 ? above : max(screenFrame.minY + 8, below)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func handlePropertyBarClick(globalPoint: CGPoint, rect: CGRect) {
        defer {
            cursor(at: globalPoint).set()
        }
        if propertyTool == .text, globalPoint.y < rect.maxY - 42 {
            guard let filled = QuickMarkupPropertyBarLayout.textStyle(at: globalPoint, in: rect) else { return }
            let style = AnnotationTextRenderer.style(filled: filled, color: currentMarkupColor, fillColor: currentMarkupTextFillColor)
            currentMarkupColor = style.color
            currentMarkupTextColor = style.color
            currentMarkupTextFillColor = style.fill
            updateSelectedAnnotationStyle()
            refreshOverlays()
            return
        }
        let rect = propertyTool == .text ? QuickMarkupPropertyBarLayout.textControls(in: rect) : rect
        let relativeX = globalPoint.x - rect.minX
        if propertyTool == .blur {
            currentMosaicIntensity = min(max((relativeX - 142) / 112, 0), 1)
            updateSelectedAnnotationStyle()
            refreshOverlays()
            return
        }
        if propertyTool == .highlighter {
            if relativeX < 120 {
                let shapes: [OverlayHighlightShape] = [.rectangle, .oval, .roundedRectangle]
                let index = min(max(Int(relativeX / 36), 0), shapes.count - 1)
                currentHighlightShape = shapes[index]
            } else {
                currentHighlightOpacity = min(max((relativeX - 218) / 74, 0.2), 0.85)
            }
            updateSelectedAnnotationStyle()
            refreshOverlays()
            return
        }
        let swatches: [NSColor] = [AnnotationDefaults.color, .systemYellow, .systemGreen, .systemBlue, .black, .systemGray, .white]
        if relativeX < 190 {
            let index = min(max(Int(relativeX / 26), 0), swatches.count - 1)
            currentMarkupColor = swatches[index]
            if propertyTool == .text { currentMarkupTextColor = currentMarkupColor }
            else { currentMarkupAnnotationColor = currentMarkupColor }
            updateSelectedAnnotationStyle()
        } else {
            let values: [CGFloat]
            if propertyTool == .text {
                values = [12, 16, 20, 28]
            } else if propertyTool?.usesStrokeWidthDots == true {
                values = AnnotationDefaults.quickMarkupLineWidths
            } else {
                values = AnnotationDefaults.quickMarkupLineWidths
            }
            guard let index = QuickMarkupPropertyBarLayout(sizeCount: values.count).sizeIndex(at: globalPoint, in: rect) else { return }
            if propertyTool == .text {
                currentMarkupFontSize = values[index]
            } else {
                currentMarkupLineWidth = values[index]
            }
            updateSelectedAnnotationStyle()
        }
        refreshOverlays()
    }

    private func propertyDrag(at point: CGPoint, rect: CGRect) -> OverlayPropertyDrag? {
        let relativeX = point.x - rect.minX
        switch propertyTool {
        case .blur:
            return relativeX >= 120 ? .mosaicIntensity : nil
        case .highlighter:
            return relativeX >= 190 ? .highlightOpacity : nil
        default:
            return nil
        }
    }

    private func updatePropertyDrag(_ drag: OverlayPropertyDrag, globalPoint: CGPoint, rect: CGRect) {
        let relativeX = globalPoint.x - rect.minX
        switch drag {
        case .mosaicIntensity:
            currentMosaicIntensity = min(max((relativeX - 142) / 112, 0), 1)
        case .highlightOpacity:
            currentHighlightOpacity = min(max((relativeX - 218) / 74, 0.2), 0.85)
        }
        updateSelectedAnnotationStyle()
        refreshOverlays()
        cursor(at: globalPoint).set()
    }

    private func updatePropertyHover(at point: CGPoint) {
        let oldValue = hoveredPropertyIndex
        defer {
            if oldValue != hoveredPropertyIndex {
                refreshOverlays()
            }
        }

        guard propertyTool?.usesStrokeWidthDots == true,
              let rect = propertyBarRectGlobal(),
              rect.contains(point) else {
            hoveredPropertyIndex = nil
            return
        }

        hoveredPropertyIndex = QuickMarkupPropertyBarLayout(sizeCount: AnnotationDefaults.quickMarkupLineWidths.count)
            .sizeIndex(at: point, in: rect)
    }

    private func updateBarHover(at point: CGPoint) {
        let oldValue = hoveredBarIndex
        let oldTooltipCandidate = hoveredBarTooltipCandidateIndex
        defer {
            if oldTooltipCandidate != hoveredBarTooltipCandidateIndex {
                scheduleBarTooltip(for: hoveredBarTooltipCandidateIndex)
            }
            if oldValue != hoveredBarIndex || oldTooltipCandidate != hoveredBarTooltipCandidateIndex {
                refreshOverlays()
            }
        }

        guard let markupBarRect, markupBarRect.contains(point) else {
            hoveredBarIndex = nil
            hoveredBarTooltipCandidateIndex = nil
            return
        }
        let slot = QuickMarkupBarSlot.slot(at: point, in: markupBarRect)
        hoveredBarTooltipCandidateIndex = slot?.kind.showsTooltip == true ? slot?.index : nil
        hoveredBarIndex = slot?.kind.drawsHover == true ? slot?.index : nil
    }

    private func scheduleBarTooltip(for index: Int?) {
        tooltipWorkItem?.cancel()
        hoveredTooltipBarIndex = nil
        guard let index else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.hoveredBarTooltipCandidateIndex == index else { return }
            self.hoveredTooltipBarIndex = index
            self.refreshOverlays()
            self.cursor(at: NSEvent.mouseLocation).set()
        }
        tooltipWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
    }

    private func showNotice(_ message: String) {
        noticeWorkItem?.cancel()
        noticeMessage = message
        if scrollingModeEnabled { scrollingHUD?.showNotice(message) }

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.noticeMessage == message else { return }
            self.noticeMessage = nil
            self.refreshOverlays()
        }
        noticeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: item)
    }

    private func beginScrollingCapture(rect: CGRect) {
        isScrollingCaptureInProgress = true
        scrollingModeEnabled = true
        scrollingResult = nil
        scrollingDestination = nil
        let cancellation = ScrollingCaptureCancellation()
        scrollingCancellation = cancellation
        cancellation.onChange = { [weak self] in self?.refreshOverlays() }
        cancellation.onMessage = { [weak self] message in
            self?.showNotice(message)
            self?.refreshOverlays()
        }
        setOverlayInteractionEnabled(false)
        propertyTool = nil
        selectedMarkupAnnotationID = nil
        scrollingHUD = ScrollingCaptureHUD(selection: rect) { [weak self] in
            guard let control = self?.scrollingCancellation, !control.isFinished else { return }
            control.setAutomatic(!control.isAutomatic)
        }
        cancellation.onPreview = { [weak self] image in self?.scrollingHUD?.updatePreview(image) }
        scrollingHUD?.showNotice(ScrollingCaptureHUD.introduction)
        refreshOverlays()

        onScrollingCapture(rect, cancellation) { [weak self] capture in
            Task { @MainActor in
                guard let self, self.isScrollingCaptureInProgress else { return }
                self.isScrollingCaptureInProgress = false
                cancellation.onChange = nil
                cancellation.onMessage = nil
                cancellation.onPreview = nil
                self.scrollingCancellation = nil
                if let capture {
                    self.scrollingResult = capture
                    if let destination = self.scrollingDestination { self.completeScrolling(destination) }
                    else { self.showNotice("Capture ready. Use the toolbar to copy, save or edit."); self.refreshOverlays() }
                } else {
                    self.scrollingHUD?.close()
                    self.scrollingHUD = nil
                    self.scrollingModeEnabled = false
                    self.setOverlayInteractionEnabled(true)
                    self.showNotice(cancellation.isCancelled ? "Scrolling capture cancelled." : "Scrolling capture failed. Please try again.")
                    self.refreshOverlays()
                }
            }
        }
    }

    private func completeScrolling(_ destination: ScrollingDestination) {
        guard let rect = markupRect else { return }
        guard let capture = scrollingResult else {
            // Keep the first requested action while the final frame is being captured.
            guard scrollingDestination == nil else { return }
            scrollingDestination = destination
            scrollingCancellation?.finish()
            return
        }
        switch destination {
        case .copy: finish(.copyRegion(rect, [], capture))
        case .save: finish(.saveRegion(rect, [], capture))
        case .pin: finish(.pinRegion(rect, [], capture))
        case .editor: finish(.editRegion(rect, capture))
        }
    }

    private func updateScrollingToolbarWindow() {
        scrollingHUD?.updateAutomatic(isAutomaticScrolling, enabled: isScrollingCaptureInProgress && scrollingDestination == nil)
        guard scrollingModeEnabled, !didComplete, let bar = markupBarRect else {
            scrollingToolbarWindow?.orderOut(nil)
            scrollingToolbarWindow = nil
            scrollingToolbarView = nil
            return
        }
        let frame = bar.union(propertyBarRectGlobal() ?? bar).insetBy(dx: -2, dy: -2)
        if let window = scrollingToolbarWindow, let view = scrollingToolbarView {
            window.setFrame(frame, display: false)
            view.updateScreenFrame(frame)
        } else {
            let view = AreaSelectionView(screenFrame: frame, screenSnapshot: nil, session: self, toolbarOnly: true)
            let window = AreaSelectionWindow(frame: frame, contentView: view)
            scrollingToolbarWindow = window
            scrollingToolbarView = view
            excludedWindowNumbers.insert(CGWindowID(window.windowNumber))
            window.orderFrontRegardless()
            window.makeKey()
        }
        scrollingToolbarView?.needsDisplay = true
        scrollingToolbarView?.displayIfNeeded()
    }

    private func setOverlayInteractionEnabled(_ isEnabled: Bool) {
        for window in windows {
            window.ignoresMouseEvents = !isEnabled
        }
    }

    private func selectMarkupAnnotation(_ id: UUID) {
        selectedMarkupAnnotationID = id
        guard let annotation = markupAnnotations.first(where: { $0.id == id }) else { return }
        propertyTool = annotation.tool
        currentMarkupColor = annotation.color
        currentMarkupLineWidth = annotation.lineWidth
        if annotation.tool == .text {
            currentMarkupTextColor = annotation.color
            currentMarkupFontSize = annotation.fontSize
            currentMarkupTextFillColor = annotation.textFillColor
        } else {
            currentMarkupAnnotationColor = annotation.color
        }
    }

    private func updateSelectedAnnotationStyle() {
        guard let selectedMarkupAnnotationID else { return }
        markupAnnotations = markupAnnotations.map { annotation in
            guard annotation.id == selectedMarkupAnnotationID else { return annotation }
            if annotation.tool == .text {
                return annotation.withTextAppearance(color: currentMarkupColor, fontSize: currentMarkupFontSize, fillColor: currentMarkupTextFillColor)
            }
            return annotation.withStyle(color: currentMarkupColor, lineWidth: currentMarkupLineWidth, fontSize: currentMarkupFontSize)
        }
        if let annotation = markupAnnotations.first(where: { $0.id == selectedMarkupAnnotationID }), annotation.tool == .text {
            autosizeTextAnnotation(id: selectedMarkupAnnotationID)
            activeTextEditingView?.refreshActiveTextStyle()
        }
    }

    private func currentSnapshot() -> OverlayMarkupSnapshot {
        OverlayMarkupSnapshot(annotations: markupAnnotations, selectedAnnotationID: selectedMarkupAnnotationID)
    }

    private func pushUndoSnapshot() {
        undoStack.append(currentSnapshot())
        redoStack.removeAll()
    }

    func undoMarkup() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        restore(snapshot)
    }

    func redoMarkup() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        restore(snapshot)
    }

    private func restore(_ snapshot: OverlayMarkupSnapshot) {
        markupAnnotations = snapshot.annotations
        selectedMarkupAnnotationID = snapshot.selectedAnnotationID
        activeTextAnnotationID = nil
        activeTextInitialSnapshot = nil
        activeTextEditingView?.discardTextEditing()
        activeTextEditingView = nil
        draftMarkupAnnotation = nil
        dragStart = nil
        dragCurrent = nil
        activeAnnotationHandle = nil
        resizingAnnotationOrigin = nil
        movingAnnotationID = nil
        movingAnnotationOrigin = nil
        refreshOverlays()
    }

    private func beginTextEditing(annotationID: UUID, recordUndo: Bool) {
        guard let annotation = markupAnnotations.first(where: { $0.id == annotationID }),
              annotation.tool == .text,
              let view = views.first(where: { $0.screenFrameContains(annotation.rect) }) else {
            return
        }
        activeTextEditingView?.endTextEditing(commit: true)
        activeTextInitialSnapshot = recordUndo ? currentSnapshot() : undoStack.last
        activeTextUndoStackCount = recordUndo ? undoStack.count : max(0, undoStack.count - 1)
        if recordUndo { pushUndoSnapshot() }
        activeTextAnnotationID = annotationID
        activeTextEditingView = view
        view.beginTextEditing()
    }

    func updateActiveText(_ text: String) {
        guard let activeTextAnnotationID else { return }
        markupAnnotations = markupAnnotations.map { annotation in
            annotation.id == activeTextAnnotationID ? annotation.withText(text) : annotation
        }
        autosizeTextAnnotation(id: activeTextAnnotationID)
        refreshOverlays()
    }

    func commitActiveTextEditing() {
        guard let activeTextAnnotationID else { return }
        if let annotation = markupAnnotations.first(where: { $0.id == activeTextAnnotationID }),
           annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            markupAnnotations.removeAll { $0.id == activeTextAnnotationID }
            selectedMarkupAnnotationID = nil
        } else {
            selectedMarkupAnnotationID = activeTextAnnotationID
        }
        self.activeTextAnnotationID = nil
        activeTextInitialSnapshot = nil
        activeTextEditingView = nil
        refreshOverlays()
    }

    func cancelActiveTextEditing() {
        guard let snapshot = activeTextInitialSnapshot else { return }
        undoStack = Array(undoStack.prefix(activeTextUndoStackCount))
        activeTextInitialSnapshot = nil
        restore(snapshot)
    }

    private func commitActiveTextIfNeeded() {
        activeTextEditingView?.endTextEditing(commit: true)
    }

    private func autosizeTextAnnotation(id: UUID) {
        guard let index = markupAnnotations.firstIndex(where: { $0.id == id }) else { return }
        let annotation = markupAnnotations[index]
        let bounds = markupRect ?? annotation.rect
        let rect = AnnotationTextRenderer.autosizedRect(annotation.rect, text: annotation.text, fontSize: annotation.fontSize, within: bounds)
        markupAnnotations[index] = annotation.updatingTextRect(rect)
    }

    private func textBoxSize(for text: String, fontSize: CGFloat) -> CGSize {
        AnnotationTextRenderer.boxSize(for: text, fontSize: fontSize)
    }

    private func makeAnnotation(tool: OverlayMarkupTool, start: CGPoint, end: CGPoint) -> OverlayMarkupAnnotation {
        let origin: CGPoint
        let annotationEnd: CGPoint
        if tool == .text {
            let rect = AnnotationTextRenderer.fittedRect(from: start, to: end, text: "", fontSize: currentMarkupFontSize, within: markupRect ?? CGRect(origin: start, size: CGSize(width: 120, height: 60)))
            origin = rect.origin
            annotationEnd = CGPoint(x: rect.maxX, y: rect.maxY)
        } else if tool == .rectangle || tool == .oval {
            let rect = AnnotationShapeGeometry.normalized(from: start, to: clampedAnnotationPoint(end), constrained: isConstrainedDrawing)
            origin = rect.origin
            annotationEnd = CGPoint(x: rect.maxX, y: rect.maxY)
        } else {
            origin = start
            annotationEnd = end
        }
        return OverlayMarkupAnnotation(
            tool: tool,
            start: origin,
            end: annotationEnd,
            color: currentMarkupColor,
            lineWidth: currentMarkupLineWidth,
            fontSize: currentMarkupFontSize,
            textFillColor: tool == .text ? currentMarkupTextFillColor : .clear,
            mosaicIntensity: currentMosaicIntensity,
            highlightOpacity: currentHighlightOpacity,
            highlightShape: currentHighlightShape
        )
    }

    private func clampedRect(_ rect: CGRect) -> CGRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main else {
            return rect
        }
        let frame = screen.frame
        let width = min(rect.width, frame.width)
        let height = min(rect.height, frame.height)
        return CGRect(
            x: min(max(rect.minX, frame.minX), frame.maxX - width),
            y: min(max(rect.minY, frame.minY), frame.maxY - height),
            width: width,
            height: height
        )
    }

    private func hitMarkupHandle(at point: CGPoint, in rect: CGRect) -> OverlaySelectionHandle? {
        let radius: CGFloat = 9
        for handle in OverlaySelectionHandle.allCases {
            let anchor = handle.point(in: rect)
            if abs(point.x - anchor.x) <= radius && abs(point.y - anchor.y) <= radius {
                return handle
            }
        }
        return nil
    }

    private func resizedMarkupRect(_ origin: CGRect, handle: OverlaySelectionHandle, to point: CGPoint) -> CGRect {
        let minSize: CGFloat = 12
        var minX = origin.minX
        var maxX = origin.maxX
        var minY = origin.minY
        var maxY = origin.maxY
        if handle.movesLeft { minX = min(point.x, maxX - minSize) }
        if handle.movesRight { maxX = max(point.x, minX + minSize) }
        if handle.movesBottom { minY = min(point.y, maxY - minSize) }
        if handle.movesTop { maxY = max(point.y, minY + minSize) }
        return clampedRect(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    private func hitAnnotationHandle(at point: CGPoint) -> (id: UUID, handle: OverlayAnnotationHandle, annotation: OverlayMarkupAnnotation)? {
        let radius: CGFloat = 10
        for annotation in markupAnnotations.reversed() {
            if annotation.tool == .arrow {
                if let handle = annotation.arrowGeometry.hitHandle(at: point) {
                    return (annotation.id, OverlayAnnotationHandle(arrowHandle: handle), annotation)
                }
                continue
            }
            guard annotation.id == selectedMarkupAnnotationID else { continue }
            if annotation.tool == .line {
                if let handle = annotation.arrowGeometry.hitHandle(at: point) {
                    return (annotation.id, OverlayAnnotationHandle(arrowHandle: handle), annotation)
                }
                continue
            }
            if annotation.tool == .rectangle || annotation.tool == .oval {
                if let handle = AnnotationShapeGeometry.hitHandle(at: point, rect: annotation.rect, flipped: false, kind: annotation.tool == .oval ? .oval : .rectangle) {
                    return (annotation.id, OverlayAnnotationHandle(shapeHandle: handle), annotation)
                }
                continue
            }
            for (handle, anchor) in annotation.handlePoints {
                if abs(point.x - anchor.x) <= radius && abs(point.y - anchor.y) <= radius {
                    return (annotation.id, handle, annotation)
                }
            }
        }
        return nil
    }

    private func hitAnnotation(at point: CGPoint) -> UUID? {
        for annotation in markupAnnotations.reversed() {
            switch annotation.tool {
            case .arrow:
                if annotation.arrowGeometry.hit(at: point, width: annotation.lineWidth, curved: false) { return annotation.id }
            case .line:
                if annotation.arrowGeometry.hit(at: point, width: annotation.lineWidth, curved: false, includesArrowhead: false) { return annotation.id }
            case .rectangle, .oval:
                if AnnotationShapeGeometry.hitStroke(at: point, kind: annotation.tool == .rectangle ? .rectangle : .oval, rect: annotation.rect, width: annotation.lineWidth) { return annotation.id }
            default:
                if annotation.rect.insetBy(dx: -6, dy: -6).contains(point) {
                    return annotation.id
                }
            }
        }
        return nil
    }

    private func distanceFromPoint(_ point: CGPoint, toLineStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projected = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projected.x, point.y - projected.y)
    }

    private func clampedAnnotationPoint(_ point: CGPoint) -> CGPoint {
        guard let markupRect else { return point }
        return CGPoint(
            x: min(max(point.x, markupRect.minX), markupRect.maxX),
            y: min(max(point.y, markupRect.minY), markupRect.maxY)
        )
    }

    func cursor(at point: CGPoint) -> NSCursor {
        if let markupBarRect, markupBarRect.contains(point) {
            guard let slot = QuickMarkupBarSlot.slot(at: point, in: markupBarRect) else {
                return .crosshair
            }
            if slot.kind == .dragHandle {
                return .editorMove
            }
            return slot.kind.isClickable ? .pointingHand : .crosshair
        }

        if let propertyBarRect = propertyBarRectGlobal(), propertyBarRect.contains(point) {
            return .pointingHand
        }

        if let hit = hitAnnotationHandle(at: point) {
            return hit.handle.cursor
        }

        if hitAnnotation(at: point) != nil {
            return .editorMove
        }

        if let markupRect,
           !hasMarkupAnnotations,
           let handle = hitMarkupHandle(at: point, in: markupRect) {
            return handle.cursor
        }

        return .crosshair
    }

    var currentBarHoverIndex: Int? {
        hoveredBarIndex
    }

    var currentBarTooltipIndex: Int? {
        hoveredTooltipBarIndex
    }

    var currentNoticeMessage: String? {
        noticeMessage
    }

    private func defaultBarRect(near rect: CGRect) -> CGRect {
        let size = CGSize(width: 690, height: 48)
        let margin: CGFloat = 12
        let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(rect) })?.frame
            ?? NSScreen.main?.frame
            ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let x = min(max(rect.midX - size.width / 2, screenFrame.minX + margin), screenFrame.maxX - size.width - margin)
        let belowY = rect.minY - size.height - margin
        let aboveY = rect.maxY + margin
        let y: CGFloat
        if belowY >= screenFrame.minY + margin {
            y = belowY
        } else if aboveY + size.height <= screenFrame.maxY - margin {
            y = aboveY
        } else {
            y = min(max(rect.minY + margin, screenFrame.minY + margin), screenFrame.maxY - size.height - margin)
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func clampedBarRect(_ rect: CGRect) -> CGRect {
        let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(rect) })?.frame
            ?? NSScreen.main?.frame
            ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        return CGRect(
            x: min(max(rect.minX, screenFrame.minX + 6), screenFrame.maxX - rect.width - 6),
            y: min(max(rect.minY, screenFrame.minY + 6), screenFrame.maxY - rect.height - 6),
            width: rect.width,
            height: rect.height
        )
    }

    private func finish(_ selection: CaptureSelection) {
        guard !didComplete else { return }
        didComplete = true

        scrollingHUD?.close()
        scrollingHUD = nil
        scrollingCancellation?.onPreview = nil
        scrollingToolbarWindow?.orderOut(nil)
        scrollingToolbarWindow = nil
        scrollingToolbarView = nil
        let overlayNumbers = excludedWindowNumbers
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        views.removeAll()

        // A region capture screenshots the whole display area (no content filter), so it will
        // include our dim mask / highlight border unless the overlay is truly gone first.
        // `orderOut` is not reflected by the window server synchronously, so gate the region
        // handoff until the server no longer lists our overlay windows on screen. Window and
        // cancel paths don't need this: window capture uses a content filter that excludes the
        // overlay, and cancel takes no screenshot.
        guard case .region = selection else {
            if selection.hasPreCapturedRegion {
                onComplete(selection)
                return
            }
            if selection.requiresOverlayClearBeforeCompletion {
                let complete = onComplete
                Self.waitForOverlaysToClear(overlayNumbers) {
                    complete(selection)
                }
                return
            }
            onComplete(selection)
            return
        }

        let complete = onComplete
        Self.waitForOverlaysToClear(overlayNumbers) {
            complete(selection)
        }
    }

    private func preCapturedRegion(for rect: CGRect) -> CapturedScreenshot? {
        guard let screenSnapshot,
              let snapshotScreenFrame,
              rect.width > 1,
              rect.height > 1 else {
            return nil
        }

        let clippedRect = rect.intersection(snapshotScreenFrame).integral
        guard !clippedRect.isNull,
              clippedRect.width > 1,
              clippedRect.height > 1,
              abs(clippedRect.width - rect.width) < 1,
              abs(clippedRect.height - rect.height) < 1 else {
            return nil
        }

        guard let crop = CaptureSnapshotGeometry.crop(screenSnapshot.image, sourceRect: snapshotScreenFrame, to: clippedRect) else {
            return nil
        }
        return CapturedScreenshot(image: crop, scaleFactor: screenSnapshot.scaleFactor, sourceRect: clippedRect)
    }

    /// Polls (bounded) until the window server no longer reports `overlayNumbers` on screen,
    /// then runs `completion`. Uses only the public `CGWindowListCopyWindowInfo`.
    private static func waitForOverlaysToClear(
        _ overlayNumbers: Set<CGWindowID>,
        attemptsRemaining: Int = 30,
        completion: @escaping () -> Void
    ) {
        guard attemptsRemaining > 0, !overlayNumbers.isEmpty, overlaysStillOnScreen(overlayNumbers) else {
            completion()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) {
            waitForOverlaysToClear(
                overlayNumbers,
                attemptsRemaining: attemptsRemaining - 1,
                completion: completion
            )
        }
    }

    private static func overlaysStillOnScreen(_ overlayNumbers: Set<CGWindowID>) -> Bool {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }
        let onscreen = Set(rawWindows.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        return !overlayNumbers.isDisjoint(with: onscreen)
    }
}

/// A borderless, non-activating overlay panel. Using a non-activating panel lets it become
/// key (for Escape handling) without bringing HeySnap to the foreground.
private final class AreaSelectionWindow: NSPanel {
    convenience init(screen: NSScreen, contentView: NSView) {
        self.init(frame: screen.frame, contentView: contentView)
    }

    init(frame: CGRect, contentView: NSView) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        self.contentView = contentView
        setFrame(frame, display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Draws the dim mask plus the active highlight (hovered window or drag rectangle) for one
/// screen, and forwards pointer events to the shared session in global coordinates.
private final class AreaSelectionView: NSView, NSTextViewDelegate {
    private var screenFrame: CGRect
    private let toolbarOnly: Bool
    private let screenSnapshot: CGImage?
    private weak var session: AreaSelectionSession?
    private var activeTextEditor: AnnotationInlineTextView?

    init(screenFrame: CGRect, screenSnapshot: CGImage?, session: AreaSelectionSession, toolbarOnly: Bool = false) {
        self.toolbarOnly = toolbarOnly
        self.screenFrame = screenFrame
        self.screenSnapshot = screenSnapshot
        self.session = session
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
        layer?.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "opacity": NSNull()]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateScreenFrame(_ frame: CGRect) { screenFrame = frame }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard session?.isInMarkupMode != true else { return }
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Coordinate helpers

    private func globalPoint(from event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: screenFrame.minX + local.x, y: screenFrame.minY + local.y)
    }

    func screenFrameContains(_ rect: CGRect) -> Bool {
        screenFrame.intersects(rect)
    }

    func beginTextEditing() {
        endTextEditing(commit: true)
        guard let annotation = session?.activeTextAnnotation(in: screenFrame) else { return }
        let editor = AnnotationInlineTextView(frame: annotation.rect)
        editor.forwardsBorderMouseEvents = true
        editor.delegate = self
        editor.drawsBackground = false
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.textContainerInset = NSSize(width: 14, height: 8)
        editor.textContainer?.lineFragmentPadding = 0
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = true
        editor.string = annotation.text
        configureTextEditor(editor, annotation: annotation)
        editor.onCommit = { [weak self] in self?.endTextEditing(commit: true) }
        editor.onCancel = { [weak self] in self?.endTextEditing(commit: false) }
        editor.onEditingLayoutChange = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.session?.updateActiveText(editor.string)
            if let annotation = self.session?.activeTextAnnotation(in: self.screenFrame) {
                editor.frame = annotation.rect
                self.configureTextEditor(editor, annotation: annotation)
            }
        }
        wantsLayer = true
        editor.wantsLayer = true
        editor.layer?.cornerRadius = 8
        editor.layer?.backgroundColor = annotation.textFillColor.cgColor
        addSubview(editor)
        activeTextEditor = editor
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
    }

    func endTextEditing(commit: Bool) {
        guard let editor = activeTextEditor else { return }
        let text = editor.string
        discardTextEditing()
        window?.makeFirstResponder(self)
        if commit {
            session?.updateActiveText(text)
            session?.commitActiveTextEditing()
        } else {
            session?.cancelActiveTextEditing()
        }
    }

    func discardTextEditing() {
        activeTextEditor?.removeFromSuperview()
        activeTextEditor?.delegate = nil
        activeTextEditor = nil
        window?.makeFirstResponder(self)
    }

    private func configureTextEditor(_ editor: AnnotationInlineTextView, annotation: OverlayMarkupAnnotation) {
        AnnotationTextRenderer.configure(editor, color: annotation.color, fillColor: annotation.textFillColor, fontSize: annotation.fontSize)
    }

    func refreshActiveTextStyle() {
        guard let editor = activeTextEditor, let annotation = session?.activeTextAnnotation(in: screenFrame) else { return }
        editor.frame = annotation.rect
        configureTextEditor(editor, annotation: annotation)
    }

    func textDidChange(_ notification: Notification) {
        guard let editor = notification.object as? AnnotationInlineTextView,
              editor === activeTextEditor else {
            return
        }
        session?.updateActiveText(editor.string)
        if let annotation = session?.activeTextAnnotation(in: screenFrame) {
            editor.frame = annotation.rect
            configureTextEditor(editor, annotation: annotation)
        }
    }

    // MARK: - Events

    override func mouseDown(with event: NSEvent) {
        let point = globalPoint(from: event)
        session?.handleMouseDown(globalPoint: point, clickCount: event.clickCount, modifiers: event.modifierFlags)
        session?.refreshCursor(globalPoint: point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = globalPoint(from: event)
        session?.handleMouseDragged(globalPoint: point, modifiers: event.modifierFlags)
        session?.refreshCursor(globalPoint: point)
    }

    override func mouseUp(with event: NSEvent) {
        let point = globalPoint(from: event)
        session?.handleMouseUp(globalPoint: point, modifiers: event.modifierFlags)
        session?.refreshCursor(globalPoint: point)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = globalPoint(from: event)
        session?.handleRightMouseDown(globalPoint: point)
        session?.refreshCursor(globalPoint: point)
    }

    override func mouseMoved(with event: NSEvent) {
        session?.handleMouseMoved(globalPoint: globalPoint(from: event))
    }

    override func flagsChanged(with event: NSEvent) {
        session?.handleModifiersChanged(event.modifierFlags)
        super.flagsChanged(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if session?.isInMarkupMode == true,
           event.keyCode == kVK_ANSI_Z,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
                session?.redoMarkup()
            } else {
                session?.undoMarkup()
            }
            return
        }
        if event.keyCode == kVK_Escape {
            session?.cancel()
            return
        }
        if event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter {
            session?.confirmMarkupToClipboard()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if toolbarOnly {
            if let propertyRect = session?.markupPropertyBarRect(in: screenFrame) { drawPropertyBar(in: propertyRect) }
            if let barRect = session?.markupBarRect(in: screenFrame) { drawMarkupBar(in: barRect) }
            return
        }
        let activeRect = activeRectInViewCoordinates()
        CaptureSnapshotGeometry.drawBackdrop(session?.showsFrozenDesktop == true ? screenSnapshot : nil, in: bounds, selection: activeRect)
        guard let activeRect else { return }

        let border = NSBezierPath(rect: activeRect)
        border.lineWidth = 2
        NSColor.systemBlue.setStroke()
        border.stroke()

        if session?.showsScrollingOptions == true { return }
        if session?.isInMarkupMode == true {
            drawMarkupAnnotations()
            drawMarkupHandles(in: activeRect)
            drawSelectedAnnotationHandles()
            if let propertyRect = session?.markupPropertyBarRect(in: screenFrame) {
                drawPropertyBar(in: propertyRect)
            }
            if let barRect = session?.markupBarRect(in: screenFrame) {
                drawMarkupBar(in: barRect)
            }
        }
    }

    private func drawMarkupAnnotations() {
        guard let session else { return }
        for annotation in session.markupAnnotations(in: screenFrame) {
            if session.isActiveTextAnnotation(annotation.id) {
                continue
            }
            drawMarkupAnnotation(annotation)
        }
        if let draft = session.draftMarkupAnnotation(in: screenFrame) {
            drawMarkupAnnotation(draft)
        }
    }

    private func drawMarkupAnnotation(_ annotation: OverlayMarkupAnnotation) {
        let rect = annotation.rect
        switch annotation.tool {
        case .rectangle:
            AnnotationShapeGeometry.draw(.rectangle, in: rect, color: annotation.color, width: annotation.lineWidth)
        case .oval:
            AnnotationShapeGeometry.draw(.oval, in: rect, color: annotation.color, width: annotation.lineWidth)
        case .line:
            AnnotationLineRenderer.draw(start: annotation.start, control: annotation.control ?? annotation.defaultControl, end: annotation.end, color: annotation.color, width: annotation.lineWidth)
        case .arrow:
            drawCurvedArrow(annotation)
        case .highlighter:
            drawSpotlight(annotation)
        case .text:
            AnnotationTextRenderer.draw(annotation.text, in: rect, color: annotation.color, fontSize: annotation.fontSize, fillColor: annotation.textFillColor, selected: session?.selectedMarkupAnnotation(in: screenFrame)?.id == annotation.id)
        case .blur:
            drawMosaicPreview(annotation)
        case .select:
            break
        }
    }

    private func drawMosaicPreview(_ annotation: OverlayMarkupAnnotation) {
        let rect = annotation.rect.integral
        guard rect.width > 2, rect.height > 2 else { return }
        guard let screenSnapshot else {
            drawFallbackMosaicPreview(in: rect, intensity: annotation.mosaicIntensity)
            return
        }
        let scaleX = CGFloat(screenSnapshot.width) / max(bounds.width, 1)
        let scaleY = CGFloat(screenSnapshot.height) / max(bounds.height, 1)
        let cropRect = CGRect(
            x: rect.minX * scaleX,
            y: (bounds.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral
        guard let crop = screenSnapshot.cropping(to: cropRect) else {
            drawFallbackMosaicPreview(in: rect, intensity: annotation.mosaicIntensity)
            return
        }
        drawPixelated(crop, in: rect, intensity: annotation.mosaicIntensity)
    }

    private func drawPixelated(_ image: CGImage, in rect: CGRect, intensity: CGFloat) {
        let divisor = max(4, min(28, 4 + intensity * 24))
        let smallSize = CGSize(width: max(1, rect.width / divisor), height: max(1, rect.height / divisor))
        let small = NSImage(size: smallSize)
        small.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: image, size: smallSize).draw(in: CGRect(origin: .zero, size: smallSize))
        small.unlockFocus()

        NSGraphicsContext.current?.imageInterpolation = .none
        small.draw(in: rect)
        NSGraphicsContext.current?.imageInterpolation = .default
    }

    private func drawFallbackMosaicPreview(in rect: CGRect, intensity: CGFloat) {
        let block = max(5, min(22, 5 + intensity * 22))
        let colors = [
            NSColor.black.withAlphaComponent(0.24),
            NSColor.white.withAlphaComponent(0.18),
            NSColor.systemGray.withAlphaComponent(0.24)
        ]
        var row = 0
        var y = rect.minY
        while y < rect.maxY {
            var column = 0
            var x = rect.minX
            while x < rect.maxX {
                colors[(row + column) % colors.count].setFill()
                CGRect(x: x, y: y, width: min(block, rect.maxX - x), height: min(block, rect.maxY - y)).fill()
                x += block
                column += 1
            }
            y += block
            row += 1
        }
    }

    private func drawSpotlight(_ annotation: OverlayMarkupAnnotation) {
        let outer = bounds
        let shape = annotation.highlightPath(in: annotation.rect)
        let path = NSBezierPath(rect: outer)
        path.append(shape)
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(annotation.highlightOpacity).setFill()
        path.fill()

        NSColor.systemBlue.withAlphaComponent(0.7).setStroke()
        shape.lineWidth = 1.5
        shape.stroke()
    }

    private func drawCurvedArrow(_ annotation: OverlayMarkupAnnotation) {
        AnnotationArrowRenderer.draw(
            start: annotation.start,
            control: annotation.control ?? annotation.defaultControl,
            end: annotation.end,
            color: annotation.color,
            width: annotation.lineWidth
        )
    }

    private func drawSelectedAnnotationHandles() {
        guard let annotation = session?.selectedMarkupAnnotation(in: screenFrame) else { return }
        guard annotation.tool != .text else { return }
        for (_, point) in annotation.handlePoints {
            AnnotationArrowGeometry.drawHandle(at: point)
        }
    }

    private func drawMarkupHandles(in rect: CGRect) {
        let points = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY)
        ]
        for point in points {
            let handleRect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            let path = NSBezierPath(ovalIn: handleRect)
            NSColor.white.setFill()
            path.fill()
            NSColor.systemBlue.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func drawMarkupBar(in rect: CGRect) {
        let background = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        background.fill()
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        background.lineWidth = 0.8
        background.stroke()

        let slots = QuickMarkupBarSlot.layout(in: rect)
        for slot in slots {
            if slot.kind == .separator {
                drawToolbarSeparator(in: slot.rect)
                continue
            }
            if session?.currentBarHoverIndex == slot.index {
                let hover = slot.rect.insetBy(dx: 5, dy: 7)
                NSColor.labelColor.withAlphaComponent(0.07).setFill()
                NSBezierPath(roundedRect: hover, xRadius: 6, yRadius: 6).fill()
            }
            if session?.markupToolIndex == slot.index {
                let selected = slot.rect.insetBy(dx: 5, dy: 7)
                NSColor.labelColor.withAlphaComponent(0.12).setFill()
                NSBezierPath(roundedRect: selected, xRadius: 6, yRadius: 6).fill()
            }
            if slot.kind == .dragHandle {
                drawDragHandle(in: slot.rect)
            } else if slot.kind == .cancel {
                drawCancelIcon(in: slot.rect)
            } else if slot.kind == .done {
                drawDoneIcon(in: slot.rect)
            } else if let symbol = slot.kind.symbolName {
                drawSymbol(
                    symbol,
                    centeredIn: slot.rect,
                    weight: .regular,
                    color: slot.kind.symbolColor
                )
            }
        }

        if let tooltipIndex = session?.currentBarTooltipIndex,
           let slot = slots.first(where: { $0.index == tooltipIndex }),
           let title = slot.kind.title {
            drawToolbarTooltip(title, anchoredTo: slot.rect, in: rect)
        }

        if !toolbarOnly, let message = session?.currentNoticeMessage {
            drawOverlayNotice(message, anchoredTo: rect)
        }
    }

    private func drawPropertyBar(in rect: CGRect) {
        let background = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        background.fill()
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        background.lineWidth = 0.8
        background.stroke()

        if session?.activePropertyTool == .blur {
            drawMosaicPropertyBar(in: rect)
            return
        }

        if session?.activePropertyTool == .highlighter {
            drawHighlightPropertyBar(in: rect)
            return
        }

        if session?.activePropertyTool == .text {
            drawTextStyleButtons(in: rect)
        }
        let rect = session?.activePropertyTool == .text ? QuickMarkupPropertyBarLayout.textControls(in: rect) : rect
        let swatches: [NSColor] = [AnnotationDefaults.color, .systemYellow, .systemGreen, .systemBlue, .black, .systemGray, .white]
        for (index, color) in swatches.enumerated() {
            let center = CGPoint(x: rect.minX + 14 + CGFloat(index) * 26, y: rect.midY)
            let swatchRect = CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)
            let isSelected = color.isVisuallyEqual(to: session?.currentPropertyColor ?? .clear)
            let path = NSBezierPath(ovalIn: swatchRect)
            color.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            if isSelected {
                drawCheckmark(centeredAt: center, over: color)
            }
        }

        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: CGPoint(x: rect.minX + 190, y: rect.minY + 8))
        separator.line(to: CGPoint(x: rect.minX + 190, y: rect.maxY - 8))
        separator.lineWidth = 1
        separator.stroke()

        if session?.activePropertyTool?.usesStrokeWidthDots == true {
            let widthValues: [CGFloat] = AnnotationDefaults.quickMarkupLineWidths
            let dotSizes: [CGFloat] = [6, 10, 14]
            for (index, dotSize) in dotSizes.enumerated() {
                let itemRect = QuickMarkupPropertyBarLayout(sizeCount: widthValues.count).itemRect(at: index, in: rect)
                let isSelected = abs((session?.currentPropertyLineWidth ?? AnnotationDefaults.lineWidth) - widthValues[index]) < 0.5
                let isHovering = session?.currentPropertyHoverIndex == index
                let displaySize = isHovering && !isSelected ? dotSize + 2 : dotSize
                let dotRect = CGRect(
                    x: itemRect.midX - displaySize / 2,
                    y: itemRect.midY - displaySize / 2,
                    width: displaySize,
                    height: displaySize
                )
                if isSelected {
                    NSColor.controlAccentColor.setFill()
                } else if isHovering {
                    NSColor.labelColor.withAlphaComponent(0.72).setFill()
                } else {
                    NSColor.secondaryLabelColor.setFill()
                }
                NSBezierPath(ovalIn: dotRect).fill()
            }
        } else {
            let labels = session?.activePropertyTool == .text ? ["12", "16", "20", "28"] : ["2", "3", "5", "8"]
            for (index, label) in labels.enumerated() {
                let itemRect = QuickMarkupPropertyBarLayout(sizeCount: labels.count).itemRect(at: index, in: rect)
                NSColor.labelColor.withAlphaComponent(0.08).setFill()
                NSBezierPath(roundedRect: itemRect, xRadius: 6, yRadius: 6).fill()
                NSString(string: label).draw(in: itemRect.insetBy(dx: 0, dy: 6), withAttributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: centeredParagraphStyle()
                ])
            }
        }
    }

    private func drawTextStyleButtons(in rect: CGRect) {
        for (filled, label) in [(false, "Normal"), (true, "Filled")] {
            let button = QuickMarkupPropertyBarLayout.textStyleRect(filled: filled, in: rect)
            let selected = session?.currentPropertyTextFilled == filled
            (selected ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.labelColor.withAlphaComponent(0.06)).setFill()
            NSBezierPath(roundedRect: button, xRadius: 6, yRadius: 6).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor]
            let size = (label as NSString).size(withAttributes: attributes)
            (label as NSString).draw(at: CGPoint(x: button.midX - size.width / 2, y: button.midY - size.height / 2), withAttributes: attributes)
        }
    }

    private func centeredParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }

    private func drawMosaicPropertyBar(in rect: CGRect) {
        drawSymbol("checkerboard.rectangle", centeredIn: CGRect(x: rect.minX + 8, y: rect.minY, width: 42, height: rect.height))
        NSString(string: "模糊强度").draw(in: CGRect(x: rect.minX + 58, y: rect.minY + 12, width: 72, height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ])
        drawSlider(in: CGRect(x: rect.minX + 142, y: rect.minY + 16, width: 112, height: 10), value: session?.currentPropertyMosaicIntensity ?? 0.5)
        let percent = Int(((session?.currentPropertyMosaicIntensity ?? 0.5) * 100).rounded())
        NSString(string: "\(percent)%").draw(in: CGRect(x: rect.minX + 270, y: rect.minY + 12, width: 52, height: 18), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
    }

    private func drawHighlightPropertyBar(in rect: CGRect) {
        let shapes: [OverlayHighlightShape] = [.rectangle, .oval, .roundedRectangle]
        for (index, shape) in shapes.enumerated() {
            let itemRect = CGRect(x: rect.minX + 10 + CGFloat(index) * 36, y: rect.minY + 6, width: 30, height: rect.height - 12)
            if session?.currentPropertyHighlightShape == shape {
                NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: itemRect, xRadius: 7, yRadius: 7).fill()
            }
            NSColor.labelColor.set()
            drawHighlightShapeIcon(shape, in: itemRect)
        }
        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: CGPoint(x: rect.minX + 124, y: rect.minY + 8))
        separator.line(to: CGPoint(x: rect.minX + 124, y: rect.maxY - 8))
        separator.lineWidth = 1
        separator.stroke()
        NSString(string: "不透明度").draw(in: CGRect(x: rect.minX + 140, y: rect.minY + 12, width: 72, height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ])
        drawSlider(in: CGRect(x: rect.minX + 218, y: rect.minY + 16, width: 74, height: 10), value: session?.currentPropertyHighlightOpacity ?? 0.5)
    }

    private func drawSlider(in rect: CGRect, value: CGFloat) {
        let clamped = min(max(value, 0), 1)
        let track = CGRect(x: rect.minX, y: rect.midY - 1.5, width: rect.width, height: 3)
        NSColor.separatorColor.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
        let active = CGRect(x: track.minX, y: track.minY, width: track.width * clamped, height: track.height)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: active, xRadius: 1.5, yRadius: 1.5).fill()
        let knobCenter = CGPoint(x: track.minX + track.width * clamped, y: track.midY)
        let knob = CGRect(x: knobCenter.x - 5, y: knobCenter.y - 5, width: 10, height: 10)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(ovalIn: knob)
        outline.lineWidth = 1.5
        outline.stroke()
    }

    private func drawHighlightShapeIcon(_ shape: OverlayHighlightShape, in rect: CGRect) {
        switch shape {
        case .rectangle:
            drawSymbol("rectangle", centeredIn: rect)
        case .oval:
            drawSymbol("circle", centeredIn: rect)
        case .roundedRectangle:
            let iconRect = CGRect(x: rect.midX - 9, y: rect.midY - 7, width: 18, height: 14)
            let path = NSBezierPath(roundedRect: iconRect, xRadius: 4, yRadius: 4)
            path.lineWidth = 1.8
            NSColor.labelColor.setStroke()
            path.stroke()
        }
    }

    private func drawSymbol(_ symbolName: String, centeredIn rect: CGRect, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: weight)
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return
        }
        let maxSize: CGFloat = 20
        let imageSize = image.size
        let scale = min(maxSize / max(imageSize.width, 1), maxSize / max(imageSize.height, 1))
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let target = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        NSGraphicsContext.saveGraphicsState()
        color.set()
        image.isTemplate = true
        image.draw(in: target)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCancelIcon(in rect: CGRect) {
        let size: CGFloat = 16
        let iconRect = CGRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: iconRect.minX + 2, y: iconRect.minY + 2))
        path.line(to: CGPoint(x: iconRect.maxX - 2, y: iconRect.maxY - 2))
        path.move(to: CGPoint(x: iconRect.maxX - 2, y: iconRect.minY + 2))
        path.line(to: CGPoint(x: iconRect.minX + 2, y: iconRect.maxY - 2))
        path.lineWidth = 2.4
        path.lineCapStyle = .round
        NSColor.systemRed.setStroke()
        path.stroke()
    }

    private func drawDoneIcon(in rect: CGRect) {
        let size: CGFloat = 18
        let iconRect = CGRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: iconRect.minX + 2, y: iconRect.midY - 1))
        path.line(to: CGPoint(x: iconRect.midX - 2, y: iconRect.minY + 3))
        path.line(to: CGPoint(x: iconRect.maxX - 2, y: iconRect.maxY - 3))
        path.lineWidth = 2.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.systemGreen.setStroke()
        path.stroke()
    }

    private func drawDragHandle(in rect: CGRect) {
        let dotSize: CGFloat = 2.3
        let gapX: CGFloat = 7
        let gapY: CGFloat = 6
        let startX = rect.midX - gapX / 2
        let startY = rect.midY - gapY
        NSColor.secondaryLabelColor.setFill()
        for column in 0..<2 {
            for row in 0..<3 {
                let center = CGPoint(x: startX + CGFloat(column) * gapX, y: startY + CGFloat(row) * gapY)
                NSBezierPath(ovalIn: CGRect(x: center.x - dotSize / 2, y: center.y - dotSize / 2, width: dotSize, height: dotSize)).fill()
            }
        }
    }

    private func drawToolbarSeparator(in rect: CGRect) {
        NSColor.separatorColor.withAlphaComponent(0.65).setStroke()
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 10))
        path.line(to: CGPoint(x: rect.midX, y: rect.maxY - 10))
        path.lineWidth = 1
        path.stroke()
    }

    private func drawToolbarTooltip(_ title: String, anchoredTo itemRect: CGRect, in barRect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = NSString(string: title).size(withAttributes: attributes)
        let padding = CGSize(width: 10, height: 6)
        let tooltipSize = CGSize(width: ceil(textSize.width + padding.width * 2), height: ceil(textSize.height + padding.height * 2))
        var tooltipRect = CGRect(
            x: itemRect.midX - tooltipSize.width / 2,
            y: barRect.maxY + 8,
            width: tooltipSize.width,
            height: tooltipSize.height
        )

        if tooltipRect.maxY > bounds.maxY - 8 {
            tooltipRect.origin.y = barRect.minY - tooltipSize.height - 8
        }
        tooltipRect.origin.x = min(max(tooltipRect.minX, bounds.minX + 8), bounds.maxX - tooltipSize.width - 8)

        let path = NSBezierPath(roundedRect: tooltipRect, xRadius: 7, yRadius: 7)
        NSColor.black.withAlphaComponent(0.82).setFill()
        path.fill()

        let textRect = CGRect(
            x: tooltipRect.minX + padding.width,
            y: tooltipRect.minY + padding.height - 1,
            width: textSize.width,
            height: textSize.height
        )
        NSString(string: title).draw(in: textRect, withAttributes: attributes)
    }

    private func drawOverlayNotice(_ message: String, anchoredTo barRect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = NSString(string: message).size(withAttributes: attributes)
        let padding = CGSize(width: 12, height: 7)
        let maxWidth = min(bounds.width - 16, 360)
        let noticeSize = CGSize(
            width: min(maxWidth, ceil(textSize.width + padding.width * 2)),
            height: ceil(textSize.height + padding.height * 2)
        )
        var noticeRect = CGRect(
            x: barRect.midX - noticeSize.width / 2,
            y: barRect.maxY + 8,
            width: noticeSize.width,
            height: noticeSize.height
        )

        if noticeRect.maxY > bounds.maxY - 8 {
            noticeRect.origin.y = barRect.minY - noticeSize.height - 8
        }
        noticeRect.origin.x = min(max(noticeRect.minX, bounds.minX + 8), bounds.maxX - noticeSize.width - 8)

        let path = NSBezierPath(roundedRect: noticeRect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.84).setFill()
        path.fill()

        let textRect = CGRect(
            x: noticeRect.minX + padding.width,
            y: noticeRect.minY + padding.height - 1,
            width: noticeRect.width - padding.width * 2,
            height: textSize.height
        )
        NSString(string: message).draw(in: textRect, withAttributes: attributes)
    }

    private func drawCheckmark(centeredAt center: CGPoint, over color: NSColor) {
        let check = QuickMarkupPropertyBarIcons.colorCheckmark(centeredAt: center)

        checkmarkColor(over: color).setStroke()
        check.stroke()
    }

    private func checkmarkColor(over color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else {
            return .white
        }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.65 ? .black : .white
    }

    /// Converts the session's global active rect into this view's coordinates, clipped to
    /// the screen, or `nil` if it does not intersect this display.
    private func activeRectInViewCoordinates() -> CGRect? {
        guard let globalRect = session?.activeGlobalRect else { return nil }
        let intersection = globalRect.intersection(screenFrame)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return nil
        }
        return CGRect(
            x: intersection.minX - screenFrame.minX,
            y: intersection.minY - screenFrame.minY,
            width: intersection.width,
            height: intersection.height
        ).integral
    }
}

private enum OverlayMarkupCompletionAction {
    case copy
    case save
}

struct QuickMarkupBarSlot {
    let index: Int
    let kind: Kind
    let rect: CGRect

    enum Kind {
        case dragHandle
        case rectangle
        case oval
        case line
        case arrow
        case text
        case separator
        case mosaic
        case highlight
        case scrolling
        case pin
        case editor
        case save
        case cancel
        case done

        var widthWeight: CGFloat {
            switch self {
            case .separator:
                return 0.45
            default:
                return 1
            }
        }

        var symbolName: String? {
            switch self {
            case .dragHandle, .separator:
                return nil
            case .rectangle:
                return "rectangle"
            case .oval:
                return "circle"
            case .line:
                return "line.diagonal"
            case .arrow:
                return "arrow.up.right"
            case .text:
                return "t.square"
            case .mosaic:
                return "checkerboard.rectangle"
            case .highlight:
                return "inset.filled.rectangle.and.pointer.arrow"
            case .scrolling:
                return "arrow.up.and.down"
            case .pin:
                return "pin"
            case .editor:
                return "pencil.and.outline"
            case .save:
                return "laptopcomputer.and.arrow.down"
            case .cancel:
                return "xmark"
            case .done:
                return "checkmark"
            }
        }

        var symbolColor: NSColor {
            switch self {
            case .cancel:
                return .systemRed
            case .done:
                return .systemGreen
            default:
                return .labelColor
            }
        }

        var title: String? {
            switch self {
            case .dragHandle:
                return "Move bar"
            case .rectangle:
                return "Rectangle"
            case .oval:
                return "Circle"
            case .line:
                return "Line"
            case .arrow:
                return "Arrow"
            case .text:
                return "Text"
            case .separator:
                return nil
            case .mosaic:
                return "Mosaic"
            case .highlight:
                return "Highlight"
            case .scrolling:
                return "Scrolling Capture"
            case .pin:
                return "Pin"
            case .editor:
                return "Open Editor"
            case .save:
                return "Save"
            case .cancel:
                return "Cancel"
            case .done:
                return "Copy"
            }
        }

        var isClickable: Bool {
            switch self {
            case .dragHandle, .separator:
                return false
            default:
                return true
            }
        }

        var drawsHover: Bool {
            isClickable
        }

        var showsTooltip: Bool {
            self != .separator
        }
    }

    static let kinds: [Kind] = [
        .dragHandle,
        .rectangle,
        .oval,
        .line,
        .arrow,
        .text,
        .separator,
        .mosaic,
        .highlight,
        .scrolling,
        .pin,
        .separator,
        .editor,
        .save,
        .cancel,
        .done
    ]

    static func layout(in rect: CGRect) -> [QuickMarkupBarSlot] {
        let totalWeight = kinds.reduce(CGFloat.zero) { $0 + $1.widthWeight }
        let unit = rect.width / max(totalWeight, 1)
        var x = rect.minX
        return kinds.enumerated().map { index, kind in
            let width = unit * kind.widthWeight
            defer { x += width }
            return QuickMarkupBarSlot(index: index, kind: kind, rect: CGRect(x: x, y: rect.minY, width: width, height: rect.height))
        }
    }

    static func slot(at point: CGPoint, in rect: CGRect) -> QuickMarkupBarSlot? {
        layout(in: rect).first { $0.rect.contains(point) }
    }
}

private struct OverlayMarkupSnapshot {
    let annotations: [OverlayMarkupAnnotation]
    let selectedAnnotationID: UUID?
}

private enum OverlayPropertyDrag {
    case mosaicIntensity
    case highlightOpacity
}

private extension NSColor {
    func isVisuallyEqual(to other: NSColor, tolerance: CGFloat = 0.01) -> Bool {
        guard let lhs = usingColorSpace(.deviceRGB),
              let rhs = other.usingColorSpace(.deviceRGB) else {
            return false
        }
        return abs(lhs.redComponent - rhs.redComponent) <= tolerance
            && abs(lhs.greenComponent - rhs.greenComponent) <= tolerance
            && abs(lhs.blueComponent - rhs.blueComponent) <= tolerance
            && abs(lhs.alphaComponent - rhs.alphaComponent) <= tolerance
    }
}

private enum OverlaySelectionHandle: CaseIterable {
    case bottomLeft
    case bottom
    case bottomRight
    case right
    case topRight
    case top
    case topLeft
    case left

    var movesLeft: Bool {
        self == .bottomLeft || self == .topLeft || self == .left
    }

    var movesRight: Bool {
        self == .bottomRight || self == .topRight || self == .right
    }

    var movesBottom: Bool {
        self == .bottomLeft || self == .bottom || self == .bottomRight
    }

    var movesTop: Bool {
        self == .topLeft || self == .top || self == .topRight
    }

    var cursor: NSCursor {
        switch self {
        case .topLeft:
            return .frameResize(position: .topLeft, directions: .all)
        case .top:
            return .resizeUpDown
        case .topRight:
            return .frameResize(position: .topRight, directions: .all)
        case .right:
            return .resizeLeftRight
        case .bottomRight:
            return .frameResize(position: .bottomRight, directions: .all)
        case .bottom:
            return .resizeUpDown
        case .bottomLeft:
            return .frameResize(position: .bottomLeft, directions: .all)
        case .left:
            return .resizeLeftRight
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .bottom:
            return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .right:
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        case .top:
            return CGPoint(x: rect.midX, y: rect.maxY)
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .left:
            return CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}
