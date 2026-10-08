import AppKit

@main struct QuickMarkupOCRTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let origin = NSScreen.main!.frame.origin
        let source = CGRect(origin: origin, size: CGSize(width: 640, height: 360))
        let image = fixture()
        let snapshot = CapturedScreenshot(image: image, scaleFactor: 1, sourceRect: source)
        var outcome: CaptureSelection?
        func makeSession(recognizer: @escaping @Sendable (CGImage) throws -> String = { try ScreenshotTextRecognizer.recognize($0) }) -> AreaSelectionSession {
            let session = AreaSelectionSession(quickMarkupEnabled: true, screenSnapshot: snapshot,
                onScrollingCapture: { _, _, completion in completion(nil) }, textRecognizer: recognizer,
                ocrPasteboard: board, onComplete: { outcome = $0 })
            session.handleMouseDown(globalPoint: source.origin)
            session.handleMouseDragged(globalPoint: CGPoint(x: source.maxX, y: source.maxY))
            session.handleMouseUp(globalPoint: CGPoint(x: source.maxX, y: source.maxY))
            return session
        }
        func clickOCR(_ session: AreaSelectionSession, kind: QuickMarkupBarSlot.Kind = .ocr) throws {
            let screen = NSScreen.main!.frame
            let bar = session.markupBarRect(in: screen)!.offsetBy(dx: screen.minX, dy: screen.minY)
            let slots = QuickMarkupBarSlot.layout(in: bar)
            let slot = slots.first { $0.kind == kind }!
            if kind == .ocr { try check(slots[slot.index + 1].kind == .editor, "OCR must be immediately left of Editor") }
            try check(NSImage(systemSymbolName: slot.kind.symbolName!, accessibilityDescription: nil) != nil, "OCR symbol must exist")
            let point = CGPoint(x: slot.rect.midX, y: slot.rect.midY)
            session.handleMouseDown(globalPoint: point)
            session.handleMouseUp(globalPoint: point)
        }
        board.setString("Keep existing text", forType: .string)
        let recognized = makeSession()
        try clickOCR(recognized)
        for _ in 0..<100 {
            if outcome != nil { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        guard case .textCopied = outcome else { throw failure("Real Vision OCR must copy and finish the session") }
        try check(board.string(forType: .string)?.contains("Hello OCR 123") == true, "OCR must recognize the frozen selection")

        for recognizer: @Sendable (CGImage) throws -> String in [
            { _ in "   \n" },
            { _ in throw failure("Injected recognition failure") }
        ] {
            outcome = nil
            board.clearContents(); board.setString("Keep existing text", forType: .string)
            let session = makeSession(recognizer: recognizer)
            try clickOCR(session)
            try await Task.sleep(for: .milliseconds(250))
            try check(outcome == nil && session.activeGlobalRect != nil, "Empty/failed OCR must keep capture open")
            try check(board.string(forType: .string) == "Keep existing text", "Empty/failed OCR must preserve clipboard")
            session.cancel()
        }
        outcome = nil
        board.clearContents(); board.setString("Keep existing text", forType: .string)
        let cancelled = makeSession(recognizer: { _ in Thread.sleep(forTimeInterval: 0.15); return "Late result" })
        try clickOCR(cancelled)
        cancelled.cancel()
        try await Task.sleep(for: .milliseconds(300))
        guard case .cancelled = outcome else { throw failure("Cancellation must win over pending OCR") }
        try check(board.string(forType: .string) == "Keep existing text", "Cancelled OCR must not copy a late result")
        outcome = nil
        var scrollCompletion: ((CapturedScreenshot?) -> Void)?
        var scrollControl: ScrollingCaptureCancellation?
        let scrolling = AreaSelectionSession(quickMarkupEnabled: true, screenSnapshot: snapshot,
            onScrollingCapture: { _, control, completion in scrollControl = control; scrollCompletion = completion },
            textRecognizer: { _ in throw failure("Long-image OCR failure") }, ocrPasteboard: board,
            onComplete: { outcome = $0 })
        scrolling.handleMouseDown(globalPoint: source.origin)
        scrolling.handleMouseDragged(globalPoint: CGPoint(x: source.maxX, y: source.maxY))
        scrolling.handleMouseUp(globalPoint: CGPoint(x: source.maxX, y: source.maxY))
        try clickOCR(scrolling, kind: .scrolling)
        try clickOCR(scrolling)
        try check(scrollControl?.isFinished == true, "Scrolling OCR must request the finished long image")
        scrollCompletion?(CapturedScreenshot(image: image, scaleFactor: 1))
        try await Task.sleep(for: .milliseconds(300))
        try check(outcome == nil && scrolling.activeGlobalRect != nil, "Failed long-image OCR must retain capture")
        try clickOCR(scrolling, kind: .editor)
        guard case .editRegion(_, .some) = outcome else { throw failure("Failed OCR must leave Editor available on the cached capture") }
        print("Quick markup OCR passed: icon order, real Vision/frozen crop, copy-and-exit, empty/error stay open, cancelled result ignored.")
    }
    static func failure(_ message: String) -> NSError { NSError(domain: "QuickMarkupOCRTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    static func check(_ value: Bool, _ message: String) throws { if !value { throw failure(message) } }
    @MainActor static func fixture() -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 360, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 640, height: 360).fill()
        "Hello OCR 123".draw(at: CGPoint(x: 60, y: 180), withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
}
