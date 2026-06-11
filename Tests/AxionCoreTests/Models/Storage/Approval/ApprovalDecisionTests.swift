import Testing
import Foundation

@testable import AxionCore

@Suite("Storage Approval Decision Logic")
struct ApprovalDecisionTests {

    private func item(_ key: String, action: StorageAction = .trash, risk: RiskLevel = .low, dataRisk: DataRisk? = .low, size: Int64 = 100, requiresExplicit: Bool = false) -> StorageApprovalItem {
        StorageApprovalItem(
            key: key, action: action, sourcePath: key, targetPath: nil,
            sizeBytes: size, riskLevel: risk, dataRisk: dataRisk,
            reason: "r", requiresExplicitApproval: requiresExplicit, evidence: nil
        )
    }

    private func request(items: [StorageApprovalItem], surface: StorageSurface = .run, typed: Bool = false, candidates: [String]? = nil) -> StorageApprovalRequest {
        let summary = PlanSummary.build(operationId: "op", surface: surface, items: items, reversible: true, requiresTypedConfirmation: typed)
        return StorageApprovalRequest(
            operationId: "op", surface: surface, planSummary: summary, items: items,
            requiresTypedConfirmation: typed, typedConfirmationCandidates: candidates
        )
    }

    // MARK: - PlanSummary aggregation + render

    @Test("PlanSummary aggregates risk to max and sorts top by size")
    func summaryAggregation() {
        let items = [
            item("/a", risk: .low, size: 10),
            item("/b", risk: .high, size: 999),
            item("/c", risk: .medium, size: 500),
        ]
        let summary = PlanSummary.build(operationId: "op", surface: .run, items: items, reversible: true, requiresTypedConfirmation: false, topN: 2)
        #expect(summary.riskLevel == .high)
        #expect(summary.totalItems == 3)
        #expect(summary.topItems.map(\.key) == ["/b", "/c"])   // 按大小降序
        #expect(summary.truncatedCount == 1)
    }

    @Test("PlanSummary.renderTerminal emits surface, risk, counts")
    func renderTerminalContent() {
        let summary = PlanSummary.build(
            operationId: "op1", surface: .run,
            items: [item("/a", action: .move, size: 2048)],
            reversible: true, requiresTypedConfirmation: false
        )
        let text = summary.renderTerminal()
        #expect(text.contains("run"))
        #expect(text.contains("move"))
        #expect(text.contains("/a"))
    }

    @Test("PlanSummary.renderJSON is stable keyed JSON containing operation_id")
    func renderJSONStable() throws {
        let summary = PlanSummary.build(operationId: "op1", surface: .chat, items: [item("/a")], reversible: true, requiresTypedConfirmation: false)
        let json = summary.renderJSON()
        #expect(json.contains("\"operation_id\""))
        #expect(json.contains("\"total_items\""))
        #expect(json.hasPrefix("{"))
    }

    @Test("PlanSummary.renderRemoteCompressed paginates long summary")
    func renderRemoteCompressedPaginates() {
        // 构造超长 summary：人为塞入超长 reason。
        var items: [StorageApprovalItem] = []
        for i in 0..<200 {
            items.append(StorageApprovalItem(
                key: "/path/\(i)", action: .trash, sourcePath: "/path/\(i)",
                sizeBytes: Int64(i), riskLevel: .medium,
                reason: String(repeating: "x", count: 30), requiresExplicitApproval: false, evidence: nil
            ))
        }
        let summary = PlanSummary.build(operationId: "op", surface: .telegram, items: items, reversible: true, requiresTypedConfirmation: false)
        let pages = summary.renderRemoteCompressed(maxChars: 200)
        #expect(pages.count > 1)
        for (idx, page) in pages.enumerated() {
            #expect(page.count <= 200 + 16)  // 含 [pN/M] 前缀余量
            if pages.count > 1 {
                #expect(page.contains("[p\(idx + 1)/\(pages.count)]"))
            }
        }
    }

    // MARK: - SurfacePolicy

    @Test("SurfacePolicy.for telegram is conservative")
    func telegramPolicyConservative() {
        let p = SurfacePolicy.for(.telegram)
        #expect(p.allowedActions == [.scanOnly, .trash])
        #expect(p.allowsTypedConfirmation == false)
        #expect(p.allowsHighDataRisk == false)
    }

    @Test("SurfacePolicy.for run/chat allow all actions")
    func localPolicyOpen() {
        #expect(SurfacePolicy.for(.run).allowedActions.contains(.uninstallApp))
        #expect(SurfacePolicy.for(.run).allowsTypedConfirmation)
        #expect(SurfacePolicy.for(.chat).allowsHighDataRisk)
    }

    @Test("offerable strips forbidden items on telegram, keeps all locally")
    func offerableFiltering() {
        let items = [
            item("/safe", action: .trash, dataRisk: .low),
            item("/hi", action: .trash, dataRisk: .high),
            item("/explicit", action: .trash, dataRisk: .low, requiresExplicit: true),
            item("/uninstall", action: .uninstallApp),
        ]
        let tg = SurfacePolicy.offerable(items: items, for: .telegram)
        #expect(tg.map(\.key) == ["/safe"])   // 仅低风险、非显式、动作在白名单

        let run = SurfacePolicy.offerable(items: items, for: .run)
        #expect(run.count == items.count)     // 本地全保留
    }

    @Test("isRemotelyApprovable forbids forbidden data risk on telegram")
    func remotelyApprovableForbidden() {
        let p = SurfacePolicy.for(.telegram)
        #expect(!p.isRemotelyApprovable(item: item("/f", dataRisk: .forbidden)))
        #expect(!p.isRemotelyApprovable(item: item("/u", action: .uninstallApp)))
        #expect(p.isRemotelyApprovable(item: item("/ok", action: .trash, dataRisk: .low)))
    }

    // MARK: - validateTypedConfirmation

    @Test("typed confirmation ignores case and whitespace, matches any candidate")
    func typedConfirmationValidation() {
        #expect(StorageApprovalDecision.validateTypedConfirmation(payload: "  Foo  ", expected: ["foo", "com.foo"]))
        #expect(StorageApprovalDecision.validateTypedConfirmation(payload: "COM.FOO", expected: ["foo", "com.foo"]))
        #expect(!StorageApprovalDecision.validateTypedConfirmation(payload: "bar", expected: ["foo"]))
        #expect(!StorageApprovalDecision.validateTypedConfirmation(payload: "   ", expected: ["foo"]))
        #expect(!StorageApprovalDecision.validateTypedConfirmation(payload: "foo", expected: []))
    }

    // MARK: - applyDecision / deriveApprovedSubset

    @Test("applyDecision filters by approved keys and respects policy")
    func applyDecisionFilters() {
        let items = [item("/a"), item("/b"), item("/c")]
        let req = request(items: items)
        let resp = StorageApprovalResponse(operationId: "op", surface: .run, action: .approveItem, approvedItemKeys: ["/a", "/c"], collectedAt: "t")
        let set = StorageApprovalDecision.applyDecision(request: req, response: resp, policy: SurfacePolicy.for(.run))
        #expect(set.approvedItems.map(\.key) == ["/a", "/c"])
        #expect(set.isSubset)
    }

    @Test("applyDecision strips non-approvable on telegram")
    func applyDecisionTelegramStrip() {
        let items = [item("/safe", dataRisk: .low), item("/hi", dataRisk: .high)]
        let req = request(items: items, surface: .telegram)
        let resp = StorageApprovalResponse(operationId: "op", surface: .telegram, action: .approvePlan, approvedItemKeys: ["/safe", "/hi"], collectedAt: "t")
        let set = StorageApprovalDecision.applyDecision(request: req, response: resp, policy: SurfacePolicy.for(.telegram))
        #expect(set.approvedItems.map(\.key) == ["/safe"])   // /hi 被策略剔除
        #expect(set.rejectedItemKeys.contains("/hi"))
    }

    @Test("deriveApprovedSubset returns raw key-matched items")
    func deriveSubsetRaw() {
        let items = [item("/a"), item("/b")]
        let req = request(items: items)
        let resp = StorageApprovalResponse(operationId: "op", surface: .run, action: .approveItem, approvedItemKeys: ["/b"], collectedAt: "t")
        let subset = StorageApprovalDecision.deriveApprovedSubset(response: resp, request: req)
        #expect(subset.map(\.key) == ["/b"])
    }

    // MARK: - resolveOutcome

    @Test("resolveOutcome cancel/reject -> deny user_cancelled")
    func resolveCancel() {
        let req = request(items: [item("/a")])
        let cancel = StorageApprovalResponse.cancel(operationId: "op", surface: .run, collectedAt: "t")
        #expect(StorageApprovalDecision.resolveOutcome(request: req, response: cancel, policy: SurfacePolicy.for(.run)) == .deny("user_cancelled"))

        let reject = StorageApprovalResponse(operationId: "op", surface: .run, action: .rejectItem, approvedItemKeys: [], collectedAt: "t")
        #expect(StorageApprovalDecision.resolveOutcome(request: req, response: reject, policy: SurfacePolicy.for(.run)) == .deny("user_cancelled"))
    }

    @Test("resolveOutcome approvePlan full -> allow")
    func resolveAllowFull() {
        let items = [item("/a"), item("/b")]
        let req = request(items: items)
        let resp = StorageApprovalResponse(operationId: "op", surface: .run, action: .approvePlan, approvedItemKeys: ["/a", "/b"], collectedAt: "t")
        #expect(StorageApprovalDecision.resolveOutcome(request: req, response: resp, policy: SurfacePolicy.for(.run)) == .allow)
    }

    @Test("resolveOutcome subset -> denySubset")
    func resolveSubset() {
        let items = [item("/a"), item("/b")]
        let req = request(items: items)
        let resp = StorageApprovalResponse(operationId: "op", surface: .run, action: .approveItem, approvedItemKeys: ["/a"], collectedAt: "t")
        let outcome = StorageApprovalDecision.resolveOutcome(request: req, response: resp, policy: SurfacePolicy.for(.run))
        if case .denySubset(let set) = outcome {
            #expect(set.approvedItems.map(\.key) == ["/a"])
        } else {
            Issue.record("expected denySubset, got \(outcome)")
        }
    }

    @Test("resolveOutcome typed fail -> deny typed_confirmation_failed")
    func resolveTypedFail() {
        let items = [item("/a")]
        let req = request(items: items, typed: true, candidates: ["Foo"])
        // payload 不匹配候选。
        let resp = StorageApprovalResponse(operationId: "op", surface: .run, action: .approvePlan, approvedItemKeys: ["/a"], typedConfirmationPayload: "bar", collectedAt: "t")
        #expect(StorageApprovalDecision.resolveOutcome(request: req, response: resp, policy: SurfacePolicy.for(.run)) == .deny("typed_confirmation_failed"))
    }

    @Test("resolveOutcome typed pass -> allow")
    func resolveTypedPass() {
        let items = [item("/a")]
        let req = request(items: items, typed: true, candidates: ["Foo"])
        let resp = StorageApprovalResponse(operationId: "op", surface: .run, action: .approvePlan, approvedItemKeys: ["/a"], typedConfirmationPayload: "foo", collectedAt: "t")
        #expect(StorageApprovalDecision.resolveOutcome(request: req, response: resp, policy: SurfacePolicy.for(.run)) == .allow)
    }

    @Test("resolveOutcome all stripped on telegram -> deny policy_violation")
    func resolvePolicyViolation() {
        // telegram 仅高危项 → offerable 为空 → approvePlan 但 applyDecision 全剔除 → 空 → policy_violation。
        let items = [item("/hi", dataRisk: .high)]
        let req = request(items: items, surface: .telegram)
        let resp = StorageApprovalResponse(operationId: "op", surface: .telegram, action: .approvePlan, approvedItemKeys: ["/hi"], collectedAt: "t")
        #expect(StorageApprovalDecision.resolveOutcome(request: req, response: resp, policy: SurfacePolicy.for(.telegram)) == .deny("policy_violation"))
    }

    // MARK: - renderSubsetRecall

    @Test("renderSubsetRecall emits structured approved_subset JSON")
    func subsetRecallRender() {
        let items = [item("/a"), item("/b")]
        let req = request(items: items)
        let resp = StorageApprovalResponse(operationId: "op", surface: .run, action: .approveItem, approvedItemKeys: ["/a"], collectedAt: "t")
        let set = StorageApprovalDecision.applyDecision(request: req, response: resp, policy: SurfacePolicy.for(.run))
        let text = StorageApprovalDecision.renderSubsetRecall(set)
        #expect(text.contains("\"type\":\"approved_subset\""))
        #expect(text.contains("\"approved_subset\""))
        #expect(text.contains("/a"))
    }
}
