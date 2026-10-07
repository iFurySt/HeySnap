import AppKit

/// The visible desktop and exported region must come from the same immutable frame.
enum CaptureSnapshotGeometry {
    static func crop(_ image: CGImage, sourceRect: CGRect, to rect: CGRect) -> CGImage? {
        guard sourceRect.width > 0, sourceRect.height > 0, rect.width > 0, rect.height > 0,
              sourceRect.contains(rect) else { return nil }
        let scaleX = CGFloat(image.width) / sourceRect.width
        let scaleY = CGFloat(image.height) / sourceRect.height
        return image.cropping(to: CGRect(
            x: (rect.minX - sourceRect.minX) * scaleX,
            y: (sourceRect.maxY - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral)
    }

    static func drawBackdrop(_ image: CGImage?, in bounds: CGRect, selection: CGRect?) {
        if let image {
            NSImage(cgImage: image, size: bounds.size).draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        }
        let mask = NSBezierPath(rect: bounds)
        if let selection { mask.append(NSBezierPath(rect: selection)); mask.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(0.32).setFill()
        mask.fill()
        // Live desktop is only used by legacy capture and while scrolling. Do not clear
        // the frozen selection: doing so would expose the changing window underneath.
        if image == nil, let selection { selection.fill(using: .clear) }
    }
}
