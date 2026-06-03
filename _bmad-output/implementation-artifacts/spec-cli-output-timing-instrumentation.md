---
title: 'CLI 输出耗时统计'
type: 'feature'
created: '2026-06-03'
status: 'done'
context: []
baseline_commit: '9223206'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 多步骤任务（run、gateway）耗时较长，但 CLI 日志中没有任何耗时信息，无法定位瓶颈在 LLM 请求、工具执行还是构建阶段。

**Approach:** 在 `SDKTerminalOutputHandler` 的工具调用和 LLM 请求环节添加毫秒级耗时输出，同时在 `RunOrchestrator` 的构建/Review/Curator 阶段添加耗时日志。仅影响 CLI 日志输出，不改变 TG 返回给用户的消息。

## Boundaries & Constraints

**Always:**
- 耗时信息仅出现在 CLI 日志（stderr/stdout）和 JSON 输出中
- TG 消息、通知消息不变
- 使用 `ContinuousClock` 计时（与现有代码一致）
- 耗时格式统一用 `XXXms`（< 1s）或 `X.Xs`（≥ 1s）

**Ask First:** 无

**Never:**
- 不修改 TG 返回消息内容
- 不修改 OpenAgentSDK 内部代码
- 不新增 CLI flag 或配置项

## I/O & Edge-Case Matrix

| 场景 | 输入/状态 | 预期输出 | 错误处理 |
|------|----------|---------|---------|
| 工具调用完成 | `.toolUse` 后收到 `.toolResult` | `[axion] 结果: ... [123ms]` | 无匹配的 toolUseId 时跳过耗时 |
| LLM 首次响应 | 运行开始后首个 `.assistant`/`.partialMessage` | 在 `.assistant` 前输出 `[axion] LLM: [2.3s]` | 无 |
| LLM 后续响应 | `.toolResult` 后首个 `.assistant`/`.partialMessage` | 同上 | 无 |
| Agent 构建完成 | `AgentBuilder.build()` 返回 | `[axion] 构建完成 [1.2s]` | 构建失败不输出耗时 |
| Review 完成 | Review agent 返回结果 | `[axion] Review: ... [3.5s]` | Review 失败/跳过不输出耗时 |
| JSON 模式 | `--json` | JSON 中包含 timing 字段 | 同上 |

</frozen-after-approval>

## Code Map

- `Sources/AxionCLI/Commands/SDKOutputHandlers.swift` -- `SDKTerminalOutputHandler` 和 `SDKJSONOutputHandler`，主要修改目标，添加工具和 LLM 计时
- `Sources/AxionCLI/Services/RunOrchestrator.swift` -- 主执行循环，添加构建/Review/Curator 阶段耗时输出
- `Sources/AxionCLI/Commands/RunCommand.swift` -- CLI 入口，传递 build 开始时间
- `Sources/AxionCLI/API/RunCoordinator.swift` -- Gateway/API 入口，同样需要构建耗时
- `Sources/AxionCLI/Services/AxionRuntime.swift` -- Runtime 层，build 和 execute 调用点

## Tasks & Acceptance

**执行：**
- [x] `Sources/AxionCLI/Commands/SDKOutputHandlers.swift` -- 在 `SDKTerminalOutputHandler` 中添加 `toolStartTimes: [String: ContinuousClock.Instant]` 和 `llmWaitStart: ContinuousClock.Instant?`，在 `.toolResult` 时计算并显示工具耗时，在 `.assistant`/`.partialMessage` 时计算并显示 LLM 等待耗时 -- 这是核心变更，直接解决用户需求中的工具和 LLM 耗时
- [x] `Sources/AxionCLI/Commands/SDKOutputHandlers.swift` -- 在 `SDKJSONOutputHandler` 中添加工具耗时和 LLM 耗时到 JSON 输出的 steps 数组中 -- JSON 模式下也能看到耗时
- [x] `Sources/AxionCLI/Services/RunOrchestrator.swift` -- 在 `execute()` 方法中，对 review 和 curator 阶段用 `ContinuousClock` 包裹，完成时输出耗时 -- 补充定位 post-run 阶段瓶颈
- [x] `Sources/AxionCLI/Services/AxionRuntime.swift` -- 在 `execute()` 方法中，对 `builder.build()` 调用添加耗时输出 `[axion] 构建完成 [X.Xs]` -- 定位构建阶段耗时
- [x] `Sources/AxionCLI/Commands/RunCommand.swift` -- 无需修改，build 耗时由 AxionRuntime 输出 -- 确认不需要额外修改

**验收标准：**
- Given `axion run` 执行多步骤任务，when 工具调用完成，then 日志显示 `[axion] 结果: ... [XXXms]`
- Given `axion run` 执行任务，when LLM 返回响应，then 日志显示 `[axion] LLM: [X.Xs]`
- Given `axion run --json` 执行任务，when 完成，then JSON 输出中 steps 包含 duration_ms 字段
- Given agent 构建完成，then 日志显示 `[axion] 构建完成 [X.Xs]`
- Given Review/Curator 执行完成，then 日志显示对应阶段耗时

## Spec Change Log

## Design Notes

**计时方式：** 使用 `SDKMessage` 流内联计时而非 EventBus 事件，因为：
1. Output handler 直接处理消息流，无需额外管道
2. 端到端耗时包含 SDK 开销，对用户定位瓶颈更实用
3. 不依赖 EventBus 是否已连接

**耗时格式：** `< 1000ms` 用 `XXXms`，`≥ 1s` 用 `X.Xs`，与现有通知中的 `耗时 Xs` 风格统一。

**LLM 计时触发点：** `displayRunStart` 设置初始等待计时；每次 `.toolResult` 处理后重置等待计时；下次 `.assistant` 或首个 `.partialMessage` 到达时输出耗时并清除计时。

## Verification

**命令：**
- `swift build` -- expected: 编译成功
- `swift test --filter "AxionCLITests"` -- expected: 所有单元测试通过

## Suggested Review Order

**工具调用和 LLM 耗时（核心变更）**

- SDKTerminalOutputHandler 添加 toolStartTimes 和 llmWaitStart 计时，工具结果和 LLM 响应时输出耗时
  [`SDKOutputHandlers.swift:15`](../../Sources/AxionCLI/Commands/SDKOutputHandlers.swift#L15)

- .assistant 和 .partialMessage 处理 LLM 等待计时
  [`SDKOutputHandlers.swift:34`](../../Sources/AxionCLI/Commands/SDKOutputHandlers.swift#L34)

- .toolUse 记录开始时间，.toolResult 计算并输出耗时
  [`SDKOutputHandlers.swift:50`](../../Sources/AxionCLI/Commands/SDKOutputHandlers.swift#L50)

- formatDuration 辅助方法（ms/s 自适应格式）
  [`SDKOutputHandlers.swift:149`](../../Sources/AxionCLI/Commands/SDKOutputHandlers.swift#L149)

**JSON 模式耗时输出**

- SDKJSONOutputHandler 添加 toolStartTimes、llmTimings、duration_ms 到 steps
  [`SDKOutputHandlers.swift:168`](../../Sources/AxionCLI/Commands/SDKOutputHandlers.swift#L168)

- llm_timings 字段写入最终 JSON
  [`SDKOutputHandlers.swift:282`](../../Sources/AxionCLI/Commands/SDKOutputHandlers.swift#L282)

**构建和后处理耗时**

- AxionRuntime.execute() 添加 builder.build() 计时
  [`AxionRuntime.swift:186`](../../Sources/AxionCLI/Services/AxionRuntime.swift#L186)

- AxionRuntime.resumeSession() 添加构建计时
  [`AxionRuntime.swift:379`](../../Sources/AxionCLI/Services/AxionRuntime.swift#L379)

- RunOrchestrator review 阶段计时
  [`RunOrchestrator.swift:341`](../../Sources/AxionCLI/Services/RunOrchestrator.swift#L341)

- RunOrchestrator curator 阶段计时
  [`RunOrchestrator.swift:396`](../../Sources/AxionCLI/Services/RunOrchestrator.swift#L396)

- formatReviewSummary/formatCuratorSummary 签名扩展（向后兼容默认参数）
  [`RunOrchestrator.swift:766`](../../Sources/AxionCLI/Services/RunOrchestrator.swift#L766)
