import Foundation

import AxionCore

/// run 入口审批收集器：终端全计划确认（`approvePlan` / `cancel`）。
///
/// - 不直接读写 stdin/stdout，通过注入闭包（`writeStdout` / `readLine`）完成 I/O，便于单元测试 Mock。
/// - 任何读取/解析失败 → 返回 `cancel`（安全默认）。
/// - typed 确认（App 卸载）在批准后二次询问，载荷写入 `typedConfirmationPayload`，由纯决策函数校验。
struct RunApprovalCollector: StorageApproving {

    let writeStdout: @Sendable (String) -> Void
    let readLine: @Sendable () -> String?
    let now: @Sendable () -> String

    init(
        writeStdout: @escaping @Sendable (String) -> Void,
        readLine: @escaping @Sendable () -> String?,
        now: @escaping @Sendable () -> String = { ISO8601DateFormatter().string(from: Date()) }
    ) {
        self.writeStdout = writeStdout
        self.readLine = readLine
        self.now = now
    }

    func collect(request: StorageApprovalRequest, policy: SurfacePolicy) async -> StorageApprovalResponse {
        writeStdout("\n" + request.planSummary.renderTerminal() + "\n")
        writeStdout("\n是否批准执行以上计划？  [a] 批准全部   [其他任意键] 取消：")

        let decision = (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let approved = (decision == "a" || decision == "y" || decision == "yes" || decision == "批准")
        guard approved else {
            writeStdout("已取消。\n")
            return StorageApprovalResponse.cancel(
                operationId: request.operationId,
                surface: request.surface,
                collectedAt: now()
            )
        }

        // App 卸载（uninstall bundle）：批准后二次 typed 确认。
        var typedPayload: String? = nil
        if request.requiresTypedConfirmation,
           let candidates = request.typedConfirmationCandidates,
           let hint = candidates.first, !hint.isEmpty {
            writeStdout("\n该操作将卸载 App，请输入应用名以二次确认（\(hint)）：")
            typedPayload = readLine()
        }

        writeStdout("✓ 已批准，开始执行...\n")
        return StorageApprovalResponse(
            operationId: request.operationId,
            surface: request.surface,
            action: .approvePlan,
            approvedItemKeys: request.items.map { $0.key },
            rejectedItemKeys: [],
            typedConfirmationPayload: typedPayload,
            remoteReserved: nil,
            collectedAt: now()
        )
    }
}
