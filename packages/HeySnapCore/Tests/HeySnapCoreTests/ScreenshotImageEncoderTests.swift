@testable import HeySnapCore
import CoreGraphics
import Foundation
import Testing

@Suite("Screenshot image encoder")
struct ScreenshotImageEncoderTests {
    @Test("Auto keeps PNG when PNG is small")
    func autoKeepsSmallPNG() throws {
        let selected = try ScreenshotImageEncoder.selectAutomaticCandidate(from: [
            candidate(.png, bytes: 400_000),
            candidate(.jpeg, bytes: 20_000)
        ])

        #expect(selected.format == .png)
    }

    @Test("Auto chooses JPEG when PNG is above half a megabyte and JPEG is under a quarter")
    func autoChoosesJPEGForMediumLargePNGWhenMuchSmaller() throws {
        let selected = try ScreenshotImageEncoder.selectAutomaticCandidate(from: [
            candidate(.png, bytes: 700_000),
            candidate(.jpeg, bytes: 150_000)
        ])

        #expect(selected.format == .jpeg)
    }

    @Test("Auto chooses PNG when JPEG does not cross the medium-size ratio")
    func autoKeepsPNGWhenJPEGIsNotSmallEnough() throws {
        let selected = try ScreenshotImageEncoder.selectAutomaticCandidate(from: [
            candidate(.png, bytes: 700_000),
            candidate(.jpeg, bytes: 200_000)
        ])

        #expect(selected.format == .png)
    }

    @Test("Auto chooses JPEG when PNG is above two megabytes and JPEG is under half")
    func autoChoosesJPEGForLargePNGWhenSmaller() throws {
        let selected = try ScreenshotImageEncoder.selectAutomaticCandidate(from: [
            candidate(.png, bytes: 3_000_000),
            candidate(.jpeg, bytes: 1_200_000)
        ])

        #expect(selected.format == .jpeg)
    }

    @Test("Auto without PNG chooses the smallest lossy candidate")
    func autoWithoutPNGChoosesSmallestCandidate() throws {
        let selected = try ScreenshotImageEncoder.selectAutomaticCandidate(from: [
            candidate(.jpeg, bytes: 80_000),
            candidate(.webp, bytes: 60_000)
        ])

        #expect(selected.format == .webp)
    }

    @Test("Explicit formats encode image data")
    func explicitFormatsEncodeImageData() throws {
        let image = try syntheticImage()

        for format in ScreenshotOutputFormat.allCases {
            let encoded = try ScreenshotImageEncoder.encode(image, as: format)
            #expect(encoded.format == format)
            #expect(!encoded.data.isEmpty)
        }
    }

    @Test("Retina downscale halves two-times screenshots when enabled")
    func retinaDownscaleHalvesTwoTimesScreenshotsWhenEnabled() throws {
        let image = try syntheticImage(width: 20, height: 12)

        let downscaled = try ScreenshotImageResizer.downscaleRetinaIfNeeded(
            image,
            sourceScaleFactor: 2,
            shouldDownscale: true
        )

        #expect(downscaled.width == 10)
        #expect(downscaled.height == 6)
    }

    @Test("Retina downscale leaves images unchanged when disabled")
    func retinaDownscaleLeavesImagesUnchangedWhenDisabled() throws {
        let image = try syntheticImage(width: 20, height: 12)

        let output = try ScreenshotImageResizer.downscaleRetinaIfNeeded(
            image,
            sourceScaleFactor: 2,
            shouldDownscale: false
        )

        #expect(output.width == 20)
        #expect(output.height == 12)
    }

    @Test("Retina downscale leaves one-times screenshots unchanged")
    func retinaDownscaleLeavesOneTimesScreenshotsUnchanged() throws {
        let image = try syntheticImage(width: 20, height: 12)

        let output = try ScreenshotImageResizer.downscaleRetinaIfNeeded(
            image,
            sourceScaleFactor: 1,
            shouldDownscale: true
        )

        #expect(output.width == 20)
        #expect(output.height == 12)
    }

    @Test("Shadow background expands the transparent canvas")
    func shadowBackgroundExpandsTransparentCanvas() throws {
        let image = try syntheticImage(
            width: 6,
            height: 6,
            opaqueRect: CGRect(x: 2, y: 1, width: 3, height: 4)
        )

        let shadowedImage = ScreenshotWindowBackgroundRenderer.shadowed(image)

        #expect(shadowedImage.width > image.width)
        #expect(shadowedImage.height > image.height)
        #expect(shadowedImage.width - image.width == shadowedImage.height - image.height)
    }

    @Test("Solid color background keeps the image canvas size")
    func solidColorBackgroundKeepsImageCanvasSize() throws {
        let image = try syntheticImage(width: 100, height: 80)

        let compositedImage = ScreenshotWindowBackgroundRenderer.composite(image, over: CGColor(gray: 0.2, alpha: 1))

        #expect(compositedImage.width == image.width)
        #expect(compositedImage.height == image.height)
    }

    private func candidate(_ format: ScreenshotOutputFormat, bytes: Int) -> EncodedScreenshot {
        EncodedScreenshot(format: format, data: Data(repeating: 0, count: bytes))
    }

    private func syntheticImage(width: Int = 8, height: Int = 8) throws -> CGImage {
        try syntheticImage(width: width, height: height, opaqueRect: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private func syntheticImage(width: Int, height: Int, opaqueRect: CGRect) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                pixels[index] = 64
                pixels[index + 1] = 128
                pixels[index + 2] = 192
                pixels[index + 3] = opaqueRect.contains(CGPoint(x: x, y: y)) ? 255 : 0
            }
        }

        guard
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            throw SyntheticImageError()
        }

        return image
    }
}

private struct SyntheticImageError: Error {}
