---
title: "Telegram Enhancement: Hermes Parity & Interactive Experience"
status: draft
created: 2026-06-03
updated: 2026-06-03
project: axion
author: Nick + John (PM)
source: hermes-agent 对标分析
---

# Telegram Enhancement: Hermes Parity & Interactive Experience

## Problem Statement

Axion 的 Telegram Gateway 在 Epic 29-32 中搭建了核心骨架：长轮询通信、流式推送、命令注册表、基础 inline keyboard（approve/confirm/clarify/skills 分页）。但与 Hermes 的 TG 体验相比，差距仍然显著：

1. **命令太少** — 7 个命令 vs Hermes 的 40+ 个。用户无法在 TG 中做运行时配置（切换模型、调推理力度、快速模式）和会话管理（retry、undo、compress）
2. **没有多媒体输入** — 只处理文本，图片/语音/视频/文档/贴纸全部忽略
3. **批处理缺失** — 快速连续发消息会触发多个 agent run，浪费资源
4. **交互按钮粒度不够** — exec approval 没有 once/session/always 分级，clarify 没有"其他（手动输入）"，model picker 不存在
5. **通知噪音** — 流式推送每条 edit 都弹通知，刷屏严重
6. **状态反馈弱** — 没有 reaction 标记处理进度，用户不知道消息是否在被处理
7. **流式溢出不优雅** — 超长消息没有 edit-overflow-split（编辑后超出 4096 字符时的续接机制）

## Vision

将 Axion TG 从"能用"升级到"好用"：补齐 Hermes 的核心交互能力，让 TG 成为真正的远程桌面控制终端。

**三个核心目标：**
- **控制力** — 用户可在 TG 中切换模型、排队任务、微调运行、管理会话
- **丰富输入** — 支持图片/语音/文档等非文本输入，利用 agent 的多模态能力
- **体验打磨** — 通知静默、状态 reaction、消息批处理、溢出续接

## Existing Infrastructure

Epic 29-32 已交付的 TG 能力：

| 组件 | 位置 | 状态 |
|------|------|------|
| `TelegramAdapter` | Services/TelegramAdapter.swift | ✅ 长轮询 + send/edit/delete |
| `TGStreamingController` | Services/Telegram/TGStreamingController.swift | ✅ Edit-based 流式推送 |
| `TGCommandRegistry` | Services/Telegram/TGCommandRegistry.swift | ✅ 命令注册表 |
| `TGCommandRouter` | Services/Telegram/TGCommandRouter.swift | ✅ 命令路由 |
| `TGMessageFormatter` | Services/Telegram/TGMessageFormatter.swift | ✅ MarkdownV2/HTML/Plain 三重降级 |
| `TGInteractiveSessionStore` | Services/Telegram/TGInteractiveSessionStore.swift | ✅ Inline keyboard state 管理 |
| `TGErrorSanitizer` | Services/Telegram/TGErrorSanitizer.swift | ✅ API 错误分类 |
| `TGModels` | Services/Telegram/TGModels.swift | ✅ TG API Codable 模型 |
| 7 个命令 | GatewayCommand.swift | ✅ help/commands/status/skills/new/queue/stop |
| approve/confirm/clarify 按钮 | TGInteractiveSessionStore | ✅ 基础实现 |

## Gap Analysis: Hermes vs Axion

### 命令差距

**Axion 已有（7 个）：** /help, /commands, /status, /skills, /new, /queue, /stop

**需要补充的命令（按优先级）：**

#### P1 — 高频核心

| 命令 | 功能 | Hermes 参考 |
|------|------|-------------|
| `/model` | 交互式模型选择（inline keyboard picker） | `send_model_picker()` + `_handle_model_picker_callback()` |
| `/queue <prompt>` | 排队下一条 prompt（不中断当前 run） | `gateway/run.py:7596` |
| `/steer <prompt>` | 在下一次工具调用后注入指令 | `gateway/run.py:7620` |
| `/retry` | 重试上一条消息 | `CommandDef("retry", ...)` |
| `/curator` | Curator 状态管理（status/run） | `CommandDef("curator", ...)` |
| `/reload-skills` | 重新扫描技能目录 | `CommandDef("reload-skills", ...)` |
| `/usage` | 显示当前会话 token 使用量 | `CommandDef("usage", ...)` |

#### P2 — 会话管理

| 命令 | 功能 | Hermes 参考 |
|------|------|-------------|
| `/compress` | 压缩对话上下文 | `CommandDef("compress", ...)` |
| `/undo [N]` | 回退 N 轮对话 | `CommandDef("undo", ...)` |
| `/sessions` | 浏览历史会话 | `CommandDef("sessions", ...)` |
| `/resume [name]` | 恢复之前的会话 | `CommandDef("resume", ...)` |
| `/title [name]` | 给会话命名 | `CommandDef("title", ...)` |
| `/background <prompt>` | 后台运行任务 | `CommandDef("background", ...)` |
| `/agents` | 查看活跃 agent 和运行中任务 | `CommandDef("agents", ...)` |

#### P3 — 配置调优

| 命令 | 功能 | Hermes 参考 |
|------|------|-------------|
| `/fast` | 切换快速模式 | `CommandDef("fast", ...)` |
| `/reasoning` | 控制推理力度 | `CommandDef("reasoning", ...)` |
| `/yolo` | 跳过危险命令审批 | `CommandDef("yolo", ...)` |
| `/verbose` | 循环切换工具进度显示 | `CommandDef("verbose", ...)` |
| `/footer` | 切换运行时元信息 footer | `CommandDef("footer", ...)` |

### 交互能力差距

| 功能 | Hermes 实现 | Axion 现状 | 优先级 |
|------|------------|-----------|--------|
| **Model Picker** | 两级下钻：Provider → Model 分页，inline keyboard | ❌ 不存在 | P1 |
| **Exec Approval 粒度** | once/session/always/deny 四级按钮 | ✅ 有基础，但粒度只有 approve/deny | P1 |
| **Clarify "其他"** | 选项按钮 + "Other" 触发文字输入模式 | ❌ 没有手动输入选项 | P1 |
| **Slash Confirm** | 破坏性操作前置确认 | ✅ 有基础实现 | P2 |
| **Update Prompt** | 新版本提示 + inline button | ❌ 不存在 | P3 |

### 体验差距

| 功能 | Hermes 实现 | Axion 现状 | 优先级 |
|------|------------|-----------|--------|
| **通知静默** | streaming/status/tool_progress 全部 `disable_notification=True` | ❌ 所有消息弹通知 | P0 |
| **Reaction 状态** | 👀 处理中 → ✅ 完成 / 👎 失败 | ❌ 没有 reaction | P1 |
| **文本批处理** | 自适应延迟（180-240ms），快速到达的消息合并 | ❌ 每条消息独立触发 agent | P1 |
| **图片批处理** | `media_group_id` 识别相册，0.8s 合并 | ❌ 不存在 | P2 |
| **溢出续接** | edit 超长时自动续接为 reply thread | ❌ split 后直接发新消息 | P1 |
| **Follow-up Grace** | 运行开始 3s 内的消息排队不中断 | ❌ 不存在 | P1 |
| **多媒体输入** | 图片/语音/视频/文档/贴纸/位置，全类型下载缓存 | ❌ 只处理文本 | P2 |
| **Sticker 分析** | 视觉分析 + 缓存 | ❌ 不存在 | P3 |
| **DM Topics** | 私信中创建 Forum Topic 隔离多会话 | ❌ 不存在 | P3 |
| **群聊支持** | @mention 触发、白名单、observe 模式 | ❌ 不存在 | P3 |
| **Voice TTS** | 回复转语音发送 | ❌ 不存在 | P3 |

## Proposed Epics

### Phase 13: Telegram 体验对齐

---

### Epic 33: TG 基础体验补强 — 通知、批处理、状态反馈

**目标：** 消除 TG 使用中最大的体验痛点：通知刷屏、消息碎片化、缺乏处理状态反馈。

| Story | 标题 | 内容 | 依赖 |
|-------|------|------|------|
| 33.1 | 通知静默模式 | streaming/edit/status 消息全部 `disable_notification=true`，仅最终回复和审批弹通知。新增 `_notification_kwargs()` 方法，返回 `[String: Any]` 含 `disable_notification`。在 `TelegramAdapter.send()` 和 `editMessage()` 中传入。 | 无 |
| 33.2 | 消息批处理（Text Batching） | 短时间内到达的多条文本消息合并为一条 agent 输入。实现 `TGTextBatcher`：基于 `chatId` 分组，自适应延迟（短消息 200ms，长消息 300ms）。在 `TelegramAdapter.pollLoop()` 中拦截文本消息，batcher 聚合后统一提交。 | 无 |
| 33.3 | Follow-up Grace Window | Agent 开始运行后 N 秒（默认 3s，可配置）内的消息不中断，而是排队合并。在 `GatewayRunner` 中检查 `_running_agents_ts`，grace period 内的消息 enqueue 到 pending queue。 | 33.2（共用批处理基础设施） |
| 33.4 | Reaction 状态反馈 | 处理开始时给用户消息加 👀 reaction，完成时替换为 ✅ 或 👎，取消时清除。新增 `TelegramAdapter.setReaction(chatId:messageId:emoji:)` 和 `clearReactions()`。在 `onProcessingStart` / `onProcessingComplete` 钩子中调用。 | 无 |
| 33.5 | Edit Overflow Split | 流式编辑时如果 MarkdownV2 渲染后超过 4096 字符，自动将溢出部分作为 reply-to 续接消息发送。增强 `TGStreamingController` 的 `_finalizeChunk` 方法，检测溢出并拆分。 | 无 |

**FRs:** FR-TG-1 (通知静默), FR-TG-2 (消息批处理), FR-TG-3 (Follow-up Grace), FR-TG-4 (Reaction 状态), FR-TG-5 (溢出续接)

**NFRs:**
- NFR-TG-1: 通知静默模式下，仅最终回复和需要用户操作的审批弹通知，其余全部静默
- NFR-TG-2: 两条消息间隔 < 300ms 时自动合并，减少无效 agent turn
- NFR-TG-3: Reaction 设置失败不阻塞主流程（catch + warning 日志）

---

### Epic 34: TG 命令与运行控制补强

**目标：** 补齐高频命令，让用户在 TG 中有完整的运行控制能力。

| Story | 标题 | 内容 | 依赖 |
|-------|------|------|------|
| 34.1 | `/queue` 和 `/steer` 命令 | `/queue <prompt>` 排队下一条 prompt（FIFO），`/steer <prompt>` 在下一次工具调用后注入指令。扩展 `TaskSerialQueue` 支持 FIFO 队列和 steer 注入点。在 `TGCommandRegistry` 注册两个新命令。 | 无 |
| 34.2 | `/model` 交互式选择器 | 两级 inline keyboard：先选 Provider（如有多个），再分页选 Model。实现 `send_model_picker()` + `_handle_model_picker_callback()`。模型列表从 `AxionConfig` 的已知模型 + 环境变量读取。回调后更新 session 的模型覆盖。 | 无 |
| 34.3 | `/retry`、`/usage`、`/curator` 命令 | `/retry` 重发上一条消息到 agent；`/usage` 显示当前会话 token 用量；`/curator status/run` 查看/触发 Curator。在 `TGCommandRegistry` 注册。 | 无 |
| 34.4 | `/reload-skills`、`/fast`、`/yolo` 命令 | `/reload-skills` 重新扫描 `~/.axion/skills/`；`/fast` 切换快速模式（下次消息生效）；`/yolo` 跳过审批。在 `TGCommandRegistry` 注册。 | 无 |
| 34.5 | Exec Approval 粒度升级 | 将现有的 approve/deny 二级按钮升级为 once/session/always/deny 四级。更新 `TGInteractiveSessionStore` 的 approval state 管理，callback 处理器映射到 session 级别的 approval 策略。 | 无 |
| 34.6 | Clarify "其他" 输入模式 | 给 clarify 按钮追加 "✏️ 其他" 选项。用户点击后进入文字输入模式，下一条消息被截获为 clarify 回复（而非新任务）。在 `GatewayRunner` 的消息分发中添加 clarify-awaiting-text 拦截。 | 无 |

**FRs:** FR-TG-6 (/queue), FR-TG-7 (/steer), FR-TG-8 (/model picker), FR-TG-9 (/retry), FR-TG-10 (/usage), FR-TG-11 (/curator), FR-TG-12 (/reload-skills), FR-TG-13 (/fast), FR-TG-14 (/yolo), FR-TG-15 (approval 粒度), FR-TG-16 (clarify 其他)

**NFRs:**
- NFR-TG-4: `/queue` 排队深度无上限但显示当前深度（"Queued. (3 queued)"）
- NFR-TG-5: `/steer` 在 agent 未运行时降级为 `/queue`
- NFR-TG-6: Model Picker 回调失败不阻塞会话（fallback 到文字列表）

---

### Epic 35: TG 多媒体输入与高级会话控制

**目标：** 让 TG 支持非文本输入，补齐会话管理命令。

| Story | 标题 | 内容 | 依赖 |
|-------|------|------|------|
| 35.1 | 图片输入处理 | 接收 TG 图片消息，下载最高分辨率到临时缓存，转为 `media_urls` 传给 agent。支持 `media_group_id` 相册批处理（0.8s 聚合）。在 `TelegramAdapter` 中添加 photo handler，扩展 `TGModels` 添加 PhotoSize 模型。 | 无 |
| 35.2 | 语音/音频输入处理 | 接收 TG voice/audio 消息，下载缓存，传给 agent（依赖 agent 支持 audio 输入）。在 `TelegramAdapter` 中添加 voice/audio handler。 | 35.1（共用下载缓存基础设施） |
| 35.3 | 文档输入处理 | 接收 TG document 消息（PDF、代码文件等），下载缓存，文件路径传给 agent。在 `TelegramAdapter` 中添加 document handler。 | 35.1（共用下载缓存基础设施） |
| 35.4 | `/compress` 和 `/undo` 命令 | `/compress` 触发对话压缩（调用 SDK session 的压缩能力）；`/undo [N]` 回退 N 轮对话并重新 prompt。需要 SDK session API 支持。在 `TGCommandRegistry` 注册。 | 无 |
| 35.5 | `/sessions` 和 `/resume` 命令 | `/sessions` 分页列出历史会话（inline keyboard），`/resume <id>` 恢复指定会话。在 `TGCommandRegistry` 注册。 | 无 |
| 35.6 | `/title`、`/background`、`/agents` 命令 | `/title` 给当前会话命名；`/background <prompt>` 后台运行；`/agents` 列出活跃任务。在 `TGCommandRegistry` 注册。 | 无 |

**FRs:** FR-TG-17 (图片输入), FR-TG-18 (语音输入), FR-TG-19 (文档输入), FR-TG-20 (/compress), FR-TG-21 (/undo), FR-TG-22 (/sessions), FR-TG-23 (/resume), FR-TG-24 (/title), FR-TG-25 (/background), FR-TG-26 (/agents)

**NFRs:**
- NFR-TG-7: 图片下载失败不阻塞（warning 日志 + 纯文本 fallback）
- NFR-TG-8: 媒体缓存目录 `~/.axion/tg-cache/`，LRU 淘汰（7 天未访问删除）
- NFR-TG-9: 文档大小限制 20MB（超过则提示用户）

---

### Epic 36: TG 网络容错与 Markdown 增强（可选）

**目标：** 提升生产环境稳定性和富文本渲染精度。优先级最低，视需求推进。

| Story | 标题 | 内容 | 依赖 |
|-------|------|------|------|
| 36.1 | 网络重连增强 | 增强 `TelegramNetwork` 的错误分类：区分 transient（超时/429）vs permanent（401/403），transient 自动重试，permanent 报错。检测 polling conflict（多实例同时轮询）并 graceful degrade。 | 无 |
| 36.2 | MarkdownV2 表格支持 | 在 `TGMessageFormatter` 中增加 GFM 表格检测和渲染——将表格行转为 `<pre>` 格式的等宽文本，避免 MarkdownV2 不支持表格标签导致乱码。 | 无 |
| 36.3 | `/reasoning` 和 `/verbose` 命令 | `/reasoning <level>` 设置推理力度；`/verbose` 循环切换工具进度显示。在 `TGCommandRegistry` 注册。 | 无 |

**优先级：** P3，可延后。

---

## FR 追溯

| FR ID | 描述 | Epic | Story |
|-------|------|------|-------|
| FR-TG-1 | 通知静默模式 | Epic 33 | 33.1 |
| FR-TG-2 | 消息批处理 | Epic 33 | 33.2 |
| FR-TG-3 | Follow-up Grace Window | Epic 33 | 33.3 |
| FR-TG-4 | Reaction 状态反馈 | Epic 33 | 33.4 |
| FR-TG-5 | Edit Overflow Split | Epic 33 | 33.5 |
| FR-TG-6 | /queue 命令 | Epic 34 | 34.1 |
| FR-TG-7 | /steer 命令 | Epic 34 | 34.1 |
| FR-TG-8 | /model 交互式选择器 | Epic 34 | 34.2 |
| FR-TG-9 | /retry 命令 | Epic 34 | 34.3 |
| FR-TG-10 | /usage 命令 | Epic 34 | 34.3 |
| FR-TG-11 | /curator 命令 | Epic 34 | 34.3 |
| FR-TG-12 | /reload-skills 命令 | Epic 34 | 34.4 |
| FR-TG-13 | /fast 命令 | Epic 34 | 34.4 |
| FR-TG-14 | /yolo 命令 | Epic 34 | 34.4 |
| FR-TG-15 | Exec Approval 四级粒度 | Epic 34 | 34.5 |
| FR-TG-16 | Clarify "其他" 输入模式 | Epic 34 | 34.6 |
| FR-TG-17 | 图片输入处理 | Epic 35 | 35.1 |
| FR-TG-18 | 语音/音频输入处理 | Epic 35 | 35.2 |
| FR-TG-19 | 文档输入处理 | Epic 35 | 35.3 |
| FR-TG-20 | /compress 命令 | Epic 35 | 35.4 |
| FR-TG-21 | /undo 命令 | Epic 35 | 35.4 |
| FR-TG-22 | /sessions 命令 | Epic 35 | 35.5 |
| FR-TG-23 | /resume 命令 | Epic 35 | 35.5 |
| FR-TG-24 | /title 命令 | Epic 35 | 35.6 |
| FR-TG-25 | /background 命令 | Epic 35 | 35.6 |
| FR-TG-26 | /agents 命令 | Epic 35 | 35.6 |

## NFR 追溯

| NFR ID | 描述 | Epic |
|--------|------|------|
| NFR-TG-1 | 通知静默：仅最终回复和审批弹通知 | Epic 33 |
| NFR-TG-2 | 批处理：两条消息间隔 < 300ms 自动合并 | Epic 33 |
| NFR-TG-3 | Reaction 失败不阻塞主流程 | Epic 33 |
| NFR-TG-4 | /queue 排队深度显示 | Epic 34 |
| NFR-TG-5 | /steer 无 agent 时降级为 /queue | Epic 34 |
| NFR-TG-6 | Model Picker 回调失败 fallback 到文字列表 | Epic 34 |
| NFR-TG-7 | 媒体下载失败不阻塞（纯文本 fallback） | Epic 35 |
| NFR-TG-8 | 媒体缓存 LRU 淘汰（7 天） | Epic 35 |
| NFR-TG-9 | 文档大小限制 20MB | Epic 35 |

## 优先级与依赖

| 优先级 | Epic | 核心价值 | 依赖 |
|--------|------|----------|------|
| **P0** | Epic 33 | 消除通知刷屏、消息碎片化、缺乏状态反馈三大体验痛点 | 无 |
| **P1** | Epic 34 | 补齐命令和运行控制，TG 从"能用"变"好用" | Epic 33 可并行 |
| **P2** | Epic 35 | 多媒体输入 + 高级会话管理 | Epic 34 建议先完成 |
| **P3** | Epic 36 | 网络容错和渲染细节，锦上添花 | 无 |

**实施建议顺序：**
1. Epic 33（体验基础）— 通知静默和 Reaction 是改动最小、收益最大的两项，可以和 Epic 34 并行启动
2. Epic 34（命令补强）— `/queue` + `/steer` + `/model` 是控制力提升的核心三件套
3. Epic 35（多媒体 + 会话）— 在命令体系完善后再加输入类型和会话管理
4. Epic 36（打磨）— 视生产环境反馈决定是否推进

**理由：**
- Epic 33 的 Story 33.1（通知静默）改动约 20 行，但体验提升巨大——是投入产出比最高的单项
- Epic 34.2（Model Picker）是所有新增命令中工作量最大的，建议优先完成其他命令再集中做
- Epic 35 的多媒体输入需要先确认 agent 侧对 image/audio 的支持程度
- Epic 36 完全可以延后，当前网络层和 Markdown 渲染已够用

## 关键设计约束

- **所有新命令必须通过 `TGCommandRegistry` 注册** — 不在 GatewayRunner 中直接 dispatch
- **Callback 前缀路由** — 新增的 callback 类型（如 model picker `mp:`）必须在 `TGInteractiveSessionStore` 中注册对应的 handler
- **`_Concurrency.Task` 而非 `Task`** — OpenAgentSDK 有 Task 类型名冲突（project-context.md 反模式 #19）
- **格式化所有权归 Adapter** — Controller 和 Handler 生产原始文本，TelegramAdapter 负责格式化。避免双重格式化（project-context.md 反模式 #17）
- **闭包跨 3+ 文件时定义 typealias** — callback handler 闭包类型必须显式声明（project-context.md 反模式 #18）
- **Reaction API 错误容忍** — `setMessageReaction` 失败（如 bot 无权限、消息太旧）不阻塞任何流程
- **媒体缓存路径** — `~/.axion/tg-cache/`，不与 `~/.axion/recordings/` 或 `~/.axion/skills/` 混用
- **TG bot token 不写入 config.json** — 保持环境变量传入（project-context.md 反模式 #14）
- **单元测试 Mock 外部依赖** — TG API 调用必须 Mock，不走真实网络（CLAUDE.md 测试规则）

## 不在范围内

以下 Hermes 功能明确**不纳入**本次 PRD，作为远期参考：

- **Draft Streaming (Bot API 9.5 sendMessageDraft)** — 需要 Swift TG 库支持新 API，且当前 edit-based 流式已够用
- **DM Topics** — Axion 是单用户场景，不需要多会话并行隔离
- **群聊支持** — MVP 阶段 TG 是个人助手场景，不需要 @mention/observe/guest mode
- **Sticker 视觉分析** — 低频功能，投入大收益小
- **Voice TTS 输出** — 需要 TTS 引擎集成，复杂度高
- **Location/Venue 输入** — 桌面自动化场景不需要地理位置
- **Slash Confirm** — Axion 已有基础实现，暂不需要增强
- **Update Prompt** — 自更新机制走 Homebrew，不需要 TG 内更新提示
