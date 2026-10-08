import AppKit

@main
struct ScrollingCaptureWorkflowTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let epoch = Date(timeIntervalSince1970: 1000)
        var recovery = ScrollingCaptureMatchRecovery()
        for index in 0..<6 {
            try check(!recovery.observe(accepted: false, stationary: false, now: epoch.addingTimeInterval(Double(index) * 0.1)), "Transient mismatches must retry silently")
        }
        try check(recovery.isRetrying, "Mismatch must remain active rather than becoming idle")
        try check(!recovery.observe(accepted: true, stationary: false, now: epoch.addingTimeInterval(0.6)) && !recovery.isRetrying, "A recovered frame must clear failure state")
        var warnings = 0
        for index in 0..<30 {
            if recovery.observe(accepted: false, stationary: false, now: epoch.addingTimeInterval(1 + Double(index) * 0.1)) { warnings += 1 }
        }
        try check(warnings == 1, "Sustained mismatch must produce one warning rather than one per frame")
        _ = recovery.observe(accepted: false, stationary: true, now: epoch.addingTimeInterval(4))
        try check(!recovery.isRetrying, "Returning to the last reliable viewport must restore the session")
        let full = fixture()
        let service = ScreenshotService(saveDirectoryProvider: { FileManager.default.temporaryDirectory })
        let rect = CGRect(x: 100, y: 100, width: 240, height: 200)
        var offset = 0
        let frame: (CGRect) async throws -> CapturedScreenshot = { _ in
            CapturedScreenshot(image: full.cropping(to: CGRect(x: 0, y: offset, width: 240, height: 200))!, scaleFactor: 1)
        }
        let manual = ScrollingCaptureCancellation()
        var previews: [CGImage] = []
        manual.onPreview = { previews.append($0) }
        let workflow = ScrollingCaptureWorkflow(screenshotService: service, frameProvider: frame)
        let drive = Task { @MainActor in
            // More than the old one-second idle timeout, both before and after movement.
            try await Task.sleep(for: .milliseconds(1500))
            offset = 60
            try await Task.sleep(for: .milliseconds(1700))
            offset = 120
            try await Task.sleep(for: .milliseconds(800))
            manual.finish()
        }
        let result = await workflow.capture(rect: rect, cancellation: manual)
        try await drive.value
        try check(result?.image.height == 320, "Manual capture must survive pauses and toolbar completion must return the stitched result")
        try check(result.map { pixels($0.image) == pixels(full.cropping(to: CGRect(x: 0, y: 0, width: 240, height: 320))!) } == true, "Manual output must contain every source row exactly once")
        try check(previews.count == 4 && previews.last.map { pixels($0) == pixels(result!.image) } == true, "Live preview must update for first, appended content and final confirmation, preserving every strip")
        offset = 0
        let auto = ScrollingCaptureCancellation()
        auto.isAutomatic = true
        var scrolls = 0
        let automatic = ScrollingCaptureWorkflow(screenshotService: service, frameProvider: frame,
            scrollProvider: { _ in offset = min(400, offset + 20); scrolls += 1 })
        let automaticDrive = Task { @MainActor in
            for _ in 0..<200 {
                if scrolls >= 20 && !auto.isAutomatic { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            try check(scrolls >= 20 && !auto.isAutomatic, "Auto must stop events at the bottom without completing the toolbar session")
            let stoppedCount = scrolls
            try await Task.sleep(for: .milliseconds(700))
            try check(scrolls == stoppedCount && !auto.isFinished, "Bottom detection must wait for a toolbar output action")
            auto.finish()
        }
        let autoResult = await automatic.capture(rect: rect, cancellation: auto)
        try await automaticDrive.value
        try check(autoResult?.image.height == 600 && scrolls >= 20, "Auto must reach the bottom and stop after three stationary captures")
        try check(autoResult.map { pixels($0.image) == pixels(full) } == true, "Automatic output must preserve all source pixels")
        let cancel = ScrollingCaptureCancellation()
        cancel.cancel()
        let cancelled = await workflow.capture(rect: rect, cancellation: cancel)
        try check(cancelled == nil, "Cancel must not return a partial screenshot")
        let blackContext = CGContext(data: nil, width: 240, height: 200, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        blackContext.setFillColor(CGColor(gray: 0, alpha: 1))
        blackContext.fill(CGRect(x: 0, y: 0, width: 240, height: 200))
        let badFrame = blackContext.makeImage()!
        var recoveryCalls = 0, recoveryNotices = 0, recoveryScrolls = 0
        let retryControl = ScrollingCaptureCancellation()
        retryControl.isAutomatic = true
        retryControl.onMessage = { _ in recoveryNotices += 1 }
        let retryWorkflow = ScrollingCaptureWorkflow(screenshotService: service, frameProvider: { _ in
            recoveryCalls += 1
            if recoveryCalls == 2 { return CapturedScreenshot(image: badFrame, scaleFactor: 1) }
            if recoveryCalls == 3 {
                let pausedCount = recoveryScrolls
                try await Task.sleep(for: .milliseconds(80))
                try check(recoveryScrolls == pausedCount, "Auto events must pause during transient retry")
            }
            if recoveryCalls == 4 { retryControl.finish() }
            let y = recoveryCalls == 1 ? 0 : 60
            return CapturedScreenshot(image: full.cropping(to: CGRect(x: 0, y: y, width: 240, height: 200))!, scaleFactor: 1)
        }, scrollProvider: { _ in recoveryScrolls += 1 })
        let recovered = await retryWorkflow.capture(rect: rect, cancellation: retryControl)
        try check(recovered?.image.height == 260 && recoveryNotices == 0, "A transient bad frame must recover from the reliable frontier without a warning")
        try check(recovered.map { pixels($0.image) == pixels(full.cropping(to: CGRect(x: 0, y: 0, width: 240, height: 260))!) } == true, "Retry must not append the bad frame or lose real content")
        let fadingBottom = ScrollingCaptureCancellation()
        fadingBottom.isAutomatic = true
        var bottomSamples = 0, bottomWheels = 0
        let bottomWorkflow = ScrollingCaptureWorkflow(screenshotService: service, frameProvider: { _ in
            let y = min(400, bottomSamples * 80)
            bottomSamples += 1
            let image = full.cropping(to: CGRect(x: 0, y: y, width: 240, height: 200))!
            guard y == 400 else { return CapturedScreenshot(image: image, scaleFactor: 1) }
            var bytes = [UInt8](pixels(image))
            for row in 0..<200 {
                for x in 0..<240 where row >= 188 || x >= 235 {
                    let i = (row * 240 + x) * 4
                    for c in 0..<3 { bytes[i + c] = UInt8((bottomSamples * 19 + c * 63) % 255) }
                }
            }
            let faded = CGImage(width: 240, height: 200, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 240 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            return CapturedScreenshot(image: faded, scaleFactor: 1)
        }, scrollProvider: { _ in bottomWheels += 1 })
        let bottomDrive = Task { @MainActor in
            for _ in 0..<200 {
                if !fadingBottom.isAutomatic { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            try check(!fadingBottom.isAutomatic, "Fading footer/scrollbar must still detect bottom")
            let stoppedWheels = bottomWheels
            try await Task.sleep(for: .milliseconds(400))
            try check(bottomWheels == stoppedWheels, "Bottom must stop wheel events even while footer pixels keep changing")
            fadingBottom.finish()
        }
        let bottomResult = await bottomWorkflow.capture(rect: rect, cancellation: fadingBottom)
        try await bottomDrive.value
        try check(bottomResult?.image.height == 600, "Sampling changed footer after reaching bottom must never grow the long image")
        var tinyOffset = 0
        var tinyCalls = 0
        let tinyControl = ScrollingCaptureCancellation()
        let tinyWorkflow = ScrollingCaptureWorkflow(screenshotService: service, frameProvider: { _ in
            tinyCalls += 1
            // Finish after the first frame: final capture must still flush a one-pixel tail.
            if tinyCalls == 1 { tinyOffset = 1; tinyControl.finish() }
            let y = tinyCalls == 1 ? 0 : tinyOffset
            return CapturedScreenshot(image: full.cropping(to: CGRect(x: 0, y: y, width: 240, height: 200))!, scaleFactor: 1)
        })
        let tinyResult = await tinyWorkflow.capture(rect: rect, cancellation: tinyControl)
        try check(tinyCalls == 2 && tinyResult?.image.height == 201, "Output must capture the final one-pixel movement even when finish arrives before the loop")
        try check(tinyResult.map { pixels($0.image) == pixels(full.cropping(to: CGRect(x: 0, y: 0, width: 240, height: 201))!) } == true, "Final one-pixel tail must be exact")
        var inFlightCalls = 0
        let inFlightControl = ScrollingCaptureCancellation()
        let inFlightWorkflow = ScrollingCaptureWorkflow(screenshotService: service, frameProvider: { _ in
            inFlightCalls += 1
            if inFlightCalls == 2 { inFlightControl.finish() }
            // Confirmation during an in-flight snapshot must request one more snapshot afterward.
            let y = inFlightCalls == 1 ? 0 : inFlightCalls == 2 ? 1 : 2
            return CapturedScreenshot(image: full.cropping(to: CGRect(x: 0, y: y, width: 240, height: 200))!, scaleFactor: 1)
        })
        let flushed = await inFlightWorkflow.capture(rect: rect, cancellation: inFlightControl)
        try check(inFlightCalls == 3 && flushed?.image.height == 202, "Confirmation during capture must flush a new frame after the action")
        let selection = CGRect(x: 100, y: 100, width: 600, height: 500)
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let short = ScrollingCaptureHUD.previewFrame(selection: selection, screen: screen, imageSize: CGSize(width: 600, height: 500))
        let medium = ScrollingCaptureHUD.previewFrame(selection: selection, screen: screen, imageSize: CGSize(width: 600, height: 1500))
        let long = ScrollingCaptureHUD.previewFrame(selection: selection, screen: screen, imageSize: CGSize(width: 600, height: 6000))
        try check(short.width == 176 && medium.width == 176 && medium.height > short.height, "Preview must grow at fixed width")
        try check(long.maxY == screen.maxY - 12 && long.width < medium.width && long.minY == selection.minY, "Tall preview must cap height, shrink width and retain bottom anchor")
        try check(abs(long.width / long.height - 0.1) < 0.001, "Preview must preserve aspect ratio")
        let edge = ScrollingCaptureHUD.previewFrame(selection: CGRect(x: 700, y: 100, width: 490, height: 500), screen: screen, imageSize: CGSize(width: 600, height: 6000))
        try check(screen.contains(edge), "Preview must stay on screen when selection is against right edge")
        var previewStitcher = ScrollingCaptureStitcher()
        _ = previewStitcher.append(full)
        let thumbnail = previewStitcher.stitchedImage(previewSize: CGSize(width: 120, height: 150))!
        try check(thumbnail.width == 60 && thumbnail.height == 150, "Bounded preview must downsample without allocating full result")
        try await verifyToolbarDestinations(capture: CapturedScreenshot(image: full, scaleFactor: 1))
        print("Scrolling passed: original toolbar copy/edit/save/pin routes, anchored auto/stop button, bounded live preview, long manual pauses, auto bottom waits for toolbar, exact pixels, cancellation.")
    }
    @MainActor static func verifyToolbarDestinations(capture: CapturedScreenshot) async throws {
        let screen = NSScreen.main!.frame
        for destination in [QuickMarkupBarSlot.Kind.done, .editor, .save, .pin, .cancel] {
            var control: ScrollingCaptureCancellation?
            var outcome: CaptureSelection?
            let session = AreaSelectionSession(quickMarkupEnabled: true, screenSnapshot: nil,
                onScrollingCapture: { _, cancellation, completion in
                    control = cancellation
                    Task { @MainActor in
                        while !cancellation.isFinished && !cancellation.isCancelled {
                            try? await Task.sleep(for: .milliseconds(10))
                        }
                        completion(cancellation.isCancelled ? nil : capture)
                    }
                }, onComplete: { outcome = $0 })
            let origin = CGPoint(x: screen.minX + 160, y: screen.minY + 200)
            session.handleMouseDown(globalPoint: origin)
            session.handleMouseDragged(globalPoint: CGPoint(x: origin.x + 240, y: origin.y + 200))
            session.handleMouseUp(globalPoint: CGPoint(x: origin.x + 240, y: origin.y + 200))
            let localBar = session.markupBarRect(in: screen)!
            let bar = localBar.offsetBy(dx: screen.minX, dy: screen.minY)
            func click(_ kind: QuickMarkupBarSlot.Kind) {
                let slot = QuickMarkupBarSlot.layout(in: bar).first { $0.kind == kind }!
                let point = CGPoint(x: slot.rect.midX, y: slot.rect.midY)
                session.handleMouseDown(globalPoint: point)
                session.handleMouseUp(globalPoint: point)
            }
            click(.scrolling)
            try check(session.showsScrollingOptions && !session.isAutomaticScrolling, "Scrolling must show one option and default to manual")
            try check(control != nil && !session.showsFrozenDesktop, "Scrolling must release the frozen desktop while retaining its bar")
            try check(session.markupPropertyBarRect(in: screen) == nil, "Scrolling button must replace the old property checkbox")
            control?.onPreview?(capture.image)
            let buttonFrame = ScrollingCaptureHUD.buttonFrame(selection: session.activeGlobalRect!)
            let buttonWindow = NSApp.windows.first { $0.isVisible && $0.frame == buttonFrame }!
            let button = buttonWindow.contentView as! NSButton
            try check(button.title == "自动滚动" && button.image != nil, "Manual session must have a labeled down-arrow button")
            control!.isAutomatic = true
            try check(button.title == "停止滚动" && button.image != nil, "Automatic mode must show pause and stop")
            button.sendAction(button.action!, to: button.target)
            try check(!control!.isAutomatic && !control!.isFinished, "Stop button must switch to manual without finishing")
            let toolbar = NSApp.windows.first { $0.isVisible && $0.frame.contains(CGPoint(x: bar.midX, y: bar.midY)) }!
            try check(!toolbar.ignoresMouseEvents, "Toolbar must remain clickable while the capture region is pass-through")
            if destination == .done, CommandLine.arguments.count > 1 {
                let panels = NSApp.windows.filter { $0.isVisible && $0 is NSPanel }.sorted { $0.level.rawValue < $1.level.rawValue }
                let union = panels.reduce(CGRect.null) { $0.union($1.frame) }.insetBy(dx: -16, dy: -16)
                let image = NSImage(size: union.size)
                image.lockFocus()
                NSColor(white: 0.55, alpha: 1).setFill()
                CGRect(origin: .zero, size: union.size).fill()
                for window in panels {
                    guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    rep.draw(in: window.frame.offsetBy(dx: -union.minX, dy: -union.minY))
                }
                image.unlockFocus()
                let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
                try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
            }
            click(destination)
            if destination == .cancel {
                try check(control!.isCancelled, "Original cancel button must stop the scrolling worker")
                guard case .cancelled = outcome else {
                    throw NSError(domain: "ScrollingCaptureWorkflowTests", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Cancel must dismiss without producing an image"])
                }
                try await Task.sleep(for: .milliseconds(40))
                try check(!toolbar.isVisible && !buttonWindow.isVisible, "Cancel must close toolbar and HUD")
                continue
            }
            try check(control!.isFinished && outcome == nil, "Toolbar must request the last frame before delivering")
            // Another destination during final-frame capture must not overwrite the first action.
            click(destination == .done ? .editor : .done)
            for _ in 0..<100 {
                if outcome != nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let delivered: CapturedScreenshot?
            switch (destination, outcome) {
            case (.done, .copyRegion(_, let annotations, let image)):
                try check(annotations.isEmpty, "Scrolling must not render stale overlay annotations")
                delivered = image
            case (.editor, .editRegion(_, let image)): delivered = image
            case (.save, .saveRegion(_, _, let image)): delivered = image
            case (.pin, .pinRegion(_, _, let image)): delivered = image
            default: throw NSError(domain: "ScrollingCaptureWorkflowTests", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Toolbar action routed to the wrong destination"])
            }
            try check(delivered?.image.height == 600, "Every destination must receive the full stitched image without re-capture")
            try check(!toolbar.isVisible && !buttonWindow.isVisible, "Output must close toolbar and HUD")
        }
    }

    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "ScrollingCaptureWorkflowTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func pixels(_ image: CGImage) -> Data {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: context.data!, count: image.width * image.height * 4)
    }
    static func fixture() -> CGImage {
        let width = 240, height = 600
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8((x * 13 + y * 7) % 251)
                bytes[offset + 1] = UInt8((x * 5 + y * 17) % 253)
                bytes[offset + 2] = UInt8((x * 23 + y * 3) % 247)
            }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}
