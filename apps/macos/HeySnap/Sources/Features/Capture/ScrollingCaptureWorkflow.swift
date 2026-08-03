import AppKit

@MainActor
final class ScrollingCaptureWorkflow {
    private let screenshotService: ScreenshotService
    private let logInfo: (String) -> Void
    private let logError: (String) -> Void
    private var progressWindow: NSWindow?

    init(
        screenshotService: ScreenshotService,
        logInfo: @escaping (String) -> Void = { _ in },
        logError: @escaping (String) -> Void = { _ in }
    ) {
        self.screenshotService = screenshotService
        self.logInfo = logInfo
        self.logError = logError
    }

    func capture(rect: CGRect, cancellation: ScrollingCaptureCancellation) async -> CapturedScreenshot? {
        logInfo("Manual scrolling capture started with rect=\(rect).")
        screenshotService.publishStatus(.capturing)

        showProgressWindow(near: rect)
        defer {
            closeProgressWindow()
        }

        do {
            let first = try await screenshotService.captureScrollingFrame(rect: rect)
            let minimumShift = Self.minimumAcceptedShift(for: first.image)
            let configuration = ScrollingCaptureStitcher.Configuration(
                maxHeight: 20_000,
                minimumShift: minimumShift,
                maximumShiftRatio: 0.82,
                sampleStride: 10,
                noMovementLimit: 3,
                maximumAveragePixelDistance: 2_500
            )
            var stitcher = ScrollingCaptureStitcher(configuration: configuration)
            _ = stitcher.append(first.image)
            logInfo("Manual scrolling capture first frame size=\(first.image.width)x\(first.image.height), minimumShift=\(minimumShift).")

            let maxFrames = 36
            let interval: UInt64 = 320_000_000
            var sawMovement = false
            var idleBeforeMovement = 0

            for frameIndex in 1...maxFrames {
                guard !cancellation.isCancelled else {
                    logInfo("Manual scrolling capture cancelled before frame=\(frameIndex).")
                    return nil
                }
                try await Task.sleep(nanoseconds: interval)
                guard !cancellation.isCancelled else {
                    logInfo("Manual scrolling capture cancelled before frame capture, frame=\(frameIndex).")
                    return nil
                }

                let frame = try await screenshotService.captureScrollingFrame(rect: rect)
                let accepted = stitcher.append(frame.image)
                sawMovement = sawMovement || accepted
                if sawMovement {
                    idleBeforeMovement = 0
                } else {
                    idleBeforeMovement += 1
                }
                updateProgressWindow(frameCount: stitcher.frameCount, height: stitcher.estimatedHeight)
                logInfo("Manual scrolling capture sampled frame=\(frameIndex), accepted=\(accepted), shift=\(stitcher.lastAcceptedShift ?? 0), estimatedHeight=\(stitcher.estimatedHeight), noMovementStreak=\(stitcher.noMovementStreak).")

                if stitcher.estimatedHeight >= configuration.maxHeight {
                    break
                }
                if sawMovement, stitcher.noMovementStreak >= 3 {
                    break
                }
                if !sawMovement, idleBeforeMovement >= 12 {
                    break
                }
            }

            guard stitcher.frameCount > 1, let image = stitcher.stitchedImage() else {
                let message = "HeySnap could not detect scrolling movement in the selected area."
                screenshotService.publishStatus(.failure(message))
                logError(message)
                NSSound.beep()
                return nil
            }

            screenshotService.publishStatus(.success("Opened scrolling screenshot editor"))
            logInfo("Manual scrolling capture stitched image \(image.width)x\(image.height).")
            return CapturedScreenshot(image: image, scaleFactor: first.scaleFactor)
        } catch {
            screenshotService.publishStatus(.failure(error.localizedDescription))
            logError("Manual scrolling capture failed: \(error.localizedDescription).")
            NSSound.beep()
            return nil
        }
    }

    private static func minimumAcceptedShift(for image: CGImage) -> Int {
        max(18, Int((CGFloat(image.height) * 0.025).rounded()))
    }

    private func showProgressWindow(near rect: CGRect) {
        let view = ScrollingCaptureProgressView()
        let window = NSPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 238, height: 52)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true

        let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(rect) })?.frame
            ?? NSScreen.main?.frame
            ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let x = min(max(rect.midX - 119, screenFrame.minX + 10), screenFrame.maxX - 248)
        let y = min(max(rect.maxY + 14, screenFrame.minY + 10), screenFrame.maxY - 62)
        window.setFrameOrigin(CGPoint(x: x, y: y))
        window.orderFrontRegardless()
        progressWindow = window
    }

    private func updateProgressWindow(frameCount: Int, height: Int) {
        guard let view = progressWindow?.contentView as? ScrollingCaptureProgressView else { return }
        view.update(frameCount: frameCount, height: height)
    }

    private func closeProgressWindow() {
        progressWindow?.orderOut(nil)
        progressWindow = nil
    }
}

@MainActor
final class ScrollingCaptureCancellation {
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

private final class ScrollingCaptureProgressView: NSView {
    private var frameCount = 1
    private var height = 0

    init() {
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: 238, height: 52)))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(frameCount: Int, height: Int) {
        self.frameCount = frameCount
        self.height = height
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 0.8
        path.stroke()

        if let symbol = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)) {
            symbol.isTemplate = true
            NSColor.labelColor.set()
            symbol.draw(in: CGRect(x: 14, y: 17, width: 18, height: 18))
        }

        NSString(string: "Scroll manually").draw(in: CGRect(x: 42, y: 27, width: 178, height: 17), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ])

        let detail = "\(frameCount) frames" + (height > 0 ? " - \(height) px" : "")
        NSString(string: detail).draw(in: CGRect(x: 42, y: 10, width: 178, height: 15), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
    }
}
