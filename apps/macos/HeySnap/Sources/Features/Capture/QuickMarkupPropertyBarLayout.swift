import AppKit

struct QuickMarkupPropertyBarLayout {
    let sizeCount: Int

    var size: CGSize {
        CGSize(width: 198 + CGFloat(sizeCount) * 32 - 4 + 8, height: 42)
    }

    func itemRect(at index: Int, in bar: CGRect) -> CGRect {
        CGRect(x: bar.minX + 198 + CGFloat(index) * 32, y: bar.minY + 6, width: 28, height: bar.height - 12)
    }

    static func textControls(in bar: CGRect) -> CGRect {
        CGRect(x: bar.minX, y: bar.maxY - 42, width: bar.width, height: 42)
    }

    static func textStyleRect(filled: Bool, in bar: CGRect) -> CGRect {
        CGRect(x: bar.minX + (filled ? 94 : 10), y: bar.minY + 6, width: 76, height: 26)
    }

    static func textStyle(at point: CGPoint, in bar: CGRect) -> Bool? {
        if textStyleRect(filled: false, in: bar).contains(point) { return false }
        if textStyleRect(filled: true, in: bar).contains(point) { return true }
        return nil
    }

    func sizeIndex(at point: CGPoint, in bar: CGRect) -> Int? {
        (0..<sizeCount).first { itemRect(at: $0, in: bar).contains(point) }
    }
}

enum QuickMarkupPropertyBarIcons {
    static func colorCheckmark(centeredAt center: CGPoint) -> NSBezierPath {
        let check = NSBezierPath()
        check.move(to: CGPoint(x: center.x - 3.3, y: center.y))
        check.line(to: CGPoint(x: center.x - 0.9, y: center.y - 2.4))
        check.line(to: CGPoint(x: center.x + 3.3, y: center.y + 2.4))
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.lineWidth = 1.5
        return check
    }
}
