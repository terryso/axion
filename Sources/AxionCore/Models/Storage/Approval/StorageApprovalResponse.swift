import Foundation

/// 审批响应（surface 无关）。字段见 AC #1。
///
/// 不变式：`action == .cancel` ⇒ `approvedItemKeys` 恒为空（安全默认）。
/// 在 init 与 decode 两处强制，保证任何来源的响应都不会在取消时漏过批准项。
public struct StorageApprovalResponse: Codable, Equatable, Sendable {

    /// 操作 ID。
    public var operationId: String
    /// 入口。
    public var surface: StorageSurface
    /// 动作。
    public var action: StorageApprovalAction
    /// 已批准项 key（子集或全集）。
    public var approvedItemKeys: [String]
    /// 被拒/被剔除项 key。
    public var rejectedItemKeys: [String]
    /// typed 确认载荷（用户键入串）。
    public var typedConfirmationPayload: String?
    /// 远程预留（telegram）。
    public var remoteReserved: RemoteApprovalReserved?
    /// 采集时间（ISO8601 字符串）。
    public var collectedAt: String

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case surface
        case action
        case approvedItemKeys = "approved_item_keys"
        case rejectedItemKeys = "rejected_item_keys"
        case typedConfirmationPayload = "typed_confirmation_payload"
        case remoteReserved = "remote_reserved"
        case collectedAt = "collected_at"
    }

    public init(
        operationId: String,
        surface: StorageSurface,
        action: StorageApprovalAction,
        approvedItemKeys: [String],
        rejectedItemKeys: [String] = [],
        typedConfirmationPayload: String? = nil,
        remoteReserved: RemoteApprovalReserved? = nil,
        collectedAt: String
    ) {
        self.operationId = operationId
        self.surface = surface
        self.action = action
        // 取消时强制清空已批准项（安全默认）。
        self.approvedItemKeys = (action == .cancel) ? [] : approvedItemKeys
        self.rejectedItemKeys = rejectedItemKeys
        self.typedConfirmationPayload = typedConfirmationPayload
        self.remoteReserved = remoteReserved
        self.collectedAt = collectedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        operationId = try c.decodeIfPresent(String.self, forKey: .operationId) ?? ""
        surface = try c.decodeIfPresent(StorageSurface.self, forKey: .surface) ?? .run
        action = try c.decodeIfPresent(StorageApprovalAction.self, forKey: .action) ?? .cancel
        let rawApproved = try c.decodeIfPresent([String].self, forKey: .approvedItemKeys) ?? []
        rejectedItemKeys = try c.decodeIfPresent([String].self, forKey: .rejectedItemKeys) ?? []
        typedConfirmationPayload = try c.decodeIfPresent(String.self, forKey: .typedConfirmationPayload)
        remoteReserved = try c.decodeIfPresent(RemoteApprovalReserved.self, forKey: .remoteReserved)
        collectedAt = try c.decodeIfPresent(String.self, forKey: .collectedAt) ?? ""
        // 解码后同样强制不变式。
        approvedItemKeys = (action == .cancel) ? [] : rawApproved
    }

    /// 便捷工厂：取消（任何 surface 的安全默认）。
    public static func cancel(operationId: String, surface: StorageSurface, collectedAt: String) -> StorageApprovalResponse {
        StorageApprovalResponse(
            operationId: operationId,
            surface: surface,
            action: .cancel,
            approvedItemKeys: [],
            rejectedItemKeys: [],
            collectedAt: collectedAt
        )
    }
}
