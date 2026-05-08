import Foundation

protocol ScreenshotCapturing: Sendable {
    func captureWindow(windowId: Int) throws -> String
    func captureFullScreen() throws -> String
}
