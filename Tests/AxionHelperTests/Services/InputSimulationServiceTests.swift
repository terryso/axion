import CoreGraphics
import Foundation
import XCTest
@testable import AxionHelper

// Unit tests for InputSimulationService pure-logic methods:
// key name mapping, hotkey parsing, scroll direction parsing, coordinate validation.
// These tests do NOT call CGEvent — they test the parsing/validation layer only.
// Priority: P0 (core logic for keyboard/mouse input)

@MainActor
final class InputSimulationServiceTests: XCTestCase {

    // MARK: - Key Name Mapping (AC5: press_key)

    func test_keyNameMapping_return_mapsToCorrectKeyCode() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("return")
        XCTAssertEqual(keyCode, 0x24, "'return' should map to virtual key code 0x24")
    }

    func test_keyNameMapping_enter_mapsToReturnKeyCode() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("enter")
        XCTAssertEqual(keyCode, 0x24, "'enter' should be an alias for 'return' (0x24)")
    }

    func test_keyNameMapping_tab_mapsToCorrectKeyCode() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("tab")
        XCTAssertEqual(keyCode, 0x30, "'tab' should map to virtual key code 0x30")
    }

    func test_keyNameMapping_escape_mapsToCorrectKeyCode() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("escape")
        XCTAssertEqual(keyCode, 0x35, "'escape' should map to virtual key code 0x35")
    }

    func test_keyNameMapping_space_mapsToCorrectKeyCode() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("space")
        XCTAssertEqual(keyCode, 0x31, "'space' should map to virtual key code 0x31")
    }

    func test_keyNameMapping_delete_mapsToCorrectKeyCode() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("delete")
        XCTAssertEqual(keyCode, 0x33, "'delete' should map to virtual key code 0x33 (Backspace)")
    }

    func test_keyNameMapping_functionKeys_mapCorrectly() throws {
        let service = InputSimulationService()
        let expectedFKeys: [String: CGKeyCode] = [
            "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
            "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
            "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        ]
        for (name, expected) in expectedFKeys {
            let actual = service.keyCodeForName(name)
            XCTAssertEqual(actual, expected, "'\(name)' should map to 0x\(String(expected, radix: 16))")
        }
    }

    func test_keyNameMapping_arrowKeys_mapCorrectly() throws {
        let service = InputSimulationService()
        let expectedArrows: [String: CGKeyCode] = [
            "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        ]
        for (name, expected) in expectedArrows {
            let actual = service.keyCodeForName(name)
            XCTAssertEqual(actual, expected, "'\(name)' should map to 0x\(String(expected, radix: 16))")
        }
    }

    func test_keyNameMapping_singleLetter_a_mapsToZero() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("a")
        XCTAssertEqual(keyCode, 0x00, "'a' should map to virtual key code 0x00")
    }

    func test_keyNameMapping_invalidKey_returnsNil() throws {
        let service = InputSimulationService()
        let keyCode = service.keyCodeForName("nonexistent_key")
        XCTAssertNil(keyCode, "Unknown key name should return nil")
    }

    // MARK: - Hotkey Parsing (AC6: hotkey)

    func test_hotkeyParsing_cmdC_returnsCommandFlagAndCKeyCode() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("cmd+c")

        XCTAssertTrue(result.flags.contains(.maskCommand), "'cmd+c' should set .maskCommand flag")
        XCTAssertEqual(result.keyCode, 0x08, "'cmd+c' main key 'c' should map to 0x08")
    }

    func test_hotkeyParsing_cmdShiftS_returnsCombinedFlags() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("cmd+shift+s")

        XCTAssertTrue(result.flags.contains(.maskCommand), "'cmd+shift+s' should set .maskCommand")
        XCTAssertTrue(result.flags.contains(.maskShift), "'cmd+shift+s' should set .maskShift")
        XCTAssertEqual(result.keyCode, 0x01, "'cmd+shift+s' main key 's' should map to 0x01")
    }

    func test_hotkeyParsing_ctrlAltDelete_returnsCombinedFlags() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("ctrl+alt+delete")

        XCTAssertTrue(result.flags.contains(.maskControl), "'ctrl+alt+delete' should set .maskControl")
        XCTAssertTrue(result.flags.contains(.maskAlternate), "'ctrl+alt+delete' should set .maskAlternate")
        XCTAssertEqual(result.keyCode, 0x33, "'delete' should map to 0x33")
    }

    func test_hotkeyParsing_singleKeyNoModifier_throwsInvalidHotkeyFormat() throws {
        let service = InputSimulationService()
        XCTAssertThrowsError(try service.parseHotkey("c")) { error in
            guard let simError = error as? InputSimulationError else {
                XCTFail("Expected InputSimulationError"); return
            }
            if case .invalidHotkeyFormat = simError {
                // expected
            } else {
                XCTFail("Expected invalidHotkeyFormat, got \(simError)")
            }
        }
    }

    func test_hotkeyParsing_unknownModifier_throwsInvalidHotkeyFormat() throws {
        let service = InputSimulationService()
        XCTAssertThrowsError(try service.parseHotkey("super+c")) { error in
            guard let simError = error as? InputSimulationError else {
                XCTFail("Expected InputSimulationError"); return
            }
            if case .invalidHotkeyFormat = simError {
                // expected
            } else {
                XCTFail("Expected invalidHotkeyFormat, got \(simError)")
            }
        }
    }

    func test_hotkeyParsing_commandAlias_worksAsCmd() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("command+c")

        XCTAssertTrue(result.flags.contains(.maskCommand), "'command+c' should set .maskCommand (alias for 'cmd')")
    }

    func test_hotkeyParsing_optionAlias_worksAsAlt() throws {
        let service = InputSimulationService()
        let result = try service.parseHotkey("option+a")

        XCTAssertTrue(result.flags.contains(.maskAlternate), "'option+a' should set .maskAlternate (alias for 'alt')")
    }

    // MARK: - Scroll Direction Parsing (AC7: scroll)

    func test_scrollDirection_up_returnsPositiveValue() throws {
        let service = InputSimulationService()
        let scrollValue = try service.scrollValueForDirection("up", amount: 5)
        XCTAssertEqual(scrollValue, 5, "Scroll 'up' should return positive amount")
    }

    func test_scrollDirection_down_returnsNegativeValue() throws {
        let service = InputSimulationService()
        let scrollValue = try service.scrollValueForDirection("down", amount: 3)
        XCTAssertEqual(scrollValue, -3, "Scroll 'down' should return negative amount")
    }

    func test_scrollDirection_invalidDirection_throwsError() throws {
        let service = InputSimulationService()
        XCTAssertThrowsError(try service.scrollValueForDirection("diagonal", amount: 1)) { error in
            guard let simError = error as? InputSimulationError else {
                XCTFail("Expected InputSimulationError"); return
            }
            if case .invalidDirection = simError {
                // expected
            } else {
                XCTFail("Expected invalidDirection, got \(simError)")
            }
        }
    }

    func test_scrollDirection_isCaseInsensitive() throws {
        let service = InputSimulationService()
        let value = try service.scrollValueForDirection("UP", amount: 2)
        XCTAssertEqual(value, 2, "Scroll direction should be case-insensitive")
    }

    // MARK: - Coordinate Validation (AC1, AC2, AC3, AC8)

    func test_coordinateValidation_negativeX_throwsOutOfBounds() throws {
        let service = InputSimulationService()
        XCTAssertThrowsError(try service.validateCoordinates(x: -1, y: 100)) { error in
            guard let simError = error as? InputSimulationError else {
                XCTFail("Expected InputSimulationError"); return
            }
            if case .coordinatesOutOfBounds = simError {
                // expected
            } else {
                XCTFail("Expected coordinatesOutOfBounds, got \(simError)")
            }
        }
    }

    func test_coordinateValidation_negativeY_throwsOutOfBounds() throws {
        let service = InputSimulationService()
        XCTAssertThrowsError(try service.validateCoordinates(x: 100, y: -1)) { error in
            guard let simError = error as? InputSimulationError else {
                XCTFail("Expected InputSimulationError"); return
            }
            if case .coordinatesOutOfBounds = simError {
                // expected
            } else {
                XCTFail("Expected coordinatesOutOfBounds, got \(simError)")
            }
        }
    }

    func test_coordinateValidation_exceedsScreenSize_throwsOutOfBounds() throws {
        let service = InputSimulationService()
        // Use an unreasonably large coordinate
        XCTAssertThrowsError(try service.validateCoordinates(x: 99999, y: 99999)) { error in
            guard let simError = error as? InputSimulationError else {
                XCTFail("Expected InputSimulationError"); return
            }
            if case .coordinatesOutOfBounds = simError {
                // expected
            } else {
                XCTFail("Expected coordinatesOutOfBounds, got \(simError)")
            }
        }
    }

    func test_coordinateValidation_validCoordinates_doesNotThrow() throws {
        let service = InputSimulationService()
        XCTAssertNoThrow(try service.validateCoordinates(x: 500, y: 300),
                         "Valid screen coordinates should not throw")
    }

    // MARK: - InputSimulationError Format (cross-cutting)

    func test_inputSimulationError_coordinatesOutOfBounds_hasRequiredFields() throws {
        let error = InputSimulationError.coordinatesOutOfBounds(x: -1, y: -1)
        XCTAssertFalse(error.errorCode.isEmpty, "Error code should not be empty")
        XCTAssertNotNil(error.errorDescription, "Error description should not be nil")
        XCTAssertFalse(error.suggestion.isEmpty, "Suggestion should not be empty")
    }

    func test_inputSimulationError_invalidKeyName_hasRequiredFields() throws {
        let error = InputSimulationError.invalidKeyName("foobar")
        XCTAssertEqual(error.errorCode, "invalid_key_name")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.suggestion.isEmpty)
    }

    func test_inputSimulationError_invalidHotkeyFormat_hasRequiredFields() throws {
        let error = InputSimulationError.invalidHotkeyFormat("xyz")
        XCTAssertEqual(error.errorCode, "invalid_hotkey_format")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.suggestion.isEmpty)
    }

    func test_inputSimulationError_invalidDirection_hasRequiredFields() throws {
        let error = InputSimulationError.invalidDirection("diagonal")
        XCTAssertEqual(error.errorCode, "invalid_direction")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.suggestion.isEmpty)
    }
}
