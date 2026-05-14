import AppKit
import Foundation

// MARK: - HotkeyAction

enum HotkeyAction: Codable, Equatable, Sendable {
    case skill(name: String)
    case task(description: String)
}

// MARK: - HotkeyBinding

struct HotkeyBinding: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let action: HotkeyAction
    let modifiers: UInt
    let keyCode: UInt16

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    var displayString: String {
        var parts: [String] = []
        let flags = modifierFlags
        if flags.contains(.control) { parts.append("^") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    func matches(event: NSEvent) -> Bool {
        let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return eventModifiers == modifierFlags && event.keyCode == keyCode
    }

    private func keyCodeToString(_ code: UInt16) -> String {
        // macOS virtual key codes (kVK_* constants from Events.h)
        switch code {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "5"
        case 23: return "6"
        case 24: return "7"
        case 25: return "8"
        case 26: return "9"
        case 27: return "0"
        case 28: return "-"
        case 29: return "="
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "'"
        case 35: return "\\"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "K"
        case 40: return ";"
        case 41: return "'"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Esc"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "PgDn"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key\(code)"
        }
    }
}

// MARK: - HotkeyConfig

struct HotkeyConfig: Codable, Equatable, Sendable {
    var bindings: [HotkeyBinding]
}

// MARK: - HotkeyConfigManager

@MainActor
final class HotkeyConfigManager {
    private let configURL: URL
    private var config: HotkeyConfig

    var bindings: [HotkeyBinding] {
        config.bindings
    }

    init(configURL: URL? = nil) {
        if let configURL {
            self.configURL = configURL
        } else {
            let axionDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".axion")
            self.configURL = axionDir.appendingPathComponent("hotkeys.json")
        }
        self.config = HotkeyConfig(bindings: [])
    }

    func load() {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            config = HotkeyConfig(bindings: [])
            return
        }

        guard let data = try? Data(contentsOf: configURL) else {
            config = HotkeyConfig(bindings: [])
            return
        }

        do {
            config = try JSONDecoder().decode(HotkeyConfig.self, from: data)
        } catch {
            config = HotkeyConfig(bindings: [])
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(config)
            let dir = configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: configURL)
        } catch {
            // Non-fatal: config save failure shouldn't crash the app
        }
    }

    @discardableResult
    func addBinding(action: HotkeyAction, modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> HotkeyBinding? {
        // Check for conflict
        let newModifiers = modifiers.rawValue
        if config.bindings.contains(where: { $0.modifiers == newModifiers && $0.keyCode == keyCode }) {
            return nil
        }

        let binding = HotkeyBinding(
            id: UUID(),
            action: action,
            modifiers: newModifiers,
            keyCode: keyCode
        )
        config.bindings.append(binding)
        save()
        return binding
    }

    func removeBinding(id: UUID) {
        config.bindings.removeAll { $0.id == id }
        save()
    }

    func findBinding(event: NSEvent) -> HotkeyBinding? {
        config.bindings.first { $0.matches(event: event) }
    }
}
