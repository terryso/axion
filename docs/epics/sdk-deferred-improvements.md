# SDK 延后改进建议

> **状态：延后**
> **来源：Axion Epic 24-27 review（2026-05-27）**
> **前提：Axion 当前不阻塞 SDK 改进，可后续推动**

---

## 1. SessionData.messages 类型化转换

**问题**：`SessionStore.load()` 返回 `SessionData`，其中 `messages: [[String: Any]]`（JSON 原始字典）。消费者（如 ReviewHandler）需要 `[SDKMessage]`，但没有官方转换方法。

**建议**：在 SDK 中添加便捷方法：

```swift
extension SessionData {
    /// 将原始消息字典转换为类型化的 SDKMessage 数组。
    public var typedMessages: [SDKMessage] {
        messages.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? JSONDecoder().decode(SDKMessage.self, from: data)
        }
    }
}
```

**影响**：Axion 当前在 `MessageConverter` 中自行实现此转换。SDK 提供后可移除 Axion 侧代码。

**优先级**：低

---

## 2. SessionMetadata 添加 status 字段

**问题**：SDK 的 `SessionMetadata` 没有 `status` 字段（CREATED / RUNNING / COMPLETED / FAILED / INTERRUPTED）。Axion 需要自行维护 `axion-state.json` 来追踪 session 状态。

**建议**：在 `SessionMetadata` 或 `SessionData` 中添加可选的 `status` 字段：

```swift
public enum SessionStatus: String, Codable, Sendable {
    case created, running, completed, failed, interrupted
}

// 在 SessionMetadata 中添加
public let status: SessionStatus?
```

**影响**：Axion 可以移除 `axion-state.json`，直接使用 SDK 的 status 字段。但 session lifecycle 管理（CREATED → RUNNING → COMPLETED 状态转换）仍然是应用层职责，SDK 只需持久化最终状态。

**优先级**：中

---

## 3. AgentEvent tool input 完整性

**问题**：`ToolStartedEvent.input: String?` 可能因敏感或大体积而返回 nil。TraceEventHandler 需要完整的 tool input 用于调试追踪。

**当前影响**：Axion 的 TraceEventHandler 只记录 toolName，不记录 input。对调试影响有限。

**优先级**：低
