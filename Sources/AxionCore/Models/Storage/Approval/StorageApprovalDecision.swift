import Foundation

/// 已批准的执行集（`applyDecision` 派生；纯值类型，无 I/O / 无 SDK 依赖）。
public struct ApprovedExecutionSet: Equatable, Sendable {
    /// 经 policy 裁剪后实际可执行的项。
    public let approvedItems: [StorageApprovalItem]
    /// 被拒 / 被裁剪项的 key（含用户拒绝 + policy 剔除）。
    public let rejectedItemKeys: [String]
    /// 本次请求的全部 key（用于判断是否为子集）。
    public let requestedItemKeys: [String]

    public var isEmpty: Bool { approvedItems.isEmpty }

    /// 是否为「严格子集」（已批准 < 请求总数，触发子集召回）。
    public var isSubset: Bool {
        !approvedItems.isEmpty && approvedItems.count < requestedItemKeys.count
    }
}

/// 审批门结果（allow / deny-子集召回 / deny-原因）。纯枚举，无 SDK 依赖。
public enum ApprovalGateOutcome: Sendable, Equatable {
    /// 放行（全部批准且通过 policy / typed 校验）。
    case allow
    /// 子集授权召回：Agent 需以该子集重新调用 execute 工具。
    case denySubset(ApprovedExecutionSet)
    /// 拒绝（附原因 code：user_cancelled / typed_confirmation_failed / approval_required / policy_violation）。
    case deny(String)
}

/// 纯决策函数集合（AC #4）。所有函数无 I/O、无副作用、可单测。
public enum StorageApprovalDecision {

    /// 按 `approvedItemKeys` 过滤请求项，并经 policy 二次裁剪，得到可执行集。
    public static func applyDecision(
        request: StorageApprovalRequest,
        response: StorageApprovalResponse,
        policy: SurfacePolicy
    ) -> ApprovedExecutionSet {
        let requestedKeys = request.items.map { $0.key }
        let approvedKeySet = Set(response.approvedItemKeys)
        var approvedItems: [StorageApprovalItem] = []
        var rejected = Array(response.rejectedItemKeys)
        for item in request.items {
            if approvedKeySet.contains(item.key) {
                if policy.isRemotelyApprovable(item: item) {
                    approvedItems.append(item)
                } else if !rejected.contains(item.key) {
                    rejected.append(item.key)
                }
            }
        }
        return ApprovedExecutionSet(
            approvedItems: approvedItems,
            rejectedItemKeys: rejected,
            requestedItemKeys: requestedKeys
        )
    }

    /// 远程 surface 上把禁止项从 `approvedItemKeys` 移除并加入 `rejectedItemKeys`。
    ///
    /// 注：AC 字面签名为 `enforcePolicy(response:policy:)`；此处追加 `items:` 形参，
    /// 因为按 dataRisk / requiresExplicitApproval 裁剪必须能查到每个 key 对应的项
    /// （response 仅含 key）。调用方（`resolveOutcome`）恒有 `request.items`。
    public static func enforcePolicy(
        response: StorageApprovalResponse,
        policy: SurfacePolicy,
        items: [StorageApprovalItem]
    ) -> StorageApprovalResponse {
        // 本地入口无需裁剪。
        guard policy.surface == .telegram else { return response }
        let itemByKey = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0) })
        var approved: [String] = []
        var rejected = Array(response.rejectedItemKeys)
        for key in response.approvedItemKeys {
            let item = itemByKey[key]
            if let item = item, policy.isRemotelyApprovable(item: item) {
                approved.append(key)
            } else {
                if !rejected.contains(key) { rejected.append(key) }
            }
        }
        return StorageApprovalResponse(
            operationId: response.operationId,
            surface: response.surface,
            action: response.action,
            approvedItemKeys: approved,
            rejectedItemKeys: rejected,
            typedConfirmationPayload: response.typedConfirmationPayload,
            remoteReserved: response.remoteReserved,
            collectedAt: response.collectedAt
        )
    }

    /// typed 确认校验：忽略大小写与首尾空白，接受 `candidates` 任一非空匹配。
    public static func validateTypedConfirmation(payload: String, expected candidates: [String]) -> Bool {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        return candidates.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed
        }
    }

    /// 按 `approvedItemKeys` 过滤出 `StorageApprovalItem` 子集（不应用 policy，原始 key 级）。
    public static func deriveApprovedSubset(
        response: StorageApprovalResponse,
        request: StorageApprovalRequest
    ) -> [StorageApprovalItem] {
        let approvedKeySet = Set(response.approvedItemKeys)
        return request.items.filter { approvedKeySet.contains($0.key) }
    }

    /// 综合决策 → 审批门结果（run/chat 共享；gate 主入口）。
    public static func resolveOutcome(
        request: StorageApprovalRequest,
        response: StorageApprovalResponse,
        policy: SurfacePolicy
    ) -> ApprovalGateOutcome {
        switch response.action {
        case .cancel, .rejectItem:
            // 用户明确取消/否决 → 安全默认 deny。
            return .deny("user_cancelled")
        case .approvePlan, .approveItem:
            // typed 确认优先校验（整个操作级）。
            if request.requiresTypedConfirmation {
                let ok = validateTypedConfirmation(
                    payload: response.typedConfirmationPayload ?? "",
                    expected: request.typedConfirmationCandidates ?? []
                )
                if !ok { return .deny("typed_confirmation_failed") }
            }
            let enforced = enforcePolicy(response: response, policy: policy, items: request.items)
            let set = applyDecision(request: request, response: enforced, policy: policy)
            if set.isEmpty {
                return .deny("policy_violation")
            }
            if set.isSubset {
                return .denySubset(set)
            }
            return .allow
        }
    }

    /// 子集召回的 deny 文本（结构化 JSON，含 `approved_subset`，引导 Agent 以子集重调）。
    public static func renderSubsetRecall(_ set: ApprovedExecutionSet) -> String {
        let payload = SubsetRecallPayload(
            approvedSubset: set.approvedItems.map {
                SubsetRecallPayload.Entry(action: $0.action.rawValue, source: $0.sourcePath, key: $0.key)
            },
            rejectedItemKeys: set.rejectedItemKeys,
            note: "User approved a subset. Re-invoke the storage execute tool with ONLY the approved_subset items; do not include unapproved items."
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload), let s = String(data: data, encoding: .utf8) else {
            return #"{"type":"approved_subset","note":"Re-invoke with the approved subset only."}"#
        }
        return s
    }

    // MARK: - Subset recall payload (Codable, stable key order)

    private struct SubsetRecallPayload: Codable {
        struct Entry: Codable {
            let action: String
            let source: String
            let key: String
        }
        let type: String = "approved_subset"
        let approvedSubset: [Entry]
        let rejectedItemKeys: [String]
        let note: String

        enum CodingKeys: String, CodingKey {
            case type
            case approvedSubset = "approved_subset"
            case rejectedItemKeys = "rejected_item_keys"
            case note
        }
    }
}
