import Testing
@testable import AxionHelper

@Suite("ServiceContainer", .serialized)
struct ServiceContainerTests {

    // MARK: - Shared Instance

    @Test("shared is initialized")
    func sharedIsInitialized() {
        let container = ServiceContainer.shared
        #expect(container as Any != nil, "ServiceContainer.shared should be initialized")
    }

    @Test("shared has appLauncher")
    func sharedHasAppLauncher() {
        let _ = ServiceContainer.shared.appLauncher
    }

    @Test("shared has accessibilityEngine")
    func sharedHasAccessibilityEngine() {
        let _ = ServiceContainer.shared.accessibilityEngine
    }

    @Test("shared has inputSimulation")
    func sharedHasInputSimulation() {
        let _ = ServiceContainer.shared.inputSimulation
    }

    @Test("shared has screenshotCapture")
    func sharedHasScreenshotCapture() {
        let _ = ServiceContainer.shared.screenshotCapture
    }

    @Test("shared has urlOpener")
    func sharedHasURLOpener() {
        let _ = ServiceContainer.shared.urlOpener
    }

    // MARK: - ServiceContainerFixture

    @Test("fixture apply and restore")
    func fixtureApplyAndRestore() {
        let original = ServiceContainer.shared

        let mockLauncher = MockAppLauncher(
            launchAppHandler: { _ in fatalError("test") },
            listRunningAppsHandler: { [] }
        )
        let restore = ServiceContainerFixture.apply(appLauncher: mockLauncher)
        #expect(!(ServiceContainer.shared.appLauncher is AppLauncherService),
                "After apply, appLauncher should be mock")

        restore()

        let restoredLauncher = ServiceContainer.shared.appLauncher
        #expect(type(of: restoredLauncher) == type(of: original.appLauncher),
               "After restore, appLauncher should be original type")
    }

    @Test("fixture partial override keeps others")
    func fixturePartialOverrideKeepsOthers() {
        let original = ServiceContainer.shared

        let mockURLOpener = MockURLOpener(openURLHandler: { _ in })
        let restore = ServiceContainerFixture.apply(urlOpener: mockURLOpener)

        // URL opener is mocked
        #expect(!(ServiceContainer.shared.urlOpener is URLOpenerService))
        // Others remain original
        #expect(type(of: ServiceContainer.shared.appLauncher) == type(of: original.appLauncher))

        restore()
    }

    @Test("fixture full override")
    func fixtureFullOverride() {
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
        #expect(ServiceContainer.shared.appLauncher is MockAppLauncher)
        #expect(ServiceContainer.shared.accessibilityEngine is MockAccessibilityEngine)
        #expect(ServiceContainer.shared.inputSimulation is MockInputSimulation)
        #expect(ServiceContainer.shared.screenshotCapture is MockScreenshotCapture)
        #expect(ServiceContainer.shared.urlOpener is MockURLOpener)
    }
}
