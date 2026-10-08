import AppKit

/// Small independent panels leave the scrolling content available to the target app.
@MainActor
final class ScrollingCaptureHUD {
    static let introduction = "请缓慢向上或向下滚动页面，或点击“自动滚动”，开始截图"
    let selection: CGRect
    let screen: CGRect
    let button: NSButton
    private let buttonWindow: NSPanel
    private let noticeWindow: NSPanel
    private let previewWindow: NSPanel
    private let noticeView = ScrollingNoticeView()
    private let previewView = NSImageView()
    private var noticeTask: Task<Void, Never>?
    private let toggle: () -> Void

    init(selection: CGRect, toggle: @escaping () -> Void) {
        self.selection = selection
        screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: selection.midX, y: selection.midY)) }?.frame
            ?? NSScreen.main!.frame
        self.toggle = toggle
        button = ScrollingAutoScrollButton(title: "自动滚动", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.imagePosition = .imageLeading
        buttonWindow = Self.panel(interactive: true)
        noticeWindow = Self.panel(interactive: false)
        previewWindow = Self.panel(interactive: false)
        buttonWindow.contentView = button
        buttonWindow.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        noticeWindow.level = buttonWindow.level
        noticeWindow.contentView = noticeView
        previewWindow.contentView = previewView
        previewView.imageScaling = .scaleProportionallyUpOrDown
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.white.cgColor
        button.target = self
        button.action = #selector(toggleAutomatic)
        buttonWindow.setFrame(Self.buttonFrame(selection: selection), display: false)
        updateAutomatic(false, enabled: true)
        buttonWindow.orderFrontRegardless()
    }

    static func buttonFrame(selection: CGRect) -> CGRect {
        CGRect(x: selection.midX - 58, y: selection.minY + 10, width: 116, height: 32)
    }

    /// Grow upward at a fixed width, then cap height and reduce width proportionally.
    static func previewFrame(selection: CGRect, screen: CGRect, imageSize: CGSize) -> CGRect {
        let margin: CGFloat = 12
        let bottom = min(max(selection.minY, screen.minY + margin), screen.maxY - margin - 1)
        let rightSpace = screen.maxX - margin - selection.maxX - margin
        let width = rightSpace >= 60 ? min(176, rightSpace) : min(176, screen.width - 2 * margin)
        let scale = min(width / max(1, imageSize.width), (screen.maxY - margin - bottom) / max(1, imageSize.height))
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let x = rightSpace >= 60 ? selection.maxX + margin : screen.maxX - margin - size.width
        return CGRect(x: x, y: bottom, width: size.width, height: size.height)
    }

    func updateAutomatic(_ automatic: Bool, enabled: Bool) {
        button.title = automatic ? "停止滚动" : "自动滚动"
        button.image = NSImage(systemSymbolName: automatic ? "pause.fill" : "arrow.down.circle.fill", accessibilityDescription: button.title)
        button.isEnabled = enabled
        button.needsDisplay = true
    }

    func updatePreview(_ image: CGImage) {
        previewView.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        previewWindow.setFrame(Self.previewFrame(selection: selection, screen: screen,
            imageSize: CGSize(width: image.width, height: image.height)), display: false)
        previewWindow.orderFrontRegardless()
    }

    func showNotice(_ message: String) {
        noticeTask?.cancel()
        noticeView.message = message
        let textSize = (message as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium)])
        let size = CGSize(width: min(textSize.width + 28, screen.width - 24), height: 42)
        let x = min(max(selection.midX - size.width / 2, screen.minX + 12), screen.maxX - size.width - 12)
        noticeWindow.setFrame(CGRect(x: x, y: selection.midY - size.height / 2, width: size.width, height: size.height), display: false)
        noticeView.needsDisplay = true
        noticeWindow.orderFrontRegardless()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.noticeWindow.orderOut(nil)
        }
    }

    func close() {
        noticeTask?.cancel()
        noticeTask = nil
        for window in [buttonWindow, noticeWindow, previewWindow] { window.orderOut(nil) }
    }

    @objc private func toggleAutomatic() { toggle() }

    private static func panel(interactive: Bool) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = !interactive
        panel.isReleasedWhenClosed = false
        return panel
    }
}

@MainActor
private final class ScrollingNoticeView: NSView {
    var message = ""
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (message as NSString).draw(in: bounds.insetBy(dx: 12, dy: 11), withAttributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white, .paragraphStyle: paragraph
        ])
    }
}

@MainActor
private final class ScrollingAutoScrollButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.white.setFill()
        background.fill()
        NSColor(white: 0.8, alpha: 1).setStroke()
        background.lineWidth = 1
        background.stroke()
        let color = NSColor(white: 0.18, alpha: isEnabled ? 1 : 0.45)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: color]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        let left = (bounds.width - size.width - 21) / 2
        if let image {
            let tinted = NSImage(size: CGSize(width: 14, height: 14))
            tinted.lockFocus()
            image.draw(in: CGRect(x: 0, y: 0, width: 14, height: 14))
            color.setFill()
            CGRect(x: 0, y: 0, width: 14, height: 14).fill(using: .sourceIn)
            tinted.unlockFocus()
            tinted.draw(in: CGRect(x: left, y: bounds.midY - 7, width: 14, height: 14))
        }
        text.draw(at: CGPoint(x: left + 21, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
}
