import AppKit
import Foundation

struct AppLauncherRunningApp: Equatable, Sendable {
    let processIdentifier: Int32
    let localizedName: String?
    let bundleIdentifier: String?
}

protocol AppLauncherWorkspace: Sendable {
    func runningApplications() -> [AppLauncherRunningApp]
    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL?
    func openApplication(at url: URL) async throws -> AppLauncherRunningApp
}

protocol AppLauncherFileSystem: Sendable {
    func fileExists(atPath path: String) -> Bool
    func contentsOfDirectory(atPath path: String) throws -> [String]
    func appDisplayName(at appURL: URL) -> String?
}

struct NSWorkspaceAppLauncherWorkspace: AppLauncherWorkspace {
    func runningApplications() -> [AppLauncherRunningApp] {
        NSWorkspace.shared.runningApplications.map { app in
            AppLauncherRunningApp(
                processIdentifier: app.processIdentifier,
                localizedName: app.localizedName,
                bundleIdentifier: app.bundleIdentifier
            )
        }
    }

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func openApplication(at url: URL) async throws -> AppLauncherRunningApp {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        return AppLauncherRunningApp(
            processIdentifier: app.processIdentifier,
            localizedName: app.localizedName,
            bundleIdentifier: app.bundleIdentifier
        )
    }
}

struct DefaultAppLauncherFileSystem: AppLauncherFileSystem {
    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }

    func appDisplayName(at appURL: URL) -> String? {
        guard let bundle = Bundle(url: appURL) else { return nil }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
    }
}

/// Errors thrown by `AppLauncherService`.
enum AppLauncherError: Error, LocalizedError, ToolErrorProtocol {
    case appNotFound(name: String)
    case launchFailed(name: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let name):
            return "\(name).app not found"
        case .launchFailed(let name, let reason):
            return "Failed to launch \(name).app: \(reason)"
        }
    }

    var errorCode: String {
        switch self {
        case .appNotFound:
            return "app_not_found"
        case .launchFailed:
            return "launch_failed"
        }
    }

    var suggestion: String {
        switch self {
        case .appNotFound:
            return "Please verify the application name is correct and the app is installed."
        case .launchFailed:
            return "Check if the application is compatible and try again."
        }
    }
}

/// Service responsible for launching macOS applications and listing running apps.
struct AppLauncherService: AppLaunching {

    // MARK: - Application Search Paths

    /// Directories searched when resolving an application by name.
    static let defaultSearchPaths = [
        "/Applications",
        "/System/Applications",
        "/Applications/Utilities",
        "\(NSHomeDirectory())/Applications",
    ]

    private let searchPaths: [String]
    private let workspace: any AppLauncherWorkspace
    private let fileSystem: any AppLauncherFileSystem

    init(
        searchPaths: [String] = AppLauncherService.defaultSearchPaths,
        workspace: any AppLauncherWorkspace = NSWorkspaceAppLauncherWorkspace(),
        fileSystem: any AppLauncherFileSystem = DefaultAppLauncherFileSystem()
    ) {
        self.searchPaths = searchPaths
        self.workspace = workspace
        self.fileSystem = fileSystem
    }

    // MARK: - Public API

    func launchApp(name: String) async throws -> AppInfo {
        // Check if already running
        if let running = findRunningApp(name: name) {
            return AppInfo(
                pid: running.processIdentifier,
                appName: running.localizedName ?? name,
                bundleId: running.bundleIdentifier
            )
        }

        // Not running — launch fresh via NSWorkspace
        let appURL = try resolveAppURL(name: name)

        let runningApp: AppLauncherRunningApp
        do {
            runningApp = try await workspace.openApplication(at: appURL)
        } catch {
            throw AppLauncherError.launchFailed(name: name, reason: error.localizedDescription)
        }

        return AppInfo(
            pid: runningApp.processIdentifier,
            appName: runningApp.localizedName ?? name,
            bundleId: runningApp.bundleIdentifier
        )
    }

    func listRunningApps() -> [AppInfo] {
        workspace.runningApplications().compactMap { app in
            guard let name = app.localizedName, !name.isEmpty else { return nil }
            return AppInfo(
                pid: app.processIdentifier,
                appName: name,
                bundleId: app.bundleIdentifier
            )
        }
    }

    // MARK: - Private Helpers

    private func findRunningApp(name: String) -> AppLauncherRunningApp? {
        let normalizedName = name.lowercased().replacingOccurrences(of: ".app", with: "")
        return workspace.runningApplications().first { app in
            if let appName = app.localizedName, appName.lowercased() == normalizedName { return true }
            if let bundleId = app.bundleIdentifier,
               let canonical = bundleId.split(separator: ".").last.map(String.init),
               canonical.lowercased() == normalizedName { return true }
            return false
        }
    }

    private func resolveAppURL(name: String) throws -> URL {
        let searchName: String
        if name.hasSuffix(".app") {
            searchName = name
        } else {
            searchName = "\(name).app"
        }

        // Bundle identifier lookup (e.g., "com.apple.calculator")
        if name.split(separator: ".").count >= 3 {
            if let url = workspace.urlForApplication(withBundleIdentifier: name) {
                return url
            }
        }

        // Exact filename match
        for dirPath in searchPaths {
            let url = URL(fileURLWithPath: dirPath).appendingPathComponent(searchName)
            if fileSystem.fileExists(atPath: url.path) {
                return url
            }
        }

        // Case-insensitive filename match
        for dirPath in searchPaths {
            if let contents = try? fileSystem.contentsOfDirectory(atPath: dirPath) {
                for item in contents {
                    if item.lowercased() == searchName.lowercased() {
                        return URL(fileURLWithPath: dirPath).appendingPathComponent(item)
                    }
                }
            }
        }

        // Localized display name match (e.g., "计算器" → Calculator.app)
        for dirPath in searchPaths {
            if let match = findAppByDisplayName(name, in: dirPath) {
                return match
            }
        }

        throw AppLauncherError.appNotFound(name: name)
    }

    /// Searches a directory for an .app bundle whose display name matches the given name.
    private func findAppByDisplayName(_ name: String, in directory: String) -> URL? {
        let normalizedName = name.lowercased()
        guard let contents = try? fileSystem.contentsOfDirectory(atPath: directory) else {
            return nil
        }
        for item in contents where item.hasSuffix(".app") {
            let appURL = URL(fileURLWithPath: directory).appendingPathComponent(item)
            if let displayName = fileSystem.appDisplayName(at: appURL), displayName.lowercased() == normalizedName {
                return appURL
            }
        }
        return nil
    }
}
