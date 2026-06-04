---
title: 'ReviewScheduler: 会话级累积触发 + 全量消息审查 + 持久化恢复'
type: 'feature'
created: '2026-06-04'
status: 'in-progress'
baseline_commit: 'a6cc6e3'
context:
  - '{project-root}/_bmad-output/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## 意图

**问题：** Review 触发条件基于单任务的 `totalSteps`（不可预测），review 只看当前单次任务的消息（无法跨任务累积偏好），gateway 重启后所有累积状态丢失。

**方案：** 重构 ReviewScheduler，改为会话级累积 user turn 计数触发（对齐 Hermes），传入全量会话历史给 review agent，持久化 chatId→session 映射以支持 gateway 重启恢复。

## 边界与约束

**始终遵守：**
- `GatewaySessionStore` 使用 `actor`（线程安全状态隔离）
- 复用 SDK 的 `SessionStore` 加载 transcript — 不自建消息累积
- Review agent 工具白名单不变（仅 memory + skill，无 MCP/Helper）
- Review 执行使用 detached task（非阻塞，NFR57）
- 降级策略：`gateway-sessions.json` 缺失时，从 SessionStore transcript 恢复计数，公式 `turnsSinceMemory = userTurnCount % nudgeInterval`（保持节奏，不立即触发）
- `nudgeInterval` 从 `AxionConfig.gatewayMemoryNudgeInterval` 读取（默认 4），与现有 config 体系一致

**需先确认：**
- 修改默认 `nudgeInterval`（当前 4）为其他值

**绝不：**
- 修改 SDK 的 `ReviewOrchestrator.shouldReview()` — Axion 自主决定触发时机
- 创建新数据库 — 使用 JSON 文件持久化
- 对 resume 任务触发 review — 仅新 user turn 计入触发计数
- 在 `gateway-sessions.json` 中存储消息内容 — 仅存元数据（sessionIds、计数）

## I/O 与边界场景矩阵

| 场景 | 输入 / 状态 | 预期输出 / 行为 | 错误处理 |
|------|------------|----------------|----------|
| 第 4 个新 user turn | `turnsSinceMemory` 达到 4 | 触发 review，计数器重置为 0 | N/A |
| 30 分钟内 resume 任务 | `shouldResume=true` | `turnsSinceMemory` 不递增 | N/A |
| Gateway 重启 | `gateway-sessions.json` 存在 | 加载状态，从持久化值继续计数 | JSON 损坏 → 从零开始，记录 warning |
| Gateway 重启，无 JSON | 重启后首条消息 | 从 transcript 数 user role 消息 → `turnsSinceMemory = count % nudgeInterval` | 无 transcript → 从 0 开始 |
| /new 命令 | 用户发送 `/new` | `clearSession(chatId)` 重置该会话所有状态 | N/A |
| Review 触发 | 加载全量会话消息 | Review agent 看到该 chatId 下所有 session 的消息 | Transcript 加载失败 → 跳过该 session，继续 |
| 多会话并发 | 两个 chatId 同时活跃 | 各自独立的 turn 计数器和 session 列表 | N/A |

</frozen-after-approval>

## 代码地图

- `Sources/AxionCLI/Services/Gateway/GatewaySessionStore.swift` -- 新增：actor，持久化 chatId→会话状态到 `~/.axion/gateway-sessions.json`
- `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` -- 集成 GatewaySessionStore，追踪 turn 计数，传递 review 触发标志
- `Sources/AxionCLI/Services/ReviewScheduler.swift` -- 构造注入 GatewaySessionStore；从 context 读取触发标志，通过 SessionStore 加载全量会话消息
- `Sources/AxionCLI/Services/EventHandlerContext.swift` -- 新增 `chatId: Int64?`、`shouldReviewMemory: Bool`、`shouldReviewSkills: Bool` 字段
- `Sources/AxionCLI/Services/DaemonRuntimeManager.swift` -- 透传 chatId 和 review 标志到 AxionRuntime
- `Sources/AxionCLI/Services/AxionRuntime.swift` -- 将 chatId/review 标志传入 EventHandlerContext
- `Sources/AxionCLI/Commands/GatewayCommand.swift` -- gateway 启动时创建并注入 GatewaySessionStore
- `Sources/AxionCore/Models/AxionConfig.swift` -- 新增 `gatewayMemoryNudgeInterval: Int`（默认 4）
- `Tests/AxionCLITests/Services/Gateway/GatewaySessionStoreTests.swift` -- 新增：持久化 actor 单元测试

## 任务与验收

**执行：**
- [ ] `Sources/AxionCore/Models/AxionConfig.swift` -- 新增 `gatewayMemoryNudgeInterval: Int`（默认 4），使用 `decodeIfPresent + ?? 4` 模式保持向后兼容
- [ ] `Sources/AxionCLI/Services/Gateway/GatewaySessionStore.swift` -- 创建 actor，含 `ChatSessionState`（sessionIds、userTurnCount、turnsSinceMemory、lastActivityAt），JSON 持久化，recordTurn/resetMemoryCounter/clearSession/hydrateFromTranscripts 方法；`hydrateFromTranscripts` 遍历 session transcript 数 user role 消息，`turnsSinceMemory = userTurnCount % nudgeInterval`
- [ ] `Sources/AxionCLI/Services/EventHandlerContext.swift` -- 新增 `chatId: Int64?`、`shouldReviewMemory: Bool`、`shouldReviewSkills: Bool` 字段（默认值：nil/false/false）
- [ ] `Sources/AxionCLI/Services/DaemonRuntimeManager.swift` -- `executeRun()`/`resumeRun()` 增加 `chatId: Int64?`、`shouldReviewMemory: Bool`、`shouldReviewSkills: Bool` 参数，透传给 AxionRuntime
- [ ] `Sources/AxionCLI/Services/AxionRuntime.swift` -- execute() 接受 chatId/shouldReviewMemory/shouldReviewSkills，传入 `dispatchToHandlers()` 中 EventHandlerContext 的构造
- [ ] `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` -- 注入 GatewaySessionStore，非 resume 的 enqueue 时递增 turns，计算 shouldReview，传递给 runtimeManager，执行后记录 sessionId，每次状态变更后持久化
- [ ] `Sources/AxionCLI/Services/ReviewScheduler.swift` -- 构造注入 GatewaySessionStore 引用；用 `context.shouldReviewMemory` 替代 `orchestrator.shouldReview()` 调用；触发时从 GatewaySessionStore 获取 sessionIds，从 SessionStore 加载 transcript（`[String: Any]` 字典需转换为 `SDKMessage`），合并为全量消息列表；移除 orchestrator.shouldReview() 依赖
- [ ] `Sources/AxionCLI/Commands/GatewayCommand.swift` -- gateway 启动时创建 GatewaySessionStore，调用 `load()` 加载持久化状态，注入 TaskSerialQueue init
- [ ] `Tests/AxionCLITests/Services/Gateway/GatewaySessionStoreTests.swift` -- 测试 recordTurn、resetMemoryCounter、clearSession、持久化 round-trip、hydrateFromTranscripts（含 `% nudgeInterval` 取模恢复）

**验收标准：**
- Given 同一 chatId 连续入队 4 个非 resume 任务，when 第 4 个完成，then 触发 review 并传入全量会话历史
- Given gateway 重启且 `gateway-sessions.json` 存在，when 新任务到达，then 从持久化值继续计数
- Given gateway 重启且无 `gateway-sessions.json`，when 该 chatId 有历史 transcript 且含 7 条 user role 消息，then `turnsSinceMemory = 7 % 4 = 3`（不立即触发，再发 1 条才触发）
- Given `/new` 命令，when clearSession 被调用，then 该 chatId 的所有状态重置
- Given `gateway-sessions.json` 损坏或缺失且无 transcript，when gateway 启动，then 从零开始（不崩溃）

## 规格变更日志

## 设计笔记

**触发决策从 ReviewScheduler 移至 TaskSerialQueue。** TaskSerialQueue 知道 chatId 和任务是否为 resume — 它是计数 user turn 的自然位置。ReviewScheduler 变为纯执行者："context 说要 review → 加载全量消息 → 跑 review agent。"

**chatId 透传链路：** TaskSerialQueue → DaemonRuntimeManager.executeRun(chatId:shouldReviewMemory:shouldReviewSkills:) → AxionRuntime.execute(chatId:shouldReviewMemory:shouldReviewSkills:) → EventHandlerContext(chatId:shouldReviewMemory:shouldReviewSkills:)。每层只透传，不持有逻辑。

**消息组装：** Review 触发时，ReviewScheduler 通过构造注入的 GatewaySessionStore 引用调用 `state(for: chatId)` 获取所有 sessionIds，然后从 `SessionStore`（已在 EventHandlerContext 中）加载每个 transcript 并拼接。SessionStore 返回的 messages 是 `[String: Any]` 字典，需转换为 `SDKMessage`（检查 `role` 字段映射）。无需内存中累积消息。

**恢复策略取模：** 从 transcript 恢复时使用 `turnsSinceMemory = userTurnCount % nudgeInterval`（对齐 Hermes 的 `% preserves 1-in-N cadence`），避免恢复后立即触发 review。

**nudgeInterval 配置：** 新增 `AxionConfig.gatewayMemoryNudgeInterval`（默认 4），走现有 config 体系的 `decodeIfPresent + ?? default` 模式。TaskSerialQueue 从注入的 config 读取。

## 验证

**命令：**
- `swift build` -- 预期：干净构建，无错误
- `swift test --filter "AxionCLITests.Services.Gateway.GatewaySessionStoreTests"` -- 预期：所有测试通过
- `swift test --filter "AxionCLITests.Services" --filter "AxionCLITests.Models"` -- 预期：无回归
