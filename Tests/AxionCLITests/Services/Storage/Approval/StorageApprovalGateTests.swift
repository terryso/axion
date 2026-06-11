import Testing
import Foundation
import OpenAgentSDK

import AxionCore
@testable import AxionCLI

@Suite("Storage Approval Gate")
struct StorageApprovalGateTests {

    private func storagePlanParams(_ sources: [String]) -> [String: Any] {
        [
            "operation_id": "op1",
            "items": sources.map { ["action": "trash", "source": $0] }
        ]
    }

    // MARK: - decide: non-storage tool

    @Test("decide returns nil for non-storage tools (caller falls through)")
    func decideNonStorageNil() async {
        let collector = MockStorageApprover(response: .cancel(operationId: "op1", surface: .run, collectedAt: "t"))
        let result = await StorageApprovalGate.decide(
            toolName: "Bash", input: ["command": "ls"], surface: .run,
            jsonOutput: false, isInteractive: true, collector: collector
        )
        #expect(result == nil)
        #expect(collector.capturedRequests.isEmpty)
    }

    // MARK: - decide: interactivity guards

    @Test("decide denies on non-TTY for run (before collect)")
    func decideNonInteractiveDenies() async throws {
        let collector = MockStorageApprover(response: .cancel(operationId: "op1", surface: .run, collectedAt: "t"))
        let result = await StorageApprovalGate.decide(
            toolName: "execute_storage_plan", input: storagePlanParams(["/a"]),
            surface: .run, jsonOutput: false, isInteractive: false, collector: collector
        )
        #expect(result?.behavior == .deny)
        #expect(try #require(result?.message).contains("approval_required"))
        #expect(collector.capturedRequests.isEmpty)   // 未进入 collect
    }

    @Test("decide denies on --json (AC #10)")
    func decideJsonDenies() async throws {
        let collector = MockStorageApprover(response: .cancel(operationId: "op1", surface: .run, collectedAt: "t"))
        let result = await StorageApprovalGate.decide(
            toolName: "execute_storage_plan", input: storagePlanParams(["/a"]),
            surface: .run, jsonOutput: true, isInteractive: true, collector: collector
        )
        #expect(result?.behavior == .deny)
        #expect(try #require(result?.message).contains("--json"))
        #expect(collector.capturedRequests.isEmpty)
    }

    @Test("decide embeds structured PlanSummary in non-interactive deny (AC #5/#10)")
    func decideNonInteractiveEmbedsSummary() async throws {
        let collector = MockStorageApprover(response: .cancel(operationId: "op1", surface: .run, collectedAt: "t"))
        let result = await StorageApprovalGate.decide(
            toolName: "execute_storage_plan", input: storagePlanParams(["/a"]),
            surface: .run, jsonOutput: false, isInteractive: false, collector: collector
        )
        let msg = try #require(result?.message)
        #expect(msg.contains("approval_required"))
        // 结构化 PlanSummary（snake_case、Codable）随 deny 输出，供带外确认消费。
        #expect(msg.contains("\"operation_id\""))
        #expect(msg.contains("\"risk_level\""))
        #expect(msg.contains("\"total_items\""))
        #expect(collector.capturedRequests.isEmpty)   // 未进入 collect
    }

    // MARK: - decide: outcome mapping

    @Test("decide allows when collector approves full plan")
    func decideAllow() async {
        let collector = MockStorageApprover(response: StorageApprovalResponse(
            operationId: "op1", surface: .run, action: .approvePlan,
            approvedItemKeys: ["/a"], collectedAt: "t"
        ))
        let result = await StorageApprovalGate.decide(
            toolName: "execute_storage_plan", input: storagePlanParams(["/a"]),
            surface: .run, jsonOutput: false, isInteractive: true, collector: collector
        )
        #expect(result?.behavior == .allow)
        #expect(collector.capturedRequests.count == 1)
        #expect(collector.capturedRequests.first?.items.first?.key == "/a")
    }

    @Test("decide returns deny-subset JSON when collector approves subset")
    func decideDenySubset() async throws {
        let collector = MockStorageApprover(response: StorageApprovalResponse(
            operationId: "op1", surface: .run, action: .approveItem,
            approvedItemKeys: ["/a"], collectedAt: "t"
        ))
        let result = await StorageApprovalGate.decide(
            toolName: "execute_storage_plan", input: storagePlanParams(["/a", "/b"]),
            surface: .run, jsonOutput: false, isInteractive: true, collector: collector
        )
        #expect(result?.behavior == .deny)
        #expect(try #require(result?.message).contains("approved_subset"))
        #expect(try #require(result?.message).contains("/a"))
    }

    @Test("decide denies user_cancelled when collector cancels")
    func decideCancel() async throws {
        let collector = MockStorageApprover(response: .cancel(operationId: "op1", surface: .run, collectedAt: "t"))
        let result = await StorageApprovalGate.decide(
            toolName: "execute_storage_plan", input: storagePlanParams(["/a"]),
            surface: .run, jsonOutput: false, isInteractive: true, collector: collector
        )
        #expect(result?.behavior == .deny)
        #expect(try #require(result?.message).contains("user_cancelled"))
    }

    // MARK: - decide: telegram surface (non-interactive allowed; reserves + denies)

    @Test("decide telegram proceeds non-interactively and denies via cancel")
    func decideTelegramReserveDeny() async throws {
        let collector = TelegramApprovalReserve(now: { "t" })
        let result = await StorageApprovalGate.decide(
            toolName: "execute_storage_plan", input: storagePlanParams(["/a"]),
            surface: .telegram, jsonOutput: false, isInteractive: false, collector: collector
        )
        #expect(result?.behavior == .deny)   // 保守 cancel → deny
        #expect(try #require(result?.message).contains("user_cancelled"))
    }

    // MARK: - makeRunCanUseTool wraps decide

    @Test("makeRunCanUseTool allows non-storage tool (via decide fallthrough)")
    func runCanUseToolNonStorage() async {
        let collector = MockStorageApprover(response: .cancel(operationId: "op1", surface: .run, collectedAt: "t"))
        let fn = StorageApprovalGate.makeRunCanUseTool(collector: collector, isInteractiveFn: { true }, jsonOutput: false)
        let stub = StubTool(name: "Read", readOnly: true)
        let result = await fn(stub, ["x"], ToolContext(cwd: "/tmp"))
        #expect(result?.behavior == .allow)
    }
}

/// 轻量 ToolProtocol 桩，仅用于触发 canUseTool 闭包（不执行真实逻辑）。
struct StubTool: ToolProtocol {
    let toolName: String
    let readOnly: Bool
    var name: String { toolName }
    var description: String { "stub" }
    var inputSchema: ToolInputSchema { [:] }
    var isReadOnly: Bool { readOnly }
    init(name: String, readOnly: Bool) { self.toolName = name; self.readOnly = readOnly }
    func call(input: Any, context: ToolContext) async -> ToolResult {
        ToolResult(toolUseId: "stub", content: "ok", isError: false)
    }
}
