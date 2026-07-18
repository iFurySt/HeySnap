import AppKit
import CoreGraphics
import Foundation

/// A single on-screen window candidate for hover selection.
///
/// `frame` is expressed in AppKit global coordinates (bottom-left origin) so it can be
/// hit-tested against `NSEvent.mouseLocation` and drawn by overlay windows directly.
public struct WindowDescriptor: Equatable, Sendable {
    public let windowID: CGWindowID
    public let ownerPID: pid_t
    public let ownerName: String
    public let title: String
    public let frame: CGRect

    public init(
        windowID: CGWindowID,
        ownerPID: pid_t,
        ownerName: String,
        title: String,
        frame: CGRect
    ) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
        self.frame = frame
    }
}

/// Enumerates on-screen windows via `CGWindowListCopyWindowInfo` and hit-tests the mouse
/// against them, using only public APIs (no Accessibility or private CGS symbols).
public enum WindowEnumerator {
    /// Minimum window edge, in points, to be considered a selectable target.
    private static let minimumWindowEdge: CGFloat = 24

    /// Returns front-to-back on-screen windows, excluding menu bar / Dock / status layers,
    /// nearly transparent windows, tiny windows, and any windows owned by `excludedPIDs`
    /// or matching `excludedWindowNumbers` (e.g. our own overlay windows).
    public static func onscreenWindows(
        excludedPIDs: Set<pid_t> = [],
        excludedWindowNumbers: Set<CGWindowID> = []
    ) -> [WindowDescriptor] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let primaryHeight = primaryScreenHeight()

        return rawWindows.compactMap { info -> WindowDescriptor? in
            // Only the normal window layer (0) is selectable; menu bar, Dock, status
            // items and other chrome live on non-zero layers.
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else {
                return nil
            }

            let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1
            guard alpha > 0.05 else {
                return nil
            }

            guard
                let windowNumber = info[kCGWindowNumber as String] as? CGWindowID,
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else {
                return nil
            }

            guard !excludedPIDs.contains(ownerPID), !excludedWindowNumbers.contains(windowNumber) else {
                return nil
            }

            guard cgRect.width >= minimumWindowEdge, cgRect.height >= minimumWindowEdge else {
                return nil
            }

            let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? ""
            let title = (info[kCGWindowName as String] as? String) ?? ""

            return WindowDescriptor(
                windowID: windowNumber,
                ownerPID: ownerPID,
                ownerName: ownerName,
                title: title,
                frame: appKitFrame(fromQuartz: cgRect, primaryHeight: primaryHeight)
            )
        }
    }

    /// Returns the front-most window whose frame contains `point` (AppKit global coordinates).
    public static func window(
        at point: CGPoint,
        excludedPIDs: Set<pid_t> = [],
        excludedWindowNumbers: Set<CGWindowID> = []
    ) -> WindowDescriptor? {
        // `CGWindowListCopyWindowInfo` returns windows in front-to-back order, so the first
        // hit is the top-most window under the cursor.
        onscreenWindows(excludedPIDs: excludedPIDs, excludedWindowNumbers: excludedWindowNumbers)
            .first { $0.frame.contains(point) }
    }

    /// Converts a Quartz rect (top-left origin, y-down) to an AppKit global rect
    /// (bottom-left origin, y-up) by flipping about the primary display height.
    static func appKitFrame(fromQuartz rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// Height of the primary display (the screen whose origin is at zero), used for the
    /// Quartz-to-AppKit coordinate flip.
    private static func primaryScreenHeight() -> CGFloat {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        return primary?.frame.height ?? NSScreen.screens.first?.frame.height ?? 0
    }
}
