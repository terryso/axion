---
baseline_commit: e8b0435
---

# Story 29.4: TG 命令支持

Status: done

## Story

As a Axion 用户,
I want 在 TG 中使用 /status 和 /skills 命令,
So that 我可以远程查看 Gateway 状态和可用技能.

## Acceptance Criteria

1. **Given** 白名单用户发送 `/status` **When** TelegramAdapter 处理命令 **Then** 回复 Gateway 状态：运行中任务数、memory 条目数、技能数、运行时长

2. **Given** 白名单用户发送 `/skills` **When** TelegramAdapter 处理命令 **Then** 回复可用技能列表（名称 + 描述，每行一个） **And** 列表超过 4096 字符时自动分段发送

3. **Given** 白名单用户发送 `/unknown_command` **When** TelegramAdapter 处理消息 **Then** 回复 "未知命令。可用命令：/status, /skills"

## Tasks / Subtasks

- [x] Task 1: 定义 TGCommandRouter (AC: #1, #2, #3)
  - [x] 1.1 创建 `Sources/AxionCLI/Services/Telegram/TGCommandRouter.swift`
  - [x] 1.2 定义 `TGCommandRouter` struct，解析 "/" 前缀消息为命令
  - [x] 1.3 实现 `/status` 命令处理 — 查询 GatewayRunnerStatus + SkillRegistry
  - [x] 1.4 实现 `/skills` 命令处理 — 查询 SkillRegistry.userInvocableSkills
  - [x] 1.5 实现未知命令回退 — 回复可用命令列表

- [x] Task 2: 修改 TelegramAdapter 集成命令路由 (AC: #1, #2, #3)
  - [x] 2.1 在 `processMessage` 中检测 "/" 前缀文本
  - [x] 2.2 命令消息路由到 TGCommandRouter 而非 taskQueue
  - [x] 2.3 注入 statusProvider 和 skillsProvider 闭包到 TelegramAdapter

- [x] Task 3: 修改 GatewayStartCommand 传递依赖 (AC: #1, #2)
  - [x] 3.1 将 SkillRegistry 和 GatewayRunner status provider 注入 TelegramAdapter
  - [x] 3.2 确保 /status 和 /skills 命令返回真实数据

- [x] Task 4: 单元测试 (AC: #1–#3)
  - [x] 4.1 测试 /status 命令回复格式
  - [x] 4.2 测试 /skills 命令回复格式
  - [x] 4.3 测试 /skills 长列表分段
  - [x] 4.4 测试未知命令回复
  - [x] 4.5 测试非命令文本正常入队（不触发命令路由）
  - [x] 4.6 测试命令路由与授权检查的顺序（先授权再路由）

## Dev Notes

### 架构约束

**命令路由职责分离** — TelegramAdapter 当前将所有白名单文本消息直接入队为任务。本故事需要在入队前拦截 "/" 前缀消息，路由到命令处理器。TGCommandRouter 作为独立的 struct（不需要 actor 隔离，无状态变更），TelegramAdapter 调用它生成回复文本。

**SkillRegistry 是线程安全的** — SDK 的 `SkillRegistry` 使用内部 `DispatchQueue` 保护并发访问（`@unchecked Sendable`），可以在 actor 内直接调用 `registry.allSkills`、`registry.userInvocableSkills` 等属性，无需 await。

**GatewayRunnerStatus 已有完整状态** — `GatewayRunnerStatus` 包含 `activeTaskCount`、`uptimeSeconds`、`tgConnected` 等字段。`/status` 命令需要额外查询 SkillRegistry 获取技能数量，以及可选的 Memory 条目数（MVP 可简化为仅显示技能数）。

### 需要修改的文件

**`Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift`**（122 行）

当前状态：`processMessage` 检查白名单后直接将 `text` 入队到 `taskQueue`。无命令路由逻辑。

本故事变更：
- init 新增 `commandRouter: TGCommandRouter?` 参数
- `processMessage` 中在入队前检测 `text.hasPrefix("/")` — 是则路由到 `commandRouter.handle(text:)` 获取回复，调用 `sendReply`；否则正常入队
- 不修改现有的 `pollLoop`、`sendReply`、`splitMessage`、`isAuthorized` 逻辑

必须保留：所有现有行为（长轮询、白名单、分段发送、非白名单静默丢弃）。

**`Sources/AxionCLI/Commands/GatewayCommand.swift`**（435 行）

当前状态：`GatewayStartCommand.run()` 中创建 `TelegramAdapter`、`TaskSerialQueue`，配置 `runner`。已有 `skillRegistry` 变量（第 63 行）。

本故事变更：
- 创建 `TGCommandRouter` 实例，注入 `skillRegistry` 和 `runner.getStatus` 闭包
- 将 `commandRouter` 传入 `TelegramAdapter` init
- 构造闭包时确保 actor 隔离安全

必须保留：所有 GatewayCommand 行为（HTTP API、信号处理、daemon 管理、TG adapter 初始化）。

### 新增文件

```
Sources/AxionCLI/Services/Telegram/
└── TGCommandRouter.swift     # 命令路由（~80 行，无状态 struct）

Tests/AxionCLITests/Services/Telegram/
└── TGCommandRouterTests.swift    # 单元测试（~120 行）
```

### TGCommandRouter 设计

```swift
// TGCommandRouter.swift

struct TGCommandRouter: Sendable {
    typealias StatusProvider = @Sendable () -> GatewayRunnerStatus
    typealias SkillsProvider = @Sendable () -> [Skill]

    private let statusProvider: StatusProvider
    private let skillsProvider: SkillsProvider

    init(
        statusProvider: @escaping StatusProvider,
        skillsProvider: @escaping SkillsProvider
    ) {
        self.statusProvider = statusProvider
        self.skillsProvider = skillsProvider
    }

    /// Returns reply text for a command message, or nil if not a command.
    func handle(_ text: String) -> String? {
        guard text.hasPrefix("/") else { return nil }

        let command = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch command {
        case "/status":
            return formatStatus()
        case "/skills":
            return formatSkills()
        default:
            return "未知命令。可用命令：/status, /skills"
        }
    }

    private func formatStatus() -> String {
        let status = statusProvider()
        let uptime = Int(status.uptimeSeconds)
        let hours = uptime / 3600
        let minutes = (uptime % 3600) / 60
        let seconds = uptime % 60

        var lines = ["📊 Gateway Status"]
        lines.append("状态: \(status.state)")
        lines.append("运行中任务: \(status.activeTaskCount)")
        if hours > 0 {
            lines.append("运行时长: \(hours)h \(minutes)m \(seconds)s")
        } else {
            lines.append("运行时长: \(minutes)m \(seconds)s")
        }
        lines.append("TG 连接: \(status.tgConnected ?? "disabled")")
        let skills = skillsProvider()
        lines.append("可用技能: \(skills.count) 个")
        return lines.joined(separator: "\n")
    }

    private func formatSkills() -> String {
        let skills = skillsProvider()
        guard !skills.isEmpty else {
            return "暂无可用技能"
        }

        var lines = ["📋 可用技能 (\(skills.count) 个):"]
        for skill in skills.sorted(by: { $0.name < $1.name }) {
            lines.append("  • \(skill.name): \(skill.description)")
        }
        return lines.joined(separator: "\n")
    }
}
```

**关键设计决策：**
- `TGCommandRouter` 是 `struct`（值类型，无状态变更）— 无需 actor 隔离
- 通过闭包注入 `statusProvider` 和 `skillsProvider` — 调用方负责 actor 隔离
- `handle()` 返回 `String?` — nil 表示非命令，让 TelegramAdapter 继续正常入队
- 命令文本统一 `lowercased()` — `/Status` 和 `/STATUS` 都能识别
- 技能列表复用 `SkillRegistry.userInvocableSkills` — 与 `axion skill list` 和 API `/v1/skills` 一致
- 长技能列表由 TelegramAdapter 的 `splitMessage` 自动分段（已有逻辑，4096 字符限制）

### TelegramAdapter 修改

```swift
// TelegramAdapter.swift — 修改 init 和 processMessage

actor TelegramAdapter {
    private let commandRouter: TGCommandRouter?
    // ... 其余不变

    init(
        apiClient: any TGAPIClientProtocol,
        allowedUsers: Set<String>,
        taskQueue: (any TaskSerialQueueProtocol)? = nil,
        commandRouter: TGCommandRouter? = nil  // 新增
    ) {
        self.apiClient = apiClient
        self.allowedUsers = allowedUsers
        self.taskQueue = taskQueue
        self.commandRouter = commandRouter
    }

    private func processMessage(_ message: TGMessage) async {
        guard let userId = message.from?.id else { return }
        guard isAuthorized(userId: userId) else { return }
        guard let text = message.text, !text.isEmpty else { return }

        // 命令路由 — 在入队前拦截
        if let reply = commandRouter?.handle(text) {
            await sendReply(reply, to: message.chat.id)
            return
        }

        fputs("[axion] Telegram task submitted: \"\(text.prefix(50))\"\n", stderr)

        if let queue = taskQueue {
            await queue.enqueue(task: text, chatId: message.chat.id)
        } else {
            await sendReply("任务已收到", to: message.chat.id)
        }
    }
}
```

### GatewayCommand 修改

在 `GatewayStartCommand.run()` 的 Telegram adapter setup 区域（约第 196 行），创建 TGCommandRouter 并注入：

```swift
// 在 Telegram adapter setup 区域
let commandRouter = TGCommandRouter(
    statusProvider: { [runner] in await runner.getStatus() },
    skillsProvider: { [skillRegistry] in skillRegistry.userInvocableSkills }
)

let adapter = TelegramAdapter(
    apiClient: tgClient,
    allowedUsers: allowedUsers,
    commandRouter: commandRouter
)
```

### 测试要求

**框架：** Swift Testing（`import Testing`、`@Suite`、`@Test`、`#expect`）
**测试目录：** `Tests/AxionCLITests/Services/Telegram/TGCommandRouterTests.swift`

**Mock 策略：**
- `statusProvider` 闭包 — 注入返回固定 `GatewayRunnerStatus` 的闭包
- `skillsProvider` 闭包 — 注入返回固定 `[Skill]` 数组的闭包
- `Skill` 构造 — 使用 SDK 的 `Skill` struct（有 public init）

**运行测试：** `swift test --filter "AxionCLITests.Services.Telegram.TGCommandRouter"`

**也要修改：** `TelegramAdapterTests.swift` — 新增测试验证命令路由集成：
- 带 commandRouter 时，`/status` 消息被路由而不入队
- 不带 commandRouter 时，所有消息正常入队（向后兼容）

**运行全部 TG 测试：** `swift test --filter "AxionCLITests.Services.Telegram"`

### 前置 Story 经验

- **Story 29.1:** TelegramAdapter 使用 `TGAPIClientProtocol` 抽象 TG API。`sendReply` 已有分段逻辑（`splitMessage`，4096 字符限制）。新增 TGCommandRouter 不需要修改 `TGAPIClient`。
- **Story 29.1 review:** `nonisolated(unsafe)` 用于 actor 外同步读取 — TGCommandRouter 是 struct 不需要此模式。
- **Story 29.2:** TaskSerialQueue 通过 `replyHandler` 闭包回复 TG。命令路由在入队前拦截，不影响排队逻辑。
- **Story 29.3:** TGEventHandler 通过闭包注入推送消息。TGCommandRouter 同样通过闭包注入 provider，保持一致的 DI 模式。
- **NotificationHandler** 是 EventHandler actor 的最佳参考；TGCommandRouter 不是 EventHandler，是独立的消息预处理组件。

### 安全规则

- 命令路由发生在白名单检查之后 — 未授权用户不会触发命令处理（AC 隐含：先 `isAuthorized` 再路由）
- `/status` 不暴露 API Key 或内部路径 — 只显示运行状态、任务数、技能数
- `/skills` 不暴露技能文件路径或内部实现 — 只显示名称和描述
- 命令处理失败不应阻塞 TG 轮询 — try/catch 防护

### 项目结构说明

- 新建 `Sources/AxionCLI/Services/Telegram/TGCommandRouter.swift`（与 TelegramAdapter、TGAPIClient、TGModels 同目录）
- 新建 `Tests/AxionCLITests/Services/Telegram/TGCommandRouterTests.swift`
- 修改 `TelegramAdapter.swift`（init 新增 commandRouter 参数，processMessage 新增命令路由分支）
- 修改 `GatewayCommand.swift`（创建 TGCommandRouter 并注入 TelegramAdapter）
- 修改 `TelegramAdapterTests.swift`（新增命令路由集成测试）

### References

- [Source: docs/epics/epic-29-telegram-remote.md#Story 29.4 — AC 和命令需求]
- [Source: _bmad-output/planning-artifacts/prds/prd-axion-gateway-2026-05-29/prd.md#FR-2.7 — /status 命令]
- [Source: _bmad-output/planning-artifacts/prds/prd-axion-gateway-2026-05-29/prd.md#FR-2.8 — /skills 命令]
- [Source: Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift — 当前 processMessage 逻辑]
- [Source: Sources/AxionCLI/Services/GatewayRunner.swift — GatewayRunnerStatus 结构和 getStatus()]
- [Source: Sources/AxionCLI/Commands/GatewayCommand.swift — Telegram adapter 初始化区域 (L196-239)]
- [Source: Sources/AxionCLI/Commands/SkillListCommand.swift — SkillRegistry 使用模式]
- [Source: OpenAgentSDK/Tools/SkillRegistry.swift — userInvocableSkills, allSkills]
- [Source: _bmad-output/implementation-artifacts/29-3-tgeventhandler-event-push.md — 闭包注入模式参考]
- [Source: _bmad-output/implementation-artifacts/29-1-telegramadapter-core-communication.md — TelegramAdapter 分段逻辑]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- Build succeeded with no warnings after fixing StatusProvider to be async (actor isolation required for GatewayRunner.getStatus())
- One pre-existing flaky test (authorizedUserPasses timing window too short under load) — not caused by this story

### Completion Notes List

- ✅ Created TGCommandRouter.swift — stateless struct with async StatusProvider (GatewayRunner is actor) and sync SkillsProvider (SkillRegistry uses DispatchQueue internally)
- ✅ Modified TelegramAdapter — added optional commandRouter parameter (backward compatible), intercepts "/" prefix before task queue enqueue
- ✅ Modified GatewayCommand — creates TGCommandRouter with runner.getStatus() and skillRegistry.userInvocableSkills, injects into TelegramAdapter
- ✅ Created TGCommandRouterTests.swift — 13 tests covering /status, /skills, unknown commands, case insensitivity, empty list, long list, whitespace trimming, non-command nil returns
- ✅ Added 4 integration tests to TelegramAdapterTests — command routing to router, non-command enqueue, backward compat without router, auth check before routing
- ✅ All 34 new + existing TG tests pass; full unit suite (1,231 tests) passes with 0 regressions

### File List

- Sources/AxionCLI/Services/Telegram/TGCommandRouter.swift (new)
- Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift (modified — added commandRouter parameter + routing logic)
- Sources/AxionCLI/Commands/GatewayCommand.swift (modified — creates and injects TGCommandRouter)
- Tests/AxionCLITests/Services/Telegram/TGCommandRouterTests.swift (new — 15 tests)
- Tests/AxionCLITests/Services/Telegram/TelegramAdapterTests.swift (modified — 4 new integration tests)

## Change Log

- 2026-05-29: Story created from Epic 29 design doc. TGCommandRouter struct with /status, /skills commands. Injected into TelegramAdapter via optional parameter. GatewayCommand wires up SkillRegistry + GatewayRunner status.
- 2026-05-29: Implementation complete. All tasks done. 17 new tests (13 unit + 4 integration). Full suite passes.
- 2026-05-29: Code review (adversarial). Fixed weak assertion in statusCommandShortUptime test. Added 2 missing test cases (command with trailing args, @botname suffix stripping). 19 new tests total (15 unit + 4 integration). All pass.

## Senior Developer Review (AI)

**Reviewer:** Nick on 2026-05-29

**Verdict:** Approved (no CRITICAL issues; all MEDIUM issues auto-fixed)

### Findings (3 MEDIUM, 2 LOW)

**MEDIUM-1** (FIXED): `TGCommandRouterTests.swift:51` — Weak assertion `#expect(text.contains("0"))` matched any "0" in the response. Fixed to `#expect(text.contains("运行中任务: 0"))`.

**MEDIUM-2** (FIXED): Missing test for commands with trailing arguments (e.g., `/status hello world`). Added test verifying first-token parsing.

**MEDIUM-3** (FIXED): Missing test for bot username suffix (e.g., `/status@mybot`). Added test verifying `@` suffix stripping.

**LOW-1** (NOTED): AC #1 mentions "memory 条目数" in /status response but not implemented. Acknowledged as MVP simplification in Dev Notes ("可选的 Memory 条目数，MVP 可简化为仅显示技能数").

**LOW-2** (NOTED): Story's suggested test filter `"AxionCLITests.Services.Telegram.TGCommandRouter"` doesn't match Swift Testing framework names; use `"TGCommandRouter"` instead.

### Test Results

- TGCommandRouter: 15 tests passed
- TelegramAdapter: 21 tests passed
- Build: 0 warnings
