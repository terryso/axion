import XCTest
import MCP
import MCPTool
@testable import AxionHelper
@testable import AxionCore

// ATDD Red-Phase Test Scaffolds for Story 1.3
// AC: launch_app - 启动应用并返回 pid
// AC: list_apps - 列举运行中的应用
// AC: app_not_found - 指定应用未安装时返回错误
// These tests verify that launch_app and list_apps tools have real AX-backed
// implementations (not stubs) that interact with macOS application management.
// Priority: P0 (core functionality - all desktop automation depends on launching apps)

final class LaunchAppIntegrationTests: XCTestCase {

    // MARK: - Helpers

    /// Creates an MCPServer with all tools registered via ToolRegistrar.
    private func makeRegisteredServer() async throws -> MCPServer {
        let server = MCPServer(name: "AxionHelper", version: "0.1.0")
        try await ToolRegistrar.registerAll(to: server)
        return server
    }

    /// Creates a minimal HandlerContext suitable for testing tool execution.
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

    // MARK: - AC1: launch_app 启动应用

    // [P0] launch_app 启动 Calculator 并返回包含 pid 的结果
    func test_launchApp_calculator_returnsSuccessWithPid() async throws {
        // Given: launch_app 工具已注册
        let server = try await makeRegisteredServer()

        // When: 调用 launch_app 传入 app_name="Calculator"
        let result = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        // Then: 返回成功结果，包含 pid
        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        // 结果中不应包含 "not yet implemented"
        XCTAssertFalse(
            textContent.lowercased().contains("not yet implemented"),
            "launch_app should have a real implementation, not a stub. Got: \(textContent)"
        )

        // 结果中应包含 pid 信息（JSON 格式或纯文本）
        XCTAssertTrue(
            textContent.contains("pid") || textContent.contains("\"pid\""),
            "launch_app result should contain 'pid'. Got: \(textContent)"
        )
    }

    // [P1] launch_app 启动后应用确实在运行
    func test_launchApp_appIsRunningAfterLaunch() async throws {

        // Given: launch_app 已调用启动 Calculator
        let server = try await makeRegisteredServer()
        _ = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        // When: 调用 list_apps
        let listResult = try await server.toolRegistry.execute(
            "list_apps",
            arguments: nil,
            context: makeTestContext()
        )

        // Then: 应用列表中包含 Calculator
        let textContent = listResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        XCTAssertTrue(
            textContent.lowercased().contains("calculator"),
            "Calculator should appear in running apps list after launch. Got: \(textContent)"
        )
    }

    // [P1] launch_app 已运行的应用不重复启动
    func test_launchApp_alreadyRunning_returnsExistingPid() async throws {
        // Given: Calculator 已运行（通过第一次 launch_app）
        let server = try await makeRegisteredServer()
        let firstResult = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        let firstText = firstResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        // When: 再次调用 launch_app
        let secondResult = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        let secondText = secondResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        // Then: 两次都返回成功（不会报错）
        XCTAssertFalse(
            secondText.lowercased().contains("error"),
            "Re-launching an already-running app should not error. Got: \(secondText)"
        )
    }

    // MARK: - AC5: app_not_found 错误

    // [P0] launch_app 指定应用未安装时返回错误
    func test_launchApp_appNotFound_returnsError() async throws {
        // Given: launch_app 工具已注册
        let server = try await makeRegisteredServer()

        // When: 调用 launch_app 传入不存在的应用名
        let result = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("ThisAppDefinitelyDoesNotExist12345")],
            context: makeTestContext()
        )

        // Then: 返回包含 "app_not_found" 或等效错误的错误信息
        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        XCTAssertTrue(
            textContent.lowercased().contains("error") || textContent.lowercased().contains("not found") || textContent.lowercased().contains("failed"),
            "launch_app should return an error for non-existent app. Got: \(textContent)"
        )

        // 应包含 suggestion 字段（修复建议）
        XCTAssertTrue(
            textContent.lowercased().contains("suggestion") || textContent.lowercased().contains("install"),
            "Error should include a suggestion. Got: \(textContent)"
        )
    }

    // [P1] launch_app 缺少 app_name 参数时返回错误
    func test_launchApp_missingAppName_returnsError() async throws {
        // Given: launch_app 工具已注册
        let server = try await makeRegisteredServer()

        // When: 调用 launch_app 不传 app_name 参数
        do {
            _ = try await server.toolRegistry.execute(
                "launch_app",
                arguments: [:],
                context: makeTestContext()
            )
            // Then: MCP 框架应抛出参数验证错误
            XCTFail("Expected error for missing app_name parameter")
        } catch {
            // Expected: MCP parameter validation error
        }
    }

    // MARK: - AC2: list_apps 列举应用

    // [P0] list_apps 返回当前运行的应用列表
    func test_listApps_returnsRunningAppsList() async throws {
        // Given: list_apps 工具已注册
        let server = try await makeRegisteredServer()

        // When: 调用 list_apps
        let result = try await server.toolRegistry.execute(
            "list_apps",
            arguments: nil,
            context: makeTestContext()
        )

        // Then: 返回应用列表，不应是 stub
        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        XCTAssertFalse(
            textContent.lowercased().contains("not yet implemented"),
            "list_apps should have a real implementation, not a stub. Got: \(textContent)"
        )
    }

    // [P0] list_apps 每项包含 pid 和 app_name
    func test_listApps_eachAppHasPidAndName() async throws {
        // Given: 至少有一个应用在运行
        let server = try await makeRegisteredServer()

        // When: 调用 list_apps
        let result = try await server.toolRegistry.execute(
            "list_apps",
            arguments: nil,
            context: makeTestContext()
        )

        // Then: 结果为 JSON 格式，每项包含 pid 和 app_name
        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        // 尝试解析为 JSON 数组
        let data = textContent.data(using: .utf8)!
        let jsonArray = try JSONSerialization.jsonObject(with: data)

        // 应该是数组
        guard let apps = jsonArray as? [[String: Any]] else {
            XCTFail("list_apps result should be a JSON array. Got: \(textContent)")
            return
        }

        XCTAssertGreaterThan(apps.count, 0, "Should have at least one running app")

        // 每项应有 pid 和 app_name
        for app in apps {
            XCTAssertNotNil(app["pid"], "Each app should have 'pid' field")
            XCTAssertNotNil(app["app_name"], "Each app should have 'app_name' field")
        }
    }

    // [P1] list_apps 包含 Finder（macOS 始终运行）
    func test_listApps_containsFinder() async throws {
        // Given: macOS 正常运行（Finder 始终存在）
        let server = try await makeRegisteredServer()

        // When: 调用 list_apps
        let result = try await server.toolRegistry.execute(
            "list_apps",
            arguments: nil,
            context: makeTestContext()
        )

        // Then: 应用列表包含 Finder
        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        XCTAssertTrue(
            textContent.lowercased().contains("finder"),
            "list_apps should include Finder (always running on macOS). Got: \(textContent)"
        )
    }
}
