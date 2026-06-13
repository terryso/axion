# Axion

[![Swift](https://img.shields.io/badge/Swift-6.1-orange)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://developer.apple.com/macos/)
[![CI](https://github.com/terryso/axion/actions/workflows/ci.yml/badge.svg)](https://github.com/terryso/axion/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/terryso/3a3cc01e58819c72bf54eab52dc2a3ff/raw/coverage.json)](https://github.com/terryso/axion/actions)
[![BMAD](https://bmad-badge.vercel.app/terryso/axion.svg)](https://github.com/bmad-code-org/BMAD-METHOD)
[![DeepWiki](https://img.shields.io/badge/DeepWiki-_.svg?style=flat&color=00b0aa&labelColor=000000&logo=data:image/svg%2Bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxNiIgaGVpZ2h0PSIxNiIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IiNmZmYiIHN0cm9rZS13aWR0aD0iMiIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMiAzaDZhMTAgMTAgMCAwIDEgMTAgMTB2MiIvPjxwYXRoIGQ9Ik0yIDEzaDYxMCAxMCAwIDAgMSAxMCAxMHYyIi8+PC9zdmc+)](https://deepwiki.com/terryso/axion)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

macOS 全能 AI Agent —— 交互式编程、文件编辑、Web 搜索、Shell 命令、安全存储清理、App 卸载、21 个原生桌面自动化工具，一个终端全搞定。

[English](./README.md) | [中文](#中文) | [更新日志](./CHANGELOG.md)

> **GLM 已适配：** Axion 的所有功能都可以通过 OpenAI Compatible Provider 使用 GLM 大模型跑通。GLM Coding 邀请链接：https://www.bigmodel.cn/glm-coding?ic=TVUZHTWCW9

---

<a id="中文"></a>

## 概述

Axion 是一个基于 Swift 的终端 AI Agent。输入 `axion` 即可开始对话 —— 它能写代码、编辑文件、执行 Shell 命令、搜索网页、读取文档、安全整理本地存储、带支持数据审查地卸载 macOS App，需要时还能通过原生无障碍 API 直接控制桌面应用。可以把它理解为「拥有 Mac 自动化超能力的 Claude Code」。

<p align="center">
  <img src="docs/demo.gif" alt="Axion Demo" width="700">
</p>

**核心亮点：**

- **交互式 Coding Agent** — 运行 `axion` 进入类 Claude Code 的交互 REPL，支持流式输出、17 个斜杠命令（`/help`、`/clear`、`/diff`、`/model`、`/cost`、`/storage`、`/apps`…）、文件编辑审批 Diff、多行输入和中文输入
- **全场景工具覆盖** — Bash 执行、文件读写编辑、代码搜索（Grep/Glob）、Web 搜索与抓取、LSP 代码智能 —— 加上 21 个原生 macOS 桌面工具（MCP 协议），GUI 场景也能搞定
- **安全存储与 App 清理** — 查找大文件，折叠展示 `node_modules`、`DerivedData` 等可重建缓存，通过审批计划整理目录，卸载 App 前审查关联支持数据，并支持撤销存储操作
- **上下文感知的文件编辑** — 基于 Diff 的审批流程，应用修改前清楚展示每处变更。每轮追踪文件修改，`/diff` 一键查看摘要
- **跨任务记忆** — 两套互补的记忆系统：App 操作经验（自动从工具调用中提取）和通用记忆（环境知识 + 用户画像）
- **SDK 技能系统** — Prompt 技能、录制技能和内置桌面技能，支持双轨查找和技能级记忆
- **录制回放** — 录制一次操作，之后无需 LLM 即可瞬间回放
- **HTTP API & MCP Server** — 集成 CI/CD，或让外部 Agent（Claude Code、Cursor）调用 Axion 的工具
- **Telegram 网关** — 通过 Telegram Bot 远程控制，支持流式响应、交互式审批键盘和技能浏览
- **自进化** — 后台 Review Agent 和智能策展自动提取记忆、演化技能、管理技能生命周期
- **完成通知** — 任务完成后发送 macOS 桌面通知，包含 AI 生成的结果摘要

## 架构

```
┌───────────────────────────────────────────────────────────────┐
│                            AxionCLI                            │
│                                                                │
│   Interactive Chat（默认）           Desktop Automation       │
│   ├── 流式 Markdown 渲染            ├── axion run "任务"      │
│   ├── 17 个斜杠命令                  ├── MCP 工具（21 个）      │
│   ├── 文件编辑审批                   ├── 录制回放               │
│   ├── 会话恢复                      └── 用户接管               │
│   └── 中文输入支持                                             │
│                                                                │
│   核心工具：Bash · 文件读写 · Grep/Glob · Web · LSP            │
│   技能系统：Prompt + 录制 + 内置技能                             │
│   记忆系统：App 经验 + Universal（MEMORY.md / USER.md）        │
│   运行时：EventBus · 7 个事件处理器 · Trace · 自进化            │
│   服务端：HTTP API（REST+SSE）· MCP Server · Telegram Gateway  │
├──────────────────────┬────────────────────────────────────────┤
│      AxionCore       │            AxionHelper                  │
│  模型、协议、          │   MCP Server（stdio）                  │
│  配置、错误            │   21 个原生 macOS 自动化工具            │
└──────────────────────┴────────────────────────────────────────┘
```

- **AxionCLI** — 与你交互的 Agent。默认进入交互 REPL；`axion run` 用于单次任务。包含完整工具集、记忆、技能、事件处理器和服务端模式
- **AxionCore** — 共享模型层（RunConfig、AxionConfig、Skill）和协议定义
- **AxionHelper** — 独立的 MCP 服务端进程，通过 stdio 协议提供 21 个原生 macOS 自动化工具

## 快速开始

### 环境要求

- macOS 14+
- Xcode 16+ (Swift 6.1)

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
# 启动交互模式（默认命令 —— 直接输入 axion）
axion

# 随便问
> 分析 ~/Logs/app.log 里的错误日志
> 把 UserService 重构为 async/await
> 搜索 Swift 6.2 的并发变更

# 编辑文件时会请求审批
> 修复 Sources/App/Cache.swift 里的内存泄漏
# → 展示 diff，确认后才应用修改

# 需要桌面自动化？也能搞定
> 打开 Safari 查一下明天的天气
> 把 Finder 和终端并排显示

# 安全清理本地存储和 App
> /storage large
> /storage scan ~/Projects
> /storage organize ~/Downloads
> /apps

# 查看变更
> /diff          # 本会话的 git diff 摘要
> /cost          # Token 用量和成本明细
> /copy          # 复制最后一条回复到剪贴板
> /status        # 会话状态卡
```

**单次执行模式**，适合脚本和 CI：

```bash
# 执行一个任务然后退出
axion run "用 ffmpeg 压缩 ~/Downloads/video.mp4"
axion run "搜索今天广州天气"
axion run "打开计算器并计算 123 + 456"

# 常用参数
axion run --dryrun "打开计算器"            # 仅生成计划，不实际执行
axion run --fast "打开计算器"               # 快速模式，减少 LLM 调用
axion run --max-steps 10 "创建新笔记"      # 限制最大步骤数
axion run --no-review "打开计算器"          # 跳过运行后审查
```

## 核心能力

### 内置工具

| 类别 | 工具 | 说明 |
|------|------|------|
| **Shell** | `Bash` | 执行任意 Shell 命令 |
| **文件** | `Read`、`Write`、`Edit` | 读取、创建、精确编辑文件 |
| **搜索** | `Grep`、`Glob` | 正则搜索文件内容、按名称模式查找文件 |
| **Web** | `WebSearch`、`WebFetch` | 搜索网页、抓取并阅读网页内容 |
| **代码智能** | `LSP` | 跳转定义、查找引用、悬停信息 |
| **记忆** | `memory` | 跨会话持久化和召回知识 |
| **技能** | `Skill` | 调用专业化工作流技能 |
| **存储与清理** | `storage_scan`、`propose_storage_plan`、`execute_storage_plan`、`undo_storage_op`、`scan_app_uninstall`、`execute_app_uninstall` | 安全整理目录、找大文件、卸载 App（默认移废纸篓、可撤销、执行前需确认） |
| **桌面** | 21 个 MCP 工具 | 原生 macOS 自动化（见下文） |

### Mac 存储与 App 清理

Axion 把清理做成可审查的 Mac 工作流，而不是直接删除文件。扫描只读取文件元数据，执行前会展示计划，清理默认进入系统废纸篓，存储整理会写入操作清单，之后可以撤销。

- **找出隐藏的大空间占用** — `/storage large` 扫描常用用户目录；`/storage large --home 1GB` 扩大到整个主目录，并保留系统、缓存、隐藏目录和受保护路径排除。
- **清理可重建的开发缓存** — `storage_scan` 会把 `node_modules`、`.build`、`DerivedData`、`.venv`、`Pods`、`.gradle` 等折叠成 `developer_cache` 根目录候选，避免展开数百万个依赖文件。
- **交互式整理目录** — `/storage organize ~/Downloads` 先扫描，再生成少量高置信计划，展示风险点，用户明确确认后才执行。
- **带支持数据审查的 App 卸载** — `/apps` 列出带大小的可卸载候选，支持按名称过滤，卸载前展示 App 详情，并通过 `scan_app_uninstall` / `execute_app_uninstall` 处理 App Bundle 和相关支持数据。

```bash
axion
> /storage help
> /storage large
> /storage large ~/Projects 500MB
> /storage large --home 1GB
> /storage organize ~/Downloads
> /storage undo
> /apps
```

### 桌面自动化（21 个 MCP 工具）

Axion 的独特优势 —— 当 CLI 工具不够用时，它能原生控制 macOS GUI 应用。

#### 应用管理
| 工具 | 说明 |
|------|------|
| `launch_app` | 按名称启动 macOS 应用（自动检测阻塞对话框） |
| `list_apps` | 列出所有正在运行的应用 |
| `quit_app` | 退出正在运行的应用 |
| `activate_window` | 激活（置顶）指定窗口 |

#### 窗口管理
| 工具 | 说明 |
|------|------|
| `list_windows` | 列出窗口（可按进程 ID 过滤） |
| `get_window_state` | 获取指定窗口的状态 |
| `move_window` | 移动窗口到新位置 |
| `resize_window` | 移动和/或调整窗口大小 |
| `validate_window` | 检查窗口是否存在且可操作 |
| `arrange_windows` | 排列多个窗口（并排、级联） |

#### 鼠标操作
| 工具 | 说明 |
|------|------|
| `click` | 在坐标或 AX 选择器位置单击 |
| `click_element` | 按标题/角色点击元素，无需查找坐标 |
| `double_click` | 在坐标或 AX 选择器位置双击 |
| `right_click` | 在坐标或 AX 选择器位置右键点击 |
| `drag` | 从一个点拖拽到另一个点 |
| `scroll` | 按方向和数量滚动 |

#### 键盘操作
| 工具 | 说明 |
|------|------|
| `type_text` | 在当前光标位置输入文本 |
| `press_key` | 按下单个按键 |
| `hotkey` | 按下快捷键组合 |

#### 屏幕 & 无障碍
| 工具 | 说明 |
|------|------|
| `screenshot` | 截屏（全屏或指定窗口） |
| `get_accessibility_tree` | 获取窗口的无障碍树 |
| `get_file_info` | 获取文件元数据（大小、日期、权限） |

#### 录制
| 工具 | 说明 |
|------|------|
| `start_recording` | 开始以只听模式捕获用户输入事件 |
| `stop_recording` | 停止录制并返回捕获的事件 |

### 交互式 Chat

默认 `axion` 命令打开一个功能丰富的终端 REPL：

- **流式输出** — Markdown、代码块、工具结果实时渲染
- **文件编辑审批** — 应用修改前展示 Diff 预览；可批准、拒绝或编辑
- **17 个斜杠命令** — `/help`、`/clear`、`/compact`、`/model`、`/cost`、`/diff`、`/status`、`/resume`、`/config`、`/new`、`/fork`、`/archive`、`/skills`、`/copy`、`/storage`、`/apps`、`/exit`
- **多行输入** — 自然粘贴或编写多行提示词
- **中文支持** — 完整的 CJK 输入处理
- **会话持久化** — 对话自动保存；`/resume` 或 `axion resume` 恢复
- **上下文管理** — 上下文过长时 `/compact` 压缩，`/clear` 重新开始
- **权限模式** — `--accept-edits` 自动批准文件编辑，`--dangerously-skip-permissions` 全自动

```bash
# 标准交互模式
axion

# 自动批准文件编辑（破坏性操作仍需确认）
axion --accept-edits

# 恢复上次会话
axion resume

# 列出所有会话
axion sessions
```

### 跨任务记忆

Axion 通过两套互补的记忆系统从每次任务中学习：

**App 操作记忆** — 自动从 MCP 工具调用中提取操作模式（菜单路径、控件位置、操作序列）并持久化。后续执行同 App 任务时，Planner 注入历史经验生成更精准的计划。

**通用记忆** — 双轨持久化知识：环境知识（MEMORY.md）和用户画像/偏好（USER.md）。Agent 在任务执行中和后台审查代理均可将发现的偏好和知识保存到这些文件。

```bash
# 记忆默认启用 — 查看已积累的知识
axion memory list

# 查看通用记忆内容
axion memory show memory    # 环境知识（MEMORY.md）
axion memory show user      # 用户画像/偏好（USER.md）

# 清除特定 App 的记忆
axion memory clear --app com.apple.calculator

# 单次运行禁用记忆
axion run --no-memory "打开计算器"
```

记忆文件存储在 `~/.axion/memory/`，加载到 prompt 前会进行安全扫描（检测提示注入、凭据泄露等）。

### 自进化（Review & Curator）

每次运行完成后，Axion 自动触发**后台 Review**，分析对话、提取记忆、演化技能——无需用户操作。

**Review Agent** — 任务完成后自动运行：
- 根据消息数和调度间隔判断是否需要 review
- Fork 轻量 review agent 审查对话内容
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
axion curator status           # 查看状态和下次运行时间
axion curator run              # 立即执行策展
axion curator run --dry-run    # 预览变更但不实际修改
```

### 技能系统

Axion 集成了 [OpenAgentSDK](https://github.com/terryso/open-agent-sdk-swift) 的 Skill 系统，支持三种技能类型：

| 类型 | 来源 | 说明 |
|------|------|------|
| **Prompt 技能** | `~/.claude/skills/*/SKILL.md` | Markdown 定义的提示词模板，支持可选的工具限制 |
| **录制技能** | `~/.axion/skills/` | 从用户录制操作编译的 JSON 工作流 — 回放无需 LLM |
| **内置技能** | 代码中注册 | `screenshot-analyze`、`data-extract`、`form-fill` — 始终可用 |

**触发技能：**

```bash
# 显式触发 — 加 / 前缀
axion run "/screenshot-analyze 分析当前屏幕布局"

# 隐式触发 — LLM 根据意图自动匹配合适的技能
axion run "把屏幕上的表单填了"

# 专用命令
axion skill run open-calculator
```

**录制工作流：**

```bash
axion record "open_calculator"    # 开始录制
# ... 执行桌面操作 ...
# Ctrl-C 结束录制

axion skill compile open_calculator  # 编译为可复用技能
axion skill run open_calculator      # 回放（不需要 LLM — 快速且确定性）
axion skill list                     # 列出所有技能
```

### HTTP API 服务

将 Axion 作为后台服务运行，供外部系统集成：

```bash
axion server --port 4242                 # 启动 API 服务
axion server --port 4242 --auth-key secret  # 启用认证
```

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
axion mcp    # 启动 MCP stdio 服务
```

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

### Telegram 网关

通过 Telegram Bot 实现常驻远程控制，支持流式响应、交互式审批键盘和技能浏览。

```bash
axion setup                               # 配置 Bot Token 和允许的用户
axion gateway start                       # 启动网关
axion daemon install --port 4242 --gateway  # 注册为守护进程（登录时自动启动）
```

| 命令 | 说明 |
|------|------|
| `/help` | 入门指南 |
| `/status` | 网关状态 |
| `/skills` | 浏览可用技能（分页内联键盘） |
| `/new` | 开始新会话 |
| `/stop` | 停止当前任务 |

### 用户接管

自动化受阻时，Axion 暂停让你手动完成操作。完成后按 Enter 恢复。

- 按 **Enter** — 手动修复后恢复
- 输入 **skip** — 跳过当前步骤
- 输入 **abort** — 取消任务
- 输入描述 — 说明你做了什么（自动记录为记忆）

### 完成通知

任务完成后，Axion 发送 macOS 桌面通知，包含：
1. **状态** — 完成 / 失败 / 已取消
2. **AI 总结** — 自动生成的一行结果摘要
3. **统计数据** — 耗时、LLM 调用次数、预估成本

### Daemon 模式与崩溃恢复

将 Axion 注册为 launchd 守护进程，开机自动启动、崩溃自动重启：

```bash
axion daemon install --port 4242        # 安装（登录时自动启动）
axion daemon status                     # 查看状态
axion daemon uninstall                  # 卸载
```

所有运行中的任务状态实时持久化到磁盘——服务端异常终止后可自动恢复。

## 作为独立 MCP Server 使用

AxionHelper 可作为独立的 MCP 服务端运行，供任意 MCP 客户端调用：

```bash
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
├── AxionCLI/              # Agent 入口
│   ├── Chat/              # 交互式 REPL（流式输出、审批、编辑器、中文支持）
│   ├── Commands/          # CLI 子命令（chat, run, setup, server, mcp, …）
│   ├── Tools/             # 内置工具实现
│   ├── Memory/            # 记忆上下文、提取、安全扫描
│   ├── Skills/            # 技能注册和内置技能
│   ├── Permissions/       # 工具权限系统
│   ├── Helper/            # Helper 进程生命周期（stdio）
│   ├── Runtime/           # 事件处理器（成本、通知、视觉差异…）
│   ├── Services/          # AxionRuntime, AgentBuilder, RunOrchestrator, Gateway
│   └── API/               # HTTP API 服务、SSE 桥接
├── AxionCore/             # 共享核心层
│   ├── Models/            # RunConfig, AxionConfig, Skill
│   ├── Protocols/         # 服务协议
│   ├── Errors/            # 统一 AxionError
│   └── Constants/         # ToolNames, Version
├── AxionHelper/           # MCP 服务端（Helper 进程）
│   ├── MCP/               # MCPServer, ToolRegistrar（21 个工具）
│   ├── Services/          # AccessibilityEngine, Screenshot, InputSimulation
│   └── Models/            # AppInfo, WindowInfo, AXElement

Tests/
├── AxionCoreTests/        # 核心模型单元测试
├── AxionCLITests/         # CLI 命令和服务测试
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
