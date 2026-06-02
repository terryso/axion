---
project_name: 'axion'
user_name: 'Nick'
date: '2026-05-31'
status: 'draft'
epic: 32
title: 'Telegram 能力补强与交互体验升级'
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/architecture.md
  - _bmad-output/planning-artifacts/prds/prd-axion-gateway-2026-05-29/prd.md
  - docs/epics/epic-29-telegram-remote.md
---

# Epic 32: Telegram 能力补强与交互体验升级

Axion 已经具备 Telegram MVP：长轮询、白名单、文本/图片输入、任务排队、最终结果回推。但当前体验仍停留在"能用"，还远没到"像一个真正的远程助手"。现在的实现本质上是纯文本 bot：`TelegramAdapter` 只会 `sendMessage`，`TGCommandRouter` 只支持 `/status`、`/skills`、`/new`，`TGEventHandler` 只能按 5 秒节流发送普通文本步骤消息，没有消息编辑、没有富文本渲染、没有 inline keyboard、没有 streaming。

本 Epic 的目标不是重写整个 gateway，而是在现有 Epic 29 基础上，补齐 Telegram 侧最影响体验的三条主线：

1. **消息样式升级**：让 agent 最终回复、状态消息、错误消息、审批/澄清消息在 Telegram 中可读、稳定、可交互。
2. **命令能力升级**：从硬编码三条命令提升到可扩展的 Telegram 命令注册表和 bot 菜单。
3. **streaming 升级**：支持 edit-based streaming，并为私聊预留 native draft preview / typing UX。

**FRs covered:** FR-2.2, FR-2.4, FR-2.5, FR-2.7, FR-2.8, FR-5.1, FR-5.3, FR-5.4
**NFRs:** NFR-2, NFR-4, NFR-6, NFR-13, NFR-15, NFR-19
**依赖:** Epic 28, Epic 29

---

## 当前实现基线

| 区域 | 当前状态 | 主要缺口 |
|------|----------|----------|
| `TGAPIClient.swift` | 只支持 `getUpdates` / `sendMessage` / `getFile` / `downloadFile` | 无 `editMessageText`、`answerCallbackQuery`、`setMyCommands`、typing/draft 等 API |
| `TelegramAdapter.swift` | 纯文本发送，4096 字拆分，图片下载后转本地附件路径 | 无 parse mode、无消息编辑、无回复元数据、无 callback handling、无富文本 fallback |
| `TGCommandRouter.swift` | 只支持 `/status`、`/skills`、`/new` | 无统一命令元数据、无 `/help`、`/commands`、`/queue`、无 Telegram 菜单同步 |
| `TGEventHandler.swift` | 工具完成时按 5 秒节流推送文本；任务结束时推最终文本 | 无流式编辑、无状态气泡复用、无富文本结果整理、无交互式确认 |

---

## 进入 Detailed Design 前锁定的 4 个决策

为避免详细设计阶段返工，本 Epic 先锁定以下架构边界：

1. **交互阻塞机制统一采用 SDK `pause/resume`**：审批、确认、clarify 都以 `Agent.pause(reason:)` / `resume(context:)` 为底座，不在 Telegram 侧自造第二套 `CheckedContinuation` 生命周期。
2. **`AskUserTool` 不作为本 Epic 的默认前提**：当前 Axion 构建路径排除了 `AskUser`。Epic 32 的 v1 交互能力不要求重新启用 `AskUserTool`；如后续要恢复，需单独技术设计评估全局 question handler 的并发模型。
3. **`TGCommandRegistry` 是 Telegram 专用展示/路由真相源**：它负责 TG 命令元数据、帮助文案和 `setMyCommands` 菜单，不试图在本 Epic 内抽象成跨平台统一命令系统。
4. **Draft Preview 必须先过技术预研门禁**：Typing Indicator 属于可交付范围；Draft Preview 只有在 Telegram Bot API/客户端兼容性被 spike 证实后，才进入实现故事。

**结论**：Epic 32 现在允许进入 detailed design，但详细设计必须严格遵守上述 4 个决策，不再重新讨论底层模型。

---

## 流式事件架构

当前 `TGEventHandler` 只订阅离散事件（`ToolStartedEvent`、`ToolCompletedEvent`、`AgentCompletedEvent` 等）。**SDK 已提供流式事件**，但 Epic 29 的实现没有启用：

| SDK 事件 | 作用 | 启用条件 |
|----------|------|---------|
| `LLMTokenStreamEvent` | LLM 每个输出 token chunk（高频） | `AgentOptions.emitTokenStream = true` |
| `ToolStreamingEvent` | 工具输出流 chunk | SDK 默认发射 |

**关键设计决策**：TG streaming 不需要创建新事件类型。只需：

1. `AgentBuilder.BuildConfig` 新增 `emitTokenStream: Bool` 字段；`TaskSerialQueue` 在构建 TG 任务的 `BuildConfig` 时传入 `true`；`AgentBuilder.build()` 读取该字段并设置 `agentOptions.emitTokenStream = true`
2. `TGStreamingController` 订阅 `LLMTokenStreamEvent` + `ToolStartedEvent` + `ToolStreamingEvent` + `ToolCompletedEvent` + `AgentCompletedEvent`
3. `TGEventHandler` 保留对 `AgentFailedEvent`、`ReviewResultEvent` 的订阅，但**不再发送旧式步骤消息**；`ReviewResultEvent` 处理逻辑保持不变，不因 streaming 重构误删
4. 所有 preview / token / tool chunk / finalize edit 都由 `TGStreamingController` 独占，避免双发

**事件消费分层**：

```
LLMTokenStreamEvent ──→ TGStreamingController（缓冲、节流、编辑气泡）
ToolStartedEvent     ──→ TGStreamingController（记录 toolUseId → toolName 映射，用于 segment 切换和 finalize 标记）
ToolStreamingEvent   ──→ TGStreamingController（工具输出分段）
ToolCompletedEvent   ──→ TGStreamingController（finalize 当前工具段，显示 "✓ Bash (1.2s)"）
AgentCompletedEvent  ──→ TGStreamingController（finalize 最终消息）
AgentFailedEvent     ──→ TGEventHandler（错误推送；必要时通知 controller 结束 preview）
ReviewResultEvent    ──→ TGEventHandler（审查摘要，保持不变，不走 token streaming）
```

**实现约束：**

- `TGEventHandler.subscribedEventTypes` 扩展后，旧的”工具完成即发一条文本消息”逻辑必须删除，而不是和 streaming 并存。
- `TGStreamingController` 只负责**同一任务的可编辑消息生命周期**；错误、审查总结、系统告警仍由 handler 发送独立消息。
- `TaskSerialQueue` 必须保证同一 chat 同时只有一个活跃 streaming controller，避免两个任务争抢同一状态消息。

**emitTokenStream 注入路径：**

当前 `BuildConfig` 不携带 streaming 开关，`AgentBuilder.build()` 也未设置 `emitTokenStream`。需要以下变更：

1. `AgentBuilder.BuildConfig` 新增字段 `emitTokenStream: Bool = false`
2. `TaskSerialQueue.executeNewWithTimeout()` / `executeWithTimeout()` 调用 `BuildConfig.forAPI()` 后，将 `emitTokenStream` 设为 `true`（或新增 `BuildConfig.forTelegram()` 工厂方法）
3. `AgentBuilder.build()` 在构建 `agentOptions` 后、创建 agent 前，读取 `buildConfig.emitTokenStream` 并赋值 `agentOptions.emitTokenStream = true`
4. 非 TG 任务（CLI、HTTP API、MCP）不受影响，保持默认 `false`

变更涉及文件：`AgentBuilder.swift`（BuildConfig + build 方法）、`TaskSerialQueue.swift`（构建 config 时传入）。

---

## Hermes 对齐矩阵

| Hermes Telegram 能力 | Axion 当前状态 | Epic 32 对齐方式 |
|---------------------|---------------|------------------|
| Telegram 专用 markdown/HTML 渲染 | 仅纯文本 | Story 32.1 |
| 长消息/长编辑安全切块 | 仅最终文本切块 | Story 32.1 |
| 进度消息复用同一气泡编辑 | 无 | Story 32.2 |
| edit-based streaming | 无 | Story 32.2 |
| 私聊 draft preview / typing UX | 无 | Story 32.3 |
| 命令注册表 + bot menu | 仅 3 个硬编码命令 | Story 32.4 |
| inline keyboard 审批 / clarify | 无 | Story 32.5 |

---

## Story 依赖关系

```
32.1 (富文本) ──→ 32.2 (Streaming) ──→ 32.3 (Draft/Typing, stretch)
                  32.4 (命令注册表, 独立)
32.1 (富文本) ──→ 32.5 (交互式审批, 依赖 parse mode + callback 模型)
```

建议实施顺序：32.1 → 32.2 → 32.4 → 32.5 → 32.3

---

### Story 32.1: Telegram 富文本渲染与可靠发送管道

As a Axion Telegram 用户,
I want agent 的最终回复、错误和状态消息在 TG 中保持清晰可读,
So that 我在手机上看到的是可消费的信息，而不是一大段生硬纯文本。

**Acceptance Criteria:**

**Given** agent 最终结果包含标题、列表、代码块、inline code、链接和表格
**When** TelegramAdapter 发送最终结果
**Then** 结果先经过 Telegram 专用格式化
**And** 标题、列表、代码块、inline code、链接在 Telegram 中保持可读
**And** 表格在不支持原样渲染时降级为可读的 key/value 列表，而不是乱码或挤成一行

**Given** Telegram parse mode 发送失败（例如 MarkdownV2 转义错误）
**When** Adapter 捕获发送失败
**Then** 按 MarkdownV2 → HTML → PlainText 三级降级重试
**And** HTML 降级能保留大部分格式（粗体、链接、代码块）
**And** 纯文本降级仍能收到完整结果
**And** 不因单次格式错误导致消息丢失

**Given** 最终结果或错误消息超过 Telegram 4096 字限制
**When** Adapter 发送消息
**Then** 按段落或换行优先切块
**And** 切块基于**渲染后长度**计算（MarkdownV2 转义字符会膨胀原文，实际可承载内容少于 4096）
**And** 保持消息顺序稳定
**And** continuation message 不丢失格式上下文

**Given** provider/raw error 中包含底层堆栈、token、路径或其他不适合直接展示给用户的信息
**When** TelegramAdapter 发送错误消息
**Then** 对外展示用户友好的错误摘要
**And** 不泄露敏感信息

**Given** 回复发生在群聊或用户以 reply 方式触发任务
**When** TelegramAdapter 发送首条结果消息
**Then** 首条消息保留 `reply_to_message_id`
**And** 后续 continuation chunk 不强制 reply 原消息，避免刷出过长线程

**渲染 Contract：**

- 标题：统一降级为 `**Title**` / `<b>Title</b>` / `TITLE`
- 列表：保留有序/无序层级；最多保留两级缩进，避免手机端过宽
- 代码块：优先 fenced code；HTML fallback 使用 `<pre><code>`；PlainText fallback 保留缩进和语言标签首行
- Inline code：优先反引号；HTML fallback 使用 `<code>`
- 链接：优先 Telegram parse mode 支持的可点击链接；PlainText fallback 输出 `label: url`
- 表格：统一降级为”每行一条记录”的 key/value block，不尝试在 TG 中保真表格布局
- 错误消息：禁止原样透传 provider payload；必须经过 `sanitizeForTelegramError()` 摘要化
- 切块：按**渲染后长度**与段落边界切分，保证每块都能独立渲染，不依赖前一块未闭合标记

**`sanitizeForTelegramError()` 规格：**

将原始错误转为用户友好的 Telegram 摘要。过滤规则：

1. **API keys / tokens**：正则匹配 `sk-[a-zA-Z0-9]+`、`Bearer .+`、API key URL 参数 → 替换为 `[REDACTED]`
2. **文件系统路径**：绝对路径如 `/Users/xxx/...` → 只保留最后一层文件名
3. **Stack traces**：截取第一行错误描述，丢弃 `at function:line` 调用栈
4. **HTTP 响应体**：原始 JSON payload → 只保留顶层 `error.message` 或 `description` 字段
5. **输出示例**：
   - 原始：`Error: Anthropic API error 401: {“error”:{“message”:”invalid x-api-key: sk-ant-abc123...”,”type”:”authentication_error”}}` → 摘要：`认证失败，请检查 API Key 配置`
   - 原始：`Failed to execute tool Bash: command timed out after 300s. Stderr: ...` → 摘要：`命令执行超时 (300s)`

**TGAPIError 四分类重构（Story 32.1 前置，所有后续 Story 依赖）：**

当前 `TGAPIError` 只有 `.apiError(String)` 一个 case。在引入 parse mode 降级和 streaming 限流前，必须重构为：

```swift
enum TGAPIError: Error, LocalizedError {
    case retryableNetwork(original: Error)          // 网络超时、连接重置 → 自动重试
    case rateLimited(retryAfter: TimeInterval?)     // 429 → 读 Retry-After，延迟重试
    case formatRejected(parseMode: TGParseMode)     // 400 + parse error → 降级到下一级 parse mode
    case permanentTelegramError(code: Int, message: String)  // 消息已删除、chat 不存在等 → 放弃

    var errorDescription: String? {
        switch self {
        case .retryableNetwork(let err): return “网络错误: \(err.localizedDescription)”
        case .rateLimited(let after): return “请求限流” + (after.map { “，\($0)秒后重试” } ?? “”)
        case .formatRejected(let mode): return “格式被拒绝: \(mode.rawValue)”
        case .permanentTelegramError(_, let msg): return “Telegram 错误: \(msg)”
        }
    }
}
```

`TGAPIClient.performRequest()` 需根据 HTTP 状态码和响应体分类抛出对应 case，而非统一 `.apiError`。

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift` | 重构 `TGAPIError` 为四分类；`performRequest()` 按 HTTP 状态码分类抛出；扩展 `sendMessage` 支持 parse mode / reply metadata；新增 `editMessageText` |
| `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` | 增加 `sendFormatted()`、`editMessage()`、overflow split（渲染后长度）、三级降级 |
| `Sources/AxionCLI/Services/Telegram/TGMessageFormatter.swift` | NEW，封装 MarkdownV2/HTML 渲染与降级策略 |
| `Sources/AxionCLI/Services/Telegram/TGErrorSanitizer.swift` | NEW，`sanitizeForTelegramError()` 错误摘要化 |

**TGMessageFormatter 核心接口：**

```swift
struct TGMessageFormatter {
    /// 将 agent 输出转为 Telegram 可渲染的格式化文本。
    /// - Returns: (formattedText, parseMode) 按 MarkdownV2 → HTML → PlainText 依次尝试
    func format(_ text: String) -> (String, TGParseMode)

    /// 安全切块，基于渲染后长度（而非源码长度）
    func split(formattedText: String, parseMode: TGParseMode, maxRenderedLength: Int = 4096) -> [String]
}

enum TGParseMode: String, Codable {
    case markdownV2 = "MarkdownV2"
    case html = "HTML"
    case plain = ""  // 不设置 parse_mode
}

struct TGReplyContext: Sendable {
    let replyToMessageId: Int64?
    let preserveReplyForFirstChunkOnly: Bool
}
```

---

### Story 32.2: Edit-based Streaming 与状态气泡复用

As a Axion Telegram 用户,
I want 在任务执行过程中看到持续更新的同一条消息,
So that 我能像看桌面端流式输出一样实时了解进度，而不是被一串碎片消息刷屏。

**事件来源（基于 SDK 已有事件）：**

- `LLMTokenStreamEvent.chunk` → agent 文本输出的 token 级增量
- `ToolStartedEvent` → 记录 toolUseId → toolName 映射，用于 segment 切换和 finalize 标记（`ToolStreamingEvent` 只有 `toolUseId`，无 toolName，必须通过 `ToolStartedEvent` 获取）
- `ToolStreamingEvent.chunk` → 工具执行的流式输出
- `ToolCompletedEvent` → 标记当前工具段结束，触发 finalize（显示 "✓ {toolName} (1.2s)"）
- `AgentCompletedEvent` → 标记整个任务结束，触发最终 finalize

**前置条件**：`AgentBuilder.BuildConfig` 为 TG 任务启用 `emitTokenStream: true`，使 SDK 在 `EventBus` 上发射 `LLMTokenStreamEvent`。

**流式状态模型：**

`TGStreamingController` 必须显式维护单任务状态，而不是靠若干散落变量拼接：

```swift
struct TGStreamSession: Sendable {
    let chatId: Int64
    let taskId: UUID
    var previewMessageId: Int64?
    var previewParseMode: TGParseMode
    var replyContext: TGReplyContext
    var bufferedText: String
    var renderedPreview: String
    var currentSegment: TGStreamSegment
    var lastEditAt: ContinuousClock.Instant?
    var retryAfterUntil: ContinuousClock.Instant?
    var transport: TGStreamingTransport
    var toolNameMap: [String: String]  // toolUseId → toolName，由 ToolStartedEvent 填充
    var finalized: Bool
}

enum TGStreamSegment: Sendable {
    case llm
    case tool(name: String)
    case final
}
```

`previewMessageId`、segment 切换、renderedPreview、`retryAfterUntil` 的 ownership 全部归 `TGStreamingController`；`TelegramAdapter` 只暴露发送/编辑原语，不保存流式状态。

**Acceptance Criteria:**

**Given** TG 任务开始执行且 streaming 已开启
**When** `LLMTokenStreamEvent` 首个 chunk 到达
**Then** Telegram 先发送一条 preview/status 气泡（含 "⏳ 思考中..." 前缀）
**And** 记录该消息的 `messageId` 用于后续编辑

**Given** streaming 过程中持续收到 `LLMTokenStreamEvent`
**When** 累积的 token 达到缓冲阈值或距上次编辑超过节流间隔（默认 0.8 秒）
**Then** 编辑已发送的气泡消息，追加新内容
**And** 编辑操作受 TG API 限流保护（同一 chat 约 1 msg/sec）
**And** 不再额外发送旧式 `ToolCompletedEvent` 步骤文本

**Given** agent 在执行过程中跨越工具边界（收到 `ToolCompletedEvent`）
**When** StreamingController 处理该事件
**Then** 当前段落 finalize（追加工具完成标记如 "✓ Bash (1.2s)"）
**And** 后续 `LLMTokenStreamEvent` 开始新段落
**And** 工具状态和最终回答不会糊成一坨

**Given** Telegram `editMessageText` 临时失败（网络抖动、429、超时）
**When** StreamingController 识别为可重试错误
**Then** 不永久关闭编辑能力
**And** 后续编辑继续尝试
**And** 对 429 错误按 `Retry-After` header 延迟

**Given** 编辑永久失败（消息已删除、chat 已变更等）
**When** StreamingController 检测到不可恢复错误
**Then** 自动退化为 append-only 发送（发新消息而非编辑）
**And** 最终结果依然可靠送达

**Given** `AgentCompletedEvent` 到达且最终文本与上一次 preview 内容相同
**When** 结束 streaming
**Then** 仍执行 finalize edit
**And** "⏳ 思考中..." 前缀被清除，替换为最终格式化结果

**Given** 内容超过单条消息 4096 字渲染长度限制
**When** finalize 时内容超长
**Then** 复用 Story 32.1 的 `TGMessageFormatter.split()` 切块
**And** 第一块编辑已有气泡，后续块发送新消息

**Given** preview 气泡已存在超过 `gateway.telegramFreshFinalAfterSeconds`
**When** `AgentCompletedEvent` 到达
**Then** controller 允许放弃编辑旧 preview
**And** 改为发送一条全新的 final message，避免长时间旧消息不断被改写

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Services/Telegram/TGStreamingController.swift` | NEW，负责事件消费、缓冲、节流、segment finalize、fallback |
| `Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift` | 重构为 streaming 模式：创建 TGStreamingController，委托流式事件处理；订阅列表新增 `LLMTokenStreamEvent`、`ToolStartedEvent`、`ToolStreamingEvent` |
| `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` | 增加 `editMessage(chatId:messageId:text:parseMode:)` 方法 |
| `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift` | 新增 `editMessageText` API 支持 |
| `Sources/AxionCLI/Services/AgentBuilder.swift` | `BuildConfig` 新增 `emitTokenStream` 字段；`build()` 读取并设置 `agentOptions.emitTokenStream` |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` | 构建 TG 任务的 `BuildConfig` 时传入 `emitTokenStream: true` |

**TGStreamingController 核心接口：**

```swift
actor TGStreamingController {
    /// 初始化，注入发送和编辑能力
    init(chatId: Int64,
         sendMessage: @Sendable (String, Int64) async -> Void,
         editMessage: @Sendable (Int64, Int64, String) async -> Bool,
         config: TGStreamingConfig)

    /// 消费事件，由 TGEventHandler 调用
    func handle(_ event: any AgentEvent) async

    /// 强制 finalize（用于任务结束或超时）
    func finalize() async

    /// 标记为已取消（TaskSerialQueue.cancelAll 时调用，放弃 buffer 中未发送内容）
    func cancel() async
}

enum TGStreamingTransport: String, Codable, Sendable {
    case edit    // edit-based streaming（默认）
    case append  // append-only fallback（edit 失败或被禁用时的降级模式）
    case off     // 禁用 streaming，退回到旧式步骤消息
    // 注意：draft 不在此枚举中。Draft Preview 是 Story 32.3 的 stretch goal，
    // 如果 spike 通过后在 32.3 中扩展此枚举，而不是在基线中预留。
}

struct TGStreamingConfig: Sendable {
    var editInterval: TimeInterval = 0.8      // 编辑节流间隔
    var bufferThreshold: Int = 24              // 累积 token 缓冲阈值
    var transport: TGStreamingTransport = .edit
    var freshFinalAfter: TimeInterval = 60
}
```

**TGStreamingController 生命周期：**

每个任务创建一个 controller 实例，生命周期绑定到 `TaskSerialQueue` 的任务执行 scope：

1. **创建**：`TGEventHandler.init()` 时创建 controller，注入 `sendMessage` 和 `editMessage` 闭包
2. **活跃**：`TGEventHandler.handle()` 将 streaming 相关事件委托给 controller
3. **Finalize**：`AgentCompletedEvent` 到达后 controller 执行最终 finalize，清除 "⏳ 思考中..." 前缀
4. **销毁**：`withThrowingTaskGroup` 的 task 结束后，handler 和 controller 随之被 ARC 回收
5. **取消**：`TaskSerialQueue.cancelAll()` 取消 task group，触发 handler 的 deinit。controller 不需要显式 cancel，因为 Task 取消后不再有新事件到达。但如果有 buffered 内容未发送，`finalize()` 应做 best-effort flush

**Reply handler / editMessage 闭包 wiring 链：**

当前 `TGEventHandler` 的 init 只接受 `sendMessage` 闭包。Streaming 模式下需要 `editMessage` 能力，wiring 链如下：

```
GatewayCommand
  → TelegramAdapter（actor，提供 sendReply / editMessage 方法）
  → TaskSerialQueue（持有 adapter 弱引用，在 updateReplyHandler 中注入闭包）
  → TGEventHandler（init 接收 sendMessage + editMessage 两个闭包）
  → TGStreamingController（init 接收 sendMessage + editMessage 两个闭包）
```

变更要点：
- `TGEventHandler.init()` 新增 `editMessage: @Sendable (Int64, Int64, String) async -> Bool` 参数
- `TaskSerialQueue.executeNewWithTimeout()` / `executeWithTimeout()` 创建 TGEventHandler 时，从 `replyHandler` 之外额外注入 `editMessage` 闭包（调到 `TelegramAdapter.editMessage()`）
- `TaskSerialQueue.init()` 需要新增 `editHandler: @Sendable (Int64, Int64, String) async -> Bool` 参数
- `GatewayCommand` 中组装 `TaskSerialQueue` 时注入 adapter 的 editMessage 方法

**TG API 限流策略：**

TG `editMessageText` 对同一 chat 约限制 1 msg/sec。TGStreamingController 内部维护 `lastEditTime`，在节流间隔内累积 buffer 而不发送编辑请求。遇到 429 响应时读取 `Retry-After` header 并延迟下次编辑。连续 3 次 429 则降级为 append-only。

---

### Story 32.3: Typing UX 与 Draft Preview 技术预研（Stretch Goal）

> **优先级：Stretch Goal。** 本 Story 拆成两层：Typing Indicator 可直接实现；Draft Preview 必须先完成可行性验证，再决定是否进入交付范围。

As a Axion Telegram 用户,
I want 在私聊里获得更自然的"正在思考/正在输入"体验,
So that Telegram 远程交互更像一个实时助手，而不是偶尔冒出几条生硬通知。

**两种 UX 机制，互不依赖：**

1. **Typing Indicator**（可靠，所有场景可用）：`sendChatAction(chatId, action: .typing)`
2. **Draft Preview**（实验性，仅私聊 + 通过兼容性门禁后才允许实施）

**Draft Preview 门禁输出物：**

在进入实现前，必须先完成一份 technical spike，至少回答：

1. Telegram Bot API 是否真实支持 bot 侧 draft 预览，还是只有客户端本地草稿能力
2. 私聊、group、supergroup、不同 iOS/macOS 客户端上的可见行为是否一致
3. 如果 draft 不可用，是否只保留 typing + edit streaming 作为最终方案
4. 失败模式是否仅影响体验，不会污染最终落地消息

**Acceptance Criteria:**

**Given** 任务开始执行且尚未收到首个 `LLMTokenStreamEvent`
**When** 任务处于进行中
**Then** 定期发送 `sendChatAction(.typing)`（间隔 4 秒，TG typing 状态约持续 5 秒）
**And** 收到真实 streaming chunk 后停止独立 typing 发送
**And** 真实消息发出后重新补发 typing，避免静默间隙

**Given** 当前会话是 Telegram 私聊
**When** 启动 streaming
**Then** 只有在 draft spike 已确认可用时，才尝试使用 private-chat draft preview 帧展示草稿内容
**And** 如果首次 draft API 调用失败（返回非 200 或客户端不支持），标记该 chatId 为 draft-unavailable
**And** 后续该 chatId 不再尝试 draft，直接使用 Story 32.2 的 edit-based transport
**And** 最终完成时仍通过普通消息正式落地结果

**Given** 当前会话是 group / supergroup，或 draft 已标记为不可用
**When** 启动 streaming
**Then** 自动回退到 Story 32.2 的 edit-based transport
**And** 不需要用户配置额外开关

**Given** draft preview 或 typing API 失败
**When** Adapter 处理异常
**Then** 不影响最终消息发送
**And** 失败被视为体验降级，不是任务失败

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift` | 新增 `sendChatAction`；只有在 spike 通过后才考虑 draft preview API |
| `Sources/AxionCLI/Services/Telegram/TGStreamingController.swift` | 增加 typing timer 和 draft transport 分支 |
| `Sources/AxionCLI/Services/Telegram/TGDraftStateStore.swift` | NEW，记录 chatId → draftAvailable 状态，in-memory，无需持久化 |

---

### Story 32.4: 命令注册表、帮助输出与 Bot 菜单

As a Axion Telegram 用户,
I want TG 命令既可 discover，又能和 Gateway 能力同步扩展,
So that 我不用记忆所有指令，也不会因为 Bot 菜单过时而困惑。

**Acceptance Criteria:**

**Given** TelegramAdapter 启动成功
**When** 初始化命令体系
**Then** 从 Telegram 专用命令注册表构建 Telegram 命令元数据
**And** 至少支持 `/help`、`/commands`、`/status`、`/skills`、`/new`、`/queue`

**Given** 用户发送 `/help`
**When** TGCommandRouter 处理命令
**Then** 返回简洁的入门帮助
**And** 说明普通文本消息会被视为任务
**And** 帮助里的命令名符合 Telegram 命名限制

**Given** 用户发送 `/commands`
**When** Router 处理命令
**Then** 返回完整命令列表和每个命令的单行说明
**And** 长输出自动切块

**Given** 用户发送 `/queue`
**When** 当前任务执行中或队列非空
**Then** 回复当前 chat 的执行状态、队列长度和是否会复用已有 session

**命令注册表边界：**

- `TGCommandRegistry` 是 **Telegram adapter 内部真相源**，负责：
  - Telegram 合法命令名（小写/下划线）
  - 单行说明与帮助文案
  - alias / `@botname` 规范化
  - `setMyCommands` 菜单裁剪
- 本 Epic **不**要求把 CLI、MCP、Telegram 命令系统合并为跨平台统一注册表。
- 如果后续要做跨平台命令抽象，应在新 Epic 中从 `TGCommandRegistry` 提炼，而不是在本 Epic 里一步到位。

**Given** Telegram 命令含 `@botname` 后缀、大小写变化、或 registry 内部命令包含 `-`
**When** Router 做命令规范化
**Then** 正确识别命令
**And** Telegram 菜单展示形式使用 Bot API 允许的小写/下划线命名

**Given** Bot 启动或命令集变更
**When** Adapter 调用 Telegram Bot API
**Then** 将高频命令同步到 `setMyCommands` 菜单
**And** 菜单数量超限时按优先级裁剪（`setMyCommands` 最多支持 100 个命令，每个命令名最长 32 字符）

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Services/Telegram/TGCommandRouter.swift` | 从硬编码 switch 升级为 registry-driven router |
| `Sources/AxionCLI/Services/Telegram/TGCommandRegistry.swift` | NEW，命令元数据注册表，支持 describe/help/aliases |
| `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift` | 新增 `setMyCommands` 支持 |
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | Gateway 启动时注册 Telegram bot commands |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` | 暴露 `pendingCount(chatId:)`、`isProcessing(chatId:)`、`hasActiveSession(chatId:)` 给 `/queue` |

**TGCommandRegistry 核心接口：**

```swift
struct TGCommandDef: Sendable {
    let name: String           // e.g. "status"（无斜杠）
    let description: String    // 单行说明，用于 /commands 和 setMyCommands
    let helpText: String       // 多行详细说明，用于 /help <command>
    let menuPriority: Int      // 越小越靠前，用于 setMyCommands 裁剪
    let handler: @Sendable (Int64) async -> String
}

struct TGCommandRegistry: Sendable {
    private var commands: [String: TGCommandDef] = [:]

    mutating func register(_ def: TGCommandDef)
    func resolve(_ rawCommand: String) -> TGCommandDef?
    func allCommands() -> [TGCommandDef]
    func menuCommands(limit: Int = 100) -> [TGCommandDef]
}
```

---

### Story 32.5: 交互式审批、确认与 Clarify

As a Axion Telegram 用户,
I want 危险操作审批、确认和多选澄清都能直接点按钮完成,
So that 远程操作时不需要输入一堆格式脆弱的文本命令。

**Callback 模型扩展：**

当前 `TGUpdate` 只有 `message` 字段。Inline keyboard 的用户响应通过 `callback_query` 到达。需要扩展数据模型：

```swift
// TGModels.swift 扩展
struct TGUpdate: Codable, Sendable, Equatable {
    let updateId: Int64
    let message: TGMessage?
    let callbackQuery: TGCallbackQuery?  // NEW

    enum CodingKeys: String, CodingKey {
        case updateId = "update_id"
        case message
        case callbackQuery = "callback_query"
    }
}

struct TGCallbackQuery: Codable, Sendable, Equatable {
    let id: String              // callback_query_id，用于 answerCallbackQuery
    let from: TGUser
    let message: TGMessage?     // 原始带 inline keyboard 的消息
    let data: String?           // 按钮回调数据（如 "approve:once:abc123"）

    enum CodingKeys: String, CodingKey {
        case id, from, message, data
    }
}
```

**TGAPIClient 新增：**

```swift
// TGAPIClient.swift 新增方法
func answerCallbackQuery(callbackQueryId: String, text: String?) async throws
func sendMessage(chatId: Int64, text: String, parseMode: TGParseMode?,
                 replyMarkup: TGInlineKeyboardMarkup?) async throws -> TGMessage
func editMessageText(chatId: Int64, messageId: Int64, text: String,
                     parseMode: TGParseMode?,
                     replyMarkup: TGInlineKeyboardMarkup?) async throws -> Bool
```

**Acceptance Criteria:**

**交互来源约束：**

- **审批/确认**：优先承接 SDK `pause_for_human` / runtime approval 事件，不再为 Telegram 额外发明一套暂停协议。
- **多选 clarify**：使用 inline keyboard + callback query。
- **自由文本 clarify**：用户点击 `Type Answer` 后，Gateway 进入“等待下一条文本消息作为恢复上下文”的模式，并在收到文本后调用 `agent.resume(context:)`。
- **不在本 Epic 内默认重新启用 `AskUserTool`**；如果后续要恢复，应单独评估全局 question handler 与多 chat 并发的冲突。

**Given** agent 触发危险命令审批
**When** Gateway 需要用户确认
**Then** Telegram 发送 inline keyboard
**And** 至少提供 `Allow Once`、`Session`、`Always`、`Deny` 四个动作
**And** 消息正文包含命令预览和审批原因
**And** `callback_data` 编码为 `approve:{scope}:{pendingId}`（总长度 ≤ 64 字节，TG 限制）

**Given** 某个 slash command 需要二次确认
**When** Gateway 发送确认消息
**Then** Telegram 展示 `Approve Once`、`Always Approve`、`Cancel` 按钮
**And** 用户点击按钮即可完成确认，不要求再输入文本

**Given** agent 使用 ask/clarify 且提供多个候选项
**When** Adapter 渲染 clarify 消息
**Then** 消息正文展示完整选项文本
**And** 每个选项有独立按钮
**And** 另有 `Type Answer` 入口切换到文本捕获模式

**Given** callback query 来自未授权用户、已过期的确认 ID、或不属于当前 chat/session
**When** Gateway 处理该 callback
**Then** 安全忽略或返回"已过期/未授权"提示
**And** 不会错误解锁其他人的会话

**Given** 用户点击某个按钮后 Telegram 还显示 loading spinner
**When** callback 被成功处理
**Then** Gateway 调用 `answerCallbackQuery` 结束转圈
**And** 原审批消息按需要更新为"已批准/已拒绝/等待文本输入"

**Approval / Clarify 阻塞机制：**

审批与 clarify 统一复用 SDK `Agent.pause(reason:)` / `resume(context:)`：

1. agent/runtime 到达人工决策点，调用 `pause(reason:)`
2. `TaskSerialQueue` 为当前 chat/session 保存**活跃 agent 引用 + pending interaction metadata**
3. `TGEventHandler` 或 `TelegramAdapter` 发送 inline keyboard / “等待输入”提示
4. `TelegramAdapter.pollLoop()` 收到 `callback_query` 或下一条文本消息后，解析为恢复上下文
5. 通过活跃 agent 的 `resume(context:)` 恢复执行

这里的 `TGInteractiveSessionStore` 只保存 pending interaction 元数据、授权信息和恢复路由，不保存自建 continuation。

**Callback → Agent.resume() 可达性设计（关键架构路径）：**

当前 `TaskSerialQueue` 的 agent 是 `executeNewWithTimeout()` / `executeWithTimeout()` 内部的局部变量，运行在 `withThrowingTaskGroup` 的 child task 中。`TelegramAdapter.pollLoop()` 收到 callback 后，**无法直接访问正在运行的 agent**。需要以下桥接：

```
Agent (运行在 TaskSerialQueue 的 task group child task 中)
  ↓ pause(reason:)
  ↓ SDK emit AgentPausedEvent
TGEventHandler 收到 AgentPausedEvent
  ↓ 通过 TGInteractiveSessionStore.register() 记录 pending interaction
  ↓ 返回 resumeHandle（闭包：调到 agent.resume(context:)）
  ↓ 该 handle 存入 TaskSerialQueue 的 activeResumeHandles 字典
TelegramAdapter.pollLoop() 收到 callback_query
  ↓ 解析 pendingId
  ↓ 调用 TaskSerialQueue.resumeInteraction(pendingId:data:)
TaskSerialQueue 查找 activeResumeHandles[pendingId]
  ↓ 调用 resumeHandle(context)
Agent.resume(context:) 被触发，继续执行
```

实现要点：

1. **`ActiveResumeHandle`**：`TaskSerialQueue` 新增 `activeResumeHandles: [String: @Sendable (String) async -> Void]`，key 为 pendingId
2. **Agent 暴露 resume 闭包**：在 `executeNewWithTimeout()` / `executeWithTimeout()` 创建 agent 后，将 `agent.resume` 封装为闭包存入 queue
3. **Event handler 与 queue 的协作**：`TGEventHandler` 收到 `AgentPausedEvent` 时（需新增此事件订阅），向 `TGInteractiveSessionStore` 注册，拿到 pendingId，再通知 `TaskSerialQueue` 将 pendingId → resume 闭包 绑定
4. **清理**：agent 执行结束或超时后，清除对应的 resume handle；TTL 过期后 `TGInteractiveSessionStore.cleanupExpired()` 清除元数据，但 resume handle 由 queue 端在 task group 完成时自动清理

**注意**：SDK 需要确认是否已提供 `AgentPausedEvent`。如果 SDK 未提供此事件，备选方案为：在 SDK 的 `onRunComplete` 回调前，通过 hook 机制（如 `SafetyHookRegistry`）在暂停点注入通知。详细设计阶段需验证 SDK 事件覆盖。

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Services/Telegram/TGModels.swift` | 新增 `TGCallbackQuery`、`TGInlineKeyboardMarkup`、`TGInlineKeyboardButton` |
| `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift` | 新增 `answerCallbackQuery`、`sendMessage`/`editMessageText` 的 replyMarkup 参数 |
| `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` | `pollLoop` 增加 callback query 分支处理；新增 `processCallback()` 路由到 `TaskSerialQueue.resumeInteraction()` |
| `Sources/AxionCLI/Services/Telegram/TGInteractiveSessionStore.swift` | NEW，保存 approval/confirm/clarify 状态、授权信息、pending text capture |
| `Sources/AxionCLI/Services/Telegram/TGCommandRouter.swift` | 将文本命令确认与按钮流程统一接入 |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` | 新增 `activeResumeHandles: [String: @Sendable (String) async -> Void]`；新增 `registerResumeHandle(pendingId:handle:)`、`resumeInteraction(pendingId:context:)` 方法；task group 完成时清理对应 handles |
| `Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift` | 订阅 `AgentPausedEvent`（或等效暂停通知），触发 `TGInteractiveSessionStore.register()` 并绑定 resume handle |

**TGInteractiveSessionStore 设计：**

```swift
actor TGInteractiveSessionStore {
    /// 等待用户交互的 pending session
    private struct PendingInteraction: Sendable {
        let pendingId: String
        let chatId: Int64
        let sessionId: String
        let allowedUserId: Int64?
        let createdAt: ContinuousClock.Instant
        let ttl: Duration                       // 默认 5 分钟
        let mode: TGInteractionMode
        let callbackPayloads: Set<String>
        let awaitsTextReply: Bool
    }

    private var pending: [String: PendingInteraction] = [:]

    /// 注册一个需要等待用户响应的交互
    /// - Returns: pendingId，编码进 callback_data
    func register(chatId: Int64, ttl: Duration = .seconds(300),
                  sessionId: String,
                  allowedUserId: Int64?,
                  mode: TGInteractionMode,
                  callbackPayloads: Set<String>,
                  awaitsTextReply: Bool = false) -> String

    /// 解析 callback query，返回恢复上下文或拒绝原因
    func resolveCallback(pendingId: String, data: String, fromUser: Int64) async -> TGInteractionResolution

    /// 捕获文本回答，返回恢复上下文
    func resolveTextReply(chatId: Int64, fromUser: Int64, text: String) async -> TGInteractionResolution

    /// 清理过期 session（定期调用或每次 register 时检查）
    func cleanupExpired()
}
```

存储策略：**in-memory only**，不需要持久化。Gateway 重启时所有 pending interaction 自动失效。TTL 默认 5 分钟，过期后 callback 返回"已过期"提示。actor 隔离保证并发安全（多个 callback 同时到达时串行处理）。**恢复动作本身由 active agent handle 执行**，不是由 store 持有 continuation 执行。

---

## TG API 限流策略总览

| API | TG 限制 | 应对策略 |
|-----|---------|---------|
| `sendMessage` | ~30 msg/sec（不同用户），1 msg/sec（同一用户） | 串行发送，间隔 30ms |
| `editMessageText` | ~1 msg/sec（同一 chat 的同一消息） | TGStreamingController 节流间隔 0.8s，累积 buffer |
| `sendChatAction` | ~1 次/5sec 有效 | 间隔 4 秒补发 |
| `answerCallbackQuery` | 无明确限制 | 收到即发 |
| `setMyCommands` | 不频繁调用 | 仅在 bot 启动或命令变更时调用 |

遇到 429 响应时的统一处理：
1. 读取 `Retry-After` header
2. 延迟相应时间后重试
3. 连续 3 次 429 → 降级为更低频操作（如 edit → append-only）

**错误分类前置要求：**

已在 Story 32.1 中定义 `TGAPIError` 四分类（`retryableNetwork` / `rateLimited` / `formatRejected` / `permanentTelegramError`），是所有后续 Story 限流/降级逻辑的前置依赖。

---

## 建议配置扩展

| 配置项 | 默认值 | 用途 |
|--------|--------|------|
| `gateway.telegramStreamingEnabled` | `true` | 是否启用 TG 流式回复 |
| `gateway.telegramStreamingTransport` | `"edit"` | `edit` / `off`（draft 为 stretch goal，不在基线配置中） |
| `gateway.telegramEditInterval` | `0.8` | 编辑节流间隔（秒） |
| `gateway.telegramBufferThreshold` | `24` | 累积 token 缓冲阈值 |
| `gateway.telegramTypingEnabled` | `true` | 是否发送 typing/chat action |
| `gateway.telegramTypingInterval` | `4.0` | typing 补发间隔（秒） |
| `gateway.telegramFreshFinalAfterSeconds` | `60` | preview 气泡超过此秒数后发新 final message |
| `gateway.telegramApprovalTTLSeconds` | `300` | 审批/确认等待超时（秒） |

**AxionConfig 新增字段定义：**

```swift
// AxionConfig.swift 新增 Telegram 体验配置
var telegramStreamingEnabled: Bool?           // 默认 true
var telegramStreamingTransport: String?       // "edit" / "off"，默认 "edit"
var telegramEditInterval: Double?             // 默认 0.8
var telegramBufferThreshold: Int?             // 默认 24
var telegramTypingEnabled: Bool?              // 默认 true
var telegramTypingInterval: Double?           // 默认 4.0
var telegramFreshFinalAfterSeconds: Double?   // 默认 60
var telegramApprovalTTLSeconds: Int?          // 默认 300
```

**便捷方法（避免各处重复默认值）：**

```swift
extension AxionConfig {
    var tgStreamingEnabled: Bool { telegramStreamingEnabled ?? true }
    var tgStreamingTransport: TGStreamingTransport {
        telegramStreamingTransport.flatMap(TGStreamingTransport.init(rawValue:)) ?? .edit
    }
    var tgEditInterval: Double { telegramEditInterval ?? 0.8 }
    var tgBufferThreshold: Int { telegramBufferThreshold ?? 24 }
    var tgTypingEnabled: Bool { telegramTypingEnabled ?? true }
    var tgTypingInterval: Double { telegramTypingInterval ?? 4.0 }
    var tgFreshFinalAfter: Double { telegramFreshFinalAfterSeconds ?? 60 }
    var tgApprovalTTL: Int { telegramApprovalTTLSeconds ?? 300 }
}
```

**配置接入面：**

详细设计必须同步补齐以下接入路径，而不是只在 epic 中声明键名：

| 接入点 | 要求 |
|--------|------|
| `AxionConfig` / gateway config model | 增加上述类型安全字段与默认值便捷方法 |
| `ConfigManager` / 配置加载路径 | 支持从 config.json 文件读入 Telegram 配置（已有 `telegramBotToken` / `telegramAllowedUsers` 的加载路径，新增字段沿用同一模式） |
| `GatewayCommand` 启动路径 | 在 adapter / queue 初始化时从 `AxionConfig` 读取并注入 `TGStreamingConfig`、`TGStreamingTransport`、approval TTL |
| 单元测试默认配置 | 为 streaming / approval / typing 提供稳定默认值，避免测试依赖真实环境 |

---

## 测试矩阵

Detailed design 必须覆盖下列测试面，避免实现阶段遗漏关键边界：

| 领域 | 必测场景 |
|------|----------|
| Formatter | 标题、列表、代码块、链接、表格降级、MarkdownV2 失败降级到 HTML/PlainText |
| Reply 语义 | 首块 reply 原消息、continuation 不再 reply、群聊/私聊行为一致 |
| Streaming | 首个 chunk 建 preview、节流编辑、tool segment finalize、fresh final、overflow split |
| Fallback | `editMessageText` 网络错误、429 + Retry-After、永久失败降级 append-only |
| Commands | `/help`、`/commands`、`/queue`、`@botname` 后缀、非法命令名规范化 |
| Interaction | callback query 未授权、过期 pendingId、跨 chat 注入、Type Answer 文本恢复 |
| Pause/Resume | 审批恢复、clarify 恢复、超时、agent 已结束时的迟到 callback |
| Config | streaming 开关关闭、typing 关闭、freshFinalAfter 自定义、approval TTL 自定义 |

所有新增测试继续使用 **Swift Testing**，并遵守现有单元测试 mock 规则：不得调用真实 Telegram API、真实 agent build、真实通知或真实外部进程。

---

## 范围边界

本 Epic 聚焦 **Telegram 交互体验**，不包含以下事项：

- Telegram 语音消息输入/输出
- Telegram forum topics / thread 级完整支持
- Webhook 模式（继续沿用长轮询）
- 多平台抽象（Slack / WeChat 等）
- 全局重新启用 `AskUserTool` / question handler 并发模型重构
- 未经验证直接落地的 Draft Preview API

这些能力可以在后续独立 Epic 中继续演进。

---

## 预期成果

完成本 Epic 后，Axion Telegram 体验应从"远程提交任务的 bot"升级为"可实时协作的远程代理"：

- 普通回复更像 Hermes：可读、有层次、不会轻易因为格式问题丢消息
- 进度消息不再刷屏，而是变成可持续更新的状态气泡
- Telegram 命令从 3 条硬编码指令升级为真正可发现、可扩展的命令体系
- 审批、确认、clarify 可以直接点按钮完成，远程交互成本显著降低
