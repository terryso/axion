import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit

private final class ScreenshotCaptureResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<CGImage, Error>?

    func set(_ result: Result<CGImage, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() -> Result<CGImage, Error>? {
        lock.lock()
        let result = self.result
        lock.unlock()
        return result
    }
}

/// Errors thrown by `ScreenshotService`.
enum ScreenshotError: Error, LocalizedError, ToolErrorProtocol {
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
        let image = try captureWindowImage(windowId: CGWindowID(windowId))
        return try captureWithSizeLimit(image: image)
    }

    func captureFullScreen() throws -> String {
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
            throw ScreenshotError.fullScreenCaptureFailed
        }
        return try captureWithSizeLimit(image: image)
    }

    // MARK: - Private Helpers

    private func captureWindowImage(windowId: CGWindowID) throws -> CGImage {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = ScreenshotCaptureResultBox()

        _Concurrency.Task {
            do {
                let content = try await SCShareableContent.current
                guard let window = content.windows.first(where: { $0.windowID == windowId }) else {
                    throw ScreenshotError.windowCaptureFailed(windowId: Int(windowId))
                }
                let image = try await captureWindowImage(window)
                resultBox.set(.success(image))
            } catch {
                resultBox.set(.failure(error))
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + 10) == .success else {
            throw ScreenshotError.windowCaptureFailed(windowId: Int(windowId))
        }

        switch resultBox.get() {
        case .success(let image):
            return image
        case .failure(let error):
            throw error
        case nil:
            throw ScreenshotError.windowCaptureFailed(windowId: Int(windowId))
        }
    }

    private func captureWindowImage(_ window: SCWindow) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            let windowId = window.windowID
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(window.frame.width))
            configuration.height = max(1, Int(window.frame.height))
            configuration.showsCursor = false

            SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(
                        throwing: ScreenshotError.windowCaptureFailed(windowId: Int(windowId))
                    )
                }
            }
        }
    }

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
