import CoreGraphics
import Foundation
import Testing
@testable import AxionHelper

@Suite("InputSimulationService")
@MainActor
struct InputSimulationServiceTests {

    // MARK: - Key Name Mapping

    @Test("key name 'return' maps to correct key code")
    func keyNameMappingReturnMapsToCorrectKeyCode() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("return")
        #expect(keyCode == 0x24, "'return' should map to virtual key code 0x24")
    }

    @Test("key name 'enter' maps to return key code")
    func keyNameMappingEnterMapsToReturnKeyCode() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("enter")
        #expect(keyCode == 0x24, "'enter' should be an alias for 'return' (0x24)")
    }

    @Test("key name 'tab' maps to correct key code")
    func keyNameMappingTabMapsToCorrectKeyCode() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("tab")
        #expect(keyCode == 0x30, "'tab' should map to virtual key code 0x30")
    }

    @Test("key name 'escape' maps to correct key code")
    func keyNameMappingEscapeMapsToCorrectKeyCode() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("escape")
        #expect(keyCode == 0x35, "'escape' should map to virtual key code 0x35")
    }

    @Test("key name 'space' maps to correct key code")
    func keyNameMappingSpaceMapsToCorrectKeyCode() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("space")
        #expect(keyCode == 0x31, "'space' should map to virtual key code 0x31")
    }

    @Test("key name 'delete' maps to correct key code")
    func keyNameMappingDeleteMapsToCorrectKeyCode() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("delete")
        #expect(keyCode == 0x33, "'delete' should map to virtual key code 0x33 (Backspace)")
    }

    @Test("function keys map correctly")
    func keyNameMappingFunctionKeysMapCorrectly() throws {
        let service = InputSimulationService()
        let expectedFKeys: [String: CGKeyCode] = [
            "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
            "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
            "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        ]
        for (name, expected) in expectedFKeys {
            let actual = service.keyCodeForName(name)
            #expect(actual == expected, "'\(name)' should map to 0x\(String(expected, radix: 16))")
        }
    }

    @Test("arrow keys map correctly")
    func keyNameMappingArrowKeysMapCorrectly() throws {
        let service = InputSimulationService()
        let expectedArrows: [String: CGKeyCode] = [
            "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        ]
        for (name, expected) in expectedArrows {
            let actual = service.keyCodeForName(name)
            #expect(actual == expected, "'\(name)' should map to 0x\(String(expected, radix: 16))")
        }
    }

    @Test("single letter 'a' maps to zero")
    func keyNameMappingSingleLetterAMapsToZero() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("a")
        #expect(keyCode == 0x00, "'a' should map to virtual key code 0x00")
    }

    @Test("invalid key name returns nil")
    func keyNameMappingInvalidKeyReturnsNil() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("nonexistent_key")
        #expect(keyCode == nil, "Unknown key name should return nil")
    }

    // MARK: - Hotkey Parsing

    @Test("cmd+c returns command flag and c key code")
    func hotkeyParsingCmdCReturnsCommandFlagAndCKeyCode() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("cmd+c")

        #expect(result.flags.contains(.maskCommand), "'cmd+c' should set .maskCommand flag")
        #expect(result.keyCode == 0x08, "'cmd+c' main key 'c' should map to 0x08")
    }

    @Test("cmd+shift+s returns combined flags")
    func hotkeyParsingCmdShiftSReturnsCombinedFlags() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("cmd+shift+s")

        #expect(result.flags.contains(.maskCommand), "'cmd+shift+s' should set .maskCommand")
        #expect(result.flags.contains(.maskShift), "'cmd+shift+s' should set .maskShift")
        #expect(result.keyCode == 0x01, "'cmd+shift+s' main key 's' should map to 0x01")
    }

    @Test("ctrl+alt+delete returns combined flags")
    func hotkeyParsingCtrlAltDeleteReturnsCombinedFlags() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("ctrl+alt+delete")

        #expect(result.flags.contains(.maskControl), "'ctrl+alt+delete' should set .maskControl")
        #expect(result.flags.contains(.maskAlternate), "'ctrl+alt+delete' should set .maskAlternate")
        #expect(result.keyCode == 0x33, "'delete' should map to 0x33")
    }

    @Test("single key no modifier throws invalidHotkeyFormat")
    func hotkeyParsingSingleKeyNoModifierThrowsInvalidHotkeyFormat() {
        let service = InputSimulationService()
        #expect(throws: InputSimulationError.self) {
            try service.parseHotkey("c")
        }
    }

    @Test("unknown modifier throws invalidHotkeyFormat")
    func hotkeyParsingUnknownModifierThrowsInvalidHotkeyFormat() {
        let service = InputSimulationService()
        #expect(throws: InputSimulationError.self) {
            try service.parseHotkey("super+c")
        }
    }

    @Test("'command' alias works as 'cmd'")
    func hotkeyParsingCommandAliasWorksAsCmd() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("command+c")

        #expect(result.flags.contains(.maskCommand), "'command+c' should set .maskCommand (alias for 'cmd')")
    }

    @Test("'option' alias works as 'alt'")
    func hotkeyParsingOptionAliasWorksAsAlt() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("option+a")

        #expect(result.flags.contains(.maskAlternate), "'option+a' should set .maskAlternate (alias for 'alt')")
    }

    // MARK: - Scroll Direction Parsing

    @Test("scroll 'up' returns positive value")
    func scrollDirectionUpReturnsPositiveValue() throws {
        let service = InputSimulationService()
        let scrollValue = try service.scrollValueForDirection("up", amount: 5)
        #expect(scrollValue == 5, "Scroll 'up' should return positive amount")
    }

    @Test("scroll 'down' returns negative value")
    func scrollDirectionDownReturnsNegativeValue() throws {
        let service = InputSimulationService()
        let scrollValue = try service.scrollValueForDirection("down", amount: 3)
        #expect(scrollValue == -3, "Scroll 'down' should return negative amount")
    }

    @Test("scroll invalid direction throws error")
    func scrollDirectionInvalidDirectionThrowsError() {
        let service = InputSimulationService()
        #expect(throws: InputSimulationError.self) {
            try service.scrollValueForDirection("diagonal", amount: 1)
        }
    }

    @Test("scroll direction is case insensitive")
    func scrollDirectionIsCaseInsensitive() throws {
        let service = InputSimulationService()
        let value = try service.scrollValueForDirection("UP", amount: 2)
        #expect(value == 2, "Scroll direction should be case-insensitive")
    }

    // MARK: - Coordinate Validation

    @Test("negative x throws out of bounds")
    func coordinateValidationNegativeXThrowsOutOfBounds() {
        let service = InputSimulationService()
        #expect(throws: InputSimulationError.self) {
            try service.validateCoordinates(x: -1, y: 100)
        }
    }

    @Test("negative y throws out of bounds")
    func coordinateValidationNegativeYThrowsOutOfBounds() {
        let service = InputSimulationService()
        #expect(throws: InputSimulationError.self) {
            try service.validateCoordinates(x: 100, y: -1)
        }
    }

    @Test("coordinates exceeding screen size throw out of bounds")
    func coordinateValidationExceedsScreenSizeThrowsOutOfBounds() {
        let service = InputSimulationService()
        #expect(throws: InputSimulationError.self) {
            try service.validateCoordinates(x: 99999, y: 99999)
        }
    }

    @Test("valid coordinates do not throw")
    func coordinateValidationValidCoordinatesDoesNotThrow() throws {
        let service = InputSimulationService()
        try service.validateCoordinates(x: 500, y: 300)
    }

    // MARK: - InputSimulationError Format

    @Test("coordinatesOutOfBounds error has required fields")
    func inputSimulationErrorCoordinatesOutOfBoundsHasRequiredFields() {
        let error = InputSimulationError.coordinatesOutOfBounds(x: -1, y: -1)
        #expect(!error.errorCode.isEmpty, "Error code should not be empty")
        #expect(error.errorDescription != nil, "Error description should not be nil")
        #expect(!error.suggestion.isEmpty, "Suggestion should not be empty")
    }

    @Test("invalidKeyName error has required fields")
    func inputSimulationErrorInvalidKeyNameHasRequiredFields() {
        let error = InputSimulationError.invalidKeyName("foobar")
        #expect(error.errorCode == "invalid_key_name")
        #expect(error.errorDescription != nil)
        #expect(!error.suggestion.isEmpty)
    }

    @Test("invalidHotkeyFormat error has required fields")
    func inputSimulationErrorInvalidHotkeyFormatHasRequiredFields() {
        let error = InputSimulationError.invalidHotkeyFormat("xyz")
        #expect(error.errorCode == "invalid_hotkey_format")
        #expect(error.errorDescription != nil)
        #expect(!error.suggestion.isEmpty)
    }

    @Test("invalidDirection error has required fields")
    func inputSimulationErrorInvalidDirectionHasRequiredFields() {
        let error = InputSimulationError.invalidDirection("diagonal")
        #expect(error.errorCode == "invalid_direction")
        #expect(error.errorDescription != nil)
        #expect(!error.suggestion.isEmpty)
    }

    // MARK: - Key Map Completeness

    @Test("all letters map correctly")
    func keyNameMappingAllLettersMapCorrectly() throws {
        let service = InputSimulationService()
        let expectedLetters: [String: CGKeyCode] = [
            "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
            "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
            "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
            "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
            "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10,
            "z": 0x06,
        ]
        for (name, expected) in expectedLetters {
            let actual = service.keyCodeForName(name)
            #expect(actual == expected, "'\(name)' should map to 0x\(String(expected, radix: 16))")
        }
    }

    @Test("key name mapping is case insensitive")
    func keyNameMappingIsCaseInsensitive() throws {
        let service = InputSimulationService()
        let lower = service.keyCodeForName("return")
        let upper = service.keyCodeForName("RETURN")
        let mixed = service.keyCodeForName("Return")
        #expect(lower == upper)
        #expect(lower == mixed)
        #expect(lower == 0x24)
    }

    @Test("'esc' alias for 'escape'")
    func keyNameMappingEscAlias() throws {
        let service = InputSimulationService()
        #expect(service.keyCodeForName("esc") == 0x35)
        #expect(service.keyCodeForName("esc") == service.keyCodeForName("escape"))
    }

    @Test("'backspace' alias for 'delete'")
    func keyNameMappingBackspaceAlias() throws {
        let service = InputSimulationService()
        #expect(service.keyCodeForName("backspace") == 0x33)
        #expect(service.keyCodeForName("backspace") == service.keyCodeForName("delete"))
    }

    @Test("home/end/pageup/pagedown/forwarddelete")
    func keyNameMappingHomeEndPageUpDown() throws {
        let service = InputSimulationService()
        #expect(service.keyCodeForName("home") == 0x73)
        #expect(service.keyCodeForName("end") == 0x77)
        #expect(service.keyCodeForName("pageup") == 0x74)
        #expect(service.keyCodeForName("pagedown") == 0x79)
        #expect(service.keyCodeForName("forwarddelete") == 0x75)
    }

    // MARK: - Hotkey Parsing Extended

    @Test("'control' alias works as ctrl")
    func hotkeyParsingCtrlAliasWorksAsControl() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("control+a")
        #expect(result.flags.contains(.maskControl), "'control+a' should set .maskControl")
    }

    @Test("'alt' alias works")
    func hotkeyParsingAltAliasWorksAsAlt() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("alt+a")
        #expect(result.flags.contains(.maskAlternate), "'alt+a' should set .maskAlternate")
    }

    @Test("three modifiers")
    func hotkeyParsingThreeModifiers() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("cmd+shift+ctrl+a")
        #expect(result.flags.contains(.maskCommand))
        #expect(result.flags.contains(.maskShift))
        #expect(result.flags.contains(.maskControl))
        #expect(result.keyCode == 0x00)
    }

    @Test("four modifiers")
    func hotkeyParsingFourModifiers() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("cmd+shift+ctrl+alt+a")
        #expect(result.flags.contains(.maskCommand))
        #expect(result.flags.contains(.maskShift))
        #expect(result.flags.contains(.maskControl))
        #expect(result.flags.contains(.maskAlternate))
    }

    @Test("hotkey parsing is case insensitive")
    func hotkeyParsingCaseInsensitive() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("CMD+SHIFT+C")
        #expect(result.flags.contains(.maskCommand))
        #expect(result.flags.contains(.maskShift))
        #expect(result.keyCode == 0x08)
    }

    @Test("hotkey parsing handles whitespace")
    func hotkeyParsingWhitespaceHandling() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("cmd + shift + c")
        #expect(result.flags.contains(.maskCommand))
        #expect(result.flags.contains(.maskShift))
        #expect(result.keyCode == 0x08)
    }

    @Test("unknown main key throws invalidKeyName")
    func hotkeyParsingUnknownMainKeyThrowsInvalidKeyName() {
        let service = InputSimulationService()
        #expect(throws: InputSimulationError.self) {
            try service.parseHotkey("cmd+nonexistent")
        }
    }

    // MARK: - Scroll Direction Extended

    @Test("scroll 'DOWN' is case insensitive")
    func scrollDirectionDownIsCaseInsensitive() throws {
        let service = InputSimulationService()
        let value = try service.scrollValueForDirection("DOWN", amount: 3)
        #expect(value == -3)
    }

    @Test("scroll with zero amount")
    func scrollDirectionZeroAmount() throws {
        let service = InputSimulationService()
        let value = try service.scrollValueForDirection("up", amount: 0)
        #expect(value == 0)
    }

    @Test("scroll with large amount")
    func scrollDirectionLargeAmount() throws {
        let service = InputSimulationService()
        let value = try service.scrollValueForDirection("down", amount: 1000)
        #expect(value == -1000)
    }

    // MARK: - Error Descriptions

    @Test("coordinatesOutOfBounds description contains coordinates")
    func errorCoordinatesOutOfBoundsContainsCoordinates() {
        let error = InputSimulationError.coordinatesOutOfBounds(x: -5, y: 10)
        let desc = error.errorDescription
        #expect(desc != nil)
        #expect(desc!.contains("-5"))
        #expect(desc!.contains("10"))
    }

    @Test("invalidKeyName description contains key name")
    func errorInvalidKeyNameContainsKeyName() {
        let error = InputSimulationError.invalidKeyName("foobar")
        let desc = error.errorDescription
        #expect(desc != nil)
        #expect(desc!.contains("foobar"))
    }

    @Test("invalidHotkeyFormat description contains keys")
    func errorInvalidHotkeyFormatContainsKeys() {
        let error = InputSimulationError.invalidHotkeyFormat("xyz+abc")
        let desc = error.errorDescription
        #expect(desc != nil)
        #expect(desc!.contains("xyz+abc"))
    }

    @Test("invalidDirection description contains direction")
    func errorInvalidDirectionContainsDirection() {
        let error = InputSimulationError.invalidDirection("sideways")
        let desc = error.errorDescription
        #expect(desc != nil)
        #expect(desc!.contains("sideways"))
    }
}
