import Foundation
import Testing
@testable import AxionHelper

extension ServicesTests {
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
        _ = AppLauncherService() as any AppLaunching
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

    // MARK: - Dependency-Injected Service Paths

    @Test("launchApp returns already-running app by display name without opening")
    func launchAppAlreadyRunningByDisplayName() async throws {
        let workspace = FakeAppLauncherWorkspace(
            runningApps: [
                AppLauncherRunningApp(
                    processIdentifier: 42,
                    localizedName: "Calculator",
                    bundleIdentifier: "com.apple.calculator"
                ),
            ]
        )
        let service = AppLauncherService(
            searchPaths: ["/Apps"],
            workspace: workspace,
            fileSystem: FakeAppLauncherFileSystem()
        )

        let app = try await service.launchApp(name: "calculator")

        #expect(app == AppInfo(pid: 42, appName: "Calculator", bundleId: "com.apple.calculator"))
        #expect(workspace.openedURLs.isEmpty)
    }

    @Test("launchApp returns already-running app by bundle-id suffix")
    func launchAppAlreadyRunningByBundleSuffix() async throws {
        let workspace = FakeAppLauncherWorkspace(
            runningApps: [
                AppLauncherRunningApp(
                    processIdentifier: 9,
                    localizedName: nil,
                    bundleIdentifier: "com.example.Terminal"
                ),
            ]
        )
        let service = AppLauncherService(
            searchPaths: ["/Apps"],
            workspace: workspace,
            fileSystem: FakeAppLauncherFileSystem()
        )

        let app = try await service.launchApp(name: "terminal.app")

        #expect(app == AppInfo(pid: 9, appName: "terminal.app", bundleId: "com.example.Terminal"))
        #expect(workspace.openedURLs.isEmpty)
    }

    @Test("listRunningApps filters unnamed applications")
    func listRunningAppsFiltersUnnamedApplications() {
        let service = AppLauncherService(
            searchPaths: ["/Apps"],
            workspace: FakeAppLauncherWorkspace(
                runningApps: [
                    AppLauncherRunningApp(processIdentifier: 1, localizedName: "Finder", bundleIdentifier: "com.apple.finder"),
                    AppLauncherRunningApp(processIdentifier: 2, localizedName: "", bundleIdentifier: "com.example.empty"),
                    AppLauncherRunningApp(processIdentifier: 3, localizedName: nil, bundleIdentifier: "com.example.nil"),
                ]
            ),
            fileSystem: FakeAppLauncherFileSystem()
        )

        #expect(service.listRunningApps() == [
            AppInfo(pid: 1, appName: "Finder", bundleId: "com.apple.finder"),
        ])
    }

    @Test("launchApp resolves bundle identifier through workspace")
    func launchAppResolvesBundleIdentifier() async throws {
        let bundleURL = URL(fileURLWithPath: "/Apps/Calculator.app")
        let workspace = FakeAppLauncherWorkspace(
            bundleURLs: ["com.apple.calculator": bundleURL],
            openResult: .success(AppLauncherRunningApp(
                processIdentifier: 100,
                localizedName: "Calculator",
                bundleIdentifier: "com.apple.calculator"
            ))
        )
        let service = AppLauncherService(
            searchPaths: ["/Apps"],
            workspace: workspace,
            fileSystem: FakeAppLauncherFileSystem()
        )

        let app = try await service.launchApp(name: "com.apple.calculator")

        #expect(app == AppInfo(pid: 100, appName: "Calculator", bundleId: "com.apple.calculator"))
        #expect(workspace.openedURLs == [bundleURL])
    }

    @Test("launchApp resolves exact app filename from search path")
    func launchAppResolvesExactFilename() async throws {
        let appURL = URL(fileURLWithPath: "/Apps/Test.app")
        let workspace = FakeAppLauncherWorkspace(
            openResult: .success(AppLauncherRunningApp(
                processIdentifier: 77,
                localizedName: nil,
                bundleIdentifier: "com.example.test"
            ))
        )
        let fileSystem = FakeAppLauncherFileSystem(existingPaths: [appURL.path])
        let service = AppLauncherService(
            searchPaths: ["/Apps"],
            workspace: workspace,
            fileSystem: fileSystem
        )

        let app = try await service.launchApp(name: "Test")

        #expect(app == AppInfo(pid: 77, appName: "Test", bundleId: "com.example.test"))
        #expect(workspace.openedURLs == [appURL])
    }

    @Test("launchApp resolves case-insensitive app filename")
    func launchAppResolvesCaseInsensitiveFilename() async throws {
        let appURL = URL(fileURLWithPath: "/Apps/Preview.app")
        let workspace = FakeAppLauncherWorkspace(
            openResult: .success(AppLauncherRunningApp(
                processIdentifier: 88,
                localizedName: "Preview",
                bundleIdentifier: nil
            ))
        )
        let fileSystem = FakeAppLauncherFileSystem(
            directories: ["/Apps": ["Preview.app"]]
        )
        let service = AppLauncherService(
            searchPaths: ["/Apps"],
            workspace: workspace,
            fileSystem: fileSystem
        )

        let app = try await service.launchApp(name: "preview")

        #expect(app == AppInfo(pid: 88, appName: "Preview", bundleId: nil))
        #expect(workspace.openedURLs == [appURL])
    }

    @Test("launchApp resolves localized display name")
    func launchAppResolvesLocalizedDisplayName() async throws {
        let appURL = URL(fileURLWithPath: "/Apps/Calculator.app")
        let workspace = FakeAppLauncherWorkspace(
            openResult: .success(AppLauncherRunningApp(
                processIdentifier: 101,
                localizedName: nil,
                bundleIdentifier: nil
            ))
        )
        let fileSystem = FakeAppLauncherFileSystem(
            directories: ["/Apps": ["Calculator.app", "Notes.txt"]],
            displayNames: [appURL.path: "计算器"]
        )
        let service = AppLauncherService(
            searchPaths: ["/Apps"],
            workspace: workspace,
            fileSystem: fileSystem
        )

        let app = try await service.launchApp(name: "计算器")

        #expect(app == AppInfo(pid: 101, appName: "计算器", bundleId: nil))
        #expect(workspace.openedURLs == [appURL])
    }

    @Test("launchApp throws appNotFound when no resolver matches")
    func launchAppThrowsAppNotFound() async {
        let service = AppLauncherService(
            searchPaths: ["/Apps"],
            workspace: FakeAppLauncherWorkspace(),
            fileSystem: FakeAppLauncherFileSystem(directories: ["/Apps": ["Other.app"]])
        )

        do {
            _ = try await service.launchApp(name: "Missing")
            Issue.record("Expected appNotFound")
        } catch let error as AppLauncherError {
            #expect(error.errorCode == "app_not_found")
            #expect(error.errorDescription?.contains("Missing") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("launchApp wraps workspace open failure")
    func launchAppWrapsOpenFailure() async {
        let appURL = URL(fileURLWithPath: "/Apps/Fails.app")
        let service = AppLauncherService(
            searchPaths: ["/Apps"],
            workspace: FakeAppLauncherWorkspace(
                openResult: .failure(FakeAppLauncherError.openDenied)
            ),
            fileSystem: FakeAppLauncherFileSystem(existingPaths: [appURL.path])
        )

        do {
            _ = try await service.launchApp(name: "Fails")
            Issue.record("Expected launchFailed")
        } catch let error as AppLauncherError {
            #expect(error.errorCode == "launch_failed")
            #expect(error.errorDescription?.contains("Fails") == true)
            #expect(error.errorDescription?.contains("denied") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private enum FakeAppLauncherError: Error, LocalizedError {
    case openDenied

    var errorDescription: String? {
        "denied"
    }
}

private final class FakeAppLauncherWorkspace: AppLauncherWorkspace, @unchecked Sendable {
    var runningApps: [AppLauncherRunningApp]
    var bundleURLs: [String: URL]
    var openResult: Result<AppLauncherRunningApp, Error>
    private(set) var openedURLs: [URL] = []

    init(
        runningApps: [AppLauncherRunningApp] = [],
        bundleURLs: [String: URL] = [:],
        openResult: Result<AppLauncherRunningApp, Error> = .success(
            AppLauncherRunningApp(
                processIdentifier: 1,
                localizedName: "Opened",
                bundleIdentifier: "com.example.opened"
            )
        )
    ) {
        self.runningApps = runningApps
        self.bundleURLs = bundleURLs
        self.openResult = openResult
    }

    func runningApplications() -> [AppLauncherRunningApp] {
        runningApps
    }

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        bundleURLs[bundleIdentifier]
    }

    func openApplication(at url: URL) async throws -> AppLauncherRunningApp {
        openedURLs.append(url)
        return try openResult.get()
    }
}

private final class FakeAppLauncherFileSystem: AppLauncherFileSystem, @unchecked Sendable {
    var existingPaths: Set<String>
    var directories: [String: [String]]
    var displayNames: [String: String]

    init(
        existingPaths: Set<String> = [],
        directories: [String: [String]] = [:],
        displayNames: [String: String] = [:]
    ) {
        self.existingPaths = existingPaths
        self.directories = directories
        self.displayNames = displayNames
    }

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        if let contents = directories[path] {
            return contents
        }
        throw CocoaError(.fileNoSuchFile)
    }

    func appDisplayName(at appURL: URL) -> String? {
        displayNames[appURL.path]
    }
}
}
