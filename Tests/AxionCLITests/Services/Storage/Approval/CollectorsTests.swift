import Testing
import Foundation

import AxionCore
@testable import AxionCLI

@Suite("Storage Approval Collectors")
struct CollectorsTests {

    /// 线程安全的脚本化 I/O：按序返回预设输入、捕获所有输出，供 collector 闭包注入。
    final class ScriptedIO: @unchecked Sendable {
        private var inputs: [String]
        private(set) var outputs: [String] = []
        private let lock = NSLock()

        init(inputs: [String]) { self.inputs = inputs }

        func read() -> String? {
            lock.lock(); defer { lock.unlock() }
            return inputs.isEmpty ? nil : inputs.removeFirst()
        }
        func write(_ s: String) {
            lock.lock(); defer { lock.unlock() }
            outputs.append(s)
        }
    }

    // MARK: - 工具：构造请求

    private func item(
        _ key: String,
        action: StorageAction = .trash,
        risk: RiskLevel = .low,
        dataRisk: DataRisk? = .low,
        requiresExplicit: Bool = false,
        category: String? = nil,
        targetPath: String? = nil,
        reason: String = "r"
    ) -> StorageApprovalItem {
        let evidence = category.map {
            StorageEvidence(
                rule: "category:\($0); kind:document; action:\(action.rawValue)",
                source: "scan",
                confidence: .high
            )
        }
        return StorageApprovalItem(
            key: key, action: action, sourcePath: key, targetPath: targetPath,
            sizeBytes: 100, riskLevel: risk, dataRisk: dataRisk,
            reason: reason, requiresExplicitApproval: requiresExplicit, evidence: evidence
        )
    }

    private func request(_ items: [StorageApprovalItem], surface: StorageSurface = .run, typed: Bool = false, candidates: [String]? = nil) -> StorageApprovalRequest {
        let summary = PlanSummary.build(operationId: "op", surface: surface, items: items, reversible: true, requiresTypedConfirmation: typed)
        return StorageApprovalRequest(
            operationId: "op", surface: surface, planSummary: summary, items: items,
            requiresTypedConfirmation: typed, typedConfirmationCandidates: candidates
        )
    }

    // MARK: - RunApprovalCollector

    @Test("RunApprovalCollector [a] approves whole plan")
    func runApprove() async {
        let io = ScriptedIO(inputs: ["a"])
        let collector = RunApprovalCollector(writeStdout: { io.write($0) }, readLine: { io.read() }, now: { "t" })
        let resp = await collector.collect(request: request([item("/a"), item("/b")]), policy: SurfacePolicy.for(.run))
        #expect(resp.action == .approvePlan)
        #expect(resp.approvedItemKeys == ["/a", "/b"])
        #expect(resp.typedConfirmationPayload == nil)
    }

    @Test("RunApprovalCollector other input cancels (safe default)")
    func runCancel() async {
        let io = ScriptedIO(inputs: ["n"])
        let collector = RunApprovalCollector(writeStdout: { io.write($0) }, readLine: { io.read() }, now: { "t" })
        let resp = await collector.collect(request: request([item("/a")]), policy: SurfacePolicy.for(.run))
        #expect(resp.action == .cancel)
        #expect(resp.approvedItemKeys.isEmpty)
    }

    @Test("RunApprovalCollector empty input cancels")
    func runEmptyInput() async {
        let io = ScriptedIO(inputs: [""])
        let collector = RunApprovalCollector(writeStdout: { io.write($0) }, readLine: { io.read() }, now: { "t" })
        let resp = await collector.collect(request: request([item("/a")]), policy: SurfacePolicy.for(.run))
        #expect(resp.action == .cancel)
    }

    @Test("RunApprovalCollector typed confirmation captured after approval")
    func runTypedConfirm() async {
        let io = ScriptedIO(inputs: ["a", "Foo"])
        let collector = RunApprovalCollector(writeStdout: { io.write($0) }, readLine: { io.read() }, now: { "t" })
        let resp = await collector.collect(request: request([item("/a")], typed: true, candidates: ["Foo"]), policy: SurfacePolicy.for(.run))
        #expect(resp.action == .approvePlan)
        #expect(resp.typedConfirmationPayload == "Foo")
    }

    // MARK: - ChatApprovalCollector

    @Test("ChatApprovalCollector per-item subset → approveItem")
    func chatSubset() async {
        let io = ScriptedIO(inputs: ["y", "n", "y"])
        let collector = ChatApprovalCollector(writeStdout: { io.write($0) }, readLine: { io.read() }, now: { "t" })
        let resp = await collector.collect(request: request([item("/a"), item("/b"), item("/c")]), policy: SurfacePolicy.for(.chat))
        #expect(resp.action == .approveItem)
        #expect(resp.approvedItemKeys == ["/a", "/c"])
        #expect(resp.rejectedItemKeys == ["/b"])
    }

    @Test("ChatApprovalCollector [a] approves all remaining → approvePlan")
    func chatApproveAll() async {
        let io = ScriptedIO(inputs: ["a"])
        let collector = ChatApprovalCollector(writeStdout: { io.write($0) }, readLine: { io.read() }, now: { "t" })
        let resp = await collector.collect(request: request([item("/a"), item("/b"), item("/c")]), policy: SurfacePolicy.for(.chat))
        #expect(resp.action == .approvePlan)
        #expect(resp.approvedItemKeys == ["/a", "/b", "/c"])
    }

    @Test("ChatApprovalCollector [q] cancels")
    func chatCancel() async {
        let io = ScriptedIO(inputs: ["q"])
        let collector = ChatApprovalCollector(writeStdout: { io.write($0) }, readLine: { io.read() }, now: { "t" })
        let resp = await collector.collect(request: request([item("/a"), item("/b")]), policy: SurfacePolicy.for(.chat))
        #expect(resp.action == .cancel)
        #expect(resp.approvedItemKeys.isEmpty)
    }

    @Test("ChatApprovalCollector groups items by category evidence")
    func chatCategoryGroupApproval() async {
        let io = ScriptedIO(inputs: ["y", "n"])
        let collector = ChatApprovalCollector(writeStdout: { io.write($0) }, readLine: { io.read() }, now: { "t" })
        let items = [
            item("/tmp/invoice-a.pdf", category: "receipts"),
            item("/tmp/invoice-b.pdf", category: "receipts"),
            item("/tmp/archive.zip", category: "archives"),
        ]

        let resp = await collector.collect(request: request(items, surface: .chat), policy: SurfacePolicy.for(.chat))

        #expect(resp.action == .approveItem)
        #expect(resp.approvedItemKeys == ["/tmp/invoice-a.pdf", "/tmp/invoice-b.pdf"])
        #expect(resp.rejectedItemKeys == ["/tmp/archive.zip"])
        let output = io.outputs.joined()
        #expect(output.contains("按分组确认"))
        #expect(output.contains("receipts"))
    }

    @Test("ChatApprovalCollector detail keeps item prompt open")
    func chatItemDetailThenApprove() async {
        let io = ScriptedIO(inputs: ["d", "y"])
        let collector = ChatApprovalCollector(writeStdout: { io.write($0) }, readLine: { io.read() }, now: { "t" })

        let resp = await collector.collect(request: request([item("/tmp/a.txt", reason: "inspect before approval")], surface: .chat), policy: SurfacePolicy.for(.chat))

        #expect(resp.action == .approvePlan)
        #expect(resp.approvedItemKeys == ["/tmp/a.txt"])
        let output = io.outputs.joined()
        #expect(output.contains("详情"))
        #expect(output.contains("inspect before approval"))
    }

    // MARK: - TelegramApprovalReserve

    @Test("TelegramApprovalReserve reserves only offerable items and returns cancel")
    func telegramReserve() async throws {
        let items = [
            item("/safe", action: .trash, dataRisk: .low),
            item("/hi", action: .trash, dataRisk: .high),
            item("/explicit", action: .trash, dataRisk: .low, requiresExplicit: true),
            item("/uninstall", action: .uninstallApp),
        ]
        let collector = TelegramApprovalReserve(now: { "t" })
        let resp = await collector.collect(request: request(items, surface: .telegram), policy: SurfacePolicy.for(.telegram))

        // 保守：始终 cancel（不在本 Story 远程执行）。
        #expect(resp.action == .cancel)
        #expect(resp.approvedItemKeys.isEmpty)

        // 仅 /safe 远程可批准 → 仅 1 个按钮。
        let buttons = try #require(resp.remoteReserved?.inlineButtonsReserved)
        #expect(buttons.count == 1)
        #expect(buttons.first?.callbackData == "approve:/safe")
        #expect(resp.remoteReserved?.detailCursor == nil)   // 单页无游标
    }

    @Test("TelegramApprovalReserve no offerable items → nil buttons")
    func telegramNoOfferable() async {
        let items = [item("/hi", action: .trash, dataRisk: .forbidden)]
        let collector = TelegramApprovalReserve(now: { "t" })
        let resp = await collector.collect(request: request(items, surface: .telegram), policy: SurfacePolicy.for(.telegram))
        #expect(resp.action == .cancel)
        #expect(resp.remoteReserved?.inlineButtonsReserved == nil)
    }
}
