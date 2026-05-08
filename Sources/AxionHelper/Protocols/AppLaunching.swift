import Foundation

protocol AppLaunching: Sendable {
    func launchApp(name: String) async throws -> AppInfo
    func listRunningApps() -> [AppInfo]
}
