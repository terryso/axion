import Testing
import Foundation
import OpenAgentSDK

import AxionCore
@testable import AxionCLI

@Suite("Execute Storage Plan Tool")
struct ExecuteStoragePlanToolTests {

    /// Records the captured request and returns a canned manifest built from it.
    private actor MockStorageExecutor: StorageExecuting {
        private(set) var capturedRequest: ExecuteRequest?

        func execute(_ request: ExecuteRequest) async -> ExecuteResult {
            capturedRequest = request
            let items = request.items.map {
                StorageManifestItem(action: $0.action, sourcePath: $0.source, targetPath: $0.target, outcome: .succeeded, evidence: $0.evidence)
            }
            let manifest = StorageManifest(
                operationId: request.operationId,
                createdAt: "2026-06-11T00:00:00Z",
                surface: request.surface,
                userRequest: request.userRequest,
                items: items,
                status: .completed,
                errors: []
            )
            return ExecuteResult(manifest: manifest, succeeded: items.count, skipped: 0, failed: 0)
        }

        func captured() -> ExecuteRequest? { capturedRequest }
    }

    private func makeContext() -> ToolContext {
        ToolContext(cwd: "/tmp", toolUseId: "exec-test-\(UUID().uuidString)")
    }

    private func jsonObject(from result: ToolResult) throws -> [String: Any] {
        let data = try #require(result.content.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test("tool executes a valid request and returns the manifest")
    func toolExecutesValidRequestAndReturnsManifest() async throws {
        let executor = MockStorageExecutor()
        let tool = ExecuteStoragePlanTool(executor: executor)

        let result = await tool.call(
            input: [
                "operation_id": "op-tool-1",
                "scan_roots": ["/Users/demo/Downloads"],
                "items": [
                    [
                        "action": "move",
                        "source": "/Users/demo/Downloads/a.pdf",
                        "target": "/Users/demo/Downloads/Docs/a.pdf",
                        "reason": "document",
                        "size_bytes": 100,
                        "evidence": ["rule": "kind:document", "source": "agent", "confidence": "high"],
                    ],
                ],
            ] as [String: Any],
            context: makeContext()
        )

        #expect(!result.isError)
        let manifest = try JSONDecoder().decode(StorageManifest.self, from: Data(result.content.utf8))
        #expect(manifest.operationId == "op-tool-1")
        #expect(manifest.items.first?.action == .move)

        let captured = try #require(await executor.captured())
        #expect(captured.operationId == "op-tool-1")
        #expect(captured.scanRoots.map(\.path) == ["/Users/demo/Downloads"])
        #expect(captured.items.count == 1)
        #expect(captured.items.first?.source == "/Users/demo/Downloads/a.pdf")
        #expect(captured.items.first?.target == "/Users/demo/Downloads/Docs/a.pdf")
        #expect(captured.items.first?.evidence?.confidence == .high)
        // size_bytes hint parsed through (executor re-reads in production, mock keeps it).
        #expect(captured.items.first?.sizeBytes == 100)
    }

    @Test("tool rejects non-object input")
    func toolRejectsNonObjectInput() async throws {
        let tool = ExecuteStoragePlanTool(executor: MockStorageExecutor())
        let result = await tool.call(input: "bad", context: makeContext())
        #expect(result.isError)
        #expect(result.content.contains("invalid_input"))
    }

    @Test("tool rejects missing operation_id")
    func toolRejectsMissingOperationId() async throws {
        let tool = ExecuteStoragePlanTool(executor: MockStorageExecutor())
        let result = await tool.call(
            input: ["scan_roots": ["/x"], "items": [["action": "scan_only", "source": "/x/a"]]] as [String: Any],
            context: makeContext()
        )
        #expect(result.isError)
        #expect(result.content.contains("missing_operation_id"))
    }

    @Test("tool rejects missing or empty scan_roots")
    func toolRejectsMissingScanRoots() async throws {
        let tool = ExecuteStoragePlanTool(executor: MockStorageExecutor())
        let missing = await tool.call(
            input: ["operation_id": "op", "items": [["action": "scan_only", "source": "/x/a"]]] as [String: Any],
            context: makeContext()
        )
        #expect(missing.isError && missing.content.contains("missing_scan_roots"))

        let empty = await tool.call(
            input: ["operation_id": "op", "scan_roots": [], "items": [["action": "scan_only", "source": "/x/a"]]] as [String: Any],
            context: makeContext()
        )
        #expect(empty.isError && empty.content.contains("missing_scan_roots"))
    }

    @Test("tool rejects missing or empty items")
    func toolRejectsMissingItems() async throws {
        let tool = ExecuteStoragePlanTool(executor: MockStorageExecutor())
        let missing = await tool.call(
            input: ["operation_id": "op", "scan_roots": ["/x"]] as [String: Any],
            context: makeContext()
        )
        #expect(missing.isError && missing.content.contains("missing_items"))

        let empty = await tool.call(
            input: ["operation_id": "op", "scan_roots": ["/x"], "items": []] as [String: Any],
            context: makeContext()
        )
        #expect(empty.isError && empty.content.contains("missing_items"))
    }

    @Test("tool drops unknown actions (delete) and errors when no valid items remain")
    func toolDropsUnknownActions() async throws {
        let executor = MockStorageExecutor()
        let tool = ExecuteStoragePlanTool(executor: executor)

        let result = await tool.call(
            input: [
                "operation_id": "op-del",
                "scan_roots": ["/x"],
                "items": [["action": "delete", "source": "/x/a"]],  // 'delete' is not a StorageAction
            ] as [String: Any],
            context: makeContext()
        )
        #expect(result.isError)
        #expect(result.content.contains("no_valid_items"))
        // Executor never invoked (parse-stage drop).
        #expect(await executor.captured() == nil)
    }

    @Test("tool passes uninstall_app through to executor (audit-rejected at execution)")
    func toolPassesUninstallAppToExecutor() async throws {
        let executor = MockStorageExecutor()
        let tool = ExecuteStoragePlanTool(executor: executor)

        let result = await tool.call(
            input: [
                "operation_id": "op-app",
                "scan_roots": ["/x"],
                "items": [["action": "uninstall_app", "source": "/x/Demo.app"]],
            ] as [String: Any],
            context: makeContext()
        )
        // Tool does not pre-filter uninstall_app (valid StorageAction); the real executor rejects it.
        #expect(!result.isError)
        let captured = try #require(await executor.captured())
        #expect(captured.items.first?.action == .uninstallApp)
    }

    @Test("tool drops unknown actions alongside valid ones (valid still executed)")
    func toolKeepsValidWhenMixedWithUnknown() async throws {
        let executor = MockStorageExecutor()
        let tool = ExecuteStoragePlanTool(executor: executor)

        _ = await tool.call(
            input: [
                "operation_id": "op-mixed",
                "scan_roots": ["/x"],
                "items": [
                    ["action": "move", "source": "/x/a", "target": "/x/b"],
                    ["action": "delete", "source": "/x/c"],  // dropped at parse
                ],
            ] as [String: Any],
            context: makeContext()
        )
        let captured = try #require(await executor.captured())
        #expect(captured.items.count == 1)
        #expect(captured.items.first?.action == .move)
    }

    @Test("tool defaults surface to run and honors chat")
    func toolSurfaceDefaultsAndOverride() async throws {
        let executor = MockStorageExecutor()
        let tool = ExecuteStoragePlanTool(executor: executor)

        _ = await tool.call(
            input: [
                "operation_id": "op-surf-default",
                "scan_roots": ["/x"],
                "items": [["action": "scan_only", "source": "/x/a"]],
            ] as [String: Any],
            context: makeContext()
        )
        let defaultCaptured = try #require(await executor.captured())
        #expect(defaultCaptured.surface == .run)

        _ = await tool.call(
            input: [
                "operation_id": "op-surf-chat",
                "scan_roots": ["/x"],
                "surface": "chat",
                "items": [["action": "scan_only", "source": "/x/a"]],
            ] as [String: Any],
            context: makeContext()
        )
        let chatCaptured = try #require(await executor.captured())
        #expect(chatCaptured.surface == .chat)
    }
}
