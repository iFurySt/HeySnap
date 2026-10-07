import AppKit

@main
struct QuickMarkupPropertyBarLayoutTests {
    static func main() throws {
        let layout = QuickMarkupPropertyBarLayout(sizeCount: AnnotationDefaults.quickMarkupLineWidths.count)
        let bar = CGRect(origin: CGPoint(x: 16, y: 16), size: layout.size)
        precondition(layout.size.width == 298, "Three sizes must not reserve space for a fourth")
        for index in 0..<3 {
            let item = layout.itemRect(at: index, in: bar)
            precondition(bar.contains(item), "Every visible size must fit inside the bar")
            precondition(layout.sizeIndex(at: CGPoint(x: item.midX, y: item.midY), in: bar) == index)
        }
        precondition(layout.sizeIndex(at: CGPoint(x: bar.minX + 308, y: bar.midY), in: bar) == nil, "Phantom fourth size must not be clickable")
        precondition(layout.sizeIndex(at: CGPoint(x: bar.maxX - 2, y: bar.midY), in: bar) == nil, "Trailing padding must not select the last size")
        precondition(layout.sizeIndex(at: CGPoint(x: bar.minX + 196, y: bar.midY), in: bar) == nil, "Separator gap must not select the first size")
        let textLayout = QuickMarkupPropertyBarLayout(sizeCount: 4)
        precondition(textLayout.sizeIndex(at: CGPoint(x: 308, y: 21), in: CGRect(origin: .zero, size: textLayout.size)) == 3, "Text must retain its fourth font size")

        let center = CGPoint(x: bar.minX + 14, y: bar.midY)
        let check = QuickMarkupPropertyBarIcons.colorCheckmark(centeredAt: center)
        precondition(abs(check.bounds.midX - center.x) < 0.001 && abs(check.bounds.midY - center.y) < 0.001, "Checkmark must be centered on both axes")
        precondition(check.bounds.width + check.lineWidth < 10 && check.bounds.height + check.lineWidth < 10, "Checkmark must leave padding in the 16-point swatch")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 330, pixelsHigh: 74, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 330, height: 74).fill()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 10, yRadius: 10).fill()
        let colors: [NSColor] = [AnnotationDefaults.color, .systemYellow, .systemGreen, .systemBlue, .black, .systemGray, .white]
        for (index, color) in colors.enumerated() {
            let p = CGPoint(x: bar.minX + 14 + CGFloat(index) * 26, y: bar.midY)
            let swatch = NSBezierPath(ovalIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
            color.setFill(); swatch.fill()
            NSColor.separatorColor.setStroke(); swatch.lineWidth = 1; swatch.stroke()
            if index == 0 { NSColor.white.setStroke(); QuickMarkupPropertyBarIcons.colorCheckmark(centeredAt: p).stroke() }
        }
        for (index, diameter) in [CGFloat(6), 10, 14].enumerated() {
            let item = layout.itemRect(at: index, in: bar)
            (index == 1 ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setFill()
            NSBezierPath(ovalIn: CGRect(x: item.midX - diameter / 2, y: item.midY - diameter / 2, width: diameter, height: diameter)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        if CommandLine.arguments.count > 1 {
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        print("Quick markup controls passed: three size hit boxes, no phantom size, four text sizes, smaller centered checkmark.")
    }
}
