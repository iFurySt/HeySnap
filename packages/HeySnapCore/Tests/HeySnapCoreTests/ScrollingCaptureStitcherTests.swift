import AppKit
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

    @Test func rejectsStationaryAndBlankFrames() throws {
        let image = try syntheticTallImage(width: 48, height: 72)
        var stitcher = ScrollingCaptureStitcher()
        #expect({ stitcher.append(image) }())
        #expect(!{ stitcher.append(image) }())
        #expect(stitcher.estimatedHeight == 72)
        let context = try #require(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let blank = try #require(context.makeImage())
        #expect(ScrollingCaptureStitcher.estimateVerticalShift(from: blank, to: blank) == 0)
    }

    @Test func preservesPixelsAndCapsAtTheCorrectContentRow() throws {
        let full = try syntheticTallImage(width: 48, height: 220)
        let frames = try [0, 24, 48].map { y in
            try #require(full.cropping(to: CGRect(x: 0, y: y, width: 48, height: 72)))
        }
        for height in [110, 120] {
            var stitcher = ScrollingCaptureStitcher(configuration: .init(maxHeight: height, minimumShift: 4,
                maximumShiftRatio: 0.7, sampleStride: 4))
            for frame in frames { #expect({ stitcher.append(frame) }()) }
            let result = try #require(stitcher.stitchedImage())
            let expected = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 48, height: height)))
            #expect(try pixels(result) == pixels(expected))
        }
    }

    @Test func reverseScrollDoesNotDuplicateAlreadyCapturedContent() throws {
        let full = try syntheticTallImage(width: 48, height: 180)
        let top = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 48, height: 72)))
        let bottom = try #require(full.cropping(to: CGRect(x: 0, y: 24, width: 48, height: 72)))
        var stitcher = ScrollingCaptureStitcher(configuration: .init(minimumShift: 4, sampleStride: 4))
        #expect({ stitcher.append(top) }())
        #expect({ stitcher.append(bottom) }())
        #expect(!{ stitcher.append(top) }())
        #expect(!{ stitcher.append(bottom) }())
        #expect(stitcher.estimatedHeight == 96)
    }

    @Test func stitchesTextOnWhiteBackgroundWithoutInventingBlankMovement() throws {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 480, pixelsHigh: 900,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 480, height: 900).fill()
        for row in 0..<25 {
            "Section \(row): a different paragraph \(row * 173)".draw(at: CGPoint(x: 40, y: 870 - row * 33),
                withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        let full = try #require(rep.cgImage)
        var stitcher = ScrollingCaptureStitcher(configuration: .init(minimumShift: 2, sampleStride: 6))
        for y in [0, 97, 213, 213, 300] {
            let frame = try #require(full.cropping(to: CGRect(x: 0, y: y, width: 480, height: 400)))
            _ = stitcher.append(frame)
        }
        let result = try #require(stitcher.stitchedImage())
        #expect(result.height == 700)
        let expected = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 480, height: 700)))
        #expect(try pixels(result) == pixels(expected))
    }

    @Test func capturesEverySinglePixelNudgeIncludingLowContrastContent() throws {
        let full = try syntheticTallImage(width: 48, height: 240)
        var stitcher = ScrollingCaptureStitcher()
        for y in 0...100 {
            let frame = try #require(full.cropping(to: CGRect(x: 0, y: y, width: 48, height: 72)))
            #expect({ stitcher.append(frame) }())
        }
        let result = try #require(stitcher.stitchedImage())
        #expect(result.height == 172)
        #expect(stitcher.frameCount == 2)
        #expect(stitcher.lastAcceptedShift == 1)
        #expect(try pixels(result) == pixels(#require(full.cropping(to: CGRect(x: 0, y: 0, width: 48, height: 172)))))
        let context = try #require(CGContext(data: nil, width: 48, height: 180, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for y in 0..<180 {
            context.setFillColor(CGColor(gray: CGFloat(y) / 255, alpha: 1))
            context.fill(CGRect(x: 0, y: y, width: 48, height: 1))
        }
        let gradient = try #require(context.makeImage())
        var faint = ScrollingCaptureStitcher()
        for y in 0...3 {
            #expect({ faint.append(gradient.cropping(to: CGRect(x: 0, y: y, width: 48, height: 72))!) }())
        }
        #expect(faint.estimatedHeight == 75)
        #expect(!faint.lastFrameWasStationary)
    }

    @Test func aThinLineBetweenSamplingRowsStillMovesByOnePixel() throws {
        let context = try #require(CGContext(data: nil, width: 48, height: 180, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 180))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 176, width: 48, height: 1))
        let full = try #require(context.makeImage())
        var stitcher = ScrollingCaptureStitcher(configuration: .init(minimumShift: 1, sampleStride: 6))
        #expect({ stitcher.append(full.cropping(to: CGRect(x: 0, y: 0, width: 48, height: 72))!) }())
        #expect({ stitcher.append(full.cropping(to: CGRect(x: 0, y: 1, width: 48, height: 72))!) }())
        #expect(stitcher.lastAcceptedShift == 1)
        #expect(stitcher.estimatedHeight == 73)
    }

    @Test func sparseContentDoesNotAliasDuringLargeShiftScreening() throws {
        let context = try #require(CGContext(data: nil, width: 48, height: 900, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 900))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 796, width: 48, height: 1))
        let full = try #require(context.makeImage())
        let first = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 48, height: 400)))
        let second = try #require(full.cropping(to: CGRect(x: 0, y: 80, width: 48, height: 400)))
        #expect(ScrollingCaptureStitcher.estimateVerticalShift(from: first, to: second,
            configuration: .init(minimumShift: 1, sampleStride: 6)) == 80)
    }

    @Test func candidateScreeningKeepsExactLargeAndIrregularShifts() throws {
        let full = try syntheticTallImage(width: 480, height: 1500)
        let first = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 480, height: 800)))
        for shift in [1, 2, 7, 13, 19, 80, 97, 213, 400, 650] {
            let frame = try #require(full.cropping(to: CGRect(x: 0, y: shift, width: 480, height: 800)))
            #expect(ScrollingCaptureStitcher.estimateVerticalShift(from: first, to: frame) == shift)
        }
    }

    @Test func fastScrollAndFixedChromeCanStillMatchTheMovingContent() throws {
        let full = try syntheticTallImage(width: 480, height: 1000)
        let first = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 480, height: 400)))
        let fast = try #require(full.cropping(to: CGRect(x: 0, y: 360, width: 480, height: 400)))
        #expect(ScrollingCaptureStitcher.estimateVerticalShift(from: first, to: fast,
            configuration: .init(minimumShift: 1, sampleStride: 6)) == 360)
        for shift in [38, 97, 180] {
            let second = try #require(full.cropping(to: CGRect(x: 0, y: shift, width: 480, height: 400)))
            let a = try modifiedViewport(first, fixedHeader: 72, sidebar: 150)
            let b = try modifiedViewport(second, fixedHeader: 72, sidebar: 150)
            #expect(ScrollingCaptureStitcher.estimateVerticalShift(from: a, to: b,
                configuration: .init(minimumShift: 1, sampleStride: 6, maximumAveragePixelDistance: 1000)) == shift)
        }
    }

    @Test func noisyFramesRecoverButUnrelatedContentIsNeverAppended() throws {
        let full = try syntheticTallImage(width: 480, height: 1000)
        let first = try #require(full.cropping(to: CGRect(x: 0, y: 0, width: 480, height: 400)))
        let shifted = try #require(full.cropping(to: CGRect(x: 0, y: 97, width: 480, height: 400)))
        let noisy = try modifiedViewport(shifted, noise: 8)
        #expect(ScrollingCaptureStitcher.estimateVerticalShift(from: first, to: noisy,
            configuration: .init(minimumShift: 1, sampleStride: 6, maximumAveragePixelDistance: 1000)) == 97)
        var stitcher = ScrollingCaptureStitcher(configuration: .init(minimumShift: 1, sampleStride: 6))
        #expect({ stitcher.append(first) }())
        let unrelated = try modifiedViewport(first, scramble: true)
        #expect(!{ stitcher.append(unrelated) }())
        #expect(!{ stitcher.append(unrelated) }())
        #expect(stitcher.estimatedHeight == 400)
        #expect({ stitcher.append(shifted) }())
        #expect(stitcher.lastAcceptedShift == 97)
    }

    @Test func bottomWithRepeatingContentAndChangingFooterNeverGrows() throws {
        let width = 480, height = 800, period = 160
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                for c in 0..<3 { bytes[i + c] = UInt8((x * (13 + c) + (y % period) * (7 + c)) % 251) }
            }
        }
        func image(_ footer: Int, _ centerWidget: Bool, phase: Int = 0) throws -> CGImage {
            var data = bytes
            if phase != 0 {
                for y in 0..<height {
                    let sourceRow = ((y + phase) % period + period) % period
                    for x in 0..<width * 4 { data[y * width * 4 + x] = bytes[sourceRow * width * 4 + x] }
                }
            }
            for y in 0..<height {
                for x in 0..<width {
                    if y >= height - 30 || x >= width - 8 || (centerWidget && y >= 370 && y < 430) {
                        let i = (y * width + x) * 4
                        for c in 0..<3 { data[i + c] = UInt8((footer * 19 + x + y + c * 37) % 255) }
                    }
                }
            }
            return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data(data) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        }
        for widget in [false, true] {
            var stitcher = ScrollingCaptureStitcher(configuration: .init(minimumShift: 1, sampleStride: 6,
                maximumAveragePixelDistance: 1000))
            let first = try image(0, widget)
            #expect({ stitcher.append(first) }())
            for i in 1...12 {
                let repeated = try image(i, widget)
                #expect(!{ stitcher.append(repeated) }())
                #expect(stitcher.lastFrameWasStationary)
            }
            for phase in [-1, 0, -3, 0, -7, 0, -15, 0, -30, 0] {
                let rebound = try image(50 + abs(phase), widget, phase: phase)
                #expect(!{ stitcher.append(rebound) }(), "widget=\(widget), phase=\(phase)")
            }
            #expect(stitcher.estimatedHeight == height)
            #expect(stitcher.frameCount == 1)
            #expect(try pixels(#require(stitcher.stitchedImage())) == pixels(first))
        }
    }

    @Test func numberedParagraphFooterReboundsNeverAppendCapturedSections() throws {
        // Match the real verification page: mostly blank rows, similar paragraphs, a unique footer.
        let full = try numberedParagraphPage()
        let viewportHeight = 1538
        let bottom = full.height - viewportHeight
        func viewport(_ y: Int) throws -> CGImage {
            let crop = try #require(full.cropping(to: CGRect(x: 0, y: y, width: full.width, height: viewportHeight)))
            return try modifiedViewport(crop, fixedHeader: 76)
        }
        var stitcher = ScrollingCaptureStitcher(configuration: .init(sampleStride: 6, maximumAveragePixelDistance: 1000))
        var last = 0
        for y in [0, 20, 244, 522, 932, 1374, 1594, 1632, 1962, 2308, 2808, 3222, 3250,
                  3460, 3760, 4058, 4262, 4362, 4700, bottom] {
            let frame = try viewport(y)
            #expect({ stitcher.append(frame) }(), "Forward position \(y)")
            if y > 0 { #expect(stitcher.lastAcceptedShift == y - last) }
            last = y
        }
        let expected = try pixels(#require(stitcher.stitchedImage()))
        #expect(expected == (try pixels(modifiedViewport(full, fixedHeader: 76))))
        for delta in [-159, -88, 0, -156, -153, -87, -133, 0, -264, 0, -133, 0, -13, -153, 0,
                      -1, 0, -7, 0, -360, 0, -720, 0] {
            let frame = try viewport(bottom + delta)
            #expect(!{ stitcher.append(frame) }(), "Footer rebound \(delta)")
            #expect(stitcher.estimatedHeight == full.height)
        }
        #expect(try pixels(#require(stitcher.stitchedImage())) == expected)

        // Rejecting old content must keep the frontier, allowing genuinely new rows afterwards.
        var resumed = ScrollingCaptureStitcher(configuration: .init(sampleStride: 6, maximumAveragePixelDistance: 1000))
        let first = try viewport(bottom - 400)
        let rebound = try viewport(bottom - 559)
        let advanced = try viewport(bottom - 300)
        #expect({ resumed.append(first) }())
        #expect(!{ resumed.append(rebound) }())
        #expect({ resumed.append(advanced) }())
        #expect(resumed.lastAcceptedShift == 100)
        #expect(resumed.estimatedHeight == viewportHeight + 100)
    }

    @Test func settledFooterRejectsRepeatedElasticBackgroundGrowthAndCanResume() throws {
        let full = try numberedParagraphPage()
        let height = 1538, bottom = full.height - height
        func viewport(_ y: Int) throws -> CGImage {
            let context = try #require(CGContext(data: nil, width: full.width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: full.width, height: height))
            let available = min(height, full.height - y)
            let crop = try #require(full.cropping(to: CGRect(x: 0, y: y, width: full.width, height: available)))
            context.draw(crop, in: CGRect(x: 0, y: height - available, width: full.width, height: available))
            return try modifiedViewport(#require(context.makeImage()), fixedHeader: 76)
        }
        let original = try viewport(bottom)
        var stitcher = ScrollingCaptureStitcher(configuration: .init(sampleStride: 6, noMovementLimit: 3,
            maximumAveragePixelDistance: 1000))
        #expect({ stitcher.append(original) }())
        for _ in 0..<3 { #expect(!{ stitcher.append(original) }()) }
        for _ in 0..<3 {
            // Includes tiny positive pulls, a viewport-sized yank, and return below/above the frontier.
            for delta in [1, 2, 8, 10, 472, 0, -128, 592, 1002, 116, 0, -264, 109, 2, 0] {
                let frame = try viewport(bottom + delta)
                #expect(!{ stitcher.append(frame) }(), "Elastic offset \(delta)")
                #expect(stitcher.estimatedHeight == height)
            }
        }
        #expect(try pixels(#require(stitcher.stitchedImage())) == pixels(original))

        // Settling before the last footer padding is visible must also tolerate two backgrounds:
        // footer blue followed by the white area revealed by rubber-band stretching.
        let padded = try viewport(bottom - 54)
        var partialFooter = ScrollingCaptureStitcher(configuration: .init(sampleStride: 6, noMovementLimit: 3,
            maximumAveragePixelDistance: 1000))
        #expect({ partialFooter.append(padded) }())
        for _ in 0..<3 { #expect(!{ partialFooter.append(padded) }()) }
        for delta in [472, 54, 592, 1002, 116, 109, 2, 0] {
            let frame = try viewport(bottom - 54 + delta)
            #expect({ partialFooter.append(frame) }() == (delta == 54), "Partial-footer elastic offset \(delta)")
            #expect(partialFooter.estimatedHeight == height + (delta == 472 ? 0 : 54))
        }
        let completedFooter = try modifiedViewport(#require(full.cropping(to: CGRect(x: 0, y: bottom - 54,
            width: full.width, height: height + 54))), fixedHeader: 76)
        #expect(try pixels(#require(partialFooter.stitchedImage())) == pixels(completedFooter))

        // An ordinary pause over whitespace must not permanently lock a scrollable document.
        var resumed = ScrollingCaptureStitcher(configuration: .init(sampleStride: 6, noMovementLimit: 3,
            maximumAveragePixelDistance: 1000))
        let first = try viewport(850)
        #expect({ resumed.append(first) }())
        for _ in 0..<3 { #expect(!{ resumed.append(first) }()) }
        let whiteGap = try viewport(870)
        #expect(!{ resumed.append(whiteGap) }())
        let nextContent = try viewport(1050)
        #expect({ resumed.append(nextContent) }())
        #expect(resumed.lastAcceptedShift == 200)
        #expect(resumed.estimatedHeight == height + 200)
        let expected = try modifiedViewport(#require(full.cropping(to: CGRect(x: 0, y: 850, width: full.width,
            height: height + 200))), fixedHeader: 76)
        #expect(try pixels(#require(resumed.stitchedImage())) == pixels(expected))
    }

    private func numberedParagraphPage() throws -> CGImage {
        let width = 1196, height = 6300
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: width, height: height).fill()
        func text(_ value: String, _ y: Int, bold: Bool) {
            value.draw(at: CGPoint(x: 22, y: height - y - 64), withAttributes: [
                .font: bold ? NSFont.boldSystemFont(ofSize: 54) : NSFont.systemFont(ofSize: 36),
                .foregroundColor: NSColor(red: 0.09, green: 0.13, blue: 0.18, alpha: 1)])
        }
        text("START — scrolling capture", 40, bold: true)
        for number in 1...16 {
            let y = 300 + (number - 1) * 360
            if number % 3 == 0 {
                NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
                CGRect(x: 0, y: height - y - 360, width: width, height: 360).fill()
            }
            text("Section \(number) — marker \(number * 173)", y + 40, bold: true)
            text("Capture verification paragraph \(number): manual pauses must keep this row; automatic scrolling", y + 132, bold: false)
            NSColor.gray.setFill()
            CGRect(x: 0, y: height - y - 360, width: width, height: 2).fill()
        }
        NSColor(red: 0.91, green: 0.95, blue: 1, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: width, height: 240).fill()
        text("END — all 16 sections captured", height - 200, bold: true)
        text("This footer verifies that capture reached the bottom.", height - 108, bold: false)
        return try #require(rep.cgImage)
    }

    private func modifiedViewport(_ image: CGImage, fixedHeader: Int = 0, sidebar: Int = 0,
                                  noise: Int = 0, scramble: Bool = false) throws -> CGImage {
        var data = [UInt8](try pixels(image))
        for y in 0..<image.height {
            for x in 0..<image.width {
                let index = (y * image.width + x) * 4
                for channel in 0..<3 {
                    if y < fixedHeader || x < sidebar {
                        data[index + channel] = UInt8((x * 7 + y * 11 + channel * 63) % 255)
                    } else if scramble {
                        data[index + channel] = UInt8((x * 137 + y * 53 + channel * 71 + x * y * 7) % 251)
                    } else if noise > 0 {
                        let delta = ((x + y + channel) % 3 - 1) * noise
                        data[index + channel] = UInt8(max(0, min(255, Int(data[index + channel]) + delta)))
                    }
                }
            }
        }
        return try #require(CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(data) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func pixels(_ image: CGImage) throws -> Data {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try #require(context.data), count: image.width * image.height * 4)
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
