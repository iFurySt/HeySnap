import Carbon
import Foundation

@MainActor
final class HotKeyService: ObservableObject {
    @Published private(set) var registeredShortcuts: [HotKeyAction: HotKeyShortcut] = [:]
    @Published private(set) var registrationError: String?

    private let handler: (HotKeyAction) -> Void
    private var hotKeyRefs: [HotKeyAction: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let signature = OSType(UInt32(ascii: "HSNP"))

    init(handler: @escaping (HotKeyAction) -> Void) {
        self.handler = handler
        installEventHandler()
    }

    deinit {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// Applies the full shortcut map: actions missing from the dictionary are unregistered.
    func register(shortcuts: [HotKeyAction: HotKeyShortcut]) throws {
        registrationError = nil
        for action in HotKeyAction.allCases {
            if let shortcut = shortcuts[action] {
                try register(shortcut: shortcut, action: action)
            } else {
                unregister(action: action)
            }
        }
    }

    private func unregister(action: HotKeyAction) {
        if let hotKeyRef = hotKeyRefs[action] {
            UnregisterEventHotKey(hotKeyRef)
            hotKeyRefs[action] = nil
        }
        registeredShortcuts[action] = nil
    }

    private func register(shortcut: HotKeyShortcut, action: HotKeyAction) throws {
        unregister(action: action)

        let id = EventHotKeyID(signature: signature, id: action.rawValue)
        var newHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &newHotKeyRef
        )

        guard status == noErr, let newHotKeyRef else {
            registrationError = HotKeyError.registrationFailed(status).localizedDescription
            AppLogger.error("RegisterEventHotKey failed for \(action.displayName) with status \(status).")
            throw HotKeyError.registrationFailed(status)
        }

        hotKeyRefs[action] = newHotKeyRef
        registeredShortcuts[action] = shortcut
        registrationError = nil
        AppLogger.info("RegisterEventHotKey succeeded for \(action.displayName): \(shortcut.displayName).")
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else {
                    return status
                }

                let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
                if hotKeyID.signature == service.signature,
                   let action = HotKeyAction(rawValue: hotKeyID.id) {
                    AppLogger.info("Carbon hotkey event received for \(action.displayName).")
                    Task { @MainActor in
                        service.handler(action)
                    }
                }
                return noErr
            },
            1,
            &eventType,
            unmanagedSelf,
            &eventHandlerRef
        )

        if status != noErr {
            registrationError = HotKeyError.eventHandlerFailed(status).localizedDescription
            AppLogger.error("InstallEventHandler failed with status \(status).")
        } else {
            AppLogger.info("InstallEventHandler succeeded.")
        }
    }
}

enum HotKeyAction: UInt32, CaseIterable, Hashable {
    case screen = 1
    case area = 2

    var displayName: String {
        switch self {
        case .screen:
            return "Screen Capture"
        case .area:
            return "Area Capture"
        }
    }
}

enum HotKeyError: LocalizedError {
    case registrationFailed(OSStatus)
    case eventHandlerFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "RegisterEventHotKey failed with status \(status)."
        case .eventHandlerFailed(let status):
            return "InstallEventHandler failed with status \(status)."
        }
    }
}

private extension UInt32 {
    init(ascii string: String) {
        var result: UInt32 = 0
        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + UInt32(scalar.value)
        }
        self = result
    }
}
