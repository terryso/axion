import Testing
import Foundation

@testable import AxionCore

@Suite("Storage Approval Models Codec")
struct ApprovalModelsCodecTests {

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - StorageApprovalAction

    @Test("StorageApprovalAction rawValue uses snake_case")
    func actionSnakeCase() throws {
        #expect(StorageApprovalAction(rawValue: "approve_plan") == .approvePlan)
        #expect(StorageApprovalAction(rawValue: "approve_item") == .approveItem)
        #expect(StorageApprovalAction(rawValue: "reject_item") == .rejectItem)
        #expect(StorageApprovalAction(rawValue: "cancel") == .cancel)
        #expect(try roundTrip(StorageApprovalAction.approveItem) == .approveItem)
    }

    // MARK: - StorageApprovalItem

    @Test("StorageApprovalItem round-trip preserves snake_case keys")
    func itemRoundTrip() throws {
        let item = StorageApprovalItem(
            key: "/a/b",
            action: .move,
            sourcePath: "/a/b",
            targetPath: "/c/d",
            sizeBytes: 4096,
            riskLevel: .medium,
            dataRisk: .medium,
            reason: "大文件",
            requiresExplicitApproval: true,
            evidence: StorageEvidence(rule: "large_file", source: "scan", confidence: .high)
        )
        let decoded = try roundTrip(item)
        #expect(decoded == item)

        let json = try #require(String(data: JSONEncoder().encode(item), encoding: .utf8))
        #expect(json.contains("\"source_path\""))
        #expect(json.contains("\"target_path\""))
        #expect(json.contains("\"size_bytes\""))
        #expect(json.contains("\"risk_level\""))
        #expect(json.contains("\"data_risk\""))
        #expect(json.contains("\"requires_explicit_approval\""))
    }

    @Test("StorageApprovalItem decodes with defaults when fields missing")
    func itemMissingDefaults() throws {
        let json = "{\"key\": \"/x\"}".data(using: .utf8)!
        let item = try JSONDecoder().decode(StorageApprovalItem.self, from: json)
        #expect(item.key == "/x")
        #expect(item.action == .scanOnly)
        #expect(item.sizeBytes == 0)
        #expect(item.riskLevel == .low)
        #expect(item.dataRisk == nil)
        #expect(item.requiresExplicitApproval == false)
    }

    // MARK: - RemoteApprovalReserved / Button

    @Test("RemoteApprovalReserved round-trip and defaults")
    func remoteReservedRoundTrip() throws {
        let reserved = RemoteApprovalReserved(
            pendingMessageId: 42,
            inlineButtonsReserved: [RemoteApprovalButton(label: "批准", callbackData: "approve:k")],
            expiresAt: "2026-06-12T00:00:00Z",
            detailCursor: "page:2"
        )
        let decoded = try roundTrip(reserved)
        #expect(decoded == reserved)

        let json = try #require(String(data: JSONEncoder().encode(reserved), encoding: .utf8))
        #expect(json.contains("\"pending_message_id\""))
        #expect(json.contains("\"inline_buttons_reserved\""))
        #expect(json.contains("\"callback_data\""))
        #expect(json.contains("\"detail_cursor\""))

        let empty = try JSONDecoder().decode(RemoteApprovalReserved.self, from: "{}".data(using: .utf8)!)
        #expect(empty.pendingMessageId == nil)
        #expect(empty.inlineButtonsReserved == nil)
    }

    // MARK: - StorageApprovalResponse invariant

    @Test("cancel response forces approvedItemKeys empty (init)")
    func cancelForcesEmptyInit() throws {
        // 构造时即使传入 approvedItemKeys，cancel 也应清空。
        let resp = StorageApprovalResponse(
            operationId: "op1", surface: .run, action: .cancel,
            approvedItemKeys: ["/a", "/b"], rejectedItemKeys: [],
            collectedAt: "t"
        )
        #expect(resp.approvedItemKeys.isEmpty)
    }

    @Test("cancel response forces approvedItemKeys empty (decode)")
    func cancelForcesEmptyDecode() throws {
        // JSON 中 cancel 仍带 approved_item_keys 时，解码后应被强制清空。
        let json = """
        {"operation_id":"op1","surface":"run","action":"cancel","approved_item_keys":["/a","/b"],"collected_at":"t"}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(StorageApprovalResponse.self, from: json)
        #expect(resp.action == .cancel)
        #expect(resp.approvedItemKeys.isEmpty)
    }

    @Test("cancel() factory produces safe default")
    func cancelFactory() throws {
        let resp = StorageApprovalResponse.cancel(operationId: "op1", surface: .chat, collectedAt: "t")
        #expect(resp.action == .cancel)
        #expect(resp.approvedItemKeys.isEmpty)
        #expect(try roundTrip(resp) == resp)
    }

    @Test("StorageApprovalResponse round-trip")
    func responseRoundTrip() throws {
        let resp = StorageApprovalResponse(
            operationId: "op1", surface: .chat, action: .approveItem,
            approvedItemKeys: ["/a"], rejectedItemKeys: ["/b"],
            typedConfirmationPayload: "Foo", collectedAt: "t"
        )
        let decoded = try roundTrip(resp)
        #expect(decoded == resp)
    }

    // MARK: - StorageApprovalRequest

    @Test("StorageApprovalRequest round-trip preserves typed candidates")
    func requestRoundTrip() throws {
        let summary = PlanSummary.build(
            operationId: "op1", surface: .chat,
            items: [StorageApprovalItem(key: "/a", action: .trash, sourcePath: "/a", sizeBytes: 10, riskLevel: .low, reason: "r", requiresExplicitApproval: false)],
            reversible: true, requiresTypedConfirmation: true
        )
        let req = StorageApprovalRequest(
            operationId: "op1", surface: .chat, planSummary: summary,
            items: summary.topItems,
            requiresTypedConfirmation: true,
            userRequest: "清理",
            typedConfirmationCandidates: ["Foo", "com.foo"]
        )
        let decoded = try roundTrip(req)
        #expect(decoded.operationId == "op1")
        #expect(decoded.typedConfirmationCandidates == ["Foo", "com.foo"])
        #expect(decoded.requiresTypedConfirmation == true)
    }

    @Test("StorageApprovalRequest decodes with safe defaults on empty json")
    func requestEmptyDefaults() throws {
        let req = try JSONDecoder().decode(StorageApprovalRequest.self, from: "{}".data(using: .utf8)!)
        #expect(req.surface == .run)
        #expect(req.items.isEmpty)
        #expect(req.requiresTypedConfirmation == false)
        #expect(req.typedConfirmationCandidates == nil)
    }

    // MARK: - PlanSummary codec

    @Test("PlanSummary round-trip preserves aggregates")
    func planSummaryRoundTrip() throws {
        let items = [
            StorageApprovalItem(key: "/a", action: .move, sourcePath: "/a", sizeBytes: 100, riskLevel: .low, reason: "r", requiresExplicitApproval: false),
            StorageApprovalItem(key: "/b", action: .trash, sourcePath: "/b", sizeBytes: 500, riskLevel: .high, reason: "r", requiresExplicitApproval: true),
        ]
        let summary = PlanSummary.build(operationId: "op", surface: .run, items: items, reversible: true, requiresTypedConfirmation: false)
        let decoded = try roundTrip(summary)
        #expect(decoded == summary)
        #expect(decoded.totalItems == 2)
        #expect(decoded.riskLevel == .high)
        #expect(decoded.countsByAction[.move] == 1)
        #expect(decoded.countsByAction[.trash] == 1)
        #expect(decoded.countsByRisk[.high] == 1)
    }
}
