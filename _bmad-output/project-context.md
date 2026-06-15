---
project_name: 'axion'
user_name: 'Nick'
date: '2026-05-08'
sections_completed:
  - technology_stack
  - language_rules
  - framework_rules
  - testing_rules
  - code_quality
  - workflow_rules
  - critical_rules
existing_patterns_found: 42
---

# Axion 项目上下文 — AI Agent 实施指南

_本文件包含 AI Agent 在实现 Axion 代码时必须遵循的关键规则和模式。聚焦于容易遗漏的非显而易见的细节。_

---

## 技术栈与版本

| 技术 | 版本 | 说明 |
|------|------|------|
| Swift | 6.1+ | swift-tools-version: 6.1 |
| 目标平台 | macOS 14+ (Sonoma) | 需要 AX API 和 SMAppService |
| SPM | Swift Package Manager | 唯一包管理器，无 CocoaPods/Carthage |
| OpenAgentSDK | 远程 SPM 依赖 (`open-agent-sdk-swift` 0.10.0+) | 通过 `Package.swift` 的 Git URL + `from:` 版本约束解析；本地 clone 仅作源码参考 |
| swift-mcp | 2.0.0+（fork: terryso/swift-mcp） | Helper 端 MCP Server，AxionHelper 和 AxionCLI 均使用 |
| swift-argument-parser | 1.5.0+ | CLI 参数解析 |
| Hummingbird | 2.22.0+ | HTTP API Server 框架（Epic 5 新增） |
| swift-json-schema | 0.11.0+ | JSONSchemaBuilder，AxionHelper SelectorQuery 使用 |

**关键版本约束：**
- `swift-tools-version: 6.1` — 由 OpenAgentSDK 依赖决定（SDK 要求 6.1+）
- `macOS 14+` 是硬性要求，不能降低（AX API 变更、SMAppService）
- OpenAgentSDK 当前是远程 URL 依赖（`https://github.com/terryso/open-agent-sdk-swift.git`，`from: "0.10.0"`）；修改 SDK 后需要发布/更新远程版本并重新 resolve，不能依赖本地 path 生效
- 无 Node.js/Python 依赖 — 纯 Swift 静态编译

**NFR 性能指标（实现时必须满足）：**

| 指标 | 目标 | 来源 |
|------|------|------|
| CLI 冷启动到首次 LLM 请求发出 | < 2 秒 | NFR1 |
| AxionHelper 启动到 MCP 连接就绪 | < 500ms | NFR2 |
| 单个 AX 操作（MCP 请求到结果返回） | < 200ms | NFR3 |
| CLI 进程常驻内存 | < 30MB | NFR4 |
| Helper 进程常驻内存 | < 20MB | NFR4 |
| AxionBar 常驻内存 | < 15MB | NFR32 |
| 全局热键响应延迟 | < 200ms | NFR35 |
| 技能执行首步延迟 | < 100ms | NFR31 |
| AxionCLI 源码总行数 | ~34,100 行（239 文件，含 60+ extension 文件） | NFR51 |
| AxionCLI 桌面专属代码占比 | ≥ 70% | NFR52 |
| API/ 使用 SDK 底层组件 | RunTracker、EventBroadcaster 保留 Axion 专属端点 | NFR53 |
| ToolRegistrar.swift | ≤ 200 行，工具注册分布在 7 个分类文件 | NFR54 |
| Memory 通用逻辑来自 SDK | Axion 保留 8 个桌面专属文件 | NFR55 |
| CostTracker/TraceRecorder | SDK Agent 内建管理（AgentOptions），Axion 不自建 actor | NFR56 |

---

## 语言规则（Swift）

### 命名规范（三套规则，互不冲突）

**Swift 代码命名：**
- 类型（struct/enum/class/protocol）：PascalCase → `AxionConfig`, `Skill`, `MCPClientProtocol`
- 函数和方法：camelCase，动词开头 → `buildAgent()`, `loadPrompt()`
- 属性和变量：camelCase → `maxSteps`, `currentPlan`
- 枚举 case：camelCase → `.done`, `.needsClarification`
- 协议：名词 + `Protocol` 后缀 → `MCPClientProtocol`, `Configurable`
- 文件名：与主类型同名 → `Skill.swift`, `Value.swift`
- 目录名：PascalCase 复数 → `Commands/`, `Services/`, `Models/`

**MCP 工具命名（跨进程通信）：**
- snake_case → `launch_app`, `type_text`, `press_key`
- 动词 + 名词 → `click`, `scroll`, `get_window_state`
- 工具名必须与 `ToolNames.swift` 常量保持一致

**JSON 字段命名：**
- MCP 请求/响应参数：snake_case → `{"app_name": "Calculator"}`
- Config 文件（Codable 默认）：camelCase → `{"maxSteps": 20}`
- Trace 事件：snake_case → `{"event": "step_done"}`

### Import 顺序（严格遵守）

**规则：** 只在文件实际使用 Foundation 类型（Date/Data/FileManager/Process/URLSession 等）时才 `import Foundation`。Swift stdlib 类型（Codable, Sendable, Equatable, Error, Optional 等）不需要 import Foundation。不要 import Darwin（Foundation 已 re-export Darwin）。

```swift
// 1. 系统框架（仅在需要时）
import Foundation
import Security

// 2. 第三方依赖
import ArgumentParser
import OpenAgentSDK
import Hummingbird    // Epic 5+ HTTP API Server
import NIOCore        // ByteBuffer (SSE/Hummingbird)
import MCP
import MCPTool

// 3. 项目内部模块
import AxionCore
```

### 模型定义规范

- 所有共享模型放在 `AxionCore/` — 遵循 `Codable + Equatable` 一致性
- 枚举使用 `String` 原始值以支持 Codable → `enum ConnectionStatus: String, Codable`
- 复杂枚举编码使用 `{type, value}` 模式（参见 `Value.swift`）
- Config 使用 camelCase JSON 键 — `CodingKeys` 不做转换，依赖 Swift 默认行为
- **部分 JSON 解码规范**：Codable 模型的 `init(from decoder:)` 使用 `decodeIfPresent` + `?? Self.default.xxx`，使缺失字段自动回退到默认值。新增字段时只需在此 init 中加一行，调用方无需修改。

### 错误处理

- 统一使用 `AxionError` 枚举，**不创建新的错误类型体系**
- 每个错误 case 必须提供 `MCPErrorPayload`（含 `error`/`message`/`suggestion` 三字段）
- MCP ToolResult 中的错误 JSON 必须是 `{"error": "...", "message": "...", "suggestion": "..."}`
- 使用 `ToolResultHelper.encodeToolResult()` / `encodeToolError()` 生成格式化的工具结果输出，共享 `axionSortedEncoder`（`JSONEncoder.outputFormatting = .sortedKeys`）

### 日志级别

| 级别 | 用途 | 示例 |
|------|------|------|
| `debug` | 开发调试 | "MCP request: launch_app {app: Calculator}" |
| `info` | 用户可见的进度 | "步骤 2/5: 输入表达式" |
| `warning` | 可恢复的异常 | "AX 元素索引过期，自动刷新" |
| `error` | 操作失败 | "截图失败：权限未授予" |

- API Key **永远**不出现在任何日志级别中（NFR9）
- 生产模式默认 `info` 级别，`--verbose` 开启 `debug`

---

## 架构规则

### 模块依赖（硬性边界）

```
AxionCore ← 无外部依赖（纯模型 + 协议 + 常量）
    ↑
AxionCLI ← AxionCore + OpenAgentSDK + ArgumentParser + Hummingbird
    ↑ (仅通过 MCP stdio 通信，禁止 import)
AxionHelper ← AxionCore + mcp-swift-sdk
    ↑ (仅通过 HTTP API 通信，禁止 import AxionCLI)
AxionBar ← AxionCore + Foundation + SwiftUI + AppKit（独立 macOS App）
```

**绝对禁止：**
- `AxionCLI` import `AxionHelper`（两者仅通过 MCP stdio JSON-RPC 通信）
- `AxionBar` import `AxionCLI`（两者仅通过 HTTP API 通信，localhost:4242）
- `AxionCore` import `OpenAgentSDK`（Core 是纯模型层）
- `AxionHelper` import `OpenAgentSDK`（Helper 只做 AX 操作）
- `AxionHelper` 做任何 LLM 调用

### 文件归属规则

- 一个文件一个主类型 → `Skill.swift` 只定义 `Skill` 及其私有辅助
- Protocol 与实现分离 → `MCPClientProtocol` 在 `Protocols/`，`HelperMCPClientAdapter` 在 `Helper/`
- Extension 按功能分文件 → `AxionConfig+Codable.swift`, `Skill+Validation.swift`
- 测试镜像源结构 → `Tests/AxionCLITests/Services/RunLockServiceTests.swift`

### 四目标结构

| 目标 | 类型 | 入口 |
|------|------|------|
| AxionCore | library | 无（共享库） |
| AxionCLI | executable | `main.swift` + `@main struct AxionCLI: ParsableCommand`（含 gateway 子命令） |
| AxionHelper | executable | `main.swift`（`try await HelperMCPServer.run()`） |
| AxionBar | executable | `App.swift`（`@main struct AxionBarApp: App` + MenuBarExtra） |

---

## MCP 工具规则（Helper 端）

### 工具注册模式

使用 `@Tool` 宏和 `@Parameter` 属性包装器（来自 mcp-swift-sdk 的 MCPTool 模块）：

```swift
@Tool
struct ClickTool {
    static let name = "click"
    static let description = "Perform a single click at the specified coordinates"

    @Parameter(description: "X coordinate")
    var x: Int

    @Parameter(description: "Y coordinate")
    var y: Int

    func perform() async throws -> String { ... }
}
```

### 工具注册集中管理

所有工具通过 `ToolRegistrar`（19 行入口文件）分发到 7 个分类文件，新工具必须：
1. 创建独立的 `@Tool` struct，放入对应分类文件（AppTools/WindowTools/MouseTools/KeyboardTools/ScreenshotTools/RecordingTools）
2. 在分类文件的 `register(to:)` 方法中添加注册行
3. 共享类型放在 `ToolTypes.swift`（190 行）
4. 在 `AxionCore/Constants/ToolNames.swift` 中添加对应常量
5. 工具名必须是 snake_case（正则 `^[a-z][a-z0-9_]*$`）

**ToolRegistrar 注册模式：**
```swift
// ToolRegistrar.swift (19 行，仅分发)
struct ToolRegistrar {
    static func registerAll(to server: MCPServerProtocol) {
        AppTools.register(to: server)
        WindowTools.register(to: server)
        MouseTools.register(to: server)
        KeyboardTools.register(to: server)
        ScreenshotTools.register(to: server)
        RecordingTools.register(to: server)
    }
}
```

**Helper MCP 文件结构：**
```
Sources/AxionHelper/MCP/
├── HelperMCPServer.swift   # 38 lines (MCP server entry point)
├── ToolRegistrar.swift     # 18 lines (entry point, delegates to categories)
├── ToolTypes.swift         # 230 lines (shared types + ToolErrorProtocol + encodeToolResult/encodeToolError)
├── ToolResultHelper.swift  # 共享 helpers：rejectIfUnsafe, validateMemoryInput, requireStringParam
├── AppTools.swift          # 71 lines
├── WindowTools.swift       # 15 lines (registry) + WindowTools+Basic.swift (78) + WindowTools+Layout.swift (130)
├── MouseTools.swift        # 15 lines (registry) + MouseTools+Click.swift (143) + MouseTools+ScrollDrag.swift (54)
├── KeyboardTools.swift     # 89 lines
├── ScreenshotTools.swift   # 59 lines
└── RecordingTools.swift    # 62 lines
```

### MCP 通信规则

- 请求超时：普通工具 5 秒，截图/AX tree 10 秒
- MCP 层不重试 — 由 Executor 层决定是否重试步骤
- 截图 base64 不超过 5MB
- Helper 通过 stdio 接收 JSON-RPC，EOF 时优雅退出

---

## 测试规则

### 测试命名格式

```swift
// 格式：test_被测单元_场景_预期结果
func test_plan_codable_roundTrip_preservesAllFields() throws
func test_value_placeholder_preservesDollarSign() throws
func test_error_toToolResultJSON_containsRequiredFields() throws
```

### 测试组织

- 测试文件镜像源文件结构
- 使用 `// MARK: - 分组描述` 组织测试方法
- 测试类命名：`{被测类型}Tests` → `PlanTests`, `AxionErrorTests`

### 测试模式

**Codable round-trip 测试**（核心模式 — 几乎所有模型都有）：
```swift
func test_xxx_roundTrip() throws {
    let original = ...
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(X.self, from: data)
    XCTAssertEqual(decoded, original)
}
```

**ATDD 分级标注**（在测试类注释中标注优先级）：
```swift
// [P0] 基础设施验证
// [P1] 行为验证
```

**Mock 策略：**
- 通过 Protocol 注入 Mock（`MCPClientProtocol`, `AgentBuilderProtocol` 等）
- 不 Mock 的层：AxionCore 模型（纯数据）、JSON 编解码（直接 round-trip）
- 单元测试禁止真实系统调用（NSWorkspace、CGEvent、网络请求等），必须通过 mock/protocol 隔离
- 涉及真实系统调用的测试（`*RealTests`）必须放在 `Tests/**/Integration/` 目录，由 `make test-integration` 运行，不混入 `make test`

**Helper 测试层级：**
- 进程级冒烟测试（`HelperProcessSmokeTests`）— 启动真实进程测试 MCP JSON-RPC
- 内存级集成测试（`HelperMCPServerTests`）— 不启动进程，直接测试 MCPServer API
- 脚手架测试（`HelperScaffoldTests`）— 验证模块导入和类型存在性

---

## 并发模式

### Actor 隔离边界

| Actor | 职责 | 隔离原因 |
|-------|------|----------|
| `HelperProcessManager` | Helper 进程启停、MCP 连接 | 进程状态串行化 |
| `MCPConnection` | JSON-RPC 收发 | stdio 管道不能并发读写 |
| `TraceRecorder` | Trace 事件写入（thin SDK integration layer, 308 lines） | 文件写入串行化（SDK AgentOptions 内建管理 trace/cost） |
| `AxionRunTracker` | HTTP API 任务状态管理（wraps SDK RunTracker） | 任务状态串行化，每次状态变更持久化 |
| `EventBroadcaster` | SSE 事件多客户端广播 + 事件持久化 | 订阅者和重放缓存串行化，每次 emit 追加到 api-events.jsonl |
| `ConcurrencyLimiter` | 并发任务槽位管理（SDK 提供） | 并发计数和排队串行化 |
| `TaskQueue` | MCP Server 模式任务串行化（SDK 提供） | agent.prompt() 调用串行化 |
| `GatewayRunner` | Gateway 生命周期管理、任务调度 | 进程状态、启停、信号处理串行化（D9） |
| `TelegramAdapter` | TG Bot API 长轮询、消息收发 | TG API 调用和消息队列串行化（D10） |
| `ReviewScheduler` | 后台审查调度 | 审查间隔状态串行化（D11） |
| `CuratorScheduler` | Curator 自动调度 | 空闲计时和 curator 状态串行化（D11） |

### Helper 进程生命周期（D8）

1. CLI 首次需要 AX 操作时，`HelperProcessManager.start()` 启动 Helper
2. 通过 `Process.standardInput` / `standardOutput` 建立 stdio 管道
3. `DispatchGroup` 跟踪 Helper 进程存活状态
4. **优雅终止流程**：发送 SIGTERM → 等待最多 3 秒 → 超时则 SIGKILL
5. 注册 SIGINT handler，Ctrl-C 时传播到 Helper（NFR8）
6. Helper 意外崩溃时，检测到后尝试**重启一次**

### Task 取消传播

```swift
try await withTaskCancellationHandler {
    try await executor.execute(plan: plan)
} onCancel: {
    Task { await helperManager.stop() }
}
```

### 重试策略

- 仅用于 LLM API 调用和 transient MCP 错误
- 指数退避：1s → 2s → 4s
- **不**用于业务逻辑错误（如"应用未找到"）

---

## 关键反模式（必须避免）

1. **在 AxionCore 中 import OpenAgentSDK** — Core 是纯模型层，零外部依赖
2. **在 Helper 中做 LLM 调用** — Helper 只做 AX 操作
3. **直接使用 `print()` 输出** — CLI 使用 `SDKTerminalOutputHandler`/`SDKJSONOutputHandler`（独立文件，子类化 SDK 的 `SDKMessageOutputHandler`）统一格式化。Chat 交互模式使用 `ChatOutputFormatter`（同样实现 `SDKMessageOutputHandler`）。所有组件使用 `fputs()` + `fflush()` 控制输出目标和缓冲（AxionBar 使用 os.Logger）
4. **MCP 通信中使用 camelCase JSON 字段** — MCP 参数必须是 snake_case
5. **硬编码 prompt 文本在 Swift 代码中** — prompt 放在 `Prompts/` 目录的 Markdown 文件中
6. **AxionCLI 直接 import AxionHelper** — 两者仅通过 MCP stdio 通信
7. **AxionBar import AxionCLI** — 两者仅通过 HTTP API 通信
8. **在 MCP 工具名中使用 camelCase 或 PascalCase** — 必须是 snake_case
9. **创建新的错误类型体系** — 统一使用 `AxionError` 枚举
10. **测试中硬编码字符串而非调用真实方法** — 测试必须调用被测方法/函数，不允许测试纯字面量（bogus test）
11. **JSON 输出使用手动字符串拼接** — 必须使用 JSONEncoder + Codable struct
12. **AxionBar 测试写入真实文件系统** — 必须使用临时目录
13. **审查 agent 连接 Helper/操作桌面** — 审查 agent 工具白名单只有 memory + skill，通过 `ReviewOrchestrator.executeReview()` 创建隔离 agent（D11）
14. **TG bot token 写入 config.json** — 必须通过环境变量 `AXION_TELEGRAM_BOT_TOKEN` 传入
15. **未授权 TG 消息回复错误信息** — 静默丢弃，不泄露任何信息
16. **Detached Task 使用 EventBus 通信** — per-request EventBus 在请求完成时停止；detached Tasks 必须使用直接回调（onReviewResult、onCuratorResult），不依赖 EventBus
17. **Controller 格式化文本后传给 Adapter** — 格式化所有权归 Adapter（TelegramAdapter），Controller 和 Handler 生产原始文本。避免双重格式化（Epic 32 教训）
18. **闭包跨 3+ 文件传递时不定义 typealias** — 消费端必须定义 typealias（如 `typealias SendMessageClosure = (String, Int64) async -> Int64?`），提供端匹配。防止 Void vs Int64? 等静默类型不匹配
19. **直接使用 `Task` 而非 `_Concurrency.Task`** — OpenAgentSDK 有 `Task` 类型名冲突，Gateway/Telegram 代码中必须使用 `_Concurrency.Task`
20. **在 Chat/ 模块中使用非纯函数或直接 I/O** — Chat/ 组件必须使用纯函数或注入闭包（`readLineFn`、`isTTYFn`、`writeStdout`）；禁止逻辑类直接依赖 SDK 类型或做 I/O 操作（Epic 37 模式）
21. **修改 `axion run` 路径代码来实现 Chat 功能** — Chat 和 desktop automation 通过 `AgentMode` 枚举隔离；Chat 功能仅修改 `ChatCommand` 和 `Chat/` 目录，`RunCommand` / `RunOrchestrator` 路径完全独立
22. **Storage 域引入 `delete`/永久删除动作或使用 sudo** — `StorageAction` 契约层只有 `move`/`trash`/`createDirectory`/`uninstallApp`/`scanOnly`，破坏性操作一律 `FileManager.trashItem`（移废纸篓）+ 可撤销 manifest；永久删除在类型层即不可表达（Epic 39 安全红线）
23. **`SupportDataScanService` 调用通用 `StorageExclusions.evaluate()`** — 通用排除会吃掉整个 `~/Library`；support 数据扫描必须用 bundle-id 精确路径探测，不放宽通用排除规则（Epic 39 架构约束）

---

## Memory 系统（Epic 4 + Epic 12 + Epic 31）

Axion 的跨任务学习系统，基于证据驱动的知识生命周期管理 + 双轨通用记忆。

**存储路径：** `~/.axion/memory/`
- 旧格式：`{domain}.json` — KnowledgeEntry 数组（SDK 兼容）
- 新格式：`{domain}-facts.json` — AppMemoryFact 数组（Epic 12+）
- **通用记忆：** `MEMORY.md`（环境知识）+ `USER.md`（用户画像）（Epic 31+）

**两套记忆系统互补不替代：**

| 系统 | 文件格式 | 内容范围 | 工具/提取器 |
|------|----------|----------|-------------|
| App 操作 facts | JSON per domain | MCP 工具调用中提取的操作经验 | `AppMemoryExtractor` → `AxionFactStore` |
| 通用记忆 | Markdown | 环境知识 + 用户画像 + 偏好 | `memory` 工具 + Review 审查提取 |

**目录结构：**
```
Sources/AxionCLI/Memory/             21 files (desktop-specific + universal memory)
├── AppMemoryFact.swift              # Epic 12: 模型（MemoryFactStatus/Source/Kind 枚举）+ normalizeFact + factId (djb2)
├── AxionFactStore.swift             # Epic 12: FactStore 操作封装（提取自 AppMemoryFact）
├── AppMemoryExtractor.swift         # ~313 行核心 + 4 个 extension（+AXTree, +Classification, +FailureAnalysis, +Deprecated）
├── AppProfileAnalyzer.swift         # ~113 行核心 + 2 个 extension（+PatternExtraction, +FailureAnalysis）
├── FamiliarityTracker.swift         # Epic 4: 熟悉度追踪（>= 3 次成功标记 familiar）
├── MemoryContextProvider.swift      # ~205 行核心 + 2 个 extension（+FactContext, +UniversalMemory）
├── UniversalMemoryStore.swift       # Epic 31: actor 管理 MEMORY.md / USER.md 的读写，线程安全
├── MemorySecurityScanner.swift      # Epic 31: 写入时拒绝 + 加载时过滤，防提示注入和凭据泄露
├── MemoryTool.swift                 # Epic 31: Agent 主动读写记忆工具（add/replace/remove/read）
├── ReviewSaveUniversalMemoryTool.swift # Epic 31: 审查代理写入记忆工具（add/replace only）
├── RunMemoryProcessor.swift         # ~125 行核心 + 1 个 extension（+PostRunProcessing）
├── TakeoverLearningService.swift    # Epic 15: Takeover 经验→Memory 转换（affordance/avoid）
└── TakeoverMarker.swift             # Epic 15: InterventionReason 枚举 + TakeoverMarker struct
```

**SDK 提供的 Memory 基础设施（Epic 21 替换）：**
- `FactStore` — 替代 MemoryFactStore（actor 隔离持久化层 + 惰性迁移）
- `LifecycleService` — 替代 MemoryLifecycleService（candidate→active→retired 管理）
- `MemoryStoreProtocol` / `FileBasedMemoryStore` — SDK 存储抽象
- Memory 导入/导出由 SDK 的 bundle 机制处理（替代 MemoryBundleExportService/ImportService）

**AppMemoryFact 生命周期状态机（Epic 12）：**
```
candidate ──(evidenceCount >= 2 && confidence >= 0.65)──► active
    ▲                                                       │
    │                                              (30 天未验证)
    │                                                       ▼
    └──────────────(再次观察到)────────────────────── retired
```

**三类记忆分类（Epic 12）：**
- **affordance** — 成功发现的操作能力（confidence=0.72，直接操作占比高）
- **avoid** — 失败经验的软性避坑规则（confidence=0.5）
- **observation** — 环境信息记录（confidence=0.7）

**Prompt 注入格式：**
- affordance → "推荐路径" section
- avoid → "注意事项" section（软性建议，非硬性禁止）
- observation → "环境备注" section
- 每类最多 5 条（按 confidence 降序），附带 "soft hints, not hard rules" 声明

**CLI 命令：**
- `axion memory list` — 显示已积累 Memory（App facts + 通用记忆概要：条目数、最后更新时间）
- `axion memory show <memory|user>` — 显示通用记忆完整内容（MEMORY.md 或 USER.md）
- `axion memory clear --app <domain>` — 清除指定 App 的 Memory
- `axion memory clear --type <memory|user>` — 清空通用记忆（MEMORY.md 或 USER.md）
- `axion memory export <file>` — 全量或按 App 导出 Memory Bundle（JSON）
- `axion memory export --app <domain> <file>` — 按 App 过滤导出
- `axion memory import <file>` — 导入 Memory（降级为 candidate + confidence 封顶 0.55）
- `axion run "任务" --no-memory` — 禁用 Memory 上下文注入

**关键设计决策：**
- Memory 操作失败不阻塞任务执行（do/catch 防护 + warning 日志）
- Memory 上下文注入到 system prompt 末尾（`buildFullSystemPrompt`），不在 user prompt
- Domain 使用 App bundle identifier（如 `com.apple.calculator`）
- **不修改 SDK KnowledgeEntry** — AppMemoryFact 是独立的 AxionCLI 层模型
- **factId 使用 djb2 确定性 hash** — 跨进程稳定（不使用 Swift hashValue）
- **导入降级**：source=imported, status=candidate, confidence=min(original, 0.55)
- **合并策略**：max confidence, stronger status, local source 优先, evidenceCount +1
- **惰性迁移**：读旧 KnowledgeEntry 时自动转为 AppMemoryFact，无需强制迁移脚本
- 熟悉 App 使用紧凑规划策略（减少 list_windows/get_window_state 验证步骤）

**通用记忆系统设计决策（Epic 31）：**
- **§ 分隔符**：条目用 `§` 分隔（对齐 Hermes）。条目内容包含 `§` 会导致解析错误（已知限制，延后修复）
- **Actor 隔离**：`UniversalMemoryStore` 是 actor，序列化文件 I/O。多个实例写同一文件安全（`atomically: true`）
- **双重安全防线**：写入时 `scan()` 拒绝恶意内容；加载时 `scanEntry()` 过滤可疑条目（prompt 注入、角色劫持、凭据泄露、不可见 Unicode）
- **冻结快照**：`buildSystemPrompt()` 在会话初始化时调用一次，结果缓存。中途写入只更新磁盘，不刷新 prompt（自然实现，无需特殊缓存机制）
- **字符上限**：MEMORY.md 4000 字符，USER.md 2000 字符。超限时提示 Agent 先 replace/remove
- **两套工具**：`MemoryTool`（Agent 主动管理，add/replace/remove/read）和 `ReviewSaveUniversalMemoryTool`（审查代理保存，add/replace only）
- **注入位置**：`[=== Universal Memory ===]` 块在 App facts 之后、Skills 之前
- **SDK 集成**：`ReviewOrchestrator` 通过 `additionalReviewTools` 参数注入审查工具（SDK v0.6.1+）

**SDK 依赖（Epic 21 更新）：**
- `FactStore` — SDK 提供的 actor 隔离持久化层，替代原 MemoryFactStore
- `LifecycleService` — SDK 提供的生命周期管理，替代原 MemoryLifecycleService
- `FileBasedMemoryStore(memoryDir:)` — 自定义存储路径
- `KnowledgeEntry` — 存储单元（id, content, tags, createdAt, sourceRunId）
- `MemoryStoreProtocol` — save/query/delete/listDomains
- `AgentOptions.memoryStore` — 注入到 ToolContext（memoryStore 参数必须在 hookRegistry 之前）

---

## 录制与技能系统（Epic 9）

用户演示操作 → Axion 录制 → 编译为可复用技能 → 一键回放（无需 LLM）。

**存储路径：**
- 录制文件：`~/.axion/recordings/{name}.json`
- 技能文件：`~/.axion/skills/{name}.json`

**核心模型（AxionCore）：**
```
Sources/AxionCore/Models/
├── RecordedEvent.swift     # Recording, RecordedEvent, WindowContext, WindowSnapshot, JSONValue
└── Skill.swift             # Skill, SkillStep, SkillParameter, SkillExecutionResult
```

**核心服务（AxionCLI）：**
```
Sources/AxionCLI/Services/
├── RecordingCompiler.swift  # 录制→技能编译（纯数据转换，不需要 Helper）
└── SkillExecutor.swift      # 技能执行引擎（通过 MCP 调用 Helper）
```

**CLI 命令：**
- `axion record "任务名"` — 启动录制模式，Ctrl-C 停止并保存
- `axion skill compile <name> [--param name ...]` — 编译录制为技能
- `axion skill run <name> [--param key=value ...]` — 执行技能（不需要 LLM）
- `axion skill list` — 列出所有已保存技能
- `axion skill delete <name>` — 删除技能

**Helper 端 MCP 工具：**
- `start_recording` — 激活 CGEvent Tap（listen-only）+ NSWorkspace 监听
- `stop_recording` — 停止监听，返回录制事件和窗口快照

**关键设计决策：**
- D9：CGEvent Tap (listen-only) + NSWorkspace Notification — 精确捕获所有输入事件，CPU < 5%
- D11：纯 JSON + Codable — 可读、可编辑、Swift 原生支持
- 窗口上下文通过 500ms 定时器采样，不在 CGEvent 回调中查询 AX tree
- compile 是纯数据转换（不需要 Helper），run 需要通过 MCP 调用 Helper
- SkillExecutor 不走 PlaceholderResolver/SafetyChecker 管线 — 技能步骤是确定性序列
- SkillStep.arguments 值均为 String 类型，执行时负责类型转换为 Value
- 文件名必须使用模块级 free function `sanitizeFileName()` 进行路径安全处理（AxionFileIO.swift）
- 录制引擎 Helper 工具必须在 SafetyChecker.backgroundSafeTools 中注册

**技能文件格式（JSON）：**
```json
{
  "name": "open_calculator",
  "description": "操作录制: open_calculator",
  "version": 1,
  "parameters": [{ "name": "url", "default_value": null }],
  "steps": [
    { "tool": "launch_app", "arguments": { "app_name": "Calculator" }, "wait_after_seconds": 0.5 }
  ]
}
```

---

## 菜单栏 UI（Epic 10 — AxionBar）

独立 macOS 菜单栏常驻 App，通过 HTTP API 与 `axion server` 后端通信。

**依赖：** AxionCore + Foundation + SwiftUI + AppKit（零第三方依赖）

**目录结构：**
```
Sources/AxionBar/
├── App.swift                        # @main, MenuBarExtra 生命周期
├── StatusBarController.swift        # NSStatusItem + ConnectionState 管理
├── Models/
│   ├── ConnectionState.swift        # .disconnected / .connected / .running
│   ├── HealthCheckResponse.swift    # 健康检查响应模型
│   ├── RunModels.swift              # Bar 前缀 API 模型
│   ├── SkillModels.swift            # Bar 前缀技能 API 模型
│   └── HotkeyConfig.swift           # 热键配置模型
├── Services/
│   ├── BackendHealthChecker.swift   # 5 秒轮询 GET /v1/health
│   ├── ServerProcessManager.swift   # Process 启动/停止 axion server
│   ├── TaskSubmissionService.swift  # POST /v1/runs
│   ├── SSEEventClient.swift         # URLSession bytes stream SSE 解析
│   ├── RunHistoryService.swift      # GET /v1/runs
│   ├── SkillService.swift           # GET/POST /v1/skills
│   └── GlobalHotkeyService.swift    # NSEvent 全局/本地热键监听
├── Views/
│   ├── QuickRunWindow.swift         # NSPanel + SwiftUI 快速执行
│   ├── TaskDetailPanel.swift        # NSWindow + SwiftUI 实时日志
│   ├── RunHistoryWindow.swift       # NSWindow + SwiftUI 历史列表
│   └── SettingsWindow.swift         # NSWindow + SwiftUI 设置
└── MenuBar/
    └── MenuBarBuilder.swift         # NSMenu 构建
```

**关键设计决策：**
- D10：独立 SPM executable target，SwiftUI App + AppKit NSStatusItem 混合方案
- AxionBar 不 import AxionCLI（通过 HTTP API 通信，localhost:4242）
- AxionBar 定义自己的 API 模型（Bar 前缀），与 AxionCLI 的 APITypes 完全解耦
- 后端 API 统一返回 `StandardTaskOutput`（Epic 14），AxionBar 通过 `decodeIfPresent` 兼容新字段
- NSApp.setActivationPolicy(.accessory) 实现无 Dock 图标（AppDelegate）
- 所有 AxionBar 服务使用 @MainActor 隔离
- 窗口使用 NSPanel/NSWindow + SwiftUI hosting（非 WindowGroup）
- 全局热键使用 NSEvent.addGlobalMonitorForEvents（不使用 CGEvent Tap）
- 技能执行复用 RunTracker + EventBroadcaster SSE 管线
- 日志使用 os.Logger，AxionBar 不输出到 stdout
- 路径使用 FileManager + URL API，不拼接字符串

**API 模型命名约定：**
- Bar 前缀：`BarCreateRunRequest`、`BarRunStatusResponse`、`BarSkillSummary` 等
- `decodeIfPresent` 用于向后兼容新增字段（如 StandardTaskOutput 的 intervention、result）
- CodingKeys 使用 snake_case（与后端 API 一致）
- Swift 属性名使用 camelCase

**HTTP API 端点（AxionBar 消费的后端端点）：**

| 端点 | 方法 | 用途 |
|------|------|------|
| `/v1/health` | GET | 健康检查（5 秒轮询） |
| `/v1/runs` | POST | 提交任务 |
| `/v1/runs` | GET | 任务历史列表（?limit=N） |
| `/v1/runs/{runId}` | GET | 任务详情 |
| `/v1/runs/{runId}/events` | GET (SSE) | 实时事件流 |
| `/v1/skills` | GET | 技能列表 |
| `/v1/capabilities` | GET | 能力发现（version、tools、features） |
| `/v1/settings/api-key` | GET/POST/DELETE | API Key 配置管理 |
| `/v1/skills/{name}` | GET | 技能详情 |
| `/v1/skills/{name}/run` | POST | 执行技能 |

---

## SDK 生态（Epic 11 — 第三方 SDK 生态）

Axion 作为 OpenAgentSDK 的旗舰参考实现。ScaffoldCLI（位于 OpenAgentSDK 仓库）提供项目模板和脚手架 CLI。模板代码只使用 SDK 公共 API，`defineTool` 有 4 种重载，`AgentOptions` 字段为 `allowedTools`/`disallowedTools`。

### Axion 关键模块内联文档（Story 11.3）

以下文件包含设计决策注释，第三方开发者应参考：
- `Sources/AxionCLI/Commands/RunCommand.swift` — CLI 入口（参数解析 + AxionRuntime 执行，Epic 26）
- `Sources/AxionCLI/Services/AxionRuntime.swift` — 统一执行入口 actor（session lifecycle + EventBus + EventHandler 注册 + executeSkill for skill path）
- `Sources/AxionCLI/Services/Protocols/AxionRuntimeRunning.swift` — AxionRuntime DI 协议（测试用）
- `Sources/AxionCLI/Services/AgentBuilder.swift` — BuildResult 工厂（build() 返回 agent + options + helper manager，不执行；buildSkillAgent() 为技能执行独立路径，Epic 27 增加 eventBus 参数）
- `Sources/AxionCLI/Services/RunOrchestrator.swift` — Stream processing layer（review/curator execution, takeover; skill fast-path moved to AxionRuntime in Epic 27; cross-cutting concerns moved to EventHandlers in Epic 26）
- `Sources/AxionCLI/Services/DaemonRuntimeManager.swift` — [Epic 27] Daemon 模式运行时协调器（per-request AxionRuntime，session tracking）
- `Sources/AxionCLI/Commands/SessionsCommand.swift` — [Epic 27] axion sessions CLI 命令（--active, --limit）
- `Sources/AxionCLI/Commands/ResumeCommand.swift` — [Epic 27] axion resume CLI 命令（session 恢复，复用 RunCommand handler 注册）
- `Sources/AxionCLI/Services/SafetyHookFactory.swift` — SafetyHook 创建（提取自 AgentBuilder，34 行）
- `Sources/AxionCLI/Services/MCPConfigResolver.swift` — MCP 配置解析（提取自 AgentBuilder，67 行）
- `Sources/AxionCLI/MCP/MCPServerRunner.swift` — Agent-as-MCP-Server 模式（使用 AgentBuilder.BuildResult）
- `Sources/AxionCLI/Memory/MemoryContextProvider.swift` — Memory 系统设计
- `Sources/AxionCLI/API/ApiRunner.swift` — HTTP API skill execution (runSkillAgent via AxionRuntime.executeSkill(); runAgent removed in Epic 26)
- `Sources/AxionCLI/Commands/SDKTerminalOutputHandler.swift` — SDKTerminalOutputHandler（SDKMessageOutputHandler 子类）
- `Sources/AxionCLI/Commands/SDKJSONOutputHandler.swift` — SDKJSONOutputHandler（SDKMessageOutputHandler 子类）

### 交互聊天模式（Epic 37）

`axion` 无参数进入交互式 coding agent REPL（`ChatCommand`），与 `axion run` 桌面自动化路径通过 `AgentMode` 枚举隔离。

**核心架构：**
- `AgentMode`：`.desktopAutomation`（`axion run`） vs `.codingAgent`（`axion` 交互模式）
- `BuildConfig.forChat()`：`maxTokens: 131072`、`mode: .codingAgent`、`includePlaywright: false`
- Coding agent 跳过 Helper 进程和 MCP 连接（`AgentBuilder.build()` 中 mode 分支）
- 权限通过 `canUseTool` 回调控制（非 SDK `permissionMode`），coding agent 路径 `permissionMode: .bypassPermissions`

**目录结构：**
```
Sources/AxionCLI/Chat/                    67 files (Epic 37+: 交互模式组件，纯函数 + DI 模式)
├── SlashCommand.swift                    # 斜杠命令枚举 + parse()
├── SlashCommandHandler.swift             # 命令处理逻辑（+ 2 个 extension：+CostStatus, +Diff）
├── SignalHandler.swift                   # SIGINT 信号处理（DispatchSource + SIG_IGN 模式）
├── BannerRenderer.swift                  # 启动横幅/提示符/退出消息格式化（含 PromptDisplayConfig）
├── SpinnerRenderer.swift                 # 进度 Spinner + ShimmerText 流动高光动画
├── ChatOutputFormatter.swift             # ~196 行核心 + ChatOutputFormatter+ContentSummary.swift
├── PermissionHandler.swift               # ~133 行核心 + PermissionHandler+Approval.swift
├── MultiLineInputReader.swift            # 多行输入（bracket paste + 反斜杠续行）
├── ContextManager.swift                  # 上下文用量管理（自动 compact + CompactionDisplayFormatter）
├── SessionResumeManager.swift            # 会话恢复（列出/格式化/恢复）
├── SessionWorkflowHandler.swift          # 会话工作流处理
├── InputQueue.swift                      # 输入队列管理
├── CJKInputHandler.swift                 # 中文输入修复（raw mode UTF-8 字符边界处理）
├── StreamingMarkdownFormatter.swift      # 流式 Markdown 渲染（斜体/列表/引用/删除线/任务列表/链接）
├── StreamingTableRenderer.swift          # 流式 Unicode 表格渲染（holdback 模式）
├── StreamingCodeBlockRenderer.swift      # 流式代码块渲染（diff 感知）
├── CodeSyntaxHighlighter.swift           # 16 语言轻量正则语法高亮
├── DiffFormatter.swift                   # /diff 命令 ANSI 彩色 unified diff
├── SystemEventRenderer.swift             # Codex 风格系统事件渲染
├── FileChangeTracker.swift               # 每轮文件操作追踪
├── TurnFileChangeTracker.swift           # 单轮文件变更收集
├── CompactionDisplayFormatter.swift      # 上下文压缩可视化（前后进度条对比）
├── ResponseSpeedTracker.swift            # TTFT + tok/s 响应速度追踪
├── ToolUsageTracker.swift                # 每工具调用次数统计
├── StatusDashboardFormatter.swift        # /status 富格式会话仪表盘
├── CommandHistoryStore.swift             # 跨会话命令历史持久化（~/.axion/history.jsonl）
├── SessionTranscriptLogger.swift         # 会话完整日志持久化（~/.axion/sessions/）
├── StartupTipProvider.swift              # 首次运行欢迎 + 功能发现提示
├── ShimmerText.swift                     # 余弦扫描流动高光动画
├── ClipboardService.swift                # /copy 命令（pbcopy/OSC 52/tmux）
├── DesktopNotifier.swift                 # macOS 桌面通知
├── GitBranchDetector.swift               # Git 分支 + working tree 状态检测
├── EscapeInterruptListener.swift         # Esc 键中断监听
├── ToolOutputFormatter.swift             # 工具输出格式化（shell 内联显示）
├── ToolCategoryFormatter.swift           # 工具分类格式化
├── KeyHintsFormatter.swift               # 按键提示格式化
├── TerminalHyperlinkFormatter.swift       # OSC 8 超链接格式化
├── TerminalTitleRenderer.swift           # 终端标题设置
├── Approval/                             # 工具权限审批组件
│   ├── ApprovalDecision.swift
│   ├── ApprovalRenderer.swift
│   ├── ApprovalDiffPreview.swift         # 彩色 diff 预览（Edit/Write 审批）
│   └── SessionAllowList.swift
├── Composer/                             # 输入编辑器组件（从 ChatComposer 分解）
│   ├── ChatComposer.swift               # 核心事件循环 + extension 文件
│   ├── ChatComposer+Continuation.swift   # 续行读取 + 降级路径
│   ├── ChatComposer+DisplayHelpers.swift # 多行感知重绘 + 光标定位
│   ├── ComposerDraft.swift              # 编辑状态快照
│   ├── ComposerMode.swift               # 模式枚举
│   ├── ComposerFileSearchHandling.swift  # @ 文件搜索模式
│   ├── ComposerSlashPopupHandling.swift  # / 斜杠补全弹出层
│   ├── ComposerHistoryNavigation.swift   # Up/Down 历史导航
│   ├── ComposerQuickActions.swift        # Ctrl+E/Q/G 快捷操作
│   ├── KeyEventReader.swift             # ~192 行 + KeyEventReader+EscapeParsing.swift
│   ├── KeyEvent.swift                   # 按键事件枚举
│   ├── SlashPopup.swift                 # Slash 弹出层数据模型
│   ├── SlashCommandContext.swift         # Slash 上下文
│   ├── ExternalEditorLauncher.swift     # Ctrl+G 外部编辑器
│   ├── FileSearcher.swift               # 文件搜索器
│   ├── FileSearchPopup.swift            # 文件搜索弹出层
└── Theme/                                # 终端主题和颜色
    ├── ChatTheme.swift
    ├── TerminalColorProfile.swift
    └── TranscriptRenderer.swift

Tests/AxionCLITests/Chat/                 ~10 test files（镜像源结构）
```

**关键文件：**
- `Sources/AxionCLI/Commands/ChatCommand.swift` — 交互 REPL 入口（`axion` 无参数默认命令）
- `Sources/AxionCLI/Services/AgentBuilder.swift` — `AgentMode` 枚举 + `BuildConfig.forChat()` + `buildCodingSystemPrompt()` + `loadClaudeMd()`
- `Prompts/coding-agent-system.md` — Coding agent 系统提示模板（非桌面自动化的 planner-system）

---

### 文件、存储与 App 管理（Epic 39）

Axion 的文件/存储/App 管理域 —— 安全、可解释、可回滚的 Mac 文件管家。所有破坏性操作先出计划、默认移废纸篓、可撤销。入口：`axion run` 与交互模式首发；Telegram 预留审批兼容。

**模块归属（严格分层）：**
- 模型在 `AxionCore/Models/Storage/`（`Storage/`、`Storage/App/`、`Storage/Approval/` 三组，纯 Codable，snake_case CodingKeys + `decodeIfPresent` 前向兼容）
- 服务在 `Sources/AxionCLI/Services/Storage/`（含 `App/`、`Approval/` 子目录）；Agent 工具在 `Sources/AxionCLI/Tools/`
- AxionHelper 不参与任何文件系统逻辑

**安全模型（契约层不可表达危险，不靠审查纪律）：**
- `StorageAction` 只有 `move` / `trash` / `createDirectory` / `uninstallApp` / `scanOnly` —— **没有 `delete` case**。永久删除在类型层即不可表达
- 破坏性操作经 `FileManager.trashItem`（移废纸篓），不使用 sudo；`removeItem` 仅用于撤销时清理新建的空目录
- 执行器纵深防御：plan 确认后、执行每个 item 前仍 re-validation（draft-first + per-item 复检），防 TOCTOU

**Agent 工具（6 个，经 `AgentBuilder` 在 `!dryrun` 时注册，仅 `desktopAutomation` 模式）：**
- 只读：`storage_scan`、`propose_storage_plan`、`scan_app_uninstall`
- 副作用：`execute_storage_plan`、`undo_storage_op`、`execute_app_uninstall`

**跨入口审批（SurfacePolicy）：**
- 审批动作 surface 无关：`approvePlan` / `approveItem` / `rejectItem` / `cancel`（`StorageApprovalAction`），三入口共享语义
- `SurfacePolicy.for(surface)` 表达入口差异：`run`/`chat` 全开放；`telegram` 保守（仅 `scanOnly`+`trash`，禁 typed 确认、禁高危数据）—— 高风险操作在远程入口更保守
- `StorageApprovalDecision` 为纯函数；副作用通过 `StorageApproving` protocol 注入（`RunApprovalCollector` / `ChatApprovalCollector` / `TelegramApprovalReserve` 各一实现）

**~/Library 排除/纳入张力（重要架构约束）：**
- `StorageExclusions.evaluate()` 会排除整个 `~/Library`（保护系统库）
- 但 `SupportDataScanService` 必须扫描 `~/Library/Application Support`、`Containers` 等 —— **刻意不调用通用排除**，改用 bundle-id 精确路径探测
- 规则：通用保护规则与定向功能冲突时，定向功能用自己的精确匹配，**不放宽通用规则**

**可撤销 manifest：**
- `StorageManifest` 记录每项 `StorageItemOutcome`；`undo_storage_op` 从废纸篓恢复（App 卸载复用同一 `restoreFromTrash`）

**卸载模式（`AppUninstallMode`，5 种）：** `scanOnly` / `uninstallAppOnly` / `uninstallWithSupportReview`（默认）/ `reviewSupportData` / `cleanApprovedSupportData`

---

## 执行循环

执行循环由 SDK Agent Loop 管理（非自建）。`AxionRuntime` 是 CLI 和 API 的统一执行入口（Epic 26），`AgentBuilder` 仅负责构建 `BuildResult`（agent + options + helper manager），不执行。

```
AxionRuntime.execute(buildConfig, runOverrides) → AgentBuilder.build() → agent.stream(task) → SDK Agent Loop
    │                                                              ↓
    ├── EventBus (from SDK)                              AgentEvents emitted
    │        ↓
    ├── EventHandlers (7 for CLI, 2 for API)
    │        ├── CostEventHandler
    │        ├── VisualDeltaHandler (CLI only)
    │        ├── SeatMonitorHandler (CLI only)
    │        ├── MemoryProcessingHandler (CLI only)
    │        ├── ReviewHandler (CLI only)
    │        ├── NotificationHandler (CLI only)
    │        └── TraceEventHandler
    │
    └── RunOrchestrator — still handles review/curator execution, takeover (skill fast-path moved to AxionRuntime in Epic 27)
```

- `maxSteps` 控制最大 turn 数（默认 20，fast mode 下 5）
- `cancelled` 由用户 Ctrl-C 触发（Takeover pause）
- `failed` 是不可恢复错误
- CLI registers 7 EventHandlers; API registers only CostEventHandler + TraceEventHandler

---

## 配置系统

分层配置（后者覆盖前者）：默认值 → `~/.axion/config.json` → 环境变量（`AXION_*`） → CLI 参数

- API Key 存储在 macOS Keychain（Security.framework），service: `"com.axion.cli"`，**不**在 config.json 中
- 环境变量 `AXION_API_KEY` 作为覆盖机制（CI/脚本场景）
- 环境变量 `AXION_AUTH_KEY` 作为 daemon 模式下 server 的 auth-key 来源（Epic 16）
- 环境变量 `AXION_BIN` 可覆盖 daemon plist 中的二进制路径（Epic 16）
- 环境变量 `AXION_TELEGRAM_BOT_TOKEN` 配置 TG bot token（Gateway 模式）
- 环境变量 `AXION_TELEGRAM_ALLOWED_USERS` 配置 TG 用户 ID 白名单（Gateway 模式）
- `axion setup` 写入配置，`axion doctor` 验证所有层级

**AxionConfig 默认值：**

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `model` | `"claude-sonnet-4-20250514"` | Anthropic 模型 |
| `maxSteps` | `20` | 单次运行最大步骤数 |
| `maxBatches` | `6` | 最大批次（plan-execute-verify 循环次数） |
| `maxReplanRetries` | `3` | 最大重规划次数 |
| `traceEnabled` | `true` | 默认开启 trace |
| `sharedSeatMode` | `true` | 默认开启共享座椅安全模式 |
| `gatewayEnabled` | `false` | 是否启用 gateway |
| `gatewayCuratorIdleHours` | `2.0` | Curator 空闲触发阈值（小时） |
| `gatewayCuratorIntervalHours` | `168.0` | Curator 间隔（小时，默认 7 天） |
| `gatewayTaskTimeoutMinutes` | `10.0` | 单任务超时（分钟） |
| `gatewayNotifyCuratorResults` | `false` | Curator 结果是否推送 TG |

---

## Trace 记录

- 格式：JSON Lines（每行一个事件）
- 路径：`~/.axion/runs/{runId}/trace.jsonl`
- 每个事件必须包含 `ts`（ISO8601）和 `event`（snake_case）
- Run ID 格式：`YYYYMMDD-{6位随机}`
- API Key **永远**不出现在 trace 中

---

## Daemon 模式与持久化（Epic 16）

### launchd Daemon / Gateway

- `axion daemon install --port 4242 [--auth-key KEY]` → launchd plist (`dev.axion.server`)，开机自启 + 崩溃自动重启
- `axion gateway install` → launchd plist (`dev.axion.gateway`)，daemon 超集（HTTP API + TG + 审查 + Curator）
- Gateway 核心文件：`GatewayCommand.swift`、`GatewayRunner.swift`(actor)、`TelegramAdapter.swift`(actor)、`ReviewScheduler.swift`(actor)、`CuratorScheduler.swift`(actor)
- TG 体验层（Epic 32）：`TGMessageFormatter`（三重降级）、`TGStreamingController`（Edit-based 流式推送）、`TGCommandRegistry`、`TGCommandRouter`、`TGInteractiveSessionStore`、`TGErrorSanitizer`、`TGModels`
- plist 配置：KeepAlive Crashed=true、ThrottleInterval=10、auth-key 通过 `AXION_AUTH_KEY` 环境变量传递
- 二进制路径解析：`AXION_BIN` > 当前进程路径 > `which axion`
- 使用 launchctl bootstrap/bootout（不使用已废弃的 load/unload）

### API 运行状态持久化

- 存储路径：`~/.axion/api-runs/{runId}/api-output.json`（原子覆写）+ `api-events.jsonl`（追加写入）
- 核心文件：`AxionRunPersistence.swift`（封装 SDK RunPersistenceService）、`AxionRunRecovery.swift`（启动恢复）
- 恢复状态映射：queued/running/resuming/userTakeover → failed；intervention_needed 保持不变；终态不干预
- SSE replay buffer miss → 自动从磁盘加载并缓存

---

## 安全规则

- 共享座椅模式（`sharedSeatMode`）下，前台操作需安全检查（`SafetyChecker`）
- Helper 仅通过 stdio 本地通信，不监听网络端口
- 截图不持久化到磁盘 — 内存中处理，用完即弃
- API Key 不出现在日志、trace、config.json 的任何位置
- Storage 域破坏性操作只移废纸篓（`FileManager.trashItem`），契约层无 `delete` 动作、不使用 sudo；所有操作先出计划 + 可撤销 manifest（Epic 39）

---

## Helper App 打包细节（Story 1.6）

- `LSUIElement=true`（Info.plist）— 无 Dock 图标，后台运行
- `LSMinimumSystemVersion=13.0`
- Entitlements 需要 `com.apple.security.automation.apple-events` 权限
- 需要 Apple Developer 签名
- Homebrew 安装路径：CLI → `bin/`，Helper.app → `libexec/axion/`

---

## Shifted Key 映射（Planner Prompt 需要）

Planner 的 system prompt 必须包含符号键到基础键的映射（`!` → `shift+"1"`, `@` → `shift+"2"`, ... 全部 21 对），告诉 LLM 如何生成 hotkey 参数。完整映射表参见 `src/planner.ts:41-63`（SHIFTED_KEY_MAP）。

---

## 数据流（完整链路）

### 主执行流（CLI）

```
RunCommand.parse() → AxionRuntime(eventBus:) → AgentBuilder.build() → agent.stream(task) → SDK Agent Loop
    │                                                    │
    ├── registerHandlers(7: Cost, VisualDelta, SeatMonitor, Memory, Review, Notification, Trace)
    ├── EventBus emit AgentEvents → 各 EventHandler 处理
    └── SDKTerminalOutputHandler → 实时输出到终端
```

### HTTP API Server（Epic 5+26）

`POST /v1/runs` → AxionAPI → AuthMiddleware → ConcurrencyLimiter → AxionRunTracker.submitRun() → AxionRuntime（仅注册 Cost + Trace handler）→ EventBusBridge → SSE 推送。崩溃恢复通过 AxionRunPersistence（原子 JSON）+ AxionRunRecovery 实现。

### MCP Server（Epic 6）

`axion mcp` → MCPServerRunner → AgentBuilder.build() → AgentMCPServer → tools/list + run_task + query_task_status。任务通过 TaskQueue 串行化。

### Gateway（D9/D10/D11）

Gateway = HTTP API + TelegramAdapter + ReviewScheduler + CuratorScheduler。TG 消息经白名单过滤后提交 TaskQueue（ConcurrencyLimiter=1），执行完毕后 ReviewScheduler 触发后台审查（工具白限 memory+skill），CuratorScheduler 在空闲时自动调度 IntelligentCurator。详见 architecture.md D9/D10/D11。

### 其他数据流（概要）

- **Takeover（Epic 7）**：Agent 调用 pause_for_human → SDK .paused 事件 → TakeoverIO 显示选项 → Enter/skip/abort
- **Fast Mode（Epic 7）**：maxSteps=5, maxTokens=2048, 跳过 discovery 和 screenshot 验证
- **录制（Epic 9）**：RecordCommand → Helper start_recording（CGEventTap listen-only）→ Ctrl-C stop → 保存 JSON
- **技能编译（Epic 9）**：RecordingCompiler.compile() → Event→SkillStep mapping + 自动参数检测 + 冗余优化
- **技能执行（Epic 9）**：SkillExecutor → resolveParams → MCP callTool → 失败重试一次
- **菜单栏 App（Epic 10）**：AxionBar → BackendHealthChecker → POST /v1/runs → SSE 订阅进度

---

## OpenAgentSDK 参考路径

SDK 本地参考路径：`/Users/nick/CascadeProjects/open-agent-sdk-swift`（用于查阅源码/运行 SDK 侧测试；Axion SPM resolve 使用 `Package.swift` 中的远程 URL 依赖）

| 需要参考的 SDK 能力 | SDK 路径 | 对应 Axion Story |
|-------------------|---------|----------------|
| Agent 创建和循环 | `Sources/OpenAgentSDK/OpenAgentSDK.swift` | Story 3.7 |
| 工具注册 | `Sources/OpenAgentSDK/Tools/` | Story 3.7 |
| MCP Client | `Examples/MCPIntegration/` | Story 3.1 |
| 流式输出 | `Examples/StreamingAgent/` | Story 3.5 |
| Hooks | `Examples/SessionsAndHooks/` | Story 3.3 |
| Session 管理 | `Examples/CompatSessions/` | Story 3.6 |
| 自定义 System Prompt | `Examples/CustomSystemPromptExample/` | Story 3.2 |
| AgentMCPServer | `Sources/OpenAgentSDK/MCP/AgentMCPServer.swift` | Story 6.1 |
| PauseForHumanTool | `Sources/OpenAgentSDK/Tools/Core/PauseForHumanTool.swift` | Story 7.1 |
| MemoryStore | `Sources/OpenAgentSDK/Memory/` | Story 4.1 |

---

## OpenClick 参考指南

Axion 基于 OpenClick（TypeScript + cua-driver）的思路重写为纯 Swift。**完整的参考矩阵和 Story 决策矩阵见 `_bmad-output/planning-artifacts/architecture.md` 的「OpenClick 参考指南」章节。**

OpenClick 本地路径：`/Users/nick/CascadeProjects/openclick`
SDK 本地路径：`/Users/nick/CascadeProjects/open-agent-sdk-swift`

**参考原则：** 适配而非照搬 — OpenClick 是 TypeScript + 外部二进制，Axion 是纯 Swift + 内嵌 MCP Server。架构决策以 architecture.md 为准。

---

## SafetyHook Tool Name 格式规则

SafetyHook 的 tool name 必须使用 **MCP-prefixed 格式**（如 `mcp__axion-helper__click`），而非 bare 格式（如 `click`）。SDK 通过 MCP 协议传递工具调用时，tool name 始终带有 `mcp__{server-name}__` 前缀。SafetyHook 的 `blockedToolNames` 必须匹配这个格式，否则 shared seat mode 的前台工具阻止完全失效。

**正确格式：** `"mcp__axion-helper__\(ToolNames.foregroundToolNames)"`
**错误格式：** `ToolNames.foregroundToolNames`（bare names）

**影响范围：** `AgentBuilder.buildSafetyHookRegistry()`、`MCPServerRunner.buildSafetyHookRegistry()`、以及任何新增 SafetyHook 注册的代码。
