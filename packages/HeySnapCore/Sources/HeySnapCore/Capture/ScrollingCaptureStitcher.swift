import CoreGraphics
import Foundation

struct ScrollingCaptureStitcher {
    struct Configuration {
        var maxHeight: Int = 20_000
        var minimumShift: Int = 8
        var maximumShiftRatio: CGFloat = 0.82
        var sampleStride: Int = 12
        var noMovementLimit: Int = 2
        var maximumAveragePixelDistance: UInt64 = 2_500

        static let `default` = Configuration()
    }

    private let configuration: Configuration
    private var frames: [CGImage] = []
    private var verticalShifts: [Int] = []
    private var noMovementCount = 0

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    var frameCount: Int {
        frames.count
    }

    var estimatedHeight: Int {
        guard let first = frames.first else { return 0 }
        return verticalShifts.reduce(first.height, +)
    }

    var shouldStop: Bool {
        noMovementCount >= configuration.noMovementLimit || estimatedHeight >= configuration.maxHeight
    }

    var noMovementStreak: Int {
        noMovementCount
    }

    var lastAcceptedShift: Int? {
        verticalShifts.last
    }

    mutating func append(_ image: CGImage) -> Bool {
        guard let first = frames.first else {
            frames.append(image)
            return true
        }
        guard image.width == first.width, image.height == first.height else {
            return false
        }

        guard let previous = frames.last else {
            frames.append(image)
            return true
        }

        guard let estimate = Self.estimateVerticalShiftCandidate(
            from: previous,
            to: image,
            configuration: configuration
        ) else {
            noMovementCount += 1
            return false
        }

        noMovementCount = 0
        verticalShifts.append(estimate.shift)
        frames.append(image)
        return true
    }

    func stitchedImage() -> CGImage? {
        guard let first = frames.first else { return nil }
        guard frames.count > 1 else { return first }

        let width = first.width
        let height = min(configuration.maxHeight, estimatedHeight)
        let colorSpace = first.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
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

        context.interpolationQuality = .none

        draw(first, cropY: 0, cropHeight: first.height, destinationY: 0, in: context, outputHeight: height)
        var outputY = first.height
        for (index, frame) in frames.dropFirst().enumerated() {
            let shift = min(verticalShifts[index], frame.height)
            let remaining = height - outputY
            guard remaining > 0 else { break }
            let cropHeight = min(shift, remaining)
            draw(
                frame,
                cropY: frame.height - cropHeight,
                cropHeight: cropHeight,
                destinationY: outputY,
                in: context,
                outputHeight: height
            )
            outputY += cropHeight
        }

        return context.makeImage()
    }

    static func estimateVerticalShift(
        from previous: CGImage,
        to current: CGImage,
        configuration: Configuration = .default
    ) -> Int {
        estimateVerticalShiftCandidate(from: previous, to: current, configuration: configuration)?.shift ?? 0
    }

    private static func estimateVerticalShiftCandidate(
        from previous: CGImage,
        to current: CGImage,
        configuration: Configuration = .default
    ) -> ShiftCandidate? {
        guard previous.width == current.width, previous.height == current.height else {
            return nil
        }
        guard let previousSample = ImageSample(image: previous),
              let currentSample = ImageSample(image: current) else {
            return nil
        }

        let height = previous.height
        let maximumShift = max(
            configuration.minimumShift,
            min(height - 1, Int(CGFloat(height) * configuration.maximumShiftRatio))
        )
        var bestShift = 0
        var bestScore = UInt64.max
        let stride = max(2, configuration.sampleStride)

        for shift in configuration.minimumShift...maximumShift {
            let comparedHeight = height - shift
            guard comparedHeight > 0 else { continue }
            var score: UInt64 = 0
            var samples = 0
            var y = 0
            while y < comparedHeight {
                var x = 0
                while x < previous.width {
                    score += previousSample.pixelDistance(
                        x: x,
                        y: y + shift,
                        other: currentSample,
                        otherX: x,
                        otherY: y
                    )
                    samples += 1
                    x += stride
                }
                y += stride
            }
            guard samples > 0 else { continue }
            let normalized = score / UInt64(samples)
            if normalized < bestScore {
                bestScore = normalized
                bestShift = shift
            }
        }

        guard bestShift >= configuration.minimumShift,
              bestScore <= configuration.maximumAveragePixelDistance else {
            return nil
        }

        return ShiftCandidate(shift: bestShift, averagePixelDistance: bestScore)
    }

    private func draw(
        _ image: CGImage,
        cropY: Int,
        cropHeight: Int,
        destinationY: Int,
        in context: CGContext,
        outputHeight: Int
    ) {
        guard cropHeight > 0,
              let crop = image.cropping(to: CGRect(x: 0, y: cropY, width: image.width, height: cropHeight)) else {
            return
        }
        context.draw(
            crop,
            in: CGRect(
                x: 0,
                y: outputHeight - destinationY - cropHeight,
                width: image.width,
                height: cropHeight
            )
        )
    }
}

private struct ImageSample {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let data: [UInt8]

    init?(image: CGImage) {
        width = image.width
        height = image.height
        bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = buffer
    }

    func pixelDistance(x: Int, y: Int, other: ImageSample, otherX: Int, otherY: Int) -> UInt64 {
        guard x >= 0, x < width, y >= 0, y < height,
              otherX >= 0, otherX < other.width, otherY >= 0, otherY < other.height else {
            return UInt64.max / 4
        }

        let lhs = y * bytesPerRow + x * 4
        let rhs = otherY * other.bytesPerRow + otherX * 4
        let dr = Int(data[lhs]) - Int(other.data[rhs])
        let dg = Int(data[lhs + 1]) - Int(other.data[rhs + 1])
        let db = Int(data[lhs + 2]) - Int(other.data[rhs + 2])
        return UInt64(dr * dr + dg * dg + db * db)
    }
}

private struct ShiftCandidate {
    let shift: Int
    let averagePixelDistance: UInt64
}
