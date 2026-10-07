import AppKit

/// Factory defaults shared by Editor and quick markup.
enum AnnotationDefaults {
    static let colorHex = "#FF3B30"
    static let lineWidth: CGFloat = 5
    static let quickMarkupLineWidths: [CGFloat] = [2, lineWidth, 7]

    static var color: NSColor {
        let value = Int(colorHex.dropFirst(), radix: 16)!
        return NSColor(calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: 1)
    }
}
