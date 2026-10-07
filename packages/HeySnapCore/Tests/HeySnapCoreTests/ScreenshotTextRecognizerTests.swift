@testable import HeySnapCore
import AppKit
import Testing

@Suite("Local screenshot OCR")
struct ScreenshotTextRecognizerTests {
    @Test("Recognizes English and Chinese screenshot text in reading order")
    @MainActor func recognizesMixedText() throws {
        let image = fixture(lines: ["Hello HeySnap", "Clipboard OCR 123", "截图文字识别"])
        let text = try ScreenshotTextRecognizer.recognize(image)
        #expect(text.contains("Hello"))
        #expect(text.contains("Clipboard OCR 123"))
        let compact = text.filter { !$0.isWhitespace }
        #expect(compact.contains("截图文字识别"))
        if let first = text.range(of: "Hello"), let second = text.range(of: "Clipboard") {
            #expect(first.lowerBound < second.lowerBound)
        }
    }

    @Test("An empty screenshot produces no text")
    @MainActor func emptyImage() throws {
        #expect(try ScreenshotTextRecognizer.recognize(fixture(lines: [])) == "")
    }

    @Test("Cropping limits recognition to the selected content")
    @MainActor func croppedImage() throws {
        let image = fixture(lines: ["First line", "Second line"])
        let crop = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: 85)))
        let text = try ScreenshotTextRecognizer.recognize(crop)
        #expect(text.contains("First line"))
        #expect(!text.contains("Second line"))
    }

    @MainActor private func fixture(lines: [String]) -> CGImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 540, pixelsHigh: 260,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 540, height: 260).fill()
        let font = NSFont(name: "PingFangSC-Regular", size: 32) ?? .systemFont(ofSize: 32)
        for (index, line) in lines.enumerated() {
            line.draw(at: CGPoint(x: 24, y: 190 - index * 65), withAttributes: [.font: font, .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage!
    }
}
