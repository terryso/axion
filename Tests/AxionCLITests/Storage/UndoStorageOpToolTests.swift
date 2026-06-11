import Testing
import Foundation
import OpenAgentSDK

import AxionCore
@testable import AxionCLI

@Suite("Undo Storage Op Tool")
struct UndoStorageOpToolTests {

    /// Records the captured request and returns a configurable result (nil simulates "nothing undoable").
    private actor MockStorageUndoer: StorageUndoing {
        private(set) var capturedRequest: UndoRequest?
        private let result: UndoResult?

        init(result: UndoResult?) {
            self.result = result
        }

        func undo(_ request: UndoRequest) async -> UndoResult? {
            capturedRequest = request
            return result
        }

        func captured() -> UndoRequest? { capturedRequest }
    }

    private func makeContext() -> ToolContext {
        ToolContext(cwd: "/tmp", toolUseId: "undo-test-\(UUID().uuidString)")
    }

    private func sampleUndoResult(op: String) -> UndoResult {
        var manifest = StorageManifest(
            operationId: op,
            createdAt: "2026-06-11T00:00:00Z",
            surface: .run,
            items: [StorageManifestItem(action: .move, sourcePath: "/a", targetPath: "/b", outcome: .succeeded)],
            status: .completed,
            errors: []
        )
        manifest.undoneAt = "2026-06-11T01:00:00Z"
        manifest.undoResults = [StorageUndoResult(sourcePath: "/a", action: .move, outcome: .restored)]
        return UndoResult(manifest: manifest, restored: 1, notRestored: 0, skipped: 0)
    }

    @Test("tool returns the updated manifest on a successful undo")
    func toolReturnsManifestOnSuccess() async throws {
        let undoer = MockStorageUndoer(result: sampleUndoResult(op: "op-undo-tool-1"))
        let tool = UndoStorageOpTool(undoer: undoer)

        let result = await tool.call(
            input: ["operation_id": "op-undo-tool-1"] as [String: Any],
            context: makeContext()
        )

        #expect(!result.isError)
        let manifest = try JSONDecoder().decode(StorageManifest.self, from: Data(result.content.utf8))
        #expect(manifest.operationId == "op-undo-tool-1")
        #expect(manifest.undoneAt != nil)
        #expect(manifest.undoResults?.first?.outcome == .restored)
    }

    @Test("tool returns no_undoable_manifest when undoer finds nothing")
    func toolReturnsNoUndoableManifestWhenNil() async throws {
        let undoer = MockStorageUndoer(result: nil)
        let tool = UndoStorageOpTool(undoer: undoer)

        let result = await tool.call(input: [:], context: makeContext())

        #expect(result.isError)
        #expect(result.content.contains("no_undoable_manifest"))
    }

    @Test("tool passes operation_id through to the undoer")
    func toolPassesOperationIdThrough() async throws {
        let undoer = MockStorageUndoer(result: sampleUndoResult(op: "op-undo-tool-2"))
        let tool = UndoStorageOpTool(undoer: undoer)

        _ = await tool.call(input: ["operation_id": "op-undo-tool-2"] as [String: Any], context: makeContext())
        let captured = try #require(await undoer.captured())
        #expect(captured.operationId == "op-undo-tool-2")
    }

    @Test("tool omits operation_id (undo most recent) when not provided")
    func toolOmitsOperationIdWhenAbsent() async throws {
        let undoer = MockStorageUndoer(result: sampleUndoResult(op: "op-undo-tool-3"))
        let tool = UndoStorageOpTool(undoer: undoer)

        _ = await tool.call(input: [:], context: makeContext())
        let captured = try #require(await undoer.captured())
        #expect(captured.operationId == nil)
    }

    @Test("tool treats empty operation_id as omitted")
    func toolTreatsEmptyOperationIdAsOmitted() async throws {
        let undoer = MockStorageUndoer(result: sampleUndoResult(op: "op-undo-tool-4"))
        let tool = UndoStorageOpTool(undoer: undoer)

        _ = await tool.call(input: ["operation_id": ""] as [String: Any], context: makeContext())
        let captured = try #require(await undoer.captured())
        #expect(captured.operationId == nil)
    }
}
