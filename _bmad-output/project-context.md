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
| OpenAgentSDK | 本地依赖 (`../open-agent-sdk-swift`) | path-based SPM 依赖，并行开发 |
| swift-mcp | 2.0.0+（fork: terryso/swift-mcp） | Helper 端 MCP Server，AxionHelper 和 AxionCLI 均使用 |
| swift-argument-parser | 1.5.0+ | CLI 参数解析 |
| Hummingbird | 2.22.0+ | HTTP API Server 框架（Epic 5 新增） |
| swift-json-schema | 0.11.0+ | JSONSchemaBuilder，AxionHelper SelectorQuery 使用 |

**关键版本约束：**
- `swift-tools-version: 6.1` — 由 OpenAgentSDK 本地依赖决定（SDK 要求 6.1+）
- `macOS 14+` 是硬性要求，不能降低（AX API 变更、SMAppService）
- OpenAgentSDK 是本地 path 依赖，不是远程 URL — 修改 SDK 后 Axion 无需更新依赖声明
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

---

## 语言规则（Swift）

### 命名规范（三套规则，互不冲突）

**Swift 代码命名：**
- 类型（struct/enum/class/protocol）：PascalCase → `Plan`, `RunState`, `PlannerProtocol`
- 函数和方法：camelCase，动词开头 → `executeStep()`, `loadPrompt()`
- 属性和变量：camelCase → `maxSteps`, `currentPlan`
- 枚举 case：camelCase → `.done`, `.needsClarification`
- 协议：名词 + `Protocol` 后缀 → `PlannerProtocol`, `ExecutorProtocol`
- 文件名：与主类型同名 → `Plan.swift`, `RunState.swift`
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

```swift
// 1. 系统框架
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
- 枚举使用 `String` 原始值以支持 Codable → `enum RunState: String, Codable`
- 复杂枚举编码使用 `{type, value}` 模式（参见 `Value.swift`）
- Config 使用 camelCase JSON 键 — `CodingKeys` 不做转换，依赖 Swift 默认行为
- **部分 JSON 解码规范**：Codable 模型的 `init(from decoder:)` 使用 `decodeIfPresent` + `?? Self.default.xxx`，使缺失字段自动回退到默认值。新增字段时只需在此 init 中加一行，调用方无需修改。

### 错误处理

- 统一使用 `AxionError` 枚举，**不创建新的错误类型体系**
- 每个错误 case 必须提供 `MCPErrorPayload`（含 `error`/`message`/`suggestion` 三字段）
- MCP ToolResult 中的错误 JSON 必须是 `{"error": "...", "message": "...", "suggestion": "..."}`
- 使用 `toToolResultJSON()` 生成格式化的错误输出，`JSONEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]`

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

- 一个文件一个主类型 → `Plan.swift` 只定义 `Plan` 及其私有辅助
- Protocol 与实现分离 → `PlannerProtocol` 在 `Protocols/`，`LLMPlanner` 在 `Planner/`
- Extension 按功能分文件 → `RunState+Codable.swift`, `Plan+Validation.swift`
- 测试镜像源结构 → `Tests/AxionCLITests/Planner/LLMPlannerTests.swift`

### 四目标结构

| 目标 | 类型 | 入口 |
|------|------|------|
| AxionCore | library | 无（共享库） |
| AxionCLI | executable | `main.swift` + `@main struct AxionCLI: ParsableCommand` |
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

所有工具在 `ToolRegistrar.registerAll(to:)` 中统一注册，新工具必须：
1. 创建独立的 `@Tool` struct
2. 在 `ToolRegistrar.registerAll` 中添加注册行
3. 在 `AxionCore/Constants/ToolNames.swift` 中添加对应常量
4. 工具名必须是 snake_case（正则 `^[a-z][a-z0-9_]*$`）

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
- 通过 Protocol 注入 Mock（`PlannerProtocol`, `MCPClientProtocol` 等）
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
| `TraceRecorder` | Trace 事件写入 | 文件写入串行化 |
| `RunTracker` | HTTP API 任务状态管理 | 任务状态串行化（Epic 5） |
| `EventBroadcaster` | SSE 事件多客户端广播 | 订阅者和重放缓存串行化（Epic 5） |
| `ConcurrencyLimiter` | 并发任务槽位管理 | 并发计数和排队串行化（Epic 5） |
| `TaskQueue` | MCP Server 模式任务串行化 | agent.prompt() 调用串行化（Epic 6） |

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
3. **直接使用 `print()` 输出** — 必须通过 `OutputProtocol` 统一格式化（AxionBar 使用 os.Logger）
4. **MCP 通信中使用 camelCase JSON 字段** — MCP 参数必须是 snake_case
5. **硬编码 prompt 文本在 Swift 代码中** — prompt 放在 `Prompts/` 目录的 Markdown 文件中
6. **AxionCLI 直接 import AxionHelper** — 两者仅通过 MCP stdio 通信
7. **AxionBar import AxionCLI** — 两者仅通过 HTTP API 通信
8. **在 MCP 工具名中使用 camelCase 或 PascalCase** — 必须是 snake_case
9. **创建新的错误类型体系** — 统一使用 `AxionError` 枚举
10. **测试中硬编码字符串而非调用真实方法** — 测试必须调用被测方法/函数，不允许测试纯字面量（bogus test）
11. **JSON 输出使用手动字符串拼接** — 必须使用 JSONEncoder + Codable struct
12. **AxionBar 测试写入真实文件系统** — 必须使用临时目录

---

## Memory 系统（Epic 4）

Axion 的跨任务学习系统，基于 SDK FileBasedMemoryStore 实现。

**存储路径：** `~/.axion/memory/`（自定义路径，非 SDK 默认的 `~/.agent/memory/`）

**目录结构：**
```
Sources/AxionCLI/Memory/
├── AppMemoryExtractor.swift       # 从 SDK 消息流提取 App 操作摘要
├── MemoryCleanupService.swift     # 30 天过期清理
├── AppProfileAnalyzer.swift       # 模式识别 + 高频路径 + 失败经验
├── FamiliarityTracker.swift       # 熟悉度追踪（>= 3 次成功标记 familiar）
└── MemoryContextProvider.swift    # 构建 Planner prompt 中的 Memory 上下文
```

**CLI 命令：**
- `axion memory list` — 显示已积累 Memory 的 App 列表
- `axion memory clear --app <domain>` — 清除指定 App 的 Memory
- `axion run "任务" --no-memory` — 禁用 Memory 上下文注入

**关键设计决策：**
- Memory 操作失败不阻塞任务执行（do/catch 防护 + warning 日志）
- Memory 上下文注入到 system prompt 末尾（`buildFullSystemPrompt`），不在 user prompt
- Domain 使用 App bundle identifier（如 `com.apple.calculator`）
- KnowledgeEntry content 使用中文标签，状态标签用英文（success/failure）
- 熟悉 App 使用紧凑规划策略（减少 list_windows/get_window_state 验证步骤）

**SDK 依赖：**
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
- 文件名必须使用 `RecordCommand.sanitizeFileName()` 进行路径安全处理
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
- NSApp.setActivationPolicy(.accessory) 实现无 Dock 图标（AppDelegate）
- 所有 AxionBar 服务使用 @MainActor 隔离
- 窗口使用 NSPanel/NSWindow + SwiftUI hosting（非 WindowGroup）
- 全局热键使用 NSEvent.addGlobalMonitorForEvents（不使用 CGEvent Tap）
- 技能执行复用 RunTracker + EventBroadcaster SSE 管线
- 日志使用 os.Logger，AxionBar 不输出到 stdout
- 路径使用 FileManager + URL API，不拼接字符串

**API 模型命名约定：**
- Bar 前缀：`BarCreateRunRequest`、`BarRunStatusResponse`、`BarSkillSummary` 等
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
| `/v1/skills/{name}` | GET | 技能详情 |
| `/v1/skills/{name}/run` | POST | 执行技能 |

---

## 执行循环状态机

```
planning → executing → verifying → done/blocked/needsClarification
                ↓                        ↓
           replanning ← ─ ─ ─ ─ ─ ─ ─ ─ ┘
                                         ↓
                                   failed/cancelled
```

- `maxRetries` 控制最大重规划次数
- `cancelled` 由用户 Ctrl-C 触发
- `failed` 是不可恢复错误
- `RunContext` 贯穿整个循环，是 trace 文件的内存表示

---

## 配置系统

分层配置（后者覆盖前者）：默认值 → `~/.axion/config.json` → 环境变量（`AXION_*`） → CLI 参数

- API Key 存储在 macOS Keychain（Security.framework），service: `"com.axion.cli"`，**不**在 config.json 中
- 环境变量 `AXION_API_KEY` 作为覆盖机制（CI/脚本场景）
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

---

## Trace 记录

- 格式：JSON Lines（每行一个事件）
- 路径：`~/.axion/runs/{runId}/trace.jsonl`
- 每个事件必须包含 `ts`（ISO8601）和 `event`（snake_case）
- Run ID 格式：`YYYYMMDD-{6位随机}`
- API Key **永远**不出现在 trace 中

---

## 安全规则

- 共享座椅模式（`sharedSeatMode`）下，前台操作需安全检查（`SafetyChecker`）
- Helper 仅通过 stdio 本地通信，不监听网络端口
- 截图不持久化到磁盘 — 内存中处理，用完即弃
- API Key 不出现在日志、trace、config.json 的任何位置

---

## Helper App 打包细节（Story 1.6）

- `LSUIElement=true`（Info.plist）— 无 Dock 图标，后台运行
- `LSMinimumSystemVersion=13.0`
- Entitlements 需要 `com.apple.security.automation.apple-events` 权限
- 需要 Apple Developer 签名
- Homebrew 安装路径：CLI → `bin/`，Helper.app → `libexec/axion/`

---

## Shifted Key 映射（Planner Prompt 需要）

Planner 的 system prompt 必须包含符号键到基础键的映射，告诉 LLM 如何生成 hotkey 参数：

| 符号 | 基础键 |
|------|--------|
| `!` | `shift+"1"` |
| `@` | `shift+"2"` |
| `#` | `shift+"3"` |
| `$` | `shift+"4"` |
| `%` | `shift+"5"` |
| `^` | `shift+"6"` |
| `&` | `shift+"7"` |
| `*` | `shift+"8"` |
| `(` | `shift+"9"` |
| `)` | `shift+"0"` |
| `_` | `shift+"-"` |
| `+` | `shift+"="` |
| `{` | `shift+"["` |
| `}` | `shift+"]"` |
| `|` | `shift+"\"` |
| `:` | `shift+";"` |
| `"` | `shift+"'"` |
| `<` | `shift+","` |
| `>` | `shift+"."` |
| `?` | `shift+"/"` |
| `~` | `shift+"\`"` |

参考：`src/planner.ts:41-63`（SHIFTED_KEY_MAP）

---

## 数据流（完整链路）

```
用户输入 "axion run '打开计算器'"
    │
    ▼
RunCommand.parse()                          # ArgumentParser 解析
    │
    ▼
ConfigManager.load()                        # 分层加载配置（默认值 → config.json → env → CLI 参数）
    │
    ▼
HelperProcessManager.start()                # 启动 Helper 进程，建立 MCP stdio 管道
    │
    ▼
RunEngine.run()                             # 状态机开始
    │
    ├──► LLMPlanner.plan()                  # 加载 planner-system.md prompt → 调用 Anthropic API
    │        │
    │        ▼
    │    PlanParser.parse() → Plan          # 剥离 markdown 围栏，解析 JSON 为结构化 Plan
    │
    ├──► StepExecutor.execute(plan)         # 逐步执行
    │        │
    │        ▼ (每个 Step)
    │    PlaceholderResolver.resolve()      # 替换 $pid/$window_id 占位符
    │    SafetyChecker.check()              # 共享座椅模式安全检查
    │    MCP call → AxionHelper             # 通过 MCP JSON-RPC 调用 Helper 工具
    │
    ├──► TaskVerifier.verify()              # 截图 + AX tree 验证任务完成状态
    │        │
    │        ▼ (如果未完成)
    │    LLMPlanner.replan()                # 携带失败上下文重规划
    │
    └──► TerminalOutput.display()           # 实时输出到终端
         TraceRecorder.record()             # 追加 JSONL 事件到 trace 文件
```

### HTTP API Server 数据流（Epic 5）

```
外部系统 POST /v1/runs {"task": "打开计算器"}
    │
    ▼
ServerCommand (axion server --port 4242)      # Hummingbird Application
    │
    ▼
AxionAPI.registerRoutes()                     # 路由分发
    │
    ├──► AuthMiddleware (如启用 --auth-key)    # Bearer token 认证
    │
    ├──► ConcurrencyLimiter.tryAcquire()       # 并发槽位检查
    │
    ├──► RunTracker.submitRun() → runId        # 生成任务 ID
    │
    ├──► 返回 HTTP 202 {"run_id": "...", "status": "running"}
    │
    └──► Task.detached {                        # 后台异步执行
            AgentRunner.runAgent(...)           # 复用 Agent 执行逻辑
            RunTracker.updateRun(runId, result) # 更新任务状态
            EventBroadcaster.emit(runId, event) # SSE 事件推送
            ConcurrencyLimiter.release()        # 释放并发槽位
        }

GET /v1/runs/{runId}/events (SSE)
    │
    ▼
EventBroadcaster.subscribe(runId)             # 订阅实时事件流
    │
    ▼
ResponseBody(asyncSequence:)                   # Hummingbird 流式响应
```

### MCP Server 数据流（Epic 6）

```
外部 Agent (Claude Code) stdin/stdout MCP JSON-RPC
    │
    ▼
McpCommand (axion mcp)                           # CLI 子命令入口
    │
    ▼
MCPServerRunner.run()                            # 编排器
    │
    ├──► createAgent(options:)                   # 复用 AgentRunner 配置逻辑
    ├──► agent.assembleFullToolPool()            # 连接 Helper，获取工具列表
    ├──► RunTracker + TaskQueue                  # 任务追踪和串行化
    │
    └──► AgentMCPServer(name:"axion", tools:)    # SDK MCP server
             │
             ├── tools/list → [Helper 工具 + run_task + query_task_status]
             ├── tool_call "run_task" → TaskQueue.enqueue() → agent.prompt(task)
             └── tool_call "query_task_status" → RunTracker.getRun(runId)
```

### Takeover 数据流（Epic 7）

```
Agent Loop 执行中 → 工具调用受阻
    │
    ▼
Agent 调用 pause_for_human 工具 → SDK 内部 Agent.pause(reason:)
    │
    ▼
SDK 发出 .system(.paused, PausedData) SDKMessage
    │
    ▼
RunCommand stream 循环收到 .paused 消息
    │
    ├──► TakeoverIO.displayTakeoverPrompt()     # 显示阻塞原因和操作选项
    │         │
    │         ▼ (用户输入)
    │    TakeoverIO.readTakeoverAction()
    │         │
    │    ┌────┼────┐
    │    ▼    ▼    ▼
    │  Enter  skip  abort
    │    │    │     │
    │    ▼    ▼     ▼
    │ resume skip  interrupt()
    │ (context:   (context:  → .cancelled
    │  "用户已    "skip")
    │  完成手动
    │  操作")
    │    │    │
    │    ▼    ▼
    └──► Agent 继续执行
         │
    (超时 5 分钟)
         ▼
    SDK 发出 .system(.pausedTimeout) → 任务 failed
```

### Fast Mode 数据流（Epic 7）

```
axion run "打开计算器" --fast
    │
    ▼
RunCommand (fast=true)
    │
    ├──► buildFullSystemPrompt(fast: true)       # 追加 FAST mode 指令
    │    "生成最小步骤(1-3步)，跳过 discovery，不调用 screenshot 验证"
    │
    ├──► computeEffectiveMaxSteps(fast: true)    # min(userValue, 5)
    ├──► computeEffectiveMaxTokens(fast: true)   # 2048 (vs 标准 4096)
    │
    └──► createAgent + agent.stream(task)        # 标准 Agent Loop，参数调优
         │
         ▼ (执行结果)
    ┌────┼────┐
    ▼    ▼    ▼
  成功  失败  maxTurns
    │    │     │
    ▼    ▼     ▼
 "Fast mode  "建议去掉  "建议去掉
  完成。      --fast"   --fast"
  N步,耗时
  X秒。"
```

---

### 录制数据流（Epic 9）

```
axion record "打开计算器"
    │
    ▼
RecordCommand.run()
    │
    ├── ConfigManager.loadConfig()
    ├── HelperProcessManager.start()
    │
    ├── MCP call: start_recording → Helper
    │       │
    │       ▼
    │   EventRecorderService.startRecording()
    │       ├── CGEventTap.activate() (listen-only)
    │       ├── NSWorkspace.addObserver (app switch)
    │       └── 500ms timer: sampleWindowContext()
    │
    ├── "录制中... 按 Ctrl-C 结束录制"
    │
    └── SIGINT handler:
            │
            ├── MCP call: stop_recording → Helper
            │       → [RecordedEvent] + [WindowSnapshot]
            ├── Save ~/.axion/recordings/{name}.json
            └── Display recording summary
```

### 技能编译数据流（Epic 9）

```
axion skill compile open_calculator [--param url]
    │
    ▼
SkillCompileCommand.run()
    │
    ├── Load ~/.axion/recordings/open_calculator.json → Recording
    │
    ├── RecordingCompiler.compile(recording:paramNames:)
    │       ├── Event → SkillStep mapping (5 types)
    │       ├── Auto parameter detection (URL/path/long text)
    │       ├── Manual --param override
    │       └── Redundancy optimization (merge, dedup, remove)
    │
    ├── Save ~/.axion/skills/open_calculator.json → Skill JSON
    └── Display compilation summary
```

### 技能执行数据流（Epic 9）

```
axion skill run open_calculator --param url=https://example.com
    │
    ▼
SkillRunCommand.run()
    │
    ├── Load ~/.axion/skills/open_calculator.json → Skill
    ├── Validate required parameters
    │
    ├── HelperProcessManager.start()
    ├── HelperMCPClientAdapter(manager) → MCPClientProtocol
    │
    ├── SkillExecutor(client).execute(skill:paramValues:)
    │       │
    │       ▼ (每个 SkillStep)
    │   resolveParams()     — {{param}} → value/default
    │   toStringValueDict() — String → Value (.int() or .string())
    │   MCP callTool()      — 调用 Helper 执行操作
    │   Retry once on failure
    │
    ├── Update skill file (lastUsedAt, executionCount)
    ├── HelperProcessManager.stop()
    └── Display execution summary
```

### 菜单栏 App 数据流（Epic 10）

```
AxionBar 启动 (MenuBarExtra)
    │
    ├── StatusBarController.init()
    │       ├── BackendHealthChecker.startChecking()     # 5 秒轮询 GET /v1/health
    │       ├── ServerProcessManager.findAxionCLI()      # PATH + Homebrew + .build 查找
    │       ├── HotkeyConfigManager.load()               # ~/.axion/hotkeys.json
    │       └── GlobalHotkeyService.register()           # NSEvent 全局/本地监听
    │
    ├── MenuBarExtra → AxionBarMenuContent (SwiftUI)     # 菜单栏下拉菜单
    │
    ├── 用户点击 "快速执行"
    │       ├── QuickRunWindow (NSPanel + SwiftUI)
    │       ├── TaskSubmissionService.submit(task:)      # POST /v1/runs
    │       └── startRunMonitoring(runId:)               # SSE 订阅进度
    │               ├── SSEEventClient.connect()         # GET /v1/runs/{id}/events
    │               ├── 更新 currentStep/totalSteps
    │               └── run_completed → macOS 通知
    │
    ├── 用户点击 "技能列表" 菜单项
    │       ├── SkillService.fetchSkills()               # GET /v1/skills
    │       └── SkillService.runSkill(name:)             # POST /v1/skills/{name}/run
    │               └── 复用 startRunMonitoring()         # 技能执行也走 SSE 管线
    │
    ├── 全局热键触发
    │       ├── GlobalHotkeyService 匹配 modifiers + keyCode
    │       └── StatusBarController.runSkill() / submitTask()
    │
    └── 用户点击 "任务历史"
            ├── RunHistoryWindow (NSWindow + SwiftUI)
            ├── RunHistoryService.fetchHistory(limit: 20) # GET /v1/runs
            └── 点击历史任务 → TaskDetailPanel
```

---

## OpenAgentSDK 参考路径

SDK 本地路径：`/Users/nick/CascadeProjects/open-agent-sdk-swift`

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

Axion 基于 OpenClick（TypeScript + cua-driver）的思路重写为纯 Swift。实现 Story 时需要参考 OpenClick 源码提取实现细节，**参考矩阵见 `_bmad-output/planning-artifacts/architecture.md` 的「OpenClick 参考指南」章节**。

关键映射：

| Axion 模块 | 参考 OpenClick 文件 | 何时必须读取 |
|-----------|-------------------|------------|
| AxionHelper AX 操作 | `mac-app/Sources/RecorderCore/` | Story 1.3–1.5 |
| Helper MCP Server + 工具注册 | `src/executor.ts:160-180`（工具列表）、`mac-app/Sources/OpenclickHelper/` | Story 1.2 |
| Helper App 打包/签名 | `mac-app/OpenclickHelper.entitlements`、`mac-app/Sources/OpenclickHelper/Info.plist` | Story 1.6 |
| Planner Prompt 设计 | `src/planner.ts:119-167`（SYSTEM_GUIDANCE） | Story 3.2 |
| Planner Plan 解析 | `src/planner.ts:255+`（stripFences） | Story 3.2 |
| Executor 步骤执行 | `src/executor.ts:90-115`（ExecutorContext） | Story 3.3 |
| 安全策略 | `src/executor.ts:147-158`（BACKGROUND_SAFE_TOOLS） | Story 3.3 |
| Config/Keychain | `src/settings.ts` | Story 2.2 |
| Run Engine | `src/run.ts` | Story 3.6 |

OpenClick 本地路径：`/Users/nick/CascadeProjects/openclick`

**参考原则：** 适配而非照搬 — OpenClick 是 TypeScript + 外部二进制，Axion 是纯 Swift + 内嵌 MCP Server。架构决策以 architecture.md 为准。
