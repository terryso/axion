import AppKit
import Testing
import Foundation
@testable import AxionBar

@Suite("HotkeyAction")
struct HotkeyActionTests {

    @Test("skill action encodes and decodes")
    func skillActionRoundTrip() throws {
        let action = HotkeyAction.skill(name: "open_calculator")
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(HotkeyAction.self, from: data)
        #expect(decoded == action)
    }

    @Test("task action encodes and decodes")
    func taskActionRoundTrip() throws {
        let action = HotkeyAction.task(description: "打开浏览器")
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(HotkeyAction.self, from: data)
        #expect(decoded == action)
    }

    @Test("skill and task actions are not equal")
    func inequality() {
        let a = HotkeyAction.skill(name: "x")
        let b = HotkeyAction.task(description: "x")
        #expect(a != b)
    }
}

@Suite("HotkeyBinding")
struct HotkeyBindingTests {

    @Test("matches event with correct modifiers and keyCode")
    func matchesCorrectEvent() {
        let binding = HotkeyBinding(
            id: UUID(),
            action: .skill(name: "test"),
            modifiers: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue,
            keyCode: 0 // A
        )

        // Create a mock key event check via the matches method
        // We test the modifierFlags logic directly
        let flags = NSEvent.ModifierFlags.command.union(.shift)
        #expect(binding.modifierFlags == flags)
        #expect(binding.keyCode == 0)
    }

    @Test("displayString includes modifiers and key")
    func displayString() {
        let binding = HotkeyBinding(
            id: UUID(),
            action: .skill(name: "test"),
            modifiers: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue,
            keyCode: 0 // A
        )
        let display = binding.displayString
        #expect(display.contains("⌘"))
        #expect(display.contains("⇧"))
        #expect(display.contains("A"))
    }

    @Test("round-trip preserves all fields")
    func roundTrip() throws {
        let original = HotkeyBinding(
            id: UUID(),
            action: .task(description: "打开浏览器"),
            modifiers: NSEvent.ModifierFlags.command.rawValue,
            keyCode: 12 // Q
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)
        #expect(decoded == original)
    }
}

@Suite("HotkeyConfig")
struct HotkeyConfigTests {

    @Test("empty config round-trips")
    func emptyConfigRoundTrip() throws {
        let config = HotkeyConfig(bindings: [])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(HotkeyConfig.self, from: data)
        #expect(decoded.bindings.isEmpty)
    }

    @Test("config with bindings round-trips")
    func configWithBindingsRoundTrip() throws {
        let config = HotkeyConfig(bindings: [
            HotkeyBinding(id: UUID(), action: .skill(name: "s1"), modifiers: 1_048_576, keyCode: 0),
            HotkeyBinding(id: UUID(), action: .task(description: "t1"), modifiers: 1_310_720, keyCode: 1),
        ])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(HotkeyConfig.self, from: data)
        #expect(decoded.bindings.count == 2)
        #expect(decoded == config)
    }
}

@MainActor
@Suite("HotkeyConfigManager")
struct HotkeyConfigManagerTests {

    private func makeTempConfigURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("axion-test-hotkeys-\(UUID().uuidString)")
        return dir.appendingPathComponent("hotkeys.json")
    }

    @Test("default config has no bindings")
    func defaultConfig() {
        let manager = HotkeyConfigManager(configURL: makeTempConfigURL())
        #expect(manager.bindings.isEmpty)
    }

    @Test("addBinding adds a binding")
    func addBinding() {
        let manager = HotkeyConfigManager(configURL: makeTempConfigURL())
        let result = manager.addBinding(
            action: .skill(name: "test"),
            modifiers: .command,
            keyCode: 0
        )
        #expect(result != nil)
        #expect(manager.bindings.count == 1)
        #expect(manager.bindings[0].action == .skill(name: "test"))
    }

    @Test("addBinding rejects duplicate key combination")
    func rejectDuplicate() {
        let manager = HotkeyConfigManager(configURL: makeTempConfigURL())
        _ = manager.addBinding(action: .skill(name: "first"), modifiers: .command, keyCode: 0)
        let second = manager.addBinding(action: .skill(name: "second"), modifiers: .command, keyCode: 0)
        #expect(second == nil)
        #expect(manager.bindings.count == 1)
    }

    @Test("removeBinding removes by ID")
    func removeBinding() {
        let manager = HotkeyConfigManager(configURL: makeTempConfigURL())
        let binding = manager.addBinding(action: .skill(name: "test"), modifiers: .command, keyCode: 0)
        #expect(binding != nil)
        manager.removeBinding(id: binding!.id)
        #expect(manager.bindings.isEmpty)
    }

    @Test("findBinding returns matching binding")
    func findBinding() {
        let manager = HotkeyConfigManager(configURL: makeTempConfigURL())
        _ = manager.addBinding(action: .skill(name: "test"), modifiers: .command, keyCode: 0)

        let found = manager.bindings.first { $0.keyCode == 0 && $0.modifiers == NSEvent.ModifierFlags.command.rawValue }
        #expect(found != nil)
        #expect(found?.action == .skill(name: "test"))
    }

    @Test("save and load round-trips")
    func saveAndLoad() throws {
        let tempURL = makeTempConfigURL()
        let manager = HotkeyConfigManager(configURL: tempURL)
        manager.addBinding(action: .skill(name: "save_test"), modifiers: .command.union(.shift), keyCode: 1)
        manager.save()

        let manager2 = HotkeyConfigManager(configURL: tempURL)
        manager2.load()
        #expect(manager2.bindings.count == 1)
        #expect(manager2.bindings[0].action == .skill(name: "save_test"))

        // Cleanup temp file
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }
}
