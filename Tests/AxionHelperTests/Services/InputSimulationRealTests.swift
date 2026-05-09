import CoreGraphics
import XCTest
@testable import AxionHelper

/// Tests that directly call InputSimulationService real implementations
/// to maximize code coverage on the non-CGEvent paths.
final class InputSimulationRealTests: XCTestCase {

    private let service = InputSimulationService()

    // MARK: - keyCodeForName (all keys)

    func test_keyMap_hasAllExpectedKeys() {
        let expectedKeys = [
            "return", "enter", "tab", "space", "escape", "esc",
            "delete", "backspace", "forwarddelete", "home", "end",
            "pageup", "pagedown", "left", "right", "down", "up",
        ]
        for key in expectedKeys {
            XCTAssertNotNil(service.keyCodeForName(key), "'\(key)' should be in keyMap")
        }
    }

    func test_keyMap_hasAllFunctionKeys() {
        for i in 1...12 {
            let name = "f\(i)"
            XCTAssertNotNil(service.keyCodeForName(name), "'\(name)' should be in keyMap")
        }
    }

    func test_keyMap_hasAllLetters() {
        for c in "abcdefghijklmnopqrstuvwxyz" {
            let name = String(c)
            XCTAssertNotNil(service.keyCodeForName(name), "'\(name)' should be in keyMap")
        }
    }

    func test_keyMap_returnsNilForUnknown() {
        XCTAssertNil(service.keyCodeForName("notakey"))
    }

    // MARK: - parseHotkey (all modifier combinations)

    func test_parseHotkey_cmdOnly() throws {
        let result = try service.parseHotkey("cmd+a")
        XCTAssertTrue(result.flags.contains(.maskCommand))
        XCTAssertFalse(result.flags.contains(.maskShift))
        XCTAssertFalse(result.flags.contains(.maskControl))
        XCTAssertFalse(result.flags.contains(.maskAlternate))
    }

    func test_parseHotkey_shiftOnly() throws {
        let result = try service.parseHotkey("shift+a")
        XCTAssertTrue(result.flags.contains(.maskShift))
    }

    func test_parseHotkey_ctrlOnly() throws {
        let result = try service.parseHotkey("ctrl+a")
        XCTAssertTrue(result.flags.contains(.maskControl))
    }

    func test_parseHotkey_altOnly() throws {
        let result = try service.parseHotkey("alt+a")
        XCTAssertTrue(result.flags.contains(.maskAlternate))
    }

    func test_parseHotkey_allModifierAliases() throws {
        // command = cmd
        let r1 = try service.parseHotkey("command+a")
        XCTAssertTrue(r1.flags.contains(.maskCommand))

        // control = ctrl
        let r2 = try service.parseHotkey("control+a")
        XCTAssertTrue(r2.flags.contains(.maskControl))

        // option = alt
        let r3 = try service.parseHotkey("option+a")
        XCTAssertTrue(r3.flags.contains(.maskAlternate))
    }

    func test_parseHotkey_throwsForSingleKey() {
        XCTAssertThrowsError(try service.parseHotkey("a"))
    }

    func test_parseHotkey_throwsForUnknownModifier() {
        XCTAssertThrowsError(try service.parseHotkey("super+a"))
    }

    func test_parseHotkey_throwsForUnknownMainKey() {
        XCTAssertThrowsError(try service.parseHotkey("cmd+unknownkey"))
    }

    // MARK: - scrollValueForDirection

    func test_scrollValueForDirection_up() throws {
        XCTAssertEqual(try service.scrollValueForDirection("up", amount: 5), 5)
    }

    func test_scrollValueForDirection_down() throws {
        XCTAssertEqual(try service.scrollValueForDirection("down", amount: 3), -3)
    }

    func test_scrollValueForDirection_invalid() {
        XCTAssertThrowsError(try service.scrollValueForDirection("left", amount: 1))
    }

    func test_scrollValueForDirection_caseInsensitive() throws {
        XCTAssertEqual(try service.scrollValueForDirection("UP", amount: 2), 2)
        XCTAssertEqual(try service.scrollValueForDirection("Down", amount: 4), -4)
    }

    // MARK: - validateCoordinates

    func test_validateCoordinates_validPoint() throws {
        XCTAssertNoThrow(try service.validateCoordinates(x: 0, y: 0))
    }

    func test_validateCoordinates_negativeX_throws() {
        XCTAssertThrowsError(try service.validateCoordinates(x: -1, y: 0))
    }

    func test_validateCoordinates_negativeY_throws() {
        XCTAssertThrowsError(try service.validateCoordinates(x: 0, y: -1))
    }

    func test_validateCoordinates_tooLarge_throws() {
        XCTAssertThrowsError(try service.validateCoordinates(x: 99999, y: 99999))
    }

    func test_validateCoordinates_atScreenEdge() throws {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        XCTAssertNoThrow(try service.validateCoordinates(x: Int(bounds.width), y: Int(bounds.height)))
    }

    // MARK: - scroll method (direct call, exercises switch statement)

    func test_scroll_up_doesNotThrow() throws {
        // This actually calls CGEvent — may or may not work in CI
        // but exercises the switch branches
        try service.scroll(direction: "up", amount: 1)
    }

    func test_scroll_down_doesNotThrow() throws {
        try service.scroll(direction: "down", amount: 1)
    }

    func test_scroll_left_doesNotThrow() throws {
        try service.scroll(direction: "left", amount: 1)
    }

    func test_scroll_right_doesNotThrow() throws {
        try service.scroll(direction: "right", amount: 1)
    }

    func test_scroll_invalidDirection_throws() {
        XCTAssertThrowsError(try service.scroll(direction: "diagonal", amount: 1))
    }

    // MARK: - typeText (exercises the loop and CGEvent creation)

    func test_typeText_emptyString_doesNotThrow() throws {
        try service.typeText("")
    }

    func test_typeText_singleChar_doesNotThrow() throws {
        try service.typeText("a")
    }

    func test_typeText_unicode_doesNotThrow() throws {
        try service.typeText("你好")
    }

    // MARK: - pressKey (exercises keyMap lookup and CGEvent)

    func test_pressKey_return_doesNotThrow() throws {
        try service.pressKey("return")
    }

    func test_pressKey_invalidKey_throws() {
        XCTAssertThrowsError(try service.pressKey("nonexistent_key_xyz"))
    }

    // MARK: - hotkey (exercises parseHotkey + CGEvent)

    func test_hotkey_cmdA_doesNotThrow() throws {
        try service.hotkey("cmd+a")
    }

    func test_hotkey_invalidFormat_throws() {
        XCTAssertThrowsError(try service.hotkey("a"))
    }

    // MARK: - click operations (exercise validateCoordinates + CGEvent)

    func test_click_validCoords_doesNotThrow() throws {
        try service.click(x: 0, y: 0)
    }

    func test_click_negativeCoords_throws() {
        XCTAssertThrowsError(try service.click(x: -1, y: -1))
    }

    func test_doubleClick_validCoords_doesNotThrow() throws {
        try service.doubleClick(x: 0, y: 0)
    }

    func test_doubleClick_negativeCoords_throws() {
        XCTAssertThrowsError(try service.doubleClick(x: -1, y: -1))
    }

    func test_rightClick_validCoords_doesNotThrow() throws {
        try service.rightClick(x: 0, y: 0)
    }

    func test_rightClick_negativeCoords_throws() {
        XCTAssertThrowsError(try service.rightClick(x: -1, y: -1))
    }

    // MARK: - drag (exercise both validateCoordinates + CGEvent loop)

    func test_drag_validCoords_doesNotThrow() throws {
        try service.drag(fromX: 0, fromY: 0, toX: 10, toY: 10)
    }

    func test_drag_negativeFromCoords_throws() {
        XCTAssertThrowsError(try service.drag(fromX: -1, fromY: 0, toX: 10, toY: 10))
    }

    func test_drag_negativeToCoords_throws() {
        XCTAssertThrowsError(try service.drag(fromX: 0, fromY: 0, toX: -1, toY: -1))
    }
}
