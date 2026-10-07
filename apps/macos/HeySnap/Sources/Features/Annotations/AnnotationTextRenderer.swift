import AppKit

enum AnnotationTextRenderer {
    static func font(size: CGFloat, scale: CGFloat = 1) -> NSFont {
        let points = max(8, size) * scale
        return NSFont(name: "PingFangSC-Regular", size: points) ?? NSFont.systemFont(ofSize: points, weight: .regular)
    }

    static func lineHeight(for font: NSFont) -> CGFloat { ceil(font.ascender - font.descender + font.leading) }

    static func paragraph() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }

    static func boxSize(for text: String, fontSize: CGFloat, scale: CGFloat = 1) -> CGSize {
        let font = font(size: fontSize, scale: scale)
        let measured = (text.isEmpty ? " " : text).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: paragraph()]).size
        return CGSize(width: max(96 * scale, ceil(measured.width) + 28 * scale), height: max(lineHeight(for: font), ceil(measured.height)) + 16 * scale)
    }

    static func fittedRect(from start: CGPoint, to end: CGPoint, text: String, fontSize: CGFloat, within bounds: CGRect, scale: CGFloat = 1) -> CGRect {
        let raw = AnnotationShapeGeometry.normalized(from: start, to: end)
        let minimum = boxSize(for: text, fontSize: fontSize, scale: scale)
        let dragged = raw.width >= 4 * scale || raw.height >= 4 * scale
        let origin = dragged ? raw.origin : start
        let width = min(max(dragged ? raw.width : minimum.width, minimum.width), bounds.width)
        let height = min(max(dragged ? raw.height : minimum.height, minimum.height), bounds.height)
        return CGRect(x: min(max(origin.x, bounds.minX), bounds.maxX - width), y: min(max(origin.y, bounds.minY), bounds.maxY - height), width: width, height: height)
    }

    static func autosizedRect(_ old: CGRect, text: String, fontSize: CGFloat, within bounds: CGRect, scale: CGFloat = 1) -> CGRect {
        let size = boxSize(for: text, fontSize: fontSize, scale: scale)
        let width = min(size.width, bounds.width), height = min(size.height, bounds.height)
        return CGRect(x: min(max(old.minX, bounds.minX), bounds.maxX - width), y: min(max(old.minY, bounds.minY), bounds.maxY - height), width: width, height: height)
    }

    static func style(filled: Bool, color: NSColor, fillColor: NSColor) -> (color: NSColor, fill: NSColor) {
        let base = fillColor.alphaComponent > 0 ? fillColor : color
        return filled ? (.white, base) : (base, .clear)
    }

    static func draw(_ text: String, in rect: CGRect, color: NSColor, fontSize: CGFloat, fillColor: NSColor = .clear, selected: Bool = false, scale: CGFloat = 1, magnification: CGFloat = 1) {
        if fillColor.alphaComponent > 0 {
            fillColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8 * scale, yRadius: 8 * scale).fill()
        }
        if selected {
            let gap = 4 / magnification
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -gap, dy: -gap), xRadius: 8 * scale + gap, yRadius: 8 * scale + gap)
            NSColor.controlAccentColor.setStroke()
            ring.lineWidth = 1.8 / magnification
            ring.stroke()
        }
        guard !text.isEmpty else { return }
        let font = font(size: fontSize, scale: scale)
        let height = boxSize(for: text, fontSize: fontSize, scale: scale).height - 16 * scale
        let content = CGRect(x: rect.minX + 14 * scale, y: rect.midY - height / 2, width: max(1, rect.width - 28 * scale), height: height)
        text.draw(in: content, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph()])
    }

    static func configure(_ editor: AnnotationInlineTextView, color: NSColor, fillColor: NSColor, fontSize: CGFloat, scale: CGFloat = 1, magnification: CGFloat = 1) {
        let font = font(size: fontSize, scale: scale)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph()]
        editor.font = font
        editor.alignment = .center
        editor.textColor = color
        editor.insertionPointColor = color
        editor.customCaretColor = color
        editor.typingAttributes = attributes
        editor.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: (editor.string as NSString).length))
        editor.textContainerInset = CGSize(width: 14 * scale, height: 8 * scale)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: max(editor.bounds.height, 1))
        editor.wantsLayer = true
        editor.layer?.cornerRadius = 8 * scale
        editor.layer?.borderWidth = 0
        editor.layer?.backgroundColor = fillColor.cgColor
        updateSelectionRing(editor, scale: scale, magnification: magnification)
    }

    static func updateSelectionRing(_ editor: AnnotationInlineTextView, scale: CGFloat = 1, magnification: CGFloat = 1) {
        let gap = 4 / magnification, width = 1.8 / magnification
        let frame = editor.bounds.insetBy(dx: -gap - width, dy: -gap - width)
        let ringRect = CGRect(x: width, y: width, width: max(1, frame.width - width * 2), height: max(1, frame.height - width * 2))
        editor.layer?.masksToBounds = false
        let ring = editor.selectionRingLayer
        ring.frame = frame
        ring.path = CGPath(roundedRect: ringRect, cornerWidth: 8 * scale + gap, cornerHeight: 8 * scale + gap, transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = NSColor.controlAccentColor.cgColor
        ring.lineWidth = width
        if ring.superlayer == nil { editor.layer?.addSublayer(ring) }
    }
}
