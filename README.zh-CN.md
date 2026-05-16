# Axion

[![Swift](https://img.shields.io/badge/Swift-6.1-orange)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://developer.apple.com/macos/)
[![CI](https://github.com/terryso/axion/actions/workflows/ci.yml/badge.svg)](https://github.com/terryso/axion/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/terryso/3a3cc01e58819c72bf54eab52dc2a3ff/raw/coverage.json)](https://github.com/terryso/axion/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

macOS 桌面自动化平台，通过 LLM 驱动的 Plan-Execute-Verify 循环、MCP 工具协议、跨任务记忆和录制回放技能实现智能桌面操控。

[English](./README.md) | [中文](#中文)

---

<a id="中文"></a>

## 概述

Axion 是一个基于 Swift 的 macOS 桌面自动化平台，能够通过自然语言描述任务，自动规划、执行并验证桌面操作。它通过 MCP（Model Context Protocol）暴露 21 个原生工具，可被任何 MCP 客户端调用，也可以通过内置 CLI 直接使用。

**核心亮点：**

- **跨任务记忆** — 每次任务自动学习，用得越多越聪明
- **录制回放技能** — 录制一次操作，之后无需 LLM 即可瞬间回放
- **HTTP API 服务** — 通过 REST + SSE 集成 CI/CD 和外部系统
- **MCP Server 模式** — 作为外部 Agent（Claude Code、Cursor 等）的桌面操作插件
- **用户接管** — 自动化受阻时可暂停，手动完成后恢复
- **菜单栏应用** — 原生 macOS 状态栏 UI，支持全局热键

## 架构

```
┌───────────────────────────────────────────────────────┐
│                       AxionCLI                         │
│  run / setup / doctor / server / mcp / record / skill  │
│  Plan → Execute → Verify → Replan Loop                 │
│  Memory · Fast Mode · Takeover                         │
├──────────────────┬──────────────────┬─────────────────┤
│    AxionCore     │   AxionHelper    │    AxionBar      │
│  Models, Proto-  │  MCP Server      │  Menu Bar App    │
│  cols, Config,   │  21 Native macOS │  Task Panel      │
│  Errors          │  Tools           │  Global Hotkeys  │
└──────────────────┴──────────────────┴─────────────────┘
```

- **AxionCLI** — 命令行入口，包含 LLM 交互、任务规划、执行引擎、记忆系统和服务器模式
- **AxionCore** — 共享模型层（Plan, Step, RunState）和协议定义
- **AxionHelper** — MCP 服务端进程，通过 stdio 协议提供 21 个原生 macOS 自动化工具
- **AxionBar** — 原生 macOS 菜单栏应用，提供任务面板、技能触发和全局热键

## MCP 工具（21 个）

### 应用管理
| 工具 | 说明 |
|------|------|
| `launch_app` | 按名称启动 macOS 应用（自动检测阻塞对话框） |
| `list_apps` | 列出所有正在运行的应用 |
| `activate_window` | 激活（置顶）指定窗口 |

### 窗口管理
| 工具 | 说明 |
|------|------|
| `list_windows` | 列出窗口（可按进程 ID 过滤） |
| `get_window_state` | 获取指定窗口的状态 |
| `resize_window` | 移动和/或调整窗口大小 |
| `validate_window` | 检查窗口是否存在且可操作 |
| `arrange_windows` | 排列多个窗口（并排、级联） |

### 鼠标操作
| 工具 | 说明 |
|------|------|
| `click` | 在坐标或 AX 选择器位置单击 |
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
| `open_url` | 在默认浏览器中打开 URL |

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

```bash
# 从源码构建
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

# 干跑模式（仅生成计划不实际执行）
axion run --dryrun "打开计算器并计算 123 + 456"

# 快速模式 — 减少 LLM 调用，适合简单任务
axion run --fast "打开计算器"

# 限制最大步骤数
axion run --max-steps 10 "在备忘录中创建一条新笔记"
```

## 核心功能

### Plan-Execute-Verify 循环

Axion 的执行引擎遵循以下循环：

1. **Planning** — LLM 根据任务描述生成步骤计划（Plan）
2. **Executing** — 逐步执行计划中的每个 Step
3. **Verifying** — 验证每步执行结果是否符合预期
4. **Replanning** — 验证失败时自动重新规划（最多重试 3 次）

支持的运行状态：`planning` → `executing` → `verifying` → `replanning` → `done`

### 跨任务记忆（Phase 2）

Axion 从每次任务执行中学习。运行结束后自动提取 App 操作模式（常用菜单路径、控件位置、操作序列）并持久化。后续执行同 App 任务时，Planner 注入历史经验生成更精准的计划，减少试错和重规划次数。

```bash
# 记忆默认启用 — 查看已积累的知识
axion memory list

# 清除特定 App 的记忆
axion memory clear --app com.apple.calculator

# 单次运行禁用记忆
axion run --no-memory "打开计算器"
```

### 用户接管（Phase 2）

自动化受阻时，Axion 暂停让你手动完成操作。完成后按 Enter 恢复自动执行。不完美的自动化好过没有自动化。

暂停时可选操作：
- 按 **Enter** — 手动修复后恢复
- 输入 **skip** — 跳过当前步骤
- 输入 **abort** — 取消任务

### HTTP API 服务（Phase 2）

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

### MCP Server 模式（Phase 2）

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

### 录制回放技能（Phase 3）

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

### 多窗口工作流（Phase 3）

协调多个应用间的操作 — 从浏览器复制数据到电子表格、从邮件提取附件到 Finder，串联端到端跨应用工作流。

```bash
axion run "从 Safari 复制网页标题，粘贴到 TextEdit 文档"
axion run "把 Safari 和 TextEdit 并排显示，左 Safari 右 TextEdit"
```

`arrange_windows` 工具支持布局模式：`tile-left-right`、`tile-top-bottom`、`cascade`。

### 菜单栏应用（Phase 3）

AxionBar 是原生 macOS 菜单栏应用，无需打开终端即可使用 Axion：

- **快速执行** — 从菜单栏直接提交任务
- **任务面板** — 通过 SSE 实时显示执行进度
- **技能触发** — 一键执行已保存的技能
- **全局热键** — 为技能绑定键盘快捷键
- **运行历史** — 查看最近任务结果

AxionBar 通过 HTTP API 与 CLI 后端通信。

### 第三方 SDK 生态（Phase 3）

Axion 是 [OpenAgentSDK](https://github.com/terryso/open-agent-sdk-swift) 的旗舰参考实现。第三方开发者可以：

- 使用项目模板快速创建 Agent 应用
- 通过 `@Tool` 宏注册自定义工具
- 通过 `axion mcp` 集成 Axion 的桌面操作能力
- 基于相同的 MCP + Agent Loop 架构构建自己的应用

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
  "maxBatches": 6,
  "maxReplanRetries": 3,
  "traceEnabled": true
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
│   ├── Commands/          # run, setup, doctor, server, mcp, record, skill 子命令
│   ├── Config/            # 配置管理
│   ├── Permissions/       # 权限检查
│   ├── Engine/            # RunEngine 状态机
│   ├── Planner/           # LLMPlanner, PlanParser, PromptBuilder
│   ├── Executor/          # StepExecutor, SafetyChecker, PlaceholderResolver
│   ├── Verifier/          # TaskVerifier, StopConditionEvaluator
│   ├── Memory/            # AppMemoryExtractor, AppProfileAnalyzer, MemoryContextProvider
│   ├── Trace/             # TraceRecorder (JSONL)
│   ├── MCP/               # MCPServerRunner (Agent-as-MCP-Server)
│   ├── API/               # HTTP API 服务、SSE 事件流
│   ├── Helper/            # HelperProcessManager (stdio 生命周期)
│   └── Services/          # SkillExecutor 和共享服务
├── AxionCore/             # 共享核心层
│   ├── Models/            # Plan, Step, RunState, AxionConfig
│   ├── Protocols/         # Planner, Executor, Verifier 协议
│   ├── Errors/            # 错误类型
│   └── Constants/         # 常量定义
├── AxionHelper/           # MCP 服务端（Helper 进程）
│   ├── MCP/               # MCPServer 和 ToolRegistrar（21 个工具）
│   ├── Services/          # AccessibilityEngine, Screenshot, InputSimulation, EventRecorder 等
│   ├── Models/            # AppInfo, WindowInfo, AXElement, SelectorQuery
│   └── Protocols/         # 服务协议定义
└── AxionBar/              # macOS 菜单栏应用
    ├── Views/             # QuickRunWindow, TaskDetailPanel, RunHistoryWindow, SettingsWindow
    ├── MenuBar/           # MenuBarBuilder
    ├── Services/          # BackendHealthChecker, SSEEventClient, GlobalHotkeyService 等
    └── Models/            # Bar 专用模型

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

- [open-agent-sdk-swift](https://github.com/terryso/open-agent-sdk-swift) — Agent SDK（Agent Loop、MCP Client、Memory Store、Hooks）
- [swift-mcp](https://github.com/terryso/swift-mcp) — MCP 协议实现
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI 参数解析

## License

MIT
