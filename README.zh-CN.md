# Axion

[![Swift](https://img.shields.io/badge/Swift-6.1-orange)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://developer.apple.com/macos/)
[![CI](https://github.com/terryso/axion/actions/workflows/ci.yml/badge.svg)](https://github.com/terryso/axion/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/terryso/3a3cc01e58819c72bf54eab52dc2a3ff/raw/coverage.json)](https://github.com/terryso/axion/actions)
[![BMAD](https://bmad-badge.vercel.app/terryso/axion.svg)](https://github.com/bmad-code-org/BMAD-METHOD)
[![zread](https://img.shields.io/badge/Ask_Zread-_.svg?style=flat&color=00b0aa&labelColor=000000&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB3aWR0aD0iMTYiIGhlaWdodD0iMTYiIHZpZXdCb3g9IjAgMCAxNiAxNiIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZD0iTTQuOTYxNTYgMS42MDAxSDIuMjQxNTZDMS44ODgxIDEuNjAwMSAxLjYwMTU2IDEuODg2NjQgMS42MDE1NiAyLjI0MDFWNC45NjAxQzEuNjAxNTYgNS4zMTM1NiAxLjg4ODEgNS42MDAxIDIuMjQxNTYgNS42MDAxSDQuOTYxNTZDNS4zMTUwMiA1LjYwMDEgNS42MDE1NiA1LjMxMzU2IDUuNjAxNTYgNC45NjAxVjIuMjQwMUM1LjYwMTU2IDEuODg2NjQgNS4zMTUwMiAxLjYwMDEgNC45NjE1NiAxLjYwMDFaIiBmaWxsPSIjZmZmIi8%2BCjxwYXRoIGQ9Ik00Ljk2MTU2IDEwLjM5OTlIMi4yNDE1NkMxLjg4ODEgMTAuMzk5OSAxLjYwMTU2IDEwLjY4NjQgMS42MDE1NiAxMS4wMzk5VjEzLjc1OTlDMS42MDE1NiAxNC4xMTM0IDEuODg4MSAxNC4zOTk5IDIuMjQxNTYgMTQuMzk5OUg0Ljk2MTU2QzUuMzE1MDIgMTQuMzk5OSA1LjYwMTU2IDE0LjExMzQgNS42MDE1NiAxMy43NTk5VjExLjAzOTlDNS42MDE1NiAxMC42ODY0IDUuMzE1MDIgMTAuMzk5OSA0Ljk2MTU2IDEwLjM5OTlaIiBmaWxsPSIjZmZmIi8%2BCjxwYXRoIGQ9Ik0xMy43NTg0IDEuNjAwMUgxMS4wMzg0QzEwLjY4NSAxLjYwMDEgMTAuMzk4NCAxLjg4NjY0IDEwLjM5ODQgMi4yNDAxVjQuOTYwMUMxMC4zOTg0IDUuMzEzNTYgMTAuNjg1IDUuNjAwMSAxMS4wMzg0IDUuNjAwMUgxMy43NTg0QzE0LjExMTkgNS42MDAxIDE0LjM5ODQgNS4zMTM1NiAxNC4zOTg0IDQuOTYwMVYyLjI0MDFDMTQuMzk4NCAxLjg4NjY0IDE0LjExMTkgMS42MDAxIDEzLjc1ODQgMS42MDAxWiIgZmlsbD0iI2ZmZiIvPgo8cGF0aCBkPSJNNCAxMkwxMiA0TDQgMTJaIiBmaWxsPSIjI2ZmZiIvPgo8cGF0aCBkPSJNNCAxMkwxMiA0IiBzdHJva2U9IiNmZmYiIHN0cm9rZS13aWR0aD0iMS41IiBzdHJva2UtbGluZWNhcD0icm91bmQiLz4KPC9zdmc%2BC&logoColor=ffffff)](https://zread.ai/terryso/axion)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

macOS AI agent，通过 LLM 驱动的 Plan-Execute-Verify 循环，结合原生桌面自动化、跨任务记忆和录制回放技能，实现智能任务执行。

[English](./README.md) | [中文](#中文)

---

<a id="中文"></a>

## 概述

Axion 是一个基于 Swift 的 macOS AI agent，能够通过自然语言描述任务，自动规划并执行操作。它结合核心工具（Bash、文件操作、Web 搜索）与 21 个原生桌面自动化工具（MCP 协议），以及 Playwright 浏览器自动化。可直接通过 CLI 使用，也可通过 HTTP API / MCP Server 模式集成。

**核心亮点：**

- **智能工具选择** — 自动选择合适的工具：CLI 任务用 Bash，GUI 任务用 MCP，浏览器用 Playwright，专业任务用 Skill
- **SDK 技能系统** — Prompt 技能、录制技能和内置桌面技能，支持双轨查找和技能级记忆
- **录制回放技能** — 录制一次操作，之后无需 LLM 即可瞬间回放
- **HTTP API 服务** — 通过 REST + SSE 集成 CI/CD 和外部系统
- **MCP Server 模式** — 作为外部 Agent（Claude Code、Cursor 等）的桌面操作插件，同时独立支持 CLI、文件和 Web 任务
- **用户接管** — 自动化受阻时可暂停，手动完成后恢复
- **完成通知** — 任务完成后发送 macOS 桌面通知，包含 AI 生成的结果摘要
- **自进化** — 后台 Review Agent 和智能策展自动提取记忆、演化技能、管理技能生命周期
- **运行时事件层** — 基于 EventBus 的 18 种类型事件，7 个内置处理器（成本追踪、通知、视觉差异、席位监控、链路追踪、记忆处理、后台审查）

## 架构

```
┌───────────────────────────────────────────────────────────┐
│                          AxionCLI                          │
│  run / setup / doctor / server / mcp / record / skill     │
│  daemon / resume / sessions / curator                     │
│  Agent Stream Loop · Memory · Takeover                    │
│  Skill System · Built-in Skills · Skill + Memory Context  │
│  Runtime Event Layer · EventBus · EventHandlers (7)       │
├──────────────────────┬────────────────────────────────────┤
│      AxionCore       │           AxionHelper              │
│  Models, Protocols,  │  MCP Server                        │
│  Config, Errors      │  21 Native macOS Automation Tools  │
└──────────────────────┴────────────────────────────────────┘
```

- **AxionCLI** — 命令行入口，包含 agent stream loop、记忆系统、技能系统（Prompt + 录制 + 内置）、Daemon 管理、会话恢复、服务器模式、运行时事件层、自进化和完成通知
- **AxionCore** — 共享模型层（RunConfig, AxionConfig）和协议定义
- **AxionHelper** — MCP 服务端进程，通过 stdio 协议提供 21 个原生 macOS 自动化工具

## MCP 工具（21 个）

### 应用管理
| 工具 | 说明 |
|------|------|
| `launch_app` | 按名称启动 macOS 应用（自动检测阻塞对话框） |
| `list_apps` | 列出所有正在运行的应用 |
| `quit_app` | 退出正在运行的应用 |
| `activate_window` | 激活（置顶）指定窗口 |

### 窗口管理
| 工具 | 说明 |
|------|------|
| `list_windows` | 列出窗口（可按进程 ID 过滤） |
| `get_window_state` | 获取指定窗口的状态 |
| `move_window` | 移动窗口到新位置 |
| `resize_window` | 移动和/或调整窗口大小 |
| `validate_window` | 检查窗口是否存在且可操作 |
| `arrange_windows` | 排列多个窗口（并排、级联） |

### 鼠标操作
| 工具 | 说明 |
|------|------|
| `click` | 在坐标或 AX 选择器位置单击 |
| `click_element` | 按标题/角色点击元素，无需查找坐标 |
| `double_click` | 在坐标或 AX 选择器位置双击 |
| `right_click` | 在坐标或 AX 选择器位置右键点击 |
| `drag` | 从一个点拖拽到另一个点 |
| `scroll` | 按方向和数量滚动 |

### 键盘操作
| 工具 | 说明 |
|------|------|
| `type_text` | 在当前光标位置输入文本 |
| `press_key` | 按下单个按键 |
| `hotkey` | 按下快捷键组合 |

### 屏幕 & 无障碍
| 工具 | 说明 |
|------|------|
| `screenshot` | 截屏（全屏或指定窗口） |
| `get_accessibility_tree` | 获取窗口的无障碍树 |
| `get_file_info` | 获取文件元数据（大小、日期、权限） |

### 录制
| 工具 | 说明 |
|------|------|
| `start_recording` | 开始以只听模式捕获用户输入事件 |
| `stop_recording` | 停止录制并返回捕获的事件 |

## 快速开始

### 环境要求

- macOS 14+
- Xcode 16+ (Swift 6.1)
- 辅助功能权限（Accessibility）和屏幕录制权限

### 安装

**Homebrew（推荐）：**

```bash
brew tap terryso/tap
brew install axion
```

**从源码构建：**

```bash
git clone https://github.com/terryso/axion.git
cd axion
swift build -c release
```

### 配置

```bash
# 交互式配置（API Key、Provider 等）
axion setup

# 检查环境状态
axion doctor
```

### 使用

```bash
# 执行任务（默认为实际执行模式）
axion run "打开计算器并计算 123 + 456"

# CLI 任务直接用 Bash — 无需 GUI
axion run "用 ffmpeg 压缩 ~/Downloads/video.mp4"
axion run "查看 ~/Documents 的磁盘占用"
axion run "搜索今天广州天气"

# 干跑模式（仅生成计划不实际执行）
axion run --dryrun "打开计算器并计算 123 + 456"

# 快速模式 — 减少 LLM 调用，适合简单任务
axion run --fast "打开计算器"

# 限制最大步骤数
axion run --max-steps 10 "在备忘录中创建一条新笔记"

# 禁用运行后的 review 和 curator
axion run --no-review "打开计算器"
```

## 核心功能

### 完成通知

任务完成后，Axion 发送 macOS 桌面通知，包含三行信息：

1. **状态** — 完成 / 失败 / 已取消
2. **AI 总结** — 自动生成的一行结果摘要（不超过 100 字）
3. **统计数据** — 耗时、LLM 调用次数、预估成本

如果任务涉及 UI 操作（桌面自动化），Axion 会自动将终端窗口切回前台，方便你立即查看结果。

JSON 模式下不发送通知（面向程序化调用）。

### 用户接管

自动化受阻时，Axion 暂停让你手动完成操作。完成后按 Enter 恢复自动执行。不完美的自动化好过没有自动化。

暂停时可选操作：
- 按 **Enter** — 手动修复后恢复
- 输入 **skip** — 跳过当前步骤
- 输入 **abort** — 取消任务

### 跨任务记忆

Axion 从每次任务执行中学习。运行结束后自动提取 App 操作模式（常用菜单路径、控件位置、操作序列）并持久化。后续执行同 App 任务时，Planner 注入历史经验生成更精准的计划，减少试错和重规划次数。

```bash
# 记忆默认启用 — 查看已积累的知识
axion memory list

# 清除特定 App 的记忆
axion memory clear --app com.apple.calculator

# 单次运行禁用记忆
axion run --no-memory "打开计算器"
```

### 自进化（Review & Curator）

每次运行完成后，Axion 自动触发**后台 Review**，分析对话、提取记忆、演化技能——无需用户操作。

**Review Agent** — `axion run` 完成后自动运行：
- 根据消息数和调度间隔判断是否需要 review
- Fork 轻量 review agent（Haiku 模型）审查对话内容
- 提取新记忆事实并演化技能定义
- 在 detached task 中执行，不阻塞终端

```bash
# Review 默认启用。单次运行禁用：
axion run --no-review "打开计算器"

# 覆盖 review agent 使用的模型：
axion run --review-model claude-haiku-4-5-20251001 "打开计算器"
```

**智能策展（Intelligent Curator）** — 定期管理技能生命周期：
- **机械式策展** — 归档过期技能（>30天未使用）、转换技能状态
- **LLM 策展** — 合并重叠技能、精简冗余技能
- 达到配置间隔时自动执行

```bash
# 查看策展状态和下次运行时间
axion curator status

# 立即执行策展
axion curator run

# 干跑模式（查看变更但不实际修改）
axion curator run --dry-run
```

**技能使用追踪** — 每次通过 `Skill` 工具调用技能都会自动计数，为策展决策提供数据。

Review 和 Curator 结果以 trace 事件形式记录在 `~/.axion/runs/<run-id>/review-trace.jsonl`。

### HTTP API 服务

将 Axion 作为后台服务运行，供外部系统集成：

```bash
# 启动 API 服务
axion server --port 4242

# 启用认证
axion server --port 4242 --auth-key mysecret

# 限制并发任务数
axion server --port 4242 --max-concurrent 3
```

API 端点：

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/v1/health` | 健康检查 |
| `POST` | `/v1/runs` | 提交任务（`{"task": "..."}`） |
| `GET` | `/v1/runs/{id}` | 查询任务状态 |
| `GET` | `/v1/runs/{id}/events` | SSE 实时事件流 |
| `GET` | `/v1/skills` | 列出所有技能 |
| `GET` | `/v1/skills/{name}` | 获取技能详情 |
| `POST` | `/v1/skills/{name}/run` | 执行技能 |

### MCP Server 模式

Axion 可作为 MCP 服务端运行，供外部 Agent 调用：

```bash
# 启动 MCP stdio 服务
axion mcp
```

在 Claude Code 的 MCP 配置中添加：

```json
{
  "mcpServers": {
    "axion": {
      "command": "/path/to/axion",
      "args": ["mcp"]
    }
  }
}
```

### 录制回放技能

录制一次操作，之后可反复回放，无需 LLM 规划：

```bash
# 录制你的操作
axion record "open_calculator"
# ... 执行桌面操作 ...
# 按 Ctrl-C 结束录制

# 将录制编译为可复用技能
axion skill compile open_calculator

# 执行技能（不需要 LLM —— 快速且确定性）
axion skill run open_calculator

# 列出所有已保存的技能
axion skill list

# 删除技能
axion skill delete open_calculator
```

技能以 JSON 文件存储在 `~/.axion/skills/`，支持通过 `--param` 参数化。

### 多窗口工作流

协调多个应用间的操作 — 从浏览器复制数据到电子表格、从邮件提取附件到 Finder，串联端到端跨应用工作流。

```bash
axion run "从 Safari 复制网页标题，粘贴到 TextEdit 文档"
axion run "把 Safari 和 TextEdit 并排显示，左 Safari 右 TextEdit"
```

`arrange_windows` 工具支持布局模式：`tile-left-right`、`tile-top-bottom`、`cascade`。

### 第三方 SDK 生态

Axion 是 [OpenAgentSDK](https://github.com/terryso/open-agent-sdk-swift) 的旗舰参考实现。第三方开发者可以：

- 使用项目模板快速创建 Agent 应用
- 通过 `@Tool` 宏注册自定义工具
- 通过 `axion mcp` 集成 Axion 的桌面操作能力
- 基于相同的 MCP + Agent Loop 架构构建自己的应用

### SDK 技能系统

Axion 集成了 [OpenAgentSDK](https://github.com/terryso/open-agent-sdk-swift) 的 Skill 系统，支持两种技能类型：

- **Prompt 技能** — 从 `~/.claude/skills/*/SKILL.md` 文件自动发现，定义 `promptTemplate`、可选的 `toolRestrictions` 和 `modelOverride`
- **录制技能** — 存储在 `~/.axion/skills/` 中的 JSON 文件，由用户录制操作编译生成

**双轨查找** — 引用技能名时，Axion 优先查找 Prompt 技能，未命中时回退到录制技能。同名技能始终解析为 Prompt 版本。

**显式触发** — 在任务描述前加 `/skill-name` 前缀直接调用指定技能：

```bash
# 直接触发 Prompt 技能
axion run "/screenshot-analyze 分析当前屏幕布局"

# 直接触发录制技能
axion run "/open-calculator"

# 或使用专用命令
axion skill run open-calculator
```

**隐式触发** — Axion 将可用技能列表注入系统提示词，LLM 可根据用户意图自动匹配并调用合适的技能，无需显式指定。

**内置桌面技能** — 三个技能在代码中注册（无需文件系统文件）：

| 技能 | 别名 | 说明 |
|------|------|------|
| `screenshot-analyze` | `sa`, `analyze`, `screen` | 截取并分析当前屏幕 |
| `data-extract` | `extract`, `de` | 从可见内容中提取结构化数据 |
| `form-fill` | `fill`, `ff` | 自动填写表单字段 |

```bash
# 列出所有可用技能（Prompt + 录制 + 内置）
axion skill list

# 单次运行禁用技能系统
axion run --no-skills "打开计算器"
```

**技能 + 记忆联动** — 技能与跨任务记忆系统深度集成：

- 技能执行成功时，记录 `affordance` 事实，scope 为 `skill:{name}`
- 执行失败时，记录 `avoid` 事实，帮助 Planner 从错误中学习
- 执行前，最多注入 3 条相关技能 scope 的记忆到提示词
- 使用 `--no-memory` 跳过注入和记录

**HTTP API 技能端点：**

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/v1/skills` | 列出所有技能（合并 Prompt + 录制，含 `type` 字段） |
| `GET` | `/v1/skills/{name}` | 获取技能详情（type, step_count, parameter_count） |
| `POST` | `/v1/skills/{name}/run` | 通过 API 执行技能（`{"task": "..."}`） |

### 运行时事件层

Axion 集成了 [OpenAgentSDK](https://github.com/terryso/open-agent-sdk-swift) 的 Runtime Event Layer — 基于 `EventBus` 的发布/订阅系统，将 agent 生命周期关注点与核心执行循环解耦。agent 执行过程中自动发射 18 种类型事件，覆盖 4 个类别。

**事件类别：**

| 类别 | 事件 |
|------|------|
| **会话** | `SessionCreatedEvent`, `SessionRestoredEvent`, `SessionClosedEvent`, `SessionAutoSavedEvent` |
| **Agent** | `AgentStartedEvent`, `AgentCompletedEvent`, `AgentFailedEvent`, `AgentInterruptedEvent`, `AgentResumedEvent` |
| **工具** | `ToolStartedEvent`, `ToolStreamingEvent`, `ToolCompletedEvent`, `ToolFailedEvent` |
| **LLM** | `LLMRequestStartedEvent`, `LLMResponseReceivedEvent`, `LLMCostEvent`, `LLMTokenStreamEvent` |

**内置事件处理器：**

| 处理器 | 描述 |
|--------|------|
| `CostEventHandler` | Agent 完成/失败/中断时，向 stderr 输出 LLM 使用摘要（轮次、Token、成本） |
| `NotificationHandler` | 任务完成后发送 macOS 桌面通知，包含 AI 生成的结果摘要 |
| `VisualDeltaHandler` | 工具执行后通过截图对比检测视觉变化 |
| `SeatMonitorHandler` | 长时间工具调用期间监控外部用户活动（共享席位模式） |
| `TraceEventHandler` | 向 `~/.axion/runs/<run-id>/events.jsonl` 追加结构化 JSONL 事件链路 |
| `MemoryProcessingHandler` | Agent 完成后触发记忆提取和技能演化 |
| `ReviewHandler` | 成功任务完成后启动后台审查 Agent |

**事件流：**

```
Agent SDK  →  EventBus.publish(event)  →  AsyncStream  →  AxionRuntime.dispatchToHandlers()
                                                                   ↓
                                                          EventHandler.handle(event, context)
```

`AxionRuntime` actor 管理事件循环生命周期：
1. `registerHandler()` — 注册事件处理器，支持类型过滤
2. `startEventLoop()` — 订阅 EventBus，开始分发事件
3. `stopEventLoop()` — 优雅取消订阅，停止分发

处理器均为 Actor — AxionRuntime 在独立 Task 中分发事件，Actor 隔离保证线程安全的可变状态。

**SSE 桥接（HTTP API）：** `EventBusBridge` 通过 `EventBroadcaster` 将所有事件转发给 SSE 客户端，可通过 `/v1/runs/{id}/events` 端点实时监控 agent 执行。

**会话恢复：** `AxionRuntime` 支持通过 `resumeSession()` 恢复被中断的会话，重建 agent 状态并重新连接事件循环。`SessionListing` 协议暴露 `listSessions()` 用于查询持久化的会话历史。

### Daemon 模式与崩溃恢复

将 Axion 注册为 launchd 守护进程，开机自动启动、崩溃自动重启。所有运行中的任务状态实时持久化到磁盘，服务端异常终止后可自动恢复。

**Daemon 管理：**

```bash
# 安装为 launchd 守护进程（登录时自动启动）
axion daemon install --port 4242

# 启用认证
axion daemon install --port 4242 --auth-key mysecret

# 查看守护进程状态
axion daemon status

# 卸载（停止服务并删除 plist）
axion daemon uninstall

# 卸载但保留日志文件
axion daemon uninstall --keep-logs
```

**Daemon 特性：**
- **开机自启** — `RunAtLoad: true` 登录时自动启动
- **崩溃重启** — `KeepAlive: true` 任何退出都会自动重启
- **日志文件** — stdout → `~/.axion/server.log`，stderr → `~/.axion/server.err.log`
- **重启节流** — ThrottleInterval 10 秒，防止频繁崩溃时无限重启

**任务状态持久化：**
- 所有任务状态（`api-output.json`）和 SSE 事件（`api-events.jsonl`）实时写入 `~/.axion/api-runs/`
- 服务端重启时，`RunRecoveryService` 加载所有持久化记录并：
  - 将 `running`/`queued`/`resuming`/`userTakeover` 状态的任务标记为 `failed`，错误信息为 `"server interrupted"`
  - `intervention_needed`、`completed`、`failed`、`cancelled` 状态保持不变
  - 恢复 SSE 事件历史，支持迟连接的客户端重放历史事件

## 作为独立 MCP Server 使用

AxionHelper 可作为独立的 MCP 服务端运行，供任意 MCP 客户端调用：

```bash
# 启动 MCP stdio 服务
.build/release/AxionHelper
```

```json
{
  "mcpServers": {
    "axion": {
      "command": "/path/to/AxionHelper"
    }
  }
}
```

## 配置

配置文件位于 `~/.config/axion/config.json`：

```json
{
  "provider": "anthropic",
  "apiKey": "sk-...",
  "model": "claude-sonnet-4-20250514",
  "maxSteps": 20,
  "maxModelCalls": 50,
  "reviewModel": "claude-haiku-4-5-20251001",
  "reviewMemoryInterval": 10,
  "reviewSkillInterval": 15,
  "reviewMinMessages": 4,
  "curatorEnabled": true,
  "curatorIntervalHours": 168,
  "curatorStaleAfterDays": 30,
  "curatorArchiveAfterDays": 90
}
```

支持 Anthropic 和 OpenAI Compatible 两种 Provider。配置优先级：默认值 → config.json → 环境变量 → CLI 参数。

## 开发

```bash
# 构建
swift build

# 运行单元测试（Swift Testing 框架）
swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" \
           --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" \
           --filter "AxionCoreTests" --filter "AxionCLITests"

# 运行集成测试（需要 macOS 辅助功能权限）
swift test --filter AxionHelperIntegrationTests
```

## 项目结构

```
Sources/
├── AxionCLI/              # CLI 入口和命令
│   ├── Commands/          # run, setup, doctor, server, mcp, record, skill, daemon, curator 子命令
│   ├── Config/            # 配置管理
│   ├── Checks/            # 环境和权限检查
│   ├── Constants/         # CLI 专用常量
│   ├── IO/                # 输出处理器和接管 I/O
│   ├── MCP/               # MCPServerRunner (Agent-as-MCP-Server)
│   ├── API/               # HTTP API 服务、SSE 事件流
│   ├── Memory/            # MemoryContextProvider, RunMemoryProcessor
│   ├── Planner/           # PromptBuilder
│   ├── Skills/            # SkillRegistry, AxionBuiltInSkills
│   ├── Helper/            # HelperProcessManager (stdio 生命周期)
│   ├── Runtime/           # EventHandlers (Cost, Notification, VisualDelta, SeatMonitor, Trace, Memory, Review)
│   ├── Trace/              # TraceRecorder (review/curator trace 事件)
│   └── Services/          # RunOrchestrator, AgentBuilder, AxionRuntime, EventBus 和共享服务
├── AxionCore/             # 共享核心层
│   ├── Models/            # RunConfig, AxionConfig, AppProfile
│   ├── Protocols/         # 服务协议
│   ├── Errors/            # 错误类型
│   └── Constants/         # ToolNames 和共享常量
├── AxionHelper/           # MCP 服务端（Helper 进程）
│   ├── MCP/               # MCPServer 和 ToolRegistrar（21 个工具）
│   ├── Services/          # AccessibilityEngine, Screenshot, InputSimulation, EventRecorder 等
│   ├── Models/            # AppInfo, WindowInfo, AXElement, SelectorQuery
│   └── Protocols/         # 服务协议定义

Tests/
├── AxionCoreTests/        # 核心模型单元测试
├── AxionCLITests/         # CLI 命令测试
├── AxionHelperTests/      # Helper 工具和服务测试
│   ├── Tools/             # 工具单元测试
│   ├── Models/            # 模型测试
│   ├── Services/          # 服务测试
│   ├── MCP/               # MCP 协议测试
│   └── Integration/       # 集成测试（需真实 macOS 环境）
```

## 依赖

- [open-agent-sdk-swift](https://github.com/terryso/open-agent-sdk-swift) — Agent SDK（Agent Loop、MCP Client、Memory Store、Hooks、Runtime Event Layer）
- [swift-mcp](https://github.com/terryso/swift-mcp) — MCP 协议实现
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI 参数解析

## Star History

<a href="https://www.star-history.com/?repos=terryso%2Faxion&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=terryso/axion&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=terryso/axion&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=terryso/axion&type=date&legend=top-left" />
 </picture>
</a>

## License

MIT
