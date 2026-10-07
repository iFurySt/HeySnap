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

    @Test("Unequal-height displays share the primary display origin")
    func conversionUsesDominantScreen() {
        let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1200, height: 900)
        let appKitRect = CGRect(x: 1100, y: 760, width: 300, height: 100)

        let captureRect = CaptureCoordinateConverter.screenCaptureRect(
            fromAppKitRect: appKitRect,
            screenFrames: [primary, right]
        )

        #expect(captureRect == CGRect(x: 1100, y: -60, width: 300, height: 100))
    }

    @Test("A display below the primary maps below it in display space")
    func lowerDisplayUsesGlobalOrigin() {
        let primary = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let lower = CGRect(x: 500, y: -982, width: 1512, height: 982)
        #expect(CaptureCoordinateConverter.screenCaptureRect(
            fromAppKitRect: lower, screenFrames: [primary, lower]
        ) == CGRect(x: 500, y: 1440, width: 1512, height: 982))
        #expect(CaptureCoordinateConverter.screenCaptureRect(
            fromAppKitRect: CGRect(x: 744, y: -532, width: 94, height: 49),
            screenFrames: [primary, lower]
        ) == CGRect(x: 744, y: 1923, width: 94, height: 49))
    }

    @Test("A display above the primary maps to negative display-space y")
    func upperDisplayUsesGlobalOrigin() {
        let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let upper = CGRect(x: -300, y: 982, width: 2560, height: 1440)
        #expect(CaptureCoordinateConverter.screenCaptureRect(
            fromAppKitRect: upper, screenFrames: [primary, upper]
        ) == CGRect(x: -300, y: -1440, width: 2560, height: 1440))
    }
}
