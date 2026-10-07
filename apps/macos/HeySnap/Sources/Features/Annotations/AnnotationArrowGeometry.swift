import AppKit

enum AnnotationArrowHandle: CaseIterable {
    case start, control, end
}

/// Shared editable arrow geometry. The middle handle is an on-curve point;
/// the quadratic control point is an implementation detail, not a draggable knob.
struct AnnotationArrowGeometry {
    var start: CGPoint
    var control: CGPoint
    var end: CGPoint

    var midpoint: CGPoint {
        CGPoint(x: 0.25 * start.x + 0.5 * control.x + 0.25 * end.x,
                y: 0.25 * start.y + 0.5 * control.y + 0.25 * end.y)
    }

    var bounds: CGRect {
        let minX = min(start.x, control.x, end.x), minY = min(start.y, control.y, end.y)
        return CGRect(x: minX, y: minY, width: max(start.x, control.x, end.x) - minX, height: max(start.y, control.y, end.y) - minY)
    }

    var handles: [(AnnotationArrowHandle, CGPoint)] {
        [(.start, start), (.control, midpoint), (.end, end)]
    }

    func updating(_ handle: AnnotationArrowHandle, to point: CGPoint) -> Self {
        var result = self
        switch handle {
        case .start: result.start = point
        case .control:
            result.control = CGPoint(x: 2 * point.x - 0.5 * (start.x + end.x),
                                     y: 2 * point.y - 0.5 * (start.y + end.y))
        case .end: result.end = point
        }
        return result
    }

    func offsetBy(dx: CGFloat, dy: CGFloat) -> Self {
        Self(start: CGPoint(x: start.x + dx, y: start.y + dy),
             control: CGPoint(x: control.x + dx, y: control.y + dy),
             end: CGPoint(x: end.x + dx, y: end.y + dy))
    }

    func hitHandle(at point: CGPoint, magnification: CGFloat = 1) -> AnnotationArrowHandle? {
        handles.first { hypot(point.x - $0.1.x, point.y - $0.1.y) <= 11 / magnification }?.0
    }

    func hit(at point: CGPoint, width: CGFloat, curved: Bool, magnification: CGFloat = 1) -> Bool {
        let slack = 10 / magnification
        let samples = AnnotationArrowRenderer.centerline(start: start, control: control, end: end, curved: curved)
        let tolerance = max(width, 0) + slack
        for (a, b) in zip(samples, samples.dropFirst()) {
            let dx = b.point.x - a.point.x, dy = b.point.y - a.point.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0
                ? max(0, min(1, ((point.x - a.point.x) * dx + (point.y - a.point.y) * dy) / lengthSquared))
                : 0
            if hypot(point.x - a.point.x - t * dx, point.y - a.point.y - t * dy) <= tolerance { return true }
        }
        let headReach = max(6, width * 2.4) + slack
        return hypot(point.x - end.x, point.y - end.y) <= headReach
    }

    static func drawHandle(at point: CGPoint, magnification: CGFloat = 1) {
        let radius = 5.5 / magnification
        let path = NSBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        NSColor.white.setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 1.5 / magnification
        path.stroke()
    }
}
