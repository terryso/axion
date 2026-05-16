import Foundation
import Testing
import MCP
import MCPTool
@testable import AxionHelper
@testable import AxionCore

@Suite("LaunchApp Integration")
struct LaunchAppIntegrationTests {

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

    // MARK: - AC1: launch_app 启动应用

    @Test("launch_app Calculator returns success with pid")
    func launchAppCalculatorReturnsSuccessWithPid() async throws {
        let server = try await makeRegisteredServer()

        let result = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        #expect(!textContent.lowercased().contains("not yet implemented"),
                "launch_app should have a real implementation, not a stub. Got: \(textContent)")
        #expect(textContent.contains("pid") || textContent.contains("\"pid\""),
                "launch_app result should contain 'pid'. Got: \(textContent)")
    }

    @Test("launch_app app is running after launch")
    func launchAppAppIsRunningAfterLaunch() async throws {
        let server = try await makeRegisteredServer()
        _ = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        let listResult = try await server.toolRegistry.execute(
            "list_apps",
            arguments: nil,
            context: makeTestContext()
        )

        let textContent = listResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        #expect(textContent.lowercased().contains("calculator"),
                "Calculator should appear in running apps list after launch. Got: \(textContent)")
    }

    @Test("launch_app already running returns existing pid")
    func launchAppAlreadyRunningReturnsExistingPid() async throws {
        let server = try await makeRegisteredServer()
        let firstResult = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        _ = firstResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        let secondResult = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        let secondText = secondResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        #expect(!secondText.lowercased().contains("error"),
                "Re-launching an already-running app should not error. Got: \(secondText)")
    }

    // MARK: - AC5: app_not_found 错误

    @Test("launch_app app not found returns error")
    func launchAppAppNotFoundReturnsError() async throws {
        let server = try await makeRegisteredServer()

        let result = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("ThisAppDefinitelyDoesNotExist12345")],
            context: makeTestContext()
        )

        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        #expect(
            textContent.lowercased().contains("error") || textContent.lowercased().contains("not found") || textContent.lowercased().contains("failed"),
            "launch_app should return an error for non-existent app. Got: \(textContent)"
        )

        #expect(
            textContent.lowercased().contains("suggestion") || textContent.lowercased().contains("install"),
            "Error should include a suggestion. Got: \(textContent)"
        )
    }

    @Test("launch_app missing app_name returns error")
    func launchAppMissingAppNameReturnsError() async throws {
        let server = try await makeRegisteredServer()

        do {
            _ = try await server.toolRegistry.execute(
                "launch_app",
                arguments: [:],
                context: makeTestContext()
            )
            Issue.record("Expected error for missing app_name parameter")
        } catch {
            // Expected: MCP parameter validation error
        }
    }

    // MARK: - AC2: list_apps 列举应用

    @Test("list_apps returns running apps list")
    func listAppsReturnsRunningAppsList() async throws {
        let server = try await makeRegisteredServer()

        let result = try await server.toolRegistry.execute(
            "list_apps",
            arguments: nil,
            context: makeTestContext()
        )

        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        #expect(!textContent.lowercased().contains("not yet implemented"),
                "list_apps should have a real implementation, not a stub. Got: \(textContent)")
    }

    @Test("list_apps each app has pid and name")
    func listAppsEachAppHasPidAndName() async throws {
        let server = try await makeRegisteredServer()

        let result = try await server.toolRegistry.execute(
            "list_apps",
            arguments: nil,
            context: makeTestContext()
        )

        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        let data = textContent.data(using: .utf8)!
        let jsonArray = try JSONSerialization.jsonObject(with: data)

        guard let apps = jsonArray as? [[String: Any]] else {
            Issue.record("list_apps result should be a JSON array. Got: \(textContent)")
            return
        }

        #expect(apps.count > 0, "Should have at least one running app")

        for app in apps {
            #expect(app["pid"] != nil, "Each app should have 'pid' field")
            #expect(app["app_name"] != nil, "Each app should have 'app_name' field")
        }
    }

    @Test("list_apps contains Finder")
    func listAppsContainsFinder() async throws {
        let server = try await makeRegisteredServer()

        let result = try await server.toolRegistry.execute(
            "list_apps",
            arguments: nil,
            context: makeTestContext()
        )

        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        #expect(textContent.lowercased().contains("finder"),
                "list_apps should include Finder (always running on macOS). Got: \(textContent)")
    }
}
