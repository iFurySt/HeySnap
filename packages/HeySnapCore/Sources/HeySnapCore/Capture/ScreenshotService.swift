import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct CapturedScreenshot {
    let image: CGImage
    let scaleFactor: CGFloat
    let sourceRect: CGRect?

    init(image: CGImage, scaleFactor: CGFloat, sourceRect: CGRect? = nil) {
        self.image = image
        self.scaleFactor = scaleFactor
        self.sourceRect = sourceRect
    }
}

@MainActor
final class ScreenshotService: ObservableObject {
    @Published private(set) var status: CaptureStatus = .idle
    @Published private(set) var lastSavedURL: URL?
    @Published private(set) var hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()

    private let saveDirectoryProvider: () -> URL
    private let saveFormatPreferenceProvider: () -> ScreenshotSaveFormatPreference
    private let resizeRetinaScreenshotsProvider: () -> Bool
    private let windowBackgroundProvider: () -> WindowScreenshotBackground
    private let logInfo: (String) -> Void
    private let logError: (String) -> Void

    init(
        saveDirectoryProvider: @escaping () -> URL,
        saveFormatPreferenceProvider: @escaping () -> ScreenshotSaveFormatPreference = { .default },
        resizeRetinaScreenshotsProvider: @escaping () -> Bool = { false },
        windowBackgroundProvider: @escaping () -> WindowScreenshotBackground = { .transparent },
        logInfo: @escaping (String) -> Void = { _ in },
        logError: @escaping (String) -> Void = { _ in }
    ) {
        self.saveDirectoryProvider = saveDirectoryProvider
        self.saveFormatPreferenceProvider = saveFormatPreferenceProvider
        self.resizeRetinaScreenshotsProvider = resizeRetinaScreenshotsProvider
        self.windowBackgroundProvider = windowBackgroundProvider
        self.logInfo = logInfo
        self.logError = logError
    }

    func captureAndSave() async {
        status = .capturing
        logInfo("Capture started.")

        do {
            let capture = try await captureScreen()
            let outputURL = try save(capture.image, sourceScaleFactor: capture.scaleFactor)
            lastSavedURL = outputURL
            status = .success(outputURL.path)
            logInfo("Capture saved: \(outputURL.path).")
        } catch {
            status = .failure(error.localizedDescription)
            logError("Capture failed: \(error.localizedDescription).")
        }
    }

    func captureForEditing() async -> CapturedScreenshot? {
        status = .capturing
        logInfo("Capture for editor started.")

        do {
            let capture = try await captureScreen()
            status = .success("Opened screenshot editor")
            logInfo("Capture opened in editor.")
            return capture
        } catch {
            status = .failure(error.localizedDescription)
            logError("Capture for editor failed: \(error.localizedDescription).")
            return nil
        }
    }

    func captureAndSave(rect: CGRect) async {
        status = .capturing
        logInfo("Area capture started with rect=\(rect).")

        do {
            let capture = try await captureScreen(rect: rect)
            let outputURL = try save(capture.image, sourceScaleFactor: capture.scaleFactor)
            lastSavedURL = outputURL
            status = .success(outputURL.path)
            logInfo("Area capture saved: \(outputURL.path).")
        } catch {
            status = .failure(error.localizedDescription)
            logError("Area capture failed: \(error.localizedDescription).")
        }
    }

    func captureForEditing(rect: CGRect) async -> CapturedScreenshot? {
        status = .capturing
        logInfo("Area capture for editor started with rect=\(rect).")

        do {
            let capture = try await captureScreen(rect: rect)
            status = .success("Opened screenshot editor")
            logInfo("Area capture opened in editor.")
            return capture
        } catch {
            status = .failure(error.localizedDescription)
            logError("Area capture for editor failed: \(error.localizedDescription).")
            return nil
        }
    }

    func captureScrollingFrame(rect: CGRect) async throws -> CapturedScreenshot {
        logInfo("Scrolling capture frame requested with rect=\(rect).")
        let provider = try await makeScrollingFrameProvider(rect: rect)
        return try await provider()
    }

    func captureAndSave(windowID: CGWindowID) async {
        status = .capturing
        logInfo("Window capture started with windowID=\(windowID).")

        do {
            let capture = try await captureWindow(windowID: windowID)
            let outputURL = try save(capture.image, sourceScaleFactor: capture.scaleFactor)
            lastSavedURL = outputURL
            status = .success(outputURL.path)
            logInfo("Window capture saved: \(outputURL.path).")
        } catch {
            status = .failure(error.localizedDescription)
            logError("Window capture failed: \(error.localizedDescription).")
        }
    }

    func captureForEditing(windowID: CGWindowID) async -> CapturedScreenshot? {
        status = .capturing
        logInfo("Window capture for editor started with windowID=\(windowID).")

        do {
            let capture = try await captureWindow(windowID: windowID)
            status = .success("Opened screenshot editor")
            logInfo("Window capture opened in editor.")
            return capture
        } catch {
            status = .failure(error.localizedDescription)
            logError("Window capture for editor failed: \(error.localizedDescription).")
            return nil
        }
    }

    @discardableResult
    func saveEditedImage(_ image: CGImage, sourceScaleFactor: CGFloat) throws -> URL {
        let outputURL = try save(image, sourceScaleFactor: sourceScaleFactor)
        lastSavedURL = outputURL
        status = .success(outputURL.path)
        logInfo("Edited screenshot saved: \(outputURL.path).")
        return outputURL
    }

    func publishStatus(_ status: CaptureStatus) {
        self.status = status
    }

    func refreshPermissionStatus() {
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
    }

    private func save(_ image: CGImage, sourceScaleFactor: CGFloat) throws -> URL {
        let preference = saveFormatPreferenceProvider()
        let outputImage = try ScreenshotImageResizer.downscaleRetinaIfNeeded(
            image,
            sourceScaleFactor: sourceScaleFactor,
            shouldDownscale: resizeRetinaScreenshotsProvider()
        )
        if outputImage.width != image.width || outputImage.height != image.height {
            logInfo("Downscaled Retina screenshot from \(image.width)x\(image.height) to \(outputImage.width)x\(outputImage.height).")
        }
        let encodedImage = try ScreenshotImageEncoder.encode(outputImage, using: preference)
        let outputURL = try prepareOutputURL(fileExtension: encodedImage.format.fileExtension)
        logInfo("Prepared output URL: \(outputURL.path).")
        try encodedImage.data.write(to: outputURL, options: .atomic)
        logInfo("Wrote \(encodedImage.format.displayName) screenshot: \(outputURL.path).")
        return outputURL
    }

    private func prepareOutputURL(fileExtension: String) throws -> URL {
        let directory = saveDirectoryProvider()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let filename = "HeySnap-\(formatter.string(from: Date())).\(fileExtension)"
        return directory.appendingPathComponent(filename)
    }

    private func captureScreen() async throws -> CapturedScreenshot {
        if #available(macOS 26.0, *) {
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                hasScreenRecordingPermission = false
                throw ScreenshotError.screenRecordingPermissionDenied
            }
            hasScreenRecordingPermission = true

            let rect = captureRectForMouseScreen()
            return try await captureScreen(rect: rect)
        }

        throw ScreenshotError.unsupportedOS
    }

    private func captureScreen(rect: CGRect) async throws -> CapturedScreenshot {
        if #available(macOS 26.0, *) {
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                hasScreenRecordingPermission = false
                throw ScreenshotError.screenRecordingPermissionDenied
            }
            hasScreenRecordingPermission = true

            guard !rect.isNull, rect.width > 1, rect.height > 1 else {
                throw ScreenshotError.emptyCaptureRect
            }

            let configuration = SCScreenshotConfiguration()
            configuration.showsCursor = false
            guard let pngType = UTTypeReference("public.png") else {
                throw ScreenshotError.missingPNGType
            }
            configuration.contentType = pngType
            configuration.dynamicRange = .sdr
            let captureRect = screenCaptureRect(fromAppKitRect: rect)
            logInfo("Calling SCScreenshotManager.captureScreenshot appKitRect=\(rect), captureRect=\(captureRect).")
            let output = try await SCScreenshotManager.captureScreenshot(rect: captureRect, configuration: configuration)

            guard let image = output.sdrImage else {
                throw ScreenshotError.missingImageOutput
            }

            return CapturedScreenshot(
                image: image,
                scaleFactor: scaleFactor(for: image, pointRect: captureRect),
                sourceRect: rect
            )
        }

        throw ScreenshotError.unsupportedOS
    }

    private func captureWindow(windowID: CGWindowID) async throws -> CapturedScreenshot {
        if #available(macOS 26.0, *) {
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                hasScreenRecordingPermission = false
                throw ScreenshotError.screenRecordingPermissionDenied
            }
            hasScreenRecordingPermission = true

            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw ScreenshotError.windowUnavailable
            }

            // A desktop-independent filter captures just this window, cleanly excluding any
            // overlapping windows (including our own selection overlay).
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            configuration.showsCursor = false
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = Int(filter.contentRect.width * scale)
            configuration.height = Int(filter.contentRect.height * scale)

            logInfo("Calling SCScreenshotManager.captureImage windowID=\(windowID).")
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            let compositedImage = try await applyWindowBackground(to: image, windowFrame: window.frame)
            return CapturedScreenshot(image: compositedImage, scaleFactor: scale, sourceRect: window.frame)
        }

        throw ScreenshotError.unsupportedOS
    }

    /// Prepare the filter once per scrolling session, including future windows of this app.
    func makeScrollingFrameProvider(rect: CGRect) async throws -> () async throws -> CapturedScreenshot {
        if #available(macOS 26.0, *) {
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                hasScreenRecordingPermission = false
                throw ScreenshotError.screenRecordingPermissionDenied
            }
            hasScreenRecordingPermission = true

            guard !rect.isNull, rect.width > 1, rect.height > 1 else {
                throw ScreenshotError.emptyCaptureRect
            }

            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            let screenFrames = NSScreen.screens.map(\.frame)
            guard let screenFrame = CaptureCoordinateConverter.dominantScreenFrame(for: rect, screenFrames: screenFrames),
                  let display = content.displays.first(where: { displayFrame(for: $0, screenFrames: screenFrames) == screenFrame }) else {
                throw ScreenshotError.displayUnavailable
            }

            let currentProcessID = NSRunningApplication.current.processIdentifier
            let excludedApplications = content.applications.filter { $0.processID == currentProcessID }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            filter.includeMenuBar = false

            let sourceRect = CGRect(
                x: rect.minX - screenFrame.minX,
                y: screenFrame.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            ).integral
            let scale = CGFloat(filter.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.showsCursor = false
            configuration.sourceRect = sourceRect
            configuration.width = Int(sourceRect.width * scale)
            configuration.height = Int(sourceRect.height * scale)

            logInfo("Prepared scrolling capture filter rect=\(rect), excludedApps=\(excludedApplications.count).")
            return {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                return CapturedScreenshot(image: image, scaleFactor: scale)
            }
        }

        throw ScreenshotError.unsupportedOS
    }

    private func applyWindowBackground(to image: CGImage, windowFrame: CGRect) async throws -> CGImage {
        let preference = windowBackgroundProvider()
        switch preference {
        case .transparent:
            return image
        case .shadow:
            return ScreenshotWindowBackgroundRenderer.shadowed(image)
        case .solidColor:
            let color = (NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? NSColor.windowBackgroundColor).cgColor
            return ScreenshotWindowBackgroundRenderer.composite(image, over: color)
        case .wallpaper:
            do {
                let background = try await captureScreen(rawRect: windowFrame.integral)
                return ScreenshotWindowBackgroundRenderer.composite(image, over: background.image)
            } catch {
                logError("Window wallpaper background failed: \(error.localizedDescription).")
                return image
            }
        }
    }

    private func captureScreen(rawRect rect: CGRect) async throws -> CapturedScreenshot {
        if #available(macOS 26.0, *) {
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                hasScreenRecordingPermission = false
                throw ScreenshotError.screenRecordingPermissionDenied
            }
            hasScreenRecordingPermission = true

            guard !rect.isNull, rect.width > 1, rect.height > 1 else {
                throw ScreenshotError.emptyCaptureRect
            }

            let configuration = SCScreenshotConfiguration()
            configuration.showsCursor = false
            guard let pngType = UTTypeReference("public.png") else {
                throw ScreenshotError.missingPNGType
            }
            configuration.contentType = pngType
            configuration.dynamicRange = .sdr
            logInfo("Calling SCScreenshotManager.captureScreenshot rawRect=\(rect).")
            let output = try await SCScreenshotManager.captureScreenshot(rect: rect, configuration: configuration)

            guard let image = output.sdrImage else {
                throw ScreenshotError.missingImageOutput
            }

            return CapturedScreenshot(
                image: image,
                scaleFactor: scaleFactor(for: image, pointRect: rect),
                sourceRect: rect
            )
        }

        throw ScreenshotError.unsupportedOS
    }

    private func screenCaptureRect(fromAppKitRect rect: CGRect) -> CGRect {
        CaptureCoordinateConverter.screenCaptureRect(
            fromAppKitRect: rect,
            screenFrames: NSScreen.screens.map(\.frame)
        )
    }

    private func displayFrame(for display: SCDisplay, screenFrames: [CGRect]) -> CGRect? {
        screenFrames.first {
            abs($0.width - display.frame.width) < 0.5
                && abs($0.height - display.frame.height) < 0.5
                && abs($0.minX - display.frame.minX) < 0.5
        }
    }

    private func scaleFactor(for image: CGImage, pointRect: CGRect) -> CGFloat {
        guard pointRect.width > 0, pointRect.height > 0 else {
            return 1
        }

        let widthScale = CGFloat(image.width) / pointRect.width
        let heightScale = CGFloat(image.height) / pointRect.height
        return max(1, max(widthScale, heightScale))
    }

    private func captureRectForMouseScreen() -> CGRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return .zero
        }

        let mouseLocation = NSEvent.mouseLocation
        if let screen = screens.first(where: { $0.frame.contains(mouseLocation) }) {
            logInfo("Selected screen under mouse=\(mouseLocation), frame=\(screen.frame).")
            return screen.frame
        }

        let nearestScreen = screens.min { lhs, rhs in
            distanceSquared(from: mouseLocation, to: lhs.frame.center) <
                distanceSquared(from: mouseLocation, to: rhs.frame.center)
        } ?? screens[0]
        logInfo("Selected nearest screen for mouse=\(mouseLocation), frame=\(nearestScreen.frame).")
        return nearestScreen.frame
    }

    private func distanceSquared(from point: CGPoint, to other: CGPoint) -> CGFloat {
        let dx = point.x - other.x
        let dy = point.y - other.y
        return dx * dx + dy * dy
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

enum CaptureStatus: Equatable {
    case idle
    case capturing
    case success(String)
    case failure(String)

    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .capturing:
            return "Capturing"
        case .success:
            return "Saved"
        case .failure:
            return "Needs attention"
        }
    }

    var message: String {
        switch self {
        case .idle:
            return "Press Shift+Option+A to capture the current screen."
        case .capturing:
            return "Saving the screenshot..."
        case .success(let path):
            return path
        case .failure(let message):
            return message
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            return "camera.viewfinder"
        case .capturing:
            return "camera.aperture"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    var isFailure: Bool {
        if case .failure = self {
            return true
        }
        return false
    }
}

enum ScreenshotError: LocalizedError {
    case unsupportedOS
    case missingPNGType
    case screenRecordingPermissionDenied
    case missingImageOutput
    case imageWriteFailed(ScreenshotOutputFormat)
    case emptyCaptureRect
    case noOutputFormatSelected
    case webPEncoderUnavailable
    case windowUnavailable
    case displayUnavailable
    case imageResizeFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "ScreenCaptureKit screenshot capture requires macOS 26 or later."
        case .missingPNGType:
            return "The system PNG uniform type is unavailable."
        case .screenRecordingPermissionDenied:
            return "Screen Recording permission is required to capture screenshots."
        case .missingImageOutput:
            return "ScreenCaptureKit did not return an image to save."
        case .imageWriteFailed(let format):
            return "The screenshot \(format.displayName) could not be written."
        case .emptyCaptureRect:
            return "The selected capture area is too small."
        case .noOutputFormatSelected:
            return "At least one automatic screenshot format must be selected."
        case .webPEncoderUnavailable:
            return "The WebP encoder is unavailable on this Mac."
        case .windowUnavailable:
            return "The selected window is no longer available to capture."
        case .displayUnavailable:
            return "The selected display is no longer available to capture."
        case .imageResizeFailed:
            return "The screenshot could not be resized."
        }
    }
}
