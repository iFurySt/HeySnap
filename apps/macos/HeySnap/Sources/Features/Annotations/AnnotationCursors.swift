import AppKit

extension NSCursor {
    // A four-way move cursor. Built from an SF Symbol so we avoid the private
    // `_moveCursor` selector (which crashed), falling back to openHand. The
    // backing is a slightly larger rotated square behind the original glyph.
    static let editorMove: NSCursor = {
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right", accessibilityDescription: "Move")?
            .withSymbolConfiguration(config) else {
            return .openHand
        }
        let size = NSSize(width: 30, height: 30)
        let image = NSImage(size: size)
        image.lockFocus()

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let backingSide: CGFloat = 23
        let backing = NSBezierPath()
        backing.move(to: CGPoint(x: center.x, y: center.y + backingSide / 2))
        backing.line(to: CGPoint(x: center.x + backingSide / 2, y: center.y))
        backing.line(to: CGPoint(x: center.x, y: center.y - backingSide / 2))
        backing.line(to: CGPoint(x: center.x - backingSide / 2, y: center.y))
        backing.close()
        NSColor.white.withAlphaComponent(0.96).setFill()
        backing.fill()
        NSColor.black.withAlphaComponent(0.18).setStroke()
        backing.lineWidth = 1
        backing.stroke()

        let symbolRect = NSRect(
            x: (size.width - symbol.size.width) / 2,
            y: (size.height - symbol.size.height) / 2,
            width: symbol.size.width,
            height: symbol.size.height
        )
        symbol.draw(in: symbolRect)
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: center.x, y: center.y))
    }()
}

