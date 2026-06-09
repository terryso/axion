import OpenAgentSDK

extension ReviewScheduler {

    /// Convert transcript `[[String: Any]]` dicts (from SessionStore) to `[SDKMessage]`.
    static func convertTranscriptMessages(_ rawMessages: [[String: Any]]) -> [SDKMessage] {
        rawMessages.compactMap { dict -> SDKMessage? in
            let role = dict["type"] as? String ?? dict["role"] as? String ?? ""
            switch role {
            case "user":
                let content = dict["message"] as? String ?? dict["content"] as? String ?? ""
                guard !content.isEmpty else { return nil }
                return .userMessage(SDKMessage.UserMessageData(
                    uuid: dict["uuid"] as? String,
                    sessionId: dict["session_id"] as? String ?? dict["sessionId"] as? String,
                    message: content,
                    parentToolUseId: dict["parent_tool_use_id"] as? String ?? dict["parentToolUseId"] as? String
                ))
            case "assistant":
                let text = dict["message"] as? String ?? dict["content"] as? String ?? ""
                guard !text.isEmpty else { return nil }
                return .assistant(SDKMessage.AssistantData(
                    text: text,
                    model: dict["model"] as? String ?? "unknown",
                    stopReason: dict["stop_reason"] as? String ?? "end_turn",
                    uuid: dict["uuid"] as? String,
                    sessionId: dict["session_id"] as? String ?? dict["sessionId"] as? String
                ))
            default:
                return nil
            }
        }
    }
}
