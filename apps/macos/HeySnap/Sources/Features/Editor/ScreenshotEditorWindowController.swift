import AppKit
import CoreGraphics
import QuartzCore
import SwiftUI

@MainActor
final class ScreenshotEditorWindowController: NSWindowController, NSWindowDelegate {
    private let screenshotService: ScreenshotService
    private let editorView: ScreenshotEditorView
    var onClose: ((ScreenshotEditorWindowController) -> Void)?

    init(image: CGImage, sourceScaleFactor: CGFloat, screenshotService: ScreenshotService) {
        self.screenshotService = screenshotService
        self.editorView = ScreenshotEditorView(image: image, sourceScaleFactor: sourceScaleFactor)

        let contentController = ScreenshotEditorViewController(
            editorView: editorView,
            sourceScaleFactor: sourceScaleFactor,
            screenshotService: screenshotService
        )
        let window = NSWindow(contentViewController: contentController)
        window.title = "HeySnap Editor"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 900, height: 560)
        window.setContentSize(NSSize(width: 1180, height: 740))
        contentController.configureToolbar(in: window)
        Self.centerWindowOnActiveScreen(window)
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        (window?.contentViewController as? ScreenshotEditorViewController)?.cancelTextRecognition()
        onClose?(self)
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        editorView.undoManager
    }

    private static func centerWindowOnActiveScreen(_ window: NSWindow) {
        guard let screen = screenUnderMouseOrNearest() else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let windowFrame = window.frame
        let origin = CGPoint(
            x: clampedCenteredOrigin(
                windowLength: windowFrame.width,
                visibleMin: visibleFrame.minX,
                visibleMax: visibleFrame.maxX
            ),
            y: clampedCenteredOrigin(
                windowLength: windowFrame.height,
                visibleMin: visibleFrame.minY,
                visibleMax: visibleFrame.maxY
            )
        )
        window.setFrameOrigin(origin)
    }

    private static func screenUnderMouseOrNearest() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return NSScreen.main
        }

        let mouseLocation = NSEvent.mouseLocation
        if let screen = screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }

        return screens.min { lhs, rhs in
            distanceSquared(from: mouseLocation, to: lhs.frame.center) <
                distanceSquared(from: mouseLocation, to: rhs.frame.center)
        } ?? NSScreen.main
    }

    private static func clampedCenteredOrigin(windowLength: CGFloat, visibleMin: CGFloat, visibleMax: CGFloat) -> CGFloat {
        let centeredOrigin = visibleMin + ((visibleMax - visibleMin) - windowLength) / 2
        let maximumOrigin = visibleMax - windowLength

        guard maximumOrigin >= visibleMin else {
            return visibleMin
        }

        return min(max(centeredOrigin, visibleMin), maximumOrigin)
    }

    private static func distanceSquared(from point: CGPoint, to other: CGPoint) -> CGFloat {
        let dx = point.x - other.x
        let dy = point.y - other.y
        return dx * dx + dy * dy
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private extension NSColor {
    var editorHexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(
            format: "#%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }

    convenience init?(editorHexString: String) {
        let trimmed = editorHexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6,
              let value = Int(trimmed, radix: 16) else {
            return nil
        }
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

private extension NSEdgeInsets {
    var horizontal: CGFloat { left + right }
    var vertical: CGFloat { top + bottom }
}

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        return path
    }
}

private extension CGImage {
    func editorColor(atViewPoint point: CGPoint, in viewSize: CGSize) -> NSColor? {
        guard width > 0, height > 0,
              viewSize.width > 0, viewSize.height > 0,
              let dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }

        let pixelX = min(max(Int((point.x / viewSize.width) * CGFloat(width)), 0), width - 1)
        let pixelY = min(max(Int((point.y / viewSize.height) * CGFloat(height)), 0), height - 1)
        let bytesPerPixel = max(bitsPerPixel / 8, 1)
        let offset = pixelY * bytesPerRow + pixelX * bytesPerPixel
        guard offset >= 0, offset + min(bytesPerPixel, 4) <= CFDataGetLength(data) else {
            return nil
        }

        let info = bitmapInfo
        let alphaInfo = CGImageAlphaInfo(rawValue: info.rawValue & CGBitmapInfo.alphaInfoMask.rawValue) ?? .none
        let byteOrder = info.intersection(.byteOrderMask)

        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var alpha: CGFloat = 1

        if bytesPerPixel >= 4 {
            let c0 = CGFloat(bytes[offset]) / 255
            let c1 = CGFloat(bytes[offset + 1]) / 255
            let c2 = CGFloat(bytes[offset + 2]) / 255
            let c3 = CGFloat(bytes[offset + 3]) / 255

            switch byteOrder {
            case .byteOrder32Little:
                blue = c0
                green = c1
                red = c2
            default:
                red = c0
                green = c1
                blue = c2
            }

            switch alphaInfo {
            case .premultipliedFirst, .first:
                if byteOrder == .byteOrder32Little {
                    alpha = c3
                } else {
                    alpha = c0
                    red = c1
                    green = c2
                    blue = c3
                }
            case .premultipliedLast, .last:
                alpha = c3
            default:
                alpha = 1
            }

            if (alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast), alpha > 0 {
                red = min(red / alpha, 1)
                green = min(green / alpha, 1)
                blue = min(blue / alpha, 1)
            }
        } else if bytesPerPixel >= 3 {
            red = CGFloat(bytes[offset]) / 255
            green = CGFloat(bytes[offset + 1]) / 255
            blue = CGFloat(bytes[offset + 2]) / 255
        } else {
            let white = CGFloat(bytes[offset]) / 255
            red = white
            green = white
            blue = white
        }

        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

private enum EditorZoomCommand {
    case zoomIn
    case zoomOut
    case fit
}

private struct EditorPreferences: Codable {
    var selectedTool: String = "select"
    var annotationColorHex: String = AnnotationDefaults.colorHex
    var lineWidth: CGFloat = AnnotationDefaults.lineWidth
    var arrowStyle: String = "single"
    var arrowCurved: Bool = false
    var textFontSize: CGFloat = AnnotationDefaults.textFontSize
    var textFilled: Bool = false
    var textColorHex: String = AnnotationDefaults.colorHex
    var textFillColorHex: String = AnnotationDefaults.colorHex
}

private enum EditorPreferencesStore {
    private static let directoryName = "HeySnap"
    private static let fileName = "EditorPreferences.json"

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func load() -> EditorPreferences {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(EditorPreferences.self, from: data)
        } catch {
            return EditorPreferences()
        }
    }

    static func save(_ preferences: EditorPreferences) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(preferences)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("HeySnap editor preferences write failed: \(error.localizedDescription)")
        }
    }
}

private enum EditorToolbarMetrics {
    static let brandWidth: CGFloat = 108
    static let brandFontSize: CGFloat = 20
    static let controlHeight: CGFloat = 26
    static let iconButtonSize: CGFloat = 28
    static let itemSpacing: CGFloat = 8
}

private enum EditorToolbarItemID {
    static let brand = NSToolbarItem.Identifier("heysnap.editor.brand")
    static let ocr = NSToolbarItem.Identifier("heysnap.editor.ocr")
    static let primaryActions = NSToolbarItem.Identifier("heysnap.editor.primaryActions")
    static let tools = NSToolbarItem.Identifier("heysnap.editor.tools")
    static let colorAndSize = NSToolbarItem.Identifier("heysnap.editor.colorAndSize")
    static let historyActions = NSToolbarItem.Identifier("heysnap.editor.historyActions")
}

private final class ToolbarColorWell: NSControl {
    var onPickRequested: (() -> Void)?
    var color: NSColor = .systemRed {
        didSet {
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 26, height: 26)
    }

    override func mouseDown(with event: NSEvent) {
        onPickRequested?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let side = max(1, min(bounds.width, bounds.height) - 2)
        let rect = CGRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
        let path = NSBezierPath(ovalIn: rect)
        color.setFill()
        path.fill()

        NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private struct EditorToolSwitcher: View {
    let selectedTool: EditorTool
    let selectTool: (EditorTool) -> Void

    @Namespace private var selectionNamespace
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                content
                    .padding(5)
                    .glassEffect(.regular, in: Capsule())
            } else {
                content
                    .padding(5)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .offset(y: 2)
        .animation(selectionAnimation, value: selectedTool)
    }

    private var content: some View {
        HStack(spacing: 8) {
            ForEach(EditorTool.allCases, id: \.self) { tool in
                EditorToolSwitcherButton(
                    tool: tool,
                    isSelected: tool == selectedTool,
                    namespace: selectionNamespace,
                    selectedFillOpacity: selectedFillOpacity,
                    hoverFillOpacity: hoverFillOpacity
                ) {
                    selectTool(tool)
                }
            }
        }
    }

    private var selectionAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: 0.16)
    }

    private var selectedFillOpacity: Double {
        controlActiveState == .inactive ? 0.08 : 0.13
    }

    private var hoverFillOpacity: Double {
        controlActiveState == .inactive ? 0.03 : 0.06
    }
}

private struct EditorToolSwitcherButton: View {
    let tool: EditorTool
    let isSelected: Bool
    let namespace: Namespace.ID
    let selectedFillOpacity: Double
    let hoverFillOpacity: Double
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(width: 36, height: 30)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.primary.opacity(selectedFillOpacity))
                            .matchedGeometryEffect(id: "editor-tool-selection", in: namespace)
                    } else if isHovering {
                        Capsule()
                            .fill(Color.primary.opacity(hoverFillOpacity))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(tool.title)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct EditorToolbarActionGroup: View {
    let actions: [EditorToolbarAction]

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                content
                    .padding(5)
                    .glassEffect(.regular, in: Capsule())
            } else {
                content
                    .padding(5)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .offset(y: 2)
    }

    private var content: some View {
        HStack(spacing: 8) {
            ForEach(actions) { action in
                EditorToolbarActionButton(action: action)
            }
        }
    }
}

private struct EditorToolbarAction: Identifiable {
    let id: String
    let title: String
    let symbolName: String
    let perform: () -> Void
}

private struct EditorToolbarActionButton: View {
    let action: EditorToolbarAction

    @State private var isHovering = false
    @State private var showsTooltip = false
    @State private var tooltipTask: Task<Void, Never>?
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        Button(action: action.perform) {
            Image(systemName: action.symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 30, height: 30)
                .background {
                    if isHovering {
                        Capsule()
                            .fill(Color.primary.opacity(hoverFillOpacity))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showsTooltip {
                Text(action.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                    .fixedSize()
                    .offset(y: 32)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(showsTooltip ? 1 : 0)
        .onHover { hovering in
            isHovering = hovering
            hovering ? scheduleTooltip() : hideTooltip()
        }
        .accessibilityLabel(action.title)
    }

    private var hoverFillOpacity: Double {
        controlActiveState == .inactive ? 0.03 : 0.06
    }

    private func scheduleTooltip() {
        tooltipTask?.cancel()
        tooltipTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.08)) {
                showsTooltip = true
            }
        }
    }

    private func hideTooltip() {
        tooltipTask?.cancel()
        tooltipTask = nil
        showsTooltip = false
    }
}

@MainActor
private final class ScreenshotEditorViewController: NSViewController, NSToolbarDelegate {
    private let editorView: ScreenshotEditorView
    private let sourceScaleFactor: CGFloat
    private let screenshotService: ScreenshotService
    private var toolbarItemIdentifiers: [NSToolbarItem.Identifier] = []
    private var selectedToolbarTool: EditorTool
    private weak var toolSwitcherHostingView: NSHostingView<EditorToolSwitcher>?
    private let colorWell = ToolbarColorWell()
    private let sizeSlider = NSSlider(value: 5, minValue: 1, maxValue: 28, target: nil, action: nil)
    private let sizeLabel = NSTextField(labelWithString: "5 px")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let imageSizeLabel = NSTextField(labelWithString: "")
    private weak var editorScrollView: EditorScrollView?
    private var arrowBar: ArrowPropertyBar?
    private var textBar: TextPropertyBar?
    private var shapeBar: ShapePropertyBar?
    private var didApplyInitialFit = false
    private var wheelZoomAccumulator: CGFloat = 0
    private weak var ocrToolbarItem: NSToolbarItem?
    private var ocrTask: Task<Void, Never>?
    private let ocrStatusLabel = NSTextField(labelWithString: "")
    private var ocrNoticeWorkItem: DispatchWorkItem?

    private let minimumZoom: CGFloat = 0.12
    private let maximumZoom: CGFloat = 4
    private let zoomStepFactor: CGFloat = 1.08

    init(editorView: ScreenshotEditorView, sourceScaleFactor: CGFloat, screenshotService: ScreenshotService) {
        self.editorView = editorView
        self.sourceScaleFactor = sourceScaleFactor
        self.screenshotService = screenshotService
        self.selectedToolbarTool = editorView.selectedTool
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 1).cgColor

        let scrollView = EditorScrollView()
        let clipView = EditorCheckerboardClipView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView = clipView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = minimumZoom
        scrollView.maxMagnification = maximumZoom
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = editorView
        scrollView.onWheelZoom = { [weak self, weak scrollView] event in
            guard let self, let scrollView else { return false }
            return self.handleWheelZoom(event, in: scrollView)
        }
        scrollView.onPinchZoom = { [weak self, weak scrollView] event in
            guard let self, let scrollView else { return }
            self.handlePinchZoom(event, in: scrollView)
        }
        editorScrollView = scrollView

        let arrowBar = ArrowPropertyBar()
        arrowBar.translatesAutoresizingMaskIntoConstraints = false
        arrowBar.isHidden = true
        arrowBar.onColorChange = { [weak self] color in self?.editorView.applyArrowColor(color) }
        arrowBar.onLineWidthChange = { [weak self] width in self?.editorView.applyArrowLineWidth(width) }
        arrowBar.onStyleChange = { [weak self] style in self?.editorView.applyArrowStyle(style) }
        arrowBar.onCurvedChange = { [weak self] curved in self?.editorView.applyArrowCurved(curved) }
        self.arrowBar = arrowBar

        let textBar = TextPropertyBar()
        textBar.translatesAutoresizingMaskIntoConstraints = false
        textBar.isHidden = true
        textBar.onTextColorChange = { [weak self] color in self?.editorView.applyTextColor(color) }
        textBar.onFontSizeChange = { [weak self] size in self?.editorView.applyTextFontSize(size) }
        textBar.onBoxStyleChange = { [weak self] filled in self?.editorView.applyTextFilledStyle(filled) }
        textBar.onFillColorChange = { [weak self] color in self?.editorView.applyTextFillColor(color) }
        self.textBar = textBar

        let shapeBar = ShapePropertyBar()
        shapeBar.translatesAutoresizingMaskIntoConstraints = false
        shapeBar.isHidden = true
        shapeBar.onColorChange = { [weak self] color in self?.editorView.applyShapeColor(color) }
        shapeBar.onLineWidthChange = { [weak self] width in self?.editorView.applyShapeLineWidth(width) }
        self.shapeBar = shapeBar

        view.addSubview(scrollView)
        view.addSubview(arrowBar)
        view.addSubview(textBar)
        view.addSubview(shapeBar)
        ocrStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        ocrStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        ocrStatusLabel.alignment = .center
        ocrStatusLabel.drawsBackground = true
        ocrStatusLabel.backgroundColor = .controlBackgroundColor
        ocrStatusLabel.wantsLayer = true
        ocrStatusLabel.layer?.cornerRadius = 6
        ocrStatusLabel.isHidden = true
        view.addSubview(ocrStatusLabel)

        NSLayoutConstraint.activate([
            ocrStatusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ocrStatusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            ocrStatusLabel.heightAnchor.constraint(equalToConstant: 28),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            arrowBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            arrowBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),

            textBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),

            shapeBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            shapeBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 16)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        editorView.onSelectionChange = { [weak self] tool in
            self?.syncSelectedTool(tool)
        }
        editorView.onZoomCommand = { [weak self] command in
            self?.handleZoomCommand(command)
        }
        editorView.onImageSizeChange = { [weak self] size in
            self?.updateImageSizeLabel(size)
        }
        editorView.onArrowContext = { [weak self] context in
            self?.updateArrowBar(with: context)
        }
        editorView.onTextContext = { [weak self] context in
            self?.updateTextBar(with: context)
        }
        editorView.onShapeContext = { [weak self] context in
            self?.updateShapeBar(with: context)
        }
        editorView.onColorPickPreview = { [weak self] color in
            self?.colorWell.color = color
        }
        colorWell.color = editorView.currentColor
        sizeSlider.doubleValue = Double(editorView.lineWidth)
        sizeLabel.stringValue = "\(Int(editorView.lineWidth)) px"
        updateImageSizeLabel(editorView.imagePixelSize)
        syncSelectedTool(editorView.selectedTool)
    }

    func configureToolbar(in window: NSWindow) {
        buildToolbarControlsIfNeeded()

        let toolbar = NSToolbar(identifier: "heysnap.editor.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false

        toolbarItemIdentifiers = [
            EditorToolbarItemID.brand,
            EditorToolbarItemID.ocr,
            EditorToolbarItemID.primaryActions,
            .space
        ] + [
            EditorToolbarItemID.tools,
            .space,
            EditorToolbarItemID.colorAndSize,
            EditorToolbarItemID.historyActions
        ]

        window.toolbar = toolbar
        window.toolbar?.isVisible = true
        syncSelectedTool(editorView.selectedTool)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyInitialFitIfNeeded()
    }

    private func buildToolbarControlsIfNeeded() {
        colorWell.onPickRequested = { [weak self] in
            self?.editorView.beginColorPicking()
        }
        colorWell.toolTip = "Pick color from image"
        colorWell.widthAnchor.constraint(equalToConstant: 26).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: EditorToolbarMetrics.controlHeight).isActive = true

        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        sizeSlider.numberOfTickMarks = 6
        sizeSlider.widthAnchor.constraint(equalToConstant: 92).isActive = true
        sizeLabel.alignment = .right
        sizeLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        zoomLabel.alignment = .center
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarItemIdentifiers
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarItemIdentifiers
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case EditorToolbarItemID.brand:
            return viewToolbarItem(identifier: itemIdentifier, label: "HeySnap", view: brandView())
        case EditorToolbarItemID.ocr:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "OCR"
            item.paletteLabel = "Recognize Text"
            item.toolTip = "Recognize screenshot text and copy"
            item.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "OCR")
            item.target = self
            item.action = #selector(recognizeText)
            item.autovalidates = false
            item.visibilityPriority = .high
            ocrToolbarItem = item
            return item
        case EditorToolbarItemID.primaryActions:
            return viewToolbarItem(identifier: itemIdentifier, label: "Copy and Save", view: primaryActionGroupView())
        case EditorToolbarItemID.tools:
            return viewToolbarItem(identifier: itemIdentifier, label: "Tools", view: toolGroupView())
        case EditorToolbarItemID.colorAndSize:
            let stack = NSStackView(views: [colorWell, sizeSlider, sizeLabel])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = EditorToolbarMetrics.itemSpacing
            return viewToolbarItem(identifier: itemIdentifier, label: "Style", view: stack)
        case EditorToolbarItemID.historyActions:
            return viewToolbarItem(identifier: itemIdentifier, label: "Undo and Redo", view: historyActionGroupView())
        default:
            return nil
        }
    }

    private func viewToolbarItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        view: NSView
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.view = view
        return item
    }

    private func brandView() -> NSView {
        let label = NSTextField(labelWithString: "HeySnap")
        label.font = NSFont.systemFont(ofSize: EditorToolbarMetrics.brandFontSize, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .left
        label.widthAnchor.constraint(equalToConstant: EditorToolbarMetrics.brandWidth).isActive = true
        return label
    }

    private func primaryActionGroupView() -> NSView {
        NSHostingView(rootView: EditorToolbarActionGroup(actions: [
            EditorToolbarAction(id: "copy", title: "Copy", symbolName: "doc.on.doc") { [weak self] in
                self?.copyImage()
            },
            EditorToolbarAction(id: "save", title: "Save", symbolName: "square.and.arrow.down") { [weak self] in
                self?.saveImage()
            }
        ]))
    }

    private func historyActionGroupView() -> NSView {
        NSHostingView(rootView: EditorToolbarActionGroup(actions: [
            EditorToolbarAction(id: "undo", title: "Undo", symbolName: "arrow.uturn.backward") { [weak self] in
                self?.undo()
            },
            EditorToolbarAction(id: "redo", title: "Redo", symbolName: "arrow.uturn.forward") { [weak self] in
                self?.redo()
            }
        ]))
    }

    private func toolGroupView() -> NSView {
        let view = makeToolSwitcherView(selectedTool: editorView.selectedTool)
        let hostingView = NSHostingView(rootView: view)
        toolSwitcherHostingView = hostingView
        return hostingView
    }

    private func metricView(valueLabel: NSTextField, caption: String, width: CGFloat) -> NSView {
        let captionLabel = NSTextField(labelWithString: caption)
        captionLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        captionLabel.textColor = .secondaryLabelColor
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .center

        let stack = NSStackView(views: [valueLabel, captionLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        return stack
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.alphaValue = 0.45
        box.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return box
    }

    private func syncSelectedTool(_ tool: EditorTool) {
        selectedToolbarTool = tool
        toolSwitcherHostingView?.rootView = makeToolSwitcherView(selectedTool: tool)
    }

    private func makeToolSwitcherView(selectedTool: EditorTool) -> EditorToolSwitcher {
        EditorToolSwitcher(selectedTool: selectedTool) { [weak self] tool in
            self?.selectTool(tool)
        }
    }

    private func selectTool(_ tool: EditorTool) {
        editorView.selectedTool = tool
        editorView.persistToolSelectionForCurrentTool()
        colorWell.color = editorView.currentColor
        sizeSlider.doubleValue = Double(editorView.lineWidth)
        sizeLabel.stringValue = "\(Int(editorView.lineWidth)) px"
        syncSelectedTool(editorView.selectedTool)
    }

    @objc private func colorChanged() {
        editorView.currentColor = colorWell.color
        editorView.persistColorForCurrentTool()
    }

    @objc private func sizeChanged() {
        editorView.lineWidth = CGFloat(sizeSlider.doubleValue.rounded())
        editorView.persistLineWidth()
        sizeLabel.stringValue = "\(Int(editorView.lineWidth)) px"
    }

    @objc private func undo() {
        editorView.undoManager?.undo()
    }

    @objc private func redo() {
        editorView.undoManager?.redo()
    }

    private func applyInitialFitIfNeeded() {
        guard !didApplyInitialFit, let scrollView = editorScrollView else {
            return
        }

        view.layoutSubtreeIfNeeded()
        let clipSize = scrollView.contentView.bounds.size
        guard clipSize.width > 1, clipSize.height > 1, editorView.bounds.width > 1, editorView.bounds.height > 1 else {
            DispatchQueue.main.async { [weak self] in
                self?.applyInitialFitIfNeeded()
            }
            return
        }

        didApplyInitialFit = true
        fitImageToWindow()
    }

    private func handleWheelZoom(_ event: NSEvent, in scrollView: NSScrollView) -> Bool {
        // Trackpad two-finger scroll pans the canvas; pinch is
        // handled separately as zoom. A traditional mouse wheel has no pinch, so
        // it keeps scroll-to-zoom.
        if event.hasPreciseScrollingDeltas {
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard dx != 0 || dy != 0 else {
                return true
            }
            panDocument(byClipDelta: CGSize(width: dx, height: dy))
            return true
        }

        let dominantDelta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
            ? event.scrollingDeltaY
            : event.scrollingDeltaX
        guard dominantDelta != 0 else {
            return false
        }

        let threshold: CGFloat = 3
        wheelZoomAccumulator += dominantDelta
        let steps = Int(wheelZoomAccumulator / threshold)
        guard steps != 0 else {
            return true
        }

        wheelZoomAccumulator -= CGFloat(steps) * threshold
        zoom(bySteps: steps, centeredAt: documentPoint(for: event, in: scrollView))
        return true
    }

    private func handlePinchZoom(_ event: NSEvent, in scrollView: NSScrollView) {
        guard event.magnification != 0 else {
            return
        }
        let target = clampedZoom(scrollView.magnification * (1 + event.magnification))
        setZoom(target, centeredAt: documentPoint(for: event, in: scrollView))
    }

    private func handleZoomCommand(_ command: EditorZoomCommand) {
        switch command {
        case .zoomIn:
            zoom(bySteps: 1, centeredAt: visibleDocumentCenter())
        case .zoomOut:
            zoom(bySteps: -1, centeredAt: visibleDocumentCenter())
        case .fit:
            fitImageToWindow()
        }
    }

    private func fitImageToWindow() {
        guard let scrollView = editorScrollView else {
            return
        }

        let clipSize = scrollView.contentView.bounds.size
        guard clipSize.width > 1, clipSize.height > 1 else {
            return
        }

        let fitScale = min(
            clipSize.width / editorView.bounds.width,
            clipSize.height / editorView.bounds.height
        ) * 0.96
        let target = clampedZoom(min(1, fitScale))
        setZoom(target, centeredAt: imageCenter)
    }

    private func zoom(bySteps steps: Int, centeredAt center: CGPoint) {
        guard let scrollView = editorScrollView else {
            return
        }

        let factor = pow(zoomStepFactor, CGFloat(steps))
        setZoom(clampedZoom(scrollView.magnification * factor), centeredAt: center)
    }

    private func setZoom(_ zoom: CGFloat, centeredAt center: CGPoint) {
        guard let scrollView = editorScrollView else {
            return
        }

        let normalized = clampedZoom(zoom)
        scrollView.setMagnification(normalized, centeredAt: center)
        scrollView.contentView.needsLayout = true
        updateZoomLabel(normalized)
    }

    private func panDocument(byClipDelta delta: CGSize) {
        guard let scrollView = editorScrollView else {
            return
        }

        let magnification = max(scrollView.magnification, 0.0001)
        let currentOrigin = scrollView.contentView.bounds.origin
        let targetOrigin = CGPoint(
            x: currentOrigin.x - delta.width / magnification,
            y: currentOrigin.y - delta.height / magnification
        )
        scrollView.contentView.scroll(to: targetOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func clampedZoom(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, minimumZoom), maximumZoom)
    }

    private func updateZoomLabel(_ zoom: CGFloat) {
        zoomLabel.stringValue = "\(Int((zoom * 100).rounded()))%"
    }

    private func updateImageSizeLabel(_ size: CGSize) {
        imageSizeLabel.stringValue = "\(Int(size.width))x\(Int(size.height)) px"
    }

    private func updateArrowBar(with context: ScreenshotEditorView.ArrowContext?) {
        guard let arrowBar else { return }
        if let context {
            arrowBar.configure(color: context.color, lineWidth: context.lineWidth, style: context.style, curved: context.curved)
            arrowBar.isHidden = false
            textBar?.isHidden = true
            shapeBar?.isHidden = true
        } else {
            arrowBar.isHidden = true
        }
    }

    private func updateTextBar(with context: ScreenshotEditorView.TextContext?) {
        guard let textBar else { return }
        if let context {
            textBar.configure(
                textColor: context.color,
                fontSize: context.fontSize,
                fillColor: context.fillColor,
                filled: context.fillColor.alphaComponent > 0
            )
            textBar.isHidden = false
            arrowBar?.isHidden = true
            shapeBar?.isHidden = true
        } else {
            textBar.isHidden = true
        }
    }

    private func updateShapeBar(with context: ScreenshotEditorView.ShapeContext?) {
        guard let shapeBar else { return }
        if let context {
            shapeBar.configure(color: context.color, lineWidth: context.lineWidth)
            shapeBar.isHidden = false
            arrowBar?.isHidden = true
            textBar?.isHidden = true
        } else {
            shapeBar.isHidden = true
        }
    }

    private func documentPoint(for event: NSEvent, in scrollView: NSScrollView) -> CGPoint {
        let pointInClipView = scrollView.contentView.convert(event.locationInWindow, from: nil)
        return editorView.convert(pointInClipView, from: scrollView.contentView)
    }

    private func visibleDocumentCenter() -> CGPoint {
        guard let scrollView = editorScrollView else {
            return imageCenter
        }

        return CGPoint(
            x: scrollView.contentView.bounds.midX,
            y: scrollView.contentView.bounds.midY
        )
    }

    private var imageCenter: CGPoint {
        CGPoint(x: editorView.bounds.midX, y: editorView.bounds.midY)
    }

    @objc private func recognizeText() {
        guard ocrTask == nil else { return }
        let image = editorView.imageForTextRecognition()
        ocrToolbarItem?.isEnabled = false
        showOCRNotice("Recognizing text…", dismiss: false)
        ocrTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ScreenshotTextRecognizer.recognize(image) }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.ocrTask = nil
            self.ocrToolbarItem?.isEnabled = true
            switch result {
            case .success(let text) where text.isEmpty:
                self.showOCRNotice("No text found")
            case .success(let text):
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                if pasteboard.setString(text, forType: .string) {
                    self.showOCRNotice("Text copied to clipboard")
                    AppLogger.info("OCR text copied to clipboard.")
                } else {
                    self.showOCRNotice("Could not copy text")
                    AppLogger.error("OCR clipboard write failed.")
                }
            case .failure(let error):
                self.showOCRNotice("Could not recognize text")
                AppLogger.error("OCR failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelTextRecognition() {
        ocrTask?.cancel()
        ocrTask = nil
        ocrNoticeWorkItem?.cancel()
    }

    private func showOCRNotice(_ message: String, dismiss: Bool = true) {
        ocrNoticeWorkItem?.cancel()
        ocrStatusLabel.stringValue = "  \(message)  "
        ocrStatusLabel.isHidden = false
        guard dismiss else { return }
        let item = DispatchWorkItem { [weak self] in self?.ocrStatusLabel.isHidden = true }
        ocrNoticeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
    }

    @objc private func copyImage() {
        guard let image = editorView.renderedImage(),
              let pngData = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
    }

    @objc private func saveImage() {
        guard let image = editorView.renderedImage() else {
            NSSound.beep()
            return
        }

        do {
            let url = try screenshotService.saveEditedImage(image, sourceScaleFactor: sourceScaleFactor)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            screenshotService.publishStatus(.failure(error.localizedDescription))
            NSSound.beep()
        }
    }
}

private final class EditorScrollView: NSScrollView {
    var onWheelZoom: ((NSEvent) -> Bool)?
    var onPinchZoom: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if onWheelZoom?(event) == true {
            return
        }

        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        onPinchZoom?(event)
    }
}

// Floating contextual bar for editing the selected arrow's color, thickness,
// and head style. Shown at the top-right of the canvas while an arrow is selected.
@MainActor
private final class ArrowPropertyBar: NSVisualEffectView {
    var onColorChange: ((NSColor) -> Void)?
    var onLineWidthChange: ((CGFloat) -> Void)?
    var onStyleChange: ((AnnotationArrowStyle) -> Void)?
    var onCurvedChange: ((Bool) -> Void)?

    private let colorWell = NSColorWell()
    private let widthSlider = NSSlider(value: 5, minValue: 1, maxValue: 28, target: nil, action: nil)
    private let styleControl = NSSegmentedControl()
    private let curveToggle = NSButton(checkboxWithTitle: "Curve", target: nil, action: nil)
    private let styles = AnnotationArrowStyle.allCases

    init() {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(color: NSColor, lineWidth: CGFloat, style: AnnotationArrowStyle, curved: Bool) {
        colorWell.color = color
        widthSlider.doubleValue = Double(lineWidth)
        styleControl.selectedSegment = styles.firstIndex(of: style) ?? 0
        curveToggle.state = curved ? .on : .off
    }

    private func build() {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        colorWell.colorWellStyle = .minimal
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.toolTip = "Arrow color"
        // Circular swatch: square bounds + a circular layer mask.
        let colorDiameter: CGFloat = 24
        colorWell.wantsLayer = true
        colorWell.layer?.cornerRadius = colorDiameter / 2
        colorWell.layer?.masksToBounds = true
        colorWell.widthAnchor.constraint(equalToConstant: colorDiameter).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: colorDiameter).isActive = true
        stack.addArrangedSubview(colorWell)
        stack.addArrangedSubview(separator())

        widthSlider.target = self
        widthSlider.action = #selector(widthChanged)
        widthSlider.toolTip = "Thickness"
        widthSlider.widthAnchor.constraint(equalToConstant: 96).isActive = true
        stack.addArrangedSubview(widthSlider)
        stack.addArrangedSubview(separator())

        styleControl.segmentCount = styles.count
        styleControl.trackingMode = .selectOne
        styleControl.segmentStyle = .texturedRounded
        styleControl.target = self
        styleControl.action = #selector(styleChanged)
        for (index, style) in styles.enumerated() {
            styleControl.setImage(NSImage(systemSymbolName: style.symbolName, accessibilityDescription: style.title), forSegment: index)
            styleControl.setToolTip(style.title, forSegment: index)
            styleControl.setWidth(34, forSegment: index)
        }
        stack.addArrangedSubview(styleControl)
        stack.addArrangedSubview(separator())

        curveToggle.target = self
        curveToggle.action = #selector(curvedChanged)
        curveToggle.toolTip = "Draw as a curved arc"
        stack.addArrangedSubview(curveToggle)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    @objc private func colorChanged() {
        onColorChange?(colorWell.color)
    }

    @objc private func widthChanged() {
        onLineWidthChange?(CGFloat(widthSlider.doubleValue.rounded()))
    }

    @objc private func styleChanged() {
        guard styleControl.selectedSegment >= 0, styleControl.selectedSegment < styles.count else {
            return
        }
        onStyleChange?(styles[styleControl.selectedSegment])
    }

    @objc private func curvedChanged() {
        onCurvedChange?(curveToggle.state == .on)
    }
}

@MainActor
private final class TextPropertyBar: NSVisualEffectView {
    var onTextColorChange: ((NSColor) -> Void)?
    var onFontSizeChange: ((CGFloat) -> Void)?
    var onBoxStyleChange: ((Bool) -> Void)?
    var onFillColorChange: ((NSColor) -> Void)?

    private let textColorWell = NSColorWell()
    private let fillColorWell = NSColorWell()
    private let boxStyleControl = NSSegmentedControl()
    private let sizeSlider = NSSlider(value: 12, minValue: 8, maxValue: 48, target: nil, action: nil)
    private let sizeLabel = NSTextField(labelWithString: "12 pt")

    init() {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(textColor: NSColor, fontSize: CGFloat, fillColor: NSColor, filled: Bool) {
        textColorWell.color = textColor
        sizeSlider.doubleValue = Double(fontSize)
        sizeLabel.stringValue = "\(Int(fontSize.rounded())) pt"
        fillColorWell.color = fillColor.alphaComponent > 0 ? fillColor : textColor
        fillColorWell.isEnabled = filled
        boxStyleControl.selectedSegment = filled ? 1 : 0
    }

    private func build() {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        configureColorWell(textColorWell, tooltip: "Text color", action: #selector(textColorChanged))
        stack.addArrangedSubview(textColorWell)
        stack.addArrangedSubview(separator())

        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        sizeSlider.toolTip = "Font size"
        sizeSlider.widthAnchor.constraint(equalToConstant: 86).isActive = true
        stack.addArrangedSubview(sizeSlider)
        sizeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        sizeLabel.alignment = .right
        sizeLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        stack.addArrangedSubview(sizeLabel)
        stack.addArrangedSubview(separator())

        boxStyleControl.segmentCount = 2
        boxStyleControl.trackingMode = .selectOne
        boxStyleControl.segmentStyle = .texturedRounded
        boxStyleControl.target = self
        boxStyleControl.action = #selector(boxStyleChanged)
        boxStyleControl.setLabel("Normal", forSegment: 0)
        boxStyleControl.setLabel("Filled", forSegment: 1)
        boxStyleControl.setToolTip("Normal text", forSegment: 0)
        boxStyleControl.setToolTip("Filled text badge", forSegment: 1)
        boxStyleControl.setWidth(62, forSegment: 0)
        boxStyleControl.setWidth(56, forSegment: 1)
        stack.addArrangedSubview(boxStyleControl)
        configureColorWell(fillColorWell, tooltip: "Fill color", action: #selector(fillColorChanged))
        stack.addArrangedSubview(fillColorWell)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func configureColorWell(_ well: NSColorWell, tooltip: String, action: Selector) {
        well.colorWellStyle = .minimal
        well.target = self
        well.action = action
        well.toolTip = tooltip
        let diameter: CGFloat = 24
        well.wantsLayer = true
        well.layer?.cornerRadius = diameter / 2
        well.layer?.masksToBounds = true
        well.widthAnchor.constraint(equalToConstant: diameter).isActive = true
        well.heightAnchor.constraint(equalToConstant: diameter).isActive = true
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    @objc private func textColorChanged() {
        onTextColorChange?(textColorWell.color)
    }

    @objc private func sizeChanged() {
        let value = CGFloat(sizeSlider.doubleValue.rounded())
        sizeLabel.stringValue = "\(Int(value)) pt"
        onFontSizeChange?(value)
    }

    @objc private func boxStyleChanged() {
        let filled = boxStyleControl.selectedSegment == 1
        fillColorWell.isEnabled = filled
        onBoxStyleChange?(filled)
    }

    @objc private func fillColorChanged() {
        guard boxStyleControl.selectedSegment == 1 else { return }
        onFillColorChange?(fillColorWell.color)
    }
}

@MainActor
private final class ShapePropertyBar: NSVisualEffectView {
    var onColorChange: ((NSColor) -> Void)?
    var onLineWidthChange: ((CGFloat) -> Void)?

    private let colorWell = NSColorWell()
    private let widthSlider = NSSlider(value: 5, minValue: 1, maxValue: 28, target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(color: NSColor, lineWidth: CGFloat) {
        colorWell.color = color
        widthSlider.doubleValue = Double(lineWidth)
    }

    private func build() {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        colorWell.colorWellStyle = .minimal
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.toolTip = "Shape color"
        let diameter: CGFloat = 24
        colorWell.wantsLayer = true
        colorWell.layer?.cornerRadius = diameter / 2
        colorWell.layer?.masksToBounds = true
        colorWell.widthAnchor.constraint(equalToConstant: diameter).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: diameter).isActive = true
        stack.addArrangedSubview(colorWell)

        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)

        widthSlider.target = self
        widthSlider.action = #selector(widthChanged)
        widthSlider.toolTip = "Shape stroke width"
        widthSlider.widthAnchor.constraint(equalToConstant: 96).isActive = true
        stack.addArrangedSubview(widthSlider)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @objc private func colorChanged() {
        onColorChange?(colorWell.color)
    }

    @objc private func widthChanged() {
        onLineWidthChange?(CGFloat(widthSlider.doubleValue.rounded()))
    }
}

private final class EditorCheckerboardClipView: NSClipView {
    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        // Preserve the document point currently at the viewport center so the
        // image stays visually anchored while the surrounding window resizes.
        let oldCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        let hadSize = bounds.width > 1 && bounds.height > 1
        super.setFrameSize(newSize)
        guard hadSize else {
            return
        }

        let targetOrigin = CGPoint(
            x: oldCenter.x - bounds.width / 2,
            y: oldCenter.y - bounds.height / 2
        )
        let constrained = constrainBoundsRect(NSRect(origin: targetOrigin, size: bounds.size))
        if constrained.origin != bounds.origin {
            scroll(to: constrained.origin)
            enclosingScrollView?.reflectScrolledClipView(self)
        }
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else {
            return rect
        }

        // When the document is smaller than the viewport, keep it centered by
        // pinning the scroll origin instead of moving the document frame. This
        // holds the image steady as the window resizes.
        let docFrame = documentView.frame
        if rect.width >= docFrame.width {
            rect.origin.x = floor((docFrame.width - rect.width) / 2)
        }
        if rect.height >= docFrame.height {
            rect.origin.y = floor((docFrame.height - rect.height) / 2)
        }
        return rect
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawEditorCheckerboard(in: dirtyRect)
    }

    // Clicks that land on the checkerboard margin (outside the image) forward to
    // the document view so a crop/select marquee can start from empty canvas,
    // which makes edge/corner selections intuitive.
    override func mouseDown(with event: NSEvent) {
        documentView?.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        documentView?.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        documentView?.mouseUp(with: event)
    }
}

private func drawEditorCheckerboard(in rect: CGRect) {
    let cellSize: CGFloat = 16
    guard let context = NSGraphicsContext.current?.cgContext else {
        return
    }
    context.saveGState()

    let minColumn = Int(floor(rect.minX / cellSize))
    let maxColumn = Int(ceil(rect.maxX / cellSize))
    let minRow = Int(floor(rect.minY / cellSize))
    let maxRow = Int(ceil(rect.maxY / cellSize))
    let light = NSColor(calibratedWhite: 0.96, alpha: 1)
    let dark = NSColor(calibratedWhite: 0.90, alpha: 1)

    // Paint the light base in one fill, then batch every dark cell into a
    // single path so the whole board costs two fills instead of one per cell.
    context.setFillColor(light.cgColor)
    context.fill(rect)

    var darkCells: [CGRect] = []
    darkCells.reserveCapacity(max(0, (maxColumn - minColumn) * (maxRow - minRow) / 2))
    for row in minRow..<maxRow {
        for column in minColumn..<maxColumn where !(row + column).isMultiple(of: 2) {
            darkCells.append(CGRect(
                x: CGFloat(column) * cellSize,
                y: CGFloat(row) * cellSize,
                width: cellSize,
                height: cellSize
            ))
        }
    }
    if !darkCells.isEmpty {
        context.setFillColor(dark.cgColor)
        context.fill(darkCells)
    }

    context.restoreGState()
}

private enum EditorTool: String, CaseIterable {
    case select
    case arrow
    case text
    case rectangle
    case oval
    case line
    case highlighter
    case blur
    case crop

    var title: String {
        switch self {
        case .select: return "Crop/Select"
        case .arrow: return "Arrow"
        case .text: return "Text"
        case .rectangle: return "Rectangle"
        case .oval: return "Oval"
        case .line: return "Line"
        case .highlighter: return "Highlighter"
        case .blur: return "Blur"
        case .crop: return "Crop"
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .rectangle: return "rectangle"
        case .oval: return "oval"
        case .line: return "line.diagonal"
        case .highlighter: return "highlighter"
        case .blur: return "checkerboard.rectangle"
        case .crop: return "crop"
        }
    }
}


private struct EditorDocumentState {
    var image: CGImage
    var annotations: [EditorAnnotation]
    // If set, undoing back to this state re-shows the crop selection so the
    // region can be tweaked and re-applied.
    var restoreCropRect: CGRect?

    init(image: CGImage, annotations: [EditorAnnotation], restoreCropRect: CGRect? = nil) {
        self.image = image
        self.annotations = annotations
        self.restoreCropRect = restoreCropRect
    }
}

@MainActor
private final class ScreenshotEditorView: NSView, NSTextViewDelegate {
    private let sourceScaleFactor: CGFloat
    var selectedTool: EditorTool = .select {
        didSet {
            onSelectionChange?(selectedTool)
        }
    }
    var currentColor: NSColor = AnnotationDefaults.color
    var lineWidth: CGFloat = AnnotationDefaults.lineWidth
    var currentArrowStyle: AnnotationArrowStyle = .single
    var currentArrowCurved: Bool = false
    var currentTextFontSize: CGFloat = AnnotationDefaults.textFontSize
    var currentTextFillColor: NSColor = .clear
    var currentTextStrokeColor: NSColor? = .controlAccentColor
    var onSelectionChange: ((EditorTool) -> Void)?
    var onZoomCommand: ((EditorZoomCommand) -> Void)?
    var onImageSizeChange: ((CGSize) -> Void)?
    // Fires with the current arrow annotation's properties when one is selected,
    // or nil when no arrow is selected, so the floating bar can show/hide/sync.
    var onArrowContext: ((ArrowContext?) -> Void)?
    var onTextContext: ((TextContext?) -> Void)?
    var onShapeContext: ((ShapeContext?) -> Void)?
    var onColorPickPreview: ((NSColor) -> Void)?

    struct ArrowContext {
        var color: NSColor
        var lineWidth: CGFloat
        var style: AnnotationArrowStyle
        var curved: Bool
    }

    struct TextContext {
        var color: NSColor
        var fontSize: CGFloat
        var fillColor: NSColor
        var strokeColor: NSColor?
    }

    struct ShapeContext {
        var color: NSColor
        var lineWidth: CGFloat
    }

    private var baseImage: CGImage {
        didSet {
            cachedImage = NSImage(cgImage: baseImage, size: NSSize(width: baseImage.width, height: baseImage.height))
        }
    }
    private var cachedImage: NSImage
    private var annotations: [EditorAnnotation] = []
    private var selectedAnnotationID: UUID? {
        didSet {
            notifySelectionContext()
            window?.invalidateCursorRects(for: self)
        }
    }
    private var activeArrowHandle: AnnotationArrowHandle?
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var dragStartAnnotations: [EditorAnnotation]?
    private var isConstrainedDrawing = false
    private var isCropSelecting = false
    private var pendingCropRect: CGRect? {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }
    private var isMovingPendingCrop = false
    private var pendingCropMoveOrigin: CGRect?
    private var activeAnnotationShapeHandle: AnnotationShapeHandle?
    private var activeShapeHandle: AnnotationShapeHandle?
    private var shapeResizeOrigin: CGRect?
    private var isMovingAnnotation = false
    private var isColorPicking = false {
        didSet {
            if oldValue != isColorPicking {
                window?.invalidateCursorRects(for: self)
            }
        }
    }
    private var colorPickPreviousColor: NSColor?
    private var colorPickCurrentColor: NSColor?
    private var trackingArea: NSTrackingArea?
    private var activeTextAnnotationID: UUID?
    private var activeTextEditor: AnnotationInlineTextView?
    private var activeTextEditorInitialState: EditorDocumentState?
    private var suppressTextInsertionOnMouseUp = false
    private var panLastPoint: CGPoint?
    private var isRenderingForExport = false
    private let editorUndoManager = UndoManager()
    private var editorPreferences = EditorPreferencesStore.load()

    init(image: CGImage, sourceScaleFactor: CGFloat) {
        self.sourceScaleFactor = max(sourceScaleFactor, 1)
        self.baseImage = image
        self.cachedImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        super.init(frame: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        applyStoredEditorPreferences()
        wantsLayer = true
        // Redraw only when the content actually changes; magnification and
        // scrolling then composite the cached layer on the GPU instead of
        // re-invoking draw() every frame, which keeps zoom/pan smooth.
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.drawsAsynchronously = true
        postsFrameChangedNotifications = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { editorUndoManager }
    var imagePixelSize: CGSize {
        CGSize(width: baseImage.width, height: baseImage.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private func applyStoredEditorPreferences() {
        if let tool = EditorTool(rawValue: editorPreferences.selectedTool) {
            selectedTool = tool
        }
        let annotationColor = NSColor(editorHexString: editorPreferences.annotationColorHex) ?? AnnotationDefaults.color
        let textColor = NSColor(editorHexString: editorPreferences.textColorHex) ?? annotationColor
        currentColor = selectedTool == .text ? textColor : annotationColor
        lineWidth = editorPreferences.lineWidth
        currentArrowStyle = AnnotationArrowStyle(rawValue: editorPreferences.arrowStyle) ?? .single
        currentArrowCurved = editorPreferences.arrowCurved
        currentTextFontSize = editorPreferences.textFontSize
        currentTextFillColor = editorPreferences.textFilled
            ? (NSColor(editorHexString: editorPreferences.textFillColorHex) ?? annotationColor)
            : .clear
        currentTextStrokeColor = .controlAccentColor
    }

    private func saveEditorPreferences() {
        EditorPreferencesStore.save(editorPreferences)
    }

    private func persistSelectedTool() {
        editorPreferences.selectedTool = selectedTool.rawValue
        saveEditorPreferences()
    }

    private func persistAnnotationDefaults() {
        editorPreferences.annotationColorHex = currentColor.editorHexString
        editorPreferences.lineWidth = lineWidth
        saveEditorPreferences()
    }

    private func persistArrowDefaults() {
        editorPreferences.arrowStyle = currentArrowStyle.rawValue
        editorPreferences.arrowCurved = currentArrowCurved
        saveEditorPreferences()
    }

    private func persistTextDefaults() {
        editorPreferences.textFontSize = currentTextFontSize
        editorPreferences.textFilled = currentTextFillColor.alphaComponent > 0
        editorPreferences.textColorHex = currentColor.editorHexString
        if currentTextFillColor.alphaComponent > 0 {
            editorPreferences.textFillColorHex = currentTextFillColor.editorHexString
        }
        saveEditorPreferences()
    }

    func persistToolSelectionForCurrentTool() {
        if selectedTool == .text {
            currentTextFontSize = editorPreferences.textFontSize
            currentTextFillColor = editorPreferences.textFilled
                ? (NSColor(editorHexString: editorPreferences.textFillColorHex) ?? currentTextFillColor)
                : .clear
            currentTextStrokeColor = .controlAccentColor
            currentColor = NSColor(editorHexString: editorPreferences.textColorHex) ?? currentColor
        } else {
            currentColor = NSColor(editorHexString: editorPreferences.annotationColorHex) ?? currentColor
            lineWidth = editorPreferences.lineWidth
            currentArrowStyle = AnnotationArrowStyle(rawValue: editorPreferences.arrowStyle) ?? currentArrowStyle
            currentArrowCurved = editorPreferences.arrowCurved
        }
        persistSelectedTool()
    }

    func persistColorForCurrentTool() {
        if selectedTool == .text {
            editorPreferences.textColorHex = currentColor.editorHexString
            saveEditorPreferences()
        } else {
            persistAnnotationDefaults()
        }
    }

    func beginColorPicking() {
        window?.makeFirstResponder(self)
        colorPickPreviousColor = currentColor
        colorPickCurrentColor = currentColor
        isColorPicking = true
        NSCursor.crosshair.set()
        onColorPickPreview?(currentColor)
    }

    private func cancelColorPicking() {
        guard isColorPicking else { return }
        if let colorPickPreviousColor {
            currentColor = colorPickPreviousColor
            onColorPickPreview?(colorPickPreviousColor)
        }
        isColorPicking = false
        colorPickPreviousColor = nil
        colorPickCurrentColor = nil
    }

    private func commitColorPickToClipboard() {
        guard isColorPicking else { return }
        let color = colorPickCurrentColor ?? currentColor
        currentColor = color
        persistColorForCurrentTool()
        onColorPickPreview?(color)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(color.editorHexString, forType: .string)

        isColorPicking = false
        colorPickPreviousColor = nil
        colorPickCurrentColor = nil
    }

    private func updatePickedColor(at point: CGPoint) {
        guard let color = baseImage.editorColor(atViewPoint: point, in: bounds.size) else {
            return
        }

        colorPickCurrentColor = color
        currentColor = color
        onColorPickPreview?(color)
    }

    func persistLineWidth() {
        persistAnnotationDefaults()
    }

    // MARK: Selection property editing (floating bars)

    private var selectedArrowIndex: Int? {
        guard let id = selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }),
              case .arrow = annotations[index].kind else {
            return nil
        }
        return index
    }

    private var selectedTextIndex: Int? {
        guard let id = selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }),
              case .text = annotations[index].kind else {
            return nil
        }
        return index
    }

    private var selectedShapeIndex: Int? {
        guard let id = selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }),
              annotations[index].isResizableShape || annotations[index].isLineAnnotation else {
            return nil
        }
        return index
    }

    private func notifySelectionContext() {
        if let index = selectedArrowIndex {
            let annotation = annotations[index]
            onArrowContext?(ArrowContext(color: annotation.color, lineWidth: annotation.lineWidth, style: annotation.arrowStyle, curved: annotation.arrowCurved))
            onTextContext?(nil)
            onShapeContext?(nil)
            return
        }

        if let index = selectedTextIndex {
            let annotation = annotations[index]
            onArrowContext?(nil)
            onTextContext?(TextContext(
                color: annotation.color,
                fontSize: annotation.textFontSize,
                fillColor: annotation.textFillColor,
                strokeColor: annotation.textStrokeColor
            ))
            onShapeContext?(nil)
            return
        }

        if let index = selectedShapeIndex {
            let annotation = annotations[index]
            onArrowContext?(nil)
            onTextContext?(nil)
            onShapeContext?(ShapeContext(color: annotation.color, lineWidth: annotation.lineWidth))
            return
        }

        onArrowContext?(nil)
        onTextContext?(nil)
        onShapeContext?(nil)
    }

    func applyArrowColor(_ color: NSColor) {
        currentColor = color
        editorPreferences.annotationColorHex = color.editorHexString
        saveEditorPreferences()
        editSelectedArrow(name: "Arrow Color") { $0.color = color }
    }

    func applyArrowLineWidth(_ width: CGFloat) {
        lineWidth = width
        editorPreferences.lineWidth = width
        saveEditorPreferences()
        editSelectedArrow(name: "Arrow Thickness") { $0.lineWidth = width }
    }

    func applyArrowStyle(_ style: AnnotationArrowStyle) {
        currentArrowStyle = style
        persistArrowDefaults()
        editSelectedArrow(name: "Arrow Style") { $0.arrowStyle = style }
    }

    func applyArrowCurved(_ curved: Bool) {
        currentArrowCurved = curved
        persistArrowDefaults()
        editSelectedArrow(name: "Arrow Curve") { $0.arrowCurved = curved }
    }

    private func editSelectedArrow(name: String, _ transform: (inout EditorAnnotation) -> Void) {
        guard let index = selectedArrowIndex else {
            return
        }
        let previousState = EditorDocumentState(image: baseImage, annotations: annotations)
        transform(&annotations[index])
        registerUndo(state: previousState, name: name)
        needsDisplay = true
        notifySelectionContext()
    }

    func applyShapeColor(_ color: NSColor) {
        currentColor = color
        editSelectedShape(name: "Shape Color") { $0.color = color }
    }

    func applyShapeLineWidth(_ width: CGFloat) {
        lineWidth = width
        editSelectedShape(name: "Shape Thickness") { $0.lineWidth = width }
    }

    private func editSelectedShape(name: String, _ transform: (inout EditorAnnotation) -> Void) {
        guard let index = selectedShapeIndex else {
            return
        }
        let previousState = EditorDocumentState(image: baseImage, annotations: annotations)
        transform(&annotations[index])
        registerUndo(state: previousState, name: name)
        needsDisplay = true
        notifySelectionContext()
    }

    func applyTextColor(_ color: NSColor) {
        currentColor = color
        editorPreferences.textColorHex = color.editorHexString
        saveEditorPreferences()
        editSelectedText(name: "Text Color") { $0.color = color }
        syncActiveTextEditorStyle()
    }

    func applyTextFontSize(_ size: CGFloat) {
        currentTextFontSize = size
        editorPreferences.textFontSize = size
        saveEditorPreferences()
        editSelectedText(name: "Text Size") { $0.textFontSize = size }
        syncActiveTextEditorStyle()
    }

    func applyTextFillColor(_ color: NSColor) {
        currentTextFillColor = color
        editorPreferences.textFillColorHex = color.editorHexString
        editorPreferences.textFilled = true
        saveEditorPreferences()
        editSelectedText(name: "Text Fill") {
            $0.textFillColor = color
            $0.textStrokeColor = .controlAccentColor
        }
        syncActiveTextEditorStyle()
    }

    func applyTextStrokeColor(_ color: NSColor?) {
        currentTextStrokeColor = color
        editSelectedText(name: "Text Stroke") { $0.textStrokeColor = color }
        syncActiveTextEditorStyle()
    }

    func applyTextFilledStyle(_ filled: Bool) {
        editSelectedText(name: "Text Style") { annotation in
            if filled {
                let baseColor = annotation.textFillColor.alphaComponent > 0 ? annotation.textFillColor : annotation.color
                let style = AnnotationTextRenderer.style(filled: true, color: annotation.color, fillColor: annotation.textFillColor)
                annotation.textFillColor = style.fill
                annotation.textStrokeColor = .controlAccentColor
                annotation.color = style.color
                currentTextFillColor = baseColor
                currentTextStrokeColor = baseColor
                currentColor = .white
                editorPreferences.textFilled = true
                editorPreferences.textFillColorHex = baseColor.editorHexString
                editorPreferences.textColorHex = NSColor.white.editorHexString
            } else {
                let baseColor = annotation.textFillColor.alphaComponent > 0 ? annotation.textFillColor : annotation.color
                let style = AnnotationTextRenderer.style(filled: false, color: annotation.color, fillColor: annotation.textFillColor)
                annotation.color = style.color
                annotation.textFillColor = style.fill
                annotation.textStrokeColor = .controlAccentColor
                currentTextFillColor = .clear
                currentTextStrokeColor = .controlAccentColor
                currentColor = baseColor
                editorPreferences.textFilled = false
                editorPreferences.textColorHex = baseColor.editorHexString
            }
            saveEditorPreferences()
        }
        syncActiveTextEditorStyle()
    }

    private func editSelectedText(name: String, _ transform: (inout EditorAnnotation) -> Void) {
        guard let index = selectedTextIndex else {
            return
        }
        let previousState = EditorDocumentState(image: baseImage, annotations: annotations)
        transform(&annotations[index])
        registerUndo(state: previousState, name: name)
        autosizeTextAnnotation(at: index)
        needsDisplay = true
        notifySelectionContext()
    }

    private func syncActiveTextEditorStyle() {
        guard let editor = activeTextEditor,
              let id = activeTextAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }) else {
            return
        }
        let annotation = annotations[index]
        editor.layer?.cornerRadius = textCornerRadius
        editor.layer?.borderColor = NSColor.clear.cgColor
        editor.layer?.borderWidth = 0
        editor.layer?.backgroundColor = annotation.textFillColor.cgColor
        editor.frame = annotation.rect
        applyTextEditorAttributes(editor, annotation: annotation)
        updateTextEditorSelectionRing(editor, annotation: annotation)
        syncTextEditorContainer(editor)
    }

    private func updateTextEditorSelectionRing(_ editor: AnnotationInlineTextView, annotation: EditorAnnotation) {
        AnnotationTextRenderer.updateSelectionRing(editor, scale: sourceScaleFactor, magnification: currentMagnification)
    }

    private func applyTextEditorAttributes(_ editor: NSTextView, annotation: EditorAnnotation) {
        guard let editor = editor as? AnnotationInlineTextView else { return }
        AnnotationTextRenderer.configure(editor, color: annotation.color, fillColor: annotation.textFillColor, fontSize: annotation.textFontSize, scale: sourceScaleFactor, magnification: currentMagnification)
    }

    private func textLineHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    private func syncTextEditorContainer(_ editor: NSTextView) {
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: max(editor.bounds.height, 1)
        )
    }

    // Current zoom of the enclosing scroll view; used to keep interactive
    // handles a constant size on screen regardless of magnification.
    private var currentMagnification: CGFloat {
        max(enclosingScrollView?.magnification ?? 1, 0.0001)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        // AppKit throws on a null/empty/non-finite cursor rect, which can happen
        // when a dragged shape moves partly outside bounds. Guard every add.
        func addCursor(_ rect: CGRect, _ cursor: NSCursor) {
            let clipped = rect.intersection(bounds)
            guard !clipped.isNull, !clipped.isEmpty,
                  clipped.origin.x.isFinite, clipped.origin.y.isFinite,
                  clipped.width.isFinite, clipped.height.isFinite else {
                return
            }
            addCursorRect(clipped, cursor: cursor)
        }

        if isColorPicking {
            addCursor(bounds, .crosshair)
            return
        }

        if let pendingCropRect {
            // Move cursor inside the selection, resize cursors on the 8 handles.
            addCursor(pendingCropRect, .editorMove)

            let radius = cropHandleHitRadius
            for handle in AnnotationShapeHandle.allCases {
                let anchor = handle.point(in: pendingCropRect)
                let handleRect = CGRect(
                    x: anchor.x - radius,
                    y: anchor.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                addCursor(handleRect, handle.resizeCursor)
            }
            return
        }

        // Over the body of a selected arrow (off its three knobs), show the
        // four-way move cursor to signal it can be dragged.
        if let id = selectedAnnotationID,
           let annotation = annotations.first(where: { $0.id == id }),
           case .arrow(let control) = annotation.kind {
            let samples = arrowCenterline(start: annotation.start, control: control, end: annotation.end, curved: annotation.arrowCurved)
            let boxHalf = max(6, annotation.lineWidth * 0.72) / currentMagnification + 3 / currentMagnification
            for sample in samples {
                let rect = CGRect(x: sample.point.x - boxHalf, y: sample.point.y - boxHalf, width: boxHalf * 2, height: boxHalf * 2)
                addCursor(rect, .editorMove)
            }
        } else if let id = selectedAnnotationID,
                  let annotation = annotations.first(where: { $0.id == id }),
                  case .line(let control) = annotation.kind {
            addLineCursorRects(for: annotation, control: control, addCursor: addCursor)
        } else if let id = selectedAnnotationID,
                  let annotation = annotations.first(where: { $0.id == id }),
                  case .text = annotation.kind {
            addCursor(annotation.rect, .editorMove)
        } else if let id = selectedAnnotationID,
                  let annotation = annotations.first(where: { $0.id == id }),
                  annotation.isResizableShape {
            addShapeStrokeCursorRects(for: annotation, addCursor: addCursor)
            let radius = cropHandleHitRadius
            for handle in AnnotationShapeHandle.allCases {
                let anchor = handle.point(in: annotation.rect, kind: annotation.shapeKind)
                let handleRect = CGRect(
                    x: anchor.x - radius,
                    y: anchor.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                addCursor(handleRect, handle.resizeCursor)
            }
        }

        // Even when a shape is not selected, hovering near its stroke should
        // advertise that it can be grabbed and moved.
        for annotation in annotations where annotation.id != selectedAnnotationID && annotation.isResizableShape {
            addShapeStrokeCursorRects(for: annotation, addCursor: addCursor)
        }
        for annotation in annotations where annotation.id != selectedAnnotationID {
            if case .line(let control) = annotation.kind {
                addLineCursorRects(for: annotation, control: control, addCursor: addCursor)
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if isColorPicking {
            updatePickedColor(at: clampedPoint(from: event))
            return
        }

        super.mouseMoved(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        suppressTextInsertionOnMouseUp = false
        let hadActiveTextEditor = activeTextEditor != nil
        let hadSelectedText = selectedTextIndex != nil

        if isColorPicking {
            updatePickedColor(at: clampedPoint(from: event))
            return
        }

        if activeTextEditor != nil {
            commitActiveTextEditing()
        }

        window?.makeFirstResponder(self)
        let point = clampedPoint(from: event)
        dragStart = point
        dragCurrent = point
        isConstrainedDrawing = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)

        // Double-clicking inside a pending selection commits the crop, matching
        // pressing Enter.
        if let pendingCropRect, event.clickCount == 2, pendingCropRect.contains(point) {
            self.pendingCropRect = nil
            suppressTextInsertionOnMouseUp = true
            crop(to: pendingCropRect)
            needsDisplay = true
            return
        }

        // A selected arrow's knobs stay grabbable no matter which tool is
        // active, so its endpoints/curve can be adjusted right after drawing.
        if let selectedID = selectedAnnotationID,
           let handleHit = hitArrowHandle(at: point),
           handleHit.annotationID == selectedID {
            selectedAnnotationID = handleHit.annotationID
            activeArrowHandle = handleHit.handle
            isCropSelecting = false
            isMovingPendingCrop = false
            activeAnnotationShapeHandle = nil
            suppressTextInsertionOnMouseUp = true
            panLastPoint = nil
            dragStartAnnotations = annotations
            needsDisplay = true
            return
        }

        if let selectedID = selectedAnnotationID,
           let handleHit = hitLineHandle(at: point),
           handleHit.annotationID == selectedID {
            selectedAnnotationID = handleHit.annotationID
            activeArrowHandle = handleHit.handle
            isCropSelecting = false
            isMovingPendingCrop = false
            activeAnnotationShapeHandle = nil
            suppressTextInsertionOnMouseUp = true
            panLastPoint = nil
            dragStartAnnotations = annotations
            needsDisplay = true
            return
        }

        if let selectedID = selectedAnnotationID,
           let annotation = annotations.first(where: { $0.id == selectedID }),
           annotation.isResizableShape,
           let handle = AnnotationShapeGeometry.hitHandle(at: point, rect: annotation.rect, magnification: currentMagnification, kind: annotation.shapeKind) {
            activeShapeHandle = handle
            shapeResizeOrigin = annotation.rect
            activeArrowHandle = nil
            isCropSelecting = false
            isMovingPendingCrop = false
            activeAnnotationShapeHandle = nil
            isMovingAnnotation = false
            suppressTextInsertionOnMouseUp = true
            panLastPoint = nil
            dragStartAnnotations = annotations
            needsDisplay = true
            return
        }

        if event.clickCount == 2,
           pendingCropRect == nil,
           let hitID = hitAnnotation(at: point),
           isTextAnnotation(hitID) {
            selectedAnnotationID = hitID
            activeArrowHandle = nil
            isCropSelecting = false
            isMovingPendingCrop = false
            activeAnnotationShapeHandle = nil
            isMovingAnnotation = false
            suppressTextInsertionOnMouseUp = true
            panLastPoint = nil
            beginEditingTextAnnotation(hitID, selectAll: false)
            needsDisplay = true
            return
        }

        // Clicking any existing annotation re-selects it and starts moving it,
        // regardless of the active tool, so an arrow can be picked back up to
        // reposition, re-curve, or delete after losing focus.
        if event.clickCount == 1, pendingCropRect == nil, let hitID = hitAnnotation(at: point) {
            selectedAnnotationID = hitID
            activeArrowHandle = nil
            isCropSelecting = false
            isMovingPendingCrop = false
            activeAnnotationShapeHandle = nil
            isMovingAnnotation = true
            suppressTextInsertionOnMouseUp = true
            panLastPoint = nil
            dragStartAnnotations = annotations
            needsDisplay = true
            return
        }

        if selectedTool == .text, hadActiveTextEditor || hadSelectedText {
            // Clicking outside a selected/editing text box only dismisses the
            // box. The mouseUp should not immediately create a new text box.
            selectedAnnotationID = nil
            activeArrowHandle = nil
            isCropSelecting = false
            isMovingPendingCrop = false
            isMovingAnnotation = false
            suppressTextInsertionOnMouseUp = true
            panLastPoint = nil
            needsDisplay = true
            return
        }

        if selectedTool == .select {
            // Grabbing a resize handle of the pending selection resizes it.
            if let pendingCropRect, let handle = cropHandle(at: point, in: pendingCropRect) {
                activeAnnotationShapeHandle = handle
                pendingCropMoveOrigin = pendingCropRect
                isMovingPendingCrop = false
                isCropSelecting = false
                selectedAnnotationID = nil
                activeArrowHandle = nil
                panLastPoint = nil
                dragStartAnnotations = annotations
                needsDisplay = true
                return
            }

            // Clicking inside an existing pending selection moves it rather than
            // starting a new marquee, so the region can be nudged into place.
            if let pendingCropRect, pendingCropRect.contains(point) {
                isMovingPendingCrop = true
                isCropSelecting = false
                pendingCropMoveOrigin = pendingCropRect
                selectedAnnotationID = nil
                activeArrowHandle = nil
                panLastPoint = nil
                dragStartAnnotations = annotations
                NSCursor.closedHand.push()
                needsDisplay = true
                return
            }

            if let handleHit = hitArrowHandle(at: point) {
                selectedAnnotationID = handleHit.annotationID
                activeArrowHandle = handleHit.handle
                isCropSelecting = false
            } else {
                selectedAnnotationID = hitAnnotation(at: point)
                activeArrowHandle = nil
                // Dragging empty canvas starts a crop/select marquee
                // style); panning the canvas is now the trackpad's job.
                isCropSelecting = selectedAnnotationID == nil
            }
            if isCropSelecting {
                pendingCropRect = nil
            }
            panLastPoint = nil
            dragStartAnnotations = annotations
        } else {
            selectedAnnotationID = nil
            activeArrowHandle = nil
            isCropSelecting = false
            panLastPoint = nil
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clampedPoint(from: event)
        isConstrainedDrawing = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)

        if let handle = activeAnnotationShapeHandle, let origin = pendingCropMoveOrigin {
            pendingCropRect = resizedRect(origin, handle: handle, to: point)
            needsDisplay = true
            return
        }

        if let handle = activeShapeHandle,
           let origin = shapeResizeOrigin,
           let selectedAnnotationID {
            let kind = annotations.first(where: { $0.id == selectedAnnotationID })?.shapeKind ?? .rectangle
            let rect = AnnotationShapeGeometry.resized(origin, handle: handle, to: point, within: bounds, constrained: isConstrainedDrawing, kind: kind)
            annotations = annotations.map { annotation in
                annotation.id == selectedAnnotationID ? annotation.updatingRect(rect) : annotation
            }
            needsDisplay = true
            return
        }

        if isMovingPendingCrop, let origin = pendingCropMoveOrigin, let dragStart {
            let dx = point.x - dragStart.x
            let dy = point.y - dragStart.y
            pendingCropRect = clampedRect(origin.offsetBy(dx: dx, dy: dy), within: bounds)
            needsDisplay = true
            return
        }

        dragCurrent = point

        // Dragging an active arrow knob adjusts that endpoint/curve, independent
        // of the current tool.
        if let activeArrowHandle,
           let selectedAnnotationID,
           let originalAnnotations = dragStartAnnotations {
            annotations = originalAnnotations.map { annotation in
                guard annotation.id == selectedAnnotationID else { return annotation }
                if case .line = annotation.kind {
                    return annotation.updatingLineHandle(activeArrowHandle, to: point)
                }
                return annotation.updatingArrowHandle(activeArrowHandle, to: point)
            }
            needsDisplay = true
            return
        }

        // Dragging a selected annotation's body moves the whole thing, again
        // regardless of the active tool.
        if isMovingAnnotation,
           let selectedAnnotationID,
           let dragStart,
           let originalAnnotations = dragStartAnnotations {
            let dx = point.x - dragStart.x
            let dy = point.y - dragStart.y
            annotations = originalAnnotations.map { annotation in
                annotation.id == selectedAnnotationID ? annotation.offsetBy(dx: dx, dy: dy) : annotation
            }
            needsDisplay = true
            return
        }

        if selectedTool == .select,
           !isCropSelecting,
           let selectedAnnotationID,
           let dragStart,
           let originalAnnotations = dragStartAnnotations {
            if let activeArrowHandle {
                annotations = originalAnnotations.map { annotation in
                    guard annotation.id == selectedAnnotationID else { return annotation }
                    if case .line = annotation.kind {
                        return annotation.updatingLineHandle(activeArrowHandle, to: point)
                    }
                    return annotation.updatingArrowHandle(activeArrowHandle, to: point)
                }
            } else {
                let dx = point.x - dragStart.x
                let dy = point.y - dragStart.y
                annotations = originalAnnotations.map { annotation in
                    annotation.id == selectedAnnotationID ? annotation.offsetBy(dx: dx, dy: dy) : annotation
                }
            }
        }

        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        isConstrainedDrawing = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
        if dragStart != nil {
            needsDisplay = true
        }
        super.flagsChanged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        dragCurrent = clampedPoint(from: event)
        isConstrainedDrawing = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
        defer {
            dragStart = nil
            dragCurrent = nil
            dragStartAnnotations = nil
            isConstrainedDrawing = false
            activeArrowHandle = nil
            isCropSelecting = false
            isMovingPendingCrop = false
            isMovingAnnotation = false
            pendingCropMoveOrigin = nil
            activeAnnotationShapeHandle = nil
            activeShapeHandle = nil
            shapeResizeOrigin = nil
            panLastPoint = nil
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            suppressTextInsertionOnMouseUp = false
        }

        if activeAnnotationShapeHandle != nil {
            return
        }

        if activeShapeHandle != nil {
            if let originalAnnotations = dragStartAnnotations, annotationsChanged(from: originalAnnotations) {
                registerUndo(
                    state: EditorDocumentState(image: baseImage, annotations: originalAnnotations),
                    name: "Resize"
                )
            }
            return
        }

        if isMovingPendingCrop {
            NSCursor.pop()
            return
        }

        // Moving a selected annotation's body can happen under any tool; register
        // its undo here.
        if isMovingAnnotation {
            if let originalAnnotations = dragStartAnnotations, annotationsChanged(from: originalAnnotations) {
                registerUndo(
                    state: EditorDocumentState(image: baseImage, annotations: originalAnnotations),
                    name: "Move"
                )
            }
            return
        }

        // An arrow-knob adjustment can happen under any tool; register its undo
        // here so it is not lost when a non-select tool is active.
        if activeArrowHandle != nil {
            if let originalAnnotations = dragStartAnnotations, annotationsChanged(from: originalAnnotations) {
                registerUndo(
                    state: EditorDocumentState(image: baseImage, annotations: originalAnnotations),
                    name: "Adjust Arrow"
                )
            }
            return
        }

        if selectedTool == .select {
            if isCropSelecting, let start = dragStart, let end = dragCurrent {
                // Hold the selection as a preview (with W/H + size readout);
                // the actual crop happens on Enter. A bare click clears it.
                let rect = normalizedRect(from: start, to: end).intersection(bounds)
                pendingCropRect = (rect.width > 4 && rect.height > 4) ? rect : nil
                return
            }
            if let originalAnnotations = dragStartAnnotations, annotationsChanged(from: originalAnnotations) {
                registerUndo(
                    state: EditorDocumentState(image: baseImage, annotations: originalAnnotations),
                    name: activeArrowHandle == nil ? "Move" : "Adjust Arrow"
                )
            }
            return
        }

        guard let start = dragStart, let end = dragCurrent else {
            return
        }

        if selectedTool == .crop {
            crop(to: normalizedRect(from: start, to: end))
            return
        }

        if selectedTool == .text {
            guard !suppressTextInsertionOnMouseUp else {
                return
            }
            insertTextAnnotation(from: start, to: end)
            return
        }

        guard let annotation = makeAnnotation(from: start, to: end) else {
            return
        }
        let previousState = EditorDocumentState(image: baseImage, annotations: annotations)
        annotations.append(annotation)
        selectedAnnotationID = annotation.id
        registerUndo(state: previousState, name: annotationUndoName(annotation))
    }

    override func keyDown(with event: NSEvent) {
        if isColorPicking {
            if event.keyCode == 48 {
                commitColorPickToClipboard()
                return
            }
            if event.keyCode == 53 {
                cancelColorPicking()
                return
            }
        }

        // Enter crops to the selection; Shift+Enter cuts the selection out and
        // keeps the rest; Escape cancels the pending selection.
        if let pendingCropRect, event.keyCode == 36 || event.keyCode == 76 {
            self.pendingCropRect = nil
            if event.modifierFlags.contains(.shift) {
                cutOut(pendingCropRect)
            } else {
                crop(to: pendingCropRect)
            }
            needsDisplay = true
            return
        }
        if pendingCropRect != nil, event.keyCode == 53 {
            pendingCropRect = nil
            needsDisplay = true
            return
        }

        if event.keyCode == 51, let selectedAnnotationID {
            let previousState = EditorDocumentState(image: baseImage, annotations: annotations)
            annotations.removeAll { $0.id == selectedAnnotationID }
            self.selectedAnnotationID = nil
            registerUndo(state: previousState, name: "Delete")
            needsDisplay = true
            return
        }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           handleCommandKey(event) {
            return
        }

        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            event.modifierFlags.contains(.shift) ? undoManager?.redo() : undoManager?.undo()
            return
        }

        super.keyDown(with: event)
    }

    private func handleCommandKey(_ event: NSEvent) -> Bool {
        let characters = event.charactersIgnoringModifiers ?? event.characters ?? ""
        switch characters {
        case "=", "+":
            onZoomCommand?(.zoomIn)
            return true
        case "-":
            onZoomCommand?(.zoomOut)
            return true
        case "0":
            onZoomCommand?(.fit)
            return true
        default:
            return false
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isRenderingForExport {
            NSColor.clear.setFill()
            bounds.fill(using: .copy)
        } else {
            drawEditorCheckerboard(in: dirtyRect)
        }

        let image = cachedImage
        image.draw(in: bounds)

        for annotation in annotations where annotation.id != activeTextAnnotationID {
            draw(annotation, selected: annotation.id == selectedAnnotationID)
        }

        if let draft = draftAnnotation() {
            draw(draft, selected: false)
        } else if isCropSelecting, let dragStart, let dragCurrent {
            drawCropSelection(normalizedRect(from: dragStart, to: dragCurrent).intersection(bounds), live: true)
        } else if let pendingCropRect {
            drawCropSelection(pendingCropRect, live: false)
        } else if selectedTool == .crop, let dragStart, let dragCurrent {
            drawCropDraft(normalizedRect(from: dragStart, to: dragCurrent))
        }
    }

    func imageForTextRecognition() -> CGImage {
        if let pendingCropRect { return baseImage.cropping(to: pendingCropRect.integral) ?? baseImage }
        return baseImage
    }

    func renderedImage() -> CGImage? {
        commitActiveTextEditing()

        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width),
            pixelsHigh: Int(bounds.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let bitmap else {
            return nil
        }

        let previousSelection = selectedAnnotationID
        let wasRenderingForExport = isRenderingForExport
        selectedAnnotationID = nil
        isRenderingForExport = true
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(bounds)
        NSGraphicsContext.restoreGraphicsState()
        selectedAnnotationID = previousSelection
        isRenderingForExport = wasRenderingForExport

        return bitmap.cgImage
    }

    private func makeAnnotation(from start: CGPoint, to end: CGPoint) -> EditorAnnotation? {
        let rect = normalizedRect(from: start, to: end)
        let adjustedEnd = CGPoint(
            x: abs(start.x - end.x) < 4 ? start.x + 160 : end.x,
            y: abs(start.y - end.y) < 4 ? start.y + 56 : end.y
        )

        switch selectedTool {
        case .select, .crop:
            return nil
        case .arrow:
            // Require an actual drag: a bare click should not create an arrow.
            guard hypot(end.x - start.x, end.y - start.y) >= 6 else { return nil }
            return EditorAnnotation(
                kind: .arrow(control: defaultArrowControlPoint(start: start, end: end)),
                start: start,
                end: end,
                color: currentColor,
                lineWidth: lineWidth,
                arrowStyle: currentArrowStyle,
                arrowCurved: currentArrowCurved
            )
        case .text:
            return EditorAnnotation(kind: .text("Text"), start: start, end: adjustedEnd, color: currentColor, lineWidth: lineWidth)
        case .rectangle:
            let shapeRect = normalizedShapeRect(from: start, to: end)
            guard shapeRect.width > 3, shapeRect.height > 3 else { return nil }
            return EditorAnnotation(kind: .rectangle, start: shapeRect.origin, end: CGPoint(x: shapeRect.maxX, y: shapeRect.maxY), color: currentColor, lineWidth: lineWidth)
        case .oval:
            let shapeRect = normalizedShapeRect(from: start, to: end)
            guard shapeRect.width > 3, shapeRect.height > 3 else { return nil }
            return EditorAnnotation(kind: .oval, start: shapeRect.origin, end: CGPoint(x: shapeRect.maxX, y: shapeRect.maxY), color: currentColor, lineWidth: lineWidth)
        case .line:
            return EditorAnnotation(kind: .line(control: defaultArrowControlPoint(start: start, end: end)), start: start, end: end, color: currentColor, lineWidth: lineWidth)
        case .highlighter:
            guard rect.width > 3, rect.height > 3 else { return nil }
            return EditorAnnotation(kind: .highlighter, start: start, end: end, color: .systemYellow, lineWidth: lineWidth)
        case .blur:
            guard rect.width > 8, rect.height > 8 else { return nil }
            return EditorAnnotation(kind: .blur, start: start, end: end, color: .clear, lineWidth: lineWidth)
        }
    }

    private func draftAnnotation() -> EditorAnnotation? {
        guard selectedTool != .select,
              selectedTool != .text,
              selectedTool != .crop,
              activeArrowHandle == nil,
              !isMovingAnnotation,
              let dragStart,
              let dragCurrent else {
            return nil
        }
        return makeDraftAnnotation(from: dragStart, to: dragCurrent)
    }

    private func makeDraftAnnotation(from start: CGPoint, to end: CGPoint) -> EditorAnnotation? {
        switch selectedTool {
        case .arrow:
            return EditorAnnotation(
                kind: .arrow(control: defaultArrowControlPoint(start: start, end: end)),
                start: start,
                end: end,
                color: currentColor,
                lineWidth: lineWidth,
                arrowStyle: currentArrowStyle,
                arrowCurved: currentArrowCurved
            )
        case .rectangle:
            let rect = normalizedShapeRect(from: start, to: end)
            return EditorAnnotation(kind: .rectangle, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), color: currentColor, lineWidth: lineWidth)
        case .oval:
            let rect = normalizedShapeRect(from: start, to: end)
            return EditorAnnotation(kind: .oval, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), color: currentColor, lineWidth: lineWidth)
        case .line:
            return EditorAnnotation(kind: .line(control: defaultArrowControlPoint(start: start, end: end)), start: start, end: end, color: currentColor, lineWidth: lineWidth)
        case .highlighter:
            return EditorAnnotation(kind: .highlighter, start: start, end: end, color: .systemYellow, lineWidth: lineWidth)
        case .blur:
            return EditorAnnotation(kind: .blur, start: start, end: end, color: .clear, lineWidth: lineWidth)
        case .select, .text, .crop:
            return nil
        }
    }

    private func draw(_ annotation: EditorAnnotation, selected: Bool) {
        switch annotation.kind {
        case .arrow(let control):
            drawCurvedArrow(
                start: annotation.start,
                control: control,
                end: annotation.end,
                color: annotation.color,
                width: annotation.lineWidth,
                style: annotation.arrowStyle,
                curved: annotation.arrowCurved
            )
        case .line(let control):
            drawCurvedLine(start: annotation.start, control: control, end: annotation.end, color: annotation.color, width: annotation.lineWidth)
        case .rectangle:
            AnnotationShapeGeometry.draw(.rectangle, in: annotation.rect, color: annotation.color, width: annotation.lineWidth)
        case .oval:
            AnnotationShapeGeometry.draw(.oval, in: annotation.rect, color: annotation.color, width: annotation.lineWidth)
        case .highlighter:
            annotation.color.withAlphaComponent(0.34).setFill()
            annotation.rect.fill()
        case .blur:
            drawMosaic(in: annotation.rect)
        case .text(let text):
            drawText(
                text,
                in: annotation.rect,
                color: annotation.color,
                fontSize: annotation.textFontSize,
                fillColor: annotation.textFillColor,
                strokeColor: annotation.textStrokeColor,
                selected: selected || annotation.id == activeTextAnnotationID
            )
        }

        if selected, case .arrow = annotation.kind {
            drawArrowHandles(for: annotation)
        } else if selected, case .line = annotation.kind {
            drawLineHandles(for: annotation)
        } else if selected, annotation.isResizableShape {
            drawShapeHandles(for: annotation)
        } else if selected, !annotation.isTextAnnotation {
            drawSelectionFrame(annotation.rect)
        }
    }

    private func drawCurvedArrow(start: CGPoint, control: CGPoint, end: CGPoint, color: NSColor, width: CGFloat, style: AnnotationArrowStyle, curved: Bool) {
        AnnotationArrowRenderer.draw(start: start, control: control, end: end, color: color, width: width, style: style, curved: curved)
    }

    private func arrowCenterline(start: CGPoint, control: CGPoint, end: CGPoint, curved: Bool) -> [AnnotationArrowRenderer.ArrowSample] {
        AnnotationArrowRenderer.centerline(start: start, control: control, end: end, curved: curved)
    }

    private func drawLine(from start: CGPoint, to end: CGPoint, color: NSColor, width: CGFloat, arrowHead: Bool) {
        color.setStroke()
        color.setFill()
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.move(to: start)
        path.line(to: end)
        path.stroke()

        guard arrowHead else { return }
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(12, width * 4)
        let spread = CGFloat.pi / 7
        let left = CGPoint(
            x: end.x - headLength * cos(angle - spread),
            y: end.y - headLength * sin(angle - spread)
        )
        let right = CGPoint(
            x: end.x - headLength * cos(angle + spread),
            y: end.y - headLength * sin(angle + spread)
        )
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: left)
        head.line(to: right)
        head.close()
        head.fill()
    }

    private func drawCurvedLine(start: CGPoint, control: CGPoint, end: CGPoint, color: NSColor, width: CGFloat) {
        AnnotationLineRenderer.draw(start: start, control: control, end: end, color: color, width: width)
    }

    private func drawArrowHandles(for annotation: EditorAnnotation) {
        guard let geometry = annotation.arrowGeometry else { return }
        for (_, point) in geometry.handles {
            AnnotationArrowGeometry.drawHandle(at: point, magnification: currentMagnification)
        }
    }

    private func drawLineHandles(for annotation: EditorAnnotation) {
        guard let geometry = annotation.lineGeometry else { return }
        for (_, point) in geometry.handles {
            AnnotationArrowGeometry.drawHandle(at: point, magnification: currentMagnification)
        }
    }

    private func drawShapeHandles(for annotation: EditorAnnotation) {
        for handle in AnnotationShapeHandle.allCases {
            drawEditorHandle(at: handle.point(in: annotation.rect, kind: annotation.shapeKind))
        }
    }

    // Shared selection-handle style used by every editable shape (arrows now,
    // rectangles/ovals later): a white disc with an accent-color ring, kept a
    // constant on-screen size regardless of zoom.
    private func drawEditorHandle(at point: CGPoint) {
        AnnotationArrowGeometry.drawHandle(at: point, magnification: currentMagnification)
    }

    private func drawText(_ text: String, in rect: CGRect, color: NSColor, fontSize: CGFloat, fillColor: NSColor, strokeColor: NSColor?, selected: Bool) {
        AnnotationTextRenderer.draw(text, in: rect, color: color, fontSize: fontSize, fillColor: fillColor, selected: selected && strokeColor != nil, scale: sourceScaleFactor, magnification: currentMagnification)
    }

    private var textInsets: NSEdgeInsets {
        NSEdgeInsets(top: 8 * sourceScaleFactor, left: 14 * sourceScaleFactor, bottom: 8 * sourceScaleFactor, right: 14 * sourceScaleFactor)
    }

    private var textCornerRadius: CGFloat {
        8 * sourceScaleFactor
    }

    private func textFont(size: CGFloat) -> NSFont {
        AnnotationTextRenderer.font(size: size, scale: sourceScaleFactor)
    }

    private func centeredParagraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return paragraph
    }

    private func insertTextAnnotation(from start: CGPoint, to end: CGPoint) {
        let annotation = makeTextAnnotation(from: start, to: end)
        let initialState = EditorDocumentState(image: baseImage, annotations: annotations)
        annotations.append(annotation)
        selectedAnnotationID = annotation.id
        activeArrowHandle = nil
        isCropSelecting = false
        pendingCropRect = nil
        beginEditingTextAnnotation(annotation.id, selectAll: false, initialState: initialState)
        needsDisplay = true
    }

    private func makeTextAnnotation(from start: CGPoint, to end: CGPoint) -> EditorAnnotation {
        let text = ""
        let rect = textRect(from: start, to: end, text: text, fontSize: currentTextFontSize)
        return EditorAnnotation(
            kind: .text(text),
            start: rect.origin,
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            color: currentColor,
            lineWidth: lineWidth,
            textFontSize: currentTextFontSize,
            textFillColor: currentTextFillColor,
            textStrokeColor: currentTextStrokeColor
        )
    }

    private func textRect(from start: CGPoint, to end: CGPoint, text: String, fontSize: CGFloat) -> CGRect {
        AnnotationTextRenderer.fittedRect(from: start, to: end, text: text, fontSize: fontSize, within: bounds, scale: sourceScaleFactor)
    }

    private func textBoxSize(for text: String, fontSize: CGFloat) -> CGSize {
        AnnotationTextRenderer.boxSize(for: text, fontSize: fontSize, scale: sourceScaleFactor)
    }

    private func autosizeTextAnnotation(at index: Int) {
        guard annotations.indices.contains(index),
              case .text(let text) = annotations[index].kind else {
            return
        }
        let rect = AnnotationTextRenderer.autosizedRect(annotations[index].rect, text: text, fontSize: annotations[index].textFontSize, within: bounds, scale: sourceScaleFactor)
        annotations[index] = annotations[index].updatingRect(rect)
    }

    private func beginEditingTextAnnotation(_ id: UUID, selectAll: Bool, initialState: EditorDocumentState? = nil) {
        commitActiveTextEditing()
        guard let index = annotations.firstIndex(where: { $0.id == id }),
              case .text(let text) = annotations[index].kind else {
            return
        }

        autosizeTextAnnotation(at: index)
        let annotation = annotations[index]
        let editorFrame = annotation.rect
        let editor = AnnotationInlineTextView(frame: editorFrame)
        editor.delegate = self
        editor.drawsBackground = false
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.textContainerInset = NSSize(width: textInsets.left, height: textInsets.top)
        editor.textContainer?.lineFragmentPadding = 0
        editor.minSize = NSSize(width: 0, height: editorFrame.height)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = true
        editor.autoresizingMask = []
        editor.string = text
        syncTextEditorContainer(editor)
        applyTextEditorAttributes(editor, annotation: annotation)
        editor.onCommit = { [weak self] in self?.commitActiveTextEditing() }
        editor.onCancel = { [weak self] in self?.cancelActiveTextEditing() }
        editor.onEditingLayoutChange = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.syncActiveTextEditorGeometry(editor)
        }

        // Rounded accent border so it clearly reads as an editable text box.
        editor.wantsLayer = true
        editor.layer?.cornerRadius = textCornerRadius
        editor.layer?.borderWidth = 0
        editor.layer?.borderColor = NSColor.clear.cgColor
        editor.layer?.backgroundColor = annotation.textFillColor.cgColor

        activeTextAnnotationID = id
        activeTextEditor = editor
        activeTextEditorInitialState = initialState ?? EditorDocumentState(image: baseImage, annotations: annotations)
        addSubview(editor)
        updateTextEditorSelectionRing(editor, annotation: annotation)
        window?.makeFirstResponder(editor)
        if selectAll {
            editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
        } else {
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
        needsDisplay = true
    }

    private func syncActiveTextEditorGeometry(_ editor: AnnotationInlineTextView) {
        guard editor === activeTextEditor,
              let id = activeTextAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }) else {
            return
        }

        // During IME marked-text composition, NSTextView may not send the usual
        // textDidChange callback for every visual update. Use the editor's live
        // string to size the annotation so the rounded box follows pinyin/marked
        // text before it is committed.
        annotations[index].kind = .text(editor.string)
        autosizeTextAnnotation(at: index)
        editor.frame = annotations[index].rect
        syncTextEditorContainer(editor)
        applyTextEditorAttributes(editor, annotation: annotations[index])
        updateTextEditorSelectionRing(editor, annotation: annotations[index])
        editor.needsDisplay = true
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        guard let editor = notification.object as? AnnotationInlineTextView,
              editor === activeTextEditor else {
            return
        }

        syncActiveTextEditorGeometry(editor)
    }

    private func commitActiveTextEditing() {
        guard let editor = activeTextEditor,
              let id = activeTextAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }) else {
            clearActiveTextEditor()
            return
        }

        let trimmed = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            annotations.removeAll { $0.id == id }
            selectedAnnotationID = nil
        } else {
            annotations[index].kind = .text(editor.string)
            autosizeTextAnnotation(at: index)
            selectedAnnotationID = id
        }

        if let initialState = activeTextEditorInitialState, !sameDocumentState(initialState) {
            registerUndo(state: initialState, name: "Edit Text")
        }
        clearActiveTextEditor()
        needsDisplay = true
    }

    private func cancelActiveTextEditing() {
        guard let initialState = activeTextEditorInitialState else {
            clearActiveTextEditor()
            needsDisplay = true
            return
        }

        annotations = initialState.annotations
        selectedAnnotationID = nil
        clearActiveTextEditor()
        needsDisplay = true
    }

    private func clearActiveTextEditor() {
        activeTextEditor?.removeFromSuperview()
        activeTextEditor?.delegate = nil
        activeTextEditor = nil
        activeTextAnnotationID = nil
        activeTextEditorInitialState = nil
        window?.makeFirstResponder(self)
    }

    private func drawMosaic(in rect: CGRect) {
        let cropRect = rect.integral.intersection(bounds)
        guard !cropRect.isNull, cropRect.width > 1, cropRect.height > 1 else {
            return
        }

        if let cropped = baseImage.cropping(to: cropRect) {
            NSGraphicsContext.current?.imageInterpolation = .none
            let smallSize = NSSize(width: max(1, cropRect.width / 14), height: max(1, cropRect.height / 14))
            let smallImage = NSImage(size: smallSize)
            smallImage.lockFocus()
            NSImage(cgImage: cropped, size: smallSize).draw(in: CGRect(origin: .zero, size: smallSize))
            smallImage.unlockFocus()
            smallImage.draw(in: cropRect)
            NSGraphicsContext.current?.imageInterpolation = .default
        } else {
            NSColor.black.withAlphaComponent(0.28).setFill()
            cropRect.fill()
        }
    }

    private func drawSelectionFrame(_ rect: CGRect) {
        let path = NSBezierPath(rect: rect.insetBy(dx: -4, dy: -4))
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 1.5
        path.setLineDash([5, 3], count: 2, phase: 0)
        path.stroke()
    }

    private func drawCropDraft(_ rect: CGRect) {
        guard rect.width > 1, rect.height > 1 else {
            return
        }

        // Dim only the area outside the selection so the selected region keeps
        // showing the image normally (PS-style), instead of clearing a hole.
        let overlay = NSBezierPath(rect: bounds)
        overlay.append(NSBezierPath(rect: rect))
        overlay.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        overlay.fill()

        let path = NSBezierPath(rect: rect)
        NSColor.systemBlue.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    private func drawAnnotationShapeHandles(_ rect: CGRect) {
        for handle in AnnotationShapeHandle.allCases {
            drawEditorHandle(at: handle.point(in: rect))
        }
    }

    private func drawCropSelection(_ rect: CGRect, live: Bool) {
        guard rect.width > 1, rect.height > 1 else {
            return
        }

        drawCropDraft(rect)

        // Draw resize handles once the selection has settled (not during the
        // initial marquee drag), so it reads as adjustable.
        if !live {
            drawAnnotationShapeHandles(rect)
        }

        // Labels scale with zoom so they stay legible at any level. W: sits above
        // the top edge, H: to the left; the crop hints stack centered below. Gaps
        // are measured to the pill edge (padding included) so nothing touches the
        // selection frame.
        let scale = 1 / currentMagnification
        let gap = 8 * scale
        let padX = 8 * scale
        let padY = 4 * scale

        let widthText = "W: \(Int(rect.width.rounded()))px"
        let widthAttrs = pillTextAttributes(fontSize: 12 * scale)
        let widthSize = widthText.size(withAttributes: widthAttrs)
        drawPill(
            text: widthText,
            at: CGPoint(x: rect.midX - widthSize.width / 2, y: rect.minY - gap - padY - widthSize.height),
            attributes: widthAttrs,
            scale: scale
        )

        let heightText = "H: \(Int(rect.height.rounded()))px"
        let heightAttrs = pillTextAttributes(fontSize: 12 * scale)
        let heightSize = heightText.size(withAttributes: heightAttrs)
        drawPill(
            text: heightText,
            at: CGPoint(x: rect.minX - gap - padX - heightSize.width, y: rect.midY - heightSize.height / 2),
            attributes: heightAttrs,
            scale: scale
        )

        let hintLines = ["Enter to crop", "⇧Enter to cut out"]
        let hintAttrs = pillTextAttributes(fontSize: 12 * scale)
        drawMultilinePill(
            lines: hintLines,
            attributes: hintAttrs,
            centerX: rect.midX,
            top: rect.maxY + gap,
            scale: scale
        )
    }

    private func pillTextAttributes(fontSize: CGFloat, color: NSColor = .white) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color
        ]
    }

    private func drawPill(
        text: String,
        at origin: CGPoint,
        attributes: [NSAttributedString.Key: Any],
        scale: CGFloat,
        background: NSColor = NSColor.black.withAlphaComponent(0.6)
    ) {
        let textSize = text.size(withAttributes: attributes)
        if background != .clear {
            let padX = 8 * scale
            let padY = 4 * scale
            let pill = CGRect(
                x: origin.x - padX,
                y: origin.y - padY,
                width: textSize.width + padX * 2,
                height: textSize.height + padY * 2
            )
            let path = NSBezierPath(roundedRect: pill, xRadius: 5 * scale, yRadius: 5 * scale)
            background.setFill()
            path.fill()
        }
        text.draw(at: origin, withAttributes: attributes)
    }

    // Draws several centered lines inside one rounded background, top-anchored.
    private func drawMultilinePill(
        lines: [String],
        attributes: [NSAttributedString.Key: Any],
        centerX: CGFloat,
        top: CGFloat,
        scale: CGFloat,
        background: NSColor = NSColor.black.withAlphaComponent(0.6)
    ) {
        let padX = 8 * scale
        let padY = 4 * scale
        let lineGap = 3 * scale
        let sizes = lines.map { $0.size(withAttributes: attributes) }
        let contentWidth = sizes.map(\.width).max() ?? 0
        let contentHeight = sizes.map(\.height).reduce(0, +) + lineGap * CGFloat(max(0, lines.count - 1))

        let pill = CGRect(
            x: centerX - contentWidth / 2 - padX,
            y: top,
            width: contentWidth + padX * 2,
            height: contentHeight + padY * 2
        )
        let path = NSBezierPath(roundedRect: pill, xRadius: 5 * scale, yRadius: 5 * scale)
        background.setFill()
        path.fill()

        var lineY = top + padY
        for (line, size) in zip(lines, sizes) {
            line.draw(at: CGPoint(x: centerX - size.width / 2, y: lineY), withAttributes: attributes)
            lineY += size.height + lineGap
        }
    }

    private func crop(to rect: CGRect) {
        commitActiveTextEditing()

        let cropRect = rect.integral.intersection(bounds)
        guard cropRect.width > 16, cropRect.height > 16, let cropped = baseImage.cropping(to: cropRect) else {
            NSSound.beep()
            return
        }

        let previousState = EditorDocumentState(
            image: baseImage,
            annotations: annotations,
            restoreCropRect: cropRect
        )
        baseImage = cropped
        annotations = annotations.compactMap { annotation in
            let shifted = annotation.offsetBy(dx: -cropRect.minX, dy: -cropRect.minY)
            return shifted.rect.intersects(CGRect(x: 0, y: 0, width: cropRect.width, height: cropRect.height)) ? shifted : nil
        }
        setFrameSize(NSSize(width: cropped.width, height: cropped.height))
        onImageSizeChange?(imagePixelSize)
        registerUndo(state: previousState, name: "Crop")
    }

    // Erases the selected region to transparency, keeping the rest of the image
    // and its full dimensions (inverse of crop).
    private func cutOut(_ rect: CGRect) {
        commitActiveTextEditing()

        let cutRect = rect.integral.intersection(bounds)
        guard cutRect.width > 1, cutRect.height > 1 else {
            NSSound.beep()
            return
        }

        let width = baseImage.width
        let height = baseImage.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            NSSound.beep()
            return
        }

        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The view is flipped (y-down); CGContext is y-up, so flip the cut rect.
        let clearRect = CGRect(
            x: cutRect.minX,
            y: CGFloat(height) - cutRect.maxY,
            width: cutRect.width,
            height: cutRect.height
        )
        context.clear(clearRect)

        guard let result = context.makeImage() else {
            NSSound.beep()
            return
        }

        let previousState = EditorDocumentState(image: baseImage, annotations: annotations)
        baseImage = result
        registerUndo(state: previousState, name: "Cut Out")
        needsDisplay = true
    }

    private func registerUndo(state: EditorDocumentState, name: String) {
        undoManager?.registerUndo(withTarget: self) { target in
            target.restore(state: state, name: name)
        }
        undoManager?.setActionName(name)
    }

    private func restore(state: EditorDocumentState, name: String) {
        clearActiveTextEditor()

        let currentState = EditorDocumentState(image: baseImage, annotations: annotations)
        baseImage = state.image
        annotations = state.annotations
        selectedAnnotationID = nil
        setFrameSize(NSSize(width: baseImage.width, height: baseImage.height))
        onImageSizeChange?(imagePixelSize)
        // Undoing a crop re-shows the original selection so it can be adjusted
        // and re-applied.
        pendingCropRect = state.restoreCropRect.map { $0.intersection(bounds) }
        undoManager?.registerUndo(withTarget: self) { target in
            target.restore(state: currentState, name: name)
        }
        undoManager?.setActionName(name)
        needsDisplay = true
    }

    private func clampedPoint(from event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }

    private func normalizedShapeRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        AnnotationShapeGeometry.normalized(from: start, to: end, constrained: isConstrainedDrawing)
    }

    // Slides `rect` back inside `container` without resizing it, so a moved crop
    // selection stops at the image edges instead of leaving the canvas.
    private func clampedRect(_ rect: CGRect, within container: CGRect) -> CGRect {
        var result = rect
        result.origin.x = min(max(rect.origin.x, container.minX), container.maxX - rect.width)
        result.origin.y = min(max(rect.origin.y, container.minY), container.maxY - rect.height)
        return result
    }

    // On-screen radius of each resize handle's grab area, in document units.
    private var cropHandleHitRadius: CGFloat { 10 / currentMagnification }
    private var shapeStrokeHitSlop: CGFloat { 8 / currentMagnification }

    private func shapeStrokeHit(_ point: CGPoint, annotation: EditorAnnotation) -> Bool {
        let kind: AnnotationShapeKind
        switch annotation.kind {
        case .rectangle: kind = .rectangle
        case .oval: kind = .oval
        default: return false
        }
        return AnnotationShapeGeometry.hitStroke(at: point, kind: kind, rect: annotation.rect, width: annotation.lineWidth, magnification: currentMagnification)
    }

    private func addShapeStrokeCursorRects(for annotation: EditorAnnotation, addCursor: (CGRect, NSCursor) -> Void) {
        let slop = max(shapeStrokeHitSlop, annotation.lineWidth / 2 + shapeStrokeHitSlop / 2)
        let rect = annotation.rect
        switch annotation.kind {
        case .rectangle:
            addCursor(CGRect(x: rect.minX - slop, y: rect.minY - slop, width: rect.width + slop * 2, height: slop * 2), .editorMove)
            addCursor(CGRect(x: rect.minX - slop, y: rect.maxY - slop, width: rect.width + slop * 2, height: slop * 2), .editorMove)
            addCursor(CGRect(x: rect.minX - slop, y: rect.minY, width: slop * 2, height: rect.height), .editorMove)
            addCursor(CGRect(x: rect.maxX - slop, y: rect.minY, width: slop * 2, height: rect.height), .editorMove)
        case .oval:
            // Approximate oval stroke hot zone with sampled cursor boxes along the outline.
            for step in 0..<48 {
                let angle = CGFloat(step) / 48 * 2 * .pi
                let point = CGPoint(x: rect.midX + cos(angle) * rect.width / 2, y: rect.midY + sin(angle) * rect.height / 2)
                addCursor(CGRect(x: point.x - slop, y: point.y - slop, width: slop * 2, height: slop * 2), .editorMove)
            }
        default:
            break
        }
    }

    private func addLineCursorRects(for annotation: EditorAnnotation, control: CGPoint, addCursor: (CGRect, NSCursor) -> Void) {
        let samples = arrowCenterline(start: annotation.start, control: control, end: annotation.end, curved: false)
        let boxHalf = max(6, annotation.lineWidth) / currentMagnification + 3 / currentMagnification
        for sample in samples {
            addCursor(
                CGRect(x: sample.point.x - boxHalf, y: sample.point.y - boxHalf, width: boxHalf * 2, height: boxHalf * 2),
                .editorMove
            )
        }
    }

    // Returns the handle under `point` for the given selection, if any.
    private func cropHandle(at point: CGPoint, in rect: CGRect) -> AnnotationShapeHandle? {
        let radius = cropHandleHitRadius
        for handle in AnnotationShapeHandle.allCases {
            let anchor = handle.point(in: rect)
            if abs(point.x - anchor.x) <= radius && abs(point.y - anchor.y) <= radius {
                return handle
            }
        }
        return nil
    }

    // Applies a handle drag to `origin`, moving only the affected edges, keeping
    // a minimum size and clamping to the image bounds.
    private func resizedRect(_ origin: CGRect, handle: AnnotationShapeHandle, to point: CGPoint) -> CGRect {
        let minSize: CGFloat = 8
        var minX = origin.minX
        var maxX = origin.maxX
        var minY = origin.minY
        var maxY = origin.maxY

        let px = min(max(point.x, bounds.minX), bounds.maxX)
        let py = min(max(point.y, bounds.minY), bounds.maxY)

        if handle.movesLeftEdge { minX = min(px, maxX - minSize) }
        if handle.movesRightEdge { maxX = max(px, minX + minSize) }
        if handle.movesTopEdge { minY = min(py, maxY - minSize) }
        if handle.movesBottomEdge { maxY = max(py, minY + minSize) }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func defaultArrowControlPoint(start: CGPoint, end: CGPoint) -> CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    private func isTextAnnotation(_ id: UUID) -> Bool {
        guard let annotation = annotations.first(where: { $0.id == id }),
              case .text = annotation.kind else {
            return false
        }
        return true
    }

    private func hitAnnotation(at point: CGPoint) -> UUID? {
        // Tolerance grows with a screen-space slack so thin arrows stay easy to
        // grab even when zoomed out.
        for annotation in annotations.reversed() {
            switch annotation.kind {
            case .arrow:
                if annotation.arrowGeometry?.hit(at: point, width: annotation.lineWidth, curved: annotation.arrowCurved, magnification: currentMagnification) == true {
                    return annotation.id
                }
            case .line:
                if annotation.lineGeometry?.hit(at: point, width: annotation.lineWidth, curved: false, magnification: currentMagnification, includesArrowhead: false) == true {
                    return annotation.id
                }
            case .rectangle, .oval:
                if shapeStrokeHit(point, annotation: annotation) {
                    return annotation.id
                }
            default:
                if annotation.rect.insetBy(dx: -8, dy: -8).contains(point) {
                    return annotation.id
                }
            }
        }
        return nil
    }

    private func sameDocumentState(_ state: EditorDocumentState) -> Bool {
        state.image === baseImage && annotationsAreEquivalent(state.annotations, annotations)
    }

    private func annotationsAreEquivalent(_ lhs: [EditorAnnotation], _ rhs: [EditorAnnotation]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }

        for (left, right) in zip(lhs, rhs) where !annotationsAreEquivalent(left, right) {
            return false
        }
        return true
    }

    private func annotationsAreEquivalent(_ lhs: EditorAnnotation, _ rhs: EditorAnnotation) -> Bool {
        guard lhs.id == rhs.id,
              lhs.start == rhs.start,
              lhs.end == rhs.end,
              lhs.color == rhs.color,
              lhs.lineWidth == rhs.lineWidth,
              lhs.arrowStyle == rhs.arrowStyle,
              lhs.arrowCurved == rhs.arrowCurved,
              lhs.textFontSize == rhs.textFontSize,
              lhs.textFillColor == rhs.textFillColor,
              lhs.textStrokeColor == rhs.textStrokeColor else {
            return false
        }

        switch (lhs.kind, rhs.kind) {
        case (.arrow(let left), .arrow(let right)):
            return left == right
        case (.line(let left), .line(let right)):
            return left == right
        case (.text(let left), .text(let right)):
            return left == right
        case (.rectangle, .rectangle), (.oval, .oval), (.highlighter, .highlighter), (.blur, .blur):
            return true
        default:
            return false
        }
    }

    private func hitArrowHandle(at point: CGPoint) -> (annotationID: UUID, handle: AnnotationArrowHandle)? {
        for annotation in annotations.reversed() {
            if let handle = annotation.arrowGeometry?.hitHandle(at: point, magnification: currentMagnification) {
                return (annotation.id, handle)
            }
        }
        return nil
    }

    private func hitLineHandle(at point: CGPoint) -> (annotationID: UUID, handle: AnnotationArrowHandle)? {
        for annotation in annotations.reversed() {
            if let handle = annotation.lineGeometry?.hitHandle(at: point, magnification: currentMagnification) {
                return (annotation.id, handle)
            }
        }
        return nil
    }

    private func distance(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx != 0 || dy != 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func distance(_ point: CGPoint, toQuadraticCurveFrom start: CGPoint, control: CGPoint, to end: CGPoint) -> CGFloat {
        var minimum = CGFloat.greatestFiniteMagnitude
        var previous = start
        for step in 1...36 {
            let t = CGFloat(step) / 36
            let current = quadraticPoint(start: start, control: control, end: end, t: t)
            minimum = min(minimum, distance(point, toSegmentFrom: previous, to: current))
            previous = current
        }
        return minimum
    }

    private func quadraticPoint(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }

    private func cubicControls(start: CGPoint, control: CGPoint, end: CGPoint) -> (control1: CGPoint, control2: CGPoint) {
        (
            CGPoint(
                x: start.x + (2.0 / 3.0) * (control.x - start.x),
                y: start.y + (2.0 / 3.0) * (control.y - start.y)
            ),
            CGPoint(
                x: end.x + (2.0 / 3.0) * (control.x - end.x),
                y: end.y + (2.0 / 3.0) * (control.y - end.y)
            )
        )
    }

    private func annotationsChanged(from oldValue: [EditorAnnotation]) -> Bool {
        guard oldValue.count == annotations.count else {
            return true
        }
        for index in annotations.indices where !annotations[index].hasSameGeometry(as: oldValue[index]) {
            return true
        }
        return false
    }

    private func annotationUndoName(_ annotation: EditorAnnotation) -> String {
        switch annotation.kind {
        case .arrow: return "Arrow"
        case .text: return "Text"
        case .rectangle: return "Rectangle"
        case .oval: return "Oval"
        case .line: return "Line"
        case .highlighter: return "Highlighter"
        case .blur: return "Blur"
        }
    }
}
