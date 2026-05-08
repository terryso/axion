import AppKit
import Foundation

/// Errors thrown by `AppLauncherService`.
enum AppLauncherError: Error, LocalizedError {
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
    private let searchPaths = [
        "/Applications",
        "/System/Applications",
        "/Applications/Utilities",
        "\(NSHomeDirectory())/Applications",
    ]

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

        // Resolve app URL
        let appURL = try resolveAppURL(name: name)

        // Launch
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        let runningApp: NSRunningApplication
        do {
            runningApp = try await NSWorkspace.shared.openApplication(
                at: appURL,
                configuration: config
            )
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
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let name = app.localizedName, !name.isEmpty else { return nil }
            return AppInfo(
                pid: app.processIdentifier,
                appName: name,
                bundleId: app.bundleIdentifier
            )
        }
    }

    // MARK: - Private Helpers

    private func findRunningApp(name: String) -> NSRunningApplication? {
        let normalizedName = name.lowercased().replacingOccurrences(of: ".app", with: "")
        return NSWorkspace.shared.runningApplications.first { app in
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

        if name.split(separator: ".").count >= 3 {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
                return url
            }
        }

        for dirPath in searchPaths {
            let url = URL(fileURLWithPath: dirPath).appendingPathComponent(searchName)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        for dirPath in searchPaths {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: dirPath) {
                for item in contents {
                    if item.lowercased() == searchName.lowercased() {
                        return URL(fileURLWithPath: dirPath).appendingPathComponent(item)
                    }
                }
            }
        }

        throw AppLauncherError.appNotFound(name: name)
    }
}
