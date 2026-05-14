# Axion

[![Swift](https://img.shields.io/badge/Swift-6.1-orange)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://developer.apple.com/macos/)
[![CI](https://github.com/terryso/axion/actions/workflows/ci.yml/badge.svg)](https://github.com/terryso/axion/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/terryso/3a3cc01e58819c72bf54eab52dc2a3ff/raw/coverage.json)](https://github.com/terryso/axion/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

macOS 桌面自动化 CLI，通过 LLM 驱动的 Plan-Execute-Verify 循环和 MCP 工具协议实现智能桌面操控。

[English](./README.md) | [中文](#中文)

---

<a id="中文"></a>

## 概述

Axion 是一个基于 Swift 的 macOS 桌面自动化工具，能够通过自然语言描述任务，自动规划、执行并验证桌面操作。它通过 MCP（Model Context Protocol）暴露 22 个原生工具，可被任何 MCP 客户端调用，也可以通过内置 CLI 直接使用。

## 架构

```
┌─────────────────────────────────────────────┐
│                  AxionCLI                    │
│  run / setup / doctor                        │
│  Plan → Execute → Verify → Replan Loop       │
├──────────────────┬──────────────────────────┤
│    AxionCore     │      AxionHelper          │
│  Models, Protocols│  MCP Server (stdio)       │
│  Config, Errors  │  22 Native macOS Tools    │
└──────────────────┴──────────────────────────┘
```

- **AxionCLI** — 命令行入口，包含 LLM 交互、任务规划和执行引擎
- **AxionCore** — 共享模型层（Plan, Step, RunState）和协议定义
- **AxionHelper** — MCP 服务端进程，通过 stdio 协议提供 22 个原生 macOS 自动化工具

## MCP 工具（22 个）

### 应用管理
| 工具 | 说明 |
|------|------|
| `launch_app` | 按名称启动 macOS 应用 |
| `list_apps` | 列出所有正在运行的应用 |
| `quit_app` | 退出正在运行的应用 |
| `activate_window` | 激活（置顶）指定窗口 |

### 窗口管理
| 工具 | 说明 |
|------|------|
| `list_windows` | 列出窗口（可按进程 ID 过滤） |
| `get_window_state` | 获取指定窗口的状态 |
| `move_window` | 移动窗口到新位置 |
| `resize_window` | 调整窗口大小和位置 |
| `validate_window` | 检查窗口是否存在且可操作 |
| `arrange_windows` | 排列多个窗口（并排、级联） |

### 鼠标操作
| 工具 | 说明 |
|------|------|
| `click` | 在指定坐标单击 |
| `double_click` | 在指定坐标双击 |
| `right_click` | 在指定坐标右键点击 |
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
| `get_file_info` | 获取文件或目录信息 |

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

# 限制最大步骤数
axion run --max-steps 10 "在备忘录中创建一条新笔记"
```

### 录制与技能复用

录制一次操作，之后可反复回放，无需 LLM 规划：

```bash
# 录制你的操作
axion record "打开计算器"
# ... 执行桌面操作 ...
# 按 Ctrl-C 结束录制

# 将录制编译为可复用技能
axion skill compile 打开计算器

# 执行技能（不需要 LLM —— 快速且确定性）
axion skill run 打开计算器

# 列出所有已保存的技能
axion skill list
```

### 作为 MCP Server 使用

AxionHelper 可作为独立的 MCP 服务端运行，供任意 MCP 客户端调用：

```bash
# 启动 MCP stdio 服务
.build/release/AxionHelper
```

在 Claude Code 的 MCP 配置中添加：

```json
{
  "mcpServers": {
    "axion": {
      "command": "/path/to/AxionHelper"
    }
  }
}
```

## 核心 Plan-Execute-Verify 循环

Axion 的执行引擎遵循以下循环：

1. **Planning** — LLM 根据任务描述生成步骤计划（Plan）
2. **Executing** — 逐步执行计划中的每个 Step
3. **Verifying** — 验证每步执行结果是否符合预期
4. **Replanning** — 验证失败时自动重新规划（最多重试 3 次）

支持的运行状态：`planning` → `executing` → `verifying` → `replanning` → `done`

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

支持 Anthropic 和 OpenAI Compatible 两种 Provider。

## 开发

```bash
# 构建
swift build

# 运行单元测试
swift test --skip AxionHelperIntegrationTests

# 运行集成测试（需要 macOS 辅助功能权限）
swift test --filter AxionHelperIntegrationTests

# 运行全部测试
swift test
```

## 项目结构

```
Sources/
├── AxionCLI/          # CLI 入口和命令
│   ├── Commands/      # run, setup, doctor 子命令
│   ├── Config/        # 配置管理
│   ├── Permissions/   # 权限检查
│   ├── Engine/        # 执行引擎（WIP）
│   ├── Planner/       # 计划器（WIP）
│   ├── Executor/      # 执行器（WIP）
│   ├── Verifier/      # 验证器（WIP）
│   └── Trace/         # 执行追踪（WIP）
├── AxionCore/         # 共享核心层
│   ├── Models/        # Plan, Step, RunState, AxionConfig
│   ├── Protocols/     # Planner, Executor, Verifier 协议
│   ├── Errors/        # 错误类型
│   └── Constants/     # 常量定义
└── AxionHelper/       # MCP 服务端
    ├── MCP/           # MCP Server 和工具注册
    ├── Services/      # 无障碍引擎、截图、输入模拟等
    ├── Models/        # AppInfo, WindowInfo, AXElement
    └── Protocols/     # 服务协议定义

Tests/
├── AxionCoreTests/       # 核心模型单元测试
├── AxionCLITests/        # CLI 命令测试
├── AxionHelperTests/     # Helper 工具和服务测试
│   ├── Tools/            # 工具单元测试
│   ├── Models/           # 模型测试
│   ├── Services/         # 服务测试
│   ├── MCP/              # MCP 协议测试
│   └── Integration/      # 集成测试（需真实 macOS 环境）
```

## 依赖

- [open-agent-sdk-swift](https://github.com/terryso/open-agent-sdk-swift) — Agent SDK
- [swift-mcp](https://github.com/terryso/swift-mcp) — MCP 协议实现
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI 参数解析

## License

MIT
