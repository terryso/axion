---
project_name: 'axion'
user_name: 'Nick'
date: '2026-06-03'
status: 'draft'
epic: 34
title: 'TG 命令与运行控制补强'
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-tg-enhancement-hermes-parity/prd.md
  - docs/epics/epic-32-telegram-experience-upgrades.md
  - docs/epics/epic-33-tg-experience-foundation.md
---

# Epic 34: TG 命令与运行控制补强

Axion TG 当前只有 7 个命令（help/commands/status/skills/new/queue/stop），而 Hermes 有 40+。用户无法在 TG 中切换模型、排队下一条 prompt、微调推理行为、重试失败任务。本 Epic 补齐高频命令和交互按钮粒度，将命令数从 7 扩展到 19，让 TG 成为完整的运行控制终端。

**FRs covered:** FR-TG-6 ~ FR-TG-16（共 11 个 FR）
**NFRs:** NFR-TG-4, NFR-TG-5, NFR-TG-6
**依赖:** Epic 32（TGCommandRegistry 基础设施）

**基础设施前置（RunOverrides 扩展）：**

Stories 34.2 (/model)、34.4 (/fast, /yolo)、36.3 (/reasoning) 需要运行时覆盖 AgentBuildConfig 的模型/推理力度/快速模式。当前 `AxionRuntime.RunOverrides` 缺少这些字段。需先完成：

| 变更 | 说明 |
|------|------|
| `AxionRuntime.RunOverrides` 新增 `modelOverride: String?`、`effortOverride: EffortLevel?`、`fastOverride: Bool?` | 运行时覆盖传递 |
| `TaskSerialQueue` 新增 per-chat `chatOverrides: [Int64: ChatOverrides]` | 每个 chat 独立存储覆盖 |
| `TaskSerialQueue.makeBuildConfig()` 读取 `chatOverrides` 注入到 `BuildConfig` | 应用覆盖 |

这是 34.2/34.4/36.3 的共享前置，应在 Story 34.1 之后、34.2 之前完成。

---

## Story 依赖关系

```
34.1 (/queue, /steer) ── 独立
RunOverrides 扩展 ──→ 34.2, 34.4, 36.3 共享前置
34.2 (/model picker) ──→ 依赖 RunOverrides 扩展
34.3 (/retry, /usage, /curator) ── 独立
34.4 (/fast, /yolo) ──→ 依赖 RunOverrides 扩展
34.5 (Approval scope 后端) ── 独立（UI 已实现 ~80%）
34.6 (Clarify "其他") ──→ ✅ 已实现，无需开发
```

建议实施顺序：34.1 → RunOverrides 扩展 → 34.2 → 34.3 → 34.4 → 34.5

---

### Story 34.1: /queue 写入模式 和 /steer 命令

As a Axion Telegram 用户,
I want 通过 `/queue <prompt>` 主动排队任务，或用 `/steer` 在下一条 queued prompt 前注入指令,
So that 我能精确控制任务队列，也能预先微调 agent 行为。

**与现有 `/queue` 的区别：**

现有 `/queue`（无参数）是只读状态查询，返回 "执行中/排队中/会话" 概览。本 Story 在此基础上新增 `/queue <prompt>` 写入模式——带参数时主动将 prompt 加入 FIFO 队列。两功能共用同一命令：

- `/queue` → 查看队列状态（已有，不变）
- `/queue 帮我检查测试结果` → 排队新任务（新增）

**`/steer` 设计约束（SDK 能力限制）：**

SDK `Agent` 没有 "mid-execution 注入指令到下一次工具调用" 的能力。`streamInput()` 可流式注入文本但语义不同（是新一轮 prompt，不是工具调用间的注入）。因此 `/steer` **降级为 prepend 到下一条 queued prompt**：

- 用户发 `/steer 优先使用 bash` → 指令暂存为 `steerBuffer`
- 当排队任务被执行时，steerBuffer 内容 prepend 到任务 prompt 前
- 相当于用户预先给 agent 加了一个前缀指令，效果类似但不完全等于 mid-execution steer

**Acceptance Criteria:**

**Given** 用户发送 `/queue 帮我检查测试结果`
**When** 当前有任务正在执行
**Then** prompt 被加入 `TaskSerialQueue` 的 FIFO 队列
**And** 回复 "已排队 (队列深度: 1)"
**And** 当前任务结束后自动执行排队任务

**Given** 用户发送 `/queue`（无参数）
**When** 调用已有命令逻辑
**Then** 返回当前队列状态（执行中/排队数/会话），行为与现有一致

**Given** 队列中有多条排队消息
**When** 用户发送 `/queue` 查看状态
**Then** 除了现有概览，还显示每条排队消息的预览（前 50 字符）

**Given** 用户发送 `/steer 优先使用 bash 工具`
**When** 有排队任务等待执行
**Then** 指令被暂存到 chat 的 `steerBuffer`
**And** 回复 "已设置 steer: 下次任务将前置指令「优先使用 bash 工具」"
**And** 排队任务执行时，steerBuffer 内容 prepend 到 prompt 前
**And** steerBuffer 在使用后清空

**Given** 用户发送 `/steer ...` 但没有排队任务
**When** 当前任务正在执行且无排队
**Then** 指令暂存到 `steerBuffer`，等下一条消息（用户发送或 `/queue`）时生效
**And** 回复 "已设置 steer: 将在下次任务生效"

**Given** steerBuffer 已设置，用户发送普通文本消息（非命令）
**When** 消息被提交为任务
**Then** steerBuffer 内容 prepend 到消息文本前
**And** steerBuffer 清空

**Given** `/queue <prompt>` 排队深度无限
**When** 用户连续排队 10 条消息
**Then** 每条都显示当前队列深度
**And** 不限制排队数量

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | 修改现有 `queueDef` handler：检测参数，有参数时调用 `enqueueNext(chatId:prompt:)`；注册 `/steer` 新命令 |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` | 新增 `enqueueNext(chatId:prompt:)` 显式排队方法（与自动排队 `enqueue()` 复用同一 FIFO 队列）；新增 `steerBuffer: [Int64: String]` 按 chat 暂存 steer 指令；`enqueueNext()` 执行时检查并 prepend steerBuffer |
| `Sources/AxionCLI/Services/Telegram/TGCommandRouter.swift` | 注册 `/steer` 命令路由 |

---

### Story 34.2: /model 交互式选择器

As a Axion Telegram 用户,
I want 通过 inline keyboard 选择模型，而不是手动输入模型名,
So that 我能快速切换模型，不需要记住模型 ID。

**SDK 能力说明：**

SDK `MODEL_PRICING` 是扁平 dict（key = model ID），`ModelInfo` 无 provider 字段。因此 model picker 采用**单级列表 + 分页**设计，不使用两級 provider→model 选择器。

**前置依赖：** RunOverrides 扩展（新增 `modelOverride` 字段）

**Acceptance Criteria:**

**Given** 用户发送 `/model`
**When** 系统有可用模型（从 `Agent.supportedModels()` 或 `AxionConfig` 获取）
**Then** 发送 inline keyboard 分页显示所有可用模型
**And** 每个按钮显示 `ModelInfo.displayName`
**And** 当前使用的模型按钮标注 ✅
**And** 每页最多 8 个模型，超过则显示 "下一页" 按钮

**Given** 用户点击某个模型按钮
**When** 模型切换成功
**Then** 更新当前 chat 的 `chatOverrides.modelOverride`
**And** 编辑选择器消息为 "已切换到 {model_name}"
**And** 下次消息发送时使用新模型

**Given** 用户点击 "下一页" 按钮
**When** 还有更多模型
**Then** 编辑消息显示下一页模型列表
**And** 提供 "上一页" 和 "下一页" 按钮

**Given** model picker callback 处理失败
**When** inline keyboard 回调出错
**Then** fallback 为文字列表：直接回复可用模型列表

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | 注册 `/model` 命令 |
| `Sources/AxionCLI/Services/Telegram/TGModelPicker.swift` | NEW — 构建单级分页 inline keyboard；处理 `mp:` 前缀的 callback query |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` | 使用 `chatOverrides` 存储 modelOverride |

**Callback data 编码：**

```
mm:{page}:{modelId}          → 选择该模型（page 用于返回）
mn:{page}                    → 下一页
mp:{page}                    → 上一页
mx                           → 取消选择
```

总长度 ≤ 64 字节（TG 限制）。

---

### Story 34.3: /retry、/usage、/curator 命令

As a Axion Telegram 用户,
I want 重试上一条消息、查看 token 用量、管理 Curator,
So that 我能快速重发失败的任务、监控成本、手动触发技能整理。

**基础设施说明：**

- `/retry` 需要消息历史追踪——当前 `ActiveSession` 不记录用户消息。需在 `TaskSerialQueue` 新增 `chatLastUserMessage: [Int64: String]`，每次 `enqueue()` 时更新
- `/usage` 需要累积 token——`QueryResult` 有 `usage: TokenUsage` + `totalCostUsd`，但 `ActiveSession` 不记录。需在 `ActiveSession` 新增 `accumulatedUsage: TokenUsage` + `totalCostUsd: Double`，每次 run 完成后累加
- `/curator` 已有 CLI 实现（`CuratorCommand` + `IntelligentCurator` + `SkillCuratorStore`），需在 Gateway 上下文中暴露调用入口

**Acceptance Criteria:**

**Given** 用户发送 `/retry`
**When** 当前 chat 有历史消息记录
**Then** 重发该 chat 的最后一条用户消息给 agent
**And** agent 重新执行该请求
**And** 回复 "正在重试..."

**Given** 用户发送 `/retry` 但没有历史消息
**When** chat 无可重试消息
**Then** 回复 "没有可重试的消息"

**Given** 用户发送 `/usage`
**When** 当前 session 有 token 使用记录
**Then** 回复当前会话的 token 使用量：输入/输出/总计
**And** 显示预估成本（基于配置的模型单价）
**And** 显示 session 开始时间

**Given** 用户发送 `/usage` 但当前无活跃 session
**When** 无 session 数据
**Then** 回复 "当前无活跃会话"

**Given** 用户发送 `/curator status`
**When** Curator 有历史记录
**Then** 回复上次运行时间、运行结果摘要、下次计划运行时间
**And** 显示技能库统计（总数/活跃/归档）

**Given** 用户发送 `/curator run`
**When** 触发手动运行
**Then** 异步启动 Curator
**And** 回复 "Curator 已启动"
**And** 运行完成后推送结果摘要

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | 注册 `/retry`、`/usage`、`/curator` 命令 |
| `Sources/AxionCLI/Services/Telegram/TGCommandRouter.swift` | 路由三个命令 |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` | 新增 `lastUserMessage(chatId:) -> String?`；新增 `sessionUsage(chatId:) -> TokenUsage?` |

---

### Story 34.4: /reload-skills、/fast、/yolo 命令

As a Axion Telegram 用户,
I want 重新加载技能、切换快速模式、跳过审批,
So that 我能动态调整 agent 行为而不需要重启 gateway。

**前置依赖：** RunOverrides 扩展（新增 `fastOverride` 字段）

**`/fast` 实现方式：** SDK `ModelInfo.supportsFastMode` 是查询能力而非控制。`RunConfig` 已有 `fast: Bool` 字段但当前硬编码为 `false`。`/fast` 通过 `chatOverrides.fastOverride` 覆盖 `BuildConfig.fast`。

**Acceptance Criteria:**

**Given** 用户发送 `/reload-skills`
**When** skill 目录中有新文件或变更
**Then** 重新扫描 `~/.axion/skills/` 目录
**And** 回复 "已重新加载技能 (N 个技能)"
**And** 列出加载的技能名称

**Given** 用户发送 `/reload-skills`
**When** 扫描出错（权限问题等）
**Then** 回复错误摘要
**And** 不影响已加载的技能

**Given** 用户发送 `/fast`
**When** 当前快速模式为关闭
**Then** 切换为开启
**And** 回复 "快速模式: ✅ 开启（下次消息生效）"

**Given** 用户再次发送 `/fast`
**When** 当前快速模式为开启
**Then** 切换为关闭
**And** 回复 "快速模式: ❌ 关闭"

**Given** 用户发送 `/yolo`
**When** 当前审批模式为正常
**Then** 切换为跳过审批
**And** 回复 "YOLO 模式: ✅ 开启（所有危险操作自动通过）"

**Given** 用户再次发送 `/yolo`
**When** 当前 YOLO 模式为开启
**Then** 切换回正常审批
**And** 回复 "YOLO 模式: ❌ 关闭"

**Given** 快速模式和 YOLO 模式是 session 级别
**When** 用户新建 session（`/new`）
**Then** 模式重置为默认值（关闭）

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | 注册 `/reload-skills`、`/fast`、`/yolo` 命令 |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` | 新增 `setFastMode(chatId:enabled:)`、`setYoloMode(chatId:enabled:)`；session 级别存储 |
| `Sources/AxionCore/Models/AxionConfig.swift` | 无新增配置（模式是运行时 session 状态，不持久化） |

---

### Story 34.5: Exec Approval scope 后端逻辑

**已部分实现：** UI 已有 4 个按钮（Allow Once / Session / Always / Deny），callback data 已编码 scope（`approve:once:{id}`、`approve:session:{id}`、`approve:always:{id}`）。但后端 handler 忽略了 scope——统一传 `"approved"` 不区分范围。

本 Story 只需补 scope 后端逻辑。

As a Axion Telegram 用户,
I want 审批按钮的 once/session/always 范围真正生效,
So that 我不需要每次都手动审批相同的操作。

**Acceptance Criteria:**

**Given** 用户点击 `Allow Once`
**When** 本次审批被通过
**Then** 仅允许当前这一次执行
**And** 下次相同命令仍需审批
**And** 审批消息更新为 "✅ 已允许（本次）"

**Given** 用户点击 `Session`
**When** 本次审批被通过
**Then** 当前 session 内相同命令自动通过
**And** 审批消息更新为 "✅ 已允许（本次会话）"
**And** 新 session（`/new`）后恢复审批

**Given** 用户点击 `Always`
**When** 本次审批被通过
**Then** 所有 session 内相同命令永久自动通过
**And** 审批消息更新为 "✅ 已允许（永久）"
**And** 记录到白名单配置

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` | `processCallback()` 的 `.approve` 分支：读取 `callbackData.detail`（scope），传 `context` 为 `"approved:\(scope)"` |
| `Sources/AxionCLI/Services/Telegram/TGInteractiveSessionStore.swift` | 新增 `sessionApprovals: [String: Set<String>]` 追踪 session 级别白名单；新增 `alwaysApprovals: Set<String>` 持久化白名单 |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` | 审批前检查 session/always 白名单，匹配时自动通过不弹审批 |

---

### ~~Story 34.6: Clarify "其他" 输入模式~~ — 已实现

**已由现有代码完全实现：**

- `TGInteractiveSessionStore.buildKeyboard(for: .clarify)` 已追加 "Type Answer" 按钮（`TGCallbackAction.respond`）
- `TelegramAdapter.processCallback()` 的 `.respond` 分支将 clarify 切换为 `.textCapture` 模式
- `TelegramAdapter.pollLoop()` 第 98 行已拦截 `.textCapture` 模式的文本消息并路由到 clarify handler
- TTL 通过 `TGInteractionSession.isExpired` 处理
- 与 Epic 33 Story 33.2 TGTextBatcher 的路由优先级已正确：pollLoop 先检查 textCapture 再喂给 batcher

无需额外开发。
