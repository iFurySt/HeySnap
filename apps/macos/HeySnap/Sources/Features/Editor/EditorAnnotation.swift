import AppKit

enum EditorAnnotationKind {
    case arrow(control: CGPoint)
    case text(String)
    case rectangle
    case oval
    case line(control: CGPoint)
    case highlighter
    case blur}

struct EditorAnnotation {
    var shapeKind: AnnotationShapeKind {
        if case .oval = kind { return .oval }
        return .rectangle
    }

    let id: UUID
    var kind: EditorAnnotationKind
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var lineWidth: CGFloat
    var arrowStyle: AnnotationArrowStyle
    // When true, an arrow renders as a circular arc through start/mid/end;
    // otherwise it stays a straight (quadratic) shaft.
    var arrowCurved: Bool
    var textFontSize: CGFloat
    var textFillColor: NSColor
    var textStrokeColor: NSColor?

    init(
        kind: EditorAnnotationKind,
        start: CGPoint,
        end: CGPoint,
        color: NSColor,
        lineWidth: CGFloat,
        arrowStyle: AnnotationArrowStyle = .single,
        arrowCurved: Bool = false,
        textFontSize: CGFloat = AnnotationDefaults.textFontSize,
        textFillColor: NSColor = .clear,
        textStrokeColor: NSColor? = .controlAccentColor
    ) {
        self.id = UUID()
        self.kind = kind
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
        self.arrowStyle = arrowStyle
        self.arrowCurved = arrowCurved
        self.textFontSize = textFontSize
        self.textFillColor = textFillColor
        self.textStrokeColor = textStrokeColor
    }

    var rect: CGRect {
        if let geometry = arrowGeometry {
            return geometry.bounds
        } else if case .line(let control) = kind {
            let minX = min(start.x, control.x, end.x)
            let minY = min(start.y, control.y, end.y)
            let maxX = max(start.x, control.x, end.x)
            let maxY = max(start.y, control.y, end.y)
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }

    func offsetBy(dx: CGFloat, dy: CGFloat) -> EditorAnnotation {
        var copy = self
        copy.start.x += dx
        copy.start.y += dy
        copy.end.x += dx
        copy.end.y += dy
        if case .arrow(let control) = copy.kind {
            copy.kind = .arrow(control: AnnotationArrowGeometry(start: start, control: control, end: end).offsetBy(dx: dx, dy: dy).control)
        } else if case .line(let control) = copy.kind {
            copy.kind = .line(control: AnnotationLineGeometry(start: start, control: control, end: end).offsetBy(dx: dx, dy: dy).control)
        }
        return copy
    }

    func arrowControlPoint() -> CGPoint? {
        guard case .arrow(let control) = kind else {
            return nil
        }
        return control
    }

    func lineControlPoint() -> CGPoint? {
        guard case .line(let control) = kind else {
            return nil
        }
        return control
    }

    var isTextAnnotation: Bool {
        if case .text = kind {
            return true
        }
        return false
    }

    var isResizableShape: Bool {
        switch kind {
        case .rectangle, .oval:
            return true
        default:
            return false
        }
    }

    var isLineAnnotation: Bool {
        if case .line = kind {
            return true
        }
        return false
    }

    var arrowGeometry: AnnotationArrowGeometry? {
        guard case .arrow(let control) = kind else { return nil }
        return AnnotationArrowGeometry(start: start, control: control, end: end)
    }

    func arrowCurveMidpoint() -> CGPoint? { arrowGeometry?.midpoint }

    var lineGeometry: AnnotationLineGeometry? {
        guard case .line(let control) = kind else { return nil }
        return AnnotationLineGeometry(start: start, control: control, end: end)
    }

    func lineCurveMidpoint() -> CGPoint? { lineGeometry?.midpoint }

    func updatingArrowHandle(_ handle: AnnotationArrowHandle, to point: CGPoint) -> EditorAnnotation {
        guard let geometry = arrowGeometry?.updating(handle, to: point) else { return self }
        var copy = self
        copy.start = geometry.start
        copy.end = geometry.end
        copy.kind = .arrow(control: geometry.control)
        return copy
    }

    func updatingLineHandle(_ handle: AnnotationArrowHandle, to point: CGPoint) -> EditorAnnotation {
        guard let geometry = lineGeometry?.updating(handle, to: point) else { return self }
        var copy = self
        copy.start = geometry.start
        copy.end = geometry.end
        copy.kind = .line(control: geometry.control)
        return copy
    }

    func updatingRect(_ rect: CGRect) -> EditorAnnotation {
        var copy = self
        copy.start = rect.origin
        copy.end = CGPoint(x: rect.maxX, y: rect.maxY)
        return copy
    }

    func hasSameGeometry(as other: EditorAnnotation) -> Bool {
        guard start == other.start, end == other.end else {
            return false
        }

        switch (kind, other.kind) {
        case (.arrow(let lhs), .arrow(let rhs)):
            return lhs == rhs
        case (.line(let lhs), .line(let rhs)):
            return lhs == rhs
        default:
            return true
        }
    }
}

// The eight resize handles of a crop selection (4 corners + 4 edge midpoints).
