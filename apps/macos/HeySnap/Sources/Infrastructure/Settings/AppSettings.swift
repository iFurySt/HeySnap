import AppKit
import Carbon
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var saveDirectoryPath: String {
        didSet {
            userDefaults.set(saveDirectoryPath, forKey: Keys.saveDirectoryPath)
        }
    }

    @Published var saveFormatMode: ScreenshotSaveFormatMode {
        didSet {
            userDefaults.set(saveFormatMode.rawValue, forKey: Keys.saveFormatMode)
        }
    }

    @Published var automaticSaveFormats: Set<ScreenshotOutputFormat> {
        didSet {
            if automaticSaveFormats.isEmpty {
                automaticSaveFormats = oldValue.isEmpty ? ScreenshotSaveFormatPreference.defaultAutomaticFormats : oldValue
                return
            }

            userDefaults.set(
                automaticSaveFormats.map(\.rawValue).sorted(),
                forKey: Keys.automaticSaveFormats
            )
        }
    }

    @Published var windowScreenshotBackground: WindowScreenshotBackground {
        didSet {
            userDefaults.set(windowScreenshotBackground.rawValue, forKey: Keys.windowScreenshotBackground)
        }
    }

    @Published var resizeRetinaScreenshots: Bool {
        didSet {
            userDefaults.set(resizeRetinaScreenshots, forKey: Keys.resizeRetinaScreenshots)
        }
    }

    @Published var postCaptureAction: PostCaptureAction {
        didSet {
            userDefaults.set(postCaptureAction.rawValue, forKey: Keys.postCaptureAction)
        }
    }

    @Published var screenShortcut: HotKeyShortcut? {
        didSet {
            persist(screenShortcut, keyCodeKey: Keys.screenShortcutKeyCode, modifiersKey: Keys.screenShortcutModifiers)
            onShortcutsChange?()
        }
    }

    @Published var areaShortcut: HotKeyShortcut? {
        didSet {
            persist(areaShortcut, keyCodeKey: Keys.areaShortcutKeyCode, modifiersKey: Keys.areaShortcutModifiers)
            onShortcutsChange?()
        }
    }

    var onShortcutsChange: (() -> Void)?

    private static let disabledShortcutSentinel = -1
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let defaultDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        let savedPath = userDefaults.string(forKey: Keys.saveDirectoryPath)
        self.saveDirectoryPath = savedPath?.isEmpty == false ? savedPath! : defaultDirectory.path
        self.saveFormatMode = Self.storedSaveFormatMode(userDefaults: userDefaults)
        self.automaticSaveFormats = Self.storedAutomaticSaveFormats(userDefaults: userDefaults)
        self.windowScreenshotBackground = Self.storedWindowScreenshotBackground(userDefaults: userDefaults)
        self.resizeRetinaScreenshots = userDefaults.bool(forKey: Keys.resizeRetinaScreenshots)
        self.postCaptureAction = Self.storedPostCaptureAction(userDefaults: userDefaults)

        self.screenShortcut = Self.shortcut(
            keyCodeKey: Keys.screenShortcutKeyCode,
            modifiersKey: Keys.screenShortcutModifiers,
            defaultShortcut: .defaultScreen,
            userDefaults: userDefaults
        )
        self.areaShortcut = Self.shortcut(
            keyCodeKey: Keys.areaShortcutKeyCode,
            modifiersKey: Keys.areaShortcutModifiers,
            defaultShortcut: .defaultArea,
            userDefaults: userDefaults
        )
    }

    var saveDirectoryURL: URL {
        URL(fileURLWithPath: (saveDirectoryPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    var saveFormatPreference: ScreenshotSaveFormatPreference {
        ScreenshotSaveFormatPreference(
            mode: saveFormatMode,
            automaticFormats: automaticSaveFormats
        )
    }

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Save Location"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveDirectoryURL

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        saveDirectoryPath = url.path
    }

    func revealSaveDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([saveDirectoryURL])
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private enum Keys {
        static let saveDirectoryPath = "saveDirectoryPath"
        static let saveFormatMode = "saveFormatMode"
        static let automaticSaveFormats = "automaticSaveFormats"
        static let windowScreenshotBackground = "windowScreenshotBackground"
        static let resizeRetinaScreenshots = "resizeRetinaScreenshots"
        static let postCaptureAction = "postCaptureAction"
        static let screenShortcutKeyCode = "screenShortcutKeyCode"
        static let screenShortcutModifiers = "screenShortcutModifiers"
        static let areaShortcutKeyCode = "areaShortcutKeyCode"
        static let areaShortcutModifiers = "areaShortcutModifiers"
    }

    private func persist(_ shortcut: HotKeyShortcut?, keyCodeKey: String, modifiersKey: String) {
        if let shortcut {
            userDefaults.set(Int(shortcut.keyCode), forKey: keyCodeKey)
            userDefaults.set(Int(shortcut.modifiers), forKey: modifiersKey)
        } else {
            userDefaults.set(Self.disabledShortcutSentinel, forKey: keyCodeKey)
            userDefaults.removeObject(forKey: modifiersKey)
        }
    }

    private static func shortcut(
        keyCodeKey: String,
        modifiersKey: String,
        defaultShortcut: HotKeyShortcut,
        userDefaults: UserDefaults
    ) -> HotKeyShortcut? {
        guard userDefaults.object(forKey: keyCodeKey) != nil else {
            return defaultShortcut
        }

        let savedKeyCode = userDefaults.integer(forKey: keyCodeKey)
        guard savedKeyCode != disabledShortcutSentinel else {
            return nil
        }

        let savedModifiers = userDefaults.object(forKey: modifiersKey) == nil
            ? defaultShortcut.modifiers
            : UInt32(userDefaults.integer(forKey: modifiersKey))
        return HotKeyShortcut(keyCode: UInt32(savedKeyCode), modifiers: savedModifiers)
    }

    private static func storedSaveFormatMode(userDefaults: UserDefaults) -> ScreenshotSaveFormatMode {
        guard
            let rawValue = userDefaults.string(forKey: Keys.saveFormatMode),
            let mode = ScreenshotSaveFormatMode(rawValue: rawValue)
        else {
            return ScreenshotSaveFormatPreference.default.mode
        }

        return mode
    }

    private static func storedAutomaticSaveFormats(userDefaults: UserDefaults) -> Set<ScreenshotOutputFormat> {
        guard let rawValues = userDefaults.stringArray(forKey: Keys.automaticSaveFormats) else {
            return ScreenshotSaveFormatPreference.defaultAutomaticFormats
        }

        let formats = Set(rawValues.compactMap(ScreenshotOutputFormat.init(rawValue:)))
        return formats.isEmpty ? ScreenshotSaveFormatPreference.defaultAutomaticFormats : formats
    }

    private static func storedWindowScreenshotBackground(userDefaults: UserDefaults) -> WindowScreenshotBackground {
        if userDefaults.string(forKey: Keys.windowScreenshotBackground) == "trimShadow" {
            return .shadow
        }

        guard
            let rawValue = userDefaults.string(forKey: Keys.windowScreenshotBackground),
            let background = WindowScreenshotBackground(rawValue: rawValue)
        else {
            return .transparent
        }

        return background
    }

    private static func storedPostCaptureAction(userDefaults: UserDefaults) -> PostCaptureAction {
        guard
            let rawValue = userDefaults.string(forKey: Keys.postCaptureAction),
            let action = PostCaptureAction(rawValue: rawValue)
        else {
            return .openEditor
        }

        return action
    }
}

enum PostCaptureAction: String, CaseIterable, Identifiable {
    case saveToLocation
    case quickMarkup
    case openEditor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .saveToLocation:
            return "Save to location"
        case .quickMarkup:
            return "Show quick markup bar"
        case .openEditor:
            return "Open editor"
        }
    }
}

struct HotKeyShortcut: Equatable {
    static let defaultScreen = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey | shiftKey))
    static let defaultArea = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey | shiftKey))

    let keyCode: UInt32
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Builds a shortcut from a key-down event captured by the recorder field.
    /// Requires at least one non-shift modifier so plain typing can never become a hotkey.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }

        guard modifiers & ~UInt32(shiftKey) != 0 else {
            return nil
        }

        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    var displayName: String {
        let symbols = modifierDisplayName
        let key = KeyCodeFormatter.displayName(for: keyCode)
        return "\(symbols)\(key)"
    }

    private var modifierDisplayName: String {
        var pieces: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { pieces.append("⌘") }
        if modifiers & UInt32(optionKey) != 0 { pieces.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { pieces.append("⌃") }
        if modifiers & UInt32(shiftKey) != 0 { pieces.append("⇧") }
        return pieces.joined()
    }
}

enum KeyCodeFormatter {
    static func displayName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Esc"
        default: return "Key \(keyCode)"
        }
    }
}
