import CoreGraphics
import Foundation

enum CaptureCoordinateConverter {
    static func screenCaptureRect(fromAppKitRect rect: CGRect, screenFrames: [CGRect]) -> CGRect {
        guard !rect.isNull,
              let screenFrame = dominantScreenFrame(for: rect, screenFrames: screenFrames)
        else {
            return rect
        }

        return CGRect(
            x: rect.minX,
            y: screenFrame.minY + screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func dominantScreenFrame(for rect: CGRect, screenFrames: [CGRect]) -> CGRect? {
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
