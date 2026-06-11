import Foundation

import AxionCore

/// telegram 入口审批收集器（Story 39.4 MVP）：保守策略——**预留字段 + 不执行**。
///
/// 本 Story 不发送 telegram 消息、不创建 inline keyboard、不接受远程审批（约束：不修改
/// `Sources/AxionCLI/Services/Telegram/`、不联网）。收集器仅：
/// - 按 `SurfacePolicy.for(.telegram)` 过滤出可批准项（scan_only/trash、剔除高危/需 typed 项）；
/// - 生成 `RemoteApprovalReserved`（inline 按钮描述 + 压缩摘要游标），供后续 Story 接入真实远程 UI；
/// - 返回 `cancel`（安全默认）→ 门 deny，远程入口不在本 Story 执行有副作用的 storage 操作。
struct TelegramApprovalReserve: StorageApproving {

    let now: @Sendable () -> String

    init(now: @escaping @Sendable () -> String = { ISO8601DateFormatter().string(from: Date()) }) {
        self.now = now
    }

    func collect(request: StorageApprovalRequest, policy: SurfacePolicy) async -> StorageApprovalResponse {
        // 仅保留「远程可批准」项作为按钮（scan_only/trash、非高危、非需显式确认）。
        let offerable = policy.offerable(items: request.items)
        let buttons: [RemoteApprovalButton] = offerable.map {
            RemoteApprovalButton(label: label(for: $0), callbackData: "approve:\($0.key)")
        }
        // 压缩摘要分页（telegram 单条 ≤ 900 字符）。
        let pages = request.planSummary.renderRemoteCompressed()
        let cursor = pages.count > 1 ? "page:2" : nil

        let reserved = RemoteApprovalReserved(
            pendingMessageId: nil,                 // 未发送消息 → 无 message id
            inlineButtonsReserved: buttons.isEmpty ? nil : buttons,
            expiresAt: nil,                        // 预留：后续接入远程过期策略
            detailCursor: cursor
        )

        // 保守：远程入口不执行 → cancel（approvedItemKeys 由不变式强制为空）。
        return StorageApprovalResponse(
            operationId: request.operationId,
            surface: request.surface,
            action: .cancel,
            approvedItemKeys: [],
            rejectedItemKeys: request.items.map { $0.key },
            typedConfirmationPayload: nil,
            remoteReserved: reserved,
            collectedAt: now()
        )
    }

    /// 按钮文案（截断过长路径，仅保留尾部）。
    private func label(for item: StorageApprovalItem) -> String {
        let action = item.action.rawValue
        let path = item.sourcePath.count > 40
            ? "…" + String(item.sourcePath.suffix(39))
            : item.sourcePath
        return "[\(action)] \(path)"
    }
}
