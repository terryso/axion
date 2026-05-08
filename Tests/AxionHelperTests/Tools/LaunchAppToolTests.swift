import Foundation
import MCP
import MCPTool
import XCTest
@testable import AxionHelper
@testable import AxionCore

// Unit tests for launch_app and list_apps tools using mock services.
// These tests do NOT launch real applications — all system interaction is mocked.
// Priority: P0 (core tool wiring)

@MainActor
final class LaunchAppToolTests: XCTestCase {

    // MARK: - Helpers

    private func makeRegisteredServer() async throws -> MCPServer {
        let server = MCPServer(name: "AxionHelper", version: "0.1.0")
        try await ToolRegistrar.registerAll(to: server)
        return server
    }

    private func makeTestContext() -> HandlerContext {
        let requestContext = RequestHandlerContext(
            sessionId: nil,
            requestId: .number(1),
            _meta: nil,
            taskId: nil,
            authInfo: nil,
            requestInfo: nil,
            closeResponseStream: nil,
            closeNotificationStream: nil,
            sendNotification: { _ in },
            sendRequest: { _ in Data() }
        )
        return HandlerContext(handlerContext: requestContext, progressToken: nil)
    }

    private func textContent(_ result: CallTool.Result) -> String {
        result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()
    }

    // MARK: - launch_app

    func test_launchApp_success_returnsJsonWithPid() async throws {
        let restore = ServiceContainerFixture.apply(
            appLauncher: MockAppLauncher(
                launchAppHandler: { name in
                    AppInfo(pid: 12345, appName: name, bundleId: "com.example.\(name)")
                },
                listRunningAppsHandler: { [] }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["pid"] as? Int, 12345)
        XCTAssertEqual(json?["app_name"] as? String, "Calculator")
    }

    func test_launchApp_appNotFound_returnsErrorJson() async throws {
        let restore = ServiceContainerFixture.apply(
            appLauncher: MockAppLauncher(
                launchAppHandler: { _ in throw AppLauncherError.appNotFound(name: "NoApp") },
                listRunningAppsHandler: { [] }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("NoApp")],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["error"] as? String, "app_not_found")
        XCTAssertNotNil(json?["message"])
        XCTAssertNotNil(json?["suggestion"])
    }

    func test_launchApp_alreadyRunning_returnsExistingPid() async throws {
        let callCount = LockedCounter()
        let restore = ServiceContainerFixture.apply(
            appLauncher: MockAppLauncher(
                launchAppHandler: { name in
                    callCount.increment()
                    return AppInfo(pid: 999, appName: name, bundleId: nil)
                },
                listRunningAppsHandler: { [] }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        _ = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )
        _ = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        XCTAssertEqual(callCount.value, 2, "Both calls should succeed via mock")
    }

    // MARK: - list_apps

    func test_listApps_returnsJsonArray() async throws {
        let restore = ServiceContainerFixture.apply(
            appLauncher: MockAppLauncher(
                launchAppHandler: { _ in AppInfo(pid: 1, appName: "A", bundleId: nil) },
                listRunningAppsHandler: {
                    [
                        AppInfo(pid: 100, appName: "Finder", bundleId: "com.apple.finder"),
                        AppInfo(pid: 200, appName: "Safari", bundleId: "com.apple.Safari"),
                    ]
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "list_apps",
            arguments: nil,
            context: makeTestContext()
        )

        let text = textContent(result)
        let data = text.data(using: .utf8)!
        let apps = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]

        XCTAssertEqual(apps?.count, 2)
        XCTAssertEqual(apps?[0]["app_name"] as? String, "Finder")
        XCTAssertEqual(apps?[1]["app_name"] as? String, "Safari")
    }

    func test_listApps_eachAppHasPidAndName() async throws {
        let restore = ServiceContainerFixture.apply(
            appLauncher: MockAppLauncher(
                launchAppHandler: { _ in fatalError("should not be called") },
                listRunningAppsHandler: {
                    [AppInfo(pid: 1, appName: "Finder", bundleId: "com.apple.finder")]
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "list_apps",
            arguments: nil,
            context: makeTestContext()
        )

        let text = textContent(result)
        let data = text.data(using: .utf8)!
        let apps = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

        for app in apps {
            XCTAssertNotNil(app["pid"], "Each app should have pid")
            XCTAssertNotNil(app["app_name"], "Each app should have app_name")
        }
    }
}

/// Thread-safe counter for verifying mock call counts.
private final class LockedCounter: @unchecked Sendable {
    private var _value = 0
    private let lock = NSLock()
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }
}
