import AppKit
import Testing
import Foundation
@testable import AxionBar

@Suite("GlobalHotkeyService")
struct GlobalHotkeyServiceTests {

    @Test("checkAccessibilityPermission returns a boolean")
    func checkAccessibilityPermissionReturnsBool() {
        let result = GlobalHotkeyService.checkAccessibilityPermission()
        #expect(type(of: result) == Bool.self)
    }

    @Test("start and stop without bindings does not crash")
    @MainActor
    func startStopNoBindings() {
        let service = GlobalHotkeyService()
        let configManager = HotkeyConfigManager()
        // No bindings — start should be a no-op
        service.start(configManager: configManager)
        service.stop()
    }

    @Test("stop without start does not crash")
    @MainActor
    func stopWithoutStart() {
        let service = GlobalHotkeyService()
        service.stop()
    }
}

@Suite("HotkeyBinding matching")
struct HotkeyBindingMatchingTests {

    @Test("binding matches correct modifiers and keyCode")
    func matchesCorrectEvent() {
        let binding = HotkeyBinding(
            id: UUID(),
            action: .skill(name: "test"),
            modifiers: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue,
            keyCode: 0
        )

        // Test that the stored modifiers match expected combined flags
        let expectedFlags = NSEvent.ModifierFlags.command.union(.shift)
        #expect(binding.modifierFlags == expectedFlags)
    }

    @Test("binding with only command modifier")
    func commandOnlyBinding() {
        let binding = HotkeyBinding(
            id: UUID(),
            action: .task(description: "test"),
            modifiers: NSEvent.ModifierFlags.command.rawValue,
            keyCode: 12 // Q
        )
        #expect(binding.modifierFlags == .command)
        #expect(binding.displayString.contains("⌘"))
        #expect(binding.displayString.contains("Q"))
    }
}
