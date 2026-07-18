import Foundation

public enum WindowScreenshotBackground: String, CaseIterable, Identifiable, Sendable {
    case transparent
    case shadow
    case solidColor
    case wallpaper

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .transparent:
            return "Transparent"
        case .shadow:
            return "Shadow"
        case .solidColor:
            return "Solid Color"
        case .wallpaper:
            return "Wallpaper"
        }
    }
}
