@testable import HeySnapCore
import CoreGraphics
import Testing

@Suite("Window enumerator coordinates")
struct WindowEnumeratorTests {
    @Test("Quartz top-left rect flips to AppKit bottom-left origin")
    func flipsTopLeftToBottomLeft() {
        // A 1000pt-tall primary display; a window at Quartz y=100 with height=200
        // occupies AppKit y = 1000 - 100 - 200 = 700.
        let quartz = CGRect(x: 50, y: 100, width: 300, height: 200)
        let appKit = WindowEnumerator.appKitFrame(fromQuartz: quartz, primaryHeight: 1000)

        #expect(appKit == CGRect(x: 50, y: 700, width: 300, height: 200))
    }

    @Test("A window flush to the top of the display maps to the top of AppKit space")
    func topWindowMapsToTopOfAppKitSpace() {
        let quartz = CGRect(x: 0, y: 0, width: 400, height: 50)
        let appKit = WindowEnumerator.appKitFrame(fromQuartz: quartz, primaryHeight: 900)

        #expect(appKit == CGRect(x: 0, y: 850, width: 400, height: 50))
    }
}
