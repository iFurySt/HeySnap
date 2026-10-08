import CoreGraphics
import Foundation

struct ScrollingCaptureStitcher {
    struct Configuration {
        var maxHeight: Int = 20_000
        var minimumShift: Int = 1
        var maximumShiftRatio: CGFloat = 0.95
        var sampleStride: Int = 12
        var noMovementLimit: Int = 2
        var maximumAveragePixelDistance: UInt64 = 2_500

        static let `default` = Configuration()
    }

    private let configuration: Configuration
    private var frames: [CGImage] = []
    private var previousSample: ImageSample?
    private var rejectedSample: ImageSample?
    private var verticalShifts: [Int] = []
    private var noMovementCount = 0
    private var stationarySampleCount = 0
    private var settledFrontier = false
    private var progressAfterSettling = 0
    private(set) var lastFrameWasStationary = false
    private(set) var lastAcceptedShift: Int?

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

    mutating func append(_ image: CGImage) -> Bool {
        guard let first = frames.first else {
            frames.append(image)
            previousSample = ImageSample(image: image)
            return true
        }
        guard image.width == first.width, image.height == first.height else {
            return false
        }

        guard let previous = previousSample, let current = ImageSample(image: image) else { return false }
        if rejectedSample?.data == current.data {
            lastFrameWasStationary = false
            stationarySampleCount = 0
            noMovementCount += 1
            return false
        }
        let match = Self.match(from: previous, to: current, configuration: configuration)
        lastFrameWasStationary = match.stationary
        guard let estimate = match.candidate else {
            rejectedSample = match.stationary ? nil : current
            stationarySampleCount = match.stationary ? stationarySampleCount + 1 : 0
            if stationarySampleCount >= max(2, configuration.noMovementLimit) {
                settledFrontier = true
                progressAfterSettling = 0
            }
            noMovementCount += 1
            return false
        }

        if settledFrontier {
            let blankTail = current.trailingLightBackgroundRows(maximum: estimate.shift)
            if blankTail == estimate.shift ||
                (blankTail >= max(24, current.height / 8) && blankTail * 2 >= estimate.shift) {
                // Rubber-band overscroll really shifts pixels upward, but reveals background,
                // not a new part of the document. Keep the last reliable viewport unchanged.
                lastFrameWasStationary = true
                noMovementCount += 1
                rejectedSample = nil
                return false
            }
        }

        guard let crop = image.cropping(to: CGRect(x: 0, y: image.height - estimate.shift,
                                                   width: image.width, height: estimate.shift)),
              let stripContext = CGContext(data: nil, width: crop.width, height: crop.height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        // CGImage crops may retain the entire source provider; redraw to own compact storage.
        stripContext.interpolationQuality = .none
        stripContext.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        guard let strip = stripContext.makeImage() else { return false }
        noMovementCount = 0
        stationarySampleCount = 0
        if settledFrontier {
            progressAfterSettling += estimate.shift
            // A small genuine footer remainder must not disable protection for the next yank.
            // Clear it after moving meaningfully away from the recently settled viewport.
            if progressAfterSettling >= current.height / 2 { settledFrontier = false }
        }
        lastAcceptedShift = estimate.shift
        // Coalesce tiny nudges into bounded blocks rather than retaining thousands of CGImages.
        if estimate.shift <= 12, frames.count > 1, let tail = frames.last,
           tail.height + strip.height <= 128,
           let block = CGContext(data: nil, width: strip.width, height: tail.height + strip.height,
               bitsPerComponent: 8, bytesPerRow: 0, space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            block.interpolationQuality = .none
            block.draw(tail, in: CGRect(x: 0, y: strip.height, width: tail.width, height: tail.height))
            block.draw(strip, in: CGRect(x: 0, y: 0, width: strip.width, height: strip.height))
            guard let combined = block.makeImage() else { return false }
            frames[frames.count - 1] = combined
            verticalShifts[verticalShifts.count - 1] += estimate.shift
        } else {
            verticalShifts.append(estimate.shift)
            frames.append(strip)
        }
        previousSample = current
        rejectedSample = nil
        return true
    }

    func stitchedImage(previewSize: CGSize? = nil) -> CGImage? {
        guard let first = frames.first else { return nil }
        if frames.count == 1 && previewSize == nil { return first }

        let width = first.width
        let height = min(configuration.maxHeight, estimatedHeight)
        let colorSpace = first.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        let scale = previewSize.map { min(1, $0.width / CGFloat(width), $0.height / CGFloat(height)) } ?? 1
        let outputWidth = max(1, Int(CGFloat(width) * scale))
        let outputHeight = max(1, Int(CGFloat(height) * scale))
        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = previewSize == nil ? .none : .medium
        context.scaleBy(x: CGFloat(outputWidth) / CGFloat(width), y: CGFloat(outputHeight) / CGFloat(height))

        draw(first, cropY: 0, cropHeight: first.height, destinationY: 0, in: context, outputHeight: height)
        var outputY = first.height
        for (index, frame) in frames.dropFirst().enumerated() {
            let shift = min(verticalShifts[index], frame.height)
            let remaining = height - outputY
            guard remaining > 0 else { break }
            let cropHeight = min(shift, remaining)
            draw(
                frame,
                cropY: 0,
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

        return match(from: previousSample, to: currentSample, configuration: configuration).candidate
    }

    private static func match(from previous: ImageSample, to current: ImageSample,
                              configuration: Configuration) -> (candidate: ShiftCandidate?, stationary: Bool) {
        let result = forwardMatch(from: previous, to: current, configuration: configuration)
        if let candidate = result.candidate, candidate.shift > 12,
           reverseExplainsMotion(from: previous, to: current, forwardShift: candidate.shift) {
            return (nil, true)
        }
        return result
    }

    /// Compare identifiable content in both directions. Blank rows cannot vote for motion.
    /// All pixels in a row contribute, so narrow text is not missed by sparse anchor samples.
    private static func reverseExplainsMotion(from previous: ImageSample, to current: ImageSample,
                                              forwardShift: Int) -> Bool {
        let a = previous.contentRows, b = current.contentRows
        let height = previous.height
        func evidence(_ shift: Int, bands: [Int], currentRows: Range<Int>? = nil) -> (matches: Int, count: Int) {
            let overlap = height - abs(shift)
            let edge = min(height / 5, overlap / 3)
            var matches = 0, count = 0
            let rows = currentRows ?? (max(0, -shift) + edge)..<(max(0, -shift) + overlap - edge)
            for y in rows {
                for band in bands {
                    let lhs = a[(y + shift) * 3 + band]
                    let rhs = b[y * 3 + band]
                    if lhs.informative || rhs.informative {
                        count += 1
                        if lhs.hash == rhs.hash { matches += 1 }
                    }
                }
            }
            return (matches, count)
        }
        // A fixed sidebar must not outweigh moving page content.
        let movingBands = (0..<3).filter { band in
            let zero = evidence(0, bands: [band])
            return zero.count < 8 || zero.matches * 100 < zero.count * 90
        }
        guard !movingBands.isEmpty else { return false }
        // Vote from identical textured rows instead of rescanning every pixel at every offset.
        // Typical non-periodic pages produce no reverse candidates at all.
        var votes = [Int](repeating: 0, count: height)
        for band in movingBands {
            var locations: [UInt64: [Int]] = [:]
            for y in 0..<height where a[y * 3 + band].informative {
                locations[a[y * 3 + band].hash, default: []].append(y)
            }
            for y in 0..<height where b[y * 3 + band].informative {
                guard let matches = locations[b[y * 3 + band].hash] else { continue }
                for oldY in matches where y > oldY && y - oldY <= height - 24 {
                    votes[y - oldY] += 1
                }
            }
        }
        let candidates = (1..<height).filter { votes[$0] >= 16 }.sorted {
            Double(votes[$0]) / Double(height - $0) > Double(votes[$1]) / Double(height - $1)
        }
        let fullForward = evidence(forwardShift, bands: movingBands)
        func reverseWins(_ value: (matches: Int, count: Int),
                         over forward: (matches: Int, count: Int), shift: Int) -> Bool {
            guard value.count >= 16, value.matches * 100 >= value.count * 70 else { return false }
            let confidence = Double(value.matches) / Double(value.count)
            let forwardConfidence = Double(forward.matches) / Double(max(1, forward.count))
            return confidence > forwardConfidence + 0.001 ||
                (confidence >= forwardConfidence && shift < forwardShift)
        }
        for reverse in candidates {
            if reverseWins(evidence(-reverse, bands: movingBands), over: fullForward, shift: reverse) { return true }
            // Also compare the same current rows: a false forward shift must not win simply
            // by cropping a changing widget out of its shorter overlap. Use the wider evidence
            // above when the shared window is blank or has too few identifiable rows.
            let overlap = height - forwardShift - reverse
            guard overlap >= 24 else { continue }
            let edge = min(height / 5, overlap / 3)
            let shared = (reverse + edge)..<(height - forwardShift - edge)
            if reverseWins(evidence(-reverse, bands: movingBands, currentRows: shared),
                           over: evidence(forwardShift, bands: movingBands, currentRows: shared),
                           shift: reverse) { return true }
        }
        return false
    }

    private static func forwardMatch(from previous: ImageSample, to current: ImageSample,
                                     configuration: Configuration) -> (candidate: ShiftCandidate?, stationary: Bool) {
        let height = previous.height
        let minimum = max(1, configuration.minimumShift)
        let maximum = min(height - 1, max(minimum, Int(CGFloat(height) * configuration.maximumShiftRatio)))
        guard minimum <= maximum else { return (nil, true) }
        let stride = max(2, configuration.sampleStride)
        func score(_ shift: Int, rowStride: Int, columnStride: Int, comparedHeight: Int? = nil) -> Double {
            var distance: UInt64 = 0
            var count = 0
            for y in Swift.stride(from: 0, to: min(height - shift, comparedHeight ?? height), by: rowStride) {
                for x in Swift.stride(from: 0, to: previous.width, by: columnStride) {
                    distance += previous.pixelDistance(x: x, y: y + shift, other: current, otherX: x, otherY: y)
                    count += 1
                }
            }
            return count > 0 ? Double(distance) / Double(count) : .infinity
        }
        // Small differences are still movement; only a zero sampled distance is stationary.
        guard previous.data != current.data else { return (nil, true) }
        var baseline = score(0, rowStride: stride, columnStride: stride)
        if baseline == 0 { baseline = score(0, rowStride: 1, columnStride: 1) }
        guard baseline > 0 else { return (nil, true) }
        // Trackpad nudges are common: exact overlap returns without scanning large shifts.
        for shift in minimum...min(maximum, max(minimum, 12)) {
            if score(shift, rowStride: stride, columnStride: stride) == 0 &&
                score(shift, rowStride: 1, columnStride: 1) == 0 &&
                score(0, rowStride: 1, columnStride: 1, comparedHeight: height - shift) > 0 {
                return (ShiftCandidate(shift: shift, averagePixelDistance: 0), false)
            }
        }
        // Scrollbar fades and footer widgets are not evidence that the content moved.
        if contentIsStationary(from: previous, to: current, trimRows: false) { return (nil, true) }
        // Full-resolution row profiles cannot skip thin content between sampled rows.
        // Only the best eight candidates need expensive two-dimensional verification.
        let previousRows = previous.rowSums, currentRows = current.rowSums
        var candidates: [(shift: Int, score: Double)] = []
        for shift in minimum...maximum {
            var distance: UInt64 = 0
            for row in 0..<(height - shift) {
                for channel in 0..<3 {
                    let delta = Int64(previousRows[(row + shift) * 3 + channel]) - Int64(currentRows[row * 3 + channel])
                    distance += UInt64(delta * delta)
                }
            }
            let value = Double(distance) / Double(height - shift)
            if candidates.count < 8 || value < candidates.last!.score {
                candidates.append((shift, value))
                candidates.sort { $0.score == $1.score ? $0.shift < $1.shift : $0.score < $1.score }
                if candidates.count > 8 { candidates.removeLast() }
            }
        }
        var bestShift = 0
        var bestScore = Double.infinity
        for candidate in candidates {
            var value = score(candidate.shift, rowStride: stride, columnStride: stride)
            if value == 0 { value = score(candidate.shift, rowStride: 1, columnStride: 1) }
            if value < bestScore { bestShift = candidate.shift; bestScore = value }
            if value == 0 { break }
        }
        var overlapBaseline = score(0, rowStride: stride, columnStride: stride, comparedHeight: height - bestShift)
        if overlapBaseline == 0 { overlapBaseline = score(0, rowStride: 1, columnStride: 1, comparedHeight: height - bestShift) }
        guard bestScore <= Double(configuration.maximumAveragePixelDistance), bestScore < overlapBaseline * 0.35,
              !(bestShift > height * 82 / 100 && bestScore > 0) else {
            if contentIsStationary(from: previous, to: current, trimRows: true) { return (nil, true) }
            return (robustMatch(from: previous, to: current, minimum: minimum, maximum: maximum,
                                threshold: Double(configuration.maximumAveragePixelDistance)), false)
        }
        return (ShiftCandidate(shift: bestShift, averagePixelDistance: bestScore), false)
    }

    /// Same-position content comparison must get the same outlier tolerance as shifted matches.
    private static func contentIsStationary(from previous: ImageSample, to current: ImageSample,
                                            trimRows: Bool) -> Bool {
        let left = previous.width / 10
        let bandWidth = max(1, (previous.width - left * 2) / 3)
        let edge = previous.height / 5
        var stationaryBands = 0
        for band in 0..<3 {
            var rows: [Double] = []
            for y in edge..<(previous.height - edge) {
                var distance = 0.0, count = 0
                for x in Swift.stride(from: left + band * bandWidth, to: left + (band + 1) * bandWidth, by: 3) {
                    distance += Double(previous.pixelDistance(x: x, y: y, other: current, otherX: x, otherY: y))
                    count += 1
                }
                rows.append(distance / Double(max(1, count)))
            }
            guard !rows.isEmpty else { continue }
            if trimRows { rows.sort() }
            let retained = rows.prefix(trimRows ? max(1, rows.count * 7 / 10) : rows.count)
            if retained.reduce(0, +) / Double(retained.count) <= 3 { stationaryBands += 1 }
        }
        return stationaryBands >= 2
    }

    /// Recovery only: ignore small edge bands and require agreement from two of three content bands.
    /// A fixed sidebar may spoil one band; unrelated frames still fail the absolute and relative checks.
    private static func robustMatch(from previous: ImageSample, to current: ImageSample,
                                    minimum: Int, maximum: Int, threshold: Double) -> ShiftCandidate? {
        let height = previous.height
        let left = previous.width / 10
        let bandWidth = max(1, (previous.width - left * 2) / 3)
        let a = previous.bandRows(left: left, bandWidth: bandWidth)
        let b = current.bandRows(left: left, bandWidth: bandWidth)
        let minimumOverlap = max(24, height / 25)
        guard height - minimum >= minimumOverlap else { return nil }
        let maxShift = min(maximum, height - minimumOverlap)
        guard minimum <= maxShift else { return nil }
        func rowRange(_ shift: Int) -> Range<Int> {
            let overlap = height - shift
            let top = min(height / 5, overlap / 3)
            let bottom = min(height / 5, overlap / 3)
            return top..<(overlap - bottom)
        }
        var candidates: [(shift: Int, score: Double)] = []
        for shift in minimum...maxShift {
            var scores = [Double](repeating: 0, count: 3)
            let rows = rowRange(shift)
            for row in rows {
                for band in 0..<3 {
                    for channel in 0..<3 {
                        let index = row * 9 + band * 3 + channel
                        let delta = Double(a[index + shift * 9]) - Double(b[index])
                        scores[band] += delta * delta
                    }
                }
            }
            scores.sort()
            let value = (scores[0] + scores[1]) / Double(rows.count)
            if candidates.count < 8 || value < candidates.last!.score {
                candidates.append((shift, value))
                candidates.sort { $0.score < $1.score }
                if candidates.count > 8 { candidates.removeLast() }
            }
        }
        var best: (shift: Int, score: Double)?
        for candidate in candidates {
            let rows = rowRange(candidate.shift)
            var bandScores = [[(distance: Double, stationary: Double)]](repeating: [], count: 3)
            for row in Swift.stride(from: rows.lowerBound, to: rows.upperBound, by: 3) {
                for band in 0..<3 {
                    var distance = 0.0, stationary = 0.0, count = 0
                    for x in Swift.stride(from: left + band * bandWidth, to: left + (band + 1) * bandWidth, by: 3) {
                        distance += Double(previous.pixelDistance(x: x, y: row + candidate.shift, other: current, otherX: x, otherY: row))
                        stationary += Double(previous.pixelDistance(x: x, y: row, other: current, otherX: x, otherY: row))
                        count += 1
                    }
                    bandScores[band].append((distance / Double(max(1, count)), stationary / Double(max(1, count))))
                }
            }
            var trusted: [Double] = []
            for band in 0..<3 {
                // Animated widgets and sticky headers may corrupt some rows, not the whole overlap.
                let sorted = bandScores[band].sorted { $0.distance < $1.distance }
                let retained = sorted.prefix(max(1, sorted.count * 7 / 10))
                let value = retained.reduce(0) { $0 + $1.distance } / Double(retained.count)
                let stationaryRows = bandScores[band].map(\.stationary).sorted().prefix(retained.count)
                let baseline = stationaryRows.reduce(0, +) / Double(stationaryRows.count)
                if baseline > 3 && value <= threshold && value < baseline * 0.35 { trusted.append(value) }
            }
            guard trusted.count >= 2 else { continue }
            trusted.sort()
            let value = (trusted[0] + trusted[1]) / 2
            if best == nil || value < best!.score { best = (candidate.shift, value) }
        }
        return best.map { ShiftCandidate(shift: $0.shift, averagePixelDistance: $0.score) }
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
        width = min(image.width, 160)
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

    /// Compute row profiles only when the exact small-motion path cannot resolve the frame.
    var rowSums: [UInt32] {
        var sums = [UInt32](repeating: 0, count: height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * 4
                for channel in 0..<3 { sums[y * 3 + channel] += UInt32(data[i + channel]) }
            }
        }
        return sums
    }

    /// Count contiguous light background rows at the bottom, ignoring edge chrome.
    /// A footer background transitioning to the overscroll background is still empty content.
    func trailingLightBackgroundRows(maximum: Int) -> Int {
        let left = width / 10, right = width - left
        var rows = 0
        for y in Swift.stride(from: height - 1, through: max(0, height - maximum), by: -1) {
            let reference = y * bytesPerRow + (width / 2) * 4
            guard (0..<3).allSatisfy({ data[reference + $0] >= 220 }) else { return rows }
            for x in left..<right {
                let i = y * bytesPerRow + x * 4
                for channel in 0..<3 where abs(Int(data[i + channel]) - Int(data[reference + channel])) > 2 {
                    return rows
                }
            }
            rows += 1
        }
        return rows
    }

    struct ContentRow {
        let hash: UInt64
        let informative: Bool
    }

    var contentRows: [ContentRow] {
        let left = width / 10
        let bandWidth = max(1, (width - left * 2) / 3)
        var result: [ContentRow] = []
        result.reserveCapacity(height * 3)
        for y in 0..<height {
            for band in 0..<3 {
                var hash: UInt64 = 14_695_981_039_346_656_037
                var low: UInt8 = 255, high: UInt8 = 0
                for x in left + band * bandWidth..<left + (band + 1) * bandWidth {
                    let i = y * bytesPerRow + x * 4
                    for channel in 0..<3 {
                        let value = data[i + channel]
                        hash = (hash ^ UInt64(value)) &* 1_099_511_628_211
                    }
                    low = min(low, data[i]); high = max(high, data[i])
                }
                result.append(ContentRow(hash: hash, informative: Int(high) - Int(low) > 4))
            }
        }
        return result
    }

    func bandRows(left: Int, bandWidth: Int) -> [UInt32] {
        var sums = [UInt32](repeating: 0, count: height * 9)
        for y in 0..<height {
            for band in 0..<3 {
                for x in left + band * bandWidth..<left + (band + 1) * bandWidth {
                    let i = y * bytesPerRow + x * 4
                    for channel in 0..<3 { sums[y * 9 + band * 3 + channel] += UInt32(data[i + channel]) }
                }
            }
        }
        return sums
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
    let averagePixelDistance: Double
}
