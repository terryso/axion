import CoreGraphics

extension InputSimulationService {

    // MARK: - Keyboard Operations

    func typeText(_ text: String) throws {
        let source = CGEventSource(stateID: .hidSystemState)

        for char in text {
            let charStr = String(char)
            let utf16 = Array(charStr.utf16)

            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: true
            )
            keyDown?.keyboardSetUnicodeString(
                stringLength: utf16.count,
                unicodeString: utf16
            )
            keyDown?.post(tap: .cghidEventTap)

            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: false
            )
            keyUp?.keyboardSetUnicodeString(
                stringLength: utf16.count,
                unicodeString: utf16
            )
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    func pressKey(_ key: String) throws {
        guard let keyCode = Self.keyMap[key.lowercased()] else {
            throw InputSimulationError.invalidKeyName(key)
        }

        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: true
        )
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: false
        )
        keyUp?.post(tap: .cghidEventTap)
    }

    func hotkey(_ keys: String) throws {
        let parsed = try parseHotkey(keys)
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: parsed.keyCode,
            keyDown: true
        )
        keyDown?.flags = parsed.flags
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: parsed.keyCode,
            keyDown: false
        )
        // Release modifiers on key-up so subsequent events don't see stale Cmd/Shift
        keyUp?.flags = []
        keyUp?.post(tap: .cghidEventTap)

        // Give the UI time to respond to the hotkey (dialogs, menus, etc.)
        usleep(500_000) // 500ms
    }
}
