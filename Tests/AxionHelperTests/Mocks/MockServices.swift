import Foundation
@testable import AxionHelper

/// Mock implementation of `AppLaunching` for unit testing.
struct MockAppLauncher: @unchecked Sendable, AppLaunching {
    var launchAppHandler: @Sendable (String) async throws -> AppInfo
    var listRunningAppsHandler: @Sendable () -> [AppInfo]

    func launchApp(name: String) async throws -> AppInfo {
        try await launchAppHandler(name)
    }

    func listRunningApps() -> [AppInfo] {
        listRunningAppsHandler()
    }
}

/// Mock implementation of `WindowManaging` for unit testing.
struct MockAccessibilityEngine: @unchecked Sendable, WindowManaging {
    var listWindowsHandler: @Sendable (Int32?) -> [WindowInfo]
    var getWindowStateHandler: @Sendable (Int) throws -> WindowState
    var getAXTreeHandler: @Sendable (Int, Int) throws -> AXElement
    var activateWindowHandler: @Sendable (Int32, Int?) throws -> Void = { _, _ in }
    var validateWindowHandler: @Sendable (Int) -> ValidateWindowResult = { windowId in
        ValidateWindowResult(windowId: windowId, exists: true, actionable: true, title: nil, pid: nil, reason: nil)
    }

    func listWindows(pid: Int32?) -> [WindowInfo] {
        listWindowsHandler(pid)
    }

    func getWindowState(windowId: Int) throws -> WindowState {
        try getWindowStateHandler(windowId)
    }

    func getAXTree(windowId: Int, maxNodes: Int) throws -> AXElement {
        try getAXTreeHandler(windowId, maxNodes)
    }

    func activateWindow(pid: Int32, windowId: Int?) throws {
        try activateWindowHandler(pid, windowId)
    }

    func validateWindow(windowId: Int) -> ValidateWindowResult {
        validateWindowHandler(windowId)
    }

    var resolveSelectorHandler: @Sendable (Int, SelectorQuery) throws -> AccessibilityEngineService.SelectorMatchResult = { _, _ in
        AccessibilityEngineService.SelectorMatchResult(x: 50, y: 50, role: "AXButton", title: "Mock")
    }

    func resolveSelector(windowId: Int, query: SelectorQuery) throws -> AccessibilityEngineService.SelectorMatchResult {
        try resolveSelectorHandler(windowId, query)
    }

    var setWindowBoundsHandler: @Sendable (Int, Int?, Int?, Int?, Int?) throws -> Void = { _, _, _, _, _ in }

    func setWindowBounds(windowId: Int, x: Int?, y: Int?, width: Int?, height: Int?) throws {
        try setWindowBoundsHandler(windowId, x, y, width, height)
    }
}

/// Mock implementation of `ScreenshotCapturing` for unit testing.
struct MockScreenshotCapture: @unchecked Sendable, ScreenshotCapturing {
    var captureWindowHandler: @Sendable (Int) throws -> String
    var captureFullScreenHandler: @Sendable () throws -> String

    func captureWindow(windowId: Int) throws -> String {
        try captureWindowHandler(windowId)
    }

    func captureFullScreen() throws -> String {
        try captureFullScreenHandler()
    }
}

/// Mock implementation of `URLOpening` for unit testing.
struct MockURLOpener: @unchecked Sendable, URLOpening {
    var openURLHandler: @Sendable (String) throws -> Void

    func openURL(_ urlString: String) throws {
        try openURLHandler(urlString)
    }
}

/// Mock implementation of `InputSimulating` for unit testing.
struct MockInputSimulation: @unchecked Sendable, InputSimulating {
    var clickHandler: @Sendable (Int, Int) throws -> Void
    var doubleClickHandler: @Sendable (Int, Int) throws -> Void
    var rightClickHandler: @Sendable (Int, Int) throws -> Void
    var scrollHandler: @Sendable (String, Int) throws -> Void
    var dragHandler: @Sendable (Int, Int, Int, Int) throws -> Void
    var typeTextHandler: @Sendable (String) throws -> Void
    var pressKeyHandler: @Sendable (String) throws -> Void
    var hotkeyHandler: @Sendable (String) throws -> Void

    func click(x: Int, y: Int) throws {
        try clickHandler(x, y)
    }

    func doubleClick(x: Int, y: Int) throws {
        try doubleClickHandler(x, y)
    }

    func rightClick(x: Int, y: Int) throws {
        try rightClickHandler(x, y)
    }

    func scroll(direction: String, amount: Int) throws {
        try scrollHandler(direction, amount)
    }

    func drag(fromX: Int, fromY: Int, toX: Int, toY: Int) throws {
        try dragHandler(fromX, fromY, toX, toY)
    }

    func typeText(_ text: String) throws {
        try typeTextHandler(text)
    }

    func pressKey(_ key: String) throws {
        try pressKeyHandler(key)
    }

    func hotkey(_ keys: String) throws {
        try hotkeyHandler(keys)
    }
}

/// Saves and restores `ServiceContainer.shared` around a test.
/// Usage: `let restore = ServiceContainerFixture.apply(…); defer { restore() }`
enum ServiceContainerFixture {

    /// Temporarily replaces `ServiceContainer.shared` with mock services.
    static func apply(
        appLauncher: (any AppLaunching)? = nil,
        accessibilityEngine: (any WindowManaging)? = nil,
        inputSimulation: (any InputSimulating)? = nil,
        screenshotCapture: (any ScreenshotCapturing)? = nil,
        urlOpener: (any URLOpening)? = nil,
        eventRecorder: (any EventRecording)? = nil
    ) -> @Sendable () -> Void {
        let original = ServiceContainer.shared
        ServiceContainer.shared = ServiceContainer(
            appLauncher: appLauncher ?? original.appLauncher,
            accessibilityEngine: accessibilityEngine ?? original.accessibilityEngine,
            inputSimulation: inputSimulation ?? original.inputSimulation,
            screenshotCapture: screenshotCapture ?? original.screenshotCapture,
            urlOpener: urlOpener ?? original.urlOpener,
            eventRecorder: eventRecorder ?? original.eventRecorder
        )
        return { ServiceContainer.shared = original }
    }
}
