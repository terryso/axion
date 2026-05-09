import XCTest
@testable import AxionHelper

/// Tests that directly call real AppLauncherService to maximize code coverage.
/// These exercise actual NSWorkspace/FileManager code paths on macOS.
final class AppLauncherServiceRealTests: XCTestCase {

    private let service = AppLauncherService()

    // MARK: - listRunningApps

    func test_listRunningApps_returnsNonEmptyArray() {
        let apps = service.listRunningApps()
        XCTAssertFalse(apps.isEmpty, "Should return at least one running app")
    }

    func test_listRunningApps_eachAppHasNonEmptyName() {
        let apps = service.listRunningApps()
        for app in apps {
            XCTAssertFalse(app.appName.isEmpty, "Each app should have a non-empty name")
        }
    }

    func test_listRunningApps_eachAppHasValidPid() {
        let apps = service.listRunningApps()
        for app in apps {
            XCTAssertGreaterThan(app.pid, 0, "Each app should have a valid PID")
        }
    }

    func test_listRunningApps_finderIsRunning() {
        let apps = service.listRunningApps()
        let finderApps = apps.filter { $0.bundleId == "com.apple.finder" }
        XCTAssertFalse(finderApps.isEmpty, "Finder should always be running on macOS")
    }

    func test_listRunningApps_hasBundleId() {
        let apps = service.listRunningApps()
        let withBundleId = apps.filter { $0.bundleId != nil }
        XCTAssertTrue(withBundleId.count > 0, "Most apps should have a bundle ID")
    }

    // MARK: - launchApp (already running apps)

    func test_launchApp_finderIsAlreadyRunning_returnsExistingInfo() async throws {
        let info = try await service.launchApp(name: "Finder")
        XCTAssertGreaterThan(info.pid, 0)
        XCTAssertNotNil(info.bundleId)
    }

    func test_launchApp_caseInsensitive_findsRunningApp() async throws {
        let info = try await service.launchApp(name: "finder")
        XCTAssertGreaterThan(info.pid, 0)
    }

    func test_launchApp_withAppSuffix_findsRunningApp() async throws {
        let info = try await service.launchApp(name: "Finder.app")
        XCTAssertGreaterThan(info.pid, 0)
    }

    // MARK: - launchApp (app not found)

    func test_launchApp_nonExistentApp_throwsAppNotFound() async {
        do {
            _ = try await service.launchApp(name: "ThisAppDefinitelyDoesNotExist12345")
            XCTFail("Should throw appNotFound")
        } catch let error as AppLauncherError {
            if case .appNotFound = error {
                // expected
            } else {
                XCTFail("Expected appNotFound, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_launchApp_nonExistentApp_errorHasDescription() async {
        do {
            _ = try await service.launchApp(name: "NoApp12345")
            XCTFail("Should throw")
        } catch let error as AppLauncherError {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - launchApp (bundle ID lookup)

    func test_launchApp_withBundleId_launchesSystemApp() async throws {
        // Use a bundle ID that exists on all macOS systems
        let info = try await service.launchApp(name: "com.apple.finder")
        XCTAssertGreaterThan(info.pid, 0)
    }

    // MARK: - launchApp returns AppInfo with correct fields

    func test_launchApp_returnsInfoWithBundleId() async throws {
        let info = try await service.launchApp(name: "Finder")
        XCTAssertNotNil(info.bundleId)
    }
}
