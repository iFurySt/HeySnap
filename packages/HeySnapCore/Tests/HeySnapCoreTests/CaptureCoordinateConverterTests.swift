@testable import HeySnapCore
import CoreGraphics
import Testing

@Suite("Capture coordinate conversion")
struct CaptureCoordinateConverterTests {
    @Test("AppKit upper-left region flips to ScreenCaptureKit upper-left")
    func appKitUpperLeftRegionFlipsToScreenCaptureUpperLeft() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let appKitRect = CGRect(x: 20, y: 882, width: 200, height: 80)

        let captureRect = CaptureCoordinateConverter.screenCaptureRect(
            fromAppKitRect: appKitRect,
            screenFrames: [screen]
        )

        #expect(captureRect == CGRect(x: 20, y: 20, width: 200, height: 80))
    }

    @Test("AppKit lower-left region flips to ScreenCaptureKit lower-left")
    func appKitLowerLeftRegionFlipsToScreenCaptureLowerLeft() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let appKitRect = CGRect(x: 20, y: 20, width: 200, height: 80)

        let captureRect = CaptureCoordinateConverter.screenCaptureRect(
            fromAppKitRect: appKitRect,
            screenFrames: [screen]
        )

        #expect(captureRect == CGRect(x: 20, y: 882, width: 200, height: 80))
    }

    @Test("Conversion uses the screen with the largest selected area")
    func conversionUsesDominantScreen() {
        let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1200, height: 900)
        let appKitRect = CGRect(x: 1100, y: 760, width: 300, height: 100)

        let captureRect = CaptureCoordinateConverter.screenCaptureRect(
            fromAppKitRect: appKitRect,
            screenFrames: [primary, right]
        )

        #expect(captureRect == CGRect(x: 1100, y: 40, width: 300, height: 100))
    }
}
