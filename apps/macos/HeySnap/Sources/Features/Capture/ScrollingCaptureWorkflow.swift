import AppKit
import ApplicationServices

@MainActor
final class ScrollingCaptureWorkflow {
    private let screenshotService: ScreenshotService
    private let logInfo: (String) -> Void
    private let logError: (String) -> Void
    private let frameProvider: ((CGRect) async throws -> CapturedScreenshot)?
    private let scrollProvider: ((CGRect) -> Void)?

    init(screenshotService: ScreenshotService,
         logInfo: @escaping (String) -> Void = { _ in },
         logError: @escaping (String) -> Void = { _ in },
         frameProvider: ((CGRect) async throws -> CapturedScreenshot)? = nil,
         scrollProvider: ((CGRect) -> Void)? = nil) {
        self.screenshotService = screenshotService
        self.logInfo = logInfo
        self.logError = logError
        self.frameProvider = frameProvider
        self.scrollProvider = scrollProvider
    }

    func capture(rect: CGRect, cancellation: ScrollingCaptureCancellation) async -> CapturedScreenshot? {
        logInfo("Scrolling capture started with rect=\(rect).")
        screenshotService.publishStatus(.capturing)
        defer {
            if cancellation.isCancelled { screenshotService.publishStatus(.idle) }
        }
        do {
            guard !cancellation.isCancelled else { return nil }
            let captureFrame: () async throws -> CapturedScreenshot
            if let frameProvider { captureFrame = { try await frameProvider(rect) } }
            else { captureFrame = try await screenshotService.makeScrollingFrameProvider(rect: rect) }
            let first = try await captureFrame()
            // Small final movements at the bottom must still be appended.
            let configuration = ScrollingCaptureStitcher.Configuration(
                maxHeight: max(first.image.height, min(20_000, 64_000_000 / max(1, first.image.width))), minimumShift: 1, maximumShiftRatio: 0.95,
                sampleStride: 6, noMovementLimit: 3, maximumAveragePixelDistance: 1_000)
            var stitcher = ScrollingCaptureStitcher(configuration: configuration)
            _ = stitcher.append(first.image)
            let initialStitcher = stitcher
            let initialPreview = await Task.detached { initialStitcher.stitchedImage(previewSize: CGSize(width: 352, height: 2200)) }.value
            if !cancellation.isCancelled, let initialPreview { cancellation.onPreview?(initialPreview) }
            // Drive smooth small wheel steps independently of screenshot/matching latency.
            let scrollingGate = ScrollingCaptureAutomaticGate()
            let scrollTask = Task { @MainActor in
                var wasAutomatic = false
                while !cancellation.isCancelled && !cancellation.isFinished && !Task.isCancelled {
                    let automatic = cancellation.isAutomatic
                    if automatic && !wasAutomatic && self.scrollProvider == nil {
                        CGWarpMouseCursorPosition(self.scrollPoint(in: rect))
                    }
                    if automatic && !scrollingGate.isPaused { self.postScroll(in: rect) }
                    wasAutomatic = automatic
                    do { try await Task.sleep(for: .milliseconds(33)) } catch { break }
                }
            }
            defer { scrollTask.cancel() }
            var automaticIdle = 0
            var automaticMoved = false
            var recovery = ScrollingCaptureMatchRecovery()
            var previousMode = false
            let started = Date()
            var lastSample = Date()
            var lastPreview = Date()
            var lastLog = Date.distantPast
            var idleSamples = 0
            while Date().timeIntervalSince(started) < 180 {
                guard !cancellation.isCancelled else { return nil }
                let finishing = cancellation.isFinished
                let automatic = cancellation.isAutomatic
                if automatic != previousMode {
                    automaticIdle = 0
                    recovery.reset()
                    scrollingGate.isPaused = false
                    automaticMoved = false
                    previousMode = automatic
                    logInfo("Scrolling capture mode=\(automatic ? "automatic" : "manual").")
                }
                // Period includes capture and matching time; never stack work or queue stale frames.
                let period = !automatic && idleSamples >= 5 ? 0.12 : 0.06
                let remaining = max(0, period - Date().timeIntervalSince(lastSample))
                if !finishing && remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
                guard !cancellation.isCancelled else { return nil }
                lastSample = Date()
                let frame = try await captureFrame()
                let currentStitcher = stitcher
                let wantsPreview = Date().timeIntervalSince(lastPreview) >= 0.10 || cancellation.isFinished
                let result = await Task.detached(priority: .userInitiated) {
                    var next = currentStitcher
                    let accepted = next.append(frame.image)
                    let preview = accepted && wantsPreview ? next.stitchedImage(previewSize: CGSize(width: 352, height: 2200)) : nil
                    return (next, accepted, preview)
                }.value
                guard !cancellation.isCancelled else { return nil }
                stitcher = result.0
                let accepted = result.1
                idleSamples = stitcher.lastFrameWasStationary ? idleSamples + 1 : 0
                let shouldWarn = recovery.observe(accepted: accepted, stationary: stitcher.lastFrameWasStationary, now: Date())
                scrollingGate.isPaused = automatic && recovery.isRetrying
                if let preview = result.2 { cancellation.onPreview?(preview); lastPreview = Date() }
                if accepted || Date().timeIntervalSince(lastLog) >= 1 {
                    logInfo("Scrolling capture sampled accepted=\(accepted), shift=\(accepted ? stitcher.lastAcceptedShift ?? 0 : 0), height=\(stitcher.estimatedHeight), stationary=\(stitcher.lastFrameWasStationary), retrying=\(recovery.isRetrying), processingMS=\(Int(Date().timeIntervalSince(lastSample) * 1000)).")
                    lastLog = Date()
                }
                if finishing { break }
                if cancellation.isFinished { continue }
                if shouldWarn {
                    cancellation.onMessage?("滚动跨度较大或页面内容变化，请稍微向上回滚后继续")
                }
                if stitcher.estimatedHeight >= configuration.maxHeight { break }
                if automatic && cancellation.isAutomatic {
                    automaticMoved = automaticMoved || accepted
                    if shouldWarn {
                        cancellation.isAutomatic = false
                        continue
                    }
                    automaticIdle = stitcher.lastFrameWasStationary ? automaticIdle + 1 : 0
                    if automaticIdle >= 3 {
                        if automaticMoved {
                            cancellation.isAutomatic = false
                            cancellation.onMessage?("Reached bottom. Use the toolbar to copy, save or edit.")
                            continue
                        }
                        cancellation.isAutomatic = false
                        cancellation.onMessage?("No movement. Scroll manually or use the toolbar.")
                    }
                }
            }
            scrollTask.cancel()
            cancellation.isAutomatic = false
            let finalStitcher = stitcher
            let output = await Task.detached(priority: .userInitiated) {
                (finalStitcher.stitchedImage(), finalStitcher.stitchedImage(previewSize: CGSize(width: 352, height: 2200)))
            }.value
            guard !cancellation.isCancelled, let image = output.0 else { return nil }
            if let preview = output.1 { cancellation.onPreview?(preview) }
            screenshotService.publishStatus(.success("Scrolling screenshot ready"))
            logInfo("Scrolling capture stitched image \(image.width)x\(image.height), frames=\(stitcher.frameCount).")
            return CapturedScreenshot(image: image, scaleFactor: first.scaleFactor)
        } catch {
            screenshotService.publishStatus(.failure(error.localizedDescription))
            logError("Scrolling capture failed: \(error.localizedDescription).")
            NSSound.beep()
            return nil
        }
    }

    private func scrollPoint(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - rect.midY)
    }

    private func postScroll(in rect: CGRect) {
        if let scrollProvider { scrollProvider(rect); return }
        let point = scrollPoint(in: rect)
        // Keep the event location in the content without repeatedly moving the user’s pointer.
        let amount = -Int32(max(3, min(12, rect.height * 0.008)))
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                            wheel1: amount, wheel2: 0, wheel3: 0)
        event?.location = point
        event?.post(tap: .cghidEventTap)
    }

}

@MainActor
final class ScrollingCaptureCancellation {
    private(set) var isCancelled = false
    private(set) var isFinished = false
    var isAutomatic = false { didSet { if oldValue != isAutomatic { onChange?() } } }
    var onChange: (() -> Void)?
    var onMessage: ((String) -> Void)?
    var onPreview: ((CGImage) -> Void)?

    @discardableResult
    func setAutomatic(_ enabled: Bool) -> Bool {
        if enabled && !AXIsProcessTrusted() {
            isAutomatic = false
            onMessage?("Allow HeySnap in Accessibility for auto scroll")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return false
        }
        isAutomatic = enabled
        return true
    }
    func cancel() { isAutomatic = false; isCancelled = true }
    func finish() { isAutomatic = false; isFinished = true }
}

@MainActor
private final class ScrollingCaptureAutomaticGate {
    var isPaused = false
}

/// Transient mismatch is a retry, with one notice only after sustained failure.
struct ScrollingCaptureMatchRecovery {
    private var failureStarted: Date?
    private var failures = 0
    private var warned = false
    private var lastNotice = Date.distantPast
    var isRetrying: Bool { failureStarted != nil }

    mutating func reset() { failureStarted = nil; failures = 0; warned = false }

    mutating func observe(accepted: Bool, stationary: Bool, now: Date) -> Bool {
        if accepted || stationary { reset(); return false }
        if failureStarted == nil { failureStarted = now }
        failures += 1
        guard !warned, failures >= 4, now.timeIntervalSince(failureStarted!) >= 0.9,
              now.timeIntervalSince(lastNotice) >= 4 else { return false }
        warned = true
        lastNotice = now
        return true
    }
}
