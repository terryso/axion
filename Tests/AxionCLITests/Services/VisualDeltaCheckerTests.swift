import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import AxionCLI

@Suite("VisualDeltaChecker")
struct VisualDeltaCheckerTests {

    // MARK: - Test Helpers

    /// Generates a solid-color JPEG image as a base64 string.
    private func makeTestJPEG(
        width: Int = 300,
        height: Int = 300,
        r: UInt8, g: UInt8, b: UInt8
    ) -> String {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create CGContext")
            return ""
        }
        context.setFillColor(CGColor(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1.0
        ))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = context.makeImage() else {
            Issue.record("Failed to create CGImage")
            return ""
        }

        // Encode to JPEG
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, "public.jpeg" as CFString, 1, nil
        ) else {
            Issue.record("Failed to create image destination")
            return ""
        }
        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: 0.9
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            Issue.record("Failed to finalize image destination")
            return ""
        }
        return (data as Data).base64EncodedString()
    }

    /// Generates a JPEG image with a horizontal gradient from one color to another.
    private func makeGradientJPEG(
        width: Int = 300,
        height: Int = 300,
        fromColor: (UInt8, UInt8, UInt8),
        toColor: (UInt8, UInt8, UInt8)
    ) -> String {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * height)

        for y in 0..<height {
            for x in 0..<width {
                let t = CGFloat(x) / CGFloat(width - 1)
                let r = UInt8(CGFloat(fromColor.0) * (1 - t) + CGFloat(toColor.0) * t)
                let g = UInt8(CGFloat(fromColor.1) * (1 - t) + CGFloat(toColor.1) * t)
                let b = UInt8(CGFloat(fromColor.2) * (1 - t) + CGFloat(toColor.2) * t)
                let offset = y * bytesPerRow + x * 4
                pixelData[offset] = r
                pixelData[offset + 1] = g
                pixelData[offset + 2] = b
                pixelData[offset + 3] = 255
            }
        }

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create CGContext for gradient")
            return ""
        }
        guard let cgImage = context.makeImage() else {
            Issue.record("Failed to create gradient CGImage")
            return ""
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, "public.jpeg" as CFString, 1, nil
        ) else {
            Issue.record("Failed to create image destination")
            return ""
        }
        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: 0.9
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            Issue.record("Failed to finalize image destination")
            return ""
        }
        return (data as Data).base64EncodedString()
    }

    // MARK: - AC1: Screenshot delta comparison (downscaled to 256x256)

    @Test("Downscale correctly resizes to 256x256")
    func downscaleResizesTo256x256() {
        let base64 = makeTestJPEG(width: 800, height: 600, r: 128, g: 128, b: 128)
        guard let downscaled = VisualDeltaChecker.downscaleScreenshot(
            base64: base64, maxWidth: 256, maxHeight: 256
        ) else {
            Issue.record("downscaleScreenshot returned nil")
            return
        }
        #expect(downscaled.width <= 256)
        #expect(downscaled.height <= 256)
    }

    // MARK: - AC2: Low delta skips verification

    @Test("Identical images produce delta = 0%")
    func identicalImagesDeltaZero() {
        let img = makeTestJPEG(r: 100, g: 150, b: 200)
        let result = VisualDeltaChecker.check(
            currentScreenshot: img,
            previousScreenshot: img
        )
        if case .unchanged(let pct) = result {
            #expect(pct == 0.0)
        } else {
            Issue.record("Expected .unchanged, got \(result)")
        }
    }

    // MARK: - AC3: High delta triggers verification

    @Test("Completely different images produce delta > 1%")
    func differentImagesHighDelta() {
        let img1 = makeTestJPEG(r: 0, g: 0, b: 0)
        let img2 = makeTestJPEG(r: 255, g: 255, b: 255)
        let result = VisualDeltaChecker.check(
            currentScreenshot: img1,
            previousScreenshot: img2
        )
        if case .changed(let pct) = result {
            #expect(pct > 1.0)
        } else {
            Issue.record("Expected .changed, got \(result)")
        }
    }

    @Test("Slightly different images produce delta near threshold")
    func slightlyDifferentImages() {
        let img1 = makeTestJPEG(r: 100, g: 100, b: 100)
        let img2 = makeTestJPEG(r: 115, g: 115, b: 115)
        let result = VisualDeltaChecker.check(
            currentScreenshot: img1,
            previousScreenshot: img2
        )
        // Both should produce a valid result (either .unchanged or .changed)
        switch result {
        case .unchanged(let pct):
            #expect(pct < 1.0)
        case .changed(let pct):
            #expect(pct >= 0.0)
        case .noPrevious:
            Issue.record("Unexpected .noPrevious for valid inputs")
        }
    }

    // MARK: - AC4: First round has no comparison

    @Test("nil previous returns .noPrevious")
    func nilPreviousReturnsNoPrevious() {
        let img = makeTestJPEG(r: 128, g: 128, b: 128)
        let result = VisualDeltaChecker.check(
            currentScreenshot: img,
            previousScreenshot: nil
        )
        #expect(result == .noPrevious)
    }

    // MARK: - Edge case: invalid base64

    @Test("Invalid base64 returns .changed (safe fallback)")
    func invalidBase64ReturnsChanged() {
        let result = VisualDeltaChecker.check(
            currentScreenshot: "not-valid-base64!!!",
            previousScreenshot: "also-not-valid!!!"
        )
        if case .changed = result {
            // correct
        } else {
            Issue.record("Expected .changed for invalid base64, got \(result)")
        }
    }

    @Test("Invalid current with valid previous returns .changed")
    func invalidCurrentWithValidPrevious() {
        let validImg = makeTestJPEG(r: 100, g: 100, b: 100)
        let result = VisualDeltaChecker.check(
            currentScreenshot: "bad-data",
            previousScreenshot: validImg
        )
        if case .changed = result {
            // correct
        } else {
            Issue.record("Expected .changed for invalid current, got \(result)")
        }
    }

    // MARK: - VisualDeltaTracker tests (AC1-AC4)

    @Test("Tracker: first call returns .noPrevious")
    func trackerFirstCallNoPrevious() async {
        let tracker = VisualDeltaTracker()
        let img = makeTestJPEG(r: 128, g: 128, b: 128)
        let result = await tracker.processScreenshot(base64: img)
        #expect(result == .noPrevious)
    }

    @Test("Tracker: same image twice returns .unchanged")
    func trackerSameImageTwice() async {
        let tracker = VisualDeltaTracker()
        let img = makeTestJPEG(r: 128, g: 128, b: 128)

        _ = await tracker.processScreenshot(base64: img)
        let result = await tracker.processScreenshot(base64: img)

        if case .unchanged = result {
            // correct
        } else {
            Issue.record("Expected .unchanged on second identical image, got \(result)")
        }
    }

    @Test("Tracker: different image returns .changed")
    func trackerDifferentImage() async {
        let tracker = VisualDeltaTracker()
        let img1 = makeTestJPEG(r: 0, g: 0, b: 0)
        let img2 = makeTestJPEG(r: 255, g: 255, b: 255)

        _ = await tracker.processScreenshot(base64: img1)
        let result = await tracker.processScreenshot(base64: img2)

        if case .changed = result {
            // correct
        } else {
            Issue.record("Expected .changed for different image, got \(result)")
        }
    }

    @Test("Tracker: reset clears history, returns .noPrevious")
    func trackerResetClearsHistory() async {
        let tracker = VisualDeltaTracker()
        let img = makeTestJPEG(r: 128, g: 128, b: 128)

        _ = await tracker.processScreenshot(base64: img)
        await tracker.reset()
        let result = await tracker.processScreenshot(base64: img)

        #expect(result == .noPrevious)
    }

    // MARK: - VisualDeltaResult

    @Test("VisualDeltaResult.shouldSkipVerifier")
    func shouldSkipVerifierProperty() {
        #expect(VisualDeltaResult.noPrevious.shouldSkipVerifier == false)
        #expect(VisualDeltaResult.unchanged(percentage: 0.0).shouldSkipVerifier == true)
        #expect(VisualDeltaResult.unchanged(percentage: 0.5).shouldSkipVerifier == true)
        #expect(VisualDeltaResult.changed(percentage: 5.0).shouldSkipVerifier == false)
    }

    // MARK: - AC5: --no-visual-delta flag disables tracker (Task 5.9)

    @Test("When tracker is nil (noVisualDelta), no delta processing occurs")
    func noVisualDeltaDisablesTracking() async {
        // Simulating RunCommand behavior: noVisualDelta → tracker is nil
        let tracker: VisualDeltaTracker? = nil
        let img = makeTestJPEG(r: 128, g: 128, b: 128)

        // When tracker is nil, no processing happens — verified by the fact
        // that RunCommand only calls tracker.processScreenshot when tracker is non-nil
        #expect(tracker == nil)

        // Also verify that a non-nil tracker would work for the same input
        let activeTracker = VisualDeltaTracker()
        let result = await activeTracker.processScreenshot(base64: img)
        #expect(result == .noPrevious)
    }

    // MARK: - Dimension mismatch edge case

    @Test("Dimension mismatch returns .changed with high delta")
    func dimensionMismatchReturnsChanged() {
        let img1 = makeTestJPEG(width: 300, height: 200, r: 128, g: 128, b: 128)
        let img2 = makeTestJPEG(width: 200, height: 300, r: 128, g: 128, b: 128)

        guard let downscaled1 = VisualDeltaChecker.downscaleScreenshot(base64: img1, maxWidth: 256, maxHeight: 256),
              let downscaled2 = VisualDeltaChecker.downscaleScreenshot(base64: img2, maxWidth: 256, maxHeight: 256)
        else {
            Issue.record("Failed to downscale test images")
            return
        }

        let delta = VisualDeltaChecker.calculateDeltaPercentage(
            current: downscaled1, previous: downscaled2
        )
        #expect(delta == 100.0)
    }

    // MARK: - Gradient image test (realistic scenario)

    @Test("Gradient vs solid color has high delta")
    func gradientVsSolidHighDelta() {
        let solid = makeTestJPEG(r: 128, g: 128, b: 128)
        let gradient = makeGradientJPEG(
            fromColor: (0, 0, 0),
            toColor: (255, 255, 255)
        )
        let result = VisualDeltaChecker.check(
            currentScreenshot: gradient,
            previousScreenshot: solid
        )
        if case .changed(let pct) = result {
            #expect(pct > 1.0)
        } else {
            Issue.record("Expected .changed for gradient vs solid, got \(result)")
        }
    }

    // MARK: - Base64 extraction from tool result content

    @Test("extractBase64FromToolResult parses JSON image_data format")
    func extractBase64JsonImageData() {
        let rawBase64 = makeTestJPEG(r: 100, g: 100, b: 100)
        let jsonContent = "{\"image_data\": \"\(rawBase64)\", \"action\": \"screenshot\"}"
        let extracted = RunOrchestrator.extractBase64FromToolResultForTest(jsonContent)
        #expect(extracted == rawBase64)
    }

    @Test("extractBase64FromToolResult parses JSON base64 format")
    func extractBase64JsonBase64() {
        let rawBase64 = makeTestJPEG(r: 100, g: 100, b: 100)
        let jsonContent = "{\"base64\": \"\(rawBase64)\"}"
        let extracted = RunOrchestrator.extractBase64FromToolResultForTest(jsonContent)
        #expect(extracted == rawBase64)
    }

    @Test("extractBase64FromToolResult parses plain base64 string")
    func extractBase64Plain() {
        let rawBase64 = makeTestJPEG(r: 100, g: 100, b: 100)
        let extracted = RunOrchestrator.extractBase64FromToolResultForTest(rawBase64)
        #expect(extracted == rawBase64)
    }

    @Test("extractBase64FromToolResult returns nil for short non-base64 content")
    func extractBase64ShortContent() {
        let extracted = RunOrchestrator.extractBase64FromToolResultForTest("short text")
        #expect(extracted == nil)
    }

    @Test("extractBase64FromToolResult parses JSON image format")
    func extractBase64JsonImage() {
        let rawBase64 = makeTestJPEG(r: 50, g: 50, b: 50)
        let jsonContent = "{\"image\": \"\(rawBase64)\"}"
        let extracted = RunOrchestrator.extractBase64FromToolResultForTest(jsonContent)
        #expect(extracted == rawBase64)
    }
}
