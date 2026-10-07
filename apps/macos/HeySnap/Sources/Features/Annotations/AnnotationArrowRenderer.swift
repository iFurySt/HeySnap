import AppKit

enum AnnotationArrowStyle: String, CaseIterable {
    case single      // head at the end only
    case double      // heads at both ends

    var symbolName: String {
        switch self {
        case .single: return "arrow.right"
        case .double: return "arrow.left.and.right"
        }
    }

    var title: String {
        switch self {
        case .single: return "Single arrow"
        case .double: return "Double arrow"
        }
    }

    var hasEndHead: Bool { true }
    var hasStartHead: Bool { self == .double }
}


/// One arrow geometry for editor, quick markup preview, and bitmap export.
enum AnnotationArrowRenderer {
    static func draw(start: CGPoint, control: CGPoint, end: CGPoint, color: NSColor, width: CGFloat, style: AnnotationArrowStyle = .single, curved: Bool = false, metricsScale: CGFloat = 1) {
        guard let path = path(start: start, control: control, end: end, width: width, style: style, curved: curved, metricsScale: metricsScale) else { return }
        color.setFill()
        path.fill()
    }

    static func path(start: CGPoint, control: CGPoint, end: CGPoint, width: CGFloat, style: AnnotationArrowStyle = .single, curved: Bool = false, metricsScale: CGFloat = 1) -> NSBezierPath? {
        let samples = centerline(start: start, control: control, end: end, curved: curved)
        guard samples.count >= 2 else { return nil }

        let minHalf = max(1.4 * metricsScale, width * 0.34)
        let maxHalf = width * 0.72
        func halfWidth(_ t: CGFloat) -> CGFloat {
            switch style {
            case .single: return minHalf + (maxHalf - minHalf) * t
            case .double: return minHalf + (maxHalf - minHalf) * (abs(t - 0.5) * 2)
            }
        }

        let headLength = max(14 * metricsScale, width * 4.6)
        let headHalfWidth = max(6 * metricsScale, width * 2.4)

        // Build the arrow as ONE connected polygon: the tapered shaft's left edge,
        // then the head barb/tip/barb, then the shaft's right edge back. The shaft
        // ends at the exact interpolated arc point where the head base sits, and
        // the barbs start from that same point — so the head and shaft share an
        // edge and can never gap or turn into a diamond, at any curvature or width.
        // Verified by rendering a grid of arrows across angles/curvatures.
        let endBase = style.hasEndHead ? sampleAtArcLength(headLength, in: samples, fromEnd: true) : nil
        let startBase = style.hasStartHead ? sampleAtArcLength(headLength, in: samples, fromEnd: false) : nil

        // Shaft samples between the two base cut points, with the exact base
        // samples appended so the ribbon reaches precisely to the head.
        let startT = startBase?.t ?? 0
        let endT = endBase?.t ?? 1
        var shaft = samples.filter { $0.t >= startT && $0.t <= endT }
        if let startBase, shaft.first?.t != startBase.t { shaft.insert(startBase, at: 0) }
        if let endBase, shaft.last?.t != endBase.t { shaft.append(endBase) }
        guard shaft.count >= 2 else { return nil }

        func leftPoint(_ s: ArrowSample) -> CGPoint {
            CGPoint(x: s.point.x - s.tangent.y * halfWidth(s.t), y: s.point.y + s.tangent.x * halfWidth(s.t))
        }
        func rightPoint(_ s: ArrowSample) -> CGPoint {
            CGPoint(x: s.point.x + s.tangent.y * halfWidth(s.t), y: s.point.y - s.tangent.x * halfWidth(s.t))
        }
        func barbs(tip: CGPoint, base: CGPoint) -> (left: CGPoint, right: CGPoint) {
            let ax = tip.x - base.x, ay = tip.y - base.y
            let len = max(hypot(ax, ay), 0.0001)
            let perp = CGPoint(x: -ay / len, y: ax / len)
            return (CGPoint(x: base.x + perp.x * headHalfWidth, y: base.y + perp.y * headHalfWidth),
                    CGPoint(x: base.x - perp.x * headHalfWidth, y: base.y - perp.y * headHalfWidth))
        }

        let path = NSBezierPath()

        // Tail head (double style): tip -> its right barb -> into the shaft left edge.
        if let startBase {
            let tip = samples[0].point
            let b = barbs(tip: tip, base: startBase.point)
            path.move(to: tip)
            path.line(to: b.right)
        } else {
            path.move(to: leftPoint(shaft[0]))
        }

        // Left edge forward.
        for s in shaft.dropFirst() { path.line(to: leftPoint(s)) }

        // End head.
        if let endBase {
            let tip = samples[samples.count - 1].point
            let b = barbs(tip: tip, base: endBase.point)
            path.line(to: b.left)
            path.line(to: tip)
            path.line(to: b.right)
        }

        // Right edge back.
        for s in shaft.reversed() { path.line(to: rightPoint(s)) }

        // Close the tail head.
        if let startBase {
            let tip = samples[0].point
            let b = barbs(tip: tip, base: startBase.point)
            path.line(to: b.left)
        }

        path.close()
        return path
    }

    // Returns the interpolated sample at `distance` arc length from the tip (or
    // tail) along the real centerline.
    private static func sampleAtArcLength(_ distance: CGFloat, in samples: [ArrowSample], fromEnd: Bool) -> ArrowSample {
        guard samples.count >= 2 else {
            return fromEnd ? samples[samples.count - 1] : samples[0]
        }
        var accumulated: CGFloat = 0
        let order = fromEnd ? Array(stride(from: samples.count - 1, through: 1, by: -1)) : Array(0...(samples.count - 2))
        for i in order {
            let j = fromEnd ? i - 1 : i + 1
            let seg = hypot(samples[j].point.x - samples[i].point.x, samples[j].point.y - samples[i].point.y)
            if accumulated + seg >= distance {
                let f = seg > 0 ? (distance - accumulated) / seg : 0
                let p = CGPoint(
                    x: samples[i].point.x + (samples[j].point.x - samples[i].point.x) * f,
                    y: samples[i].point.y + (samples[j].point.y - samples[i].point.y) * f
                )
                let t = samples[i].t + (samples[j].t - samples[i].t) * f
                return ArrowSample(point: p, tangent: samples[i].tangent, t: t)
            }
            accumulated += seg
        }
        return fromEnd ? samples[0] : samples[samples.count - 1]
    }

    struct ArrowSample {
        var point: CGPoint
        var tangent: CGPoint   // unit tangent pointing start -> end
        var t: CGFloat         // 0...1 along the centerline
    }

    // Samples the arrow centerline. Curved mode fits a circle through start, the
    // on-curve midpoint, and end; otherwise it uses
    // the quadratic through the control point.
    static func centerline(start: CGPoint, control: CGPoint, end: CGPoint, curved: Bool) -> [ArrowSample] {
        let steps = 64
        let mid = AnnotationArrowGeometry(start: start, control: control, end: end).midpoint

        // Circle fit through the three points.
        let d = 2 * (start.x * (mid.y - end.y) + mid.x * (end.y - start.y) + end.x * (start.y - mid.y))

        var samples: [ArrowSample] = []
        samples.reserveCapacity(steps + 1)

        if !curved || abs(d) < 0.0001 {
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let p = quadraticPoint(start: start, control: control, end: end, t: t)
                let dx = 2 * (1 - t) * (control.x - start.x) + 2 * t * (end.x - control.x)
                let dy = 2 * (1 - t) * (control.y - start.y) + 2 * t * (end.y - control.y)
                let len = max(hypot(dx, dy), 0.0001)
                samples.append(ArrowSample(point: p, tangent: CGPoint(x: dx / len, y: dy / len), t: t))
            }
            return samples
        }

        let sq = { (p: CGPoint) in p.x * p.x + p.y * p.y }
        let s2 = sq(start), m2 = sq(mid), e2 = sq(end)
        let center = CGPoint(
            x: (s2 * (mid.y - end.y) + m2 * (end.y - start.y) + e2 * (start.y - mid.y)) / d,
            y: (s2 * (end.x - mid.x) + m2 * (start.x - end.x) + e2 * (mid.x - start.x)) / d
        )
        let radius = hypot(start.x - center.x, start.y - center.y)
        let a0 = atan2(start.y - center.y, start.x - center.x)
        let am = atan2(mid.y - center.y, mid.x - center.x)
        let a2 = atan2(end.y - center.y, end.x - center.x)

        // Choose the sweep direction that passes through the midpoint.
        func normalize(_ a: CGFloat) -> CGFloat {
            var x = a
            while x < 0 { x += 2 * .pi }
            while x >= 2 * .pi { x -= 2 * .pi }
            return x
        }
        let base = normalize(a0)
        let relMid = normalize(am - base)
        var relEnd = normalize(a2 - base)
        // If the midpoint isn't between start and end going CCW, sweep the other way.
        let clockwise = relMid > relEnd
        if clockwise {
            relEnd = relEnd - 2 * .pi
        }
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let angle = base + relEnd * t
            let p = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            // Tangent is the radius rotated 90 deg in the sweep direction.
            let sweepSign: CGFloat = relEnd >= 0 ? 1 : -1
            let tx = -sin(angle) * sweepSign
            let ty = cos(angle) * sweepSign
            samples.append(ArrowSample(point: p, tangent: CGPoint(x: tx, y: ty), t: t))
        }
        return samples
    }

    private static func quadraticPoint(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }

}
