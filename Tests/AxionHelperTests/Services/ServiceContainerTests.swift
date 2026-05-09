import XCTest
@testable import AxionHelper

final class ServiceContainerTests: XCTestCase {

    // MARK: - Shared Instance

    func test_shared_isInitialized() {
        let container = ServiceContainer.shared
        XCTAssertNotNil(container as Any, "ServiceContainer.shared should be initialized")
    }

    func test_shared_hasAppLauncher() {
        let _ = ServiceContainer.shared.appLauncher
    }

    func test_shared_hasAccessibilityEngine() {
        let _ = ServiceContainer.shared.accessibilityEngine
    }

    func test_shared_hasInputSimulation() {
        let _ = ServiceContainer.shared.inputSimulation
    }

    func test_shared_hasScreenshotCapture() {
        let _ = ServiceContainer.shared.screenshotCapture
    }

    func test_shared_hasURLOpener() {
        let _ = ServiceContainer.shared.urlOpener
    }

    // MARK: - ServiceContainerFixture

    func test_fixture_applyAndRestore() {
        let original = ServiceContainer.shared

        let mockLauncher = MockAppLauncher(
            launchAppHandler: { _ in fatalError("test") },
            listRunningAppsHandler: { [] }
        )
        let restore = ServiceContainerFixture.apply(appLauncher: mockLauncher)
        XCTAssertFalse(ServiceContainer.shared.appLauncher is AppLauncherService,
                       "After apply, appLauncher should be mock")

        restore()

        // Verify original is restored
        let restoredLauncher = ServiceContainer.shared.appLauncher
        XCTAssertTrue(type(of: restoredLauncher) == type(of: original.appLauncher),
                       "After restore, appLauncher should be original type")
    }

    func test_fixture_partialOverride_keepsOthers() {
        let original = ServiceContainer.shared

        let mockURLOpener = MockURLOpener(openURLHandler: { _ in })
        let restore = ServiceContainerFixture.apply(urlOpener: mockURLOpener)

        // URL opener is mocked
        XCTAssertFalse(ServiceContainer.shared.urlOpener is URLOpenerService)
        // Others remain original
        XCTAssertTrue(type(of: ServiceContainer.shared.appLauncher) == type(of: original.appLauncher))

        restore()
    }

    func test_fixture_fullOverride() {
        let restore = ServiceContainerFixture.apply(
            appLauncher: MockAppLauncher(
                launchAppHandler: { _ in AppInfo(pid: 1, appName: "Test", bundleId: nil) },
                listRunningAppsHandler: { [] }
            ),
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in
                    WindowState(windowId: 1, pid: 1, title: nil,
                               bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0),
                               isMinimized: false, isFocused: false, axTree: nil)
                },
                getAXTreeHandler: { _, _ in
                    AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: [])
                }
            ),
            inputSimulation: MockInputSimulation(
                clickHandler: { _, _ in },
                doubleClickHandler: { _, _ in },
                rightClickHandler: { _, _ in },
                scrollHandler: { _, _ in },
                dragHandler: { _, _, _, _ in },
                typeTextHandler: { _ in },
                pressKeyHandler: { _ in },
                hotkeyHandler: { _ in }
            ),
            screenshotCapture: MockScreenshotCapture(
                captureWindowHandler: { _ in "" },
                captureFullScreenHandler: { "" }
            ),
            urlOpener: MockURLOpener(openURLHandler: { _ in })
        )
        defer { restore() }

        // All services should be mocks now
        XCTAssertTrue(ServiceContainer.shared.appLauncher is MockAppLauncher)
        XCTAssertTrue(ServiceContainer.shared.accessibilityEngine is MockAccessibilityEngine)
        XCTAssertTrue(ServiceContainer.shared.inputSimulation is MockInputSimulation)
        XCTAssertTrue(ServiceContainer.shared.screenshotCapture is MockScreenshotCapture)
        XCTAssertTrue(ServiceContainer.shared.urlOpener is MockURLOpener)
    }
}
