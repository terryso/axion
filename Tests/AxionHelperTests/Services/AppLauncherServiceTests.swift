import XCTest
@testable import AxionHelper

final class AppLauncherServiceTests: XCTestCase {

    // MARK: - AppLauncherError Format

    func test_appLauncherError_appNotFound_hasRequiredFields() {
        let error = AppLauncherError.appNotFound(name: "NoApp")
        XCTAssertEqual(error.errorCode, "app_not_found")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("NoApp"))
        XCTAssertFalse(error.suggestion.isEmpty)
    }

    func test_appLauncherError_launchFailed_hasRequiredFields() {
        let error = AppLauncherError.launchFailed(name: "Calculator", reason: "timeout")
        XCTAssertEqual(error.errorCode, "launch_failed")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Calculator"))
        XCTAssertTrue(error.errorDescription!.contains("timeout"))
        XCTAssertFalse(error.suggestion.isEmpty)
    }

    // MARK: - Protocol Conformance

    func test_appLauncherService_conformsToAppLaunching() {
        let service = AppLauncherService()
        XCTAssertTrue(service is AppLaunching,
                      "AppLauncherService should conform to AppLaunching protocol")
    }

    // MARK: - Error Equality

    func test_appLauncherError_appNotFound_descriptions() {
        let error1 = AppLauncherError.appNotFound(name: "Foo")
        let error2 = AppLauncherError.appNotFound(name: "Bar")
        XCTAssertTrue(error1.errorDescription!.contains("Foo"))
        XCTAssertTrue(error2.errorDescription!.contains("Bar"))
    }

    func test_appLauncherError_launchFailed_descriptions() {
        let error = AppLauncherError.launchFailed(name: "Test", reason: "crashed")
        let desc = error.errorDescription
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.contains("Test"))
        XCTAssertTrue(desc!.contains("crashed"))
    }

    func test_appLauncherError_suggestions_notEmpty() {
        XCTAssertFalse(AppLauncherError.appNotFound(name: "X").suggestion.isEmpty)
        XCTAssertFalse(AppLauncherError.launchFailed(name: "X", reason: "Y").suggestion.isEmpty)
    }

    func test_appLauncherError_errorCodes() {
        XCTAssertEqual(AppLauncherError.appNotFound(name: "X").errorCode, "app_not_found")
        XCTAssertEqual(AppLauncherError.launchFailed(name: "X", reason: "Y").errorCode, "launch_failed")
    }
}
