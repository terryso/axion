---
title: "Axion Gateway: Remote Interaction & Self-Evolving Learning Loop"
status: final
created: 2026-05-29
updated: 2026-05-29
project: axion
author: Nick + John (PM)
---

# Axion Gateway: Remote Interaction & Self-Evolving Learning Loop

## Problem Statement

Axion 的自进化闭环只转了一半。`ReviewOrchestrator`、`IntelligentCurator`、`LLMSkillEvolver` 已经在代码里，但只在 `axion run` 执行时触发。没有长驻进程，就没有：

- **后台审查**：run 结束后自动提炼 memory 和 skill 更新
- **周期性 curator**：空闲时合并/归档/修补 SKILL.md
- **远程交互**：不在 Mac 前面时无法使用 Axion

用户（Nick）需要 Axion 变成真正的私人助手：随时随地通过 Telegram 发任务、拿结果，同时 Axion 在后台持续自我进化。

## Vision

Axion Gateway 是一个长驻进程，让 Axion 从"按需启动的 CLI 工具"变成"始终在线的个人助手"：

1. **多渠道接入** — MVP 支持 Telegram，架构预留其他渠道（WeChat、Slack 等）
2. **后台审查** — 每次 run 后自动 fork 审查 agent，提取 memory 和 skill 更新
3. **自进化闭环** — Curator 空闲时定期整理技能库，合并重叠、归档过期、修补 SKILL.md
4. **统一入口** — HTTP API + TG + 后台任务，一个进程搞定

## Existing Infrastructure

Axion 已有的组件（无需重做）：

| 组件 | 位置 | 状态 |
|------|------|------|
| `ReviewOrchestrator` | AgentBuilder.swift | 已集成，按 schedule 触发 memory/skill 审查 |
| `LLMSkillEvolver` | AgentBuilder.swift | 用 LLM 进化 SKILL.md 内容 |
| `IntelligentCurator` | AgentBuilder.swift | Curator 逻辑（stale/archive/merge） |
| `SkillCuratorStore` | AgentBuilder.swift | `.curator_state` 持久化 |
| `SkillUsageStore` | AgentBuilder.swift | 使用频率追踪 |
| `FactStore` | SDK | Memory 持久化（actor 隔离） |
| `SkillRegistry` | AgentBuilder.swift | SKILL.md 发现和加载 |
| `AxionRuntime` | AxionRuntime.swift | 统一执行入口（eventBus + handlers） |
| `DaemonService` | DaemonService.swift | launchd plist 管理（仅 HTTP API） |

**缺少的部分：**
- 长驻 gateway 进程（把 HTTP API + TG + 后台审查 + curator 串起来）
- Telegram adapter
- 后台任务调度器（让审查和 curator 在空闲时自动运行）
- ReviewHandler 增强：当前只检查 `shouldReview` 后打日志，不实际执行审查。需要在 gateway 中补充审查执行逻辑

## User Journeys

### UJ-1: 远程执行任务（TG → Axion → Mac）

Nick 在外面，用手机发 TG 消息给 Axion Bot：

> "帮我在 Mac 上打开 Calculator，输入 42*58，把结果告诉我"

Axion Gateway 收到消息 → 启动 AxionRuntime 执行任务 → 通过 Helper 完成 AX 操作 → 结果推送到 TG。

```
Nick (TG) → Axion Gateway → AxionRuntime → Helper (AX ops)
                                              ↓
                               结果 → TG 回复给 Nick
```

### UJ-2: 远程代码执行

> "帮我跑一下 ~/projects/api 的测试，如果失败了把错误日志发我"

Axion 通过 bash 工具执行代码 → 结果（成功/失败 + 日志）推送到 TG。

### UJ-3: 后台审查（自动，用户无感）

Nick 用 Axion 完成了一系列调试任务。每次 run 结束后：

1. Gateway 检查 ReviewScheduleConfig，判断是否到审查间隔
2. 如果到了，fork 审查 agent（复用 AxionRuntime 的 agent 配置）
3. 审查 agent 回放对话，决定是否更新 memory 或 SKILL.md
4. 结果记录到 trace（用户下次查看时能看到）

### UJ-4: Curator 自动整理（空闲时）

Gateway 检测到超过 2 小时没有任务，且距离上次 curator 超过 7 天：

1. 触发 IntelligentCurator
2. Curator 扫描所有 SKILL.md，根据使用数据决定：
   - 合并重叠技能
   - 归档 90 天未用技能
   - 修补需要更新的技能（通过 LLMSkillEvolver）
3. 结果记录到 `.curator_state`

## Functional Requirements

### FR-1: Gateway 进程

**FR-1.1** `axion gateway` 命令启动长驻进程，包含 HTTP API server + TG adapter + 后台任务调度器。

**FR-1.2** `axion gateway install` 注册为 launchd 守护进程（复用 DaemonService 的 plist 生成逻辑），开机自启。

**FR-1.3** `axion gateway status` 显示运行状态（进程 PID、TG 连接状态、上次审查时间、上次 curator 时间）。

**FR-1.4** `axion gateway uninstall` 停止并卸载守护进程。

**FR-1.5** Gateway 进程包含 HTTP API server（兼容现有 `axion server` 的所有端点），AxionBar 无需修改。

**FR-1.6** Gateway 优雅关闭：SIGTERM → 停止接受新任务 → 等待运行中任务完成（最多 30 秒）→ 退出。

### FR-2: Telegram Adapter

**FR-2.1** 通过环境变量配置：`AXION_TELEGRAM_BOT_TOKEN`（必填）、`AXION_TELEGRAM_ALLOWED_USERS`（逗号分隔的用户 ID 白名单）。

**FR-2.2** 支持文本消息接收和发送。TG 消息作为 task 提交给 AxionRuntime。

**FR-2.3** 支持图片接收（截图/照片），作为附件传入 agent 上下文。

**FR-2.4** 任务执行中，每步进展通过 TG 推送（复用 EventBus → SSE 相同的事件流）。

**FR-2.5** 任务完成后，最终结果推送到 TG。长消息自动分段发送。

**FR-2.6** 未授权用户发消息时，静默忽略（不回复，不报错）。

**FR-2.7** 支持 `/status` 命令查看 gateway 状态（运行中任务数、memory 条目数、技能数）。

**FR-2.8** 支持 `/skills` 命令列出可用技能。

### FR-3: 后台审查

**FR-3.1** 每次 run 结束后，Gateway 检查 ReviewScheduleConfig，决定是否触发审查。

**FR-3.2** 审查使用与主任务相同的模型（MVP），后续可通过 `review_model` 配置项指定辅助模型。

**FR-3.3** 审查 agent 的工具权限限制为 memory 和 skill 操作（白名单隔离）。

**FR-3.4** 审查结果记录到 trace，并可选推送到 TG（通过配置开关控制）。

**FR-3.5** 审查遵循 Hermes 的反模式清单：不捕获环境依赖失败、负面断言、一次性错误、一次性任务叙述。

### FR-4: Curator 自进化

**FR-4.1** Gateway 空闲超过 `curator_idle_hours`（默认 2 小时）且距上次运行超过 `curator_interval_hours`（默认 168 小时 = 7 天）时，自动触发 Curator。

**FR-4.2** Curator 操作对象仅限 SKILL.md（agent 创建的技能），不触碰内置技能和用户置顶技能。

**FR-4.3** Curator 操作包括：合并重叠技能、修补过时内容、归档长期未用技能。永不自动删除。

**FR-4.4** Curator 使用 LLMSkillEvolver（已有）执行 SKILL.md 内容更新。

**FR-4.5** Curator 运行结果持久化到 `.curator_state`，支持 `axion gateway status` 查看。

**FR-4.6** 支持 `axion curator run` 手动触发（已有），`axion curator run --dry-run` 预览模式（已有）。Gateway 通过 CuratorScheduler 在空闲时自动触发。

### FR-5: 任务执行

**FR-5.1** TG 提交的任务通过 AxionRuntime.execute() 执行，复用完整的 agent loop（Helper MCP + bash + skill）。

**FR-5.2** 任务并发限制：同一时间最多 1 个任务执行（单用户场景，避免桌面操作冲突）。

**FR-5.3** 任务排队：如果已有任务在执行，新任务排队等待，通过 TG 通知"任务已排队"。

**FR-5.4** 任务超时：单任务最长执行 10 分钟（可配置），超时自动取消并通知用户。

### FR-6: 配置

**FR-6.1** Gateway 配置项通过 `~/.axion/config.json` 管理，新增字段：

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `gateway.enabled` | `false` | 是否启用 gateway |
| `gateway.telegramBotToken` | 环境变量 | TG Bot Token |
| `gateway.telegramAllowedUsers` | 环境变量 | TG 用户 ID 白名单 |
| `gateway.curatorIdleHours` | `2` | Curator 空闲触发阈值 |
| `gateway.curatorIntervalHours` | `168` | Curator 间隔（小时） |
| `gateway.taskTimeoutMinutes` | `10` | 单任务超时（分钟） |
| `gateway.notifyCuratorResults` | `false` | Curator 结果是否推送 TG |

## Non-Functional Requirements

### NFR-1: 进程稳定性

- Gateway 崩溃后 launchd 自动重启（ThrottleInterval: 10 秒）
- 内存泄漏防护：常驻内存 < 50MB（不含运行中任务）
- 日志轮转：`~/.axion/gateway.log` + `~/.axion/gateway.err.log`

### NFR-2: 安全

- TG 消息只接受白名单用户，未授权消息静默丢弃
- API Key 不出现在日志和 TG 消息中
- 远程任务执行受到 sharedSeatMode 安全策略约束
- 环境变量存储敏感信息（bot token），不写入 config.json

### NFR-3: 成本

- 后台审查复用前缀缓存（共享系统 prompt）
- 审查间隔可配置，默认每 5 轮对话触发一次
- Curator 使用辅助模型（后续迭代，MVP 先用主模型）

### NFR-4: 兼容性

- Gateway 包含现有 HTTP API 的所有功能，AxionBar 无需修改
- 现有 `axion daemon` 命令保持不变（向后兼容）
- 现有 `axion run` 命令行为不变（不依赖 gateway）

## Architecture Overview

```
axion gateway (长驻进程)
    │
    ├── HTTP API Server (复用 AxionAPI, Hummingbird)
    │       ├── /v1/health, /v1/runs, /v1/skills ...
    │       └── AxionBar 消费
    │
    ├── Telegram Adapter
    │       ├── TelegramBotAPI (Swift 实现)
    │       ├── 消息接收 → 任务提交
    │       └── EventBus → TG 推送
    │
    ├── TaskQueue (串行执行)
    │       └── AxionRuntime.execute() per task
    │
    ├── Background Review Scheduler
    │       ├── 每次 run 后检查间隔
    │       └── fork 审查 agent (ReviewOrchestrator)
    │
    ├── Curator Scheduler
    │       ├── 空闲检测 + 间隔检查
    │       └── IntelligentCurator + LLMSkillEvolver
    │
    └── EventBus (SDK)
            └── 事件分发到 TG adapter + trace + SSE
```

### 模块归属

| 新增/修改文件 | 模块 | 说明 |
|-------------|------|------|
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | AxionCLI | gateway CLI 入口 |
| `Sources/AxionCLI/Services/GatewayRunner.swift` | AxionCLI | gateway 编排器 |
| `Sources/AxionCLI/Services/TelegramAdapter.swift` | AxionCLI | TG Bot API 对接 |
| `Sources/AxionCLI/Services/BackgroundReviewScheduler.swift` | AxionCLI | 审查调度 |
| `Sources/AxionCLI/Services/CuratorScheduler.swift` | AxionCLI | Curator 调度 |
| `AxionCore/` | — | 无新增（复用现有 Skill/Curator 模型） |

### 依赖

| 依赖 | 用途 | 方式 |
|------|------|------|
| Telegram Bot API | TG 消息收发 | HTTP 长轮询（无需第三方 Swift 库，直接 URLSession） |
| Hummingbird | HTTP API | 已有 |
| OpenAgentSDK | Agent/EventBus/TaskQueue | 已有 |

## Success Metrics

| 指标 | 目标 | 衡量方式 |
|------|------|---------|
| TG 消息响应延迟 | 收到消息到开始执行 < 3 秒 | 日志时间戳 |
| Gateway 常驻内存 | < 50MB | Activity Monitor |
| 后台审查触发率 | > 90% 符合条件的 run 后触发 | curator_state 日志 |
| Curator 执行成功率 | > 95% | curator_state |
| 审查成本增量 | < 基础使用成本的 20% | LLM API 调用统计 |

### Counter-metrics

- 审查不应导致 memory 污染（用户手动修正 memory 的频率不应增加）
- Curator 不应误归档常用技能（置顶率不应异常上升）

## Open Questions

- ~~**TG 长轮询 vs Webhook**~~ → **已决定：MVP 用长轮询。** 无需公网 IP，开发简单。后续迭代加 webhook。详见 addendum。
- **审查 agent 的 Swift 实现方式**：Hermes 用 Python thread fork，Axion 用 Swift Task + 同一进程内 AxionRuntime 实例。Actor 隔离问题需要在架构设计阶段确认（AxionRuntime 是 actor，审查 agent 不能共享状态）。→ 延迟到架构设计阶段解决。
- ~~**Skill.md 的具体格式规范**~~ → **已确认：Axion 已有完整的 SKILL.md 加载/注入/执行能力（类似 Claude Code 的 skill 机制）。** Curator 更新时复用现有 SkillRegistry 的读写接口。

## Scope & Phasing

### MVP（本 PRD 范围）

- `axion gateway` 命令 + launchd 集成
- Telegram adapter（文本 + 图片收发，结果推送）
- 后台审查调度（接入现有 ReviewOrchestrator）
- Curator 调度（接入现有 IntelligentCurator）
- 基本配置（config.json + 环境变量）

### Future Iterations（不在本 PRD）

- 辅助模型配置（降低审查成本）
- 更多渠道（WeChat、Slack 等）
- TG 交互式按钮（InlineKeyboard）
- Darwinian Evolver 式的技能进化
- 多用户支持
- TG 语音消息支持
- Webhook 模式
