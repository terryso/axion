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

    func listWindows(pid: Int32?) -> [WindowInfo] {
        listWindowsHandler(pid)
    }

    func getWindowState(windowId: Int) throws -> WindowState {
        try getWindowStateHandler(windowId)
    }
}

/// Saves and restores `ServiceContainer.shared` around a test.
/// Usage: `let restore = ServiceContainerFixture.apply(…); defer { restore() }`
enum ServiceContainerFixture {

    /// Temporarily replaces `ServiceContainer.shared` with mock services.
    static func apply(
        appLauncher: (any AppLaunching)? = nil,
        accessibilityEngine: (any WindowManaging)? = nil
    ) -> @Sendable () -> Void {
        let original = ServiceContainer.shared
        ServiceContainer.shared = ServiceContainer(
            appLauncher: appLauncher ?? original.appLauncher,
            accessibilityEngine: accessibilityEngine ?? original.accessibilityEngine
        )
        return { ServiceContainer.shared = original }
    }
}
