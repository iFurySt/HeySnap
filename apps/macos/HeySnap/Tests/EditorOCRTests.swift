import AppKit

@main
struct EditorOCRTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let pasteboard = NSPasteboard.general
        let original = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            pasteboard.clearContents()
            let items = original.map { entries in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { pasteboard.writeObjects(items) }
        }
        let controller = ScreenshotEditorWindowController(image: fixture(text: "Hello OCR 123"), sourceScaleFactor: 1,
            screenshotService: ScreenshotService(saveDirectoryProvider: { FileManager.default.temporaryDirectory }))
        controller.showWindow(nil)
        let window = controller.window!
        window.setContentSize(CGSize(width: 1100, height: 600))
        let item = window.toolbar!.items.first { $0.itemIdentifier.rawValue == "heysnap.editor.primaryActions" }!
        try check(!window.toolbar!.items.contains { $0.itemIdentifier.rawValue == "heysnap.editor.ocr" }, "OCR must share the primary group, with no separate toolbar item")
        try await Task.sleep(for: .milliseconds(100))
        try check(item.view != nil && item.view!.fittingSize.width >= 110, "Shared group must fit three action buttons")
        pasteboard.clearContents(); pasteboard.setString("Before OCR", forType: .string)
        try check(NSApp.sendAction(NSSelectorFromString("recognizeText"), to: window.contentViewController, from: item.view), "OCR action must remain connected")
        for _ in 0..<200 {
            if pasteboard.string(forType: .string)?.contains("Hello OCR 123") == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try check(pasteboard.string(forType: .string)?.contains("Hello OCR 123") == true,
                     "Clicking the grouped OCR button must recognize and copy the screenshot")
        if CommandLine.arguments.count > 1, let frameView = window.contentView?.superview,
           let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
            frameView.cacheDisplay(in: frameView.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        window.close()
        let blankController = ScreenshotEditorWindowController(image: fixture(text: ""), sourceScaleFactor: 1,
            screenshotService: ScreenshotService(saveDirectoryProvider: { FileManager.default.temporaryDirectory }))
        blankController.showWindow(nil)
        let blankWindow = blankController.window!
        let blankItem = blankWindow.toolbar!.items.first { $0.itemIdentifier == item.itemIdentifier }!
        try await Task.sleep(for: .milliseconds(100))
        pasteboard.clearContents(); pasteboard.setString("Keep clipboard", forType: .string)
        try check(NSApp.sendAction(NSSelectorFromString("recognizeText"), to: blankWindow.contentViewController, from: blankItem.view), "Blank-image OCR action must respond")
        try await Task.sleep(for: .milliseconds(500))
        try check(pasteboard.string(forType: .string) == "Keep clipboard", "Empty OCR must preserve clipboard")
        blankWindow.close()
        print("Editor OCR passed: shared three-button toolbar group, OCR action, clipboard copy, empty-result preservation.")
    }

    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "EditorOCRTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    @MainActor static func fixture(text: String) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 360, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 640, height: 360).fill()
        text.draw(at: CGPoint(x: 32, y: 160), withAttributes: [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
}
