import AppKit

@main
struct AnnotationArrowRendererTests {
    static func main() throws {
        let start = CGPoint(x: 40, y: 60)
        let control = CGPoint(x: 120, y: 60)
        let end = CGPoint(x: 200, y: 60)
        let arrow = AnnotationArrowRenderer.path(start: start, control: control, end: end, width: 5)!
        // The old open chevron left this interior of the arrowhead empty.
        precondition(arrow.contains(CGPoint(x: 183, y: 64)), "Arrowhead must be filled")
        precondition(arrow.contains(CGPoint(x: 90, y: 60)), "Shaft must join the arrowhead")
        precondition(!arrow.contains(CGPoint(x: 183, y: 80)), "Arrowhead should not fill outside its silhouette")

        // Export scales all geometry, including the minimum head dimensions of thin arrows.
        for width: CGFloat in [1, 3, 5, 10] {
            for style in AnnotationArrowStyle.allCases {
                for curved in [false, true] {
                    let bend = CGPoint(x: 110, y: 110)
                    let one = AnnotationArrowRenderer.path(start: start, control: bend, end: end, width: width, style: style, curved: curved)!
                    let two = AnnotationArrowRenderer.path(start: start * 2, control: bend * 2, end: end * 2, width: width * 2, style: style, curved: curved, metricsScale: 2)!
                    for x in stride(from: 30.25, through: 220.25, by: 2) {
                        for y in stride(from: 30.25, through: 130.25, by: 2) {
                            let point = CGPoint(x: x, y: y)
                            precondition(one.contains(point) == two.contains(point * 2), "Retina export silhouette differs from preview")
                        }
                    }
                }
            }
        }

        // The dragged middle handle must sit exactly under the pointer and on
        // the visible curve, even when its raw control point lies outside the image.
        let geometry = AnnotationArrowGeometry(start: start, control: control, end: end)
        let pointer = CGPoint(x: 280, y: 155)
        let bent = geometry.updating(.control, to: pointer)
        precondition(bent.midpoint == pointer, "Middle handle must stay under the pointer")
        precondition(bent.control != pointer, "Handle must not expose the raw control point")
        for curved in [false, true] {
            let samples = AnnotationArrowRenderer.centerline(start: bent.start, control: bent.control, end: bent.end, curved: curved)
            if !curved {
                precondition(samples.contains { hypot($0.point.x - pointer.x, $0.point.y - pointer.y) < 0.001 }, "Quadratic midpoint must equal the handle")
            }
            let silhouette = AnnotationArrowRenderer.path(start: bent.start, control: bent.control, end: bent.end, width: 5, curved: curved)!
            precondition(silhouette.contains(pointer), "Middle handle must lie on the visible arrow")
            precondition(bent.hit(at: pointer, width: 5, curved: curved), "Bent shaft must be selectable away from the endpoint chord")
        }
        precondition(bent.hitHandle(at: pointer) == .control)
        precondition(bent.hitHandle(at: CGPoint(x: pointer.x + 8, y: pointer.y + 8)) == nil, "Handle hit region must match Editor's circular radius")
        let movedStart = bent.updating(.start, to: CGPoint(x: 30, y: 45))
        precondition(movedStart.start == CGPoint(x: 30, y: 45) && movedStart.control == bent.control && movedStart.end == bent.end)
        let movedEnd = bent.updating(.end, to: CGPoint(x: 230, y: 40))
        precondition(movedEnd.end == CGPoint(x: 230, y: 40) && movedEnd.start == bent.start && movedEnd.control == bent.control)
        let moved = bent.offsetBy(dx: -25, dy: 35)
        precondition(moved.midpoint == CGPoint(x: pointer.x - 25, y: pointer.y + 35), "Moving the arrow must preserve its curvature")
        precondition(!bent.hit(at: CGPoint(x: -300, y: -300), width: 5, curved: false))
        print("Arrow interaction checks passed: on-curve dragging, endpoint movement, rigid translation, curve and circular handle hit testing.")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 720, pixelsHigh: 420, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 720, height: 420).fill()
        for (index, width) in [CGFloat(3), 5, 10].enumerated() {
            let x = CGFloat(index) * 240
            AnnotationArrowRenderer.draw(start: CGPoint(x: x + 45, y: 365), control: CGPoint(x: x + 45, y: 270), end: CGPoint(x: x + 45, y: 175), color: .systemRed, width: width)
            AnnotationArrowRenderer.draw(start: CGPoint(x: x + 90, y: 365), control: CGPoint(x: x + 210, y: 270), end: CGPoint(x: x + 125, y: 175), color: .systemRed, width: width, curved: true)
            if index == 1 {
                let example = AnnotationArrowGeometry(start: CGPoint(x: x + 90, y: 365), control: CGPoint(x: x + 210, y: 270), end: CGPoint(x: x + 125, y: 175))
                for (_, point) in example.handles { AnnotationArrowGeometry.drawHandle(at: point) }
            }
            AnnotationArrowRenderer.draw(start: CGPoint(x: x + 35, y: 75), control: CGPoint(x: x + 110, y: 120), end: CGPoint(x: x + 195, y: 75), color: .systemRed, width: width, style: .double)
        }
        NSGraphicsContext.restoreGraphicsState()
        if CommandLine.arguments.count > 1 {
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        print("Arrow rendering checks passed: filled head, shaft, Retina scale invariance (16 variants).")
    }
}

private extension CGPoint {
    static func * (point: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }
}
