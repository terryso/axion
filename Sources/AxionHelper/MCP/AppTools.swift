import MCP
import MCPTool

enum AppTools {
    static func register(to server: MCPServer) async throws {
        try await server.register {
            LaunchAppTool.self
            ListAppsTool.self
        }
    }
}

// MARK: - App Management Tools (Story 1.3)

@Tool
struct LaunchAppTool {
    static let name = "launch_app"
    static let description = "Launch a macOS application by name"

    @Parameter(key: "app_name", description: "Application name (e.g. 'Calculator')")
    var appName: String

    func perform() async throws -> String {
        do {
            let appInfo = try await ServiceContainer.shared.appLauncher.launchApp(name: appName)

            try? await Task.sleep(nanoseconds: ServiceContainer.shared.launchDelayNs)
            let windows = ServiceContainer.shared.accessibilityEngine.listWindows(pid: appInfo.pid)

            let blocker = detectBlockingDialog(windows: windows, appPid: appInfo.pid)

            if let blocker {
                struct LaunchResult: Codable {
                    let pid: Int32
                    let appName: String
                    let bundleId: String?
                    let blockingDialog: BlockingDialogInfo

                    enum CodingKeys: String, CodingKey {
                        case pid
                        case appName = "app_name"
                        case bundleId = "bundle_id"
                        case blockingDialog = "blocking_dialog"
                    }
                }
                let result = LaunchResult(
                    pid: appInfo.pid,
                    appName: appInfo.appName,
                    bundleId: appInfo.bundleId,
                    blockingDialog: blocker
                )
                return encodeToolResult(result)
            } else {
                return encodeToolResult(appInfo)
            }
        } catch let error as AppLauncherError {
            return encodeToolError(error)
        }
    }
}

@Tool
struct ListAppsTool {
    static let name = "list_apps"
    static let description = "List all running macOS applications"

    func perform() async throws -> String {
        let apps = ServiceContainer.shared.appLauncher.listRunningApps()
        return encodeToolResult(apps, fallback: "[]")
    }
}
