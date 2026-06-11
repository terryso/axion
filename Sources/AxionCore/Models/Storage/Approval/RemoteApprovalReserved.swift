import Foundation

/// 远程 inline-button 描述（仅描述，不发送）。telegram 入口预留字段（AC #9）。
///
/// 本 Story 不发送 telegram 消息、不创建 inline keyboard；仅保留结构以便后续 Story 接入。
public struct RemoteApprovalButton: Codable, Equatable, Sendable {
    /// 按钮文案。
    public var label: String
    /// 回调标识（后续映射为 telegram callback_data）。
    public var callbackData: String

    enum CodingKeys: String, CodingKey {
        case label
        case callbackData = "callback_data"
    }

    public init(label: String, callbackData: String) {
        self.label = label
        self.callbackData = callbackData
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        callbackData = try c.decodeIfPresent(String.self, forKey: .callbackData) ?? ""
    }
}

/// 远程审批预留（AC #9）。全部可选；本 Story 仅声明结构、保守策略下恒不发送。
public struct RemoteApprovalReserved: Codable, Equatable, Sendable {
    /// 待编辑/回复的消息 ID（telegram 上发送 pending 消息后回填）。
    public var pendingMessageId: Int64?
    /// 预留的 inline 按钮（按可批准项生成，保守策略下为空数组或 nil）。
    public var inlineButtonsReserved: [RemoteApprovalButton]?
    /// 过期时间（ISO8601 字符串）。
    public var expiresAt: String?
    /// 详情分页游标（指向压缩摘要的下一页）。
    public var detailCursor: String?

    enum CodingKeys: String, CodingKey {
        case pendingMessageId = "pending_message_id"
        case inlineButtonsReserved = "inline_buttons_reserved"
        case expiresAt = "expires_at"
        case detailCursor = "detail_cursor"
    }

    public init(
        pendingMessageId: Int64? = nil,
        inlineButtonsReserved: [RemoteApprovalButton]? = nil,
        expiresAt: String? = nil,
        detailCursor: String? = nil
    ) {
        self.pendingMessageId = pendingMessageId
        self.inlineButtonsReserved = inlineButtonsReserved
        self.expiresAt = expiresAt
        self.detailCursor = detailCursor
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pendingMessageId = try c.decodeIfPresent(Int64.self, forKey: .pendingMessageId)
        inlineButtonsReserved = try c.decodeIfPresent([RemoteApprovalButton].self, forKey: .inlineButtonsReserved)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        detailCursor = try c.decodeIfPresent(String.self, forKey: .detailCursor)
    }
}
