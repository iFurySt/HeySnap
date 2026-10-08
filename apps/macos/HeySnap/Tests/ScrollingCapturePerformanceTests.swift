import CoreGraphics
import Foundation

/// Release-mode synthetic benchmark. It does not exercise the WindowServer capture latency.
@main
struct ScrollingCapturePerformanceTests {
    static func main() throws {
        let width = 2400, height = 1600
        var bytes = [UInt8](repeating: 255, count: width * 2400 * 4)
        for y in 0..<2400 {
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i] = UInt8((x * 13 + y * 7) % 251)
                bytes[i + 1] = UInt8((x * 5 + y * 17) % 253)
                bytes[i + 2] = UInt8((x * 23 + y * 3) % 247)
            }
        }
        let full = CGImage(width: width, height: 2400, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let first = full.cropping(to: CGRect(x: 0, y: 0, width: width, height: height))!
        for shift in [0, 1, 80, 400] {
            let next = full.cropping(to: CGRect(x: 0, y: shift, width: width, height: height))!
            let baseline = measure {
                require(exhaustiveShift(first, next) == shift)
            }
            var cached = ScrollingCaptureStitcher(configuration: .init(minimumShift: 1, sampleStride: 6))
            require(cached.append(first))
            let optimized = measure {
                var copy = cached
                require(copy.append(next) == (shift > 0))
                if shift > 0 { require(copy.lastAcceptedShift == shift) }
            }
            print(String(format: "2400x1600 shift=%d: exhaustiveMatch=%.2f ms cachedAppend=%.2f ms speedup=%.1fx", shift, baseline, optimized, baseline / optimized))
        }
        func withFixedChrome(_ image: CGImage) -> CGImage {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(first.cropping(to: CGRect(x: 0, y: 0, width: 700, height: height))!,
                in: CGRect(x: 0, y: 0, width: 700, height: height))
            context.draw(first.cropping(to: CGRect(x: 0, y: 0, width: width, height: 180))!,
                in: CGRect(x: 0, y: height - 180, width: width, height: 180))
            return context.makeImage()!
        }
        let chromeFirst = withFixedChrome(first)
        let chromeNext = withFixedChrome(full.cropping(to: CGRect(x: 0, y: 80, width: width, height: height))!)
        let recoveryMS = measure {
            let shift = ScrollingCaptureStitcher.estimateVerticalShift(from: chromeFirst, to: chromeNext,
                configuration: .init(minimumShift: 1, sampleStride: 6, maximumAveragePixelDistance: 1000))
            if shift != 80 { print("Fixed chrome actual shift=\(shift)") }
            require(shift == 80)
        }
        print(String(format: "Fixed header/sidebar recovery: %.2f ms", recoveryMS))
        let pullContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pullContext.setFillColor(CGColor(gray: 1, alpha: 1))
        pullContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let pull = 472
        pullContext.draw(first.cropping(to: CGRect(x: 0, y: pull, width: width, height: height - pull))!,
            in: CGRect(x: 0, y: pull, width: width, height: height - pull))
        let elastic = pullContext.makeImage()!
        var settled = ScrollingCaptureStitcher(configuration: .init(sampleStride: 6, noMovementLimit: 3))
        require(settled.append(first))
        for _ in 0..<3 { require(!settled.append(first)) }
        let elasticMS = measure {
            var copy = settled
            require(!copy.append(elastic) && copy.estimatedHeight == height)
        }
        print(String(format: "Settled elastic-background rejection: %.2f ms", elasticMS))
        var stitcher = ScrollingCaptureStitcher(configuration: .init(minimumShift: 1, sampleStride: 6))
        _ = stitcher.append(first)
        let began = Date()
        for y in 1...400 {
            require(stitcher.append(full.cropping(to: CGRect(x: 0, y: y, width: width, height: height))!))
        }
        let appendMS = Date().timeIntervalSince(began) * 1000 / 400
        let previewMS = measure {
            let preview = stitcher.stitchedImage(previewSize: CGSize(width: 352, height: 2200))!
            require(preview.width <= 352 && preview.height <= 2200)
        }
        require(stitcher.estimatedHeight == 2000 && stitcher.frameCount == 5)
        print(String(format: "400 one-pixel nudges: append=%.2f ms/frame retainedBlocks=%d preview=%.2f ms", appendMS, stitcher.frameCount, previewMS))
    }

    static func require(_ condition: Bool, line: Int = #line) {
        if !condition {
            FileHandle.standardError.write(Data("Scrolling performance correctness failed at line \(line)\n".utf8))
            exit(1)
        }
    }

    static func measure(_ body: () -> Void) -> Double {
        body()
        var durations: [Double] = []
        for _ in 0..<5 {
            let begin = Date()
            body()
            durations.append(Date().timeIntervalSince(begin) * 1000)
        }
        return durations.sorted()[2]
    }

    /// Previous full-grid exhaustive search, same downsample and confidence criterion.
    static func exhaustiveShift(_ previous: CGImage, _ current: CGImage) -> Int {
        let width = 160, height = previous.height
        func sample(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return data
        }
        let a = sample(previous), b = sample(current)
        func score(_ shift: Int) -> Double {
            var sum: UInt64 = 0, count: UInt64 = 0
            for y in stride(from: 0, to: height - shift, by: 6) {
                for x in stride(from: 0, to: width, by: 6) {
                    let i = ((y + shift) * width + x) * 4, j = (y * width + x) * 4
                    for channel in 0..<3 {
                        let delta = Int(a[i + channel]) - Int(b[j + channel])
                        sum += UInt64(delta * delta)
                    }
                    count += 1
                }
            }
            return Double(sum) / Double(count)
        }
        let stationary = score(0)
        if stationary == 0 { return 0 }
        var best = Double.infinity, shift = 0
        for candidate in 1...Int(Double(height) * 0.82) {
            let distance = score(candidate)
            if distance < best { best = distance; shift = candidate }
        }
        return best < stationary * 0.35 ? shift : 0
    }
}
