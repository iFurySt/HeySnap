import AppKit

typealias AnnotationLineGeometry = AnnotationArrowGeometry

enum AnnotationLineRenderer {
    static func path(start: CGPoint, control: CGPoint, end: CGPoint, width: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: start)
        path.curve(to: end,
                   controlPoint1: CGPoint(x: start.x + (2.0 / 3.0) * (control.x - start.x), y: start.y + (2.0 / 3.0) * (control.y - start.y)),
                   controlPoint2: CGPoint(x: end.x + (2.0 / 3.0) * (control.x - end.x), y: end.y + (2.0 / 3.0) * (control.y - end.y)))
        path.lineWidth = width
        path.lineCapStyle = .round
        return path
    }

    static func draw(start: CGPoint, control: CGPoint, end: CGPoint, color: NSColor, width: CGFloat) {
        color.setStroke()
        path(start: start, control: control, end: end, width: width).stroke()
    }
}
