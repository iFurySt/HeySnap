import CoreGraphics
import Foundation

enum ScreenshotWindowBackgroundRenderer {
    static func composite(_ foreground: CGImage, over color: CGColor) -> CGImage {
        render(width: foreground.width, height: foreground.height) { context, rect in
            context.setFillColor(color)
            context.fill(rect)
            context.draw(foreground, in: rect)
        } ?? foreground
    }

    static func shadowed(_ foreground: CGImage) -> CGImage {
        let padding = shadowPadding(for: foreground)
        let width = foreground.width + padding * 2
        let height = foreground.height + padding * 2
        return render(width: width, height: height) { context, rect in
            let shadowColor = CGColor(gray: 0, alpha: 0.18)
            context.setShadow(offset: CGSize(width: 0, height: -2), blur: CGFloat(padding) * 0.42, color: shadowColor)
            context.draw(
                foreground,
                in: CGRect(
                    x: padding,
                    y: padding,
                    width: foreground.width,
                    height: foreground.height
                )
            )
        } ?? foreground
    }

    static func composite(_ foreground: CGImage, over background: CGImage) -> CGImage {
        render(width: foreground.width, height: foreground.height) { context, rect in
            context.interpolationQuality = .high
            context.draw(background, in: rect)
            context.draw(foreground, in: rect)
        } ?? foreground
    }

    private static func shadowPadding(for image: CGImage) -> Int {
        let shortEdge = min(image.width, image.height)
        return max(24, min(96, Int((Double(shortEdge) * 0.08).rounded())))
    }

    private static func render(
        width: Int,
        height: Int,
        draw: (CGContext, CGRect) -> Void
    ) -> CGImage? {
        guard width > 0, height > 0 else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        draw(context, rect)
        return context.makeImage()
    }
}
