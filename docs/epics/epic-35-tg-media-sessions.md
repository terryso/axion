---
project_name: 'axion'
user_name: 'Nick'
date: '2026-06-03'
status: 'draft'
epic: 35
title: 'TG 会话管理与运行时控制'
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-tg-enhancement-hermes-parity/prd.md
  - docs/epics/epic-32-telegram-experience-upgrades.md
  - docs/epics/epic-34-tg-commands-runtime-control.md
---

# Epic 35: TG 会话管理与运行时控制

Axion TG 缺少会话管理命令：用户无法浏览历史会话、恢复旧会话、给会话命名、查看活跃 agent。本 Epic 利用 SDK 已有的 `SessionStore`（持久化）、`SessionMetadata`、`Agent.supportedModels()` 等能力补齐这些命令。

**SDK 能力验证结果：**

| 能力 | SDK 支持 | 来源 |
|------|---------|------|
| Session 持久化 | ✅ `SessionStore.save/load/list/rename` | `Stores/SessionStore.swift` |
| Session 元数据 | ✅ `SessionMetadata` (id, title, createdAt, model, messageCount) | `Types/SessionTypes.swift` |
| Session 恢复 | ✅ `SessionStore.load()` + `Agent(sessionId:)` | `Core/Agent.swift` |
| Token usage | ✅ `QueryResult.usage: TokenUsage` + `totalCostUsd` | `Types/AgentTypes.swift` |
| Reasoning/Effort | ✅ `AgentOptions.effort: EffortLevel?` (.low/.medium/.high/.max) | `Types/AgentTypes.swift` |

**已砍掉的 Story（SDK 不支持）：**

| 原 Story | 原因 | 所需 SDK 变更 |
|----------|------|--------------|
| 35.1 图片输入 | `CreateRunRequest` 只有 `task: String`，无附件字段 | 需要 SDK `CreateRunRequest` 新增 `attachments` 字段 |
| 35.2 语音输入 | 同上 | 同上 |
| 35.3 文档输入 | 同上 | 同上 |
| 35.4 /compress | `compactConversation` 是 private，无公开 API | 需要 SDK 暴露 `public func compact() throws` |
| 35.4 /undo | 只有文件级 `rewindFiles`，无对话级回退 | 需要 SDK 新增 `rewindMessages(count:)` |

这些 Story 移到远期 backlog，待 SDK 支持后再启动。

**FRs covered:** FR-TG-22 (/sessions), FR-TG-23 (/resume), FR-TG-24 (/title), FR-TG-26 (/agents)
**NFRs:** NFR-TG-7 (媒体下载容错) → 已砍掉
**依赖:** Epic 34（复用 TGCommandRegistry）

---

## Story 依赖关系

```
35.1 (/sessions, /resume) ── 独立
35.2 (/title) ── 独立
35.3 (/agents) ── 独立
```

所有 story 相互独立，可并行开发。

---

### Story 35.1: /sessions 和 /resume 命令

As a Axion Telegram 用户,
I want 浏览历史会话并恢复之前的会话,
So that 我能回到之前的上下文继续工作。

**SDK 能力：** `SessionStore.list() → [SessionMetadata]` 返回所有持久化 session；`SessionStore.load(sessionId:)` 加载完整 session 数据；`Agent` 初始化时可通过 `AgentOptions.sessionId` 恢复。

**Acceptance Criteria:**

**Given** 用户发送 `/sessions`
**When** `SessionStore.list()` 返回历史会话
**Then** 发送 inline keyboard 分页显示历史会话列表
**And** 每个按钮显示会话标题（`summary` 字段，或 `firstPrompt` 前 30 字符）和日期
**And** 每页最多 8 个会话，超过则显示分页按钮

**Given** 用户点击某个历史会话按钮
**When** callback 被处理
**Then** 显示该会话的摘要：轮数（`messageCount`）、最后活跃时间（`updatedAt`）、标题、使用的模型（`model`）
**And** 提供 "恢复" 和 "返回" 按钮

**Given** 用户发送 `/resume <session-id>` 或点击 "恢复" 按钮
**When** 目标会话在 `SessionStore` 中存在
**Then** 当前 chat 的 session 切换为目标 session
**And** 回复 "已恢复会话: {session_title}"
**And** 后续消息在该会话上下文中继续

**Given** 目标会话不存在或 `SessionStore.load()` 返回 nil
**When** 尝试恢复
**Then** 回复 "会话不存在或已过期"

**Given** `/sessions` 无历史会话
**When** `SessionStore.list()` 返回空数组
**Then** 回复 "没有历史会话"

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | 注册 `/sessions` 和 `/resume` 命令 |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` | 新增 `listSessions(page:) -> [SessionMetadata]`（调 `SessionStore.list()`）；新增 `resumeSession(chatId:sessionId:)`（更新 `chatSessions` 映射） |

---

### Story 35.2: /title 命令

As a Axion Telegram 用户,
I want 给当前会话命名,
So that 我能在会话列表中快速识别不同会话。

**SDK 能力：** `SessionStore.rename(sessionId:newTitle:)` 更新 session 的 summary 字段。

**Acceptance Criteria:**

**Given** 用户发送 `/title 工作日报分析`
**When** 当前 chat 有活跃 session（`chatSessions[chatId]` 存在）
**Then** 调用 `SessionStore.rename(sessionId:newTitle:)` 更新标题
**And** 回复 "会话已命名: 工作日报分析"

**Given** 用户发送 `/title` 不带参数
**When** 当前会话有标题
**Then** 显示当前标题
**And** 提示用法 "/title <名称>"

**Given** 用户发送 `/title ...` 但无活跃 session
**When** `chatSessions[chatId]` 不存在
**Then** 回复 "当前无活跃会话"

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | 注册 `/title` 命令 |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` | 新增 `setSessionTitle(chatId:title:)`：从 `chatSessions` 取 sessionId，调 `SessionStore.rename()` |

---

### Story 35.3: /agents 命令

As a Axion Telegram 用户,
I want 查看当前活跃的任务和 agent 状态,
So that 我知道哪些任务在运行、排队情况如何。

**Acceptance Criteria:**

**Given** 用户发送 `/agents`
**When** 有活跃任务（前台正在执行）
**Then** 列出当前任务：类型（前台）、状态（执行中）、运行时长
**And** 显示排队任务数量

**Given** 用户发送 `/agents`
**When** 无活跃任务
**Then** 回复 "无活跃任务"
**And** 显示上次任务完成时间（如果有）

**Given** 有排队任务
**When** `/agents` 回复
**Then** 在活跃任务信息后追加排队任务预览（前 50 字符）

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | 注册 `/agents` 命令 |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` | 新增 `activeAgentStatus(chatId:) -> AgentStatus`（包含 isProcessing、pendingCount、pendingPreviews、lastCompletedAt） |
