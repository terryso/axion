---
title: 'Axion 深度分析：SDK 提取 + 重构'
type: 'refactor'
created: '2026-05-20'
updated: '2026-05-21'
baseline_commit: 'f2754f2'
sdk_branch: 'docs/epic20-reference-paths'
sdk_status: 'epic-20 已完成'
status: 'ready-for-axion'
context:
  - '{project-root}/_bmad-output/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## 意图

**问题：** AxionCLI 已膨胀至 11,499 行 — 是架构目标 ~2,000 行的 5.7 倍。其中约一半（~7,000 行）是通用 Agent 基础设施（HTTP API 服务、Run 追踪、SSE 广播、Cost 追踪、Trace 记录、增强 Memory 生命周期、输出格式化），任何基于 SDK 的 Agent 项目都需要这些能力。这削弱了 SDK 的价值主张：如果 Axion 作为旗舰应用需要这么多样板代码，说明 SDK 提供得不够。

**方案：** (1) 识别属于 SDK 的代码，定义 SDK 侧新增能力。(2) 重构留在 Axion 的代码，使职责分离更清晰、行数更少。目标：AxionCLI 提取后降至 6,000 行以下。

**当前状态：** SDK Epic 20 已完成（`docs/epic20-reference-paths` 分支），提供了 AgentHTTPServer、CostTracker、TraceRecorder、增强 Memory、SDKMessageOutputHandler。Axion 侧重构可开始。

## 边界与约束

**始终遵守：**
- 所有现有 CLI 参数和 Flag 行为不变
- Memory 操作保持非致命（do/catch 包裹，失败仅 warning 日志）
- AxionHelper 和 AxionBar 不动（全部是桌面专属代码，位置正确）
- API 端点契约不变（AxionBar 兼容性）— 响应格式必须保持 `StandardTaskOutput`
- 每个阶段完成后单元测试全部通过

**需先确认：**
- 对 SDK 公共 API 的任何修改（AgentOptions、Agent、SDKMessage）
- 删除或合并跨模块边界的 AxionCore 类型
- 更改 Memory 磁盘文件格式

**禁止：**
- 将桌面专属代码（AX 操作、截图、输入模拟）移入 SDK
- 修改 AxionBar 的 HTTP 客户端代码
- 破坏 Helper ↔ CLI MCP stdio 契约
- 改变 API 响应格式（AxionBar 依赖 `StandardTaskOutput`，不是 SDK 的 `RunResponse`）

</frozen-after-approval>

## Code Map

### SDK 提取候选（AxionCLI 中的通用 Agent 基础设施）

- `Sources/AxionCLI/API/AxionAPI.swift` (996 行) — Run、Skill、SSE、Settings、Health 的 REST 路由
- `Sources/AxionCLI/API/ApiRunner.swift` (331 行) — 流处理 → SSE 广播
- `Sources/AxionCLI/API/Models/APITypes.swift` (598 行) — 全部 API 请求/响应 Codable 类型
- `Sources/AxionCLI/API/EventBroadcaster.swift` (143 行) — Actor 隔离的 SSE 扇出 + 重放缓冲
- `Sources/AxionCLI/API/RunTracker.swift` (180 行) — Actor 隔离的 Run 生命周期状态机
- `Sources/AxionCLI/API/RunPersistenceService.swift` (168 行) — Run 状态 JSONL 文件持久化
- `Sources/AxionCLI/API/RunRecoveryService.swift` (59 行) — 崩溃恢复
- `Sources/AxionCLI/API/ConcurrencyLimiter.swift` (54 行) — 异步信号量
- `Sources/AxionCLI/API/AuthMiddleware.swift` (33 行) — Bearer Token 认证
- `Sources/AxionCLI/API/SkillAPIRunner.swift` (183 行) — 通过 API 执行 Skill
- `Sources/AxionCLI/Services/CostTracker.swift` (124 行) — Token/Cost/截图预算追踪
- `Sources/AxionCLI/Trace/TraceRecorder.swift` (308 行) — JSONL 执行 Trace
- `Sources/AxionCLI/Memory/` (14 文件, ~2,100 行) — 增强的 Fact-based Memory（生命周期、证据、分类、导入导出）
- `Sources/AxionCLI/Commands/SDKOutputHandlers.swift` (247 行) — SDKMessage → 格式化输出
- `Sources/AxionCLI/MCP/MCPServerRunner.swift` (73 行) — Agent-as-MCP-Server 编排器
- `Sources/AxionCLI/MCP/TaskQueue.swift` (70 行) — MCP 模式串行任务队列
- `Sources/AxionCLI/MCP/RunTaskTool.swift` (124 行) — run_task MCP 工具
- `Sources/AxionCLI/MCP/QueryTaskStatusTool.swift` (114 行) — query_task_status MCP 工具
- `Sources/AxionCLI/Services/RunLockService.swift` (142 行) — 跨进程 Run 锁

### 留在 Axion（桌面专属，位置正确）

- 全部 AxionHelper（21 文件, 3,009 行）— AX 引擎、输入模拟、截图、App 启动
- 全部 AxionBar（19 文件, 2,453 行）— 菜单栏 GUI
- `Services/VisualDeltaTracker.swift` (208 行) — 截图像素差异
- `Services/SeatActivityMonitor.swift` (84 行) — 桌面活动检测
- `Helper/HelperProcessManager.swift` (368 行) — Helper 子进程生命周期
- `Skills/AxionBuiltInSkills.swift` (141 行) — 桌面 Skill Prompt 模板
- `Commands/` CLI 入口 — 桌面专属参数解析

### 需要重构（留在 Axion 但需要重组）

- `Sources/AxionCLI/Services/AgentBuilder.swift` (476 行) — 混合了通用 Agent 设置与桌面专属逻辑
- `Sources/AxionHelper/MCP/ToolRegistrar.swift` (1,042 行) — 独石式工具注册文件
- `Sources/AxionCLI/Memory/` (14 文件) — 小文件过多，部分紧耦合

## Tasks & Acceptance

### SDK 侧（已完成 ✅）

SDK Epic 20 已在 `docs/epic20-reference-paths` 分支完成，提供以下能力：

| SDK 类型 | 文件 | Axion 对应物 |
|----------|------|-------------|
| `AgentHTTPServer` | `HTTP/AgentHTTPServer.swift` | AxionAPI（完整服务器） |
| `RunTracker` | `HTTP/RunTracker.swift` | Axion API/RunTracker.swift |
| `EventBroadcaster` | `HTTP/EventBroadcaster.swift` | Axion API/EventBroadcaster.swift |
| `RunPersistenceService` | `HTTP/RunPersistenceService.swift` | Axion API/RunPersistenceService.swift |
| `RunRecoveryService` | `HTTP/RunRecoveryService.swift` | Axion API/RunRecoveryService.swift |
| `ConcurrencyLimiter` | `HTTP/ConcurrencyLimiter.swift` | Axion API/ConcurrencyLimiter.swift |
| `AuthMiddleware` | `HTTP/AuthMiddleware.swift` | Axion API/AuthMiddleware.swift |
| `CostTracker` (struct) | `Utils/CostTracker.swift` | Axion Services/CostTracker.swift (actor) |
| `TraceRecorder` (actor) | `Utils/TraceRecorder.swift` | Axion Trace/TraceRecorder.swift |
| `TraceEventMapping` | `Utils/TraceEventMapping.swift` | Axion RunOrchestrator 内联逻辑 |
| `FactStore` (actor) | `Stores/FactStore.swift` | Axion Memory/MemoryFactStore.swift |
| `MemoryFact` | `Types/MemoryFact.swift` | Axion Memory 内联类型 |
| `MemoryLifecycleService` | `Utils/MemoryLifecycleService.swift` | Axion Memory/MemoryLifecycleService.swift |
| `MemoryContextProvider` | `Utils/MemoryContextProvider.swift` | Axion Memory/MemoryContextProvider.swift |
| `MemoryBundleImportService` | `Utils/MemoryBundleImportService.swift` | Axion Memory/MemoryBundleImportService.swift |
| `MemoryBundleExportService` | `Utils/MemoryBundleExportService.swift` | Axion Memory/MemoryBundleExportService.swift |
| `MemoryBundle` / `ExportedDomain` | `Types/MemoryBundle.swift` | Axion Memory/MemoryBundle.swift |
| `SDKMessageOutputHandler` | `Types/SDKMessageOutputHandler.swift` | Axion Commands/SDKOutputHandlers.swift 协议 |
| `TerminalOutputHandler` | `Utils/TerminalOutputHandler.swift` | Axion Commands/SDKOutputHandlers.swift 实现 |
| `JSONOutputHandler` | `Utils/JSONOutputHandler.swift` | Axion Commands/SDKOutputHandlers.swift 实现 |
| `CostSummary` / `ModelCostEntry` | `Types/CostTypes.swift` | Axion Services/CostTracker.swift 类型 |
| `RunCompleteContext` | `Types/AgentTypes.swift` | Axion 无对应（新增能力） |
| `onRunComplete` / `traceEnabled` / `maxBudgetUsd` | AgentOptions 字段 | Axion 手动管理 |

### Axion 侧重构

**Phase 1: HTTP API — 用 SDK 组件重建路由（移除 ~1,500 行）**

> **集成方式：** SDK 的 `AgentHTTPServer` 是独立完整服务器，不能直接替换 AxionAPI。
> Axion 使用 SDK 的**底层组件**（RunTracker、EventBroadcaster、RunPersistenceService、
> RunRecoveryService、ConcurrencyLimiter、AuthMiddleware）重建 Hummingbird 路由。
> Axion 保留 SDK 不提供的端点（settings、capabilities、skills）和 `StandardTaskOutput` 响应格式。

- [ ] 删除 `Sources/AxionCLI/API/RunTracker.swift` → 用 `OpenAgentSDK.HTTP.RunTracker`
- [ ] 删除 `Sources/AxionCLI/API/EventBroadcaster.swift` → 用 `OpenAgentSDK.HTTP.EventBroadcaster`
- [ ] 删除 `Sources/AxionCLI/API/RunPersistenceService.swift` → 用 `OpenAgentSDK.HTTP.RunPersistenceService`
- [ ] 删除 `Sources/AxionCLI/API/RunRecoveryService.swift` → 用 `OpenAgentSDK.HTTP.RunRecoveryService`
- [ ] 删除 `Sources/AxionCLI/API/ConcurrencyLimiter.swift` → 用 `OpenAgentSDK.HTTP.ConcurrencyLimiter`
- [ ] 删除 `Sources/AxionCLI/API/AuthMiddleware.swift` → 用 `OpenAgentSDK.HTTP.AuthMiddleware`
- [ ] 精简 `AxionAPI.swift` — Run 相关路由用 SDK 组件重建，保留 Axion 专属端点（settings、capabilities、skills）
- [ ] 精简 `ApiRunner.swift` — SSE 广播和 Run 追踪委托 SDK 组件
- [ ] 精简 `SkillAPIRunner.swift` — Run 追踪委托 SDK 组件
- [ ] 精简 `API/Models/APITypes.swift` — 删除与 SDK `APITypes` 重叠的类型，保留 `StandardTaskOutput` 和 Axion 专属模型

**Phase 2: Cost + Trace — 用 SDK 内化能力替换（移除 ~430 行）**

> **集成方式：** SDK 的 CostTracker 是 struct，由 Agent loop 内部自动管理。
> Axion 不需要自己的 CostTracker actor — 只需配置 `AgentOptions.maxBudgetUsd`。
> Trace 也一样 — 配置 `AgentOptions.traceEnabled = true`，Agent 自动创建 TraceRecorder。
> 运行后数据通过 `AgentOptions.onRunComplete` 回调获取（`RunCompleteContext` 含 toolPairs、usage、totalCostUsd、durationMs 等）。

- [ ] 删除 `Sources/AxionCLI/Services/CostTracker.swift`（124 行）→ 配置 `AgentOptions.maxBudgetUsd`
- [ ] 删除 `Sources/AxionCLI/Trace/TraceRecorder.swift`（308 行）→ 配置 `AgentOptions.traceEnabled = true`
- [ ] 更新 `RunOrchestrator` — 移除手动 Trace 调用，改用 SDK 内建 trace
- [ ] 更新 `RunOrchestrator` — 费用摘要改从 `RunCompleteContext.totalCostUsd` / `costBreakdown` 获取
- [ ] 更新 `AgentBuilder` — 配置 `onRunComplete` 回调处理运行后逻辑（Memory 提取、费用显示）

**Phase 3: Memory — 用 SDK 核心替换，保留桌面专属文件（移除 ~1,000 行）**

> **集成方式：** SDK 提供 Fact 存储和生命周期的完整基础设施。
> Axion 仅保留桌面专属的 Memory 提取和学习逻辑。

删除（SDK 替代）：
- [ ] `Memory/MemoryFactStore.swift` → `OpenAgentSDK.Stores.FactStore`
- [ ] `Memory/MemoryLifecycleService.swift` → `OpenAgentSDK.Utils.MemoryLifecycleService`
- [ ] `Memory/MemoryContextProvider.swift` → `OpenAgentSDK.Utils.MemoryContextProvider`
- [ ] `Memory/MemoryBundle.swift` → `OpenAgentSDK.Types.MemoryBundle` + `ExportedDomain`
- [ ] `Memory/MemoryBundleExportService.swift` → `OpenAgentSDK.Utils.MemoryBundleExportService`
- [ ] `Memory/MemoryBundleImportService.swift` → `OpenAgentSDK.Utils.MemoryBundleImportService`
- [ ] `Memory/MemoryCleanupService.swift` → SDK 的 `MemoryLifecycleService.demoteRetired()` 已覆盖

保留（Axion 桌面专属）：
- `AppMemoryExtractor.swift` — MCP 工具名前缀 `mcp__axion-helper__` 过滤逻辑
- `AppMemoryFact.swift` — Axion 专属 Fact 类型
- `AppProfileAnalyzer.swift` — 用户画像分析
- `RunMemoryProcessor.swift` — 运行后 Memory 处理（接入 SDK FactStore）
- `FamiliarityTracker.swift` — 熟悉度追踪
- `TakeoverLearningService.swift` — Takeover 学习
- `TakeoverMarker.swift` — Takeover 标记

**Phase 4: 输出格式化 — 用 SDK 协议替换（移除 ~150 行）**

> **集成方式：** SDK 提供 `SDKMessageOutputHandler` 协议及 `TerminalOutputHandler`、`JSONOutputHandler` 实现。
> Axion 的输出处理器有桌面专属逻辑（截图 binary 检测、visual delta 信息），
> 可扩展 SDK 实现或保留少量 Axion 专属代码。

- [ ] 精简 `SDKOutputHandlers.swift` — 协议部分用 SDK 的 `SDKMessageOutputHandler`，保留 Axion 专属扩展（截图处理等）
- [ ] 或者：如果桌面专属逻辑可内联到 RunOrchestrator，直接删除 `SDKOutputHandlers.swift` 用 SDK 实现

**Phase 5: 内部重构（不依赖 SDK）**
- [ ] `Sources/AxionHelper/MCP/ToolRegistrar.swift` — 将 1,042 行独石文件按类别拆分（MouseTools、KeyboardTools、WindowTools、AppTools、ScreenshotTools、RecordingTools）。
- [ ] `Sources/AxionCLI/Services/AgentBuilder.swift` — 将通用 `buildAgent()` 流程与桌面专属设置（HelperProcess、SafetyHook、Playwright 配置）分离。提取 `DesktopSafetyHookFactory`。
- [ ] `Sources/AxionCLI/Services/RunLockService.swift`（142 行）— 评估是否可简化或合入 RunOrchestrator

**验收标准：**
- Given AxionCLI 源码，when 统计所有阶段后的行数，then 总计 ≤ 6,000（从 11,499 下降）
- Given `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"`，when 运行，then 全部通过
- Given `axion run "打开计算器"`，when 执行，then Agent 运行行为与重构前完全一致
- Given `axion server --port 4242`，when 启动，then 所有 HTTP API 端点响应与之前一致（`StandardTaskOutput` 格式不变）
- Given AxionBar 正在运行，when 连接到 Server，then 所有功能正常工作
- Given `axion run "打开计算器" --trace`，when 执行完成后检查 `~/.axion/traces/`，then trace.jsonl 格式与之前一致
- Given `axion run "打开计算器"`，when 执行完成后检查终端，then 费用摘要与之前一致

## Spec Change Log

## Design Notes

### HTTP API 集成策略

SDK 的 `AgentHTTPServer` 是独立完整服务器（自建 Hummingbird 路由），不能直接替换 AxionAPI。Axion 采取**组件级复用**策略：

1. **用 SDK 底层组件替换 Axion 的实现类**：RunTracker、EventBroadcaster、RunPersistenceService、RunRecoveryService、ConcurrencyLimiter、AuthMiddleware
2. **AxionAPI 保留为路由入口**：用 SDK 组件实例化路由，保留 Axion 专属端点（settings、capabilities、skills）
3. **保留 `StandardTaskOutput` 响应格式**：AxionBar 依赖此格式，不迁移到 SDK 的 `RunResponse`

这样做的好处：
- Axion 保留对 API 层的完全控制（AxionBar 兼容性）
- Run 追踪、SSE 广播、持久化等核心逻辑来自 SDK（零维护成本）
- SDK 的 `AgentHTTPServer` 继续服务简单场景（开箱即用）

### CostTracker / TraceRecorder 集成策略

SDK 的 CostTracker 是 struct（不是 actor），由 Agent loop 内部自动管理。Axion 不需要自己的 CostTracker actor。

**迁移方式：**
- 删除 Axion 的 `CostTracker.swift` actor
- 在 `AgentBuilder` 中配置 `AgentOptions.maxBudgetUsd`
- 费用数据通过 `AgentOptions.onRunComplete` 回调的 `RunCompleteContext` 获取：
  - `totalCostUsd` — 总费用
  - `costBreakdown` — 按模型分项
  - `usage` — Token 使用统计
  - `durationMs` / `numTurns` — 运行指标
- Trace 同理：配置 `AgentOptions.traceEnabled = true`，Agent 自动创建 TraceRecorder

### Memory 保留文件策略

SDK 提供了 Memory 的核心基础设施。以下 7 个文件是 Axion 桌面专属，必须保留：

| 文件 | 职责 | 保留理由 |
|------|------|----------|
| `AppMemoryExtractor.swift` | 从 MCP 工具结果提取 Memory | 含 `mcp__axion-helper__` 前缀过滤 |
| `AppMemoryFact.swift` | Axion 专属 Fact 类型 | 桌面场景特有字段 |
| `AppProfileAnalyzer.swift` | 用户画像分析 | 桌面使用习惯分析 |
| `RunMemoryProcessor.swift` | 运行后 Memory 处理 | 桥接 SDK FactStore 和桌面提取 |
| `FamiliarityTracker.swift` | 熟悉度追踪 | 桌面交互频次追踪 |
| `TakeoverLearningService.swift` | Takeover 学习 | Takeover 模式专属学习 |
| `TakeoverMarker.swift` | Takeover 标记 | Takeover 模式标记 |

### SDK 提取优先级理由

HTTP API 是 Phase 1，因为：
1. 提取量最大（~1,500 行移除）
2. SDK 底层组件全部 public，集成路径清晰
3. 零耦合桌面专属代码

Cost + Trace 是 Phase 2，因为：
1. SDK 通过 `AgentOptions` 字段完全内化，Axion 只需删除代码 + 配置选项
2. `onRunComplete` 回调是新能力，需要设计运行后处理流程

Memory 是 Phase 3（不是 Phase 1），因为：
1. 7 个桌面专属文件需要保留，迁移边界更复杂
2. `RunMemoryProcessor` 需要桥接 SDK FactStore
3. 需要更新 Memory CLI 命令（import/export）使用 SDK 类型

### 不应提取的代码

- **RunOrchestrator**（519 行）：桌面专属流循环（VisualDelta、SeatMonitor、TakeoverIO）。正确留在 Axion。
- **HelperProcessManager**（368 行）：桌面专属子进程管理。非通用。
- **Skill/录制系统**：编译逻辑有一定通用性，但录制基于 CGEvent Tap（桌面专属）。不值得拆分。
- **AxionCore 模型**：`Skill`、`Value`、`AxionError` 是 Axion 的领域类型。SDK 有自己的对应物（`ToolProtocol`、`SDKError`）。
- **`StandardTaskOutput`**：AxionBar 依赖的响应格式。SDK 的 `RunResponse` 是通用格式，不能替代。

### 提取后架构

```
OpenAgentSDK (~25K 行，Epic 20 已完成)
    ├── Core/ (Agent — 内建 CostTracker + TraceRecorder)
    ├── HTTP/ (AgentHTTPServer, RunTracker, EventBroadcaster, RunPersistenceService, RunRecoveryService, ConcurrencyLimiter, AuthMiddleware)
    ├── Utils/ (CostTracker, TraceRecorder, TraceEventMapping, TerminalOutputHandler, JSONOutputHandler, MemoryLifecycleService, MemoryContextProvider, MemoryBundleImportService, MemoryBundleExportService)
    ├── Types/ (MemoryFact, MemoryBundle, CostTypes, SDKMessageOutputHandler, RunCompleteContext)
    ├── Stores/ (FactStore)
    ├── Tools/ (现有)
    ├── Hooks/ (现有)
    └── Skills/ (现有)

AxionCLI (11.5K → ~6K 行)
    ├── API/ (AxionAPI — SDK 组件 + Axion 专属路由；ApiRunner — SSE 委托 SDK；SkillAPIRunner)
    ├── Commands/ (CLI 入口 — 薄 ArgumentParser 层)
    ├── Services/ (AgentBuilder, RunOrchestrator, RunLock — 桌面编排)
    ├── Memory/ (7 个桌面专属文件 — AppMemoryExtractor, AppMemoryFact, AppProfileAnalyzer, RunMemoryProcessor, FamiliarityTracker, TakeoverLearningService, TakeoverMarker)
    ├── MCP/ (MCPServerRunner 使用 SDK 的 AgentMCPServer)
    ├── Helper/ (HelperProcessManager — 子进程生命周期)
    ├── Skills/ (AxionBuiltInSkills — 桌面 Skill Prompt)
    └── IO/ (TakeoverIO, 终端输出)
```

## Verification

**Commands:**
- `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` — 预期：全部通过
- `find Sources/AxionCLI -name "*.swift" -exec wc -l {} + | tail -1` — 预期：≤ 6,000（所有阶段完成后）
- `swift build` — 预期：干净构建，无警告
