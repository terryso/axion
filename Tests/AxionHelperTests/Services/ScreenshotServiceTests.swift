import Foundation
import Testing
@testable import AxionHelper

@Suite("ScreenshotService")
@MainActor
struct ScreenshotServiceTests {

    // MARK: - ScreenshotError Format

    @Test("windowCaptureFailed error has required fields")
    func screenshotErrorWindowCaptureFailedHasRequiredFields() {
        let error = ScreenshotError.windowCaptureFailed(windowId: 12345)
        #expect(error.errorCode == "window_capture_failed")
        #expect(error.errorDescription != nil)
        #expect(!error.suggestion.isEmpty)
    }

    @Test("fullScreenCaptureFailed error has required fields")
    func screenshotErrorFullScreenCaptureFailedHasRequiredFields() {
        let error = ScreenshotError.fullScreenCaptureFailed
        #expect(error.errorCode == "fullscreen_capture_failed")
        #expect(error.errorDescription != nil)
        #expect(!error.suggestion.isEmpty)
    }

    @Test("imageConversionFailed error has required fields")
    func screenshotErrorImageConversionFailedHasRequiredFields() {
        let error = ScreenshotError.imageConversionFailed
        #expect(error.errorCode == "image_conversion_failed")
        #expect(error.errorDescription != nil)
        #expect(!error.suggestion.isEmpty)
    }

    @Test("screenshotTooLarge error has required fields")
    func screenshotErrorScreenshotTooLargeHasRequiredFields() {
        let error = ScreenshotError.screenshotTooLarge(sizeBytes: 6 * 1024 * 1024)
        #expect(error.errorCode == "screenshot_too_large")
        #expect(error.errorDescription != nil)
        #expect(!error.suggestion.isEmpty)
    }

    // MARK: - ScreenshotCapturing Protocol Conformance

    @Test("conforms to ScreenshotCapturing protocol")
    func screenshotServiceConformsToScreenshotCapturing() {
        let service = ScreenshotService()
        #expect(service is ScreenshotCapturing,
               "ScreenshotService should conform to ScreenshotCapturing protocol")
    }

    // MARK: - Base64 Encoding Validation

    @Test("valid base64 round-trips correctly")
    func base64EncodingValidBase64RoundTrips() {
        let originalData = Data("Hello, Screenshot!".utf8)
        let base64String = originalData.base64EncodedString()
        let decodedData = Data(base64Encoded: base64String)

        #expect(decodedData == originalData,
                "Base64 encode/decode should round-trip correctly")
    }

    @Test("base64 string contains only valid characters")
    func base64EncodingContainsOnlyValidCharacters() {
        let originalData = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])
        let base64String = originalData.base64EncodedString()

        let validBase64 = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        for char in base64String.unicodeScalars {
            #expect(validBase64.contains(char),
                    "Character '\(char)' should be valid base64")
        }
    }

    // MARK: - Size Limit Logic

    @Test("5MB size limit is correct value")
    func sizeLimitFiveMBIsCorrectValue() {
        let fiveMB = 5 * 1024 * 1024
        #expect(fiveMB == 5_242_880, "5MB should be 5,242,880 bytes")
    }

    @Test("small data passes size check")
    func sizeLimitSmallDataPassesCheck() {
        let smallData = Data(repeating: 0xAA, count: 1024) // 1KB
        let base64Data = smallData.base64EncodedData()
        #expect(base64Data.count <= 5 * 1024 * 1024,
                "1KB data base64 should be well under 5MB limit")
    }

    // MARK: - Error Description Content

    @Test("windowCaptureFailed description contains window ID")
    func screenshotErrorWindowCaptureFailedContainsWindowId() {
        let error = ScreenshotError.windowCaptureFailed(windowId: 999)
        let desc = error.errorDescription
        #expect(desc != nil)
        #expect(desc!.contains("999"), "Description should contain window ID")
    }

    @Test("screenshotTooLarge description contains size")
    func screenshotErrorScreenshotTooLargeContainsSize() {
        let size = 7 * 1024 * 1024
        let error = ScreenshotError.screenshotTooLarge(sizeBytes: size)
        let desc = error.errorDescription
        #expect(desc != nil)
        #expect(desc!.contains(String(size)), "Description should contain size in bytes")
    }

    @Test("imageConversionFailed description")
    func screenshotErrorImageConversionFailedDescription() {
        let error = ScreenshotError.imageConversionFailed
        #expect(error.errorDescription == "Failed to convert screenshot image to JPEG")
    }

    @Test("fullScreenCaptureFailed description")
    func screenshotErrorFullScreenCaptureFailedDescription() {
        let error = ScreenshotError.fullScreenCaptureFailed
        #expect(error.errorDescription == "Failed to capture full screen")
    }

    // MARK: - Error Suggestions

    @Test("suggestions are not empty")
    func screenshotErrorSuggestionsNotEmpty() {
        #expect(!ScreenshotError.windowCaptureFailed(windowId: 1).suggestion.isEmpty)
        #expect(!ScreenshotError.fullScreenCaptureFailed.suggestion.isEmpty)
        #expect(!ScreenshotError.imageConversionFailed.suggestion.isEmpty)
        #expect(!ScreenshotError.screenshotTooLarge(sizeBytes: 1).suggestion.isEmpty)
    }

    @Test("windowCaptureFailed suggests list_windows")
    func screenshotErrorWindowCaptureFailedSuggestsListWindows() {
        let error = ScreenshotError.windowCaptureFailed(windowId: 1)
        #expect(error.suggestion.contains("list_windows"))
    }

    @Test("fullScreenCaptureFailed suggests permission")
    func screenshotErrorFullScreenCaptureFailedSuggestsPermission() {
        let error = ScreenshotError.fullScreenCaptureFailed
        #expect(error.suggestion.contains("screen recording"))
    }

    @Test("screenshotTooLarge suggests window capture")
    func screenshotErrorScreenshotTooLargeSuggestsWindowCapture() {
        let error = ScreenshotError.screenshotTooLarge(sizeBytes: 9999999)
        #expect(error.suggestion.lowercased().contains("window"))
    }

    // MARK: - Error Codes Distinct

    @Test("all error codes are distinct")
    func screenshotErrorAllErrorCodesDistinct() {
        let codes = [
            ScreenshotError.windowCaptureFailed(windowId: 1).errorCode,
            ScreenshotError.fullScreenCaptureFailed.errorCode,
            ScreenshotError.imageConversionFailed.errorCode,
            ScreenshotError.screenshotTooLarge(sizeBytes: 1).errorCode,
        ]
        #expect(Set(codes).count == codes.count, "All error codes should be distinct")
    }
}
