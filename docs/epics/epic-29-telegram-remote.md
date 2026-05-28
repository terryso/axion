---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
  - step-04-final-validation
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-axion-gateway-2026-05-29/prd.md
  - _bmad-output/planning-artifacts/architecture.md
project_name: 'axion'
user_name: 'Nick'
date: '2026-05-29'
status: 'complete'
epic: 29
title: 'Telegram 远程交互'
---

# Epic 29: Telegram 远程交互

用户通过手机 Telegram 远程给 Mac 上的 Axion 发任务、实时看执行进展、收到结果。单任务串行执行，排队 + 超时保护。任务完成后自动推送结果。

**FRs covered:** FR-2.1, FR-2.2, FR-2.3, FR-2.4, FR-2.5, FR-2.6, FR-2.7, FR-2.8, FR-5.1, FR-5.2, FR-5.3, FR-5.4
**NFRs:** NFR-2
**新增文件:** TelegramAdapter.swift, TGEventHandler.swift
**修改文件:** GatewayRunner.swift（集成 TG adapter）
**依赖:** Epic 28

---

### Story 29.1: TelegramAdapter 核心通信

As a Axion 用户,
I want Gateway 通过 Telegram Bot API 接收和回复消息,
So that 我可以通过 TG 文本消息与 Axion 交互.

**Acceptance Criteria:**

**Given** `AXION_TELEGRAM_BOT_TOKEN` 环境变量已设置
**When** GatewayRunner 启动 TelegramAdapter
**Then** Adapter 开始长轮询 getUpdates（timeout=30s）
**And** 收到文本消息时解析为 Update 对象（Codable 模型：Update, Message, Chat, User）

**Given** 收到来自白名单用户（`AXION_TELEGRAM_ALLOWED_USERS`）的文本消息 "打开计算器"
**When** TelegramAdapter 处理该消息
**Then** 消息被识别为有效任务，进入处理流程

**Given** 收到来自非白名单用户的消息
**When** TelegramAdapter 处理该消息
**Then** 静默丢弃，不回复、不记录用户内容、不报错

**Given** `AXION_TELEGRAM_BOT_TOKEN` 环境变量未设置
**When** GatewayRunner 尝试启动 TelegramAdapter
**Then** 记录 warning 日志，TelegramAdapter 不启动，Gateway 其余功能正常运行

**Given** TG API 调用遇到网络错误
**When** getUpdates 或 sendMessage 失败
**Then** 最多重试 3 次（指数退避 1s→2s→4s），不崩溃

### Story 29.2: 任务串行执行与排队

As a Axion 用户,
I want TG 发送的任务通过 AxionRuntime 串行执行，支持排队和超时,
So that 多个任务不会同时操作桌面冲突，且超时任务自动取消.

**Acceptance Criteria:**

**Given** TG 收到白名单用户的文本消息 "打开计算器"
**When** 没有其他任务在执行
**Then** 通过 AxionRuntime.execute() 启动任务执行（复用完整 agent loop）
**And** ConcurrencyLimiter=1 确保串行执行

**Given** 已有一个任务在执行
**When** TG 收到新的任务消息
**Then** 新任务排队等待
**And** TG 回复 "任务已排队，前面还有 1 个任务等待"

**Given** 任务已执行超过 10 分钟（`gatewayTaskTimeoutMinutes` 可配置）
**When** 超时触发
**Then** 任务自动取消
**And** TG 推送 "任务超时（10 分钟），已自动取消"

**Given** 排队中的任务
**When** 前一个任务完成
**Then** 自动开始执行排队任务
**And** TG 通知 "任务开始执行"

### Story 29.3: TGEventHandler 事件推送

As a Axion 用户,
I want 在 TG 上实时看到任务执行进展和最终结果,
So that 我不需要在电脑前也能跟踪任务状态.

**Acceptance Criteria:**

**Given** TG 任务正在执行中
**When** EventBus 发出 AgentStepEvent
**Then** TGEventHandler 推送步骤进展到 TG（节流：最多每 5 秒推送一次）
**And** 推送内容包含步骤描述（如 "步骤 2/5: 输入表达式"）

**Given** TG 任务执行完成
**When** EventBus 发出 AgentCompletedEvent
**Then** 最终结果推送到 TG
**And** 长消息自动分段发送（TG 限制 4096 字符）

**Given** TG 任务执行失败
**When** EventBus 发出 AgentFailedEvent
**Then** 错误信息推送到 TG（不包含 API Key）
**And** 错误消息包含用户友好的描述（引用 AxionError.message）

### Story 29.4: TG 命令支持

As a Axion 用户,
I want 在 TG 中使用 /status 和 /skills 命令,
So that 我可以远程查看 Gateway 状态和可用技能.

**Acceptance Criteria:**

**Given** 白名单用户发送 `/status`
**When** TelegramAdapter 处理命令
**Then** 回复 Gateway 状态：运行中任务数、memory 条目数、技能数、运行时长

**Given** 白名单用户发送 `/skills`
**When** TelegramAdapter 处理命令
**Then** 回复可用技能列表（名称 + 描述，每行一个）
**And** 列表超过 4096 字符时自动分段发送

**Given** 白名单用户发送 `/unknown_command`
**When** TelegramAdapter 处理消息
**Then** 回复 "未知命令。可用命令：/status, /skills"

### Story 29.5: TG 图片支持

As a Axion 用户,
I want 通过 TG 发送图片给 Axion,
So that 我可以提供截图或照片作为任务上下文.

**Acceptance Criteria:**

**Given** 白名单用户发送一张图片（附带或不附带文本说明）
**When** TelegramAdapter 处理该消息
**Then** 从 PhotoSize 数组中选取最大尺寸
**And** 通过 getFile API 获取文件路径，下载到临时文件
**And** 图片作为附件传入 agent 上下文

**Given** 图片下载失败
**When** TelegramAdapter 处理错误
**Then** TG 回复 "图片下载失败，请重试"
**And** 临时文件已清理

---

## 实现参考

### 复用组件

| 现有文件 | 复用方式 |
|---------|---------|
| `Sources/AxionCLI/Services/AxionRuntime.swift` | `AxionRuntime` actor — Gateway 持有一个实例，通过 `execute()` 执行任务。`RunOverrides` 控制行为（json/noVisualDelta/noReview） |
| `Sources/AxionCLI/Services/Protocols/AxionRuntimeRunning.swift` | `AxionRuntimeRunning` protocol 定义了 `execute()` 和 `executeSkill()` 接口 |
| `Sources/AxionCLI/Services/RunOrchestrator.swift` | 完整的 agent 执行 pipeline（stream loop、SIGINT 处理、post-run review/curator）。TG 任务执行可复用或参考此逻辑 |
| `Sources/AxionCLI/Services/EventHandler.swift` | `EventHandler` protocol — TGEventHandler 必须实现此协议（`identifier`, `subscribedEventTypes`, `handle(_:context:)`） |
| `Sources/AxionCLI/Runtime/Handlers/NotificationHandler.swift` | 最佳参考——同样是 actor，订阅 `AgentCompletedEvent`/`AgentFailedEvent`，通过闭包注入发送逻辑（可 mock 测试） |
| `Sources/AxionCLI/Runtime/Handlers/ReviewHandler.swift` | 参考——订阅 `AgentCompletedEvent`，检查 `shouldReview()` 后执行审查 |
| `Sources/AxionCLI/API/Models/APITypes.swift` | `SDKConcurrencyLimiter = OpenAgentSDK.ConcurrencyLimiter` — 串行执行限制 |
| `Sources/AxionCLI/Services/AgentBuilder.swift` | `BuildConfig.forAPI()` — TG 任务可参考此模式构建 agent（不含 Playwright） |

### Telegram Bot API 端点

MVP 只需实现以下端点（全部通过 URLSession HTTP 请求，无第三方库）：

```
GET  https://api.telegram.org/bot{token}/getUpdates?offset=N&timeout=30
POST https://api.telegram.org/bot{token}/sendMessage
POST https://api.telegram.org/bot{token}/sendPhoto
GET  https://api.telegram.org/bot{token}/getFile?file_path=xxx
     → 返回 file_path，拼接 https://api.telegram.org/file/bot{token}/{file_path} 下载
```

### Codable 模型（参考 TG Bot API 文档）

```swift
struct TGUpdate: Codable { let updateId: Int; let message: TGMessage? }
struct TGMessage: Codable { let messageId: Int; let chat: TGChat; let from: TGUser?; let text: String?; let photo: [TGPhotoSize]? }
struct TGChat: Codable { let id: Int64; let type: String }
struct TGUser: Codable { let id: Int64; let firstName: String?; let username: String? }
struct TGPhotoSize: Codable { let fileId: String; let width: Int; let height: Int; let fileSize: Int? }
struct TGSendMessageResponse: Codable { let ok: Bool; let result: TGMessage? }
struct TGGetUpdatesResponse: Codable { let ok: Bool; let result: [TGUpdate] }
struct TGGetFileResponse: Codable { let ok: Bool; let result: TGFile? }
struct TGFile: Codable { let fileId: String; let filePath: String? }
```

### 安全模型（参考 Hermes `gateway/run.py:_is_user_authorized()`）

Hermes 的认证链（5 级优先级）在 Axion MVP 中简化为：
- 读取 `AXION_TELEGRAM_ALLOWED_USERS` 环境变量（逗号分隔的 TG user ID）
- 消息的 `from.id` 不在白名单 → 静默丢弃（不回复、不记录内容、不报错）
- `AXION_TELEGRAM_BOT_TOKEN` 未设置 → `TelegramAdapter` 不启动，记录 warning，Gateway 其余功能正常

### TGEventHandler 设计

```swift
// 实现 EventHandler protocol
actor TGEventHandler: EventHandler {
    let identifier = "telegram-push"
    let subscribedEventTypes: [any AgentEvent.Type] = [
        ToolCompletedEvent.self,    // 步骤进展
        AgentCompletedEvent.self,   // 最终结果
        AgentFailedEvent.self,      // 错误
    ]

    private let chatId: Int64           // 当前任务的 TG chat ID
    private let sendMessage: @Sendable (String, Int64) async -> Void
    private var lastPushTime: Date = .distantPast
    private let pushInterval: TimeInterval = 5.0  // 节流：最多每 5 秒推送一次
}
```

**关键问题：chatId 传递** — EventHandler 的 `handle(_:context:)` 接收的 `EventHandlerContext` 不包含 TG chatId。解决方案：
1. TGEventHandler 初始化时注入 chatId（每个任务创建一个 TGEventHandler 实例）
2. 或在 EventHandlerContext 中扩展 metadata 字段传递 chatId
3. 或 GatewayRunner 维护一个 `sessionId → chatId` 映射

推荐方案 1：每个 TG 任务创建专属的 TGEventHandler 实例，任务完成后移除。

### 长消息分段

TG `sendMessage` 限制 4096 字符。分段策略：
- 按段落（`\n\n`）分割
- 每段不超过 4096 字符
- 超长段落按 4096 截断
- 多段消息按顺序发送（`sendMessage` 串行调用）

### 图片作为 agent 附件

SDK Agent 的 `stream()` 方法接受 `String` 类型的 prompt。图片附件的传递方式需确认：
- 检查 SDK `AgentOptions` 是否有 `attachments` 或 `images` 参数
- 如果 SDK 不支持图片输入，MVP 可将图片描述为 "用户发送了一张图片，保存在 /tmp/xxx.png" 让 agent 自行读取
- 临时文件路径传入 prompt，agent 通过 Bash 工具 `file /tmp/xxx.png` 或 `sips` 查看

### 重试策略

所有 TG API 调用（getUpdates、sendMessage、sendPhoto）共用同一重试策略：
- 网络错误最多重试 3 次
- 指数退避：1s → 2s → 4s
- 重试耗尽后记录 error 日志，不崩溃
- 长轮询 getUpdates 失败后继续下一轮（不中断轮询循环）

### 文件位置

| 新增文件 | 目录 | 说明 |
|---------|------|------|
| `TelegramAdapter.swift` | `Sources/AxionCLI/Services/` | TG Bot API 对接（长轮询、消息收发、用户白名单） |
| `TGEventHandler.swift` | `Sources/AxionCLI/Runtime/Handlers/` | EventBus → TG 推送（步骤进展、最终结果、错误） |
| `GatewayRunner.swift` | `Sources/AxionCLI/Services/` | 集成 TelegramAdapter（Epic 28 创建，Epic 29 补充 TG 初始化） |
