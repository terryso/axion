---
title: 'Phase 6: RunCommand 重构 — SDK 对齐'
type: 'refactor'
created: '2026-05-19'
baseline_commit: '0d41a22'
status: 'in-progress'
context:
  - '{project-root}/docs/phase6-runcommand-refactor.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## 意图

**问题：** RunCommand.run() 约 530 行，混合了 CLI 解析、Memory 生命周期、费用追踪、技能路由、Tool Pair 收集、运行后分析——全部挤在一个方法里。违反架构定义的"薄 CLI 层"原则，难以独立测试或修改。

**方案：** 利用 SDK 0.4.0 的新能力（`toolPairs`、`maxModelCalls`、`onRunComplete`）将 RunCommand 瘦身至 ~250-300 行（CLI 参数 + TakeoverIO + 终端输出）。其余逻辑下沉到 AgentBuilder（技能注册）和新服务 `RunMemoryProcessor`（Memory/Takeover 后处理）。

## 边界与约束

**始终遵守：**
- Memory 操作保持非致命（do/catch 包裹，失败仅 warning 日志）
- 所有现有 CLI 参数（--no-memory, --no-skills, --no-visual-delta, --fast, --dryrun, --json 等）继续正常工作
- SeatMonitor 暂留在 RunCommand stream loop 中（桌面专属，不归 SDK 管）
- VisualDeltaTracker 暂留在 RunCommand stream loop 中（桌面专属）
- Package.swift SDK 依赖从 0.3.8 升级到 0.4.0

**需先确认：**
- 对 SDK 0.4.0 公共 API 的任何修改
- 是否完全删除 CostTracker（而非原地简化）

**绝不：**
- 修改 ApiRunner（后续单独重构）
- 新增 CLI 参数或改变用户可见行为
- 改变 JSON 输出格式或终端输出格式

</frozen-after-approval>

## 代码地图

- `Sources/AxionCLI/Commands/RunCommand.swift` -- 主要重构目标（共 ~1014 行，run() 在 L69-598）
- `Sources/AxionCLI/Services/AgentBuilder.swift` -- 吸收 RunCommand 中的技能注册逻辑
- `Sources/AxionCLI/Services/CostTracker.swift` -- 简化：移除 model call 计数，保留 screenshot 计数 + 费用汇总
- `Sources/AxionCLI/Memory/MemoryLifecycleService.swift` -- 现有生命周期逻辑（晋升/降级/重新激活）
- `Sources/AxionCLI/Memory/AppMemoryExtractor.swift` -- 从 tool pairs 提取记忆
- `Sources/AxionCLI/Memory/AppProfileAnalyzer.swift` -- 运行后 Profile 分析
- `Sources/AxionCLI/Memory/FamiliarityTracker.swift` -- 运行后熟悉度追踪
- `Sources/AxionCLI/Memory/TakeoverLearningService.swift` -- 运行后接管学习
- `Sources/AxionCLI/Memory/MemoryCleanupService.swift` -- 运行前清理
- `Sources/AxionCLI/Memory/MemoryFactStore.swift` -- Fact 持久化
- `Sources/AxionCLI/Services/SkillLookupService.swift` -- 技能预解析（待删除）
- `Sources/AxionCLI/Services/SeatActivityMonitor.swift` -- 不变，保留在 stream loop
- `Sources/AxionCLI/Services/VisualDeltaTracker.swift` -- 不变，保留在 stream loop
- `Package.swift` -- 升级 SDK 依赖至 0.4.0

## 任务与验收

**执行任务：**

- [x] `Package.swift` -- 升级 SDK 依赖 `from: "0.3.8"` → `from: "0.4.0"`，执行 `swift package resolve` -- 引入包含 toolPairs/maxModelCalls/onRunComplete 的 SDK 0.4.0

- [x] `Sources/AxionCLI/Commands/RunCommand.swift` + `Sources/AxionCLI/Services/SkillLookupService.swift` -- **Phase 6A：删除技能预解析。** 删除双轨技能查找代码块（L82-148：`SkillLookupService.parseSkillInvocation` + 三路 switch）。彻底删除 `SkillLookupService.swift` 文件。SDK 的 `SkillTool` 现在通过 agent loop 自动处理技能调用。保留技能注册代码块（L70-80）但移入 AgentBuilder。

- [x] `Sources/AxionCLI/Commands/RunCommand.swift` + `Sources/AxionCLI/Services/AgentBuilder.swift` -- **Phase 6A：技能注册移入 AgentBuilder。** 将 RunCommand L70-80 的技能发现+注册代码移入 `AgentBuilder.build()`。在 AgentBuilder 内部创建并填充 `SkillRegistry`（`noSkills` 时跳过）。从 `BuildConfig.forCLI()` 参数中移除 `skillRegistry`——由 AgentBuilder 自行创建。

- [x] `Sources/AxionCLI/Commands/RunCommand.swift` -- **Phase 6A：用 SDK toolPairs 替换手动 Tool Pair 收集。** 删除 `pendingToolUses`/`collectedPairs` 声明（L275-276）和 stream loop 中的 pair 匹配逻辑（L312-348 toolUse/toolResult 分支中的配对收集代码）。改为从 `.result` 消息的 `ResultData.toolPairs` 直接读取。

- [x] `Sources/AxionCLI/Commands/RunCommand.swift` -- **Phase 6B：用 SDK maxModelCalls 替换 CostTracker 的 model call 逻辑。** 从 `.assistant` 分支删除 `costTracker.recordModelCall()` 调用（L325-332）。删除 `budgetExceeded` 追踪。通过 BuildConfig 在 AgentOptions 上设置 `maxModelCalls`。CostTracker 仅保留 screenshot 计数 + 费用汇总。简化 `CostTracker`：移除 `maxModelCalls` 参数和 `recordModelCall()` 方法。

- [x] `Sources/AxionCLI/Memory/RunMemoryProcessor.swift`（新建）-- **Phase 6B：抽取 RunMemoryProcessor。** 创建新服务，封装 RunCommand L471-584 中所有内联的运行后 Memory 逻辑：记忆提取、Fact 提取/合并、Profile 分析、熟悉度追踪、接管学习。提供单一 `processRunResult()` 方法，接收 tool pairs、task、runId、memoryStore、memoryDir、takeover event、运行结果标志、externally-modified 标志。所有操作保持非致命。

- [x] `Sources/AxionCLI/Commands/RunCommand.swift` -- **Phase 6B：将 RunMemoryProcessor 接入 onRunComplete。** 通过 BuildConfig 在 AgentOptions 上设置 SDK 的 `onRunComplete` 回调，调用 `RunMemoryProcessor.processRunResult()`。备选方案（若 onRunComplete 仅支持同步）：在 stream loop 结束后直接调用 RunMemoryProcessor，使用从 `.result` 消息提取的 `toolPairs`。删除内联 Memory 代码（L471-584）。

- [x] `Sources/AxionCLI/Commands/RunCommand.swift` -- **Phase 6B：运行前 Memory 清理移入 RunMemoryProcessor。** 将 Memory 清理逻辑（L237-260：过期条目清理 + Fact 降级）抽取到 `RunMemoryProcessor.preRunCleanup()`，由 RunCommand 调用。

- [x] `Sources/AxionCLI/Services/CostTracker.swift` -- **Phase 6B：简化 CostTracker。** 移除 `maxModelCalls` init 参数、`recordModelCall()`、`currentModelCallCount`、`modelCallsExceeded` case。保留 `recordScreenshot()`、`finalizeWithSDKData()`、`getSummary()`、`getTelemetry()`。更新 `CostSummary` 使 `modelCalls` 来自 SDK 数据而非手动计数。

- [x] `Sources/AxionCLI/Commands/RunCommand.swift` -- **Phase 6B：SeatMonitor 检查从 stream loop 的 assistant 分支移出。** SeatMonitor 创建仍在 RunCommand，但将活跃度检查移出 `.assistant` 消息处理器。改为 stream 结束后检查一次，或在 message-type switch 外定期检查。（SeatMonitor 按架构仍为 RunCommand 关注点，只是位置更清晰。）

- [x] 所有变更文件 -- **验证编译和单元测试通过。**

**验收标准：**
- Given RunCommand.run() 被调用，when agent stream 结束，then tool pairs 来自 `ResultData.toolPairs`（非手动收集）
- Given 设置了 `--max-model-calls N`，when 达到 N 次 LLM 调用，then SDK 终止运行（非 Axion 的 CostTracker）
- Given 有 tool pairs 的成功运行，when stream 结束，then RunMemoryProcessor 处理所有 memory 提取、fact 保存、profile 分析、熟悉度追踪和接管学习
- Given `--no-memory` 参数，when 运行结束，then 不执行任何 memory 操作
- Given `--no-skills` 参数，when 构建 agent，then 不进行技能注册且不添加 SkillTool
- Given 重构后的代码，when 编译通过，then RunCommand.run() 低于 350 行
- Given 现有单元测试，when 执行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"`，then 所有测试通过

## Spec 变更日志

## 设计说明

**onRunComplete 同步/异步考量：** SDK 的 `onRunComplete` 回调可能是同步的。若 Memory 操作需要 async（通过 actor 进行文件 I/O），需在回调内用 `Task { }` 包装，或退而使用 stream loop 结束后调用 RunMemoryProcessor、从 `.result` 消息提取 `toolPairs` 的方式。实现时选择能编译且正确工作的方案。

**SkillRegistry 所有权变更：** 当前 RunCommand 创建 SkillRegistry 并传给 AgentBuilder。重构后 AgentBuilder 拥有 SkillRegistry 的创建权。RunCommand 的 `BuildConfig.forCLI()` 不再接收 `skillRegistry`——由内部创建。

## 验证

**命令：**
- `swift build` -- 预期：SDK 0.4.0 下编译通过
- `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` -- 预期：所有单元测试通过
