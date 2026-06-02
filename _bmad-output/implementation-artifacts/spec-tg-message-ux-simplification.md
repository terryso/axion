---
title: 'TG 消息 UX 简化'
type: 'feature'
created: '2026-06-01'
status: 'done'
baseline_commit: '9dc5266'
context:
  - '{project-root}/_bmad-output/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## 意图

**问题：** Telegram 回复仍然过于嘈杂。一个简单的用户请求目前会产生一条独立的开始消息、进度气泡中可见的工具执行细节，某些情况下最终回答仍然包含原始 MCP `Input` / `Output` 转录内容。

**方案：** 将 Telegram UX 简化为用户期望的静默路径：无冗余开始横幅、一个轻量级进度界面、以及仅包含用户有意义内容的最终回答。Hermes 是"静默聊天，详细日志"的产品参考标杆。

## 边界与约束

**始终遵守：**
- 当任务已通过流式/状态气泡展示进度时，移除常规的 Telegram 执行开始推送（`"任务开始执行: ..."`）。
- 保持队列通知、超时/失败消息、`/new` 和会话恢复行为不变，除非本次清理明确更改了面向用户的文案。
- 确保工具进度文本保持简洁，永不显示原始工具输入、原始工具输出、`Built-in Tool`、`Input:`、`Output:`、`*_result_summary` 或 `*Executing on server...*`。
- 强化最终结果清洗，支持混合转录格式，包括 MCP 块前后的散文文本。
- 仅更改 Telegram 相关逻辑；不修改 CLI / 通知 / HTTP 输出界面。
- 仅使用 Swift Testing 单元测试覆盖 UX 契约。

**需先确认：** 无。

**禁止：**
- 不移除有意义的失败投递或审批/澄清交互。
- 不添加重复已编辑气泡的第二个执行进度通道。
- 不将原始 MCP 转录内容作为后备暴露给 Telegram。

## I/O 与边缘用例矩阵

| 场景 | 输入 / 状态 | 预期输出 / 行为 | 错误处理 |
|----------|--------------|----------------------|----------------|
| 常规 TG 任务 | 用户发送文本任务；流式传输已启用 | 无独立开始消息；用户看到一个进度气泡和一个干净的最终回答 | 不适用 |
| MCP 密集型最终文本 | `resultText` 包含散文与 MCP 转录块混合内容 | 最终 Telegram 回复剥离转录块，仅保留有用回答 | 若清洗无法确认某块内容，优先返回最安全的已清洗散文，而非回显原始转录 |
| 编辑回退 | 进度气泡无法再编辑 | 回退投递仍使用静默措辞并隐藏原始 MCP 转录 | 复用现有的追加/回退路径，不崩溃 |

</frozen-after-approval>

## 代码地图

- `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` -- 在流式传输开始前发送当前的独立开始消息。
- `Sources/AxionCLI/Services/Telegram/TGStreamingController.swift` -- 负责可见的进度措辞、工具摘要和最终包装文案。
- `Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift` -- 负责 Telegram 特定的结果清洗辅助方法；原始 MCP 转录泄漏需在此修复。
- `Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift` -- 验证开始消息 / 队列 UX。
- `Tests/AxionCLITests/Services/Telegram/TGStreamingControllerTests.swift` -- 验证进度气泡和最终格式化行为。
- `Tests/AxionCLITests/Services/Telegram/TGEventHandlerTests.swift` -- 验证转录剥离和结果提取边缘用例。

## 任务与验收

**执行：**
- [x] `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` -- 停止在流式传输开始前发送常规 TG 执行开始横幅 -- 移除用户反馈的首条低价值消息。
- [x] `Sources/AxionCLI/Services/Telegram/TGStreamingController.swift` -- 简化进度/最终文案，使 Telegram 显示一个轻量级状态气泡，包含简洁的工具措辞和更干净的最终回答包装 -- 让聊天体验更接近 Hermes.
- [x] `Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift` -- 强化 Telegram 结果清洗，即使原始 MCP 转录块与模型散文混合也能被剥离 -- 修复天气示例泄漏。
- [x] `Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift` -- 更新移除开始横幅后的预期，同时保留队列通知覆盖。
- [x] `Tests/AxionCLITests/Services/Telegram/TGStreamingControllerTests.swift` -- 为更安静的进度/最终措辞和回退行为添加覆盖。
- [x] `Tests/AxionCLITests/Services/Telegram/TGEventHandlerTests.swift` -- 添加报告的天气风格转录及类似交错夹具，锁定转录剥离行为。

**验收标准：**
- 给定用户发送常规 Telegram 文本请求，当 Axion 开始处理时，用户不会在进度气泡出现前收到单独的 `"任务开始执行: ..."` 消息。
- 给定代理在 Telegram 任务中使用工具，当显示进度文本时，可见进度保持简洁，不暴露原始工具输入、原始工具输出或内部工具传输措辞。
- 给定 `AgentCompletedEvent.resultText` 包含交错的 MCP 转录段（如 `Built-in Tool`、`Input:`、`Output:`、`*_result_summary` 或 `*Executing on server...*`），当 Axion 发送最终 Telegram 回答时，这些段落被移除，仅保留用户有意义的回答。
- 给定进度投递从编辑模式回退到追加模式，当后续进度或最终文本被发送时，追加消息仍遵循静默 Telegram 措辞，不暴露原始 MCP 转录内容。

## 规格变更日志

## 设计说明

本规格的拆分版本仅保持一个目标：**静默的 Telegram 任务消息**。更广泛的 Hermes 对等想法（如表情反应或通知模式调优）被推迟。实现应将已编辑的进度气泡视为主要执行界面，并将日志作为详细诊断的位置。

## 验证

**命令：**
- `swift test --filter "AxionCLITests.Services.Gateway.TaskSerialQueueTests"` -- 预期：TG 队列/开始消息测试通过新的静默生命周期行为
- `swift test --filter "AxionCLITests.Services.Telegram.TGStreamingControllerTests"` -- 预期：TG 进度/最终格式化测试通过简化的措辞
- `swift test --filter "AxionCLITests.Services.Telegram.TGEventHandlerTests"` -- 预期：混合 MCP 转录夹具被正确剥离
- `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` -- 预期：单元测试套件保持绿色，不运行集成测试

## 建议的审查顺序

**执行生命周期**

- 从移除的独立 TG 开始横幅和保留的队列通知路径开始。
  [`TaskSerialQueue.swift:83`](../../Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift#L83)

- 查看工具优先运行现在如何创建相同的静默预览气泡。
  [`TGStreamingController.swift:199`](../../Sources/AxionCLI/Services/Telegram/TGStreamingController.swift#L199)

**进度和回退行为**

- 审查更安静的预览/最终传输和编辑失败时的追加回退。
  [`TGStreamingController.swift:331`](../../Sources/AxionCLI/Services/Telegram/TGStreamingController.swift#L331)

- 审查文本到达 Telegram 之前的最终回答清洗管道。
  [`TGEventHandler.swift:176`](../../Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift#L176)

- 确认最新结果提取优先选择用户有意义的回答文本。
  [`TGEventHandler.swift:368`](../../Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift#L368)

**配套测试**

- 验证队列行为对首个任务保持静默但仍通知排队工作。
  [`TaskSerialQueueTests.swift:358`](../../Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift#L358)

- 验证工具启动预览创建和编辑失败后的追加回退。
  [`TGStreamingControllerTests.swift:136`](../../Tests/AxionCLITests/Services/Telegram/TGStreamingControllerTests.swift#L136)

- 验证转录剥离防护、多行结果和短终端回答。
  [`TGEventHandlerTests.swift:374`](../../Tests/AxionCLITests/Services/Telegram/TGEventHandlerTests.swift#L374)

- 审查群聊会话隔离的推迟后续工作备注。
  [`deferred-work.md:46`](deferred-work.md#L46)
