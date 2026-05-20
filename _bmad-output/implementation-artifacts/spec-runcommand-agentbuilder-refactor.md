---
title: 'RunCommand 与 AgentBuilder 深度重构'
type: 'refactor'
created: '2026-05-20'
baseline_commit: '7f98b38'
status: 'done'
context:
  - '{project-root}/_bmad-output/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## 意图

**问题：** RunCommand.run() 仍有 864 行——CLI 解析、锁管理、Trace 初始化、SIGINT 处理、一个 116 行的 stream loop（混合了 5 个关注点：视觉增量、费用追踪、座位监控、Takeover、Trace 记录）、输出处理器、运行后 Memory 处理全部挤在一个文件里。AgentBuilder（455 行）混合了 Agent 构建、System Prompt 组装、Safety Hook 注册、Playwright 配置解析。MCPServerRunner 重复了 AgentBuilder 约 70% 的逻辑（API Key 解析、Helper 路径、Memory Store、System Prompt、Safety Hook、Agent 创建），没有复用。

**方案：** 将 RunCommand 的执行管线提取到 `RunOrchestrator`（stream loop + 锁 + Trace + SIGINT + 运行后处理）。将输出处理器提取到 `SDKOutputHandlers.swift`。AgentBuilder 保持 `build()` 入口，内部重组 System Prompt 和 Safety Hook。MCPServerRunner 改为复用 AgentBuilder，消除重复代码。

## 边界与约束

**始终遵守：**
- 所有现有 CLI 参数和 Flag 行为不变
- Memory 操作保持非致命（do/catch 包裹，失败仅 warning 日志）
- ApiRunner 对 AgentBuilder 的使用不受影响
- 视觉增量、费用追踪、座位监控、Takeover 的行为完全保留
- 改完后运行单元测试：`swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"`

**需先确认：**
- 对 AgentBuildResult 公共接口的任何变更
- 移动 RunMemoryProcessor 引用的方法（如 `RunCommand.buildProfileContent`）

**绝不：**
- 修改 JSON 输出格式或终端输出格式
- 新增 CLI 参数或改变用户可见行为
- 修改 ApiRunner（后续单独重构）
- 创建深层继承体系或过度抽象

</frozen-after-approval>

## 代码地图

- `Sources/AxionCLI/Commands/RunCommand.swift` — 主要重构目标：864 行，提取执行管线
- `Sources/AxionCLI/Services/AgentBuilder.swift` — 次要目标：455 行，重组内部结构
- `Sources/AxionCLI/MCP/MCPServerRunner.swift` — 去重：复用 AgentBuilder，消除 ~70 行重复代码
- `Sources/AxionCLI/API/ApiRunner.swift` — AgentBuilder 消费者，必须继续正常工作
- `Sources/AxionCLI/Memory/RunMemoryProcessor.swift` — 引用 `RunCommand.buildProfileContent`
- `Sources/AxionCLI/Services/CostTracker.swift` — RunCommand 和 ApiRunner 共用
- `Sources/AxionCLI/Services/VisualDeltaTracker.swift` — stream loop 关注点
- `Sources/AxionCLI/Services/SeatActivityMonitor.swift` — stream loop 关注点
- `Sources/AxionCLI/Helper/HelperPathResolver.swift` — AgentBuilder 使用
- `Sources/AxionCLI/Config/PromptBuilder.swift` — AgentBuilder System Prompt 使用

## 任务与验收

**执行：**

- [x] `Sources/AxionCLI/Commands/SDKOutputHandlers.swift`（新文件）— 从 RunCommand.swift 提取 `SDKMessageOutputHandler` 协议、`SDKTerminalOutputHandler` 和 `SDKJSONOutputHandler` 到独立文件。RunCommand 改为引用新类型。

- [x] `Sources/AxionCLI/Services/RunOrchestrator.swift`（新文件）— 从 `RunCommand.run()` 提取执行管线到 `RunOrchestrator` struct。负责：Run ID 生成、桌面锁、Trace 初始化、SIGINT handler、stream loop（含全部 5 个关注点：视觉增量、费用追踪、座位监控、Takeover 处理、Trace 记录）、Agent 清理、费用摘要输出、运行后 Memory 处理。RunCommand 调用 `RunOrchestrator.execute()` 传入解析后的参数。

- [x] `Sources/AxionCLI/Commands/RunCommand.swift` — 瘦身至 ~150-200 行：参数解析、配置加载、技能检测、BuildConfig 组装、单次调用 `RunOrchestrator.execute()`。将 `generateRunId`、`computeEffectiveMaxSteps/Tokens`、`traceMode`、`buildProfileContent`、`extractBase64FromToolResult`、`recordToTrace` 移至 RunOrchestrator。将 `parseSkillName` 和 `executeSkillDirectly` 也移至 RunOrchestrator。

- [x] `Sources/AxionCLI/Services/AgentBuilder.swift` — 重组：保持 `build()` 和 `buildSkillAgent()` 为公共 API，System Prompt 和 Safety Hook 保留为私有内部方法（已具备良好作用域）。将 `resolvePlaywrightConfig()` 提取到文件末尾的 `PlaywrightConfig` helper 或独立的 `MCPConfigResolver.swift`。新增 `BuildConfig.forMCP()` 工厂方法供 MCPServerRunner 使用。

- [x] `Sources/AxionCLI/MCP/MCPServerRunner.swift` — 用 `AgentBuilder.build(BuildConfig.forMCP())` 替换重复的 Agent 构建代码。删除 ~70 行重复的 API Key 解析、Helper 路径解析、Memory Store 创建、System Prompt 构建、Safety Hook 注册、Agent 创建逻辑。保留 MCP 特有逻辑（工具池组装、RunTracker、TaskQueue、AgentMCPServer）。

- [x] `Sources/AxionCLI/Memory/RunMemoryProcessor.swift` — 将 `RunCommand.buildProfileContent` 引用更新为 `RunOrchestrator.buildProfileContent`（或改为自由函数 / 移至 AppProfileAnalyzer）。

- [x] 更新所有引用 `RunCommand.computeEffectiveMaxSteps`、`RunCommand.computeEffectiveMaxTokens`、`RunCommand.extractBase64FromToolResultForTest`、`RunCommand.buildProfileContent` 的测试文件，指向新位置。

**验收标准：**
- Given 打开 RunCommand.swift，when 阅读 run() 方法，then 应在 50 行以内——仅参数解析、配置、单次编排调用
- Given 打开 MCPServerRunner.swift，when 搜索 "apiKey" 或 "resolveHelperPath"，then 零结果——所有构建走 AgentBuilder
- Given 运行 `swift test`（单元测试），then 所有现有测试通过
- Given `axion run "open Calculator" --fast`，then 行为与重构前完全一致
- Given `axion run "/polyv-live-cli do something"`，then 技能直接执行仍然正常

## 设计备注

**RunOrchestrator 模式：** 编排器是一个 struct，包含一个 `execute()` 静态方法，不是带可变状态的 class。所有配置通过参数传入，返回结构化结果。stream loop 的可变状态（totalSteps、visualDeltaSkipped 等）是 execute 方法内的局部变量。这避免了 actor 隔离复杂性，同时保持可测试性。

```swift
struct RunOrchestrator {
    struct RunResult {
        let totalSteps: Int
        let durationMs: Int
        let runSucceeded: Bool
    }

    static func execute(
        agent: Agent,
        task: String,
        runId: String,
        config: OrchestratorConfig
    ) async throws -> RunResult
}
```

**MCPServerRunner 统一：** 新增 `BuildConfig.forMCP()`——最小化工厂方法，跳过技能、不注入 Memory、不包含 Playwright。MCPServerRunner 调用 `AgentBuilder.build()` 后，在其基础上添加 MCP 特有工具。消除 ~70 行重复代码，同时保留 MCPServerRunner 独特的工具组装逻辑。

**为什么不从 AgentBuilder 提取 System Prompt / Safety Hook：** 这些是 Agent 构建的内部实现细节。提取到独立文件增加了间接层但没有实际收益——它们只被 AgentBuilder 和 MCPServerRunner 调用（而 MCPServerRunner 现在将调用 AgentBuilder）。保持为私有方法维持了内聚性。

## 验证

**命令：**
- `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` — 预期：全部通过
- `wc -l Sources/AxionCLI/Commands/RunCommand.swift` — 预期：~150-200 行
- `grep -c "apiKey" Sources/AxionCLI/MCP/MCPServerRunner.swift` — 预期：0（或仅出现在错误信息中）

**手动检查：**
- RunCommand.run() 方法体应呈现清晰的线性流程：解析 → 构建 → 执行 → 结束
- AgentBuilder 和 MCPServerRunner 之间不存在重复的 API Key / Helper 路径 / Memory Store / System Prompt 逻辑
