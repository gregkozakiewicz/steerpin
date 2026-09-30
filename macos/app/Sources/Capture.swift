import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Global hotkeys through the Carbon hotkey API, which needs no permission.
final class HotKeys {
    private static var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            HotKeys.actions[id.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Returns false if another app already owns the shortcut.
    func register(id: UInt32, keyCode: UInt32, action: @escaping () -> Void) -> Bool {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5354_504E), id: id) // "STPN"
        let status = RegisterEventHotKey(keyCode, UInt32(optionKey | shiftKey), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs.append(ref)
        HotKeys.actions[id] = action
        return true
    }
}

enum Selection {
    static var hasAccess: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Accessibility settings.
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Copies the selection with ⌘C, reads it, then puts the user's clipboard back as it was.
    static func copy(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let saved: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        let before = pasteboard.changeCount
        pressCommandC()

        let deadline = Date().addingTimeInterval(0.6)
        func poll() {
            if pasteboard.changeCount != before || Date() > deadline {
                let text = pasteboard.changeCount != before ? pasteboard.string(forType: .string) : nil
                pasteboard.clearContents()
                if !saved.isEmpty { pasteboard.writeObjects(saved) }
                completion(text)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: poll)
            }
        }
        poll()
    }

    private static func pressCommandC() {
        let source = CGEventSource(stateID: .privateState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: keyDown)
            event?.flags = .maskCommand // overrides the ⌥⇧ the user is still holding
            event?.post(tap: .cghidEventTap)
        }
    }
}
