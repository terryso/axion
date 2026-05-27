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
| AxionCLI 源码总行数 | ≤ 10,688（重构后） | NFR51 |
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
- 枚举使用 `String` 原始值以支持 Codable → `enum ConnectionStatus: String, Codable`
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

- 一个文件一个主类型 → `Skill.swift` 只定义 `Skill` 及其私有辅助
- Protocol 与实现分离 → `MCPClientProtocol` 在 `Protocols/`，`HelperMCPClientAdapter` 在 `Helper/`
- Extension 按功能分文件 → `AxionConfig+Codable.swift`, `Skill+Validation.swift`
- 测试镜像源结构 → `Tests/AxionCLITests/Services/RunLockServiceTests.swift`

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
├── HelperMCPServer.swift   # 39 lines (MCP server entry point)
├── ToolRegistrar.swift     # 19 lines (entry point, delegates to categories)
├── ToolTypes.swift         # 210 lines (shared types + ToolNames)
├── AppTools.swift          # 87 lines
├── WindowTools.swift       # 290 lines
├── MouseTools.swift        # 190 lines
├── KeyboardTools.swift     # 123 lines
├── ScreenshotTools.swift   # 82 lines
└── RecordingTools.swift    # 74 lines
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
3. **直接使用 `print()` 输出** — CLI 使用 `SDKTerminalOutputHandler`/`SDKJSONOutputHandler`（子类化 SDK 的 `SDKMessageOutputHandler`）统一格式化（AxionBar 使用 os.Logger）
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

## Memory 系统（Epic 4 + Epic 12）

Axion 的跨任务学习系统，基于证据驱动的知识生命周期管理。

**存储路径：** `~/.axion/memory/`
- 旧格式：`{domain}.json` — KnowledgeEntry 数组（SDK 兼容）
- 新格式：`{domain}-facts.json` — AppMemoryFact 数组（Epic 12+）

**目录结构：**
```
Sources/AxionCLI/Memory/             8 files, 2,107 lines (desktop-specific only)
├── AppMemoryFact.swift              # Epic 12: 模型（MemoryFactStatus/Source/Kind 枚举）+ normalizeFact + factId (djb2)
├── AppMemoryExtractor.swift         # Epic 4: 从 SDK 消息流提取 App 操作摘要（+ extractFacts() + classifyKind()）
├── AppProfileAnalyzer.swift         # Epic 4: 模式识别 + 高频路径 + 失败经验
├── FamiliarityTracker.swift         # Epic 4: 熟悉度追踪（>= 3 次成功标记 familiar）
├── MemoryContextProvider.swift      # Epic 4: Memory 上下文（Epic 12: 新增 buildFactMemoryContext 三类分类注入）
├── RunMemoryProcessor.swift         # Epic 21: 每次运行后处理 Memory（SDK FactStore 交互）
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
- `axion memory list` — 显示已积累 Memory（含状态图标 ✓/○/✗、分类标签、evidence_count）
- `axion memory clear --app <domain>` — 清除指定 App 的 Memory
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

Axion 作为 OpenAgentSDK 的旗舰参考实现，ScaffoldCLI 提供项目模板和脚手架 CLI。

### ScaffoldCLI（位于 OpenAgentSDK 仓库）

```
Sources/ScaffoldCLI/
├── ScaffoldCLI.swift              # ArgumentParser CLI 入口
├── TemplateGenerator.swift        # 文件生成逻辑
└── Templates/
    ├── BasicMainTemplate.swift    # basic 和 mcp-integration main.swift 模板
    ├── ToolTemplates.swift        # HelloWorld/Calculator/SystemInfo/Config 工具模板
    ├── HookTemplates.swift        # Hooks 安全策略示例模板
    ├── PromptTemplates.swift      # System prompt 和 .env.example 模板
    └── ReadmeTemplate.swift       # README.md 模板
```

**关键规则：**
- 模板代码只使用 SDK 公共 API，不引用 Axion 特有模块
- 工具数组类型使用 `ToolProtocol`（不是不存在的 `AnyTool`）
- 模板字符串中的 Swift 插值需要双重转义：`\\()` 在模板源码中 → `\()` 在生成输出中
- `defineTool` 有 4 种重载，模板应展示多种模式
- `AgentOptions` 的字段名是 `allowedTools`/`disallowedTools`（不是 `allowed`/`disallowed`）
- `canUseTool` 回调签名：`(ToolProtocol, Any, ToolContext) async -> CanUseToolResult?`

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
- `Sources/AxionCLI/Commands/SDKOutputHandlers.swift` — SDKTerminalOutputHandler / SDKJSONOutputHandler（SDKMessageOutputHandler 子类）

### SDK 开发者文档（位于 OpenAgentSDK 仓库）

| 文档 | 内容 |
|------|------|
| `docs/getting-started.md` | 5 分钟快速开始 |
| `docs/tool-development-guide.md` | defineTool 4 种模式 |
| `docs/mcp-integration-guide.md` | MCP 协议和集成 |
| `docs/agent-customization-guide.md` | AgentOptions、PermissionMode、Hooks |
| `docs/session-memory-guide.md` | Session 和 Memory 使用 |
| `docs/packaging-distribution-guide.md` | SPM/Homebrew/签名/AX 权限 |

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

## Daemon 模式与持久化（Epic 16）

### launchd Daemon

Axion server 可注册为 macOS 用户级 launchd 守护进程，实现开机自启和崩溃自动重启。

**CLI 命令：**
- `axion daemon install --host 127.0.0.1 --port 4242 [--auth-key KEY]` — 安装并启动守护进程
- `axion daemon status` — 查看 daemon 状态（running/stopped/not_installed）、PID、端口
- `axion daemon uninstall [--keep-logs]` — 停止并卸载守护进程

**核心文件：**
```
Sources/AxionCLI/Services/DaemonService.swift    # plist 生成、launchctl 调用、状态查询
Sources/AxionCLI/Commands/DaemonCommand.swift     # CLI 子命令入口
```

**plist 配置：**
- Label: `dev.axion.server`
- 路径: `~/Library/LaunchAgents/dev.axion.server.plist`
- RunAtLoad: true（开机自启）
- KeepAlive: Crashed=true（仅非零退出时重启）
- ThrottleInterval: 10（崩溃后 10 秒重启）
- auth-key 通过 EnvironmentVariables 的 `AXION_AUTH_KEY` 传递（不写入 ProgramArguments）
- 日志: `~/.axion/server.log` + `~/.axion/server.err.log`

**二进制路径解析优先级：** `AXION_BIN` 环境变量 > 当前进程路径 > `which axion`

**关键设计决策：**
- 使用 launchctl bootstrap/bootout（不使用已废弃的 load/unload）
- DaemonService 通过注入 `@Sendable` 闭包实现 launchctl 调用的可测试性
- ServerCommand authKey 优先级：CLI `--auth-key` > `AXION_AUTH_KEY` 环境变量 > nil

### API 运行状态持久化

daemon 模式下 server 崩溃/重启后，从磁盘恢复任务状态。

**存储路径：**
```
~/.axion/api-runs/                    # API 持久化目录（与 CLI trace 的 runs/ 分开）
├── {runId}/
│   ├── api-output.json               # TrackedRun JSON（每次状态更新原子覆写）
│   └── api-events.jsonl              # SSE 事件追加写入
```

**核心文件：**
```
Sources/AxionCLI/API/AxionRunPersistence.swift   # Epic 21: wraps SDK persistence for 磁盘读写
Sources/AxionCLI/API/AxionRunRecovery.swift      # Epic 21: wraps SDK recovery for 启动恢复
```

**恢复状态映射：**

| 恢复前状态 | 恢复后状态 | 说明 |
|-----------|-----------|------|
| queued/running/resuming/userTakeover | failed | 标记中断，error="server interrupted" |
| intervention_needed | intervention_needed | 保持不变，等待用户处理 |
| completed/failed/cancelled | 不变 | 已终态，无需干预 |

**关键设计决策：**
- AxionRunPersistence wraps SDK's RunPersistenceService (Sendable struct) with Axion-specific directory
- api-output.json 使用原子写入（write-to-tmp + rename）
- api-events.jsonl 使用追加写入（每行一个 JSON）
- 持久化失败不阻塞主流程（catch + warning 日志）
- SSE 订阅时内存 replay buffer miss → 自动从磁盘加载并缓存
- PersistedSSEEvent Codable wrapper 桥接 SSEEvent enum 到 JSONL

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
    ├── (skill path: /skill-name → AxionRuntime.executeSkill())  # [Epic 27] skill also through runtime
    │
    ▼
AxionRuntime(eventBus:)                     # [Epic 26] 统一执行入口
    ├── registerHandlers(7 handlers)         # Cost, VisualDelta, SeatMonitor, Memory, Review, Notification, Trace
    ├── startEventLoop()
    ├── runtime.execute(buildConfig, runOverrides)
    │       └── AgentBuilder.build() internally → agent.stream(task)
    │                │
    │                ├── LLM 规划 + 工具调用  # SDK Agent 自动编排
    │                │        └── ToolExecutor → MCP tools (Helper)
    │                │
    │                └── EventBus emit AgentEvents
    │                         ├── CostEventHandler → cost tracking
    │                         ├── VisualDeltaHandler → screenshot comparison
    │                         ├── SeatMonitorHandler → external activity detection
    │                         ├── MemoryProcessingHandler → memory extraction
    │                         ├── ReviewHandler → review scheduling
    │                         ├── NotificationHandler → desktop notification
    │                         └── TraceEventHandler → trace recording
    │
    ├── stopEventLoop()
    └── SDKTerminalOutputHandler             # 实时输出到终端
```

### HTTP API Server 数据流（Epic 5 + Epic 26）

```
外部系统 POST /v1/runs {"task": "打开计算器"}
    │
    ▼
ServerCommand (axion server --port 4242)      # Hummingbird Application
    │
    ├── AxionRunPersistence()                  # [Epic 21] 包装 SDK 持久化
    ├── AxionRunTracker(persistence:)          # [Epic 21] 包装 SDK RunTracker
    ├── AxionRunRecovery.recover()             # [Epic 21] 包装 SDK 恢复逻辑
    ├── EventBroadcaster(persistence:)         # SSE 事件广播 + 事件持久化
    │
    ▼
AxionAPI.registerRoutes()                     # 路由分发
    │
    ├──► AuthMiddleware (如启用 --auth-key)    # Bearer token 认证
    │
    ├──► ConcurrencyLimiter.tryAcquire()       # 并发槽位检查（SDK 提供）
    │
    ├──► AxionRunTracker.submitRun() → runId   # 生成任务 ID
    │        └──► AxionRunPersistence.persistRecordSafely()  # 持久化
    │
    ├──► 返回 HTTP 202 {"run_id": "...", "status": "running"}
    │
    └──► server.runHandler {                   # [Epic 26] 使用 AxionRuntime
            AxionRuntime(eventBus:)            # 创建 Runtime 实例
            ├── registerHandlers(cost + trace) # API 只注册 2 个 handler
            ├── EventBusBridge(eventBus:broadcaster:runId:)  # AgentEvents → SSE
            ├── bridge.start(onComplete:)      # 终端事件时更新 RunCoordinator
            ├── runtime.execute(buildConfig, runOverrides)    # 执行 agent
            └── 更新 RunCoordinator + SDK tracker + broadcaster.complete()
        }

GET /v1/runs/{runId}/events (SSE)
    │
    ▼
EventBroadcaster.subscribeWithReplay(runId)   # 订阅实时事件流
    ├── 内存 replay buffer 命中 → 直接重放
    └── 未命中 → 从 api-events.jsonl 磁盘加载
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
MCPServerRunner.run()                            # 编排器（使用 AgentBuilder.BuildResult）
    │
    ├──► AgentBuilder.build()                    # [Epic 21] 返回 BuildResult
    ├──► agent.assembleFullToolPool()            # 连接 Helper，获取工具列表
    ├──► RunTracker + TaskQueue                  # 任务追踪和串行化（SDK 组件）
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

---

## SafetyHook Tool Name 格式规则

SafetyHook 的 tool name 必须使用 **MCP-prefixed 格式**（如 `mcp__axion-helper__click`），而非 bare 格式（如 `click`）。SDK 通过 MCP 协议传递工具调用时，tool name 始终带有 `mcp__{server-name}__` 前缀。SafetyHook 的 `blockedToolNames` 必须匹配这个格式，否则 shared seat mode 的前台工具阻止完全失效。

**正确格式：** `"mcp__axion-helper__\(ToolNames.foregroundToolNames)"`
**错误格式：** `ToolNames.foregroundToolNames`（bare names）

**影响范围：** `AgentBuilder.buildSafetyHookRegistry()`、`MCPServerRunner.buildSafetyHookRegistry()`、以及任何新增 SafetyHook 注册的代码。
