import AppKit

@main
struct BasicAnnotationTests {
    static func main() throws {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 480)
        let rect = CGRect(x: 70, y: 100, width: 200, height: 120)
        for kind in [AnnotationShapeKind.rectangle, .oval] {
            precondition(!AnnotationShapeGeometry.hitStroke(at: CGPoint(x: rect.midX, y: rect.midY), kind: kind, rect: rect, width: 5), "Hollow interiors must not grab the shape")
            precondition(AnnotationShapeGeometry.hitStroke(at: CGPoint(x: rect.maxX, y: rect.midY), kind: kind, rect: rect, width: 5))
        }
        let flippedRect = mirror(rect, within: bounds)
        for handle in AnnotationShapeHandle.allCases {
            let topDown = handle.point(in: rect)
            let bottomUp = handle.point(in: flippedRect, flipped: false)
            precondition(near(topDown, mirror(bottomUp, within: bounds)), "Visual handles must agree across coordinate systems")
            let target = CGPoint(x: topDown.x + 25, y: topDown.y + 17)
            for constrained in [false, true] {
                let editorRect = AnnotationShapeGeometry.resized(rect, handle: handle, to: target, within: bounds, constrained: constrained)
                let overlay = OverlayMarkupAnnotation(tool: .rectangle, start: flippedRect.origin, end: CGPoint(x: flippedRect.maxX, y: flippedRect.maxY))
                let quickRect = overlay.updating(handle: OverlayAnnotationHandle(shapeHandle: handle), to: mirror(target, within: bounds), within: bounds, constrained: constrained).rect
                precondition(editorRect == mirror(quickRect, within: bounds), "Resize adapters must preserve Editor behavior for all eight handles")
                if constrained { precondition(editorRect.width == editorRect.height) }
            }
        }
        let square = AnnotationShapeGeometry.normalized(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 40, y: 260), constrained: true)
        precondition(square == CGRect(x: 40, y: 100, width: 60, height: 60))

        for handle in AnnotationShapeHandle.allCases {
            let anchor = handle.point(in: rect, kind: .oval)
            let nx = (anchor.x - rect.midX) / (rect.width / 2)
            let ny = (anchor.y - rect.midY) / (rect.height / 2)
            precondition(abs(nx * nx + ny * ny - 1) < 0.0001, "Every ellipse anchor must sit on its outline")
            precondition(AnnotationShapeGeometry.hitHandle(at: anchor, rect: rect, kind: .oval) == handle)
            let unchanged = AnnotationShapeGeometry.resized(rect, handle: handle, to: anchor, within: bounds, constrained: false, kind: .oval)
            precondition(near(unchanged.origin, rect.origin) && abs(unchanged.width - rect.width) < 0.001 && abs(unchanged.height - rect.height) < 0.001, "Grabbing an ellipse knob must not jump")
            let target = CGPoint(x: anchor.x + 10, y: anchor.y + 10)
            let resized = AnnotationShapeGeometry.resized(rect, handle: handle, to: target, within: bounds, constrained: false, kind: .oval)
            if handle.isCorner { precondition(near(handle.point(in: resized, kind: .oval), target), "The diagonal knob must follow the pointer") }
            for constrained in [false, true] {
                let editor = AnnotationShapeGeometry.resized(rect, handle: handle, to: target, within: bounds, constrained: constrained, kind: .oval)
                let overlay = OverlayMarkupAnnotation(tool: .oval, start: flippedRect.origin, end: CGPoint(x: flippedRect.maxX, y: flippedRect.maxY))
                let quick = mirror(overlay.updating(handle: OverlayAnnotationHandle(shapeHandle: handle), to: mirror(target, within: bounds), within: bounds, constrained: constrained).rect, within: bounds)
                precondition(near(editor.origin, quick.origin) && abs(editor.width - quick.width) < 0.001 && abs(editor.height - quick.height) < 0.001)
                if constrained { precondition(abs(editor.width - editor.height) < 0.001) }
            }
        }
        precondition(AnnotationShapeGeometry.hitHandle(at: rect.origin, rect: rect, kind: .oval) == nil, "Old bounding corners must not remain clickable")

        let start = CGPoint(x: 40, y: 60), end = CGPoint(x: 240, y: 60), control = CGPoint(x: 140, y: 60)
        let pointer = CGPoint(x: 170, y: 150)
        let editorLine = EditorAnnotation(kind: .line(control: control), start: start, end: end, color: AnnotationDefaults.color, lineWidth: 5).updatingLineHandle(.control, to: pointer)
        let quickLine = OverlayMarkupAnnotation(tool: .line, start: start, end: end).updating(handle: .control, to: pointer, within: bounds, constrained: false)
        precondition(editorLine.lineControlPoint() == quickLine.control)
        precondition(editorLine.lineCurveMidpoint() == pointer && quickLine.handlePoints[1].1 == pointer, "Line's middle handle must stay on the drawn curve")
        let geometry = quickLine.arrowGeometry
        precondition(geometry.hit(at: pointer, width: 5, curved: false, includesArrowhead: false), "Bent line must be hittable off its endpoint chord")
        precondition(!geometry.hit(at: CGPoint(x: 140, y: 60), width: 5, curved: false, includesArrowhead: false), "Empty chord must not grab a bent line")
        let path = AnnotationLineRenderer.path(start: start, control: geometry.control, end: end, width: 5)
        precondition(path.lineCapStyle == .round)
        let translated = quickLine.offsetBy(dx: 30, dy: -10)
        let movedEditor = editorLine.offsetBy(dx: 30, dy: -10)
        precondition(translated.control == movedEditor.lineControlPoint() && translated.start == movedEditor.start && translated.end == movedEditor.end)

        let normal = OverlayMarkupAnnotation(tool: .text, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), text: "中文 Text")
        let filled = normal.withTextStyle(filled: true)
        precondition(filled.color == .white && filled.textFillColor == normal.color)
        let plainAgain = filled.withTextStyle(filled: false)
        precondition(plainAgain.color == normal.color && plainAgain.textFillColor.alphaComponent == 0)
        precondition(filled.withStyle(color: filled.color, lineWidth: 7, fontSize: 20).textFillColor == filled.textFillColor, "Font/style copies must keep text background")
        precondition(normal.fontSize == AnnotationDefaults.textFontSize)
        for text in ["", "中文 Text", "第一行\nSecond line", "A long piece of text that must grow while typing"] {
            let one = AnnotationTextRenderer.boxSize(for: text, fontSize: 12)
            let two = AnnotationTextRenderer.boxSize(for: text, fontSize: 12, scale: 2)
            precondition(abs(two.width - 2 * one.width) <= 2 && abs(two.height - 2 * one.height) <= 2, "Retina text geometry must scale font and padding together")
        }
        let grown = AnnotationTextRenderer.autosizedRect(rect, text: String(repeating: "Text ", count: 8), fontSize: 12, within: bounds)
        let shrunk = AnnotationTextRenderer.autosizedRect(grown, text: "Hi", fontSize: 12, within: bounds)
        precondition(shrunk.width < grown.width, "Deleting text must shrink the box like Editor")
        precondition(AnnotationTextRenderer.boxSize(for: "A\nB", fontSize: 12).height > AnnotationTextRenderer.boxSize(for: "A", fontSize: 12).height)
        let reverse = AnnotationTextRenderer.fittedRect(from: CGPoint(x: 220, y: 150), to: CGPoint(x: 80, y: 60), text: "", fontSize: 12, within: bounds)
        precondition(reverse.minX == 80 && reverse.minY == 60, "Reverse text drags must use the normalized origin")
        let textBar = CGRect(x: 0, y: 0, width: 330, height: 76)
        precondition(QuickMarkupPropertyBarLayout.textStyle(at: CGPoint(x: 48, y: 19), in: textBar) == false)
        precondition(QuickMarkupPropertyBarLayout.textStyle(at: CGPoint(x: 132, y: 19), in: textBar) == true)
        precondition(QuickMarkupPropertyBarLayout.textStyle(at: CGPoint(x: 48, y: 60), in: textBar) == nil)

        let input = AnnotationInlineTextView(frame: rect)
        var updates = 0, cancelled = false
        input.onEditingLayoutChange = { updates += 1 }
        input.onCancel = { cancelled = true }
        AnnotationTextRenderer.configure(input, color: filled.color, fillColor: filled.textFillColor, fontSize: 12)
        input.insertText("中文 Text", replacementRange: NSRange(location: 0, length: 0))
        precondition(input.string == "中文 Text" && updates > 0, "Shared text input must publish live layout changes")
        input.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        precondition(cancelled, "Escape must route to canceling the text edit")
        precondition(input.selectionRingLayer.superlayer != nil)

        let parent = NSView(frame: bounds)
        parent.addSubview(input)
        input.forwardsBorderMouseEvents = true
        let border = CGPoint(x: rect.minX + 3, y: rect.midY)
        precondition(parent.hitTest(border) === parent, "Text border must pass mouse events to the canvas for dragging")
        precondition(parent.hitTest(CGPoint(x: rect.midX, y: rect.midY)) === input, "Text interior must remain editable")
        let movedText = filled.offsetBy(dx: 20, dy: 30)
        precondition(movedText.rect == filled.rect.offsetBy(dx: 20, dy: 30) && movedText.text == filled.text && movedText.textFillColor == filled.textFillColor)

        if CommandLine.arguments.count > 1 {
            for scale: CGFloat in [1, 2] { try preview(scale: scale).write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "-\(Int(scale))x.png")) }
        }
        print("Basic annotations passed: hollow shape hit tests, 16 resize/coordinate adapters, line midpoint and movement, normal/filled text, autosizing, Retina, shared text input and style controls.")
    }

    static func preview(scale: CGFloat) throws -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(640 * scale), pixelsHigh: Int(360 * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 640 * scale, height: 360 * scale).fill()
        let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
        let color = AnnotationDefaults.color
        let rectangle = CGRect(x: 35, y: 195, width: 165, height: 110)
        let oval = CGRect(x: 245, y: 195, width: 165, height: 110)
        AnnotationShapeGeometry.draw(.rectangle, in: rectangle, color: color, width: 5)
        AnnotationShapeGeometry.draw(.oval, in: oval, color: color, width: 5)
        for (rect, kind) in [(rectangle, AnnotationShapeKind.rectangle), (oval, .oval)] {
            for handle in AnnotationShapeHandle.allCases { AnnotationArrowGeometry.drawHandle(at: handle.point(in: rect, kind: kind)) }
        }
        let line = AnnotationLineGeometry(start: CGPoint(x: 455, y: 280), control: CGPoint(x: 620, y: 255), end: CGPoint(x: 480, y: 180))
        AnnotationLineRenderer.draw(start: line.start, control: line.control, end: line.end, color: color, width: 5)
        for (_, p) in line.handles { AnnotationArrowGeometry.drawHandle(at: p) }
        AnnotationTextRenderer.draw("Normal 中文", in: CGRect(x: 35, y: 70, width: 165, height: 55), color: color, fontSize: 12, selected: true)
        AnnotationTextRenderer.draw("Filled 中文", in: CGRect(x: 245, y: 70, width: 165, height: 55), color: .white, fontSize: 12, fillColor: color, selected: true)
        AnnotationTextRenderer.draw("第一行\nSecond line", in: CGRect(x: 455, y: 65, width: 165, height: 65), color: color, fontSize: 12)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }

    static func mirror(_ point: CGPoint, within bounds: CGRect) -> CGPoint { CGPoint(x: point.x, y: bounds.minY + bounds.maxY - point.y) }
    static func mirror(_ rect: CGRect, within bounds: CGRect) -> CGRect { CGRect(x: rect.minX, y: bounds.minY + bounds.maxY - rect.maxY, width: rect.width, height: rect.height) }
    static func near(_ a: CGPoint, _ b: CGPoint) -> Bool { hypot(a.x - b.x, a.y - b.y) < 0.001 }
}
