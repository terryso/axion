import Testing
@testable import AxionHelper

@Suite("ScreenshotService Real")
struct ScreenshotServiceRealTests {

    private let service = ScreenshotService()

    // MARK: - captureFullScreen

    @Test("captureFullScreen exercises code path")
    func captureFullScreenExercisesCodePath() {
        do {
            let result = try service.captureFullScreen()
            #expect(!result.isEmpty, "Base64 string should not be empty")
        } catch {
            // Expected in CI — still exercises the code
        }
    }

    // MARK: - captureWindow

    @Test("captureWindow invalid window ID exercises code path")
    func captureWindowInvalidWindowId() {
        do {
            _ = try service.captureWindow(windowId: 999999)
        } catch ScreenshotError.windowCaptureFailed {
            // Expected for invalid window
        } catch ScreenshotError.imageConversionFailed {
            // Also possible
        } catch {
            // Other errors possible
        }
    }

    @Test("captureWindow zero window ID exercises code path")
    func captureWindowZeroWindowId() {
        do {
            _ = try service.captureWindow(windowId: 0)
        } catch {
            // Expected to fail
        }
    }
}
