---
stepsCompleted:
  - step-01-init
  - step-02-context
  - step-03-starter
  - step-04-decisions
  - step-05-patterns
  - step-06-structure
  - step-07-validation
  - step-08-complete
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
documentCounts:
  prd: 1
  uxDesign: 0
  research: 0
  projectDocs: 0
  projectContext: 0
workflowType: 'architecture'
project_name: 'axion'
user_name: 'Nick'
date: '2026-05-08'
documentLanguage: 'zh-CN'
lastStep: 8
status: 'complete'
completedAt: '2026-05-08'
---

# 架构决策文档 — Axion

_本文档通过逐步发现协作构建。各部分随架构决策推进逐步追加。_

## 项目上下文分析

### 需求概览

**功能需求（41 项 FR，7 个领域）：**

| 领域 | FR 范围 | 数量 | 架构影响 |
|------|---------|------|----------|
| 安装与配置 | FR1–FR5 | 5 | 配置系统设计、Homebrew 分发、权限引导流程 |
| 任务执行 | FR6–FR10 | 5 | CLI 入口设计、执行模式（live/dry-run/foreground）、中断处理 |
| 规划引擎 | FR11–FR15 | 5 | Planner 模块独立设计、LLM 集成方式、plan 结构定义 |
| 本地执行 | FR16–FR20 | 5 | Executor 模块、MCP 调用管道、占位符解析、安全策略 |
| 任务验证 | FR21–FR23 | 3 | Verifier 模块、stopWhen 条件评估、任务状态机 |
| AxionHelper | FR24–FR32 | 9 | Helper App 独立架构、MCP Server、AX/Screenshot/KB/Mouse 服务 |
| 进度反馈与 SDK 集成 | FR33–FR41 | 9 | 流式输出管道、SDK 边界划分 |

**非功能需求（23 项 NFR，6 个维度）：**

| 维度 | NFR 范围 | 关键约束 |
|------|----------|----------|
| 性能 | NFR1–NFR4 | CLI 冷启动 < 2s，Helper 启动 < 500ms，单操作 < 200ms，CLI < 30MB，Helper < 20MB |
| 可靠性 | NFR5–NFR8 | Helper 故障隔离，LLM 调用重试（3次指数退避），Ctrl-C 正确清理 |
| 安全性 | NFR9–NFR12 | API Key 不泄露，共享座椅模式，Helper 仅本地通信，截图不持久化 |
| 可用性 | NFR13–NFR16 | 非技术用户 5 分钟上手，实时进度反馈，自然语言错误信息 |
| 可维护性 | NFR17–NFR20 | SDK 解耦，工具集可扩展，prompt 可配置，trace 文件可调试 |
| 兼容性 | NFR21–NFR23 | macOS 14+，Apple Silicon + Intel |

**规模与复杂度：**

- 主要领域：CLI 工具 + macOS Helper App（双进程架构）
- 复杂度等级：中高
- 预估架构组件：~12 个核心模块（CLI 侧 6 + Helper 侧 6）
- 代码规模目标：应用层 ~2000 行 Swift（不含 SDK）

### 技术约束与依赖

- **语言与运行时**：Swift 6.1+，静态编译，零 Node.js/Python 依赖
- **包管理**：SPM（Swift Package Manager）
- **关键依赖**：
  - OpenAgentSDK — Agent 引擎（Agent Loop、MCP Client、Tool Registry、Hooks、Streaming、Session）
  - mcp-swift-sdk — Helper 端 MCP Server 实现
  - ArgumentParser — CLI 参数解析
- **平台约束**：macOS 14+（Sonoma），无沙盒，需 Accessibility + 屏幕录制权限
- **分发约束**：Homebrew 安装，AxionHelper 必须 Apple Developer 签名
- **LLM 依赖**：需要 Anthropic API（Sonnet），规划引擎核心依赖

### 跨切关注点

1. **SDK vs 应用层边界** — 这是 Axion 项目的核心价值：每个模块必须明确归属，SDK 短板通过补 SDK 解决而非绕过
2. **MCP stdio 管道** — CLI ↔ Helper 的唯一通信通道，影响错误处理、超时、生命周期管理
3. **错误恢复与重规划** — Planner → Executor → Verifier 循环是核心执行模式，需要在架构层面统一处理
4. **安全策略** — 共享座椅模式下的前台操作限制，需贯穿 Executor 和 Helper 两层
5. **生命周期管理** — Helper 随 CLI 启停，Ctrl-C 必须正确清理，不留僵尸进程
6. **可观测性** — trace 文件记录每次运行的完整轨迹，用于调试和 SDK 改进反馈

## 项目脚手架评估

### 主要技术领域

macOS 桌面自动化 CLI 工具 + Helper App（Swift 原生）。无传统 Web/Mobile starter template 适用 — 技术栈已由 PRD 完全定义。

### 评估结论：自定义 SPM 项目结构

Axion 不使用任何现有 starter template，原因：

1. **非标准项目类型** — CLI + 签名 macOS Helper App 的组合无现成模板
2. **技术栈已锁定** — Swift、SPM、OpenAgentSDK、mcp-swift-sdk、ArgumentParser 均已确定
3. **SDK 依赖为本地包** — OpenAgentSDK 作为 SPM 本地依赖引入，需要自定义 Package.swift

### 选定项目结构

```
axion/
├── Package.swift                    # SPM 清单，定义 3 个可执行目标 + 1 个库目标
├── Sources/
│   ├── AxionCLI/                    # CLI 主程序（可执行目标）
│   │   ├── main.swift               # 入口，ArgumentParser 根命令
│   │   ├── Commands/                # 子命令：RunCommand, SetupCommand, DoctorCommand, ServerCommand, McpCommand, MemoryCommand
│   │   ├── Planner/                 # 规划引擎：LLM 调用、plan 解析、prompt 管理
│   │   ├── Executor/                # 执行引擎：步骤执行、MCP 调用、占位符解析
│   │   ├── Verifier/                # 验证引擎：截图/AX 验证、stopWhen 评估
│   │   ├── Config/                  # 配置管理：读写 ~/.axion/config.json
│   │   ├── Trace/                   # Trace 记录器：运行轨迹持久化
│   │   ├── Output/                  # 输出格式化：终端进度、JSON 输出
│   │   ├── Memory/                  # App Memory 系统（Epic 4）：跨任务学习
│   ├── AxionHelper/                 # Helper App（可执行目标，独立 macOS App）
│   │   ├── main.swift               # 入口，启动 MCP Server
│   │   ├── MCP/                     # MCP Server 实现：工具注册、JSON-RPC 处理
│   │   ├── Services/                # 系统服务：AXEngine, ScreenshotService,
│   │   │                            #   KeyboardService, MouseService, AppLauncher
│   │   └── Models/                  # Helper 专有模型：窗口状态、AX 元素等
│   └── AxionCore/                   # 共享库（library target）
│       ├── Models/                  # 共享数据模型：Plan, Step, ToolResult, RunState
│       ├── Protocols/               # 协议定义：PlannerProtocol, ExecutorProtocol
│       └── Constants/               # 共享常量：工具名、错误码、配置键
├── Tests/
│   ├── AxionCLITests/
│   ├── AxionHelperTests/
│   └── AxionCoreTests/
├── Prompts/                         # Planner 的 system prompt 文件（独立于代码）
│   ├── planner-system.md
│   └── verifier-system.md
└── Distribution/
    └── homebrew/                    # Homebrew formula 和打包脚本
```

### Package.swift 关键决策

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "axion",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AxionCLI", dependencies: [
            "AxionCore",
            .product(name: "OpenAgentSDK", package: "open-agent-sdk-swift"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .executableTarget(name: "AxionHelper", dependencies: [
            "AxionCore",
            .product(name: "MCP", package: "swift-sdk"),
        ]),
        .target(name: "AxionCore"),
    ],
    dependencies: [
        .package(path: "../open-agent-sdk-swift"),      // 本地 SDK 依赖
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ]
)
```

### 架构决策理由

| 决策 | 理由 |
|------|------|
| 三目标结构（CLI / Helper / Core） | CLI 和 Helper 是独立进程，共享 Core 模型 |
| Core 作为 library target | 避免 CLI 和 Helper 之间的代码重复（模型、协议、常量） |
| Prompts 独立目录 | PRD NFR19 要求 prompt 可独立修改，不硬编码 |
| 本地 SDK 依赖（path-based） | Axion 和 SDK 并行开发，需要即时反映 SDK 变更 |
| macOS 14 最低版本 | mcp-swift-sdk 0.1.5+ 要求 Sonoma |

**注：** 项目初始化（创建此 Package.swift 和目录结构）应为第一个实现 Story。

## 核心架构决策

### 决策优先级分析

**已由 PRD 确定（不再重新决策）：**

| 决策 | 选择 | 来源 |
|------|------|------|
| 编程语言 | Swift 6.1+ | PRD 技术架构概览 |
| 包管理 | SPM | PRD 实现考量 |
| 核心依赖 | OpenAgentSDK, mcp-swift-sdk, ArgumentParser | PRD SPM 依赖 |
| 目标平台 | macOS 14+ | PRD NFR21 |
| 进程架构 | CLI + Helper 双进程，MCP stdio 通信 | PRD 技术架构概览 |
| LLM 提供商 | Anthropic (Sonnet) | PRD 规划引擎 |
| 分发方式 | Homebrew | PRD FR1 |
| Helper 签名 | Apple Developer 签名 | PRD 系统集成要求 |

**关键决策（阻塞性）：**

| # | 决策 | 影响 |
|---|------|------|
| D1 | API Key 存储方式 | 安全性、用户体验 |
| D2 | Plan 数据模型设计 | Planner/Executor/Verifier 三个模块的接口契约 |
| D3 | 执行循环的状态机设计 | 任务状态转换、错误恢复、重规划触发 |
| D4 | 配置系统实现 | 所有模块的参数化控制 |

**重要决策（影响架构形态）：**

| # | 决策 | 影响 |
|---|------|------|
| D5 | 并发模型 | 性能（NFR1–NFR4）、代码复杂度 |
| D6 | Prompt 管理策略 | 可维护性（NFR19） |
| D7 | Trace 记录格式 | 可观测性、调试效率 |
| D8 | Helper 进程生命周期管理 | 可靠性（NFR5, NFR8） |

**延迟决策（MVP 后）— 已实施状态：**

| 决策 | 延迟理由 | 状态 |
|------|----------|------|
| HTTP API server 框架 | 成长功能，MVP 不需要 | ✅ 已实施（Epic 5，Hummingbird 2.x） |
| Memory 持久化方案 | 成长功能，MVP 不需要 | ✅ 已实施（Epic 4，SDK FileBasedMemoryStore） |
| MCP server 模式（供外部调用） | 成长功能，MVP 不需要 | ✅ 已实施（Epic 6，SDK AgentMCPServer） |

---

### D1: API Key 存储

**决策：macOS Keychain（Security.framework）**

**选项评估：**

| 方案 | 优点 | 缺点 |
|------|------|------|
| 明文 config.json | 简单 | 不安全，NFR9 风险 |
| macOS Keychain | 系统级加密，用户可见可管理 | 多一层 API 调用 |
| 环境变量 | 简单，CI 友好 | 持久化差，多 Shell 兼容问题 |

**理由：**
- 满足 NFR9（API Key 不出现在日志和 trace 中）
- 用户可在「钥匙串访问」中查看和删除
- `axion setup` 写入，`axion doctor` 验证，体验统一
- 环境变量 `AXION_API_KEY` 作为覆盖机制保留（CI/脚本场景）

**实现：** 使用 `SecItemAdd` / `SecItemCopyMatching`，封装为 `KeychainStore` 服务，CLI 层调用。

---

### D2: Plan 数据模型

**决策：结构化 Plan 模型（Codable JSON）**

```swift
// AxionCore/Models/Plan.swift

struct Plan: Codable {
    let id: UUID
    let task: String              // 原始用户任务描述
    let steps: [Step]
    let stopWhen: [StopCondition] // 任务完成条件
    let maxRetries: Int           // 最大重规划次数
}

struct Step: Codable {
    let index: Int
    let tool: String              // MCP 工具名：launch_app, click, type_text...
    let parameters: [String: Value] // 支持字符串、数字、$pid/$window_id 占位符
    let purpose: String           // LLM 生成的人类可读说明
    let expectedChange: String    // LLM 生成的预期变化描述
}

enum Value: Codable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case placeholder(String)      // $pid, $window_id 等
}

struct StopCondition: Codable {
    let type: StopType
    let description: String

    enum StopType: String, Codable {
        case done
        case blocked
        case needsClarification
    }
}
```

**理由：**
- Plan 是 Planner 输出 → Executor 输入的核心契约，必须强类型
- Codable 支持序列化到 trace 文件（NFR20）
- Value 枚举支持占位符解析（FR17），Executor 在运行时替换
- StopCondition 直接映射到 FR21–FR23 的验证逻辑

---

### D3: 执行循环状态机

**决策：显式状态机（RunState 枚举 + 状态转换规则）**

```
┌──────────┐
│ planning │ ──── LLM 生成 Plan
└────┬─────┘
     ▼
┌──────────┐
│executing │ ──── 逐步执行 Step[]
└────┬─────┘
     │
     ├── 全部步骤成功 ──→ ┌───────────┐
     │                   │ verifying │ ──── 截图 + AX tree 验证
     │                   └─────┬─────┘
     │                         │
     │           ┌─────────────┼─────────────┐
     │           ▼             ▼               ▼
     │     ┌────────┐   ┌─────────┐    ┌──────────────┐
     │     │  done  │   │ blocked │    │ needs_clarif │
     │     └────────┘   └────┬────┘    └──────────────┘
     │                       │
     │                       ▼
     │                  ┌──────────┐
     │                  │replanning│ ──── 携带失败上下文重新规划
     │                  └────┬─────┘
     │                       │
     │                       └──→ planning（循环，maxRetries 控制）
     │
     └── 步骤失败 ──→ replanning
```

```swift
enum RunState: String, Codable {
    case planning
    case executing
    case verifying
    case replanning
    case done
    case blocked
    case needsClarification
    case cancelled      // 用户 Ctrl-C
    case failed         // 不可恢复错误
}

struct RunContext {
    let runId: String
    var state: RunState
    var currentPlan: Plan?
    var executedSteps: [ExecutedStep]
    var replanCount: Int
    var error: AxionError?
}
```

**理由：**
- 显式状态机比隐式 if/else 更容易验证和调试
- RunContext 贯穿整个执行循环，是 trace 文件的内存表示
- 状态转换规则可以在编译时通过枚举穷举检查
- SDK 的 Agent Loop 管理外层 turn 循环，RunState 管理内层 plan-execute-verify 循环

---

### D4: 配置系统

**决策：分层配置（文件 → 环境变量 → CLI 参数，后者覆盖前者）**

```swift
struct AxionConfig: Codable {
    var apiKey: String?           // 从 Keychain 读取，不在此文件存储
    var model: String             // 默认 "claude-sonnet-4-20250514"
    var maxSteps: Int             // 默认 20
    var maxBatches: Int           // 默认 6
    var maxReplanRetries: Int     // 默认 3
    var traceEnabled: Bool        // 默认 true
    var sharedSeatMode: Bool      // 默认 true
}
```

| 优先级 | 来源 | 示例 |
|--------|------|------|
| 1（最低） | 默认值 | `model = "claude-sonnet-4-20250514"` |
| 2 | `~/.axion/config.json` | `{"maxSteps": 30}` |
| 3 | 环境变量 | `AXION_MODEL=claude-haiku-4-5-20251001` |
| 4（最高） | CLI 参数 | `--max-steps 10` |

**理由：**
- 12-factor app 原则适配 CLI 场景
- API Key 走 Keychain 不走文件（D1 已决定）
- `axion setup` 写 config.json，`axion doctor` 验证所有层级

---

### D5: 并发模型

**决策：Swift Structured Concurrency（async/await + Actor）**

| 场景 | 并发策略 |
|------|----------|
| LLM API 调用（Planner） | async/await，自带重试和取消支持 |
| MCP stdio 通信 | Actor 隔离的 `MCPConnection`，串行化 JSON-RPC |
| 流式输出 | AsyncStream<SDKMessage>（SDK 提供） |
| 截图/AX tree 获取 | async，不阻塞主循环 |
| Helper 进程监控 | Task + withTaskCancellationHandler |

**理由：**
- SDK 本身基于 Swift Concurrency 设计，Axion 应保持一致
- Actor 隔离 MCP 连接避免 JSON-RPC 的竞态条件
- Structured Concurrency 自动处理 Ctrl-C 取消传播（NFR8）

---

### D6: Prompt 管理策略

**决策：外部 Markdown 文件 + 运行时加载 + 模板变量注入**

```
Prompts/
├── planner-system.md     # Planner 的 system prompt
├── verifier-system.md    # Verifier 的 system prompt
└── replanner-context.md  # 重规划时的上下文模板
```

```swift
struct PromptTemplate {
    static func load(name: String, variables: [String: String]) async throws -> String
}
```

**理由：**
- 满足 NFR19（prompt 可独立修改，不硬编码）
- Markdown 格式方便在 PR review 中审查 prompt 变更
- 模板变量支持注入当前工具列表、屏幕状态等运行时上下文
- 与代码分离，prompt 工程师和 Swift 开发者可以独立工作

---

### D7: Trace 记录格式

**决策：JSON Lines（每行一个事件）**

```jsonl
{"ts":"2026-05-08T10:30:00Z","event":"run_start","task":"打开计算器，计算 17 乘以 23","runId":"20260508-a3f2k1"}
{"ts":"2026-05-08T10:30:01Z","event":"plan_created","steps":3}
{"ts":"2026-05-08T10:30:02Z","event":"step_start","index":0,"tool":"launch_app","purpose":"启动 Calculator"}
{"ts":"2026-05-08T10:30:02Z","event":"step_done","index":0,"result":"success"}
{"ts":"2026-05-08T10:30:05Z","event":"run_done","totalSteps":3,"duration_ms":8200,"replans":0}
```

**理由：**
- JSONL 支持流式追加，崩溃不丢失已写入的事件
- 可用 `jq` / `cat` 直接查看，无需解析完整 JSON
- 每行独立解析，方便过滤特定事件类型
- 文件路径：`~/.axion/runs/{runId}/trace.jsonl`

---

### D8: Helper 进程生命周期管理

**决策：`Process`（NSTask）启动 + `DispatchGroup` 同步 + Signal 传播**

```swift
actor HelperProcessManager {
    private var process: Process?

    func start() async throws          // 启动 Helper，建立 MCP 连接
    func stop() async                  // 优雅终止（SIGTERM → 3s → SIGKILL）
    func isRunning -> Bool             // 检查 Helper 是否存活

    // 注册 SIGINT handler，Ctrl-C 时传播到 Helper
    func setupSignalHandling()
}
```

**流程：**
1. CLI 首次需要 AX 操作时，`HelperProcessManager.start()` 启动 Helper
2. 通过 `Process.standardInput` / `standardOutput` 建立 stdio 管道
3. `DispatchGroup` 跟踪 Helper 进程存活状态
4. CLI 正常退出或 Ctrl-C 时，`stop()` 发送 SIGTERM，等待最多 3 秒，超时则 SIGKILL
5. 如果 Helper 意外崩溃，检测到后尝试重启一次

**理由：**
- 满足 NFR8（Ctrl-C 正确清理，不留僵尸进程）
- Helper 不监听网络端口，无端口占用问题（NFR11）
- Signal 传播确保 Helper 与 CLI 同步退出

---

### 决策影响分析

**实现顺序：**

1. **AxionCore**（共享模型） — Plan, Step, RunState, AxionConfig, AxionError
2. **AxionHelper**（MCP Server + AX 服务） — 可独立开发和测试
3. **Config 系统** — KeychainStore + ConfigManager
4. **Planner** — Prompt 加载 + LLM 调用 + Plan 解析
5. **Executor** — 步骤执行 + MCP 调用 + 占位符解析
6. **Verifier** — 截图/AX 验证 + StopCondition 评估
7. **执行循环** — RunState 状态机编排上述三个模块
8. **CLI 入口** — ArgumentParser 子命令 + 流式输出 + Trace 记录

**跨组件依赖：**

- Planner → AxionCore（Plan 模型）、Config（模型选择）、Helper（截图/AX 上下文）
- Executor → AxionCore（Step 模型）、Helper（MCP 工具调用）
- Verifier → AxionCore（StopCondition）、Helper（截图/AX tree）
- CLI → 所有模块（编排入口）
- Helper → AxionCore（共享模型）

## 实现模式与一致性规则

### 关键冲突点识别

AI Agent 在实现 Axion 时可能产生不一致的 6 个关键区域：

1. **命名风格** — Swift API Design Guidelines vs MCP 工具命名 vs JSON 字段命名
2. **模块组织** — 文件归属、Protocol 放置、Extension 组织
3. **错误处理** — 错误类型定义、MCP 错误返回格式、日志级别
4. **异步模式** — Actor 隔离边界、Task 取消传播、重试策略
5. **数据格式** — MCP JSON-RPC 字段命名、Trace 事件结构、Config 格式
6. **测试模式** — 测试命名、Mock 策略、MCP 通信测试

---

### 命名模式

**Swift 代码命名（遵循 Swift API Design Guidelines）：**

| 类别 | 规则 | 示例 |
|------|------|------|
| 类型（struct/enum/class/protocol） | PascalCase | `Plan`, `RunState`, `PlannerProtocol` |
| 函数和方法 | camelCase，动词开头 | `executeStep()`, `loadPrompt()` |
| 属性和变量 | camelCase | `maxSteps`, `currentPlan` |
| 枚举 case | camelCase | `.done`, `.needsClarification` |
| 协议 | 名词 + Protocol 后缀（能力型用 -able/-ible） | `PlannerProtocol`, `Configurable` |
| 文件名 | 与主类型同名 | `Plan.swift`, `RunState.swift` |
| 目录名 | PascalCase 复数 | `Commands/`, `Services/`, `Models/` |

**MCP 工具命名（跨进程通信，Helper 暴露给 CLI 的工具）：**

| 规则 | 示例 |
|------|------|
| snake_case | `launch_app`, `type_text`, `press_key` |
| 动词 + 名词 | `click`, `scroll`, `get_window_state` |
| 与 OpenClick 兼容 | 优先沿用 OpenClick 已有的工具命名 |

**JSON 字段命名（MCP JSON-RPC 通信和 Config 文件）：**

| 场景 | 规则 | 示例 |
|------|------|------|
| MCP 请求/响应参数 | snake_case | `{"app_name": "Calculator"}` |
| Config 文件 | camelCase（Swift Codable 默认） | `{"maxSteps": 20}` |
| Trace 事件 | snake_case | `{"event": "step_done"}` |

---

### 结构模式

**文件归属规则：**

| 规则 | 说明 |
|------|------|
| 一个文件一个主类型 | `Plan.swift` 只定义 `Plan` 及其私有辅助类型 |
| Protocol 与实现分离 | `PlannerProtocol` 在 `Protocols/`，`LLMPlanner` 在 `Planner/` |
| Extension 按功能分文件 | `RunState+Codable.swift`, `Plan+Validation.swift` |
| 测试镜像源结构 | `Tests/AxionCLITests/Planner/LLMPlannerTests.swift` |

**模块间依赖规则：**

```
AxionCore ← 不依赖任何其他 Axion 模块
AxionHelper ← 依赖 AxionCore
AxionCLI ← 依赖 AxionCore + OpenAgentSDK + ArgumentParser
AxionCLI 不能直接 import AxionHelper（通过 MCP 通信）
```

**import 顺序：**

```swift
// 1. 系统框架
import Foundation
import Security

// 2. 第三方依赖
import ArgumentParser
import OpenAgentSDK

// 3. 项目内部模块
import AxionCore
```

---

### 格式模式

**错误返回格式（MCP ToolResult）：**

```json
{
  "isError": true,
  "content": [{
    "type": "text",
    "text": "{\"error\": \"app_not_found\", \"message\": \"Calculator.app 未找到\", \"suggestion\": \"请确认应用已安装\"}"
  }]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `error` | String | 错误码，machine-readable |
| `message` | String | 人类可读的错误描述 |
| `suggestion` | String? | 修复建议（NFR14） |

**Trace 事件格式：**

```json
{"ts": "ISO8601", "event": "snake_case_event_name", ...payload}
```

所有事件必须包含 `ts`（ISO8601 时间戳）和 `event`（事件类型）。

**日期时间格式：**

| 场景 | 格式 |
|------|------|
| Trace 时间戳 | ISO8601 with timezone：`2026-05-08T10:30:00+08:00` |
| Run ID | `YYYYMMDD-{6位随机}`：`20260508-a3f2k1` |
| 配置文件 | 无日期字段 |

---

### 通信模式

**MCP 通信规则：**

| 规则 | 说明 |
|------|------|
| 请求超时 | 单个 MCP 工具调用超时 5 秒，截图和 AX tree 超时 10 秒 |
| 重试 | MCP 层不重试，由 Executor 层根据错误类型决定是否重试步骤 |
| 大 payload | 截图 base64 不超过 5MB，超过则压缩分辨率 |
| 心跳 | 不实现心跳，Helper 崩溃由进程监控检测 |

**日志级别：**

| 级别 | 用途 | 示例 |
|------|------|------|
| `debug` | 开发调试 | "MCP request: launch_app {app: Calculator}" |
| `info` | 用户可见的进度 | "步骤 2/5: 输入表达式" |
| `warning` | 可恢复的异常 | "AX 元素索引过期，自动刷新" |
| `error` | 操作失败 | "截图失败：权限未授予" |

- API Key 永远不出现在任何日志级别中（NFR9）
- 生产模式默认 `info` 级别，`--verbose` 开启 `debug`

---

### 异步模式

**Actor 隔离边界：**

| Actor | 职责 | 隔离原因 |
|-------|------|----------|
| `HelperProcessManager` | Helper 进程启停、MCP 连接 | 进程状态需要串行化访问 |
| `MCPConnection` | JSON-RPC 收发 | stdio 管道不能并发读写 |
| `TraceRecorder` | Trace 事件写入 | 文件写入串行化 |

**Task 取消传播：**

```swift
// 正确模式：使用 withTaskCancellationHandler
try await withTaskCancellationHandler {
    try await executor.execute(plan: plan)
} onCancel: {
    Task { await helperManager.stop() }
}
```

**重试策略：**

```swift
// 统一重试函数，用于 LLM API 调用
func withRetry<T>(maxAttempts: Int = 3, action: () async throws -> T) async throws -> T
```

- 仅用于 LLM API 调用（NFR6）和 transient MCP 错误
- 指数退避：1s → 2s → 4s
- 不用于业务逻辑错误（如"应用未找到"）

---

### 测试模式

**测试命名：**

```swift
// 格式：test_方法名_场景_预期结果
func test_executeStep_launchAppSuccess_returnsSuccess() async throws
func test_parsePlan_invalidJson_throwsParseError() async throws
func test_runStateTransition_fromExecutingToVerifying_isValid() async throws
```

**Mock 策略：**

| 被测模块 | Mock 对象 | 方式 |
|----------|-----------|------|
| Planner | LLM API | Mock AnthropicClient（Protocol 注入） |
| Executor | MCP 连接 | Mock PlannerProtocol + MCPClientProtocol |
| Verifier | Helper | Mock 截图/AX tree 返回值 |
| CLI 命令 | 全部内部模块 | 依赖注入 + Protocol Mock |

**不 Mock 的层：**
- AxionCore 模型（纯数据结构，无需 Mock）
- JSON 编解码（直接测 Codable round-trip）
- 配置文件读写（使用临时目录）

---

### 执行准则

**所有 AI Agent 必须：**

1. 遵循上述命名规则，不引入新风格
2. 新文件必须放在正确的目录中，不创建新的顶级目录
3. 错误必须使用 `AxionError` 枚举，不创建新的错误类型体系
4. MCP 工具参数使用 snake_case JSON，不使用 camelCase
5. 测试文件镜像源文件结构，测试命名遵循 `test_方法_场景_预期` 格式
6. import 顺序：系统 → 第三方 → 项目内部
7. AxionCLI 不直接 import AxionHelper，两者仅通过 MCP 通信

**反模式（必须避免）：**

- 在 AxionCore 中 import OpenAgentSDK（Core 是纯模型层）
- 在 Helper 中做 LLM 调用（Helper 只做 AX 操作）
- 直接使用 `print()` 输出（必须通过统一的 Output 格式化器）
- 在 MCP 通信中使用 camelCase JSON 字段
- 硬编码 prompt 文本在 Swift 代码中

## 项目结构与边界

### 完整项目目录结构

```
axion/
├── Package.swift                              # SPM 清单
├── Package.resolved                           # 锁文件（自动生成）
├── .gitignore
├── .swiftpm/                                  # Xcode/SPM 工作区（自动生成）
│
├── Sources/
│   ├── AxionCore/                             # 共享库目标
│   │   ├── Models/
│   │   │   ├── Plan.swift                     # D2: Plan 结构体
│   │   │   ├── Step.swift                     # D2: Step + Value 枚举
│   │   │   ├── StopCondition.swift            # D2: StopCondition + StopType
│   │   │   ├── RunState.swift                 # D3: RunState 枚举
│   │   │   ├── RunContext.swift               # D3: RunContext（运行时状态）
│   │   │   ├── ExecutedStep.swift             # 已执行步骤记录（含结果）
│   │   │   └── AxionConfig.swift              # D4: 配置模型
│   │   ├── Protocols/
│   │   │   ├── PlannerProtocol.swift          # Planner 接口
│   │   │   ├── ExecutorProtocol.swift         # Executor 接口
│   │   │   ├── VerifierProtocol.swift         # Verifier 接口
│   │   │   ├── MCPClientProtocol.swift        # MCP 客户端抽象
│   │   │   └── OutputProtocol.swift           # 输出格式化接口
│   │   ├── Errors/
│   │   │   └── AxionError.swift               # 统一错误类型
│   │   └── Constants/
│   │       ├── ToolNames.swift                # MCP 工具名常量
│   │       └── ConfigKeys.swift               # 配置键常量
│   │
│   ├── AxionCLI/                              # CLI 主程序（可执行目标）
│   │   ├── main.swift                         # 入口：ArgumentParser 根命令
│   │   ├── Commands/
│   │   │   ├── AxionCommand.swift             # 根命令（注册子命令）
│   │   │   ├── RunCommand.swift               # FR6–FR10: axion run
│   │   │   ├── SetupCommand.swift             # FR2: axion setup
│   │   │   ├── DoctorCommand.swift            # FR3: axion doctor
│   │   │   ├── ServerCommand.swift            # FR45–FR46: axion server（Epic 5）
│   │   │   ├── McpCommand.swift               # FR47: axion mcp（Epic 6）
│   │   │   ├── MemoryCommand.swift            # FR44: axion memory 命令组（Epic 4）
│   │   │   ├── MemoryListCommand.swift        # FR44: axion memory list
│   │   │   └── MemoryClearCommand.swift       # FR44: axion memory clear --app
│   │   ├── Planner/
│   │   │   ├── LLMPlanner.swift               # FR11–FR14: 调用 LLM 生成 Plan
│   │   │   ├── PlanParser.swift               # FR14–FR15: 解析 LLM 输出为 Plan
│   │   │   └── PromptBuilder.swift            # D6: 构建含上下文的 prompt
│   │   ├── Executor/
│   │   │   ├── StepExecutor.swift             # FR16–FR17: 执行单个 Step
│   │   │   ├── PlaceholderResolver.swift      # FR17: 解析 $pid/$window_id
│   │   │   └── SafetyChecker.swift            # FR20: 共享座椅安全策略
│   │   ├── Verifier/
│   │   │   ├── TaskVerifier.swift             # FR21: 验证任务完成状态
│   │   │   └── StopConditionEvaluator.swift   # FR22: 评估 stopWhen 条件
│   │   ├── Engine/
│   │   │   └── RunEngine.swift                # D3: 状态机编排 plan→exec→verify 循环
│   │   ├── Config/
│   │   │   ├── ConfigManager.swift            # FR4–FR5: 分层配置加载
│   │   │   └── KeychainStore.swift            # D1: API Key 安全存储
│   │   ├── Helper/
│   │   │   └── HelperProcessManager.swift     # D8: Helper 进程启停管理
│   │   ├── Trace/
│   │   │   └── TraceRecorder.swift            # D7/NFR20: JSONL trace 记录
│   │   └── Output/
│   │       ├── TerminalOutput.swift            # FR33–FR34: 终端实时输出
│   │       └── JSONOutput.swift               # FR35: JSON 结构化输出
│   │   ├── Memory/                              # Epic 4: App Memory 系统
│   │   │   ├── AppMemoryExtractor.swift        # 从消息流提取 App 操作摘要
│   │   │   ├── MemoryCleanupService.swift      # 30 天过期清理
│   │   │   ├── AppProfileAnalyzer.swift        # 模式识别 + 高频路径 + 失败经验
│   │   │   ├── FamiliarityTracker.swift        # 熟悉度追踪（>= 3 次成功标记 familiar）
│   │   │   └── MemoryContextProvider.swift      # 构建 Planner Memory 上下文
│   │   ├── API/                                # Epic 5: HTTP API Server
│   │   │   ├── AgentRunner.swift              # Agent 执行封装
│   │   │   ├── RunTracker.swift               # 任务状态追踪
│   │   │   ├── AxionAPI.swift                 # Hummingbird 路由注册
│   │   │   ├── EventBroadcaster.swift         # SSE 事件广播
│   │   │   ├── AuthMiddleware.swift           # Bearer token 认证
│   │   │   ├── ConcurrencyLimiter.swift       # 并发槽位管理
│   │   │   └── Models/APITypes.swift          # API 请求/响应模型
│   │   ├── MCP/                                # Epic 6: MCP Server Mode
│   │   │   ├── MCPServerRunner.swift          # MCP 编排器
│   │   │   ├── RunTaskTool.swift              # run_task 工具实现
│   │   │   ├── QueryTaskStatusTool.swift      # query_task_status 工具实现
│   │   │   └── TaskQueue.swift                # 任务串行化 Actor
│   │
│   └── AxionHelper/                           # Helper App（可执行目标）
│       ├── main.swift                         # 入口：启动 MCP Server
│       ├── MCP/
│       │   ├── HelperMCPServer.swift          # FR31: MCP stdio server 主循环
│       │   └── ToolRegistrar.swift            # FR32: 注册所有桌面操作工具
│       ├── Services/
│       │   ├── AccessibilityEngine.swift      # FR25–FR29: AX API 封装
│       │   ├── ScreenshotService.swift         # FR28: 截图服务
│       │   ├── KeyboardService.swift           # FR27: 键盘输入
│       │   ├── MouseService.swift              # FR26: 鼠标操作
│       │   ├── AppLauncher.swift              # FR24: 应用启停管理
│       │   └── URLOpener.swift                # FR30: 打开 URL
│       └── Models/
│           ├── WindowState.swift              # 窗口状态模型
│           └── AXElement.swift                # AX 元素模型
│
│   ├── AxionBar/                              # Epic 10: 菜单栏 App（独立 executable）
│       ├── App.swift                          # @main, MenuBarExtra 生命周期
│       ├── StatusBarController.swift          # NSStatusItem + ConnectionState
│       ├── Models/
│       │   ├── ConnectionState.swift          # .disconnected / .connected / .running
│       │   ├── HealthCheckResponse.swift
│       │   ├── RunModels.swift                # Bar 前缀 API 模型
│       │   ├── SkillModels.swift
│       │   └── HotkeyConfig.swift
│       ├── Services/
│       │   ├── BackendHealthChecker.swift     # 5 秒轮询 GET /v1/health
│       │   ├── ServerProcessManager.swift     # Process 启动/停止 axion server
│       │   ├── TaskSubmissionService.swift
│       │   ├── SSEEventClient.swift           # URLSession bytes stream SSE
│       │   ├── RunHistoryService.swift
│       │   ├── SkillService.swift
│       │   └── GlobalHotkeyService.swift      # NSEvent 全局热键
│       ├── Views/
│       │   ├── QuickRunWindow.swift
│       │   ├── TaskDetailPanel.swift
│       │   ├── RunHistoryWindow.swift
│       │   └── SettingsWindow.swift
│       └── MenuBar/
│           └── MenuBarBuilder.swift
│
├── Prompts/                                   # D6: 外部 Prompt 文件
│   ├── planner-system.md                      # Planner system prompt
│   ├── verifier-system.md                     # Verifier system prompt
│   └── replanner-context.md                   # 重规划上下文模板
│
├── Tests/
│   ├── AxionCoreTests/
│   │   ├── PlanTests.swift
│   │   ├── RunStateTests.swift
│   │   ├── AxionConfigTests.swift
│   │   └── AxionErrorTests.swift
│   ├── AxionCLITests/
│   │   ├── Commands/
│   │   │   ├── RunCommandTests.swift
│   │   │   ├── SetupCommandTests.swift
│   │   │   └── DoctorCommandTests.swift
│   │   ├── Planner/
│   │   │   ├── LLMPlannerTests.swift
│   │   │   └── PlanParserTests.swift
│   │   ├── Executor/
│   │   │   ├── StepExecutorTests.swift
│   │   │   └── PlaceholderResolverTests.swift
│   │   ├── Verifier/
│   │   │   ├── TaskVerifierTests.swift
│   │   │   └── StopConditionEvaluatorTests.swift
│   │   └── Engine/
│   │       └── RunEngineTests.swift
│   │   ├── Memory/                                # Epic 4: Memory 测试
│   │   │   ├── AppMemoryExtractorTests.swift
│   │   │   ├── MemoryCleanupServiceTests.swift
│   │   │   ├── AppProfileAnalyzerTests.swift
│   │   │   ├── FamiliarityTrackerTests.swift
│   │   │   └── MemoryContextProviderTests.swift
│   ├── AxionBarTests/                                # Epic 10: 菜单栏 App 测试
│   │   ├── Models/
│   │   │   ├── RunModelsTests.swift
│   │   │   ├── SkillModelsTests.swift
│   │   │   └── HotkeyConfigTests.swift
│   │   ├── Services/
│   │   │   ├── BackendHealthCheckerTests.swift
│   │   │   ├── ServerProcessManagerTests.swift
│   │   │   ├── TaskSubmissionServiceTests.swift
│   │   │   ├── SSEEventClientTests.swift
│   │   │   ├── RunHistoryServiceTests.swift
│   │   │   ├── SkillServiceTests.swift
│   │   │   └── GlobalHotkeyServiceTests.swift
│   │   ├── StatusBar/
│   │   │   └── StatusBarControllerTests.swift
│   │   └── MenuBar/
│   │       └── MenuBarBuilderTests.swift
│   └── AxionHelperTests/
│       ├── Services/
│       │   ├── AccessibilityEngineTests.swift
│       │   ├── ScreenshotServiceTests.swift
│       │   └── AppLauncherTests.swift
│       └── MCP/
│           └── HelperMCPServerTests.swift
│
└── Distribution/
    └── homebrew/
        ├── axion.rb.template                   # Homebrew formula 模板
        └── build-release.sh                    # 构建和打包脚本
```

### 架构边界

**进程边界（最严格的边界）：**

```
┌─────────────────────────────────────────────────────────┐
│ AxionCLI 进程                                           │
│                                                         │
│  AxionCLI → AxionCore（直接 import）                      │
│  AxionCLI → OpenAgentSDK（直接 import）                    │
│  AxionCLI → ArgumentParser（直接 import）                  │
│  AxionCLI ↛ AxionHelper（禁止直接 import）                 │
│                                                         │
│  与 Helper 通信：MCP stdio（stdin/stdout JSON-RPC）       │
│  与 AxionBar 通信：HTTP API（localhost:4242）              │
├─────────────────────────────────────────────────────────┤
│ AxionHelper 进程                                        │
│                                                         │
│  AxionHelper → AxionCore（直接 import）                   │
│  AxionHelper → mcp-swift-sdk（直接 import）               │
│  AxionHelper ↛ OpenAgentSDK（不需要）                     │
│  AxionHelper ↛ AxionCLI（禁止）                          │
├─────────────────────────────────────────────────────────┤
│ AxionBar 进程（Epic 10 — 独立 macOS App）                │
│                                                         │
│  AxionBar → AxionCore（直接 import）                      │
│  AxionBar → SwiftUI + AppKit（系统框架）                  │
│  AxionBar ↛ AxionCLI（禁止 — 通过 HTTP API 通信）         │
│  AxionBar ↛ OpenAgentSDK（不需要）                        │
│                                                         │
│  与 CLI 通信：HTTP API（localhost:4242 REST + SSE）       │
└─────────────────────────────────────────────────────────┘
```

**模块依赖规则：**

```
AxionCore ← 无外部依赖（纯模型 + 协议 + 常量）
    ↑
AxionCLI ← OpenAgentSDK + ArgumentParser + Hummingbird
    ↑ (MCP stdio, 非 import)
AxionHelper ← mcp-swift-sdk
    ↑ (HTTP API, 非 import)
AxionBar ← SwiftUI + AppKit（独立 macOS App）
```

### 需求到结构的映射

**FR 到文件的映射：**

| FR | 文件 | 说明 |
|----|------|------|
| FR1 | Distribution/homebrew/axion.rb.template | Homebrew 安装 |
| FR2 | SetupCommand.swift + KeychainStore.swift | 首次配置 |
| FR3 | DoctorCommand.swift | 环境检查 |
| FR4–FR5 | ConfigManager.swift | 配置加载 |
| FR6–FR10 | RunCommand.swift + RunEngine.swift | 任务执行入口 |
| FR11–FR15 | LLMPlanner.swift + PlanParser.swift | 规划引擎 |
| FR16–FR17 | StepExecutor.swift + PlaceholderResolver.swift | 步骤执行 |
| FR18 | StepExecutor.swift | 自动刷新窗口状态 |
| FR19 | SafetyChecker.swift | 共享座椅安全 |
| FR20 | SafetyChecker.swift | 前台操作限制 |
| FR21–FR23 | TaskVerifier.swift + StopConditionEvaluator.swift | 任务验证 |
| FR24 | AppLauncher.swift | 应用管理 |
| FR25–FR29 | AccessibilityEngine.swift + ScreenshotService.swift 等 | 桌面操作 |
| FR30 | URLOpener.swift | URL 打开 |
| FR31–FR32 | HelperMCPServer.swift + ToolRegistrar.swift | MCP Server |
| FR33–FR35 | TerminalOutput.swift + JSONOutput.swift | 输出格式 |
| FR36–FR40 | RunEngine.swift + SDK 集成 | SDK 使用 |
| FR41 | 本文档 + SDK 边界文档 | 边界记录 |
| FR42 | AppMemoryExtractor.swift + MemoryCleanupService.swift | Memory 提取（Epic 4） |
| FR43 | AppProfileAnalyzer.swift + MemoryContextProvider.swift | Memory 增强规划（Epic 4） |
| FR44 | MemoryCommand.swift + MemoryListCommand.swift + MemoryClearCommand.swift | Memory 管理 CLI（Epic 4） |

**跨切关注点到位置的映射：**

| 关注点 | 位置 | 说明 |
|--------|------|------|
| 错误处理 | AxionCore/Errors/AxionError.swift | 统一错误类型，所有模块使用 |
| 配置管理 | AxionCLI/Config/ | 分层配置 + Keychain |
| 进程生命周期 | AxionCLI/Helper/HelperProcessManager.swift | Helper 启停 + 信号传播 |
| 安全策略 | AxionCLI/Executor/SafetyChecker.swift | 共享座椅模式 |
| 可观测性 | AxionCLI/Trace/TraceRecorder.swift | JSONL trace |
| 输出格式 | AxionCLI/Output/ | 终端 + JSON 双输出 |
| Memory 系统 | AxionCLI/Memory/ | App 操作经验积累 + Planner 上下文注入 |

### 集成点

**内部通信：**

| 通信路径 | 协议 | 方向 |
|----------|------|------|
| CLI → Helper | MCP stdio JSON-RPC | 请求/响应 |
| CLI → Anthropic API | HTTPS REST | 请求/响应 |
| CLI → Keychain | Security.framework API | 读写 |
| CLI → Config 文件 | FileManager + Codable | 读写 |
| CLI → Trace 文件 | FileManager + JSONL 追加 | 只写 |

**外部集成：**

| 集成点 | 方式 | 依赖 |
|--------|------|------|
| Anthropic API | HTTPS REST（via SDK） | API Key |
| macOS Accessibility | AX API（via Helper） | 权限授权 |
| macOS 截图 | CGWindowListCreateImage（via Helper） | 屏幕录制权限 |
| Homebrew | Ruby formula | 构建产物 |

### 数据流

```
用户输入 "axion run '打开计算器'"
    │
    ▼
RunCommand.parse()                          # ArgumentParser 解析
    │
    ▼
ConfigManager.load()                        # 分层加载配置
    │
    ▼
HelperProcessManager.start()                # 启动 Helper
    │
    ▼
RunEngine.run()                             # 状态机开始
    │
    ├──► LLMPlanner.plan()                  # 调用 Anthropic API
    │        │
    │        ▼
    │    PlanParser.parse() → Plan          # 解析为结构化 Plan
    │
    ├──► StepExecutor.execute(plan)         # 逐步执行
    │        │
    │        ▼ (每个 Step)
    │    HelperMCPServer.tool_call()        # MCP JSON-RPC → Helper
    │        │
    │        ▼
    │    AX/Screenshot/KB/Mouse Service     # Helper 执行桌面操作
    │
    ├──► TaskVerifier.verify()              # 验证完成状态
    │        │
    │        ▼ (如果未完成)
    │    LLMPlanner.replan()                # 携带失败上下文重规划
    │
    └──► TerminalOutput.display()           # 实时输出到终端
         TraceRecorder.record()             # 记录到 trace 文件
```

## 架构验证结果

### 一致性验证

**决策兼容性：** 全部通过

| 检查项 | 结果 | 说明 |
|--------|------|------|
| Swift 6.1+ 与所有依赖兼容 | ✅ | OpenAgentSDK 要求 6.1、mcp-swift-sdk 和 ArgumentParser 均支持 |
| macOS 14+ 与所有依赖兼容 | ✅ | mcp-swift-sdk 0.1.5+、OpenAgentSDK、ArgumentParser 均支持 |
| Actor 并发与 MCP stdio | ✅ | Actor 隔离串行化 JSON-RPC 读写，无竞态 |
| Keychain + Security.framework | ✅ | macOS 原生 API，无需额外依赖 |
| JSONL trace + FileManager | ✅ | 简单文件追加，无额外依赖 |
| OpenAgentSDK (path) + mcp-swift-sdk (URL) | ✅ | 两种 SPM 依赖来源可共存 |

**模式一致性：** 全部通过

- 命名约定：Swift 代码 PascalCase/camelCase，MCP 工具 snake_case，Trace 事件 snake_case — 三套规则互不冲突
- 文件结构：三目标分离（CLI/Helper/Core）与进程边界一致
- 错误处理：统一 AxionError 枚举，MCP 错误 JSON 格式与 AxionError 可互转

**结构对齐：** 全部通过

- 项目结构支持所有架构决策
- 进程边界在目录结构中体现（AxionCLI ≠ AxionHelper）
- 依赖方向：Core ← CLI, Core ← Helper，无循环依赖

### 需求覆盖验证

**功能需求覆盖（41/41 FR — 100%）：**

| FR 范围 | 数量 | 覆盖状态 | 关键文件 |
|---------|------|----------|----------|
| FR1–FR5 安装与配置 | 5 | ✅ 全覆盖 | SetupCommand, DoctorCommand, ConfigManager, KeychainStore |
| FR6–FR10 任务执行 | 5 | ✅ 全覆盖 | RunCommand, RunEngine |
| FR11–FR15 规划引擎 | 5 | ✅ 全覆盖 | LLMPlanner, PlanParser, PromptBuilder |
| FR16–FR20 本地执行 | 5 | ✅ 全覆盖 | StepExecutor, PlaceholderResolver, SafetyChecker |
| FR21–FR23 任务验证 | 3 | ✅ 全覆盖 | TaskVerifier, StopConditionEvaluator |
| FR24–FR32 AxionHelper | 9 | ✅ 全覆盖 | AppLauncher, AccessibilityEngine, ScreenshotService, KeyboardService, MouseService, URLOpener, HelperMCPServer |
| FR33–FR41 进度与 SDK | 9 | ✅ 全覆盖 | TerminalOutput, JSONOutput, RunEngine (SDK 集成) |

**非功能需求覆盖（23/23 NFR — 100%）：**

| NFR 范围 | 数量 | 覆盖状态 |
|---------|------|----------|
| NFR1–NFR4 性能 | 4 | ✅ 静态编译 + Actor 隔离 + Helper 进程隔离 |
| NFR5–NFR8 可靠性 | 4 | ✅ Process 隔离 + withRetry + Trace 记录 + Signal 清理 |
| NFR9–NFR12 安全性 | 4 | ✅ Keychain + SafetyChecker + stdio-only + 内存截图 |
| NFR13–NFR16 可用性 | 4 | ✅ SetupCommand + DoctorCommand + TerminalOutput + AxionError |
| NFR17–NFR20 可维护性 | 4 | ✅ SPM 解耦 + ToolRegistrar + 外部 Prompt + JSONL Trace |
| NFR21–NFR23 兼容性 | 3 | ✅ macOS 14 platform + 静态编译 + SPM multi-arch |

### 实现就绪性验证

**决策完整性：** 所有 8 项核心决策均已记录，含代码示例和理由。

**结构完整性：** 完整目录树已定义到文件级别，41 项 FR 均映射到具体文件。

**模式完整性：** 命名、结构、格式、通信、异步、测试 6 大模式均已定义，含正例和反例。

### 差距分析

**关键差距：** 无

**重要差距（MVP 内可接受）：**

| 差距 | 影响 | 处理方式 |
|------|------|----------|
| CI/CD 管道未定义 | 构建自动化缺失 | MVP 阶段用本地 `swift test`，Phase 2 补充 GitHub Actions |
| 日志框架未选型 | 结构化日志依赖 print | MVP 使用统一 Output 协议，Phase 2 引入 os.Logger 或 swift-log |
| Helper App 的 Info.plist 和 Entitlements 细节未定义 | 签名和权限配置 | 实现时参考 OpenClick 的 Helper 配置 |
| E2E 测试策略未定义（需要真实 macOS 桌面） | 无法 CI 自动化 | MVP 手动测试核心场景，Phase 2 探索 AX 测试框架 |

**锦上添花差距（可后续补充）：**

- 性能基准测试框架
- Prompt 版本管理策略
- Helper 工具能力发现机制（当前为静态注册）

### 架构完整性检查清单

**需求分析**

- [x] 项目上下文已全面分析
- [x] 规模与复杂度已评估（中高，~12 组件，~2000 行 Swift）
- [x] 技术约束已识别（Swift, macOS 14+, 无沙盒, AX 权限）
- [x] 跨切关注点已映射（6 项：SDK 边界、MCP 管道、错误恢复、安全、生命周期、可观测性）

**架构决策**

- [x] 关键决策已文档化（8 项 D1–D8，含代码示例）
- [x] 技术栈已完全指定（Swift 6.1+, SPM, 3 个核心依赖）
- [x] 集成模式已定义（MCP stdio, Anthropic HTTPS, Keychain, FileManager）
- [x] 性能考量已解决（静态编译, Actor 隔离, 进程隔离, 冷启动 <2s）

**实现模式**

- [x] 命名约定已建立（Swift / MCP / JSON 三套规则）
- [x] 结构模式已定义（文件归属, 模块依赖, import 顺序）
- [x] 通信模式已指定（MCP 工具命名, Trace 事件, 日志级别）
- [x] 流程模式已文档化（错误处理, Actor 隔离, 重试策略, 测试模式）

**项目结构**

- [x] 完整目录结构已定义（40+ 文件，3 个 SPM 目标）
- [x] 组件边界已建立（进程边界 + 模块依赖规则）
- [x] 集成点已映射（5 条内部通信 + 4 个外部集成）
- [x] 需求到结构映射已完成（41 FR → 文件级别映射）

### 架构就绪评估

**整体状态：** 实施已就绪

**信心等级：** 高 — 所有 16 项检查通过，无关键差距，41 FR 和 23 NFR 全覆盖。

**核心优势：**

1. **SDK 边界清晰** — 每个模块归属明确，Axion 的核心价值（验证 SDK 能力）有架构保障
2. **双进程隔离** — CLI 崩溃不影响 Helper，Helper 崩溃可检测恢复，安全性高
3. **强类型契约** — Plan/Step/RunState 等 Codable 模型确保模块间接口一致
4. **可观测性** — JSONL trace 贯穿整个执行流，调试和 SDK 改进有数据支撑
5. **一致性规则** — 命名、结构、模式规则足以防止 AI Agent 间冲突

**未来增强方向：**

1. CI/CD 管道（GitHub Actions + Homebrew tap 自动发布）
2. 结构化日志框架（os.Logger 或 swift-log）
3. E2E 测试框架（基于 AX API 的自动化桌面测试）
4. Prompt 版本管理和 A/B 测试机制

### 实现交接

**AI Agent 指南：**

- 严格遵循本文档中的所有架构决策
- 在所有组件中一致使用实现模式
- 尊重项目结构和边界定义
- 遇到架构疑问时以本文档为准

**首要实现优先级：**

1. 创建 `Package.swift` 和目录结构（Step 3 定义的项目结构）
2. 实现 `AxionCore` 共享模型（Plan, Step, RunState, AxionConfig, AxionError）
3. 实现 `AxionHelper` MCP Server + AX 服务（可独立开发和测试）
4. 实现 CLI Config 系统（ConfigManager + KeychainStore）
5. 实现 Planner → Executor → Verifier 执行循环

## OpenClick 参考指南

Axion 在实现时需要参考本地 OpenClick 仓库（`/Users/nick/CascadeProjects/openclick`）中的具体实现。以下按 Axion 模块逐一映射：**创建 Epic/Story 时，agent 应根据此映射决定何时读取 OpenClick 源码提取细节。**

### 参考原则

- **参考层**：Axion 的架构决策已在本文档中确定，OpenClick 只提供实现细节参考，不改变架构
- **适配层**：OpenClick 是 TypeScript + cua-driver（外部二进制），Axion 是纯 Swift + 内嵌 MCP Server — 需要适配而非照搬
- **SDK 差异**：OpenClick 绕过 SDK 自己实现 planner/executor 循环，Axion 必须通过 SDK 公共 API 编排

---

### AxionHelper → OpenClick mac-app/ 和 cua-driver

**何时参考：创建 AxionHelper 的 Story 时必须读取。**

| Axion 文件 | 参考 OpenClick 文件 | 提取什么 |
|-----------|-------------------|---------|
| `AxionHelper/Services/AccessibilityEngine.swift` | `mac-app/Sources/RecorderCore/AXTree.swift` | AXNode/WindowState 数据模型、Codable 编码键映射（snake_case） |
| `AxionHelper/Services/AccessibilityEngine.swift` | `mac-app/Sources/RecorderCore/CuaDriver.swift` | AX API 调用模式（getWindowState, listWindows）、Process 启动和超时处理、stdout/stderr 并发排空避免死锁 |
| `AxionHelper/Services/ScreenshotService.swift` | `mac-app/Sources/Recorder/Screenshotter.swift` | macOS 截图 API 调用方式 |
| `AxionHelper/MCP/HelperMCPServer.swift` | `mac-app/Sources/OpenclickHelper/main.swift` | Helper App 入口结构、MCP Server 初始化模式 |
| `AxionHelper/MCP/ToolRegistrar.swift` | `src/executor.ts:160-180`（BACKGROUND_SAFE_TOOLS） | 完整的 MCP 工具列表、参数 schema、安全分类（background_safe / foreground_required） |
| Helper App 打包配置 | `mac-app/Sources/OpenclickHelper/Info.plist` | LSUIElement=true（无 Dock 图标）、LSMinimumSystemVersion=13.0、CFBundleIdentifier 格式 |
| Helper App 签名配置 | `mac-app/OpenclickHelper.entitlements` | com.apple.security.automation.apple-events 权限声明 |
| Helper App 构建/打包 | `src/mac-app.ts` | App Bundle 创建流程（构建产物 → .app 目录结构 → Info.plist + Entitlements + 可执行文件） |

**关键注意：** OpenClick 的 mac-app 调用 `cua-driver` 外部二进制，AxionHelper 需要将这些调用替换为直接使用 macOS AX API（ApplicationServices.framework）。CuaDriver.swift 中的 Process 管理和超时处理模式值得参考，但实际的 AX 操作需要用 Swift 原生 API 重写。

---

### Planner → OpenClick src/planner.ts

**何时参考：创建 Planner 相关 Story 时必须读取。**

| Axion 文件 | 参考 OpenClick 文件 | 提取什么 |
|-----------|-------------------|---------|
| `AxionCLI/Planner/PromptBuilder.swift` | `src/planner.ts:119-167`（SYSTEM_GUIDANCE 常量） | **完整的 Planner system prompt** — 工具描述、规划原则、输出格式要求、shifted key 处理、background-safe 策略 |
| `AxionCLI/Planner/LLMPlanner.swift` | `src/planner.ts:169-185`（generatePlan 函数） | Plan 生成流程：构建 prompt → 调用 LLM → 解析 JSON → 验证 |
| `AxionCLI/Planner/PlanParser.swift` | `src/planner.ts:255-280`（stripFences 函数） | LLM 输出解析：剥离 markdown 围栏、提取 JSON 对象、处理 prose 前缀/后缀 |
| `AxionCore/Models/Plan.swift` | `src/planner.ts:17-39`（PlanStep / Plan 接口） | Plan 数据结构：status (ready/done/blocked/needs_clarification)、steps、stopWhen、message |
| `AxionCore/Models/Step.swift` | `src/planner.ts:17-26`（PlanStep 接口） | Step 数据结构：tool、args、purpose、expected_change |
| Planner 重规划逻辑 | `src/planner.ts:80-98`（ReplanContext 接口）+ `src/planner.ts:200-245`（buildPlannerPrompt replan 分支） | 重规划上下文传递：失败步骤、已执行步骤、live AX tree、run history、恢复策略 |
| shifted key 处理 | `src/planner.ts:41-63`（SHIFTED_KEY_MAP） | 符号键到基础键的映射表（如 `"*"` → `shift+"8"`） |

**SYSTEM_GUIDANCE 是最关键的参考** — 它包含了完整的工具描述、参数格式、规划约束和输出格式要求。Axion 的 `Prompts/planner-system.md` 应以此为基础适配。

---

### Executor → OpenClick src/executor.ts

**何时参考：创建 Executor 相关 Story 时必须读取。**

| Axion 文件 | 参考 OpenClick 文件 | 提取什么 |
|-----------|-------------------|---------|
| `AxionCLI/Executor/PlaceholderResolver.swift` | `src/executor.ts:90-115`（ExecutorContext 接口） | 占位符解析：$pid/$window_id 的上下文跟踪、AX index 缓存、screenshot 尺寸 |
| `AxionCLI/Executor/StepExecutor.swift` | `src/executor.ts:12-18`（StepResult 接口） | 步骤执行结果模型 |
| `AxionCLI/Executor/StepExecutor.swift` | `src/executor.ts:33-70`（ExecutePlanOptions 接口） | 执行选项：dryRun、confirm、refreshBeforeAxClick、executionPolicy、maxSteps |
| `AxionCLI/Executor/SafetyChecker.swift` | `src/executor.ts:147-158`（ExecutionPolicy / StepSafety 类型）+ `src/executor.ts:160+`（BACKGROUND_SAFE_TOOLS） | 工具安全分类逻辑、foreground vs background 模式策略 |
| AxionCore/Models/ 相关 | `src/executor.ts:122-145`（AxIndexEntry 接口） | AX 元素索引结构：index、role、id、title、subtreeText、ancestorPath、ordinal |

**关键注意：** OpenClick 的 Executor 通过 `spawnSync` 调用 cua-driver 子进程执行每个步骤。Axion 通过 MCP stdio 调用 AxionHelper — 通信机制完全不同，但步骤执行逻辑（占位符解析、安全检查、错误处理）可以复用思路。

---

### Config/Settings → OpenClick src/settings.ts

**何时参考：创建 Config 系统 Story 时必须读取。**

| Axion 文件 | 参考 OpenClick 文件 | 提取什么 |
|-----------|-------------------|---------|
| `AxionCLI/Config/KeychainStore.swift` | `src/settings.ts:12-13`（KEYCHAIN_SERVICE / KEYCHAIN_ACCOUNT）+ `src/settings.ts:64-73`（resolveProviderApiKey） | Keychain 服务名格式、API Key 解析优先级（env → keychain → settings file） |
| `AxionCLI/Config/ConfigManager.swift` | `src/settings.ts:18-23`（OpenClickSettings 接口）+ `src/settings.ts:29-58` | 配置文件读写、JSON 解析防御性处理 |
| `AxionCLI/Commands/SetupCommand.swift` | `src/setup.ts` | setup 引导流程参考 |
| `AxionCLI/Commands/DoctorCommand.swift` | `src/doctor.ts` | doctor 检查逻辑参考 |

---

### Run Loop → OpenClick src/run.ts

**何时参考：创建 RunEngine Story 时必须读取。**

| Axion 文件 | 参考 OpenClick 文件 | 提取什么 |
|-----------|-------------------|---------|
| `AxionCLI/Engine/RunEngine.swift` | `src/run.ts:54-80`（RunOptions 接口） | 运行参数模型：taskPrompt、live、maxSteps、maxBatches、maxReplans、cursor、fast |
| RunEngine 主循环 | `src/run.ts` 全文 | 批次循环：plan → execute → verify → replan 的完整编排流程、锁机制、中断处理 |

---

### AX Tree 解析 → OpenClick src/axtree.ts

**何时参考：创建 AX 相关服务时参考。**

| Axion 文件 | 参考 OpenClick 文件 | 提取什么 |
|-----------|-------------------|---------|
| `AxionHelper/Services/AccessibilityEngine.swift` | `src/axtree.ts` | AX 树截断逻辑（maxNodes / maxDepth）、节点计数 |

---

### 模型调用 → OpenClick src/models.ts

**何时参考：Axion 不直接参考此文件 — 应通过 SDK 的 Agent Loop 调用 LLM。但了解 OpenClick 的做法有助于理解 SDK 边界。**

| OpenClick 文件 | 说明 |
|---------------|------|
| `src/models.ts` | OpenClick 直接使用 Anthropic SDK 调用 LLM（绕过 OpenAgentSDK）。Axion 必须通过 SDK 的 Agent Loop 调用，不应参考此文件的调用方式 |

---

### OpenAgentSDK 参考

**Axion 依赖的 SDK 本地路径：`/Users/nick/CascadeProjects/open-agent-sdk-swift`**

| 需要参考的 SDK 能力 | SDK 路径 | 用途 |
|-------------------|---------|------|
| Agent 创建和循环 | `Sources/OpenAgentSDK/OpenAgentSDK.swift` | 主入口，了解 `createAgent` API |
| 工具注册 | `Sources/OpenAgentSDK/Tools/` | 工具定义框架（defineTool） |
| MCP Client | `Examples/MCPIntegration/` | MCP Client 连接和使用示例 |
| 流式输出 | `Examples/StreamingAgent/` | AsyncStream<SDKMessage> 使用模式 |
| Hooks | `Examples/SessionsAndHooks/` | 生命周期拦截器注册 |
| Session 管理 | `Examples/CompatSessions/` | 会话保存/恢复 |
| 自定义 System Prompt | `Examples/CustomSystemPromptExample/` | 自定义 Agent 行为 |

---

### Story 创建时的参考决策矩阵

| Story 类型 | 是否需要读 OpenClick | 读哪些文件 |
|-----------|---------------------|-----------|
| AxionHelper AX 操作 | **必须** | `mac-app/Sources/RecorderCore/`、`mac-app/Sources/OpenclickHelper/` |
| AxionHelper MCP Server | **必须** | `src/executor.ts`（工具列表和参数）、`mac-app/Sources/OpenclickHelper/main.swift` |
| Helper App 打包/签名 | **必须** | `mac-app/OpenclickHelper.entitlements`、`mac-app/Sources/OpenclickHelper/Info.plist`、`src/mac-app.ts` |
| Planner Prompt 设计 | **必须** | `src/planner.ts:119-167`（SYSTEM_GUIDANCE 完整内容） |
| Planner Plan 解析 | **必须** | `src/planner.ts:255+`（stripFences）、`src/planner.ts:17-39`（数据模型） |
| Executor 步骤执行 | **推荐** | `src/executor.ts:90-115`（ExecutorContext）、`src/executor.ts:160+`（BACKGROUND_SAFE_TOOLS） |
| 安全策略（共享座椅） | **推荐** | `src/executor.ts:147-158`、`src/planner.ts` 中的 background-safe 规则 |
| Config/Keychain | **推荐** | `src/settings.ts`（Keychain 服务名、优先级链） |
| Run Engine 主循环 | **参考** | `src/run.ts`（批次循环结构） |
| CLI 命令（run/setup/doctor） | **参考** | `src/run.ts`、`src/setup.ts`、`src/doctor.ts` |
| AxionCore 共享模型 | **不需要** | Axion Architecture 已定义完整的数据模型 |
| SDK 集成 | **不参考 OpenClick** | 参考 `/Users/nick/CascadeProjects/open-agent-sdk-swift/Examples/` |
| 测试 | **不需要** | 按 Axion Architecture 定义的测试模式写 |
