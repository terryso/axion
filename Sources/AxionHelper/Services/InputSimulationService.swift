import AppKit
import CoreGraphics
import Foundation

/// Errors thrown by `InputSimulationService`.
enum InputSimulationError: Error, LocalizedError {
    case coordinatesOutOfBounds(x: Int, y: Int)
    case invalidKeyName(String)
    case invalidHotkeyFormat(String)
    case invalidDirection(String)

    var errorDescription: String? {
        switch self {
        case .coordinatesOutOfBounds(let x, let y):
            return "Coordinates (\(x), \(y)) are outside screen bounds"
        case .invalidKeyName(let name):
            return "Unknown key: '\(name)'"
        case .invalidHotkeyFormat(let keys):
            return "Invalid hotkey format: '\(keys)'"
        case .invalidDirection(let dir):
            return "Invalid scroll direction: '\(dir)'"
        }
    }

    var errorCode: String {
        switch self {
        case .coordinatesOutOfBounds:
            return "coordinates_out_of_bounds"
        case .invalidKeyName:
            return "invalid_key_name"
        case .invalidHotkeyFormat:
            return "invalid_hotkey_format"
        case .invalidDirection:
            return "invalid_direction"
        }
    }

    var suggestion: String {
        switch self {
        case .coordinatesOutOfBounds:
            return "Use screen coordinates within the display bounds."
        case .invalidKeyName:
            return "Use standard key names: return, tab, escape, space, a-z, f1-f12, etc."
        case .invalidHotkeyFormat:
            return "Use format 'modifier+key' (e.g. 'cmd+c', 'cmd+shift+s'). At least one modifier required."
        case .invalidDirection:
            return "Use 'up', 'down', 'left', or 'right'."
        }
    }
}

/// Service responsible for simulating mouse and keyboard input using macOS CGEvent API.
struct InputSimulationService: InputSimulating {

    // MARK: - Key Name Mapping

    /// Key name to macOS virtual key code mapping.
    static let keyMap: [String: CGKeyCode] = [
        "return": 0x24,
        "enter": 0x24,
        "tab": 0x30,
        "space": 0x31,
        "escape": 0x35,
        "esc": 0x35,
        "delete": 0x33,
        "backspace": 0x33,
        "forwarddelete": 0x75,
        "home": 0x73,
        "end": 0x77,
        "pageup": 0x74,
        "pagedown": 0x79,
        "left": 0x7B,
        "right": 0x7C,
        "down": 0x7D,
        "up": 0x7E,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
        "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
        "=": 0x18, "-": 0x1B, "/": 0x2C, ".": 0x2F, ",": 0x2B,
        "[": 0x21, "]": 0x1E, "\\": 0x2A, ";": 0x29, "'": 0x27,
        "`": 0x32,
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
        "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
        "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
        "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
        "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10,
        "z": 0x06,
    ]

    func keyCodeForName(_ name: String) -> CGKeyCode? {
        Self.keyMap[name.lowercased()]
    }

    // MARK: - Hotkey Parsing

    func parseHotkey(_ keys: String) throws -> (flags: CGEventFlags, keyCode: CGKeyCode) {
        let parts = keys.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else {
            throw InputSimulationError.invalidHotkeyFormat(keys)
        }

        var flags: CGEventFlags = []
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "ctrl", "control":
                flags.insert(.maskControl)
            case "alt", "option":
                flags.insert(.maskAlternate)
            default:
                throw InputSimulationError.invalidHotkeyFormat(keys)
            }
        }

        let mainKey = parts.last!
        guard let keyCode = Self.keyMap[mainKey] else {
            throw InputSimulationError.invalidKeyName(mainKey)
        }
        return (flags, keyCode)
    }

    // MARK: - Scroll Direction

    func scrollValueForDirection(_ direction: String, amount: Int) throws -> Int {
        switch direction.lowercased() {
        case "up":
            return amount
        case "down":
            return -amount
        default:
            throw InputSimulationError.invalidDirection(direction)
        }
    }

    // MARK: - Coordinate Validation

    func validateCoordinates(x: Int, y: Int) throws {
        guard x >= 0, y >= 0 else {
            throw InputSimulationError.coordinatesOutOfBounds(x: x, y: y)
        }
        let bounds = CGDisplayBounds(CGMainDisplayID())
        guard CGFloat(x) <= bounds.width, CGFloat(y) <= bounds.height else {
            throw InputSimulationError.coordinatesOutOfBounds(x: x, y: y)
        }
    }

    // MARK: - InputSimulating Protocol — Mouse Operations

    func click(x: Int, y: Int) throws {
        try validateCoordinates(x: x, y: y)
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))

        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        downEvent?.post(tap: .cghidEventTap)

        let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        upEvent?.post(tap: .cghidEventTap)
    }

    func doubleClick(x: Int, y: Int) throws {
        try validateCoordinates(x: x, y: y)
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))

        // First click
        let down1 = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        down1?.setIntegerValueField(.mouseEventClickState, value: 1)
        down1?.post(tap: .cghidEventTap)

        let up1 = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        up1?.setIntegerValueField(.mouseEventClickState, value: 1)
        up1?.post(tap: .cghidEventTap)

        // Second click with clickState = 2
        let down2 = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        down2?.setIntegerValueField(.mouseEventClickState, value: 2)
        down2?.post(tap: .cghidEventTap)

        let up2 = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        up2?.setIntegerValueField(.mouseEventClickState, value: 2)
        up2?.post(tap: .cghidEventTap)
    }

    func rightClick(x: Int, y: Int) throws {
        try validateCoordinates(x: x, y: y)
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))

        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: .right
        )
        downEvent?.post(tap: .cghidEventTap)

        let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: .right
        )
        upEvent?.post(tap: .cghidEventTap)
    }

    func scroll(direction: String, amount: Int) throws {
        let event: CGEvent?
        switch direction.lowercased() {
        case "up":
            event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: Int32(amount),
                wheel2: 0,
                wheel3: 0
            )
        case "down":
            event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: Int32(-amount),
                wheel2: 0,
                wheel3: 0
            )
        case "left":
            event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: 0,
                wheel2: Int32(-amount),
                wheel3: 0
            )
        case "right":
            event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: 0,
                wheel2: Int32(amount),
                wheel3: 0
            )
        default:
            throw InputSimulationError.invalidDirection(direction)
        }
        event?.post(tap: .cghidEventTap)
    }

    func drag(fromX: Int, fromY: Int, toX: Int, toY: Int) throws {
        try validateCoordinates(x: fromX, y: fromY)
        try validateCoordinates(x: toX, y: toY)

        let start = CGPoint(x: CGFloat(fromX), y: CGFloat(fromY))
        let end = CGPoint(x: CGFloat(toX), y: CGFloat(toY))

        // Move to start position
        let moveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: start,
            mouseButton: .left
        )
        moveEvent?.post(tap: .cghidEventTap)

        // Mouse down at start
        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: start,
            mouseButton: .left
        )
        downEvent?.post(tap: .cghidEventTap)

        // Smooth drag with interpolated intermediate points
        let distance = hypot(end.x - start.x, end.y - start.y)
        let steps = max(10, Int(distance / 20))

        var prevX = start.x
        var prevY = start.y

        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t

            let dragEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: CGPoint(x: x, y: y),
                mouseButton: .left
            )
            dragEvent?.setIntegerValueField(.mouseEventDeltaX, value: Int64(x - prevX))
            dragEvent?.setIntegerValueField(.mouseEventDeltaY, value: Int64(y - prevY))
            dragEvent?.post(tap: .cghidEventTap)

            prevX = x
            prevY = y
        }

        // Mouse up at end
        let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: end,
            mouseButton: .left
        )
        upEvent?.post(tap: .cghidEventTap)
    }

    // MARK: - InputSimulating Protocol — Keyboard Operations

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
        keyUp?.flags = parsed.flags
        keyUp?.post(tap: .cghidEventTap)
    }
}
