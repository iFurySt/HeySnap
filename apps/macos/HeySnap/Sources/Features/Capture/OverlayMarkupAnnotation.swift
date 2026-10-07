import AppKit

enum OverlayMarkupTool {
    case select
    case rectangle
    case oval
    case line
    case arrow
    case highlighter
    case text
    case blur

    var barIndex: Int {
        switch self {
        case .rectangle: return 1
        case .oval: return 2
        case .line: return 3
        case .arrow: return 4
        case .text: return 5
        case .blur: return 7
        case .highlighter: return 8
        case .select: return -1
        }
    }

    var usesStrokeWidthDots: Bool {
        switch self {
        case .rectangle, .oval, .line, .arrow:
            return true
        case .select, .text, .highlighter, .blur:
            return false
        }
    }
}

enum OverlayHighlightShape {
    case rectangle
    case oval
    case roundedRectangle
}

struct OverlayMarkupAnnotation {
    let id: UUID
    let tool: OverlayMarkupTool
    let start: CGPoint
    let end: CGPoint
    let control: CGPoint?
    let color: NSColor
    let lineWidth: CGFloat
    let fontSize: CGFloat
    let text: String
    let textFillColor: NSColor
    let mosaicIntensity: CGFloat
    let highlightOpacity: CGFloat
    let highlightShape: OverlayHighlightShape

    init(
        id: UUID = UUID(),
        tool: OverlayMarkupTool,
        start: CGPoint,
        end: CGPoint,
        control: CGPoint? = nil,
        color: NSColor = AnnotationDefaults.color,
        lineWidth: CGFloat = AnnotationDefaults.lineWidth,
        fontSize: CGFloat = AnnotationDefaults.textFontSize,
        text: String = "",
        textFillColor: NSColor = .clear,
        mosaicIntensity: CGFloat = 0.5,
        highlightOpacity: CGFloat = 0.5,
        highlightShape: OverlayHighlightShape = .rectangle
    ) {
        self.id = id
        self.tool = tool
        self.start = start
        self.end = end
        self.control = control ?? ((tool == .arrow || tool == .line) ? OverlayMarkupAnnotation.defaultControl(start: start, end: end) : nil)
        self.color = color
        self.lineWidth = lineWidth
        self.fontSize = fontSize
        self.text = text
        self.textFillColor = textFillColor
        self.mosaicIntensity = mosaicIntensity
        self.highlightOpacity = highlightOpacity
        self.highlightShape = highlightShape
    }

    var rect: CGRect {
        if tool == .arrow || tool == .line { return arrowGeometry.bounds }
        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    var defaultControl: CGPoint {
        Self.defaultControl(start: start, end: end)
    }

    func highlightPath(in rect: CGRect) -> NSBezierPath {
        switch highlightShape {
        case .rectangle:
            return NSBezierPath(rect: rect)
        case .oval:
            return NSBezierPath(ovalIn: rect)
        case .roundedRectangle:
            return NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        }
    }

    var arrowGeometry: AnnotationArrowGeometry {
        AnnotationArrowGeometry(start: start, control: control ?? defaultControl, end: end)
    }

    var handlePoints: [(OverlayAnnotationHandle, CGPoint)] {
        switch tool {
        case .arrow:
            return arrowGeometry.handles.map { (OverlayAnnotationHandle(arrowHandle: $0.0), $0.1) }
        case .line:
            return arrowGeometry.handles.map { (OverlayAnnotationHandle(arrowHandle: $0.0), $0.1) }
        case .rectangle, .oval:
            return AnnotationShapeHandle.allCases.map { (OverlayAnnotationHandle(shapeHandle: $0), $0.point(in: rect, flipped: false, kind: tool == .oval ? .oval : .rectangle)) }
        case .highlighter, .blur:
            return OverlayAnnotationHandle.shapeCases.map { ($0, $0.point(in: rect)) }
        case .text:
            return []
        default:
            return []
        }
    }

    var lineSamplePoints: [CGPoint] {
        switch tool {
        case .arrow:
            return AnnotationArrowRenderer.centerline(start: start, control: control ?? defaultControl, end: end, curved: false).map(\.point)
        case .line:
            return AnnotationArrowRenderer.centerline(start: start, control: control ?? defaultControl, end: end, curved: false).map(\.point)
        default:
            return []
        }
    }

    func clamped(to bounds: CGRect) -> OverlayMarkupAnnotation {
        copy(
            start: clamp(start, to: bounds),
            end: clamp(end, to: bounds),
            control: control.map { clamp($0, to: bounds) }
        )
    }

    func inViewCoordinates(screenFrame: CGRect) -> OverlayMarkupAnnotation? {
        let bounds = CGRect(origin: screenFrame.origin, size: screenFrame.size)
        let clipped = rect.intersection(bounds)
        guard !clipped.isNull, clipped.width > 0 || clipped.height > 0 else {
            return nil
        }
        return copy(
            start: CGPoint(x: start.x - screenFrame.minX, y: start.y - screenFrame.minY),
            end: CGPoint(x: end.x - screenFrame.minX, y: end.y - screenFrame.minY),
            control: control.map { CGPoint(x: $0.x - screenFrame.minX, y: $0.y - screenFrame.minY) }
        )
    }

    func updating(handle: OverlayAnnotationHandle, to point: CGPoint, within bounds: CGRect, constrained: Bool) -> OverlayMarkupAnnotation {
        if (tool == .rectangle || tool == .oval), let shapeHandle = handle.shapeHandle {
            return updatingRect(AnnotationShapeGeometry.resized(rect, handle: shapeHandle, to: point, within: bounds, constrained: constrained, flipped: false, kind: tool == .oval ? .oval : .rectangle))
        }
        if (tool == .arrow || tool == .line), let arrowHandle = handle.arrowHandle {
            let geometry = arrowGeometry.updating(arrowHandle, to: point)
            return copy(start: geometry.start, end: geometry.end, control: geometry.control)
        }
        if handle.isShapeHandle {
            return updatingRect(resizedRect(handle: handle, to: point))
        }

        switch handle {
        case .start:
            return copy(start: point)
        case .control:
            return copy(control: point)
        case .end:
            return copy(end: point)
        default:
            return self
        }
    }

    func withStyle(color: NSColor, lineWidth: CGFloat, fontSize: CGFloat) -> OverlayMarkupAnnotation {
        copy(color: color, lineWidth: lineWidth, fontSize: fontSize)
    }

    func withEffects(mosaicIntensity: CGFloat, highlightOpacity: CGFloat, highlightShape: OverlayHighlightShape) -> OverlayMarkupAnnotation {
        copy(mosaicIntensity: mosaicIntensity, highlightOpacity: highlightOpacity, highlightShape: highlightShape)
    }

    func withTextAppearance(color: NSColor, fontSize: CGFloat, fillColor: NSColor) -> OverlayMarkupAnnotation {
        copy(color: color, fontSize: fontSize, textFillColor: fillColor)
    }

    func withTextStyle(filled: Bool) -> OverlayMarkupAnnotation {
        let style = AnnotationTextRenderer.style(filled: filled, color: color, fillColor: textFillColor)
        return copy(color: style.color, textFillColor: style.fill)
    }

    func withText(_ text: String) -> OverlayMarkupAnnotation {
        copy(text: text)
    }

    func updatingTextRect(_ rect: CGRect) -> OverlayMarkupAnnotation {
        updatingRect(rect)
    }

    func offsetBy(dx: CGFloat, dy: CGFloat) -> OverlayMarkupAnnotation {
        if tool == .arrow || tool == .line {
            let geometry = arrowGeometry.offsetBy(dx: dx, dy: dy)
            return copy(start: geometry.start, end: geometry.end, control: geometry.control)
        }
        return copy(
            start: CGPoint(x: start.x + dx, y: start.y + dy),
            end: CGPoint(x: end.x + dx, y: end.y + dy),
            control: control.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        )
    }

    private func updatingRect(_ rect: CGRect) -> OverlayMarkupAnnotation {
        copy(
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            control: control
        )
    }

    private func copy(
        start: CGPoint? = nil,
        end: CGPoint? = nil,
        control: CGPoint? = nil,
        color: NSColor? = nil,
        lineWidth: CGFloat? = nil,
        fontSize: CGFloat? = nil,
        text: String? = nil,
        textFillColor: NSColor? = nil,
        mosaicIntensity: CGFloat? = nil,
        highlightOpacity: CGFloat? = nil,
        highlightShape: OverlayHighlightShape? = nil
    ) -> OverlayMarkupAnnotation {
        OverlayMarkupAnnotation(
            id: id,
            tool: tool,
            start: start ?? self.start,
            end: end ?? self.end,
            control: control ?? self.control,
            color: color ?? self.color,
            lineWidth: lineWidth ?? self.lineWidth,
            fontSize: fontSize ?? self.fontSize,
            text: text ?? self.text,
            textFillColor: textFillColor ?? self.textFillColor,
            mosaicIntensity: mosaicIntensity ?? self.mosaicIntensity,
            highlightOpacity: highlightOpacity ?? self.highlightOpacity,
            highlightShape: highlightShape ?? self.highlightShape
        )
    }

    private func resizedRect(handle: OverlayAnnotationHandle, to point: CGPoint) -> CGRect {
        let minSize: CGFloat = 6
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        if handle.movesLeft { minX = min(point.x, maxX - minSize) }
        if handle.movesRight { maxX = max(point.x, minX + minSize) }
        if handle.movesBottom { minY = min(point.y, maxY - minSize) }
        if handle.movesTop { maxY = max(point.y, minY + minSize) }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func defaultControl(start: CGPoint, end: CGPoint) -> CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    private func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }
}

enum OverlayAnnotationHandle {
    case start
    case control
    case end
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    static let shapeCases: [OverlayAnnotationHandle] = [
        .topLeft,
        .top,
        .topRight,
        .right,
        .bottomRight,
        .bottom,
        .bottomLeft,
        .left
    ]

    var isShapeHandle: Bool {
        Self.shapeCases.contains(self)
    }

    var cursor: NSCursor {
        if let handle = shapeHandle { return handle.resizeCursor }
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
        case .start, .control, .end:
            return .editorMove
        }
    }

    var movesLeft: Bool {
        self == .topLeft || self == .bottomLeft || self == .left
    }

    var movesRight: Bool {
        self == .topRight || self == .bottomRight || self == .right
    }

    var movesBottom: Bool {
        self == .bottomLeft || self == .bottom || self == .bottomRight
    }

    var movesTop: Bool {
        self == .topLeft || self == .top || self == .topRight
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .top:
            return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        case .right:
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom:
            return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .left:
            return CGPoint(x: rect.minX, y: rect.midY)
        case .start, .control, .end:
            return .zero
        }
    }
}

extension OverlayAnnotationHandle {
    init(arrowHandle: AnnotationArrowHandle) {
        switch arrowHandle {
        case .start: self = .start
        case .control: self = .control
        case .end: self = .end
        }
    }

    var arrowHandle: AnnotationArrowHandle? {
        switch self {
        case .start: return .start
        case .control: return .control
        case .end: return .end
        default: return nil
        }
    }
}

extension OverlayMarkupTool {
    var sharesEditorGeometry: Bool {
        switch self {
        case .arrow, .line, .rectangle, .oval, .text: return true
        default: return false
        }
    }
}

extension OverlayAnnotationHandle {
    init(shapeHandle: AnnotationShapeHandle) {
        switch shapeHandle {
        case .topLeft: self = .topLeft
        case .top: self = .top
        case .topRight: self = .topRight
        case .right: self = .right
        case .bottomRight: self = .bottomRight
        case .bottom: self = .bottom
        case .bottomLeft: self = .bottomLeft
        case .left: self = .left
        }
    }

    var shapeHandle: AnnotationShapeHandle? {
        switch self {
        case .topLeft: return .topLeft
        case .top: return .top
        case .topRight: return .topRight
        case .right: return .right
        case .bottomRight: return .bottomRight
        case .bottom: return .bottom
        case .bottomLeft: return .bottomLeft
        case .left: return .left
        default: return nil
        }
    }
}
