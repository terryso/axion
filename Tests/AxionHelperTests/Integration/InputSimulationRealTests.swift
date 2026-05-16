import CoreGraphics
import Testing
@testable import AxionHelper

@Suite("InputSimulation Real")
struct InputSimulationRealTests {

    private let service = InputSimulationService()

    // MARK: - keyCodeForName (all keys)

    @Test("keyMap has all expected keys")
    func keyMapHasAllExpectedKeys() {
        let expectedKeys = [
            "return", "enter", "tab", "space", "escape", "esc",
            "delete", "backspace", "forwarddelete", "home", "end",
            "pageup", "pagedown", "left", "right", "down", "up",
        ]
        for key in expectedKeys {
            #expect(service.keyCodeForName(key) != nil, "'\(key)' should be in keyMap")
        }
    }

    @Test("keyMap has all function keys")
    func keyMapHasAllFunctionKeys() {
        for i in 1...12 {
            let name = "f\(i)"
            #expect(service.keyCodeForName(name) != nil, "'\(name)' should be in keyMap")
        }
    }

    @Test("keyMap has all letters")
    func keyMapHasAllLetters() {
        for c in "abcdefghijklmnopqrstuvwxyz" {
            let name = String(c)
            #expect(service.keyCodeForName(name) != nil, "'\(name)' should be in keyMap")
        }
    }

    @Test("keyMap returns nil for unknown")
    func keyMapReturnsNilForUnknown() {
        #expect(service.keyCodeForName("notakey") == nil)
    }

    // MARK: - parseHotkey (all modifier combinations)

    @Test("parseHotkey cmd only")
    func parseHotkeyCmdOnly() throws {
        let result = try service.parseHotkey("cmd+a")
        #expect(result.flags.contains(.maskCommand))
        #expect(!result.flags.contains(.maskShift))
        #expect(!result.flags.contains(.maskControl))
        #expect(!result.flags.contains(.maskAlternate))
    }

    @Test("parseHotkey shift only")
    func parseHotkeyShiftOnly() throws {
        let result = try service.parseHotkey("shift+a")
        #expect(result.flags.contains(.maskShift))
    }

    @Test("parseHotkey ctrl only")
    func parseHotkeyCtrlOnly() throws {
        let result = try service.parseHotkey("ctrl+a")
        #expect(result.flags.contains(.maskControl))
    }

    @Test("parseHotkey alt only")
    func parseHotkeyAltOnly() throws {
        let result = try service.parseHotkey("alt+a")
        #expect(result.flags.contains(.maskAlternate))
    }

    @Test("parseHotkey all modifier aliases")
    func parseHotkeyAllModifierAliases() throws {
        let r1 = try service.parseHotkey("command+a")
        #expect(r1.flags.contains(.maskCommand))

        let r2 = try service.parseHotkey("control+a")
        #expect(r2.flags.contains(.maskControl))

        let r3 = try service.parseHotkey("option+a")
        #expect(r3.flags.contains(.maskAlternate))
    }

    @Test("parseHotkey throws for single key")
    func parseHotkeyThrowsForSingleKey() {
        do {
            _ = try service.parseHotkey("a")
            Issue.record("Should throw for single key")
        } catch {
            // Expected
        }
    }

    @Test("parseHotkey throws for unknown modifier")
    func parseHotkeyThrowsForUnknownModifier() {
        do {
            _ = try service.parseHotkey("super+a")
            Issue.record("Should throw for unknown modifier")
        } catch {
            // Expected
        }
    }

    @Test("parseHotkey throws for unknown main key")
    func parseHotkeyThrowsForUnknownMainKey() {
        do {
            _ = try service.parseHotkey("cmd+unknownkey")
            Issue.record("Should throw for unknown main key")
        } catch {
            // Expected
        }
    }

    // MARK: - scrollValueForDirection

    @Test("scrollValueForDirection up")
    func scrollValueForDirectionUp() throws {
        #expect(try service.scrollValueForDirection("up", amount: 5) == 5)
    }

    @Test("scrollValueForDirection down")
    func scrollValueForDirectionDown() throws {
        #expect(try service.scrollValueForDirection("down", amount: 3) == -3)
    }

    @Test("scrollValueForDirection invalid throws")
    func scrollValueForDirectionInvalid() {
        do {
            _ = try service.scrollValueForDirection("left", amount: 1)
            Issue.record("Should throw for invalid direction")
        } catch {
            // Expected
        }
    }

    @Test("scrollValueForDirection case insensitive")
    func scrollValueForDirectionCaseInsensitive() throws {
        #expect(try service.scrollValueForDirection("UP", amount: 2) == 2)
        #expect(try service.scrollValueForDirection("Down", amount: 4) == -4)
    }

    // MARK: - validateCoordinates

    @Test("validateCoordinates valid point")
    func validateCoordinatesValidPoint() throws {
        try service.validateCoordinates(x: 0, y: 0)
    }

    @Test("validateCoordinates negative X throws")
    func validateCoordinatesNegativeX() {
        do {
            try service.validateCoordinates(x: -1, y: 0)
            Issue.record("Should throw for negative X")
        } catch {
            // Expected
        }
    }

    @Test("validateCoordinates negative Y throws")
    func validateCoordinatesNegativeY() {
        do {
            try service.validateCoordinates(x: 0, y: -1)
            Issue.record("Should throw for negative Y")
        } catch {
            // Expected
        }
    }

    @Test("validateCoordinates too large throws")
    func validateCoordinatesTooLarge() {
        do {
            try service.validateCoordinates(x: 99999, y: 99999)
            Issue.record("Should throw for too large coordinates")
        } catch {
            // Expected
        }
    }

    @Test("validateCoordinates at screen edge")
    func validateCoordinatesAtScreenEdge() throws {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        try service.validateCoordinates(x: Int(bounds.width), y: Int(bounds.height))
    }

    // MARK: - scroll method (direct call, exercises switch statement)

    @Test("scroll up does not throw")
    func scrollUpDoesNotThrow() throws {
        try service.scroll(direction: "up", amount: 1)
    }

    @Test("scroll down does not throw")
    func scrollDownDoesNotThrow() throws {
        try service.scroll(direction: "down", amount: 1)
    }

    @Test("scroll left does not throw")
    func scrollLeftDoesNotThrow() throws {
        try service.scroll(direction: "left", amount: 1)
    }

    @Test("scroll right does not throw")
    func scrollRightDoesNotThrow() throws {
        try service.scroll(direction: "right", amount: 1)
    }

    @Test("scroll invalid direction throws")
    func scrollInvalidDirection() {
        do {
            try service.scroll(direction: "diagonal", amount: 1)
            Issue.record("Should throw for invalid direction")
        } catch {
            // Expected
        }
    }

    // MARK: - typeText (exercises the loop and CGEvent creation)

    @Test("typeText empty string does not throw")
    func typeTextEmptyString() throws {
        try service.typeText("")
    }

    @Test("typeText single char does not throw")
    func typeTextSingleChar() throws {
        try service.typeText("a")
    }

    @Test("typeText unicode does not throw")
    func typeTextUnicode() throws {
        try service.typeText("你好")
    }

    // MARK: - pressKey (exercises keyMap lookup and CGEvent)

    @Test("pressKey return does not throw")
    func pressKeyReturn() throws {
        try service.pressKey("return")
    }

    @Test("pressKey invalid key throws")
    func pressKeyInvalidKey() {
        do {
            try service.pressKey("nonexistent_key_xyz")
            Issue.record("Should throw for invalid key")
        } catch {
            // Expected
        }
    }

    // MARK: - hotkey (exercises parseHotkey + CGEvent)

    @Test("hotkey cmd+a does not throw")
    func hotkeyCmdA() throws {
        try service.hotkey("cmd+a")
    }

    @Test("hotkey invalid format throws")
    func hotkeyInvalidFormat() {
        do {
            try service.hotkey("a")
            Issue.record("Should throw for invalid format")
        } catch {
            // Expected
        }
    }

    // MARK: - click operations (exercise validateCoordinates + CGEvent)

    @Test("click valid coords does not throw")
    func clickValidCoords() throws {
        try service.click(x: 0, y: 0)
    }

    @Test("click negative coords throws")
    func clickNegativeCoords() {
        do {
            try service.click(x: -1, y: -1)
            Issue.record("Should throw for negative coords")
        } catch {
            // Expected
        }
    }

    @Test("doubleClick valid coords does not throw")
    func doubleClickValidCoords() throws {
        try service.doubleClick(x: 0, y: 0)
    }

    @Test("doubleClick negative coords throws")
    func doubleClickNegativeCoords() {
        do {
            try service.doubleClick(x: -1, y: -1)
            Issue.record("Should throw for negative coords")
        } catch {
            // Expected
        }
    }

    @Test("rightClick valid coords does not throw")
    func rightClickValidCoords() throws {
        try service.rightClick(x: 0, y: 0)
    }

    @Test("rightClick negative coords throws")
    func rightClickNegativeCoords() {
        do {
            try service.rightClick(x: -1, y: -1)
            Issue.record("Should throw for negative coords")
        } catch {
            // Expected
        }
    }

    // MARK: - drag (exercise both validateCoordinates + CGEvent loop)

    @Test("drag valid coords does not throw")
    func dragValidCoords() throws {
        try service.drag(fromX: 0, fromY: 0, toX: 10, toY: 10)
    }

    @Test("drag negative from coords throws")
    func dragNegativeFromCoords() {
        do {
            try service.drag(fromX: -1, fromY: 0, toX: 10, toY: 10)
            Issue.record("Should throw for negative from coords")
        } catch {
            // Expected
        }
    }

    @Test("drag negative to coords throws")
    func dragNegativeToCoords() {
        do {
            try service.drag(fromX: 0, fromY: 0, toX: -1, toY: -1)
            Issue.record("Should throw for negative to coords")
        } catch {
            // Expected
        }
    }
}
