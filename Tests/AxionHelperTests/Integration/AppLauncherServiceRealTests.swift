import Testing
@testable import AxionHelper

@Suite("AppLauncherService Real")
struct AppLauncherServiceRealTests {

    private let service = AppLauncherService()

    // MARK: - listRunningApps

    @Test("listRunningApps returns non-empty array")
    func listRunningAppsReturnsNonEmptyArray() {
        let apps = service.listRunningApps()
        #expect(!apps.isEmpty, "Should return at least one running app")
    }

    @Test("listRunningApps each app has non-empty name")
    func listRunningAppsEachAppHasNonEmptyName() {
        let apps = service.listRunningApps()
        for app in apps {
            #expect(!app.appName.isEmpty, "Each app should have a non-empty name")
        }
    }

    @Test("listRunningApps each app has valid PID")
    func listRunningAppsEachAppHasValidPid() {
        let apps = service.listRunningApps()
        for app in apps {
            #expect(app.pid > 0, "Each app should have a valid PID")
        }
    }

    @Test("listRunningApps Finder is running")
    func listRunningAppsFinderIsRunning() {
        let apps = service.listRunningApps()
        let finderApps = apps.filter { $0.bundleId == "com.apple.finder" }
        #expect(!finderApps.isEmpty, "Finder should always be running on macOS")
    }

    @Test("listRunningApps has bundle IDs")
    func listRunningAppsHasBundleId() {
        let apps = service.listRunningApps()
        let withBundleId = apps.filter { $0.bundleId != nil }
        #expect(withBundleId.count > 0, "Most apps should have a bundle ID")
    }

    // MARK: - launchApp (already running apps)

    @Test("launchApp Finder already running returns existing info")
    func launchAppFinderAlreadyRunning() async throws {
        let info = try await service.launchApp(name: "Finder")
        #expect(info.pid > 0)
        #expect(info.bundleId != nil)
    }

    @Test("launchApp case insensitive finds running app")
    func launchAppCaseInsensitive() async throws {
        let info = try await service.launchApp(name: "finder")
        #expect(info.pid > 0)
    }

    @Test("launchApp with .app suffix finds running app")
    func launchAppWithAppSuffix() async throws {
        let info = try await service.launchApp(name: "Finder.app")
        #expect(info.pid > 0)
    }

    // MARK: - launchApp (app not found)

    @Test("launchApp non-existent app throws appNotFound")
    func launchAppNonExistentAppThrowsAppNotFound() async {
        do {
            _ = try await service.launchApp(name: "ThisAppDefinitelyDoesNotExist12345")
            Issue.record("Should throw appNotFound")
        } catch let error as AppLauncherError {
            if case .appNotFound = error {
                // expected
            } else {
                Issue.record("Expected appNotFound, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("launchApp non-existent app error has description")
    func launchAppNonExistentAppErrorHasDescription() async {
        do {
            _ = try await service.launchApp(name: "NoApp12345")
            Issue.record("Should throw")
        } catch let error as AppLauncherError {
            #expect(!(error.errorDescription?.isEmpty ?? true))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - launchApp (bundle ID lookup)

    @Test("launchApp with bundle ID launches system app")
    func launchAppWithBundleId() async throws {
        let info = try await service.launchApp(name: "com.apple.finder")
        #expect(info.pid > 0)
    }

    // MARK: - launchApp returns AppInfo with correct fields

    @Test("launchApp returns info with bundle ID")
    func launchAppReturnsInfoWithBundleId() async throws {
        let info = try await service.launchApp(name: "Finder")
        #expect(info.bundleId != nil)
    }
}
