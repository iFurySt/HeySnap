import CoreGraphics
import Vision

/// Runs Apple's local text recognition on a captured bitmap; no screen recapture or upload.
enum ScreenshotTextRecognizer {
    static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let supported = try request.supportedRecognitionLanguages()
        let preferred = ["zh-Hans", "zh-Hant", "en-US"].filter { supported.contains($0) }
        if !preferred.isEmpty { request.recognitionLanguages = preferred }
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
