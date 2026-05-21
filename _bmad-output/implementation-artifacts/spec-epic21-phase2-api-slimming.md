---
title: 'Epic 21 Phase 2: SDK 路由扩展 + RunResponse 丰富化 + API 精简'
type: 'refactor'
created: '2026-05-21'
status: 'done'
baseline_commit: '2da5a59'
baseline_lines: 10146
target_lines: 9500
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-epic21-continued-slimming.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## 意图

**问题：** AxionCLI 当前 10,146 行，距 8,000 行目标差 2,146 行。`AxionAPI.swift`（989 行）重复实现了 health、runs CRUD、SSE 等通用 agent 服务器路由，这些应该由 SDK 提供。SDK 的 `RunResponse` 只有 5 个字段（run_id/status/task/created_at/updated_at），缺少任何 agent 都应有的通用字段（步骤数、耗时、成功/失败、错误信息、步骤列表、费用追踪等），迫使 Axion 自行维护 `StandardTaskOutput`（16 字段）和完整的 runs 路由处理。`APITypes.swift`（521 行）重复了 SDK 类型。Memory 目录中 `FamiliarityTracker`（58 行）与 `AppProfileAnalyzer` 有职责重叠。

**方案：** (1) 丰富 SDK `RunResponse`，加入通用 agent 字段（步骤数、耗时、成功/失败、错误、步骤列表、费用、结果、intervention 等）。(2) 在 SDK `AgentHTTPServer` 增加 `customRouteBuilder` + `runHandler` 扩展点。SDK 处理所有标准路由，Axion 通过钩子注入执行逻辑和自定义路由。(3) 删除 Axion 重复类型和路由。(4) 合并 `FamiliarityTracker`。目标：AxionCLI ≤ 9,500 行。

## 边界与约束

**必须：**
- 所有现有 API 端点的路径和 HTTP 方法保持不变
- SDK `RunResponse` 丰富化后，AxionBar 无需修改即可获得更完整的运行数据
- AxionHelper 不做修改
- 每个 Phase 完成后所有单元测试通过

**先确认：**
- 无

**绝不：**
- 将 Axion 桌面特有字段（`live`、`allow_foreground`、`criteria`）移入 SDK
- 破坏 SDK `AgentHTTPServer` 的独立使用能力（SDK 测试必须仍然通过）
- 修改 SDK 现有字段的名称或语义（仅增加新字段）

</frozen-after-approval>

## 代码地图

**SDK 需要修改的文件：**
- `../open-agent-sdk-swift/Sources/OpenAgentSDK/HTTP/AgentHTTPServer.swift`（294 行）— 增加 `customRouteBuilder` 和 `runHandler` 钩子，暴露内部组件
- `../open-agent-sdk-swift/Sources/OpenAgentSDK/HTTP/APITypes.swift`（277 行）— 丰富 `RunResponse`，增加 `CreateRunRequest.allowForeground`
- `../open-agent-sdk-swift/Sources/OpenAgentSDK/HTTP/` — 可能需要新增 `StepSummary`、`CostTelemetry` 等通用类型（若 SDK 尚无）

**Axion 需要精简的文件：**
- `Sources/AxionCLI/API/AxionAPI.swift`（989 行）— 删除所有 runs/health/SSE 路由（SDK 处理）。仅保留 Settings + Skills + Capabilities 路由。目标：~400 行。**（-589 行）**
- `Sources/AxionCLI/API/Models/APITypes.swift`（521 行）— 删除 `HealthResponse`、`APIErrorResponse`、`RunOptions`（用 SDK 类型），`StandardTaskOutput` 改为 typealias 或扩展 SDK `RunResponse` + 3 个 Axion 专属字段，移除手写 `init(from:)`。目标：~440 行。**（-81 行）**
- `Sources/AxionCLI/Commands/ServerCommand.swift`（121 行）— 创建 SDK `AgentHTTPServer`，设置钩子。目标：~90 行。**（-31 行）**
- `Sources/AxionCLI/Memory/FamiliarityTracker.swift`（58 行）— 合并入 `AppProfileAnalyzer`。**（-58 行）**
- `Sources/AxionCLI/Memory/AppProfileAnalyzer.swift`（308 行）— 吸收 familiarity 逻辑。**（+15 行净增）**

**参考文件：**
- `Sources/AxionCLI/API/RunCoordinator.swift`（157 行）— 包装 SDK 组件
- `Sources/AxionCLI/API/ApiRunner.swift`（316 行）— Agent 执行逻辑
- `Sources/AxionBar/Models/RunModels.swift`（193 行）— AxionBar 响应模型（`decodeIfPresent` 兼容）

## 任务与验收

**Phase A：SDK RunResponse 丰富化（SDK 侧）**

- [ ] `../open-agent-sdk-swift/Sources/OpenAgentSDK/HTTP/APITypes.swift` — 丰富 `RunResponse`，增加通用 agent 字段（全部 optional，向后兼容）：`totalSteps`、`durationMs`、`ok`、`error`、`steps: [StepSummary]?`、`startedAt`、`endedAt`、`costTelemetry`、`result`、`intervention`、`exitCode`、`schemaVersion`。保留现有 5 个字段不变。
- [ ] `../open-agent-sdk-swift/Sources/OpenAgentSDK/HTTP/APITypes.swift` — 新增或复用 SDK 中已有的通用类型：`StepSummary`（index/tool/purpose/success）、`CostTelemetry`、`AgentResult`（kind/title/body）、`InterventionData`（reason/availableActions/blockingIssue）。检查 SDK 已有哪些，避免重复。
- [ ] `../open-agent-sdk-swift/Sources/OpenAgentSDK/HTTP/APITypes.swift` — 给 `CreateRunRequest` 增加 `public var allowForeground: Bool?`（默认 nil）。
- [ ] SDK 的 `executeRun` 更新：在 agent 执行过程中收集 steps/duration/cost 等数据，填充到 `RunResponse`。

**Phase B：SDK 路由扩展钩子（SDK 侧）**

- [ ] `../open-agent-sdk-swift/Sources/OpenAgentSDK/HTTP/AgentHTTPServer.swift` — 增加 `public var customRouteBuilder: ((Router<BasicRequestContext>, RunTracker, EventBroadcaster, RunPersistenceService, ConcurrencyLimiter) -> Void)?`。在 `registerRoutes` 末尾调用。
- [ ] `../open-agent-sdk-swift/Sources/OpenAgentSDK/HTTP/AgentHTTPServer.swift` — 增加 `public var runHandler: ((String, CreateRunRequest, RunTracker, EventBroadcaster, RunPersistenceService, ConcurrencyLimiter) async -> Void)?`。设置后 POST /v1/runs 调用此闭包替代内置执行。为 nil 时保持现有行为。
- [ ] SDK 回归：验证无钩子时行为与之前完全一致。

**Phase C：AxionAPI 精简 — 删除所有重复路由（-589 行）**

- [ ] `Sources/AxionCLI/API/AxionAPI.swift` — 删除全部 SDK 已处理的路由：`GET /v1/health`、`POST /v1/runs`、`GET /v1/runs`、`GET /v1/runs/:runId`、`GET /v1/runs/:runId/events`。仅保留 Settings（~117 行）、Skills（~302 行）、Capabilities（~18 行）路由。
- [ ] `Sources/AxionCLI/API/AxionAPI.swift` — 将剩余路由重构为 `AxionAPI.registerCustomRoutes(on:tracker:broadcaster:persistenceService:limiter:config:skillRegistry:)`，签名匹配 `customRouteBuilder`。
- [ ] `Sources/AxionCLI/Commands/ServerCommand.swift` — 创建 `AgentHTTPServer`，设置 `runHandler` → ApiRunner 执行管线，设置 `customRouteBuilder` → `AxionAPI.registerCustomRoutes`。移除手动 router 组装。
- [ ] `Sources/AxionCLI/API/RunCoordinator.swift` — `submitRun(task:options:)` → `submitRun(task:request:)`，直接使用 SDK `CreateRunRequest`。

**Phase D：APITypes 去重（-81 行）**

- [ ] `Sources/AxionCLI/API/Models/APITypes.swift` — 删除 `HealthResponse`，`typealias HealthResponse = OpenAgentSDK.HealthResponse`。
- [ ] `Sources/AxionCLI/API/Models/APITypes.swift` — 删除 `APIErrorResponse`，`typealias APIErrorResponse = OpenAgentSDK.APIErrorResponse`。
- [ ] `Sources/AxionCLI/API/Models/APITypes.swift` — 删除 `RunOptions`，所有用法替换为 `CreateRunRequest`。
- [ ] `Sources/AxionCLI/API/Models/APITypes.swift` — `StandardTaskOutput` 重构：如果 SDK `RunResponse` 已包含 13 个通用字段，则 `StandardTaskOutput` 仅需扩展 3 个 Axion 专属字段（`live`、`allowForeground`、`criteria`）。考虑 typealias + extension 或包装模式。删除 `StepSummary`、`CostTelemetry` 等已移入 SDK 的重复类型。
- [ ] `Sources/AxionCLI/API/Models/APITypes.swift` — 尝试移除手写 `init(from:)`（如 Codable 自动合成可行）。

**Phase E：Memory 目录整合（-43 行）**

- [ ] `Sources/AxionCLI/Memory/AppProfileAnalyzer.swift` — 吸收 `FamiliarityTracker.checkAndUpdateFamiliarity(domain:store:)` 到 `analyze()`。
- [ ] 删除 `Sources/AxionCLI/Memory/FamiliarityTracker.swift`（58 行）。
- [ ] 更新 `RunMemoryProcessor.swift`：替换 `FamiliarityTracker()` 为 `AppProfileAnalyzer` 内联调用。

**验收标准：**
- Given `swift build`，编译通过，无新增 error
- Given `swift test`，所有单元测试通过（排除已知的 StdoutPurity 预存失败）
- Given `Sources/AxionCLI/`，行数总计 ≤ 9,500
- Given SDK `AgentHTTPServer` 无钩子初始化，行为与之前完全一致
- Given `axion server --port 4242`，所有 HTTP 端点响应包含通用 agent 字段（steps/duration/ok/error 等），AxionBar 无信息损失

## Spec 变更记录

## 设计笔记

### SDK RunResponse 丰富化策略

当前 SDK `RunResponse` 只有 5 个字段（run_id/status/task/created_at/updated_at）。丰富化后增加的通用字段全部设为 optional，确保向后兼容：

```
现有（必填）：run_id, status, task, created_at, updated_at
新增（optional）：total_steps, duration_ms, ok, error, steps,
  started_at, ended_at, cost_telemetry, result, intervention,
  exit_code, schema_version
```

SDK 的 `executeRun` 在 agent 执行过程中收集这些数据。当 `runHandler` 被设置时（如 Axion 的 AgentBuilder），`runHandler` 负责调用 `tracker.updateRun()` 填充这些字段。

### SDK runHandler 钩子

```swift
server.runHandler = { task, request, tracker, broadcaster, persistence, limiter in
    let buildResult = await AgentBuilder.build(...)
    await RunOrchestrator.execute(buildResult, task: task)
    // RunOrchestrator 内部调用 tracker.updateRun() 填充丰富字段
}
```

为 nil 时 SDK 用内置执行（单一 agent），独立使用不受影响。

### AxionBar 完全兼容

SDK `RunResponse` 丰富化后包含 AxionBar `BarRunStatusResponse` 所需的全部通用字段（run_id、status、task、total_steps、duration_ms、ok、error、steps 等）。AxionBar 的 `decodeIfPresent` 会自然读取这些字段。3 个 Axion 专属字段（`live`、`allow_foreground`、`criteria`）优雅降级为 nil，不影响核心功能。

**不需要覆写任何 SDK 路由。** AxionAPI 仅保留 Settings/Skills/Capabilities 自定义路由。

### StandardTaskOutput 重构

`StandardTaskOutput` 当前 16 字段，其中 13 个将移入 SDK `RunResponse`。重构选项：
- **选项 A**：`typealias StandardTaskOutput = OpenAgentSDK.RunResponse`，Axion 仅在使用处补充 3 个 Axion 专属字段
- **选项 B**：保留 `StandardTaskOutput` 作为 `RunResponse` 的扩展类型（extension + 额外字段）

根据实际 Codable 约束选择最简方案。

### 行数预算

| 文件 | 当前 | 目标 | 节省 |
|------|------|------|------|
| AxionAPI.swift | 989 | 400 | -589 |
| APITypes.swift | 521 | 440 | -81 |
| ServerCommand.swift | 121 | 90 | -31 |
| FamiliarityTracker.swift | 58 | 0 | -58 |
| AppProfileAnalyzer.swift | 308 | 323 | +15 |
| **AxionCLI 总计** | **10,146** | **~9,402** | **-744** |

保守估计：-744 行 → 9,402 行。低于 9,500 目标。

## 验证

**命令：**
- `swift build` — 期望：编译通过
- `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` — 期望：全部通过
- `find Sources/AxionCLI -name "*.swift" -exec wc -l {} + | tail -1` — 期望：≤ 9,500

## Suggested Review Order

**入口：SDK 钩子集成**

- ServerCommand 用 SDK AgentHTTPServer + runHandler + customRouteBuilder 替代手动路由组装
  [`ServerCommand.swift:58`](../../Sources/AxionCLI/Commands/ServerCommand.swift#L58)

**AxionAPI 精简（-589 行）**

- 删除全部 SDK 已处理路由后，仅保留 registerCustomRoutes（Settings/Skills/Capabilities）
  [`AxionAPI.swift:15`](../../Sources/AxionCLI/API/AxionAPI.swift#L15)

**APITypes 去重（-81 行）**

- SDK 类型别名替代本地重复定义，保留 Axion 专属类型
  [`APITypes.swift:5`](../../Sources/AxionCLI/API/Models/APITypes.swift#L5)

**RunCoordinator（新文件）**

- 包装 SDK 组件的 Axion 专属 run 跟踪 actor
  [`RunCoordinator.swift:1`](../../Sources/AxionCLI/API/RunCoordinator.swift#L1)

**Memory 整合**

- FamiliarityTracker 逻辑内联到 RunMemoryProcessor，删除原文件
  [`RunMemoryProcessor.swift:154`](../../Sources/AxionCLI/Memory/RunMemoryProcessor.swift#L154)

**RunOrchestrator 精简**

- 移除 TraceRecorder 依赖，改用 SDK MessageOutputHandler 收集 tool pairs
  [`RunOrchestrator.swift:34`](../../Sources/AxionCLI/Services/RunOrchestrator.swift#L34)

**AgentBuilder 对齐**

- BuildConfig.forAPI 签名从 RunOptions 改为 CreateRunRequest
  [`AgentBuilder.swift:73`](../../Sources/AxionCLI/Services/AgentBuilder.swift#L73)

**ApiRunner 对齐**

- runAgent/runSkillAgent 签名对齐 SDK 类型
  [`ApiRunner.swift:28`](../../Sources/AxionCLI/API/ApiRunner.swift#L28)

**已删除文件**

- `AxionRunTracker.swift`（153 行）、`AxionRunPersistence.swift`（148 行）、`TraceRecorder.swift`（308 行）、`FamiliarityTracker.swift`（58 行）

**测试重写**

- 路由测试改用 SDK buildTestApplication() + buildTestContext() 模式
  [`AxionAPIRoutesTests.swift:12`](../../Tests/AxionCLITests/API/AxionAPIRoutesTests.swift#L12)
