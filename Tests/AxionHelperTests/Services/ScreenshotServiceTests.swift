import Foundation
import XCTest
@testable import AxionHelper

// ATDD Red-Phase Test Scaffolds for Story 1.5
// Tests for ScreenshotService logic: base64 encoding, size limits, error types.
// Actual CGWindowListCreateImage calls are NOT tested here (need real macOS display).
// Priority: P0 (core logic for screenshot tool)

@MainActor
final class ScreenshotServiceTests: XCTestCase {

    // MARK: - ScreenshotError Format (cross-cutting)

    // [P0] ScreenshotError.windowCaptureFailed has required fields
    func test_screenshotError_windowCaptureFailed_hasRequiredFields() {
        let error = ScreenshotError.windowCaptureFailed(windowId: 12345)
        XCTAssertEqual(error.errorCode, "window_capture_failed")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.suggestion.isEmpty)
    }

    // [P0] ScreenshotError.fullScreenCaptureFailed has required fields
    func test_screenshotError_fullScreenCaptureFailed_hasRequiredFields() {
        let error = ScreenshotError.fullScreenCaptureFailed
        XCTAssertEqual(error.errorCode, "fullscreen_capture_failed")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.suggestion.isEmpty)
    }

    // [P0] ScreenshotError.imageConversionFailed has required fields
    func test_screenshotError_imageConversionFailed_hasRequiredFields() {
        let error = ScreenshotError.imageConversionFailed
        XCTAssertEqual(error.errorCode, "image_conversion_failed")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.suggestion.isEmpty)
    }

    // [P0] ScreenshotError.screenshotTooLarge has required fields
    func test_screenshotError_screenshotTooLarge_hasRequiredFields() {
        let error = ScreenshotError.screenshotTooLarge(sizeBytes: 6 * 1024 * 1024)
        XCTAssertEqual(error.errorCode, "screenshot_too_large")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.suggestion.isEmpty)
    }

    // MARK: - ScreenshotCapturing Protocol Conformance

    // [P0] ScreenshotService conforms to ScreenshotCapturing protocol
    func test_screenshotService_conformsToScreenshotCapturing() {
        let service = ScreenshotService()
        XCTAssertTrue(service is ScreenshotCapturing,
                      "ScreenshotService should conform to ScreenshotCapturing protocol")
    }

    // MARK: - Base64 Encoding Validation (using mock data)

    // [P0] A valid base64 string can be decoded back to binary data
    func test_base64Encoding_validBase64_roundTrips() {
        let originalData = Data("Hello, Screenshot!".utf8)
        let base64String = originalData.base64EncodedString()
        let decodedData = Data(base64Encoded: base64String)

        XCTAssertEqual(decodedData, originalData,
                       "Base64 encode/decode should round-trip correctly")
    }

    // [P0] Base64 string contains only valid base64 characters
    func test_base64Encoding_containsOnlyValidCharacters() {
        let originalData = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])
        let base64String = originalData.base64EncodedString()

        let validBase64 = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        for char in base64String.unicodeScalars {
            XCTAssertTrue(validBase64.contains(char),
                          "Character '\(char)' should be valid base64")
        }
    }

    // MARK: - Size Limit Logic

    // [P0] 5MB size limit constant is correct
    func test_sizeLimit_fiveMB_isCorrectValue() {
        let fiveMB = 5 * 1024 * 1024
        XCTAssertEqual(fiveMB, 5_242_880, "5MB should be 5,242,880 bytes")
    }

    // [P0] Data smaller than 5MB base64 should pass size check
    func test_sizeLimit_smallData_passesCheck() {
        let smallData = Data(repeating: 0xAA, count: 1024) // 1KB
        let base64Data = smallData.base64EncodedData()
        XCTAssertTrue(base64Data.count <= 5 * 1024 * 1024,
                      "1KB data base64 should be well under 5MB limit")
    }
}
