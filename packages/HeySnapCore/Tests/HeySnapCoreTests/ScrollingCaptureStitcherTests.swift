import CoreGraphics
import Foundation
import Testing
@testable import HeySnapCore

struct ScrollingCaptureStitcherTests {
    @Test func estimatesVerticalShiftBetweenOverlappingFrames() throws {
        let full = try syntheticTallImage(width: 48, height: 180)
        let first = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 48, height: 72)))
        let second = try #require(full.cropping(to: CGRect(x: 0, y: 24, width: 48, height: 72)))

        let shift = ScrollingCaptureStitcher.estimateVerticalShift(
            from: first,
            to: second,
            configuration: .init(maxHeight: 400, minimumShift: 4, maximumShiftRatio: 0.7, sampleStride: 4, noMovementLimit: 2, maximumAveragePixelDistance: 2_500)
        )

        #expect(abs(shift - 24) <= 1)
    }

    @Test func stitchesAcceptedFramesIntoLongImage() throws {
        let full = try syntheticTallImage(width: 48, height: 220)
        let first = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 48, height: 72)))
        let second = try #require(full.cropping(to: CGRect(x: 0, y: 24, width: 48, height: 72)))
        let third = try #require(full.cropping(to: CGRect(x: 0, y: 48, width: 48, height: 72)))
        var stitcher = ScrollingCaptureStitcher(configuration: .init(maxHeight: 400, minimumShift: 4, maximumShiftRatio: 0.7, sampleStride: 4, noMovementLimit: 2, maximumAveragePixelDistance: 2_500))

        let acceptedFirst = stitcher.append(first)
        let acceptedSecond = stitcher.append(second)
        let acceptedThird = stitcher.append(third)
        let image = try #require(stitcher.stitchedImage())

        #expect(acceptedFirst)
        #expect(acceptedSecond)
        #expect(acceptedThird)
        #expect(stitcher.frameCount == 3)
        #expect(image.width == 48)
        #expect(abs(image.height - 120) <= 2)
    }

    @Test func rejectsTinyShiftsBelowConfiguredMinimum() throws {
        let full = try syntheticTallImage(width: 48, height: 180)
        let first = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 48, height: 72)))
        let second = try #require(full.cropping(to: CGRect(x: 0, y: 8, width: 48, height: 72)))
        var stitcher = ScrollingCaptureStitcher(configuration: .init(maxHeight: 400, minimumShift: 18, maximumShiftRatio: 0.7, sampleStride: 4, noMovementLimit: 2, maximumAveragePixelDistance: 2_500))

        let acceptedFirst = stitcher.append(first)
        let acceptedSecond = stitcher.append(second)

        #expect(acceptedFirst)
        #expect(!acceptedSecond)
        #expect(stitcher.frameCount == 1)
        #expect(stitcher.noMovementStreak == 1)
    }

    private func syntheticTallImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 255, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                data[offset] = UInt8((x * 13 + y * 7) % 251)
                data[offset + 1] = UInt8((x * 5 + y * 17) % 253)
                data[offset + 2] = UInt8((x * 23 + y * 3) % 247)
                data[offset + 3] = 255
            }
        }
        let provider = try #require(CGDataProvider(data: Data(data) as CFData))
        return try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }
}
