import AppKit

enum AnnotationShapeKind { case rectangle, oval }

enum AnnotationShapeHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    // Anchor point of the handle within `rect` (view is flipped: y increases down).
    func point(in rect: CGRect, flipped: Bool = true, kind: AnnotationShapeKind = .rectangle) -> CGPoint {
        let anchor = rectanglePoint(in: rect, flipped: flipped)
        guard kind == .oval, isCorner else { return anchor }
        let diagonal = 1 / sqrt(CGFloat(2))
        return CGPoint(x: rect.midX + (anchor.x - rect.midX) * diagonal,
                       y: rect.midY + (anchor.y - rect.midY) * diagonal)
    }

    var isCorner: Bool { (movesLeftEdge || movesRightEdge) && (movesTopEdge || movesBottomEdge) }

    private func rectanglePoint(in rect: CGRect, flipped: Bool) -> CGPoint {
        let topY = flipped ? rect.minY : rect.maxY
        let bottomY = flipped ? rect.maxY : rect.minY
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: topY)
        case .top: return CGPoint(x: rect.midX, y: topY)
        case .topRight: return CGPoint(x: rect.maxX, y: topY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: bottomY)
        case .bottom: return CGPoint(x: rect.midX, y: bottomY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: bottomY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    var movesLeftEdge: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRightEdge: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTopEdge: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottomEdge: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    // Public directional resize cursor for this handle (macOS 15+).
    var resizeCursor: NSCursor {
        switch self {
        case .topLeft: return .frameResize(position: .topLeft, directions: .all)
        case .top: return .frameResize(position: .top, directions: .all)
        case .topRight: return .frameResize(position: .topRight, directions: .all)
        case .right: return .frameResize(position: .right, directions: .all)
        case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
        case .bottom: return .frameResize(position: .bottom, directions: .all)
        case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
        case .left: return .frameResize(position: .left, directions: .all)
        }
    }
}

enum AnnotationShapeGeometry {
    static func normalized(from start: CGPoint, to end: CGPoint, constrained: Bool = false) -> CGRect {
        let dx = end.x - start.x, dy = end.y - start.y
        let side = min(abs(dx), abs(dy))
        let target = constrained ? CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side)) : end
        return CGRect(x: min(start.x, target.x), y: min(start.y, target.y), width: abs(target.x - start.x), height: abs(target.y - start.y))
    }

    static func path(_ kind: AnnotationShapeKind, in rect: CGRect) -> NSBezierPath {
        kind == .rectangle ? NSBezierPath(rect: rect) : NSBezierPath(ovalIn: rect)
    }

    static func draw(_ kind: AnnotationShapeKind, in rect: CGRect, color: NSColor, width: CGFloat) {
        let outline = path(kind, in: rect)
        color.setStroke()
        outline.lineWidth = width
        outline.stroke()
    }

    static func hitStroke(at point: CGPoint, kind: AnnotationShapeKind, rect: CGRect, width: CGFloat, magnification: CGFloat = 1) -> Bool {
        let slop = max(8 / magnification, width / 2 + 4 / magnification)
        switch kind {
        case .rectangle:
            return rect.insetBy(dx: -slop, dy: -slop).contains(point) && !rect.insetBy(dx: slop, dy: slop).contains(point)
        case .oval:
            guard rect.width > 1, rect.height > 1 else { return false }
            let nx = (point.x - rect.midX) / (rect.width / 2), ny = (point.y - rect.midY) / (rect.height / 2)
            let outer = 1 + slop / (min(rect.width, rect.height) / 2)
            let inner = max(0, 1 - slop / (min(rect.width, rect.height) / 2))
            return nx * nx + ny * ny <= outer * outer && nx * nx + ny * ny >= inner * inner
        }
    }

    static func hitHandle(at point: CGPoint, rect: CGRect, magnification: CGFloat = 1, flipped: Bool = true, kind: AnnotationShapeKind = .rectangle) -> AnnotationShapeHandle? {
        AnnotationShapeHandle.allCases.first {
            let p = $0.point(in: rect, flipped: flipped, kind: kind)
            return abs(point.x - p.x) <= 10 / magnification && abs(point.y - p.y) <= 10 / magnification
        }
    }

    private static func resizedRect(_ origin: CGRect, handle: AnnotationShapeHandle, to point: CGPoint, within bounds: CGRect) -> CGRect {
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

    static func resized(_ origin: CGRect, handle: AnnotationShapeHandle, to point: CGPoint, within bounds: CGRect, constrained: Bool, flipped: Bool = true, kind: AnnotationShapeKind = .rectangle) -> CGRect {
        if !flipped {
            let sumY = bounds.minY + bounds.maxY
            let mirrored = CGRect(x: origin.minX, y: sumY - origin.maxY, width: origin.width, height: origin.height)
            let result = resized(mirrored, handle: handle, to: CGPoint(x: point.x, y: sumY - point.y), within: bounds, constrained: constrained, kind: kind)
            return CGRect(x: result.minX, y: sumY - result.maxY, width: result.width, height: result.height)
        }
        var point = point
        if kind == .oval, handle.isCorner {
            // An ellipse's diagonal knob is inset from the bounding corner. Reverse
            // that inset about the fixed opposite corner so grabbing it never jumps.
            let anchor = CGPoint(x: handle.movesLeftEdge ? origin.maxX : origin.minX,
                                 y: handle.movesTopEdge ? origin.maxY : origin.minY)
            let fraction = (1 + 1 / sqrt(CGFloat(2))) / 2
            point = CGPoint(x: anchor.x + (point.x - anchor.x) / fraction,
                            y: anchor.y + (point.y - anchor.y) / fraction)
        }
        guard constrained else {
            return resizedRect(origin, handle: handle, to: point, within: bounds)
        }

        let px = min(max(point.x, bounds.minX), bounds.maxX)
        let py = min(max(point.y, bounds.minY), bounds.maxY)
        let minSize: CGFloat = 8
        let raw: CGRect
        switch handle {
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            let anchor: CGPoint
            let signX: CGFloat
            let signY: CGFloat
            switch handle {
            case .topLeft:
                anchor = CGPoint(x: origin.maxX, y: origin.maxY)
                signX = -1; signY = -1
            case .topRight:
                anchor = CGPoint(x: origin.minX, y: origin.maxY)
                signX = 1; signY = -1
            case .bottomRight:
                anchor = CGPoint(x: origin.minX, y: origin.minY)
                signX = 1; signY = 1
            case .bottomLeft:
                anchor = CGPoint(x: origin.maxX, y: origin.minY)
                signX = -1; signY = 1
            default:
                fatalError("unreachable")
            }
            let side = max(minSize, min(abs(px - anchor.x), abs(py - anchor.y)))
            raw = CGRect(
                x: min(anchor.x, anchor.x + signX * side),
                y: min(anchor.y, anchor.y + signY * side),
                width: side,
                height: side
            )
        case .top:
            let side = max(minSize, abs(py - origin.maxY))
            raw = CGRect(x: origin.midX - side / 2, y: origin.maxY - side, width: side, height: side)
        case .bottom:
            let side = max(minSize, abs(py - origin.minY))
            raw = CGRect(x: origin.midX - side / 2, y: origin.minY, width: side, height: side)
        case .left:
            let side = max(minSize, abs(px - origin.maxX))
            raw = CGRect(x: origin.maxX - side, y: origin.midY - side / 2, width: side, height: side)
        case .right:
            let side = max(minSize, abs(px - origin.minX))
            raw = CGRect(x: origin.minX, y: origin.midY - side / 2, width: side, height: side)
        }

        return clampedRect(raw, within: bounds)
    }

    private static func clampedRect(_ rect: CGRect, within bounds: CGRect) -> CGRect {
        var result = rect
        result.origin.x = min(max(rect.minX, bounds.minX), bounds.maxX - rect.width)
        result.origin.y = min(max(rect.minY, bounds.minY), bounds.maxY - rect.height)
        return result
    }
}
