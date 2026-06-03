---
project_name: 'axion'
user_name: 'Nick'
date: '2026-06-03'
status: 'draft'
epic: 33
title: 'TG 基础体验补强 — 通知、批处理、状态反馈'
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-tg-enhancement-hermes-parity/prd.md
  - docs/epics/epic-32-telegram-experience-upgrades.md
---

# Epic 33: TG 基础体验补强 — 通知、批处理、状态反馈

Axion TG 当前最大的体验痛点有三个：通知刷屏（每条 streaming edit 都弹通知）、消息碎片化（快速连发多条消息触发多个 agent run）、缺乏处理状态反馈（用户不知道消息是否在被处理）。本 Epic 以最小改动解决这三个问题，让 TG 从"能用"变"好用"。

**FRs covered:** FR-TG-1 (通知静默), FR-TG-2 (消息批处理), FR-TG-3 (Follow-up Grace), FR-TG-4 (Reaction 状态反馈), FR-TG-5 (溢出续接)
**NFRs:** NFR-TG-1, NFR-TG-2, NFR-TG-3
**依赖:** Epic 32（使用 TGStreamingController、TGMessageFormatter、TGAPIClient 基础设施）

---

## Story 依赖关系

```
33.1 (通知静默) ── 独立
33.2 (消息批处理) ── 独立（需注意与 34.6 clarify-awaiting-text 的路由优先级）
33.3 (Follow-up Grace) ──→ 依赖 33.2（共用批处理基础设施）
33.4 (Reaction 状态反馈) ── 独立
33.5 (Edit Overflow Split) ── 独立
```

建议实施顺序：33.1 → 33.4 → 33.5 → 33.2 → 33.3
**注意：** 33.2 与 Epic 34 Story 34.6 存在消息路由交互——`TelegramAdapter.pollLoop()` 的路由优先级为：命令 → clarify 截获 → TGTextBatcher → 直接提交。两者可并行开发但需对齐路由顺序。

---

### Story 33.1: 通知静默模式

As a Axion Telegram 用户,
I want streaming/edit/status 消息不弹通知，仅最终回复和需要用户操作的审批弹通知,
So that 我的手机不被 agent 中间步骤的推送刷屏。

**Acceptance Criteria:**

**Given** TG streaming 正在进行中
**When** `TGStreamingController` 发送或编辑 preview 消息
**Then** 所有 edit 和中间状态消息使用 `disable_notification=true`
**And** 用户手机不会因 streaming edit 弹出任何推送

**Given** 任务执行完成
**When** `TGStreamingController` 发送最终结果消息（finalize）
**Then** 最终消息使用 `disable_notification=false`（默认）
**And** 用户手机弹出推送通知，包含最终结果预览

**Given** agent 触发审批/确认/clarify 等需要用户操作的交互
**When** `TGInteractiveSessionStore` 发送 inline keyboard 消息
**Then** 交互消息使用 `disable_notification=false`
**And** 用户收到推送通知，知道需要操作

**Given** 错误消息需要发送
**When** `TGEventHandler` 发送错误摘要
**Then** 错误消息使用 `disable_notification=false`
**And** 用户收到推送通知，知道任务失败

**Given** review/curator 结果消息
**When** 后台审查完成推送摘要
**Then** review 消息使用 `disable_notification=true`（非紧急）

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift` | `sendMessage` / `editMessageText` 增加 `disableNotification: Bool = false` 参数 |
| `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` | 新增 `notificationPolicy(for context:) -> Bool` 方法，根据消息类型返回是否静默；streaming edit 和中间状态调用时传入 `true` |
| `Sources/AxionCLI/Services/Telegram/TGStreamingController.swift` | `editMessage` 和中间发送调用时传入 `disableNotification: true`；finalize 时传入 `false` |

---

### Story 33.2: 消息批处理（Text Batching）

As a Axion Telegram 用户,
I want 短时间内连续发送的多条文本消息被自动合并为一条 agent 输入,
So that 快速补充说明时不会触发多个 agent run，浪费资源和时间。

**Acceptance Criteria:**

**Given** 用户在 300ms 内连续发送两条文本消息
**When** `TGTextBatcher` 检测到同一 chatId 的第二条消息到达
**Then** 两条消息被合并为一条，以换行分隔
**And** 只触发一次 agent run，输入为合并后的文本

**Given** 用户连续发送多条消息，间隔均在 200-300ms 内
**When** batcher 的聚合窗口尚未关闭
**Then** 所有消息继续累积，直到间隔超过阈值
**And** 最终合并为一条输入提交

**Given** 单条消息长度超过 500 字符
**When** batcher 评估合并策略
**Then** 使用更长的聚合延迟（300ms vs 短消息的 200ms）
**And** 长消息有更多时间被后续消息补充

**Given** 用户发送的是命令（以 `/` 开头）
**When** `TelegramAdapter.pollLoop()` 收到该消息
**Then** 命令不进入批处理，直接路由到 `TGCommandRouter`
**And** 不影响同一 chat 中其他文本消息的批处理

**Given** 批处理中有待发送消息时用户发送了新消息
**When** 聚合窗口已关闭但合并消息尚未提交
**Then** 已合并消息立即提交给 agent
**And** 新消息开始新的批处理窗口

**Given** 批处理等待期间 agent 正在执行任务
**When** 合并后的消息准备好提交
**Then** 消息进入 `TaskSerialQueue` 排队
**And** 不中断正在执行的任务

**Given** chat 处于 `clarify-awaiting-text` 模式（Epic 34 Story 34.6）
**When** `TelegramAdapter.pollLoop()` 收到文本消息
**Then** **消息不进入 `TGTextBatcher`**，由 clarify 机制优先截获
**And** batcher 不感知该消息的存在

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Services/Telegram/TGTextBatcher.swift` | NEW — actor，按 chatId 分组，自适应延迟聚合；提供 `feed(chatId:text:isCommand:)` 和 `onBatchReady` 闭包回调 |
| `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` | `pollLoop()` 文本消息路由优先级：命令 → clarify 截获（已有 `textCapture` 检查，第 98 行）→ `TGTextBatcher` → 直接提交；确保 clarify 模式下消息不经过 batcher |

**TGTextBatcher 核心接口：**

```swift
actor TGTextBatcher {
    /// 注入一条文本，返回是否被批处理拦截
    func feed(chatId: Int64, text: String, isCommand: Bool) async -> Bool

    /// 批处理就绪回调
    var onBatchReady: (@Sendable (Int64, String) async -> Void)?

    /// 强制 flush 指定 chat 的待处理消息
    func flush(chatId: Int64) async

    /// 强制 flush 所有待处理消息（graceful shutdown 时调用）
    func flushAll() async
}
```

---

### ~~Story 33.3: Follow-up Grace Window~~ — 已由 TaskSerialQueue 实现

`TaskSerialQueue.enqueue()` 已实现完整的 FIFO 排队机制：任务执行中时新消息自动排队并回复 `"任务已排队 (队列: N)"`。无需额外开发。

---

### Story 33.4: Reaction 状态反馈

As a Axion Telegram 用户,
I want 发送消息后看到处理进度 reaction（👀→✅/👎）,
So that 我知道消息已被接收并正在处理，无需猜测状态。

**Acceptance Criteria:**

**Given** 用户发送文本消息且被接受为任务
**When** agent 开始处理
**Then** 给用户原始消息添加 👀 reaction
**And** 用户在聊天列表中看到消息有 reaction 标记

**Given** 任务执行完成（成功）
**When** 最终结果已发送
**Then** 将 👀 reaction 替换为 ✅ reaction
**And** 用户一眼知道任务已完成

**Given** 任务执行失败
**When** 错误消息已发送
**Then** 将 👀 reaction 替换为 👎 reaction
**And** 用户一眼知道任务失败

**Given** 任务被用户取消（`/stop`）
**When** 取消操作完成
**Then** 清除 👀 reaction（不替换为任何 reaction）

**Given** TG bot 无权限设置 reaction（如群聊中未启用）
**When** `setMessageReaction` API 返回错误
**Then** 捕获错误，打印 warning 日志
**And** 不阻塞主流程，任务正常执行

**Given** 消息太旧（TG 限制 reaction 时间窗口）
**When** 设置 reaction 失败
**Then** 同样 catch + warning，不影响任务

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift` | 新增 `setMessageReaction(chatId:messageId:emoji:)` 和 `deleteMessageReaction(chatId:messageId:)` 方法 |
| `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` | 新增 `setReaction(chatId:messageId:emoji:)` 便捷方法，catch 所有错误不外泄 |
| `Sources/AxionCLI/Services/Telegram/TGReactionManager.swift` | NEW — 管理 reaction 生命周期：`onTaskStart(chatId:messageId:)` 设置 👀，`onTaskComplete(chatId:messageId:success:)` 替换为 ✅/👎 |
| `Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift` | 在 `AgentCompletedEvent` 和 `AgentFailedEvent` 处理中调用 `TGReactionManager` |

---

### Story 33.5: Edit Overflow Split

As a Axion Telegram 用户,
I want 超长的 agent 回复自动续接而不丢失内容,
So that 我能看到完整的回复，不会被截断。

**Acceptance Criteria:**

**Given** streaming finalize 时格式化后的文本超过 TG 4096 字符限制
**When** `TGStreamingController` 准备发送最终消息
**Then** 第一块内容编辑到已有的 preview 气泡
**And** 溢出部分作为 reply-to 第一条消息的新消息发送
**And** 所有切块保持 MarkdownV2 格式完整性（不跨块截断格式标记）

**Given** 非 streaming 场景下最终结果超过 4096 字符
**When** `TelegramAdapter.sendFormatted()` 发送消息
**Then** 复用 `TGMessageFormatter.split()` 切块
**And** 切块按段落/换行优先分割，不从单词中间截断

**Given** 编辑操作本身触发了 overflow（编辑后内容超长）
**When** `editMessageText` 返回 `message is too long` 错误
**Then** 拆分为：编辑前 N 字符 + 新消息发送剩余内容
**And** 新消息作为 reply-to 原消息发送

**Given** 多次 overflow split 后总消息数量
**When** 连续切块发送
**Then** 保持消息顺序稳定
**And** 每条切块都能独立渲染（不依赖前一条的未闭合标记）

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Services/Telegram/TGStreamingController.swift` | 增强 finalize 逻辑：检测渲染后长度，超长时自动拆分；第一块 edit，后续块 sendMessage(replyTo:) |
| `Sources/AxionCLI/Services/Telegram/TGMessageFormatter.swift` | 确保 `split()` 生成的每块都是格式自包含的 |
| `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` | `sendFormatted()` 支持 reply-to 续接发送 |
