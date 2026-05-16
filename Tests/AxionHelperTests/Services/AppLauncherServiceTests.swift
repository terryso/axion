import Testing
@testable import AxionHelper

@Suite("AppLauncherService")
struct AppLauncherServiceTests {

    // MARK: - AppLauncherError Format

    @Test("appNotFound error has required fields")
    func appLauncherErrorAppNotFoundHasRequiredFields() {
        let error = AppLauncherError.appNotFound(name: "NoApp")
        #expect(error.errorCode == "app_not_found")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("NoApp"))
        #expect(!error.suggestion.isEmpty)
    }

    @Test("launchFailed error has required fields")
    func appLauncherErrorLaunchFailedHasRequiredFields() {
        let error = AppLauncherError.launchFailed(name: "Calculator", reason: "timeout")
        #expect(error.errorCode == "launch_failed")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("Calculator"))
        #expect(error.errorDescription!.contains("timeout"))
        #expect(!error.suggestion.isEmpty)
    }

    // MARK: - Protocol Conformance

    @Test("conforms to AppLaunching protocol")
    func conformsToAppLaunching() {
        let service = AppLauncherService()
        #expect(service is AppLaunching,
               "AppLauncherService should conform to AppLaunching protocol")
    }

    // MARK: - Error Equality

    @Test("appNotFound descriptions contain app name")
    func appLauncherErrorAppNotFoundDescriptions() {
        let error1 = AppLauncherError.appNotFound(name: "Foo")
        let error2 = AppLauncherError.appNotFound(name: "Bar")
        #expect(error1.errorDescription!.contains("Foo"))
        #expect(error2.errorDescription!.contains("Bar"))
    }

    @Test("launchFailed description contains name and reason")
    func appLauncherErrorLaunchFailedDescriptions() {
        let error = AppLauncherError.launchFailed(name: "Test", reason: "crashed")
        let desc = error.errorDescription
        #expect(desc != nil)
        #expect(desc!.contains("Test"))
        #expect(desc!.contains("crashed"))
    }

    @Test("suggestions are not empty")
    func appLauncherErrorSuggestionsNotEmpty() {
        #expect(!AppLauncherError.appNotFound(name: "X").suggestion.isEmpty)
        #expect(!AppLauncherError.launchFailed(name: "X", reason: "Y").suggestion.isEmpty)
    }

    @Test("error codes are correct")
    func appLauncherErrorErrorCodes() {
        #expect(AppLauncherError.appNotFound(name: "X").errorCode == "app_not_found")
        #expect(AppLauncherError.launchFailed(name: "X", reason: "Y").errorCode == "launch_failed")
    }
}
