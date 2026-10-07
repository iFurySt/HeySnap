import AppKit

@main
struct CaptureSnapshotTests {
    static func main() throws {
        let sourceRect = CGRect(x: -100, y: -200, width: 200, height: 200)
        for scale in [1, 2] {
            let bitmap = render(width: 200 * scale, height: 200 * scale) {
                NSColor.red.setFill(); CGRect(x: 0, y: 100 * scale, width: 200 * scale, height: 100 * scale).fill()
                NSColor.blue.setFill(); CGRect(x: 0, y: 0, width: 200 * scale, height: 100 * scale).fill()
            }
            let frozen = bitmap.cgImage!
            // Above/below and left/right screens must all use the same global frame.
            for rect in [CGRect(x: -100, y: -100, width: 100, height: 100), CGRect(x: 0, y: -200, width: 100, height: 100)] {
                let crop = CaptureSnapshotGeometry.crop(frozen, sourceRect: sourceRect, to: rect)!
                precondition(crop.width == 100 * scale && crop.height == 100 * scale)
                let rep = NSBitmapImageRep(cgImage: crop)
                let expectedY = rect.minY == -100 ? 25 : 125
                precondition(same(rep.colorAt(x: 25 * scale, y: 25 * scale)!, bitmap.colorAt(x: 25 * scale, y: expectedY * scale)!))
            }
            precondition(CaptureSnapshotGeometry.crop(frozen, sourceRect: sourceRect, to: CGRect(x: 100, y: 0, width: 10, height: 10)) == nil)
            let bounds = CGRect(x: 0, y: 0, width: 200 * scale, height: 200 * scale)
            let selection = CGRect(x: 20 * scale, y: 20 * scale, width: 160 * scale, height: 160 * scale)
            let overlay = render(width: 200 * scale, height: 200 * scale) {
                // A live window has already changed to green, then multiple redraws occur.
                NSColor.green.setFill(); bounds.fill()
                for _ in 0..<3 { CaptureSnapshotGeometry.drawBackdrop(frozen, in: bounds, selection: selection) }
            }
            let selected = overlay.colorAt(x: 50 * scale, y: 50 * scale)!
            precondition(selected.alphaComponent == 1, "Selection must remain opaque, never reveal the live desktop")
            precondition(same(selected, bitmap.colorAt(x: 50 * scale, y: 50 * scale)!))
            let outside = overlay.colorAt(x: 5 * scale, y: 5 * scale)!.usingColorSpace(.deviceRGB)!
            precondition(outside.alphaComponent == 1 && outside.redComponent > 0.6 && outside.redComponent < 0.8, "Mask must dim the captured frame without accumulating")
            let live = render(width: 200 * scale, height: 200 * scale) {
                CaptureSnapshotGeometry.drawBackdrop(nil, in: bounds, selection: selection)
            }
            precondition(live.colorAt(x: 50 * scale, y: 50 * scale)!.alphaComponent == 0, "Scrolling must reveal the live selected region")
            if CommandLine.arguments.count > 1 {
                try overlay.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "-\(scale)x.png"))
            }
        }
        print("Frozen capture passed: global/negative-origin screen crops, 1x/2x pixels, opaque selection, stable redraws, and live scrolling fallback.")
    }

    static func render(width: Int, height: Int, draw: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(); NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func same(_ a: NSColor, _ b: NSColor) -> Bool {
        let a = a.usingColorSpace(.deviceRGB)!, b = b.usingColorSpace(.deviceRGB)!
        return abs(a.redComponent - b.redComponent) < 0.01 && abs(a.greenComponent - b.greenComponent) < 0.01 && abs(a.blueComponent - b.blueComponent) < 0.01
    }
}
