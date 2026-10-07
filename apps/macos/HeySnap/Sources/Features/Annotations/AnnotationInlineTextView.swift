import AppKit
import QuartzCore

final class AnnotationInlineTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onEditingLayoutChange: (() -> Void)?
    var forwardsBorderMouseEvents = false
    let selectionRingLayer = CAShapeLayer()
    var customCaretColor: NSColor = .labelColor {
        didSet { needsDisplay = true }
    }

    private var customCaretVisible = true
    private var customCaretTimer: Timer?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if forwardsBorderMouseEvents {
            let local = convert(point, from: superview)
            if !bounds.insetBy(dx: textContainerInset.width, dy: textContainerInset.height).contains(local) {
                return nil
            }
        }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard forwardsBorderMouseEvents else { return }
        let x = textContainerInset.width, y = textContainerInset.height
        for rect in [CGRect(x: 0, y: 0, width: bounds.width, height: y),
                     CGRect(x: 0, y: bounds.maxY - y, width: bounds.width, height: y),
                     CGRect(x: 0, y: y, width: x, height: max(0, bounds.height - 2 * y)),
                     CGRect(x: bounds.maxX - x, y: y, width: x, height: max(0, bounds.height - 2 * y))] {
            addCursorRect(rect, cursor: .editorMove)
        }
    }

    deinit {
        customCaretTimer?.invalidate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            customCaretTimer?.invalidate()
            customCaretTimer = nil
        } else if customCaretTimer == nil {
            customCaretTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.customCaretVisible.toggle()
                self.needsDisplay = true
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawCustomEmptyCaretIfNeeded()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onEditingLayoutChange?()
    }

    override func unmarkText() {
        super.unmarkText()
        onEditingLayoutChange?()
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        onEditingLayoutChange?()
    }

    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        onEditingLayoutChange?()
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(cancelOperation(_:)) {
            onCancel?()
            return
        }

        if selector == #selector(insertNewline(_:)) || selector == #selector(insertNewlineIgnoringFieldEditor(_:)) {
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            if flags.contains(.command) {
                onCommit?()
                return
            }
        }

        super.doCommand(by: selector)
    }

    private func drawCustomEmptyCaretIfNeeded() {
        guard string.isEmpty,
              selectedRange().length == 0,
              window?.firstResponder === self,
              customCaretVisible else {
            return
        }

        let font = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let caretWidth: CGFloat = 1.5
        let rect = CGRect(
            x: bounds.midX - caretWidth / 2,
            y: textContainerInset.height,
            width: caretWidth,
            height: lineHeight
        )
        customCaretColor.setFill()
        NSBezierPath(rect: rect).fill()
    }
}
