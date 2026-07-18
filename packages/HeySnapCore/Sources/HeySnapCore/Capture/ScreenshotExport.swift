import CoreGraphics
import Darwin
import Foundation
import ImageIO

public enum ScreenshotOutputFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg
    case webp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .webp: return "WebP"
        }
    }

    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpeg"
        case .webp: return "webp"
        }
    }

    var typeIdentifier: CFString {
        switch self {
        case .png: return "public.png" as CFString
        case .jpeg: return "public.jpeg" as CFString
        case .webp: return "org.webmproject.webp" as CFString
        }
    }

    var usesLossyCompression: Bool {
        switch self {
        case .png:
            return false
        case .jpeg, .webp:
            return true
        }
    }
}

public enum ScreenshotSaveFormatMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case png
    case jpeg
    case webp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: return "Auto"
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .webp: return "WebP"
        }
    }

    var explicitOutputFormat: ScreenshotOutputFormat? {
        switch self {
        case .automatic: return nil
        case .png: return .png
        case .jpeg: return .jpeg
        case .webp: return .webp
        }
    }
}

public struct ScreenshotSaveFormatPreference: Equatable, Sendable {
    public static let defaultAutomaticFormats: Set<ScreenshotOutputFormat> = [.png, .jpeg]
    public static let `default` = ScreenshotSaveFormatPreference(
        mode: .automatic,
        automaticFormats: defaultAutomaticFormats
    )

    public var mode: ScreenshotSaveFormatMode
    public var automaticFormats: Set<ScreenshotOutputFormat>

    public init(mode: ScreenshotSaveFormatMode, automaticFormats: Set<ScreenshotOutputFormat>) {
        self.mode = mode
        self.automaticFormats = automaticFormats
    }

    var normalizedAutomaticFormats: Set<ScreenshotOutputFormat> {
        automaticFormats.isEmpty ? Self.defaultAutomaticFormats : automaticFormats
    }
}

struct EncodedScreenshot: Sendable {
    let format: ScreenshotOutputFormat
    let data: Data
}

enum ScreenshotImageEncoder {
    static let lossyCompressionQuality = 0.92

    static func encode(
        _ image: CGImage,
        using preference: ScreenshotSaveFormatPreference
    ) throws -> EncodedScreenshot {
        if let explicitFormat = preference.mode.explicitOutputFormat {
            return try encode(image, as: explicitFormat)
        }

        let candidates = try preference.normalizedAutomaticFormats.map { format in
            try encode(image, as: format)
        }
        return try selectAutomaticCandidate(from: candidates)
    }

    static func encode(_ image: CGImage, as format: ScreenshotOutputFormat) throws -> EncodedScreenshot {
        if format == .webp {
            return EncodedScreenshot(
                format: format,
                data: try WebPImageEncoder.encode(image, quality: lossyCompressionQuality)
            )
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.typeIdentifier, 1, nil) else {
            throw ScreenshotError.imageWriteFailed(format)
        }

        let properties = imageDestinationProperties(for: format)
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotError.imageWriteFailed(format)
        }

        return EncodedScreenshot(format: format, data: data as Data)
    }

    static func selectAutomaticCandidate(from candidates: [EncodedScreenshot]) throws -> EncodedScreenshot {
        guard !candidates.isEmpty else {
            throw ScreenshotError.noOutputFormatSelected
        }

        guard let pngCandidate = candidates.first(where: { $0.format == .png }) else {
            return candidates.min { lhs, rhs in lhs.data.count < rhs.data.count } ?? candidates[0]
        }

        let lossyCandidates = candidates.filter { $0.format.usesLossyCompression }
        guard
            let smallestLossyCandidate = lossyCandidates.min(by: { lhs, rhs in lhs.data.count < rhs.data.count }),
            shouldPreferLossy(pngBytes: pngCandidate.data.count, lossyBytes: smallestLossyCandidate.data.count)
        else {
            return pngCandidate
        }

        return smallestLossyCandidate
    }

    private static func shouldPreferLossy(pngBytes: Int, lossyBytes: Int) -> Bool {
        let pngMB = Double(pngBytes) / 1024 / 1024
        let lossyMB = Double(lossyBytes) / 1024 / 1024

        if pngMB > 0.5, lossyMB * 4 < pngMB {
            return true
        }

        if pngMB > 2.0, lossyMB * 2 < pngMB {
            return true
        }

        return false
    }

    private static func imageDestinationProperties(for format: ScreenshotOutputFormat) -> CFDictionary? {
        guard format.usesLossyCompression else {
            return nil
        }

        return [
            kCGImageDestinationLossyCompressionQuality: lossyCompressionQuality
        ] as CFDictionary
    }
}

enum ScreenshotImageResizer {
    static func downscaleRetinaIfNeeded(
        _ image: CGImage,
        sourceScaleFactor: CGFloat,
        shouldDownscale: Bool
    ) throws -> CGImage {
        guard shouldDownscale, sourceScaleFactor >= 2 else {
            return image
        }

        let width = max(1, Int((CGFloat(image.width) / sourceScaleFactor).rounded()))
        let height = max(1, Int((CGFloat(image.height) / sourceScaleFactor).rounded()))
        guard width < image.width || height < image.height else {
            return image
        }

        return try resize(image, width: width, height: height)
    }

    static func resize(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0 else {
            throw ScreenshotError.imageResizeFailed
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw ScreenshotError.imageResizeFailed
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let resizedImage = context.makeImage() else {
            throw ScreenshotError.imageResizeFailed
        }

        return resizedImage
    }
}

private enum WebPImageEncoder {
    private typealias WebPEncodeRGBAFunction = @convention(c) (
        UnsafePointer<UInt8>,
        CInt,
        CInt,
        CInt,
        Float,
        UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>
    ) -> Int
    private typealias WebPFreeFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void

    static func encode(_ image: CGImage, quality: Double) throws -> Data {
        let library = try WebPLibrary.load()
        let bitmap = try RGBABitmap(image: image)

        var outputPointer: UnsafeMutablePointer<UInt8>?
        let byteCount = bitmap.pixels.withUnsafeBufferPointer { buffer in
            library.encodeRGBA(
                buffer.baseAddress!,
                CInt(bitmap.width),
                CInt(bitmap.height),
                CInt(bitmap.bytesPerRow),
                Float(quality * 100),
                &outputPointer
            )
        }

        guard byteCount > 0, let outputPointer else {
            throw ScreenshotError.imageWriteFailed(.webp)
        }
        defer {
            library.free(outputPointer)
        }

        return Data(bytes: outputPointer, count: byteCount)
    }

    private struct WebPLibrary {
        let encodeRGBA: WebPEncodeRGBAFunction
        let free: WebPFreeFunction

        static func load() throws -> WebPLibrary {
            for path in candidateLibraryPaths {
                guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
                    continue
                }

                guard
                    let encodeSymbol = dlsym(handle, "WebPEncodeRGBA"),
                    let freeSymbol = dlsym(handle, "WebPFree")
                else {
                    dlclose(handle)
                    continue
                }

                return WebPLibrary(
                    encodeRGBA: unsafeBitCast(encodeSymbol, to: WebPEncodeRGBAFunction.self),
                    free: unsafeBitCast(freeSymbol, to: WebPFreeFunction.self)
                )
            }

            throw ScreenshotError.webPEncoderUnavailable
        }

        private static var candidateLibraryPaths: [String] {
            var paths = [
                "libwebp.dylib",
                "/opt/homebrew/lib/libwebp.dylib",
                "/usr/local/lib/libwebp.dylib"
            ]

            if let bundledLibrary = Bundle.main.privateFrameworksURL?.appendingPathComponent("libwebp.7.dylib").path {
                paths.insert(bundledLibrary, at: 0)
            }

            return paths
        }
    }

    private struct RGBABitmap {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let bytesPerRow: Int

        init(image: CGImage) throws {
            let bitmapWidth = image.width
            let bitmapHeight = image.height
            let bitmapBytesPerRow = bitmapWidth * 4
            var renderedPixels = [UInt8](repeating: 0, count: bitmapBytesPerRow * bitmapHeight)
            let bitmapInfo = CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue
            )

            try renderedPixels.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(
                    data: buffer.baseAddress,
                    width: bitmapWidth,
                    height: bitmapHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: bitmapBytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: bitmapInfo.rawValue
                ) else {
                    throw ScreenshotError.imageWriteFailed(.webp)
                }

                context.draw(image, in: CGRect(x: 0, y: 0, width: bitmapWidth, height: bitmapHeight))
            }

            width = bitmapWidth
            height = bitmapHeight
            bytesPerRow = bitmapBytesPerRow
            pixels = renderedPixels
        }
    }
}
