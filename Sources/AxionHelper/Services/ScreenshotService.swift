import CoreGraphics
import Foundation
import ImageIO

/// Errors thrown by `ScreenshotService`.
enum ScreenshotError: Error, LocalizedError {
    case windowCaptureFailed(windowId: Int)
    case fullScreenCaptureFailed
    case imageConversionFailed
    case screenshotTooLarge(sizeBytes: Int)

    var errorDescription: String? {
        switch self {
        case .windowCaptureFailed(let windowId):
            return "Failed to capture window with id \(windowId)"
        case .fullScreenCaptureFailed:
            return "Failed to capture full screen"
        case .imageConversionFailed:
            return "Failed to convert screenshot image to JPEG"
        case .screenshotTooLarge(let sizeBytes):
            return "Screenshot exceeds 5MB limit (\(sizeBytes) bytes)"
        }
    }

    var errorCode: String {
        switch self {
        case .windowCaptureFailed:
            return "window_capture_failed"
        case .fullScreenCaptureFailed:
            return "fullscreen_capture_failed"
        case .imageConversionFailed:
            return "image_conversion_failed"
        case .screenshotTooLarge:
            return "screenshot_too_large"
        }
    }

    var suggestion: String {
        switch self {
        case .windowCaptureFailed:
            return "Use list_windows to get valid window IDs. Ensure screen recording permission is granted."
        case .fullScreenCaptureFailed:
            return "Ensure screen recording permission is granted in System Settings > Privacy & Security."
        case .imageConversionFailed:
            return "Try capturing a different window or reduce screen resolution."
        case .screenshotTooLarge:
            return "The screenshot is too large. Try capturing a specific window instead of full screen."
        }
    }
}

/// Service that captures screenshots using macOS CoreGraphics APIs.
struct ScreenshotService: ScreenshotCapturing {

    private static let maxSizeBytes = 5 * 1024 * 1024 // 5MB

    func captureWindow(windowId: Int) throws -> String {
        let windowIdCG = CGWindowID(windowId)
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowIdCG,
            [.bestResolution]
        ) else {
            throw ScreenshotError.windowCaptureFailed(windowId: windowId)
        }
        return try captureWithSizeLimit(image: image)
    }

    func captureFullScreen() throws -> String {
        guard let image = CGWindowListCreateImage(
            CGDisplayBounds(CGMainDisplayID()),
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            throw ScreenshotError.fullScreenCaptureFailed
        }
        return try captureWithSizeLimit(image: image)
    }

    // MARK: - Private Helpers

    private func captureWithSizeLimit(image: CGImage) throws -> String {
        // First attempt: high quality JPEG
        var data = try imageToJPEGData(image, compressionQuality: 0.8)
        var base64Data = data.base64EncodedData()

        if base64Data.count <= Self.maxSizeBytes {
            return data.base64EncodedString()
        }

        // Second attempt: lower quality
        data = try imageToJPEGData(image, compressionQuality: 0.5)
        base64Data = data.base64EncodedData()

        if base64Data.count <= Self.maxSizeBytes {
            return data.base64EncodedString()
        }

        // Third attempt: scale down resolution
        let scale: CGFloat = 0.5
        let newWidth = Int(CGFloat(image.width) * scale)
        let newHeight = Int(CGFloat(image.height) * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: newWidth, height: newHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScreenshotError.imageConversionFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        guard let resizedImage = context.makeImage() else {
            throw ScreenshotError.imageConversionFailed
        }
        data = try imageToJPEGData(resizedImage, compressionQuality: 0.6)
        base64Data = data.base64EncodedData()

        if base64Data.count <= Self.maxSizeBytes {
            return data.base64EncodedString()
        }

        throw ScreenshotError.screenshotTooLarge(sizeBytes: base64Data.count)
    }

    private func imageToJPEGData(_ image: CGImage, compressionQuality: CGFloat = 0.8) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, "public.jpeg" as CFString, 1, nil
        ) else {
            throw ScreenshotError.imageConversionFailed
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotError.imageConversionFailed
        }
        return data as Data
    }
}
