import AppKit
import Carbon
import Darwin
import SwiftUI

@main
struct HeySnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("HeySnap", id: HeySnapWindowID.main) {
            PreferencesRootView(
                settings: appDelegate.settings,
                hotKeyService: appDelegate.hotKeyService,
                screenshotService: appDelegate.screenshotService,
                updateController: appDelegate.updateController
            )
            .frame(minWidth: 460, minHeight: 340)
        }
        .defaultSize(width: 780, height: 520)
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    openWindow(id: HeySnapWindowID.main)
                    appDelegate.showPreferencesWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

enum HeySnapWindowID {
    static let main = "main"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var singleInstanceLockFileDescriptor: CInt = -1
    let settings = AppSettings()
    let updateController = UpdateController()
    private(set) lazy var screenshotService = ScreenshotService(
        saveDirectoryProvider: { [settings] in settings.saveDirectoryURL },
        saveFormatPreferenceProvider: { [settings] in settings.saveFormatPreference },
        resizeRetinaScreenshotsProvider: { [settings] in settings.resizeRetinaScreenshots },
        windowBackgroundProvider: { [settings] in settings.windowScreenshotBackground },
        logInfo: AppLogger.info,
        logError: AppLogger.error
    )
    private let areaSelectionController = AreaSelectionController()
    private var editorWindowControllers: [ScreenshotEditorWindowController] = []
    private var pinnedWindowControllers: [PinnedScreenshotWindowController] = []
    private(set) lazy var hotKeyService = HotKeyService { [weak self] action in
        self?.handleHotKey(action)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        enforceSingleRunningInstance()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.info("Application did finish launching.")
        updateController.start()
        settings.onShortcutsChange = { [weak self] in
            self?.registerHotKey()
        }
        registerHotKey()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        screenshotService.refreshPermissionStatus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func showPreferencesWindow() {
        NSApp.activate(ignoringOtherApps: true)
        focusPreferencesWindow()
    }

    private func enforceSingleRunningInstance() {
        guard acquireSingleInstanceLock() else {
            activateExistingInstance()
            NSApp.terminate(nil)
            return
        }
    }

    private func acquireSingleInstanceLock() -> Bool {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let lockDirectory = supportDirectory.appendingPathComponent("HeySnap", isDirectory: true)

        do {
            try fileManager.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        } catch {
            AppLogger.error("Could not create single-instance lock directory: \(error.localizedDescription)")
            return true
        }

        let lockURL = lockDirectory.appendingPathComponent("HeySnap.lock", isDirectory: false)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            AppLogger.error("Could not open single-instance lock file.")
            return true
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            AppLogger.info("Another HeySnap instance is already running; lock acquisition failed.")
            return false
        }

        singleInstanceLockFileDescriptor = descriptor
        return true
    }

    private func activateExistingInstance() {
        let currentApplication = NSRunningApplication.current
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }

        let existingApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentApplication.processIdentifier }
        guard let existingApplication else {
            return
        }

        AppLogger.info("Another HeySnap instance is already running; activating existing instance.")
        existingApplication.activate(options: [.activateAllWindows])
    }

    private func focusPreferencesWindow(attemptsRemaining: Int = 8) {
        if let window = NSApp.windows.first(where: { $0.title == "HeySnap" }) {
            window.makeKeyAndOrderFront(self)
            return
        }

        guard attemptsRemaining > 0 else {
            AppLogger.error("Could not focus preferences window after Command+, request.")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.focusPreferencesWindow(attemptsRemaining: attemptsRemaining - 1)
        }
    }

    private func registerHotKey() {
        var shortcuts: [HotKeyAction: HotKeyShortcut] = [:]
        shortcuts[.screen] = settings.screenShortcut
        shortcuts[.area] = settings.areaShortcut

        do {
            try hotKeyService.register(shortcuts: shortcuts)
            AppLogger.info("Registered screen hotkey \(settings.screenShortcut?.displayName ?? "disabled").")
            AppLogger.info("Registered area hotkey \(settings.areaShortcut?.displayName ?? "disabled").")
        } catch {
            AppLogger.error("Hotkey registration failed: \(error.localizedDescription)")
            screenshotService.publishStatus(.failure("Hotkey registration failed: \(error.localizedDescription)"))
        }
    }

    private func handleHotKey(_ action: HotKeyAction) {
        AppLogger.info("Hotkey fired for \(action.displayName).")
        switch action {
        case .screen:
            Task { @MainActor in
                await handleScreenCapture()
            }
        case .area:
            if settings.postCaptureAction == .quickMarkup {
                Task { @MainActor in
                    let snapshot = await screenshotService.captureForEditing()
                    beginAreaSelection(quickMarkupEnabled: true, screenSnapshot: snapshot)
                }
            } else {
                beginAreaSelection(quickMarkupEnabled: false, screenSnapshot: nil)
            }
        }
    }

    private func beginAreaSelection(quickMarkupEnabled: Bool, screenSnapshot: CapturedScreenshot?) {
        areaSelectionController.beginSelection(
            quickMarkupEnabled: quickMarkupEnabled,
            screenSnapshot: screenSnapshot
        ) { [weak self] selection in
            guard let self else { return }
            switch selection {
            case .region(let rect):
                Task { @MainActor in
                    await self.handleRegionCapture(rect: rect)
                }
            case .copyRegion(let rect, let annotations):
                Task { @MainActor in
                    await self.copyRegionToClipboard(rect: rect, annotations: annotations)
                }
            case .saveRegion(let rect, let annotations):
                Task { @MainActor in
                    await self.saveRegion(rect: rect, annotations: annotations)
                }
            case .pinRegion(let rect, let annotations):
                Task { @MainActor in
                    await self.pinRegion(rect: rect, annotations: annotations)
                }
            case .editRegion(let rect):
                Task { @MainActor in
                    await self.openEditorForRegion(rect: rect)
                }
            case .window(let window):
                Task { @MainActor in
                    await self.handleWindowCapture(windowID: window.windowID)
                }
            case .cancelled:
                AppLogger.info("Area capture cancelled.")
            }
        }
    }

    private func handleScreenCapture() async {
        switch settings.postCaptureAction {
        case .saveToLocation:
            await screenshotService.captureAndSave()
        case .quickMarkup:
            guard let capture = await screenshotService.captureForEditing() else { return }
            openEditor(with: capture)
        case .openEditor:
            guard let capture = await screenshotService.captureForEditing() else { return }
            openEditor(with: capture)
        }
    }

    private func handleRegionCapture(rect: CGRect) async {
        switch settings.postCaptureAction {
        case .saveToLocation:
            await screenshotService.captureAndSave(rect: rect)
        case .quickMarkup:
            await screenshotService.captureAndSave(rect: rect)
        case .openEditor:
            guard let capture = await screenshotService.captureForEditing(rect: rect) else { return }
            openEditor(with: capture)
        }
    }

    private func handleWindowCapture(windowID: CGWindowID) async {
        switch settings.postCaptureAction {
        case .saveToLocation:
            await screenshotService.captureAndSave(windowID: windowID)
        case .quickMarkup:
            guard let capture = await screenshotService.captureForEditing(windowID: windowID) else { return }
            openEditor(with: capture)
        case .openEditor:
            guard let capture = await screenshotService.captureForEditing(windowID: windowID) else { return }
            openEditor(with: capture)
        }
    }

    private func openEditor(with capture: CapturedScreenshot) {
        let controller = ScreenshotEditorWindowController(
            image: capture.image,
            sourceScaleFactor: capture.scaleFactor,
            screenshotService: screenshotService
        )
        controller.onClose = { [weak self] closedController in
            self?.editorWindowControllers.removeAll { $0 === closedController }
        }
        editorWindowControllers.append(controller)
        controller.showWindow(self)
        controller.window?.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.info("Screenshot editor opened.")
    }

    private func copyRegionToClipboard(rect: CGRect, annotations: [OverlayMarkupAnnotation]) async {
        guard let capture = await screenshotService.captureForEditing(rect: rect) else {
            NSSound.beep()
            return
        }
        let image = OverlayMarkupRenderer.render(annotations: annotations, over: capture.image, region: rect)
        guard let pngData = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        screenshotService.publishStatus(.success("Copied screenshot to clipboard"))
        AppLogger.info("Quick markup region copied to clipboard.")
    }

    private func saveRegion(rect: CGRect, annotations: [OverlayMarkupAnnotation]) async {
        guard let capture = await screenshotService.captureForEditing(rect: rect) else {
            NSSound.beep()
            return
        }
        let image = OverlayMarkupRenderer.render(annotations: annotations, over: capture.image, region: rect)
        do {
            let url = try screenshotService.saveEditedImage(image, sourceScaleFactor: capture.scaleFactor)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            screenshotService.publishStatus(.failure(error.localizedDescription))
            NSSound.beep()
        }
    }

    private func openEditorForRegion(rect: CGRect) async {
        guard let capture = await screenshotService.captureForEditing(rect: rect) else {
            NSSound.beep()
            return
        }
        openEditor(with: capture)
    }

    private func pinRegion(rect: CGRect, annotations: [OverlayMarkupAnnotation]) async {
        guard let capture = await screenshotService.captureForEditing(rect: rect) else {
            NSSound.beep()
            return
        }
        let image = OverlayMarkupRenderer.render(annotations: annotations, over: capture.image, region: rect)
        let controller = PinnedScreenshotWindowController(image: image, screenRect: rect)
        controller.onClose = { [weak self] closedController in
            self?.pinnedWindowControllers.removeAll { $0 === closedController }
        }
        pinnedWindowControllers.append(controller)
        controller.showWindow(self)
        controller.window?.makeKeyAndOrderFront(self)
        AppLogger.info("Quick markup region pinned.")
    }
}

private final class PinnedScreenshotWindowController: NSWindowController, NSWindowDelegate {
    var onClose: ((PinnedScreenshotWindowController) -> Void)?

    init(image: CGImage, screenRect: CGRect) {
        let imageSize = PinnedScreenshotView.windowSize(forImageSize: CGSize(width: image.width, height: image.height))
        let view = PinnedScreenshotView(image: image)
        let window = PinnedScreenshotWindow(
            contentRect: CGRect(origin: .zero, size: imageSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let frame = CGRect(
            x: screenRect.minX - PinnedScreenshotView.chromeOutset,
            y: screenRect.minY,
            width: screenRect.width + PinnedScreenshotView.chromeOutset * 2,
            height: screenRect.height + PinnedScreenshotView.chromeOutset
        )
        window.setFrame(frame, display: true)
        super.init(window: window)
        window.delegate = self
        view.onClose = { [weak self] in
            self?.close()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func close() {
        super.close()
        onClose?(self)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }
}

private final class PinnedScreenshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class PinnedScreenshotView: NSView {
    static let chromeOutset: CGFloat = 14

    static func windowSize(forImageSize imageSize: CGSize) -> CGSize {
        CGSize(width: imageSize.width + chromeOutset * 2, height: imageSize.height + chromeOutset)
    }

    private let image: CGImage
    private let aspectRatio: CGFloat
    var onClose: (() -> Void)?
    private var dragStartLocation: CGPoint?
    private var dragStartFrame: CGRect?
    private var isMovingWindow = false
    private var isHoveringWindow = false {
        didSet {
            if oldValue != isHoveringWindow {
                needsDisplay = true
            }
        }
    }
    private var isHoveringClose = false {
        didSet {
            if oldValue != isHoveringClose {
                needsDisplay = true
            }
        }
    }

    init(image: CGImage) {
        self.image = image
        self.aspectRatio = max(1, CGFloat(image.width)) / max(1, CGFloat(image.height))
        let size = Self.windowSize(forImageSize: CGSize(width: image.width, height: image.height))
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        autoresizingMask = [.width, .height]
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(imageRect, cursor: .editorMove)
        addCursorRect(closeButtonRect, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.draw(image, in: imageRect)
        drawPinnedBorder()
        if isHoveringWindow {
            drawCloseButton()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHoveringWindow = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        isHoveringWindow = true
        isHoveringClose = closeButtonRect.contains(point)
        if isHoveringClose {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.editorMove.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHoveringWindow = false
        isHoveringClose = false
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if closeButtonRect.contains(point) {
            onClose?()
            return
        }
        guard imageRect.contains(point) else { return }
        dragStartLocation = NSEvent.mouseLocation
        dragStartFrame = window?.frame
        isMovingWindow = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isMovingWindow,
              let dragStartLocation,
              let dragStartFrame,
              let window else { return }
        let location = NSEvent.mouseLocation
        let dx = location.x - dragStartLocation.x
        let dy = location.y - dragStartLocation.y
        window.setFrame(dragStartFrame.offsetBy(dx: dx, dy: dy), display: true)
    }

    override func mouseUp(with event: NSEvent) {
        isMovingWindow = false
        dragStartLocation = nil
        dragStartFrame = nil
        let point = convert(event.locationInWindow, from: nil)
        isHoveringWindow = bounds.contains(point)
        isHoveringClose = closeButtonRect.contains(point)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : -event.scrollingDeltaX
        guard delta != 0 else { return }
        let factor = min(max(1 + delta * 0.012, 0.85), 1.18)
        resizeWindow(by: factor)
    }

    override func magnify(with event: NSEvent) {
        resizeWindow(by: min(max(1 + event.magnification, 0.8), 1.25))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == kVK_Escape {
            onClose?()
            return
        }
        if event.keyCode == kVK_ANSI_W && event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            onClose?()
            return
        }
        super.keyDown(with: event)
    }

    private var closeButtonRect: CGRect {
        CGRect(x: imageRect.maxX - 22, y: imageRect.maxY - 22, width: 28, height: 28)
    }

    private var imageRect: CGRect {
        CGRect(
            x: bounds.minX + Self.chromeOutset,
            y: bounds.minY,
            width: max(1, bounds.width - Self.chromeOutset * 2),
            height: max(1, bounds.height - Self.chromeOutset)
        )
    }

    private func drawPinnedBorder() {
        let border = NSBezierPath(rect: imageRect.insetBy(dx: 0.5, dy: 0.5))
        NSColor.white.withAlphaComponent(0.72).setStroke()
        border.lineWidth = 0.6
        border.stroke()
    }

    private func drawCloseButton() {
        let rect = closeButtonRect
        let path = NSBezierPath(ovalIn: rect)
        if isHoveringClose {
            NSColor.systemRed.setFill()
        } else {
            NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        }
        path.fill()
        (isHoveringClose ? NSColor.systemRed : NSColor.separatorColor.withAlphaComponent(0.55)).setStroke()
        path.lineWidth = 1
        path.stroke()

        let markInset: CGFloat = 8.5
        let mark = NSBezierPath()
        mark.move(to: CGPoint(x: rect.minX + markInset, y: rect.minY + markInset))
        mark.line(to: CGPoint(x: rect.maxX - markInset, y: rect.maxY - markInset))
        mark.move(to: CGPoint(x: rect.maxX - markInset, y: rect.minY + markInset))
        mark.line(to: CGPoint(x: rect.minX + markInset, y: rect.maxY - markInset))
        mark.lineWidth = 1.8
        (isHoveringClose ? NSColor.white : NSColor.labelColor).setStroke()
        mark.stroke()
    }

    private func resizeWindow(by factor: CGFloat) {
        guard let window else { return }
        let frame = window.frame
        let minWidth: CGFloat = 120
        let maxWidth = (window.screen?.visibleFrame.width ?? 1600) * 0.92
        let imageWidth = frame.width - Self.chromeOutset * 2
        let width = min(max(imageWidth * factor, minWidth), maxWidth)
        let height = width / aspectRatio
        let windowWidth = width + Self.chromeOutset * 2
        let windowHeight = height + Self.chromeOutset
        let newFrame = CGRect(
            x: frame.midX - windowWidth / 2,
            y: frame.midY - windowHeight / 2,
            width: windowWidth,
            height: windowHeight
        )
        window.setFrame(newFrame, display: true)
    }
}

private enum OverlayMarkupRenderer {
    static func render(annotations: [OverlayMarkupAnnotation], over image: CGImage, region: CGRect) -> CGImage {
        guard !annotations.isEmpty else { return image }
        let scaleX = CGFloat(image.width) / max(region.width, 1)
        let scaleY = CGFloat(image.height) / max(region.height, 1)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: image.width,
            pixelsHigh: image.height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let bitmap else { return image }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: image.width, height: image.height).fill(using: .copy)
        NSGraphicsContext.current?.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let imageSize = CGSize(width: image.width, height: image.height)
        for annotation in annotations {
            draw(annotation, baseImage: image, region: region, imageSize: imageSize, scaleX: scaleX, scaleY: scaleY)
        }

        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage ?? image
    }

    private static func draw(_ annotation: OverlayMarkupAnnotation, baseImage: CGImage, region: CGRect, imageSize: CGSize, scaleX: CGFloat, scaleY: CGFloat) {
        let start = convert(annotation.start, region: region, scaleX: scaleX, scaleY: scaleY)
        let end = convert(annotation.end, region: region, scaleX: scaleX, scaleY: scaleY)
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        let lineWidth = max(annotation.lineWidth * max(scaleX, scaleY), 2)

        switch annotation.tool {
        case .rectangle:
            stroke(NSBezierPath(rect: rect), width: lineWidth, color: annotation.color)
        case .oval:
            stroke(NSBezierPath(ovalIn: rect), width: lineWidth, color: annotation.color)
        case .line:
            let path = NSBezierPath()
            path.move(to: start)
            let control = annotation.control.map { convert($0, region: region, scaleX: scaleX, scaleY: scaleY) }
                ?? defaultControl(start: start, end: end)
            path.curve(to: end, controlPoint1: control, controlPoint2: control)
            stroke(path, width: lineWidth, color: annotation.color)
        case .arrow:
            let control = annotation.control.map { convert($0, region: region, scaleX: scaleX, scaleY: scaleY) }
                ?? defaultControl(start: start, end: end)
            drawArrow(from: start, control: control, to: end, width: lineWidth, color: annotation.color)
        case .highlighter:
            drawSpotlight(annotation, rect: rect, imageSize: imageSize)
        case .text:
            let textRect = rect.width > 1 && rect.height > 1 ? rect : CGRect(x: start.x, y: start.y, width: 140 * scaleX, height: 42 * scaleY)
            let path = NSBezierPath(roundedRect: textRect, xRadius: 7 * scaleX, yRadius: 7 * scaleY)
            annotation.color.withAlphaComponent(0.12).setFill()
            path.fill()
            stroke(path, width: lineWidth * 0.7, color: annotation.color)
            guard !annotation.text.isEmpty else { break }
            let font = NSFont(name: "PingFangSC-Regular", size: annotation.fontSize * max(scaleX, scaleY))
                ?? NSFont.systemFont(ofSize: annotation.fontSize * max(scaleX, scaleY), weight: .regular)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let lineHeight = ceil(font.ascender - font.descender + font.leading)
            let drawRect = CGRect(
                x: textRect.minX + 14 * scaleX,
                y: textRect.midY - lineHeight / 2,
                width: max(1, textRect.width - 28 * scaleX),
                height: lineHeight
            )
            annotation.text.draw(in: drawRect, withAttributes: [
                .font: font,
                .foregroundColor: annotation.color,
                .paragraphStyle: paragraph
            ])
        case .blur:
            drawMosaic(in: rect, from: baseImage, intensity: annotation.mosaicIntensity)
        case .select:
            break
        }
    }

    private static func convert(_ point: CGPoint, region: CGRect, scaleX: CGFloat, scaleY: CGFloat) -> CGPoint {
        CGPoint(
            x: (point.x - region.minX) * scaleX,
            y: (point.y - region.minY) * scaleY
        )
    }

    private static func stroke(_ path: NSBezierPath, width: CGFloat, color: NSColor = .systemRed) {
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    private static func drawSpotlight(_ annotation: OverlayMarkupAnnotation, rect: CGRect, imageSize: CGSize) {
        let path = NSBezierPath(rect: CGRect(origin: .zero, size: imageSize))
        path.append(annotation.highlightPath(in: rect))
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(annotation.highlightOpacity).setFill()
        path.fill()
    }

    private static func drawMosaic(in rect: CGRect, from baseImage: CGImage, intensity: CGFloat) {
        let clipped = rect.integral
        guard clipped.width > 2, clipped.height > 2,
              let crop = baseImage.cropping(to: clipped) else {
            NSColor.black.withAlphaComponent(0.28).setFill()
            rect.fill()
            return
        }

        let divisor = max(4, min(28, 4 + intensity * 24))
        let smallSize = CGSize(width: max(1, clipped.width / divisor), height: max(1, clipped.height / divisor))
        let small = NSImage(size: smallSize)
        small.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: crop, size: smallSize).draw(in: CGRect(origin: .zero, size: smallSize))
        small.unlockFocus()

        NSGraphicsContext.current?.imageInterpolation = .none
        small.draw(in: clipped)
        NSGraphicsContext.current?.imageInterpolation = .default
    }

    private static func drawArrow(from start: CGPoint, control: CGPoint, to end: CGPoint, width: CGFloat, color: NSColor) {
        let shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.curve(to: end, controlPoint1: control, controlPoint2: control)
        stroke(shaft, width: width, color: color)

        let angle = atan2(end.y - control.y, end.x - control.x)
        let length = max(18, width * 5)
        let spread: CGFloat = 0.55
        let left = CGPoint(x: end.x - cos(angle - spread) * length, y: end.y - sin(angle - spread) * length)
        let right = CGPoint(x: end.x - cos(angle + spread) * length, y: end.y - sin(angle + spread) * length)
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: left)
        head.move(to: end)
        head.line(to: right)
        stroke(head, width: width, color: color)
    }

    private static func defaultControl(start: CGPoint, end: CGPoint) -> CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }
}
