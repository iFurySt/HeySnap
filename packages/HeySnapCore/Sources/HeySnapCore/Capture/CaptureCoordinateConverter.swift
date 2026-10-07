import CoreGraphics
import Foundation

enum CaptureCoordinateConverter {
    static func screenCaptureRect(fromAppKitRect rect: CGRect, screenFrames: [CGRect]) -> CGRect {
        guard !rect.isNull,
              let primaryScreenFrame = screenFrames.first
        else {
            return rect
        }

        return CGRect(
            x: rect.minX,
            // Display-space coordinates share the primary display's top-left origin.
            // Flipping around the selected display moves vertically arranged displays
            // to the wrong side of the primary display.
            y: primaryScreenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func dominantScreenFrame(for rect: CGRect, screenFrames: [CGRect]) -> CGRect? {
        screenFrames
            .map { screenFrame in
                (screenFrame, intersectionArea(rect.intersection(screenFrame)))
            }
            .filter { _, area in area > 0 }
            .max { lhs, rhs in lhs.1 < rhs.1 }?
            .0
    }

    private static func intersectionArea(_ rect: CGRect) -> CGFloat {
        guard !rect.isNull, rect.width > 0, rect.height > 0 else {
            return 0
        }
        return rect.width * rect.height
    }
}
