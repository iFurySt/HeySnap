import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderField: View {
    @Binding var shortcut: HotKeyShortcut?
    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                beginRecording()
            } label: {
                Text(displayText)
                    .font(.system(size: 13, weight: hasCommittedShortcut ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(hasCommittedShortcut ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 14)
                    .padding(.trailing, hasCommittedShortcut ? 28 : 14)
                    .frame(height: FieldMetrics.height)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            if hasCommittedShortcut {
                Button {
                    clearShortcut()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 7)
                .accessibilityLabel("Remove shortcut")
            }
        }
        .frame(width: FieldMetrics.width, height: FieldMetrics.height)
        .background(FieldPalette.background, in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    isRecording ? Color(nsColor: .keyboardFocusIndicatorColor) : FieldPalette.border,
                    lineWidth: isRecording ? 2.5 : FieldMetrics.hairline
                )
        }
        .animation(.easeInOut(duration: 0.12), value: isRecording)
        .onDisappear {
            stopRecording()
        }
    }

    private var hasCommittedShortcut: Bool {
        shortcut != nil && !isRecording
    }

    private var displayText: String {
        if isRecording {
            return "Press Shortcut"
        }
        return shortcut?.displayName ?? "Record Shortcut"
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stopRecording()
                return nil
            }

            if let captured = HotKeyShortcut(event: event) {
                shortcut = captured
                stopRecording()
            }
            return nil
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            stopRecording()
            return event
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        isRecording = false
    }

    private func clearShortcut() {
        stopRecording()
        shortcut = nil
    }
}

private enum FieldMetrics {
    static let width: CGFloat = 150
    static let height: CGFloat = 26
    static let hairline: CGFloat = 0.5
}

private enum FieldPalette {
    static let background = Color(nsColor: dynamic(light: 0xFFFFFF, dark: 0x24262A, lightAlpha: 0.86, darkAlpha: 0.94))
    static let border = Color(nsColor: dynamic(light: 0xD7D9DD, dark: 0x3B3E44))

    private static func dynamic(
        light: Int,
        dark: Int,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: isDark ? darkAlpha : lightAlpha
            )
        }
    }
}
