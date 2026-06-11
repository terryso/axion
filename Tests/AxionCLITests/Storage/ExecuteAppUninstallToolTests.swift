import Testing
import Foundation
import OpenAgentSDK

import AxionCore
@testable import AxionCLI

@Suite("Execute App Uninstall Tool")
struct ExecuteAppUninstallToolTests {

    /// Captures the parsed request and returns a canned manifest summarizing it.
    private actor MockAppUninstallExecutor: AppUninstallExecuting {
        private(set) var capturedRequest: AppUninstallExecuteRequest?

        func execute(_ request: AppUninstallExecuteRequest) async -> AppUninstallExecuteResult {
            capturedRequest = request
            // Build manifest items echoing the parsed app/support set (so tests can assert parsing).
            var items: [StorageManifestItem] = []
            if request.uninstallBundle {
                items.append(StorageManifestItem(
                    action: .uninstallApp,
                    sourcePath: request.app.bundlePath,
                    outcome: .succeeded
                ))
            }
            for s in request.supportDataItems {
                items.append(StorageManifestItem(
                    action: .trash,
                    sourcePath: s.path,
                    outcome: .succeeded
                ))
            }
            let manifest = StorageManifest(
                operationId: request.operationId,
                createdAt: "2026-06-12T00:00:00Z",
                surface: request.surface,
                userRequest: request.userRequest,
                items: items,
                status: .completed,
                errors: []
            )
            return AppUninstallExecuteResult(manifest: manifest, succeeded: items.count, skipped: 0, failed: 0)
        }

        func captured() -> AppUninstallExecuteRequest? { capturedRequest }
    }

    private func makeContext() -> ToolContext {
        ToolContext(cwd: "/tmp", toolUseId: "exec-app-\(UUID().uuidString)")
    }

    /// Minimal valid app input object.
    private func appInput() -> [String: Any] {
        [
            "bundle_path": "/Applications/Foo.app",
            "bundle_identifier": "com.example.foo",
            "display_name": "Foo",
            "is_running": true,
            "is_system_protected": false,
            "match_confidence": "high",
            "size_bytes": 12345,
        ]
    }

    // MARK: - happy path + parsing

    @Test("tool executes bundle uninstall and returns the manifest")
    func toolExecutesBundleUninstall() async throws {
        let executor = MockAppUninstallExecutor()
        let tool = ExecuteAppUninstallTool(executor: executor)

        let result = await tool.call(
            input: [
                "operation_id": "op-app-1",
                "search_roots": ["/Applications"],
                "uninstall_bundle": true,
                "app": appInput(),
            ] as [String: Any],
            context: makeContext()
        )

        #expect(!result.isError)
        let manifest = try JSONDecoder().decode(StorageManifest.self, from: Data(result.content.utf8))
        #expect(manifest.operationId == "op-app-1")
        #expect(manifest.status == .completed)
        #expect(manifest.items.first?.action == .uninstallApp)
        #expect(manifest.items.first?.sourcePath == "/Applications/Foo.app")

        let captured = try #require(await executor.captured())
        #expect(captured.operationId == "op-app-1")
        #expect(captured.uninstallBundle == true)
        // App parsed end-to-end.
        #expect(captured.app.bundleIdentifier == "com.example.foo")
        #expect(captured.app.displayName == "Foo")
        #expect(captured.app.isRunning == true)
        #expect(captured.app.isSystemProtected == false)
        #expect(captured.app.matchConfidence == .high)
        #expect(captured.app.sizeBytes == 12345)
        // search_roots forwarded (bundle re-validation scope).
        #expect(captured.searchRoots.map(\.path) == ["/Applications"])
    }

    @Test("tool parses support data items through to the executor")
    func toolParsesSupportItems() async throws {
        let executor = MockAppUninstallExecutor()
        let tool = ExecuteAppUninstallTool(executor: executor)

        let result = await tool.call(
            input: [
                "operation_id": "op-app-2",
                "search_roots": ["/Applications"],
                "uninstall_bundle": false,
                "app": appInput(),
                "support_data_items": [
                    [
                        "category": "cache",
                        "path": "/Users/demo/Library/Caches/com.example.foo",
                        "size_bytes": 999,
                        "match_confidence": "high",
                        "data_risk": "low",
                        "default_selected": true,
                        "requires_explicit_approval": false,
                        "match_evidence": ["rule": "bundle_id_prefix", "source": "scanner", "confidence": "high"],
                    ],
                    [
                        "category": "preferences",
                        "path": "/Users/demo/Library/Preferences/com.example.foo.plist",
                        "data_risk": "medium",
                        "default_selected": false,
                        "requires_explicit_approval": true,
                    ],
                ],
            ] as [String: Any],
            context: makeContext()
        )

        #expect(!result.isError)
        let captured = try #require(await executor.captured())
        #expect(captured.uninstallBundle == false)
        #expect(captured.supportDataItems.count == 2)

        let cache = captured.supportDataItems[0]
        #expect(cache.category == .cache)
        #expect(cache.path == "/Users/demo/Library/Caches/com.example.foo")
        #expect(cache.sizeBytes == 999)
        #expect(cache.matchConfidence == .high)
        #expect(cache.dataRisk == .low)
        #expect(cache.defaultSelected == true)
        #expect(cache.requiresExplicitApproval == false)
        #expect(cache.matchEvidence.confidence == .high)

        let prefs = captured.supportDataItems[1]
        #expect(prefs.category == .preferences)
        #expect(prefs.dataRisk == .medium)
        #expect(prefs.requiresExplicitApproval == true)
    }

    // MARK: - error / validation paths

    @Test("tool rejects non-object input")
    func toolRejectsNonObjectInput() async throws {
        let tool = ExecuteAppUninstallTool(executor: MockAppUninstallExecutor())
        let result = await tool.call(input: "bad", context: makeContext())
        #expect(result.isError)
        #expect(result.content.contains("invalid_input"))
    }

    @Test("tool rejects missing operation_id")
    func toolRejectsMissingOperationId() async throws {
        let tool = ExecuteAppUninstallTool(executor: MockAppUninstallExecutor())
        let result = await tool.call(
            input: ["search_roots": ["/Applications"], "uninstall_bundle": true, "app": appInput()] as [String: Any],
            context: makeContext()
        )
        #expect(result.isError)
        #expect(result.content.contains("missing_operation_id"))
    }

    @Test("tool rejects missing or empty search_roots")
    func toolRejectsMissingOrEmptySearchRoots() async throws {
        let tool = ExecuteAppUninstallTool(executor: MockAppUninstallExecutor())

        let missing = await tool.call(
            input: ["operation_id": "op", "uninstall_bundle": true, "app": appInput()] as [String: Any],
            context: makeContext()
        )
        #expect(missing.isError && missing.content.contains("missing_search_roots"))

        let empty = await tool.call(
            input: ["operation_id": "op", "search_roots": [], "uninstall_bundle": true, "app": appInput()] as [String: Any],
            context: makeContext()
        )
        #expect(empty.isError && empty.content.contains("missing_search_roots"))
    }

    @Test("tool rejects missing or invalid app")
    func toolRejectsMissingOrInvalidApp() async throws {
        let tool = ExecuteAppUninstallTool(executor: MockAppUninstallExecutor())

        let missing = await tool.call(
            input: ["operation_id": "op", "search_roots": ["/Applications"], "uninstall_bundle": true] as [String: Any],
            context: makeContext()
        )
        #expect(missing.isError && missing.content.contains("missing_or_invalid_app"))

        // Empty bundle_path is not a valid app.
        let noPath = await tool.call(
            input: ["operation_id": "op", "search_roots": ["/Applications"], "uninstall_bundle": true, "app": ["bundle_identifier": "x"]] as [String: Any],
            context: makeContext()
        )
        #expect(noPath.isError && noPath.content.contains("missing_or_invalid_app"))
    }

    @Test("tool rejects when nothing is requested to execute")
    func toolRejectsNoActionRequested() async throws {
        let tool = ExecuteAppUninstallTool(executor: MockAppUninstallExecutor())
        let result = await tool.call(
            input: ["operation_id": "op", "search_roots": ["/Applications"], "uninstall_bundle": false, "app": appInput()] as [String: Any],
            context: makeContext()
        )
        #expect(result.isError)
        #expect(result.content.contains("no_action_requested"))
    }

    @Test("tool drops support items with unknown category and still executes the rest")
    func toolDropsSupportItemsWithUnknownCategory() async throws {
        let executor = MockAppUninstallExecutor()
        let tool = ExecuteAppUninstallTool(executor: executor)

        let result = await tool.call(
            input: [
                "operation_id": "op-app-3",
                "search_roots": ["/Applications"],
                "uninstall_bundle": true,
                "app": appInput(),
                "support_data_items": [
                    ["category": "bogus_category", "path": "/x"],   // dropped (unknown category)
                    ["category": "cache", "path": "/y"],            // kept
                ],
            ] as [String: Any],
            context: makeContext()
        )
        #expect(!result.isError)
        let captured = try #require(await executor.captured())
        #expect(captured.supportDataItems.count == 1)
        #expect(captured.supportDataItems.first?.category == .cache)
    }

    // MARK: - surface

    @Test("tool defaults surface to run and honors chat")
    func toolSurfaceDefaultsAndOverride() async throws {
        let executor = MockAppUninstallExecutor()
        let tool = ExecuteAppUninstallTool(executor: executor)

        _ = await tool.call(
            input: ["operation_id": "op-surf-1", "search_roots": ["/Applications"], "uninstall_bundle": true, "app": appInput()] as [String: Any],
            context: makeContext()
        )
        let defaultCaptured = try #require(await executor.captured())
        #expect(defaultCaptured.surface == .run)

        _ = await tool.call(
            input: ["operation_id": "op-surf-2", "search_roots": ["/Applications"], "surface": "chat", "uninstall_bundle": true, "app": appInput()] as [String: Any],
            context: makeContext()
        )
        let chatCaptured = try #require(await executor.captured())
        #expect(chatCaptured.surface == .chat)
    }

    @Test("tool is a side-effecting (read-write) tool")
    func toolIsNotReadOnly() {
        let tool = ExecuteAppUninstallTool(executor: MockAppUninstallExecutor())
        #expect(tool.name == "execute_app_uninstall")
        #expect(tool.isReadOnly == false)
    }
}
