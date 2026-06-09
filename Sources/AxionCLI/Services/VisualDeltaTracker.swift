import CoreGraphics
import Foundation
import ImageIO

// MARK: - VisualDeltaResult

/// Result of comparing two screenshots for visual changes.
enum VisualDeltaResult: Sendable, Equatable {
    case noPrevious
    case unchanged(percentage: Double)
    case changed(percentage: Double)

    var shouldSkipVerifier: Bool {
        if case .unchanged = self { return true }
        return false
    }
}

// MARK: - VisualDeltaChecker

/// Pure-stateless struct that performs pixel-level screenshot comparison.
/// Screenshots are downscaled to 256x256 before comparing to keep latency < 50ms (NFR37).
struct VisualDeltaChecker {

    /// Threshold below which the screen is considered unchanged.
    static let deltaThreshold: Double = 1.0

    /// Luminance difference threshold per pixel (out of 255).
    private static let luminanceThreshold: UInt8 = 10

    // MARK: - Public API

    /// Compare current screenshot against a previous one.
    /// Returns `.noPrevious` if `previousScreenshot` is nil.
    /// Returns `.changed` on any decode/processing failure (safe fallback).
    static func check(
        currentScreenshot: String,
        previousScreenshot: String?
    ) -> VisualDeltaResult {
        guard let previous = previousScreenshot else {
            return .noPrevious
        }

        guard let currentDownscaled = downscaleScreenshot(
            base64: currentScreenshot, maxWidth: 256, maxHeight: 256
        ) else {
            return .changed(percentage: 100.0)
        }

        guard let previousDownscaled = downscaleScreenshot(
            base64: previous, maxWidth: 256, maxHeight: 256
        ) else {
            return .changed(percentage: 100.0)
        }

        // Fast path: hash comparison for identical images
        let currentHash = hashPixels(of: currentDownscaled)
        let previousHash = hashPixels(of: previousDownscaled)
        if currentHash == previousHash {
            return .unchanged(percentage: 0.0)
        }

        let percentage = calculateDeltaPercentage(
            current: currentDownscaled,
            previous: previousDownscaled
        )

        if percentage < deltaThreshold {
            return .unchanged(percentage: percentage)
        } else {
            return .changed(percentage: percentage)
        }
    }

    /// Downscale a base64 JPEG image to fit within maxWidth x maxHeight while
    /// preserving aspect ratio. Returns nil on decode failure.
    static func downscaleScreenshot(
        base64: String,
        maxWidth: Int = 256,
        maxHeight: Int = 256
    ) -> CGImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let srcWidth = CGFloat(image.width)
        let srcHeight = CGFloat(image.height)
        let scaleX = CGFloat(maxWidth) / srcWidth
        let scaleY = CGFloat(maxHeight) / srcHeight
        let scale = min(scaleX, scaleY, 1.0) // never upscale

        let newWidth = Int(srcWidth * scale)
        let newHeight = Int(srcHeight * scale)

        guard newWidth > 0, newHeight > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = CGInterpolationQuality.high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    // MARK: - Internal (testable)

    /// Extract RGBA pixel data from a CGImage.
    static func computePixelData(cgImage: CGImage) -> [UInt8]? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * height)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelData
    }

    /// Calculate pixel-level delta percentage using luminance comparison.
    /// `L = 0.299*R + 0.587*G + 0.114*B`; a pixel is "different" if its
    /// luminance changes by more than `luminanceThreshold`.
    static func calculateDeltaPercentage(
        current: CGImage,
        previous: CGImage
    ) -> Double {
        guard let currentData = computePixelData(cgImage: current),
              let previousData = computePixelData(cgImage: previous)
        else { return 100.0 }

        // Dimension mismatch → images are fundamentally different
        guard current.width == previous.width, current.height == previous.height else {
            return 100.0
        }

        let totalPixels = current.width * current.height
        guard totalPixels > 0 else { return 0.0 }

        var diffCount = 0
        let threshold = Int(luminanceThreshold)
        for i in stride(from: 0, to: currentData.count, by: 4) {
            let r1 = currentData[i], g1 = currentData[i + 1], b1 = currentData[i + 2]
            let r2 = previousData[i], g2 = previousData[i + 1], b2 = previousData[i + 2]

            let dr1 = Double(r1), dg1 = Double(g1), db1 = Double(b1)
            let dr2 = Double(r2), dg2 = Double(g2), db2 = Double(b2)
            let l1 = Int(0.299 * dr1 + 0.587 * dg1 + 0.114 * db1)
            let l2 = Int(0.299 * dr2 + 0.587 * dg2 + 0.114 * db2)

            if abs(l1 - l2) > threshold {
                diffCount += 1
            }
        }

        return Double(diffCount) / Double(totalPixels) * 100.0
    }

    // MARK: - Private

    private static func hashPixels(of image: CGImage) -> Int {
        guard let data = computePixelData(cgImage: image) else { return 0 }
        var hasher = Hasher()
        data.withUnsafeBytes { ptr in
            hasher.combine(bytes: ptr)
        }
        return hasher.finalize()
    }
}

// MARK: - VisualDeltaTracker

/// Actor that tracks the last screenshot hash across an agent run.
/// On each call to `processScreenshot`, it compares the current screenshot
/// against the stored one and updates the stored hash.
actor VisualDeltaTracker {

    private var lastScreenshotBase64: String?

    /// Compare the current screenshot against the stored previous one,
    /// then update the stored value. Returns the delta result.
    func processScreenshot(base64: String) -> VisualDeltaResult {
        let result = VisualDeltaChecker.check(
            currentScreenshot: base64,
            previousScreenshot: lastScreenshotBase64
        )
        lastScreenshotBase64 = base64
        return result
    }

    /// Clear stored state (e.g. at the start of a new run).
    func reset() {
        lastScreenshotBase64 = nil
    }
}
