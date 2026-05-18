---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
  - step-04-final-validation
  - step-05-phase2-epics
  - step-06-phase3-epics
  - step-07-phase5-epics
  - step-08-phase6-epics
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/architecture.md
documentCounts:
  prd: 1
  architecture: 1
  uxDesign: 0
requirementsExtracted:
  fr: 41
  nfr: 23
  additional: 8
  uxDesign: 0
phase1Status: complete
phase2EpicsAdded: 2026-05-12
phase3EpicsAdded: 2026-05-14
phase5EpicsAdded: 2026-05-18
phase6EpicsAdded: 2026-05-18
---

# Axion - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for Axion, decomposing the requirements from the PRD and Architecture requirements into implementable stories.

## Requirements Inventory

### Functional Requirements

FR1: 用户可以通过 Homebrew 私有 Tap 一行命令安装 Axion（`brew install terryso/tap/axion`，CLI + Helper 同时安装）
FR2: 用户可以通过 `axion setup` 完成首次配置（API Key 输入、权限引导）
FR3: 用户可以通过 `axion doctor` 检查系统环境、权限状态和依赖完整性
FR4: 用户可以通过配置文件（`~/.axion/config.json`）管理 API Key、模型选择和执行参数
FR5: 用户可以通过环境变量覆盖配置文件中的设置
FR6: 用户可以通过自然语言描述执行桌面自动化任务（`axion run "任务描述"`）
FR7: 用户可以在干跑模式下预览执行计划而不实际操作桌面（`axion run "任务描述" --dryrun`）
FR8: 用户可以限制任务的最大步数和最大批次（`--max-steps`、`--max-batches`）
FR9: 用户可以随时通过 Ctrl-C 中断正在执行的任务
FR10: 用户可以在前台模式运行，允许使用全局光标和焦点操作（`--allow-foreground`）
FR11: 系统可以根据任务描述和当前屏幕状态，通过 LLM 生成小批量工具调用序列（plan）
FR12: 系统可以将截图和 AX tree 作为视觉上下文附加到规划请求中
FR13: 系统可以在执行失败或验证未通过时，携带失败上下文重新规划
FR14: 系统可以将规划结果解析为结构化的步骤序列（工具名、参数、目的、预期变化）
FR15: 系统可以解析和修正 LLM 输出中的常见格式错误（markdown 围栏、前导文本等）
FR16: 系统可以按顺序执行 planner 生成的步骤，通过 MCP 调用 AxionHelper
FR17: 系统可以解析 `$pid` 和 `$window_id` 占位符，从已执行步骤的结果中填充后续步骤的参数
FR18: 系统可以在 AX 定位操作前自动刷新窗口状态，避免使用过期的元素索引
FR19: 系统可以处理步骤执行失败，记录失败位置和原因，触发重规划
FR20: 系统可以在共享座椅后台模式下阻止前台/全局操作，保障用户桌面可用性
FR21: 系统可以在每个批次执行完成后，通过截图和 AX tree 验证任务是否已完成
FR22: 系统可以根据 planner 定义的 `stopWhen` 条件判断任务完成状态
FR23: 系统可以区分任务完成（done）、被阻塞（blocked）和需要澄清（needs_clarification）状态
FR24: Helper 可以启动和列举 macOS 应用（launch_app、list_apps）
FR25: Helper 可以列举和管理窗口（list_windows、get_window_state）
FR26: Helper 可以执行鼠标操作（click、double_click、right_click、drag、scroll）
FR27: Helper 可以执行键盘操作（type_text、press_key、hotkey）
FR28: Helper 可以截取指定窗口的屏幕截图
FR29: Helper 可以获取窗口的 Accessibility tree（AX tree）
FR30: Helper 可以在默认浏览器中打开 URL
FR31: Helper 作为 MCP stdio server 运行，通过 stdin/stdout JSON-RPC 通信
FR32: Helper 在 CLI 启动时自动被拉起，CLI 退出时随之退出
FR33: 系统可以在终端实时显示每个步骤的执行状态（工具名、目的、结果）
FR34: 系统可以显示任务完成的汇总信息（总步数、耗时、重规划次数）
FR35: 系统可以结构化输出 JSON 格式的执行结果（`--json`）
FR36: 系统使用 SDK 的 Agent 循环编排 planner/executor/verify 的完整工作流
FR37: 系统使用 SDK 的 MCP client 连接 AxionHelper 并调用工具
FR38: 系统使用 SDK 的工具注册机制注册 Helper 提供的桌面操作工具
FR39: 系统使用 SDK 的 Hooks 机制实现执行前的安全策略检查
FR40: 系统使用 SDK 的流式消息机制输出实时进度
FR41: 产出的 SDK 边界文档明确记录每个模块的归属（SDK / 应用层）和理由

### NonFunctional Requirements

NFR1: CLI 冷启动到首次 LLM 请求发出 < 2 秒（不含网络延迟）
NFR2: AxionHelper 启动到 MCP 连接就绪 < 500 毫秒
NFR3: 单个 AX 操作（点击、输入）从 MCP 请求到结果返回 < 200 毫秒
NFR4: CLI 进程常驻内存 < 30MB，Helper 进程常驻内存 < 20MB
NFR5: Helper 单次操作失败不导致 CLI 崩溃，错误通过 ToolResult 返回
NFR6: LLM API 调用失败时自动重试（最多 3 次，指数退避）
NFR7: 规划结果解析失败时记录原始响应，不静默丢弃
NFR8: 用户 Ctrl-C 中断时正确清理 Helper 进程，不留僵尸进程
NFR9: API Key 不出现在日志、trace 或终端输出中
NFR10: 共享座椅模式下默认阻止前台操作（移动光标、抢焦点），防止干扰用户
NFR11: Helper 仅响应来自本地 CLI 的 MCP 请求，不监听网络端口
NFR12: 截图和 AX tree 数据仅用于当前任务，不在磁盘持久化（除非用户启用 trace）
NFR13: `axion setup` 提供清晰的逐步引导，非技术用户可在 5 分钟内完成
NFR14: `axion doctor` 输出明确的修复建议，不只是报错
NFR15: 任务执行过程中终端输出实时更新，用户无需猜测进度
NFR16: 错误信息使用自然语言描述，不暴露内部异常堆栈
NFR17: CLI 代码与 SDK 通过 SPM 依赖解耦，SDK 更新只需修改版本号
NFR18: Helper 工具集可独立扩展，新增工具无需修改 CLI 核心逻辑
NFR19: Planner 的 system prompt 可独立修改，不硬编码在代码中
NFR20: 每次运行生成 trace 文件（`~/.axion/runs/{runId}/trace.jsonl`），用于调试和回溯
NFR21: 支持 macOS 14（Sonoma）及以上版本
NFR22: 不依赖 Xcode Command Line Tools 以外的系统级软件
NFR23: 支持 Apple Silicon（arm64）和 Intel（x86_64）

### Additional Requirements

- AR1: 使用自定义 SPM 项目结构（三目标：AxionCLI / AxionHelper / AxionCore），无现成 starter template
- AR2: API Key 与其他配置统一存储在 config.json（文件权限 0o600），环境变量 AXION_API_KEY 可覆盖（D1）
- AR3: Plan 数据模型使用强类型 Codable JSON 结构，支持 Value 枚举占位符（D2）
- AR4: 执行循环使用显式状态机（RunState 枚举 + RunContext），含 replanning 路径（D3）
- AR5: 配置系统分层：默认值 → config.json → 环境变量 → CLI 参数（D4）
- AR6: 并发模型使用 Swift Structured Concurrency（async/await + Actor）（D5）
- AR7: Prompt 管理使用外部 Markdown 文件 + 运行时加载 + 模板变量注入（D6）
- AR8: Trace 记录使用 JSONL 格式，每行一个事件（D7）
- AR9: Helper 进程生命周期使用 Process + DispatchGroup + Signal 传播（D8）
- AR10: 实现顺序遵循架构决策影响分析：Core → Helper → Config → Planner → Executor → Verifier → RunEngine → CLI
- AR11: 模块依赖规则：AxionCore 无外部依赖；AxionCLI ← OpenAgentSDK + ArgumentParser；AxionHelper ← mcp-swift-sdk；CLI 不直接 import Helper
- AR12: 创建 Story 时按 OpenClick 参考指南矩阵决定何时读取 OpenClick 源码提取实现细节

### UX Design Requirements

无 UX Design 文档。Axion 为 CLI + Helper 工具，终端输出为唯一用户界面。

### FR Coverage Map

FR1: Epic 2 - Homebrew 私有 Tap 安装（terryso/tap）
FR2: Epic 2 - axion setup 首次配置
FR3: Epic 2 - axion doctor 环境检查
FR4: Epic 2 - 配置文件管理
FR5: Epic 2 - 环境变量覆盖
FR6: Epic 3 - 自然语言任务执行
FR7: Epic 3 - 干跑模式
FR8: Epic 3 - 步数/批次限制
FR9: Epic 3 - Ctrl-C 中断
FR10: Epic 3 - 前台模式
FR11: Epic 3 - LLM 规划引擎
FR12: Epic 3 - 视觉上下文附加
FR13: Epic 3 - 失败重规划
FR14: Epic 3 - 结构化步骤解析
FR15: Epic 3 - LLM 输出格式修正
FR16: Epic 3 - 步骤执行
FR17: Epic 3 - 占位符解析
FR18: Epic 3 - 窗口状态刷新
FR19: Epic 3 - 步骤失败处理
FR20: Epic 3 - 共享座椅安全策略
FR21: Epic 3 - 任务完成验证
FR22: Epic 3 - stopWhen 条件评估
FR23: Epic 3 - 任务状态区分
FR24: Epic 1 - 应用启动和列举
FR25: Epic 1 - 窗口管理
FR26: Epic 1 - 鼠标操作
FR27: Epic 1 - 键盘操作
FR28: Epic 1 - 屏幕截图
FR29: Epic 1 - AX tree 获取
FR30: Epic 1 - URL 打开
FR31: Epic 1 - MCP stdio server
FR32: Epic 1 - Helper 自动启停
FR33: Epic 3 - 终端实时进度
FR34: Epic 3 - 任务汇总信息
FR35: Epic 3 - JSON 输出
FR36: Epic 3 - SDK Agent 循环编排
FR37: Epic 3 - SDK MCP client
FR38: Epic 3 - SDK 工具注册
FR39: Epic 3 - SDK Hooks 安全检查
FR40: Epic 3 - SDK 流式消息
FR41: Epic 3 - SDK 边界文档

## Epic List

### Epic 1: AxionHelper — macOS 桌面自动化引擎
构建可独立运行的 macOS Helper App，通过 MCP stdio 协议暴露完整的桌面操作能力（应用管理、窗口管理、鼠标/键盘操作、截图、AX tree 获取、URL 打开）。AxionHelper 是 Axion 的「手和眼」—— CLI 的大脑通过 MCP 管道指挥 Helper 的双手操作桌面。

同时搭建项目基础设施：SPM 三目标结构（AxionCLI / AxionHelper / AxionCore）、AxionCore 共享模型（Plan、Step、RunState、AxionConfig、AxionError 等）和统一错误处理体系。

**FRs covered:** FR24, FR25, FR26, FR27, FR28, FR29, FR30, FR31, FR32
**ARs covered:** AR1, AR3, AR6, AR11

### Epic 2: CLI 安装配置与首次运行体验
用户可以安装 Axion（brew install）、完成首次配置（axion setup：API Key 输入、权限引导）、验证系统环境（axion doctor）。配置系统支持分层覆盖（默认值 → config.json → 环境变量 → CLI 参数）。

**FRs covered:** FR1, FR2, FR3, FR4, FR5
**ARs covered:** AR5

### Epic 3: 自然语言任务执行
用户输入 `axion run "打开计算器，计算 17 乘以 23"`，Axion 完成完整的 plan → execute → verify → replan 循环：Planner 调用 LLM 生成结构化执行计划，Executor 通过 MCP 调用 Helper 逐步执行，Verifier 通过截图和 AX tree 验证结果，失败时携带上下文自动重规划。整个过程中终端实时显示进度，支持干跑模式、步数限制、Ctrl-C 中断和前台模式。所有核心编排通过 SDK 公共 API 完成（Agent Loop、MCP Client、Tool Registry、Hooks、Streaming），产出清晰的 SDK 边界文档。

**FRs covered:** FR6, FR7, FR8, FR9, FR10, FR11, FR12, FR13, FR14, FR15, FR16, FR17, FR18, FR19, FR20, FR21, FR22, FR23, FR33, FR34, FR35, FR36, FR37, FR38, FR39, FR40, FR41
**ARs covered:** AR4, AR7, AR8, AR9, AR10, AR12

## Epic 1: AxionHelper — macOS 桌面自动化引擎

构建可独立运行的 macOS Helper App，通过 MCP stdio 协议暴露完整的桌面操作能力。同时搭建项目基础设施：SPM 三目标结构、AxionCore 共享模型和统一错误处理体系。

### Story 1.1: SPM 项目脚手架与 AxionCore 共享模型

As a 开发者,
I want 项目有完整的三目标 SPM 结构和强类型共享模型,
So that 后续所有 Story 可以在类型安全的基础上开发.

**Acceptance Criteria:**

**Given** 一个新的空目录
**When** 运行 `swift build`
**Then** 项目编译成功，生成 AxionCLI 和 AxionHelper 两个可执行目标
**And** AxionCore 作为 library target 存在

**Given** Plan 模型包含 steps 和 stopWhen
**When** 用 JSON 初始化并编码后解码
**Then** 数据完整 round-trip，Value 枚举的 placeholder case（如 `$pid`）正确保留

**Given** RunState 枚举定义
**When** 检查所有 case
**Then** 包含 planning / executing / verifying / replanning / done / blocked / needsClarification / cancelled / failed 所有状态

**Given** AxionConfig 使用 Codable 默认策略
**When** 编码为 JSON
**Then** 输出 camelCase 格式（maxSteps, maxBatches, maxReplanRetries 等）

**Given** AxionError 枚举
**When** 转换为 MCP ToolResult 错误格式
**Then** 输出包含 error / message / suggestion 字段的 JSON

**Given** 所有 Protocol 定义（PlannerProtocol, ExecutorProtocol, VerifierProtocol, MCPClientProtocol, OutputProtocol）
**When** 检查文件位置
**Then** 位于 AxionCore/Protocols/ 目录

### Story 1.2: Helper MCP Server 基础

As a CLI 进程,
I want Helper 可以通过 MCP stdio 协议通信,
So that CLI 可以通过标准化协议调用桌面操作工具.

**Acceptance Criteria:**

**Given** AxionHelper 启动
**When** 通过 stdin 发送 MCP initialize 请求
**Then** 返回正确的 initialize 响应，包含服务端能力声明

**Given** MCP 连接已建立
**When** 发送 tools/list 请求
**Then** 返回所有已注册工具的列表，每个工具包含 name、description 和 inputSchema

**Given** Helper 收到未知工具名调用
**When** 执行 tool_call
**Then** 返回 isError=true 的 ToolResult，message 说明工具不存在

**Given** Helper 进程的 stdin 收到 EOF
**When** 管道关闭
**Then** Helper 优雅退出，无崩溃日志

### Story 1.3: 应用启动与窗口管理

As a CLI 进程,
I want Helper 可以启动应用和管理窗口,
So that 自动化任务可以控制 macOS 应用.

**Acceptance Criteria:**

**Given** launch_app 工具调用 app_name="Calculator"
**When** 执行
**Then** Calculator.app 启动成功，返回包含 pid 的结果

**Given** list_apps 工具调用
**When** 执行
**Then** 返回当前运行的应用列表，每项包含 pid 和 app_name

**Given** Calculator 正在运行
**When** 调用 list_windows
**Then** 返回窗口列表，每项包含 window_id、title、bounds

**Given** Calculator 窗口存在
**When** 调用 get_window_state 传入 window_id
**Then** 返回完整窗口状态（bounds, is_minimized, is_focused, ax_tree）

**Given** 指定应用未安装
**When** 调用 launch_app
**Then** 返回错误结果，包含 error: "app_not_found" 和 suggestion

### Story 1.4: 鼠标与键盘操作

As a CLI 进程,
I want Helper 可以执行鼠标和键盘操作,
So that 自动化任务可以与桌面 UI 交互.

**Acceptance Criteria:**

**Given** 屏幕坐标 (x, y) 在有效范围内
**When** 调用 click
**Then** 在指定位置执行单击操作，返回成功

**Given** 文本光标在输入框中
**When** 调用 type_text 传入 "Hello World"
**Then** 输入框中出现 "Hello World" 文本

**Given** 文本光标活跃
**When** 调用 press_key 传入 "return"
**Then** 按下回车键

**Given** 组合键参数 "cmd+c"
**When** 调用 hotkey
**Then** 执行 Command+C 快捷键

**Given** 滚动参数（direction: "down", amount: 3）
**When** 调用 scroll
**Then** 在指定方向滚动指定量

**Given** 拖拽起止坐标
**When** 调用 drag
**Then** 执行从起点到终点的拖拽操作

### Story 1.5: 截图、AX Tree 与 URL 打开

As a CLI 进程,
I want Helper 可以截图、获取无障碍树和打开 URL,
So that 自动化任务可以感知屏幕状态并浏览网页.

**Acceptance Criteria:**

**Given** 指定窗口 window_id
**When** 调用 screenshot
**Then** 返回该窗口截图的 base64 编码，大小不超过 5MB

**Given** 未指定 window_id
**When** 调用 screenshot
**Then** 返回全屏截图

**Given** 窗口存在
**When** 调用 get_ax_tree
**Then** 返回该窗口的完整 Accessibility tree，节点包含 role / title / value / bounds / children

**Given** AX tree 节点数超过阈值（maxNodes=500）
**When** 调用 get_ax_tree
**Then** 按层级截断，返回有限大小的树

**Given** URL "https://example.com"
**When** 调用 open_url
**Then** 在默认浏览器中打开该 URL，返回成功

### Story 1.6: Helper 完整集成与 App 打包

As a 用户,
I want Helper 是一个完整的签名 macOS App，所有工具正确注册并可通过 MCP 调用,
So that Axion 可以作为完整产品使用 Helper 的桌面操作能力.

**Acceptance Criteria:**

**Given** 所有工具已实现
**When** 调用 tools/list
**Then** 返回全部 15 个工具：launch_app, list_apps, list_windows, get_window_state, click, double_click, right_click, drag, scroll, type_text, press_key, hotkey, screenshot, get_ax_tree, open_url

**Given** AxionHelper.app 打包完成
**When** 检查 Info.plist
**Then** 包含 LSUIElement=true（无 Dock 图标）和 LSMinimumSystemVersion=13.0

**Given** Helper 启动
**When** 等待 500ms 后发送 MCP 请求
**Then** MCP 连接就绪，可正常响应（NFR2）

**Given** 单个 AX 操作执行
**When** 测量从 MCP 请求到结果返回的耗时
**Then** 不超过 200ms（NFR3）

**Given** Helper 运行中
**When** CLI 进程退出
**Then** Helper 进程随之退出，不残留

## Epic 2: CLI 安装配置与首次运行体验

用户可以安装 Axion、完成首次配置、验证系统环境。配置系统支持分层覆盖，所有配置统一存储在 config.json。

### Story 2.1: CLI 入口与 ArgumentParser 骨架

As a 用户,
I want `axion` 命令可以运行并显示帮助信息,
So that 我可以了解 Axion 提供的命令和用法.

**Acceptance Criteria:**

**Given** axion 编译完成
**When** 运行 `axion --help`
**Then** 显示根命令帮助，列出 run / setup / doctor 子命令及其简要说明

**Given** axion 编译完成
**When** 运行 `axion --version`
**Then** 显示版本号

**Given** 未知子命令
**When** 运行 `axion unknown`
**Then** 显示错误提示和帮助信息

### Story 2.2: 配置系统与分层加载

As a 用户,
I want 所有配置（含 API Key）统一存储在 config.json，支持分层覆盖,
So that 我可以通过一个文件管理所有配置，且环境变量和 CLI 参数可以覆盖文件设置.

**Acceptance Criteria:**

**Given** ~/.axion/config.json 存在 {"apiKey": "sk-ant-xxx", "maxSteps": 30}
**When** ConfigManager 加载配置
**Then** apiKey 和 maxSteps 正确读取

**Given** ~/.axion/config.json 存在 {"maxSteps": 30}
**When** ConfigManager 加载配置
**Then** maxSteps=30（文件覆盖默认值 20）

**Given** 环境变量 AXION_MODEL 设置
**When** ConfigManager 加载配置
**Then** model 值来自环境变量（覆盖 config.json）

**Given** CLI 参数 --max-steps 10
**When** ConfigManager 加载配置
**Then** maxSteps=10（优先级最高，覆盖环境变量和文件）

**Given** API Key 已存储
**When** 运行任何 axion 命令并启用 --verbose
**Then** API Key 不出现在任何终端输出中（NFR9）

### Story 2.3: axion setup 首次配置命令

As a 新用户,
I want 通过 `axion setup` 引导完成首次配置,
So that 我可以在 5 分钟内准备好使用 Axion.

**Acceptance Criteria:**

**Given** 运行 `axion setup`
**When** 引导开始
**Then** 提示用户输入 Anthropic API Key

**Given** API Key 输入完成
**When** setup 继续
**Then** 将 API Key 写入 ~/.axion/config.json

**Given** API Key 已存储
**When** setup 检查 Accessibility 权限
**Then** 如已授权则显示通过，未授权则提示前往系统偏好设置授权

**Given** Accessibility 已授权
**When** setup 检查屏幕录制权限
**Then** 如已授权则显示通过，未授权则提示授权步骤

**Given** 所有配置完成
**When** setup 结束
**Then** 显示 "Setup complete! 运行 axion doctor 检查环境" 提示

### Story 2.4: axion doctor 环境检查命令

As a 用户,
I want 通过 `axion doctor` 检查系统环境和配置状态,
So that 我可以快速定位和修复配置问题.

**Acceptance Criteria:**

**Given** 运行 `axion doctor`
**When** 检查 API Key
**Then** 报告 config.json 中是否存在有效的 API Key

**Given** API Key 缺失
**When** doctor 输出
**Then** 建议运行 `axion setup` 配置 API Key

**Given** Accessibility 权限检查
**When** doctor 运行
**Then** 报告权限状态，未授权时给出 "前往系统偏好设置 > 隐私与安全 > 辅助功能" 的具体步骤

**Given** 屏幕录制权限检查
**When** doctor 运行
**Then** 报告权限状态，未授权时给出修复建议

**Given** macOS 版本检查
**When** doctor 运行
**Then** 报告当前版本是否满足 13.0+ 要求

**Given** 所有检查通过
**When** doctor 完成
**Then** 显示 "All checks passed!"

### Story 2.5: Homebrew 私有 Tap 分发与打包

As a 用户,
I want 通过 `brew install terryso/tap/axion` 一键安装 CLI 和 Helper,
So that 我不需要手动编译或配置安装，且无需等待 homebrew-core 审核.

**Acceptance Criteria:**

**Given** Homebrew formula 已推送至 github.com/terryso/homebrew-tap
**When** 运行 `brew install terryso/tap/axion`
**Then** 同时安装 axion CLI 到 bin/ 和 AxionHelper.app 到 libexec/axion/

**Given** 安装完成
**When** 运行 `axion --version`
**Then** 显示正确的版本号

**Given** 安装完成
**When** axion run 需要启动 Helper
**Then** 在 libexec/axion/AxionHelper.app 路径找到并启动 Helper

**Given** AxionHelper.app 构建完成
**When** 检查 code signing
**Then** 包含有效的 Apple Developer 签名和 entitlements

**Given** build-release.sh 执行
**When** 构建 + 打包完成
**Then** 生成 axion-{version}.tar.gz（含 axion CLI + AxionHelper.app），并更新 homebrew-tap 仓库中的 formula（sha256 + URL）

## Epic 3: 自然语言任务执行

用户输入自然语言任务，Axion 完成完整的 plan → execute → verify → replan 循环。所有核心编排通过 SDK 公共 API 完成，产出清晰的 SDK 边界文档。

### Story 3.1: Helper 进程管理器与 MCP 客户端连接

As a CLI 进程,
I want 自动启动 Helper 并建立 MCP 连接,
So that CLI 可以无缝调用 Helper 的桌面操作工具.

**Acceptance Criteria:**

**Given** CLI 首次需要 Helper
**When** HelperProcessManager.start() 调用
**Then** 启动 AxionHelper.app 进程并通过 stdio 建立 MCP 连接

**Given** Helper 已启动
**When** 检查连接状态
**Then** MCP 连接就绪，可以发送工具调用请求

**Given** CLI 正常退出
**When** HelperProcessManager.stop() 调用
**Then** 发送 SIGTERM，Helper 在 3 秒内优雅退出

**Given** Helper 无响应
**When** stop() 等待超过 3 秒
**Then** 发送 SIGKILL 强制终止

**Given** 用户按下 Ctrl-C
**When** 信号处理触发
**Then** Helper 进程被正确清理，不留僵尸进程（NFR8）

**Given** Helper 意外崩溃
**When** 进程监控检测到
**Then** 尝试重启一次 Helper 并重建 MCP 连接

### Story 3.2: Prompt 管理与规划引擎

As a 系统,
I want 根据自然语言任务描述生成结构化的执行计划,
So that 后续执行器可以按步骤完成桌面自动化.

**Acceptance Criteria:**

**Given** Prompts/planner-system.md 文件存在
**When** PromptBuilder.load(name: "planner-system", variables: ["tools": toolList])
**Then** 加载 prompt 内容并将 `{{tools}}` 替换为当前工具列表

**Given** 任务描述 "打开计算器，计算 17 乘以 23" 和截图上下文
**When** LLMPlanner.plan() 调用
**Then** 返回包含 steps 和 stopWhen 的 Plan 对象

**Given** Plan 包含多个步骤
**When** 检查结构
**Then** 每个步骤包含 tool / parameters / purpose / expectedChange 字段

**Given** LLM 输出包含 markdown 围栏 \`\`\`json...\`\`\`
**When** PlanParser 解析
**Then** 正确提取 JSON 并解析为 Plan

**Given** LLM 输出包含前导自然语言文本后跟 JSON
**When** PlanParser 解析
**Then** 跳过文本部分，提取并解析 JSON

**Given** LLM API 调用失败（网络错误）
**When** 重试逻辑触发
**Then** 最多重试 3 次，使用指数退避 1s→2s→4s（NFR6）

**Given** Plan 解析失败
**When** 错误处理
**Then** 记录原始 LLM 响应到 trace，抛出解析错误，不静默丢弃（NFR7）

### Story 3.3: 步骤执行与占位符解析

As a 系统,
I want 按顺序执行 Plan 中的步骤并通过 MCP 调用 Helper,
So that 自然语言指令被转化为实际的桌面操作.

**Acceptance Criteria:**

**Given** Plan 包含 launch_app(Calculator) 步骤
**When** StepExecutor 执行该步骤
**Then** 通过 MCP 调用 Helper 的 launch_app 工具，返回 pid

**Given** 后续步骤参数包含 `$pid`
**When** PlaceholderResolver 解析
**Then** 替换为前一步骤返回的 pid 值

**Given** 后续步骤参数包含 `$window_id`
**When** PlaceholderResolver 解析
**Then** 替换为前一步骤返回的 window_id

**Given** 步骤需要 AX 定位操作（click, type_text 等）
**When** 执行前
**Then** 自动调用 get_window_state 刷新窗口状态，避免使用过期元素索引（FR18）

**Given** 步骤执行失败（如应用未找到）
**When** StepExecutor 处理
**Then** 记录失败位置和原因，返回失败结果以触发重规划

**Given** 共享座椅模式启用，步骤为前台操作（click, type_text）
**When** SafetyChecker 检查
**Then** 阻止执行并返回安全策略错误（FR20）

**Given** --allow-foreground 模式
**When** SafetyChecker 检查前台操作
**Then** 允许执行

### Story 3.4: 任务验证与停止条件评估

As a 系统,
I want 在步骤执行完成后验证任务是否完成,
So that 系统可以判断是继续执行、重规划还是宣告完成.

**Acceptance Criteria:**

**Given** 批次步骤全部执行成功
**When** TaskVerifier 验证
**Then** 获取当前截图和 AX tree 作为验证上下文

**Given** Plan 定义 stopWhen 条件 "Calculator 显示 391"
**When** StopConditionEvaluator 评估
**Then** 结合截图/AX tree 判断是否满足完成条件

**Given** 验证通过，任务完成
**When** 评估结果返回
**Then** 状态为 .done

**Given** 验证发现任务受阻（如应用崩溃、元素不存在）
**When** 评估结果返回
**Then** 状态为 .blocked，携带阻塞原因

**Given** 任务描述不清晰或需要用户输入
**When** 评估结果返回
**Then** 状态为 .needsClarification，携带澄清问题

### Story 3.5: 输出、Trace 与进度显示

As a 用户,
I want 在终端实时看到任务执行进度和结果,
So that 我不需要猜测自动化任务的进展.

**Acceptance Criteria:**

**Given** 任务开始执行
**When** TerminalOutput 显示
**Then** 输出运行 ID 和模式信息（如 "[axion] 模式: 规划执行（小批量）" 和 "[axion] 运行 ID: 20260508-a3f2k1"）

**Given** 步骤开始执行
**When** TerminalOutput 更新
**Then** 显示步骤编号、工具名和目的（如 "[axion] 步骤 1/3: 启动 Calculator"）

**Given** 步骤执行完成
**When** TerminalOutput 更新
**Then** 显示步骤结果（✓ 成功 或 ✗ 失败及原因）

**Given** 任务全部完成
**When** TerminalOutput 显示汇总
**Then** 显示总步数、耗时、重规划次数（如 "[axion] 完成。3 步，耗时 8.2 秒。"）

**Given** --json 标志启用
**When** JSONOutput 输出
**Then** 以结构化 JSON 格式输出完整的执行结果

**Given** 任务运行中
**When** TraceRecorder 记录
**Then** 向 ~/.axion/runs/{runId}/trace.jsonl 追加 JSONL 事件

**Given** trace 文件存在
**When** 用 jq 或 cat 查看
**Then** 每行是一个独立 JSON 对象，包含 ts（ISO8601）和 event（snake_case）字段

### Story 3.6: Run Engine 执行循环状态机

As a 系统,
I want 通过状态机编排 plan → execute → verify → replan 的完整循环,
So that 自然语言任务可以被完整执行和验证.

**Acceptance Criteria:**

**Given** 运行 `axion run "打开计算器"`
**When** RunEngine 启动
**Then** 依次进入 planning → executing → verifying 状态

**Given** 验证结果为 .done
**When** 状态机转换
**Then** 进入 .done 终态，显示完成汇总

**Given** 验证结果为 .blocked
**When** 状态机转换
**Then** 进入 replanning 状态，携带失败上下文重新调用 Planner

**Given** 重规划成功生成新 Plan
**When** 状态机继续
**Then** 回到 executing 状态执行新计划

**Given** 重规划次数达到 maxReplanRetries（默认 3）
**When** 状态机判断
**Then** 进入 .failed 终态

**Given** 用户按下 Ctrl-C
**When** 取消信号传播
**Then** 状态机进入 .cancelled，正确清理 Helper 进程

**Given** 运行 `axion run "任务" --max-steps 5 --max-batches 3`
**When** 执行
**Then** 最多执行 5 个步骤和 3 个批次，超出则终止

**Given** 运行 `axion run "任务" --dryrun`
**When** RunEngine 执行
**Then** 干跑模式：Planner 生成计划后输出到终端，不调用 Helper 执行

**Given** 运行 `axion run "任务" --allow-foreground`
**When** SafetyChecker 检查
**Then** 允许前台/全局操作（click, type_text 等）

### Story 3.7: SDK 集成与 Run Command 完整接入

As a 开发者,
I want Axion 的核心编排通过 SDK 公共 API 实现，`axion run` 命令完整可用,
So that Axion 验证了 SDK 的能力并提供了完整的用户体验.

**Acceptance Criteria:**

**Given** RunEngine 编排执行循环
**When** 检查代码实现
**Then** 使用 SDK 的 Agent Loop（createAgent）管理 turn 循环

**Given** CLI 需要连接 Helper
**When** 检查代码实现
**Then** 使用 SDK 的 MCP Client 连接和调用工具

**Given** Helper 工具集
**When** 注册到 Agent
**Then** 使用 SDK 的 Tool Registry（defineTool）注册

**Given** 步骤执行前
**When** 安全检查
**Then** 使用 SDK 的 Hooks 机制拦截和验证

**Given** 执行过程中进度更新
**When** 消息输出
**Then** 通过 SDK 的 Streaming（AsyncStream<SDKMessage>）管道传递

**Given** 运行 `axion run "打开计算器，计算 17 乘以 23"`
**When** 完整流程执行
**Then** Calculator 打开，显示 391，终端显示完成信息

### Story 3.8: SDK 边界文档与端到端验证

As a SDK 开发者和用户,
I want 有一份清晰的 SDK vs 应用层边界文档，并验证核心场景端到端可用,
So that 后续 SDK 和 Axion 的开发有明确的指导.

**Acceptance Criteria:**

**Given** 所有模块已实现
**When** 审查代码
**Then** 每个 SDK 集成点使用 SDK 公共 API，不绕过 SDK 直接调用底层实现

**Given** SDK 边界文档已编写
**When** 阅读文档
**Then** 每个模块的归属（SDK / 应用层）有明确的理由说明，与 PRD 的 SDK vs 应用层边界表一致

**Given** SDK 短板发现
**When** 记录到边界文档
**Then** 包含问题描述、为什么应该是 SDK 能力、当前的临时变通方案

**Given** Calculator 场景
**When** 运行 `axion run "打开计算器，计算 17 乘以 23"`
**Then** 成功完成，Calculator 显示 391

**Given** TextEdit 场景
**When** 运行 `axion run "打开 TextEdit，输入 Hello World"`
**Then** 成功完成，TextEdit 中包含 Hello World

**Given** Finder 场景
**When** 运行 `axion run "打开 Finder，进入下载目录"`
**Then** 成功完成，Finder 导航到下载目录

**Given** 浏览器场景
**When** 运行 `axion run "打开 Safari，访问 example.com"`
**Then** 成功完成，Safari 打开 example.com

---

# Phase 2 — 成长功能 Epics

> Phase 1（Epic 1–3）已于 2026-05-12 全部完成并通过验证。以下为 PRD Phase 2 成长功能的 Epic 分解。
>
> **SDK 依赖说明：** Epic 4（Memory）依赖 OpenAgentSDK Epic 19 Story 19.1（Cross-run Memory Store）；Epic 6（MCP Server）依赖 SDK Epic 19 Story 19.2（Agent-as-MCP-Server）；Epic 7（Takeover）依赖 SDK Epic 19 Story 19.3（Human-in-the-loop Pause）。Axion 是这些 SDK 新能力的第一个消费者。

## Phase 2 Epic List

### Epic 4: 本地 App Memory — 跨任务学习系统

构建跨次运行的学习系统。每次任务执行后，Axion 自动提取 App 操作模式（常用菜单路径、控件位置、操作序列），通过 SDK 的 MemoryStore（FR68）持久化。后续执行同 App 任务时，Planner 利用历史经验生成更精准的计划，减少试错和重规划次数。

**核心价值：** 用得越多越聪明。第一次操作 Finder 可能需要 2 次重规划，第二次就能一步到位。
**SDK 依赖：** OpenAgentSDK Epic 19 Story 19.1（Cross-run Memory Store）

### Epic 5: HTTP API Server — 外部集成服务

提供 HTTP API 服务模式，外部系统（CI/CD、调度器、其他 Agent）可通过 REST API 提交异步任务、监听 SSE 事件流、查询任务状态和结果。支撑 PRD 旅程三（王强）的核心场景。

**核心价值：** Axion 从 CLI 工具升级为可编程的桌面自动化服务。

### Epic 6: MCP Server Mode — Agent 协作

Axion 通过 SDK 的 AgentMCPServer（FR69）作为 MCP stdio server 运行，暴露桌面操作能力供外部 Agent（如 Claude Code、Cursor Agent）调用。外部 Agent 无需了解 Axion 内部架构，通过标准 MCP 协议即可操控 macOS 桌面。

**核心价值：** Axion 成为 Agent 生态的「macOS 桌面操作插件」。
**SDK 依赖：** OpenAgentSDK Epic 19 Story 19.2（Agent-as-MCP-Server）

### Epic 7: 执行增强 — Takeover 与 Fast Mode

两个互补的执行增强能力：(1) 用户接管机制 — 基于 SDK 的 pause/resume 协议（FR70），自动化受阻时暂停，用户手动完成后恢复；(2) `--fast` 模式 — 小批量规划 + 本地执行，减少 LLM 调用，提升简单任务的响应速度。

**核心价值：** 不完美的自动化比不自动化好（takeover）；简单任务不该等 LLM（fast mode）。
**SDK 依赖：** OpenAgentSDK Epic 19 Story 19.3（Human-in-the-loop Pause Protocol）。`--fast` 模式为纯应用层。

---

## Epic 4: 本地 App Memory — 跨任务学习系统

### Story 4.1: 集成 SDK MemoryStore 与 App Memory 提取

As a 系统,
I want 通过 SDK 的 MemoryStore 积累跨运行的操作经验,
So that Axion 可以在多次运行之间积累和复用 App 操作模式.

**SDK 依赖：** OpenAgentSDK Epic 19 Story 19.1（Cross-run Memory Store）— 提供 MemoryStore 协议、FileBasedMemoryStore 持久化实现和 ToolContext.memoryStore 访问。

**Acceptance Criteria:**

**Given** 任务执行完成
**When** RunEngine 结束
**Then** 自动提取本次运行的 App 操作摘要（目标 App、使用的工具、成功/失败路径），通过 SDK MemoryStore 的 `save(domain:knowledge:)` 持久化

**Given** Memory 文件存在
**When** 查看 SDK 存储目录
**Then** 按 App domain 组织（如 domain="com.apple.calculator"），每个 domain 包含该 App 的操作历史和模式

**Given** Memory 存储超过 30 天的记录
**When** 新任务启动
**Then** SDK MemoryStore 的 `delete(domain:olderThan:)` 自动清理过期记录

**Given** Memory 文件损坏
**When** SDK MemoryStore 加载
**Then** 跳过损坏条目，不阻塞任务执行，记录 warning 日志

**Given** `axion doctor` 运行
**When** 检查 Memory
**Then** 报告已积累 Memory 的 domain 数量和总条目数

### Story 4.2: App Profile 自动积累

As a 系统,
I want 每次任务执行后自动提取 App 操作模式,
So that 后续同 App 任务可以利用积累的经验.

**Acceptance Criteria:**

**Given** Calculator 任务成功完成
**When** 提取操作模式
**Then** 记录：Calculator 的 AX tree 结构特征、常用按钮的 selector 路径、成功操作序列

**Given** 同一 App 积累了多次操作记录
**When** 分析操作模式
**Then** 识别高频操作路径（如「打开 Finder → Cmd+Shift+G → 输入路径」是导航到指定目录的可靠路径）

**Given** 操作失败后被重规划修正
**When** 记录失败经验
**Then** 标记失败的 selector/坐标为不可靠，记录修正后的成功路径

**Given** Memory 中某 App 积累了 3 次以上成功操作
**When** 新任务涉及该 App
**Then** 自动在该 App 的 Memory 中标记为「已熟悉」

### Story 4.3: Memory 增强规划

As a Planner,
I want 在生成计划时利用历史操作经验,
So that 计划更精准，减少试错和重规划次数.

**Acceptance Criteria:**

**Given** Memory 中有 Calculator 的操作记录
**When** Planner 规划 "打开计算器，计算 17 × 23"
**Then** system prompt 注入 Calculator 的 Memory 上下文（已知控件路径、可靠操作序列）

**Given** Memory 中有某 App 的失败经验
**When** Planner 规划涉及该 App 的任务
**Then** prompt 中标注已知不可靠的操作路径，避免重复失败

**Given** Memory 中某 App 标记为「已熟悉」
**When** Planner 规划该 App 的任务
**Then** 使用更紧凑的规划策略（减少验证步骤），缩短执行时间

**Given** 运行 `axion run "任务" --no-memory`
**When** Planner 规划
**Then** 不注入任何 Memory 上下文，行为等同于 Phase 1

**Given** 运行 `axion memory list`
**When** 查看 Memory
**Then** 显示已积累 Memory 的 App 列表和每个 App 的操作次数、最近使用时间

**Given** 运行 `axion memory clear --app com.apple.calculator`
**When** 清除特定 App Memory
**Then** 删除该 App 的 Memory 文件，其他 App 不受影响

---

## Epic 5: HTTP API Server — 外部集成服务

### Story 5.1: HTTP API 基础与任务管理

As a 外部系统,
I want 通过 HTTP API 提交和管理桌面自动化任务,
So that 我可以将 Axion 集成到 CI/CD 管道和调度系统中.

**Acceptance Criteria:**

**Given** 运行 `axion server --port 4242`
**When** server 启动
**Then** 监听指定端口，显示 "Axion API server running on port 4242"

**Given** server 运行中
**When** 发送 `POST /v1/runs` body `{"task": "打开计算器"}`
**Then** 返回 `{"runId": "20260512-abc123", "status": "running"}`，后台启动任务执行

**Given** 任务已提交
**When** 发送 `GET /v1/runs/{runId}`
**Then** 返回任务状态（running / done / failed / cancelled）和已完成的步骤摘要

**Given** 任务已完成
**When** 发送 `GET /v1/runs/{runId}`
**Then** 返回完整执行结果（总步数、耗时、重规划次数、最终状态）

**Given** 发送 `POST /v1/runs` 未提供 task 字段
**When** 请求到达
**Then** 返回 400 错误，message 说明缺少 task 参数

**Given** server 运行中
**When** 发送 `GET /v1/health`
**Then** 返回 `{"status": "ok", "version": "x.y.z"}`

### Story 5.2: SSE 事件流实时进度

As a 外部系统,
I want 通过 SSE 事件流实时监听任务执行进度,
So that 我的平台可以实时显示桌面自动化任务的执行状态.

**Acceptance Criteria:**

**Given** 任务正在执行
**When** 连接 `GET /v1/runs/{runId}/events`（SSE endpoint）
**Then** 实时推送事件流：`step_started`、`step_completed`、`batch_completed`、`run_completed`

**Given** SSE 事件 `step_completed`
**When** 解析事件数据
**Then** 包含 stepIndex、tool、purpose、result（成功/失败）、耗时

**Given** SSE 事件 `run_completed`
**When** 解析事件数据
**Then** 包含最终状态、总步数、总耗时、重规划次数

**Given** 连接 SSE 时任务已完成
**When** 订阅 events
**Then** 立即收到 `run_completed` 事件（重放最终状态），然后关闭连接

**Given** 多个客户端同时订阅同一任务
**When** 事件推送
**Then** 所有客户端都收到相同的事件序列

### Story 5.3: Server 命令与 API 认证

As a 运维人员,
I want Axion server 有安全认证和优雅的生命周期管理,
So that API 服务不会被未授权访问，且可以安全启停.

**Acceptance Criteria:**

**Given** `axion server --port 4242 --auth-key mysecret`
**When** 发送未携带 Authorization header 的请求
**Then** 返回 401 错误

**Given** server 启用了 auth-key
**When** 发送 `Authorization: Bearer mysecret` 的请求
**Then** 正常处理请求

**Given** server 运行中，用户在终端按 Ctrl-C
**When** 信号触发
**Then** 等待所有运行中的任务完成（最多 30 秒），然后优雅关闭

**Given** `axion server --port 4242 --max-concurrent 3`
**When** 已有 3 个任务运行中
**Then** 新提交的任务排队等待，返回 `{"status": "queued", "position": 1}`

**Given** server 启动
**When** 检查绑定地址
**Then** 默认绑定 localhost（127.0.0.1），不暴露到网络。`--host 0.0.0.0` 可选覆盖

---

## Epic 6: MCP Server Mode — Agent 协作

### Story 6.1: 通过 SDK AgentMCPServer 暴露 Axion

As a 外部 Agent（如 Claude Code）,
I want 通过 MCP stdio 协议调用 Axion 的桌面操作能力,
So that 我的 Agent 可以操控 macOS 桌面而不需要了解 Axion 的内部架构.

**SDK 依赖：** OpenAgentSDK Epic 19 Story 19.2（Agent-as-MCP-Server）— 提供 AgentMCPServer 类，通过 stdin/stdout 暴露 MCP JSON-RPC 协议，自动处理工具发现和调用路由。

**Acceptance Criteria:**

**Given** 运行 `axion mcp`
**When** 通过 stdin 发送 MCP initialize 请求
**Then** 返回正确的 initialize 响应，声明 Axion 作为 MCP server 的能力

**Given** MCP 连接已建立
**When** 发送 tools/list
**Then** 返回 Axion 暴露的工具列表（run_task、query_task_status、list_apps 等）

**Given** 外部 Agent 发送 tool_call `run_task`
**When** 参数包含 `{"task": "打开计算器，计算 1+1"}`
**Then** Axion 启动任务执行，返回 runId

**Given** 外部 Agent 发送 tool_call `query_task_status`
**When** 参数包含 runId
**Then** 返回任务当前状态和已执行步骤摘要

**Given** Axion MCP server 运行中
**When** stdin 收到 EOF
**Then** 等待运行中的任务完成后优雅退出

### Story 6.2: `axion mcp` 命令与外部 Agent 集成验证

As a 开发者,
I want 将 Axion 配置为 Claude Code 的 MCP server,
So that Claude Code 可以直接调用 Axion 完成桌面操作.

**Acceptance Criteria:**

**Given** Claude Code 的 MCP 配置中添加 Axion
**When** 配置 `{"mcpServers": {"axion": {"command": "axion", "args": ["mcp"]}}}`
**Then** Claude Code 可以发现和调用 Axion 的工具

**Given** Claude Code 调用 Axion 的 run_task 工具
**When** 任务执行完成
**Then** Claude Code 收到包含执行结果的 tool response

**Given** 运行 `axion mcp --help`
**When** 查看帮助
**Then** 显示 MCP server 模式的用法说明

**Given** `axion mcp` 启动
**When** 检查日志
**Then** 不输出任何 stdout 内容（仅通过 MCP 协议通信），日志写入 stderr

---

## Epic 7: 执行增强 — Takeover 与 Fast Mode

### Story 7.1: 基于 SDK Pause Protocol 的用户接管机制

As a 用户,
I want 在自动化受阻时暂停、手动完成后恢复,
So that 不完美的自动化仍然可以完成任务，而不是直接报错退出.

**SDK 依赖：** OpenAgentSDK Epic 19 Story 19.3（Human-in-the-loop Pause Protocol）— 提供 `Agent.pause(reason:)`、`Agent.resume(context:)`、`Agent.abort()` 和内置 `pause_for_human` 工具。Axion 在 SDK 协议之上实现终端交互（stdin 等待用户输入）。

**Acceptance Criteria:**

**Given** 任务执行遇到 `blocked` 状态
**When** RunEngine 检测到不可自动恢复的阻塞
**Then** 调用 SDK 的 `Agent.pause(reason: "任务受阻：{阻塞原因}")`，SDK 发出 `.paused` 消息，Axion 在终端显示接管提示

**Given** Agent 处于 SDK paused 状态
**When** 终端显示提示
**Then** 输出 "任务受阻：{阻塞原因}。手动完成后按 Enter 继续，或输入 'skip' 跳过此步骤，或输入 'abort' 终止任务"

**Given** 用户按 Enter
**When** 恢复执行
**Then** 调用 SDK 的 `Agent.resume(context: "用户已完成手动操作")`，截取当前屏幕状态，Verifier 重新评估

**Given** 用户输入 'skip'
**When** 跳过当前步骤
**Then** 调用 SDK 的 `Agent.resume(context: "skip")`，标记当前步骤为 skipped，继续执行后续步骤

**Given** 用户输入 'abort'
**When** 终止任务
**Then** 调用 SDK 的 `Agent.abort()`，进入 `cancelled` 状态，显示已完成的步骤摘要

**Given** SDK paused 超过 5 分钟无用户输入
**When** 超时
**Then** SDK 发出 `.pausedTimeout` 消息，Axion 进入 `failed` 状态，输出超时提示

**Given** `--allow-foreground` 模式
**When** 任务受阻进入 takeover
**Then** 前台操作限制暂时解除，用户可以手动操作桌面

### Story 7.2: `--fast` 模式

As a 用户,
I want 用 `--fast` 模式快速执行简单任务,
So that 简单操作不需要等待完整的 LLM 规划循环.

**Acceptance Criteria:**

**Given** 运行 `axion run "打开计算器" --fast`
**When** fast 模式启动
**Then** 使用轻量规划策略：单步规划 + 立即执行 + 简化验证，减少 LLM 调用次数

**Given** fast 模式的 LLM 规划
**When** 生成计划
**Then** prompt 明确指示生成最小步骤计划（1-3 步），不请求截图和完整 AX tree

**Given** fast 模式执行
**When** 每步执行后
**Then** 简化验证：只检查工具调用是否成功（ToolResult.isError == false），不额外截图验证

**Given** fast 模式下步骤执行失败
**When** 失败检测
**Then** 不触发重规划，直接报告失败并建议用户去掉 `--fast` 重新尝试

**Given** fast 模式执行成功
**When** 任务完成
**Then** 显示 "Fast mode 完成。N 步，耗时 X 秒。" 以及提示 "如需更精确执行，可去掉 --fast 重试"

**Given** 运行 `axion run "打开计算器，计算 17 乘以 23" --fast`
**When** 完整流程执行
**Then** 成功完成，响应时间显著短于标准模式（目标：减少 50% 以上 LLM 调用）

---

## Phase 2 FR 追溯

| FR | 来源 | Epic | SDK 依赖 | 说明 |
|----|------|------|----------|------|
| FR35 (JSON 输出) | PRD Phase 2 | 已在 Story 3.5 完成 | 无 | `--json` 标志已实现 |
| FR42 (Memory 提取) | Phase 2 新增 | Epic 4 | SDK FR68 (MemoryStore) | 跨任务学习 |
| FR43 (Memory 增强规划) | Phase 2 新增 | Epic 4 | SDK FR68 | 利用经验优化计划 |
| FR44 (Memory 管理 CLI) | Phase 2 新增 | Epic 4 | SDK FR68 | axion memory list/clear |
| FR45 (HTTP API) | Phase 2 新增 | Epic 5 | 无 | 外部集成服务 |
| FR46 (SSE 事件流) | Phase 2 新增 | Epic 5 | 无 | 实时进度推送 |
| FR47 (MCP Server) | Phase 2 新增 | Epic 6 | SDK FR69 (AgentMCPServer) | Agent 协作 |
| FR48 (Takeover) | Phase 2 新增 | Epic 7 | SDK FR70 (Pause Protocol) | 人机协作 |
| FR49 (--fast 模式) | Phase 2 新增 | Epic 7 | 无 | 快速执行 |

## Phase 2 新增 NFR

- NFR24: HTTP API 请求响应时间 < 100ms（不含任务执行时间）
- NFR25: SSE 事件推送延迟 < 500ms（从事件发生到客户端收到）
- NFR26: MCP server 工具调用响应时间 < 200ms（不含任务执行时间）
- NFR27: Memory 存储占用磁盘空间 < 10MB（自动清理后）
- NFR28: `--fast` 模式下 LLM 调用次数比标准模式减少 50% 以上
- NFR29: Server 模式支持至少 10 个并发 SSE 连接

## Phase 2 优先级与 SDK 依赖

| 优先级 | Epic | SDK 依赖 | 理由 |
|--------|------|----------|------|
| P0 | Epic 7 (Takeover & Fast) | SDK Story 19.3 (Pause Protocol) | 提升核心体验，--fast 无 SDK 依赖可先行 |
| P1 | Epic 4 (Memory) | SDK Story 19.1 (MemoryStore) | 产品差异化的核心，用得越多越聪明 |
| P2 | Epic 5 (HTTP API) | 无 | 解锁外部集成场景，纯应用层可独立推进 |
| P3 | Epic 6 (MCP Server) | SDK Story 19.2 (AgentMCPServer) | Agent 生态位，依赖 SDK 新能力 |

**实施前提：** OpenAgentSDK 的 Epic 19 需先于 Axion Phase 2 完成。建议 SDK 和 Axion 并行开发：Axion 先做 Epic 5（HTTP API，无 SDK 依赖）和 Epic 7 的 --fast 部分，SDK Epic 19 完成后再做 Memory、Takeover 和 MCP Server 集成。

**建议实施顺序：Epic 5（无 SDK 依赖）→ SDK Epic 19 → Epic 7 → Epic 4 → Epic 6**

---

# Phase 3 — 愿景 Epics

> Phase 1（Epic 1–3）MVP 和 Phase 2（Epic 4–7）成长功能均已完成。以下为 PRD Phase 3 愿景功能的 Epic 分解。
>
> Phase 3 定位为「从工具到平台」的跨越——将 Axion 从单窗口 CLI 自动化工具进化为支持跨应用工作流、可录制技能、拥有原生 GUI、可供第三方扩展的桌面自动化平台。
>
> **前置条件：** Phase 1 和 Phase 2 全部完成。Epic 8（多窗口）和 Epic 9（录制技能）依赖 Phase 1/2 的 Helper 工具集和 Agent 循环；Epic 10（菜单栏 UI）依赖 Phase 2 的 HTTP API；Epic 11（SDK 生态）依赖 Phase 1 的 SDK 边界文档和 Phase 2 的 MCP Server 模式。

## Phase 3 Epic List

### Epic 8: 多窗口、多 App 工作流

当前 Axion 每次操作聚焦一个窗口。Epic 8 让 Axion 能同时追踪多个应用窗口的状态，协调跨应用的数据传递和操作编排——从浏览器复制数据到 Excel、从邮件客户端提取附件到 Finder、在多个应用间完成端到端工作流。

**核心价值：** 真正的桌面自动化不是操作一个应用，而是串起多个应用完成端到端工作流。
**依赖：** Phase 1 Helper 工具集（FR24–FR32）、Phase 1 执行循环（Epic 3）

### Epic 9: 录制 → 编译 → 技能复用

用户演示一遍操作，Axion 自动录制操作序列并编译为可复用的「技能」（Skill）。下次需要同样操作时，直接调用技能执行，无需 LLM 规划——从「每次都思考」进化到「学一次，用无数次」。

**核心价值：** 把 LLM 规划成本降为零。常用操作从「N 秒 + API 调用」变成「毫秒级本地回放」。
**依赖：** Phase 1 Helper 工具集、Phase 1 执行引擎

### Epic 10: macOS 菜单栏 UI

原生 macOS 菜单栏常驻应用，提供快捷操作入口、任务状态面板、技能快捷键和配置界面。用户不再需要打开终端，直接从菜单栏发起和管理自动化任务。

**核心价值：** Axion 从 CLI 工具进化为原生 Mac 应用，触达非技术用户。
**依赖：** Phase 2 HTTP API（Epic 5）作为后端通信通道

### Epic 11: 第三方 SDK 生态

让第三方开发者能基于 OpenAgentSDK 构建自己的 macOS 桌面 Agent 应用。Axion 作为旗舰参考实现，提供项目模板、插件化工具注册接口和开发者文档。

**核心价值：** SDK 的价值不在于一个应用，在于一个生态。
**依赖：** Phase 1 SDK 边界文档（FR41）、Phase 2 MCP Server 模式（Epic 6）

---

## Epic 8: 多窗口、多 App 工作流

Axion 从单窗口操作升级为跨应用协调。核心变化：Planner 可以在计划中引用多个目标窗口，Executor 能在窗口间切换操作，数据通过剪贴板或文件系统在应用间传递。

### Story 8.1: 多窗口状态追踪与上下文管理

As a Planner,
I want 同时追踪多个应用窗口的状态,
So that 我可以在规划时了解所有相关窗口的布局和内容.

**Acceptance Criteria:**

**Given** 多个应用正在运行（如 Chrome 和 TextEdit）
**When** 调用 list_windows
**Then** 返回所有应用的窗口列表，每项包含 app_name、pid、window_id、title、bounds 和 z-order

**Given** 任务涉及两个应用的交互
**When** Planner 生成计划
**Then** 计划中的步骤可以引用不同的 window_id，并通过 `$window_id:Chrome` 和 `$window_id:TextEdit` 占位符区分

**Given** 执行过程中窗口焦点切换
**When** Executor 在窗口间切换操作
**Then** 每次切换前自动刷新目标窗口状态，确保 AX 元素索引有效（复用 FR18 机制）

**Given** 某个目标窗口被用户最小化
**When** Executor 尝试操作该窗口
**Then** 检测到窗口不可见，自动恢复窗口后再执行操作，或触发 takeover 让用户手动恢复

**Given** 多窗口上下文
**When** TraceRecorder 记录事件
**Then** 每个步骤事件包含 window_id 和 app_name 字段，trace 文件可回溯完整的多窗口操作序列

### Story 8.2: 跨应用工作流编排

As a 用户,
I want 用一句话描述跨多个应用的工作流,
So that Axion 可以自动协调多个应用完成端到端任务.

**Acceptance Criteria:**

**Given** 运行 `axion run "从 Safari 复制网页标题，粘贴到 TextEdit 文档"`
**When** Planner 规划
**Then** 生成包含跨应用操作的计划：激活 Safari → 获取标题 → 复制到剪贴板 → 切换到 TextEdit → 粘贴

**Given** 跨应用计划执行中
**When** 步骤需要切换目标应用
**Then** Executor 通过 `list_windows` + 窗口激活确保目标应用获得焦点，再执行后续操作

**Given** 跨应用数据传递涉及剪贴板
**When** Planner 规划剪贴板操作
**Then** 使用 cmd+c / cmd+v 的 hotkey 操作，Executor 在复制后验证剪贴板内容再执行粘贴

**Given** 跨应用计划中某一步失败（如目标应用未安装）
**When** 执行失败
**Then** 携带失败上下文触发重规划，Planner 可以选择跳过失败步骤或寻找替代路径

**Given** 运行 `axion run "打开浏览器搜索 'Swift Agent'，把第一个结果复制到备忘录"`
**When** 完整流程执行
**Then** 成功协调 Safari/Chrome 和 Notes/TextEdit 两个应用完成端到端操作

### Story 8.3: 窗口布局管理

As a 用户,
I want Axion 自动管理窗口位置和大小,
So that 多窗口工作流可以在最优布局下执行，避免窗口遮挡.

**Acceptance Criteria:**

**Given** 任务涉及两个窗口交互
**When** Planner 规划
**Then** 可选择在计划中包含窗口布局步骤（如并排显示两个窗口），Planner prompt 理解 `arrange_windows` 指令

**Given** 用户运行 `axion run "把 Safari 和 TextEdit 并排显示，左 Safari 右 TextEdit"`
**When** 执行
**Then** AxionHelper 的窗口管理服务调整两个窗口的 bounds 实现并排布局

**Given** 窗口布局调整后
**When** 后续步骤执行
**Then** 所有窗口坐标基于新布局重新计算，不使用布局前的过期坐标

**Given** 布局操作完成
**When** 任务结束
**Then** 可选恢复原始窗口布局（`--restore-layout` 标志），或保持当前布局

---

## Epic 9: 录制 → 编译 → 技能复用

用户演示操作，Axion 录制为结构化序列，编译为可复用技能（Skill）。技能以 JSON 文件存储在 `~/.axion/skills/`，执行时直接回放，无需 LLM 规划。技能支持参数化（如 URL、文件路径），适应不同的输入。

### Story 9.1: 操作录制引擎

As a 用户,
I want Axion 录制我的桌面操作,
So that 常用操作可以被记录下来供后续复用.

**Acceptance Criteria:**

**Given** 运行 `axion record "打开计算器"`
**When** 录制模式启动
**Then** Helper 开始监听用户操作（点击、键盘输入、应用切换），终端显示 "录制中... 按 Ctrl-C 结束录制"

**Given** 录制模式下用户操作桌面
**When** 用户点击 (x, y) 坐标
**Then** 记录 click 事件：坐标、目标窗口、时间戳

**Given** 录制模式下用户输入文本
**When** 用户在输入框中打字
**Then** 记录 type_text 事件：输入内容、目标窗口

**Given** 录制模式下用户切换应用
**When** 用户 Cmd+Tab 切换
**Then** 记录 app_switch 事件：目标应用名

**Given** 用户按 Ctrl-C 结束录制
**When** 录制停止
**Then** 将录制序列保存为 `~/.axion/recordings/{name}.json`，包含操作列表和窗口上下文快照

**Given** 录制过程中 Helper 操作执行失败
**When** 检测到失败
**Then** 记录失败事件但不中断录制，继续监听后续操作

### Story 9.2: 录制编译为可复用技能

As a 用户,
I want 将录制的操作编译为可复用的技能,
So that 下次可以直接调用技能，不需要 LLM 重新规划.

**Acceptance Criteria:**

**Given** 录制文件存在 `~/.axion/recordings/open_calculator.json`
**When** 运行 `axion skill compile open_calculator`
**Then** 将录制编译为技能文件 `~/.axion/skills/open_calculator.json`，包含结构化的步骤序列

**Given** 编译过程中发现可参数化的值
**When** 分析录制内容
**Then** 识别可变部分（如 URL、文件路径、搜索关键词）并标记为参数，编译后技能支持 `{{param}}` 占位符

**Given** 运行 `axion skill compile open_calculator --param url --param search_term`
**When** 编译完成
**Then** 技能文件中指定的值被替换为参数占位符，执行时由用户提供具体值

**Given** 编译后的技能文件
**When** 检查格式
**Then** 为标准 JSON，包含 name、description、parameters、steps（工具调用序列）字段，可人工编辑

**Given** 录制中包含冗余操作（如多余的窗口切换）
**When** 编译
**Then** 自动去重和优化操作序列，移除无效的中间步骤

### Story 9.3: 技能库管理与执行

As a 用户,
I want 管理和执行已保存的技能,
So that 常用操作可以一键执行，无需每次描述任务.

**Acceptance Criteria:**

**Given** 技能文件存在 `~/.axion/skills/open_calculator.json`
**When** 运行 `axion skill run open_calculator`
**Then** 直接回放技能中的步骤序列，不调用 LLM，通过 MCP 调用 Helper 执行

**Given** 技能包含参数 `{{url}}`
**When** 运行 `axion skill run open_calculator --param url=https://example.com`
**Then** 将参数值注入步骤序列后执行

**Given** 运行 `axion skill list`
**When** 查看技能库
**Then** 显示所有已保存的技能：名称、描述、参数列表、上次使用时间、执行次数

**Given** 运行 `axion skill delete open_calculator`
**When** 删除技能
**Then** 移除技能文件，`axion skill list` 不再显示该技能

**Given** 技能执行中某步骤失败
**When** 回放失败
**Then** 记录失败位置，尝试重试一次（元素坐标可能因窗口位置变化而失效），仍失败则报告错误并建议用 `axion run` 代替

**Given** 技能执行成功
**When** 回放完成
**Then** 显示 "技能完成。N 步，耗时 X 秒。" 以及技能名称，响应时间显著短于 LLM 规划模式

---

## Epic 10: macOS 菜单栏 UI

Axion 作为 macOS 菜单栏常驻应用（NSStatusItem），通过 HTTP API 与 CLI 后端通信。提供任务状态面板、快捷操作入口、全局热键和技能快捷触发。

### Story 10.1: 菜单栏常驻状态与服务通信

As a 用户,
I want Axion 在菜单栏常驻显示状态,
So that 我可以随时了解 Axion 的运行状态并快速访问功能.

**Acceptance Criteria:**

**Given** 运行 `AxionBar`（菜单栏 App）
**When** 应用启动
**Then** 在 macOS 菜单栏显示状态图标（空闲/运行中），点击图标显示下拉菜单

**Given** 菜单栏 App 启动
**When** 检查后端连接
**Then** 自动检测 `axion server` 是否在 localhost:4242 运行，未运行时显示 "启动服务" 菜单项

**Given** 用户点击 "启动服务"
**When** 触发服务启动
**Then** 在后台启动 `axion server` 进程，就绪后菜单栏状态变为 "就绪"

**Given** 菜单栏 App 运行中
**When** 用户点击菜单栏图标
**Then** 显示下拉菜单包含：快速执行、技能列表、任务历史、设置、退出

**Given** 后端服务异常退出
**When** 菜单栏 App 检测到连接断开
**Then** 状态图标变为 "未连接"，下拉菜单提供 "重启服务" 选项

### Story 10.2: 任务管理与实时状态面板

As a 用户,
I want 从菜单栏查看和管理任务执行状态,
So that 我不需要切换到终端就能了解自动化任务的进展.

**Acceptance Criteria:**

**Given** 菜单栏 App 和后端服务均运行
**When** 用户点击 "快速执行"
**Then** 弹出输入框，用户输入自然语言任务描述后提交执行

**Given** 任务正在执行
**When** 查看菜单栏状态
**Then** 状态图标显示执行中动画，下拉菜单显示当前任务名称和进度（步骤 N/M）

**Given** 用户点击正在执行的任务
**When** 查看详情
**Then** 弹出面板显示实时日志流：步骤描述、工具调用、执行结果（通过 SSE 事件流获取）

**Given** 任务执行完成
**When** 查看结果
**Then** 菜单栏弹出通知（macOS native notification）：任务完成/失败 + 摘要

**Given** 用户点击 "任务历史"
**When** 查看历史
**Then** 显示最近 20 条任务记录，每条包含任务描述、状态、执行时间

### Story 10.3: 全局热键与技能快捷触发

As a 用户,
I want 通过全局热键快速触发常用技能,
So that 常用自动化操作可以一键执行，无需打开任何界面.

**Acceptance Criteria:**

**Given** 菜单栏 App 运行中
**When** 用户在设置中配置全局热键
**Then** 可以为技能或常用任务绑定全局热键（如 Cmd+Shift+A 触发 "打开计算器" 技能）

**Given** 全局热键已配置
**When** 用户按下热键组合
**Then** 触发绑定的技能或任务，菜单栏图标显示执行状态

**Given** 菜单栏 App 首次启动
**When** 检查 Accessibility 权限
**Then** 全局热键需要 Accessibility 权限，未授权时提示用户授权

**Given** 技能列表中有已编译的技能
**When** 用户点击 "技能" 菜单
**Then** 显示所有可用技能的列表，每个技能可直接点击执行

**Given** 运行 `axion skill run open_calculator` 或通过菜单栏触发技能
**When** 执行方式不同
**Then** 两种方式执行结果一致（技能回放，无 LLM 调用）

---

## Epic 11: 第三方 SDK 生态

让第三方开发者基于 OpenAgentSDK 构建自己的 macOS 桌面 Agent 应用。提供项目模板脚手架、插件化工具注册接口和开发者文档。Axion 作为旗舰参考实现。

### Story 11.1: Agent 项目模板与脚手架 CLI

As a 第三方开发者,
I want 通过模板快速创建基于 SDK 的 Agent 项目,
So that 我可以在几分钟内搭建好项目骨架，专注于业务逻辑.

**Acceptance Criteria:**

**Given** 安装了 OpenAgentSDK
**When** 运行 SDK 提供的脚手架命令（如 `swift package init --type agent`）
**Then** 生成标准 Agent 项目结构：main.swift、Tools/、Prompts/、Config/ 目录

**Given** 生成的项目模板
**When** 运行 `swift build`
**Then** 编译成功，包含一个可运行的 Agent 骨架（自定义工具 + system prompt）

**Given** 模板中的 README
**When** 阅读文档
**Then** 包含：项目结构说明、如何添加自定义工具、如何配置 system prompt、如何运行和调试

**Given** 模板中的示例工具
**When** 查看代码
**Then** 包含一个完整的自定义工具示例（如 `hello_world` 工具），展示 `@Tool` 宏用法

**Given** Axion 仓库的 SDK 边界文档
**When** 开发者阅读
**Then** 可作为参考指南理解哪些是 SDK 提供的能力，哪些需要自己实现

### Story 11.2: 插件化工具注册与自定义 Agent 扩展

As a 第三方开发者,
I want 为我的 Agent 注册自定义工具,
So that 我的 Agent 可以执行特定领域的操作.

**Acceptance Criteria:**

**Given** SDK 的工具注册 API
**When** 开发者创建自定义工具
**Then** 通过 `@Tool` 宏 + `@Parameter` 定义工具签名，实现 `perform()` 方法，无需理解 MCP 协议细节

**Given** 开发者注册了多个自定义工具
**When** Agent 运行
**Then** LLM 可以在规划时发现和使用所有已注册的工具，工具调用走 SDK 的标准 MCP 通道

**Given** Axion 的 MCP Server 模式（Epic 6）
**When** 第三方开发者想使用 Axion 的桌面操作能力
**Then** 通过 `axion mcp` 暴露的工具（如 run_task），在自己的 Agent 中调用 Axion 完成桌面操作，无需重新实现 AX 引擎

**Given** 第三方 Agent 需要特定的 macOS 操作（如模拟器控制）
**When** 开发者实现自定义 Helper
**Then** 参考 AxionHelper 架构（MCP Server + AX Service 分离），创建自己的 Helper App，通过 MCP stdio 与 Agent 通信

**Given** SDK 的 Hooks 机制
**When** 开发者需要添加安全策略
**Then** 通过 Hook 拦截工具调用，实现自定义的权限检查和审计逻辑

### Story 11.3: 开发者文档与示例库

As a 第三方开发者,
I want 有完整的开发文档和示例代码,
So that 我可以快速上手并避免踩坑.

**Acceptance Criteria:**

**Given** OpenAgentSDK 仓库
**When** 浏览文档
**Then** 包含以下指南：快速开始（5 分钟跑通第一个 Agent）、工具开发指南、MCP 集成指南、Agent 自定义指南、Session 和 Memory 使用指南

**Given** SDK 示例目录
**When** 查看示例
**Then** 包含至少 5 个完整示例：基础 Agent、自定义工具、MCP 集成、Session 管理、Memory 使用

**Given** Axion 作为参考实现
**When** 开发者阅读 Axion 源码
**Then** 关键模块（Planner、Executor、Memory、MCP Server）有清晰的内联文档说明设计决策

**Given** SDK 的 API 文档
**When** 查看 `createAgent` 等 API
**Then** 包含参数说明、使用场景、返回类型和常见错误处理模式

**Given** 开发者完成自己的 Agent
**When** 准备分发
**Then** 文档提供打包和分发指南（SPM package 结构、Helper App 签名、Homebrew formula）

---

## Phase 3 FR 追溯

| FR | 来源 | Epic | SDK 依赖 | 说明 |
|----|------|------|----------|------|
| FR50 (多窗口状态追踪) | Phase 3 新增 | Epic 8 | 无 | 扩展 list_windows 和 Plan 模型 |
| FR51 (跨应用工作流) | Phase 3 新增 | Epic 8 | 无 | Planner + Executor 跨窗口协调 |
| FR52 (窗口布局管理) | Phase 3 新增 | Epic 8 | 无 | Helper 新增窗口定位能力 |
| FR53 (操作录制) | Phase 3 新增 | Epic 9 | 无 | Helper 新增事件监听模式 |
| FR54 (录制编译) | Phase 3 新增 | Epic 9 | 无 | 录制 → 技能的编译管道 |
| FR55 (技能执行) | Phase 3 新增 | Epic 9 | 无 | 本地回放，无 LLM 调用 |
| FR56 (技能管理 CLI) | Phase 3 新增 | Epic 9 | 无 | axion skill 命令组 |
| FR57 (菜单栏 UI) | Phase 3 新增 | Epic 10 | 无 | 独立 macOS App |
| FR58 (任务管理面板) | Phase 3 新增 | Epic 10 | 依赖 Epic 5 HTTP API | 通过 API 与后端通信 |
| FR59 (全局热键) | Phase 3 新增 | Epic 10 | 无 | macOS Accessibility API |
| FR60 (项目模板) | Phase 3 新增 | Epic 11 | SDK 提供脚手架 | SPM 模板 |
| FR61 (插件化工具) | Phase 3 新增 | Epic 11 | SDK 工具注册 API | @Tool 宏 |
| FR62 (开发者文档) | Phase 3 新增 | Epic 11 | 无 | 文档和示例 |

## Phase 3 新增 NFR

- NFR30: 多窗口操作时，窗口切换延迟 < 300ms（从激活窗口到获取焦点）
- NFR31: 技能执行响应时间 < 100ms（本地回放，无 LLM 调用，首步执行延迟）
- NFR32: 菜单栏 App 常驻内存 < 15MB
- NFR33: 录制模式下的 CPU 开销 < 5%（不影响用户正常桌面操作体验）
- NFR34: 技能编译后的执行准确率 >= 95%（相同窗口布局和分辨率下）
- NFR35: 全局热键响应延迟 < 200ms（从按键到触发动作）
- NFR36: 技能文件大小 < 100KB（单技能，包含步骤序列和元数据）

## Phase 3 优先级与依赖

| 优先级 | Epic | SDK 依赖 | 理由 |
|--------|------|----------|------|
| P0 | Epic 8 (多窗口工作流) | 无 | 扩展现有核心能力，解锁最常见的高级使用场景 |
| P1 | Epic 9 (录制技能) | 无 | 从 LLM 依赖进化到本地执行，降本提效，纯应用层 |
| P2 | Epic 10 (菜单栏 UI) | 依赖 Epic 5 HTTP API | 拓宽用户群到非技术用户，需要后端 API 支撑 |
| P3 | Epic 11 (SDK 生态) | SDK 持续完善 | 长期生态价值，依赖 SDK 文档化和模板化 |

**实施建议顺序：Epic 8 → Epic 9 → Epic 10 → Epic 11**

**理由：**
- Epic 8（多窗口）和 Epic 9（录制技能）无外部 SDK 依赖，可立即推进
- Epic 8 优先于 Epic 9：多窗口是跨应用工作流的基础，录制技能也会涉及多窗口操作
- Epic 10 在 Epic 8/9 之后：菜单栏 UI 是入口升级，核心能力先完善
- Epic 11 最后：生态建设需要 Axion 自身成熟度足够高，文档和模板才有参考价值

**关键技术决策（Phase 3 实施前需确定）：**

| 决策 | 说明 | 影响 | 状态 |
|------|------|------|------|
| D9: 录制引擎实现方式 | AX Observer（系统事件监听）vs 辅助功能监听 vs 轮询 | 录制精度、CPU 开销、权限要求 | ✅ 已决定：CGEvent Tap (listen-only) + NSWorkspace Notification（Epic 9） |
| D10: 菜单栏 App 架构 | 独立 App vs Framework + App Extension | 进程模型、通信方式、分发策略 | ✅ 已决定：独立 SPM executable target（AxionBar），SwiftUI App + AppKit NSStatusItem 混合方案，通过 HTTP API 与 CLI 后端通信（Epic 10） |
| D11: 技能文件格式 | 纯 JSON vs DSL（YAML/Markdown）vs Swift Codable | 可读性、可编辑性、参数化能力 | ✅ 已决定：纯 JSON + Codable（Epic 9） |
| D12: 跨应用数据传递机制 | 剪贴板 vs 临时文件 vs AX 值提取 | 可靠性、数据类型支持、隐私 | ✅ 已决定：剪贴板（Epic 8） |

---

# Phase 4 — 执行质量与 API 成熟度 Epics

> Phase 1-3（Epic 1-11）均已完成。Phase 4 Epic 12（Memory 生命周期）和 Epic 13（执行安全与成本控制）已完成。以下为基于竞品 OpenClick 对比分析提炼的 Phase 4 Epics，聚焦 Axion 在 Memory 质量、执行安全、API 规范和运维便利性方面的差距补齐。
>
> **核心理念：** Phase 1-3 构建了完整的功能版图（从 CLI 到 MCP Server 到菜单栏 UI），Phase 4 专注于让这些功能更可靠、更省钱、更易集成。
>
> **无新增 SDK 依赖：** Phase 4 所有 Epic 均为应用层改进，不依赖 OpenAgentSDK 新增能力。

## Phase 4 Epic List

### Epic 12: Memory 生命周期与质量控制

将 Axion 的 Memory 系统从「记录-检索」升级为结构化的知识生命周期管理。引入 candidate → active → retired 状态流转、置信度评分、证据计数和三类记忆分类（affordance / avoid / observation），确保记忆质量随使用不断提升，避免一次性失败产生错误的长期记忆。同时增加 Memory 导入/导出能力，支持在多台机器间共享经验。

**核心价值：** 用得越多越聪明，但必须「聪明得对」——一条错误记忆比没有记忆更糟。
**依赖：** Epic 4（Memory 基础设施）
**竞品参考：** OpenClick `src/memory.ts` — AppMemoryFact 模型（candidate/active/retired、confidence、evidence_count）

### Epic 13: 执行安全与成本控制

三个互补的执行增强能力：(1) 桌面级运行锁——同一时刻只有一个 live run 控制桌面，防止多任务冲突；(2) 视觉增量检查——在调用 LLM verifier 前先做本地截图对比，画面无变化则跳过验证调用，节省成本；(3) 精细预算控制——新增 `--max-model-calls` 和 `--max-screenshots` 限制，加上 trace 中的成本遥测。

**核心价值：** 安全不贵，贵的是不安全。一次桌面冲突事故的成本远高于预防机制。
**依赖：** Epic 3（执行循环）、Epic 5（HTTP API Server，用于 run lock 检查）
**竞品参考：** OpenClick `run.lock` 文件锁、`visual-delta` 检查、`--max-model-calls`/`--max-screenshots` 参数

### Epic 14: API 规范化与集成友好度

将 Axion HTTP API 的输出契约升级为 OpenClick 的 StandardTaskOutput 规范，增加结构化的 result.kind（answer vs confirmation）、intervention 数据、schema_version 版本控制。新增 Capabilities 端点和 Settings API，让外部集成方可以程序化发现能力、管理配置。

**核心价值：** API 是 Axion 从「工具」变成「平台」的关键接口，规范的契约决定集成成本。
**依赖：** Epic 5（HTTP API Server）
**竞品参考：** OpenClick `src/api-runs.ts` — StandardTaskOutput、ApiRunStatus、Capabilities endpoint

### Epic 15: Takeover 学习与桌面活动感知

两个互补的能力：(1) Takeover 学习——用户手动接管后，系统自动将接管经验记录为结构化 Memory（成功为 affordance，失败为 avoid 规则），使人工干预转化为可复用的自动化知识；(2) 桌面活动检测——在 shared-seat 模式下检测用户手动操作，自动禁用该次 run 的学习，防止「污染证据」变成错误记忆。

**核心价值：** 用户的手动操作是最有价值的训练数据，但不能让噪音污染信号。
**依赖：** Epic 7（Takeover 机制）、Epic 4（Memory 基础设施）、Epic 12（Memory 生命周期）
**竞品参考：** OpenClick `memory learn-takeover` 命令、external seat activity detection

### Epic 16: Daemon 模式与运维便利性

Axion server 可安装为 macOS launchd 用户守护进程，开机自启、崩溃自动重启。新增 `axion daemon install/status/uninstall` 命令，以及 HTTP API 中的 Settings 管理（GET/POST/DELETE api-key），让 API 部署和维护更接近生产级。

**核心价值：** 从「手动启动服务」到「开机即用」，是从开发工具到生产服务的最后一公里。
**依赖：** Epic 5（HTTP API Server）
**竞品参考：** OpenClick `src/daemon.ts` — launchd daemon install/status/uninstall

---

## Epic 12: Memory 生命周期与质量控制

### Story 12.1: Memory Fact 模型升级

As a 系统,
I want Memory 条目有生命周期状态和置信度评分,
So that 记忆质量随使用不断提升，一次性失败不会产生错误的长期记忆.

**OpenClick 参考：**
- `src/memory.ts:11-32` — `AppMemoryFact` 接口定义：status（candidate/active/retired）、confidence（number）、evidence_count（number）、source（local/imported）
- `src/memory.ts:120-170` — `addAppMemoryFact()` 函数：新增记忆时设 status=candidate、confidence=0.5、evidence_count=1；合并已有记忆时累加 evidence_count 并取 max confidence
- `src/memory.ts:411-425` — `promoteOrRetire()` 函数：evidence_count >= 2 且 confidence >= 0.65 时提升为 active；retired 状态的记忆不再变化
- `src/memory.ts:318-338` — `normalizeFact()` 函数：校验 confidence 范围 [0,1]、evidence_count >= 0、默认 status 为 candidate
- `src/memory.ts:362-375` — `mergeMemoryFacts()` 函数：合并导入记忆时取 max confidence、累加 evidence_count
- `src/memory.ts:391-398` — `selectActiveFacts()` 函数：只选 active 状态的记忆，按 confidence 排序

**Acceptance Criteria:**

**Given** 当前 KnowledgeEntry 模型
**When** 升级为 AppMemoryFact 模型
**Then** 新增字段：status（candidate/active/retired）、confidence（0.0-1.0）、evidence_count（Int）、source（local/imported）、scope（可选 String）、cause（可选 String）

**Given** 一次任务执行产生新的记忆
**When** 提取 App 操作模式
**Then** 新记忆以 candidate 状态写入，confidence 初始值为 0.5-0.7（根据操作复杂度调整）

**Given** 同一事实被后续运行重复观察到
**When** evidence_count 累积到 2 次
**Then** 自动提升为 active 状态，confidence 提升 0.1

**Given** 同一事实的后续观察与已有记忆矛盾
**When** 冲突检测
**Then** 不自动覆盖，而是创建新的 candidate 条目，由证据累积决定最终状态

**Given** active 状态的记忆连续 30 天未被验证（未在后续运行中观察到）
**When** MemoryCleanupService 执行
**Then** 自动降级为 retired 状态

**Given** retired 状态的记忆再次被观察到
**When** 重新激活
**Then** 恢复为 candidate 状态，evidence_count 重置为 1

### Story 12.2: 三类记忆分类

As a Planner,
I want 记忆分为 affordance（可用能力）、avoid（避坑规则）和 observation（观察）三类,
So that planner prompt 可以根据类型注入不同策略的上下文.

**OpenClick 参考：**
- `src/memory.ts:46` — `MemoryKind` 类型定义：`"affordance" | "avoid" | "observation"`
- `src/memory.ts:22-31` — `AppMemory` 接口：按 `affordances`、`avoid`、`observations` 三个数组组织记忆
- `src/memory.ts:226-250` — `renderRelevantMemoriesForPrompt()` 函数：将三类记忆渲染为 planner prompt 文本，affordance 标注为推荐能力、avoid 标注为 caution 警告、observation 标注为环境备注
- `src/memory.ts:48-83` — `recordTakeoverLearning()` 函数：成功接管 → affordance，失败接管 → avoid

**Acceptance Criteria:**

**Given** 任务成功完成，发现新的操作路径
**When** 提取记忆
**Then** 记录为 affordance 类型（如 "Finder 中 Cmd+Shift+G 可直接导航到指定路径"）

**Given** 任务执行中某操作失败，触发重规划后成功
**When** 提取记忆
**Then** 失败操作记录为 avoid 类型（如 "避免在 Chrome 中使用 AX 定位地址栏，截图坐标更可靠"）

**Given** 任务执行中发现非操作性的环境信息
**When** 提取记忆
**Then** 记录为 observation 类型（如 "Calculator 在 macOS 14 中的窗口标题为 'Calculator'"）

**Given** Planner 生成计划时
**When** 注入 Memory 上下文
**Then** affordance 注入为推荐路径提示，avoid 注入为避坑警告，observation 注入为环境备注

**Given** avoid 类型的记忆被注入 planner prompt
**When** Planner 规划
**Then** 为软性建议（"不建议使用 X"），不是硬性禁止，Planner 可以在必要时忽略

### Story 12.3: Memory 导入/导出

As a 用户,
I want 在多台机器间共享积累的 Memory,
So that 我不需要在每台机器上重新积累经验.

**OpenClick 参考：**
- `src/memory.ts:40-44` — `MemoryBundle` 接口：schema_version、exported_at、memories 数组
- `src/memory.ts:190-203` — `exportMemoryBundle()` / `writeMemoryBundle()` 函数：遍历所有 domain 的 memory.json，打包为 MemoryBundle
- `src/memory.ts:204-250` — `importMemoryBundle()` 函数：解析导入文件，对每条记忆执行 normalizeFact()（`L318-338`）确保字段合法，合并时调用 mergeMemoryFacts()（`L362-375`）
- `src/memory.ts:437-443` — 导入时 source 标记为 "imported"，confidence 降为 `Math.min(fact.confidence, 0.55)`
- `src/cli.ts:239-258` — CLI 入口：`memory export <file>` / `memory import <file>` / `memory learn-takeover` 命令处理

**Acceptance Criteria:**

**Given** 运行 `axion memory export axion-memory.json`
**When** 导出完成
**Then** 生成包含所有 domain 的 Memory Bundle（JSON 文件），含 schema_version、exported_at 和 memories 数组

**Given** 导出的 Memory 文件
**When** 在另一台机器上运行 `axion memory import axion-memory.json`
**Then** 导入的记忆以 candidate + 低 confidence（0.4）状态进入，不覆盖已有的 active 记忆

**Given** 导入的记忆中某条与本地已有记忆重复
**When** 按 bundle_id + description 匹配
**Then** 合并为单条记忆，取更高的 evidence_count 和 confidence

**Given** `axion memory export --app com.apple.finder`
**When** 指定 App 导出
**Then** 只导出该 App 的记忆，其他 App 不包含

**Given** `axion memory list` 输出
**When** 查看列表
**Then** 每条记忆显示状态图标（✓ active / ○ candidate / ✗ retired）、类型（affordance/avoid/observation）和 evidence_count

---

## Epic 13: 执行安全与成本控制

### Story 13.1: 桌面级运行锁

As a 系统,
I want 同一时刻只有一个 live run 控制桌面,
So that 多任务并发不会产生操作冲突和安全问题.

**OpenClick 参考：**
- `src/paths.ts:47-48` — `resolveRunLockPath()` 函数：返回 `~/.openclick/run.lock`
- `src/trace.ts:143-178` — `acquireRunLock(runId)` 函数：写 lock 文件（pid + run_id + started_at），检查已有 lock 的进程是否存活（`process.kill(pid, 0)`），stale lock 自动覆盖
- `src/run.ts:286-293` — `acquireRunLock()` 调用点：live run 启动时获取锁，获取失败则记录 trace 并 exit(15)
- `src/trace.ts:170-177` — `release()` 回调：run 结束后 unlink lock 文件（best effort）

**Acceptance Criteria:**

**Given** 无运行中的 live run
**When** 提交新的 live run
**Then** 创建 `~/.axion/run.lock` 文件，写入 run_id、pid 和启动时间，然后正常执行

**Given** 已有一个 live run 正在执行
**When** 提交新的 live run
**Then** 检测到 run.lock 存在且 lock 持有进程存活，拒绝执行并返回错误："另一个 live run（run_id: xxx）正在执行，请等待其完成或使用 `axion cancel xxx` 取消"

**Given** run.lock 文件存在但持有进程已退出（异常退出未清理）
**When** 检测
**Then** 识别为 stale lock，自动清理后允许新 run 启动

**Given** live run 正常结束（done/failed/cancelled）
**When** 清理
**Then** 删除 run.lock 文件

**Given** API server 接收到 POST /v1/runs 且已有 live run
**When** 检查
**Then** 返回 409 Conflict，body 包含当前运行中的 run_id 和建议操作

**Given** 用户运行 `axion doctor`
**When** 检查
**Then** 报告是否有 stale lock 文件存在并建议清理

### Story 13.2: 视觉增量检查

As a 系统,
I want 在调用 LLM verifier 前先做本地截图对比,
So that 画面无变化时跳过昂贵的 verifier 调用，节省 API 成本.

**OpenClick 参考：**
- `src/run.ts:391` — `lastScreenshotHash` 变量：维护上一轮截图的 hash 值
- `src/run.ts:460-479` — `addScreenshotIfChanged()` 调用模式：传入 hash 比较回调，`hash === lastScreenshotHash` 时返回 false 跳过截图
- `src/run.ts:1070-1084` — 视觉增量检查核心逻辑：截图 hash 未变时记录 "visual delta check: no material screenshot change"，构造 `tool: "visual_delta"` 的伪失败步骤触发 replan（让 planner 换策略而非重复无效操作）
- `src/run.ts:857-872` — 高风险视觉操作后的 delta 检查：canvas 拖拽等操作后对比截图，无变化则记录 critique（background_visual_delta_failed）

**Acceptance Criteria:**

**Given** 一个批次步骤执行完成，准备调用 verifier
**When** 获取当前截图
**Then** 与上一轮 verifier 调用时的截图做像素级差异比较（downscaled 到 256x256 后比较）

**Given** 截图差异率 < 1%（画面几乎无变化）
**When** 视觉增量检查
**Then** 跳过 verifier 调用，判定任务状态未改变，直接进入下一轮规划或保持当前状态

**Given** 截图差异率 >= 1%
**When** 视觉增量检查
**Then** 正常调用 LLM verifier 进行验证

**Given** 第一轮执行（无历史截图）
**When** 视觉增量检查
**Then** 跳过比较，直接调用 verifier

**Given** `--no-visual-delta` 标志启用
**When** 执行
**Then** 禁用视觉增量检查，每次都调用 verifier（兼容旧行为）

**Given** trace 记录
**When** verifier 调用被跳过
**Then** 记录 `verifier_skipped` 事件，包含 delta_percentage 和 reason

### Story 13.3: 精细预算控制与成本遥测

As a 用户,
I want 通过 --max-model-calls 和 --max-screenshots 精确控制 LLM 调用和截图次数,
So that 我可以精确预算每次任务的 API 成本.

**OpenClick 参考：**
- `src/run.ts:74-76` — RunOptions 接口：`maxModelCalls?: number` 和 `maxScreenshots?: number` 字段
- `src/run.ts:344-347` — 从 opts 和环境变量 `OPENCLICK_MAX_MODEL_CALLS`（默认 12）、`OPENCLICK_MAX_SCREENSHOTS`（默认 8）读取预算值
- `src/run.ts:506-507,564-565,...` — 每次执行/验证/截图操作前将 maxModelCalls/maxScreenshots 传入 budgeted* 函数做检查（共约 15 处调用点）
- `src/trace.ts:130-134` — `TraceRecorder.finish()` 方法：接受 `costs?: Record<string, number>` 参数，记录 trace.costs
- `src/trace.ts:100` — TraceRecorder 的 trace 对象包含 costs 字段（model calls、screenshot count 等）

**Acceptance Criteria:**

**Given** 运行 `axion run "任务" --max-model-calls 10`
**When** LLM 调用次数达到 10
**Then** 停止执行，进入 failed 状态，输出 "已达到模型调用上限（10次）"

**Given** 运行 `axion run "任务" --max-screenshots 5`
**When** 截图次数达到 5
**Then** 后续步骤使用最后一次截图或跳过验证，不截新图

**Given** 所有预算维度（max-steps、max-batches、max-model-calls、max-screenshots）
**When** 任意一个达到上限
**Then** 停止执行，trace 中记录哪个预算被触发

**Given** 任务运行中
**When** TraceRecorder 记录
**Then** 每次 LLM 调用记录 `model_call` 事件，包含 model 名称、input_tokens、output_tokens、estimated_cost

**Given** 任务完成
**When** 输出汇总
**Then** 显示成本摘要：总 LLM 调用次数、总 tokens、预估成本（如 "LLM 调用: 8次, Tokens: 45,230, 预估成本: $0.12"）

**Given** API server 返回 RunStatusResponse
**When** 检查响应
**Then** 包含 cost_telemetry 字段：model_calls、total_tokens、screenshot_count

### Story 13.4: 桌面活动检测与学习保护

As a 系统,
I want 在 shared-seat 模式下检测用户的桌面操作,
So that 被用户操作"污染"的运行不会产生错误的 Memory.

**OpenClick 参考：**
- `src/run.ts:398-415` — `SeatActivityMonitor` 创建和 `noteSeatActivity()` 回调：检测到外部活动后设 `learningDisabled = true`，记录 `external_seat_activity` trace 事件
- `src/run.ts:2849-2907` — `SeatActivityMonitor` 类实现：基线记录 cursor 位置和 frontmost app；`check()` 方法比较当前 cursor 移动距离（>= 8px 触发）和 frontmost app 变化
- `src/run.ts:2857-2863` — `SeatActivityMonitor.create()` 静态方法：采样初始 cursor 位置（`sampleCursorPosition()`）和前台 app（`sampleFrontmostApp()`）作为基线
- `src/run.ts:2877-2907` — `check()` 方法：比较当前与基线，cursor 移动 >= 8px 或 frontmost app 变化时返回变化描述，每个变化类型只报告一次（`this.reported` Set）

**Acceptance Criteria:**

**Given** shared-seat 模式运行中（未设置 --allow-foreground）
**When** 检测到用户手动操作了目标窗口（通过 CGEvent Tap 监听鼠标/键盘事件，仅限目标窗口区域）
**Then** 标记该次运行为 "externally modified"，TraceRecorder 记录 `external_activity_detected` 事件

**Given** 运行被标记为 externally modified
**When** 任务完成
**Then** 禁用 Memory 提取（不调用 AppMemoryExtractor），输出提示 "检测到外部桌面操作，本次运行的经验不会被记忆"

**Given** 运行被标记为 externally modified
**When** verifier 评估
**Then** 正常验证，不跳过验证逻辑（仅影响 Memory 学习）

**Given** --allow-foreground 模式运行
**When** 检测
**Then** 不检测外部活动（foreground 模式本身就是用户协作模式）

**Given** 用户在运行期间手动操作了非目标窗口
**When** 检测
**Then** 不标记为 externally modified（只关注任务目标窗口）

---

## Epic 14: API 规范化与集成友好度

### Story 14.1: StandardTaskOutput 契约升级

As a 外部集成方,
I want Axion API 返回规范化的 StandardTaskOutput,
So that 我可以用统一的契约处理所有任务状态和结果.

**OpenClick 参考：**
- `src/api-runs.ts:21-48` — `StandardTaskOutput` 接口：schema_version、run_id、task、status（ApiRunStatus）、ok、live、allow_foreground、criteria、result（ApiTaskResult）、intervention、exit_code、error、stdout、stderr、started_at、ended_at
- `src/api-runs.ts:13-20` — `ApiRunStatus` 类型：queued / running / intervention_needed / user_takeover / resuming / completed / failed / cancelled
- `src/api-runs.ts:23-28` — `ApiTaskResult` 接口：kind（"answer" | "confirmation"）、title、body、created_at
- `src/api-runs.ts:50-62` — `ApiRunEvent` 接口：SSE 事件结构（id、ts、type、data）
- `src/api-runs.ts:80-100` — `startApiRun()` 函数：创建初始 StandardTaskOutput（status=queued）

**Acceptance Criteria:**

**Given** API 运行结果
**When** 检查 StandardTaskOutput 结构
**Then** 包含字段：schema_version（Int）、run_id、task、status、ok（Bool）、live（Bool）、allow_foreground（Bool）、criteria（可选）、result（可选）、intervention（可选）、exit_code（可选）、error（可选）、started_at、ended_at（可选）

**Given** 任务成功完成且用户要求返回信息（如 "读取最新邮件"）
**When** 生成 result
**Then** result.kind = "answer"，result.body 包含用户期望的答案内容

**Given** 任务成功完成且用户要求执行操作（如 "打开计算器"）
**When** 生成 result
**Then** result.kind = "confirmation"，result.body 包含操作确认摘要

**Given** 任务进入 takeover 状态
**When** 返回 StandardTaskOutput
**Then** status = "intervention_needed"，intervention 包含 reason、available_actions（resume/abort）和 blocking_issue

**Given** GET /v1/runs/{runId} 请求
**When** 查询已完成的任务
**Then** 返回完整的 StandardTaskOutput（包含 result 和 cost_telemetry）

**Given** POST /v1/runs 请求
**When** 创建新任务
**Then** 返回 202 Accepted + StandardTaskOutput（status = "running"）

### Story 14.2: Capabilities 端点

As a 外部集成方,
I want 通过 API 发现 Axion 的桌面操作能力,
So that 我可以动态适配不同配置的 Axion 实例.

**OpenClick 参考：**
- `src/api-runs.ts:218-252` — `capabilitiesResponse()` 函数：返回 schema_version、name、version、capabilities 数组（desktop.run/desktop.cancel/desktop.status/desktop.events/desktop.memory/desktop.settings.api_key/desktop.takeover）、run_statuses 枚举、result_kinds（answer/confirmation）、endpoints 路由表
- `src/server.ts:70-71` — 路由注册：`GET /v1/capabilities` → `capabilitiesResponse()`

**Acceptance Criteria:**

**Given** GET /v1/capabilities 请求
**When** 响应
**Then** 返回 JSON 包含：version（Axion 版本）、supported_run_statuses（所有可能的状态值）、supported_result_kinds（answer/confirmation）、available_tools（Helper 暴露的工具列表）、max_concurrent_runs（并发限制）、features（支持的功能列表，如 memory、takeover、fast_mode、skills）

**Given** Helper 未连接
**When** GET /v1/capabilities
**Then** available_tools 为空数组，version 和 features 正常返回

**Given** capabilities 响应
**When** 检查格式
**Then** 为稳定的 JSON schema，可被集成方缓存（建议缓存时间 5 分钟）

### Story 14.3: Settings API

As a 运维人员,
I want 通过 HTTP API 管理配置,
So that 我不需要登录服务器运行 CLI 命令.

**OpenClick 参考：**
- `src/server.ts:74-247` — Settings API 实现整体（`handleApiKeyRequest` 函数）
- `src/server.ts:228-238` — GET：调用 `apiKeyStatus(provider)` 返回 provider、available、source、masked key
- `src/server.ts:232-240` — POST：调用 `saveProviderApiKey(provider, apiKey)` 保存 key 并返回 masked 确认
- `src/server.ts:243-247` — DELETE：调用 `clearProviderApiKey(provider)` 清除 key 并返回 available=false
- `src/settings.ts` — `apiKeyStatus()`、`saveProviderApiKey()`、`clearProviderApiKey()` 函数：底层 config 读写

**Acceptance Criteria:**

**Given** GET /v1/settings/api-key 请求
**When** 响应
**Then** 返回 provider（anthropic/openai）、available（Bool）、source（config/env）和 masked_key（如 "sk-ant-****xxxx"），不暴露完整 API Key

**Given** POST /v1/settings/api-key body `{"api_key": "sk-ant-xxx"}`
**When** 处理
**Then** 保存 API Key 到 config.json，返回 masked_key 状态确认

**Given** DELETE /v1/settings/api-key 请求
**When** 处理
**Then** 清除 config.json 中的 API Key，返回 available=false 状态

**Given** Settings API 请求需要认证
**When** server 启用了 --auth-key
**Then** Settings API 同样受 AuthMiddleware 保护

**Given** 运行 `axion doctor`
**When** 检查
**Then** 新增检查：API server 的 Settings API 是否可访问（如果 server 在运行）

---

## Epic 15: Takeover 学习与桌面活动感知

### Story 15.1: Takeover 经验自动学习

As a 系统,
I want 用户手动接管后自动将接管经验转化为 Memory,
So that 人工干预成为可复用的自动化知识，减少未来同类任务被阻塞的概率.

**OpenClick 参考：**
- `src/memory.ts:48-83` — `recordTakeoverLearning()` 函数：接收 bundleId、appName、issue、summary、outcome 等参数；成功→affordance（confidence 0.72），失败→avoid（confidence 0.66），status 均为 candidate
- `src/memory.ts:69-81` — 证据构造：拼接 task、issue、reason_type、outcome、takeover summary、feedback 为 evidence 数组
- `src/cli.ts:239-258` — CLI `memory learn-takeover` 命令处理：解析 --bundle-id / --app-name / --issue / --summary 参数，调用 `recordTakeoverLearning()` + `saveAppMemory()`
- `src/run.ts:417-440` — `handleTakeoverResume()` 函数：takeover 恢复后调用 `recordTakeoverResumeLearning()` 将接管经验写入 Memory
- `src/trace.ts:53-70` — `TakeoverResumeMarker` 接口：schema_version、run_id、outcome、issue、summary、reason_type、feedback、trajectory_path

**Acceptance Criteria:**

**Given** 任务进入 takeover 状态
**When** 用户手动完成操作后按 Enter 恢复
**Then** 自动调用 Memory 系统，记录一条 takeover 学习（outcome: success）

**Given** Takeover 成功恢复
**When** 生成 Memory 条目
**Then** 类型为 affordance，description 格式为 "当被 {issue} 阻塞时，用户手动 {summary} 成功"，confidence = 0.72，status = candidate

**Given** Takeover 后任务仍然失败
**When** 生成 Memory 条目
**Then** 类型为 avoid，description 格式为 "当被 {issue} 阻塞时，{summary} 未解决问题"，confidence = 0.66，status = candidate

**Given** Takeover 学习记录
**When** 后续运行遇到同类阻塞
**Then** Planner prompt 中注入对应的 affordance/avoid 记忆，帮助 Planner 选择更优路径

**Given** `axion memory learn-takeover --bundle-id com.apple.finder --issue "文件选择对话框无法通过 AX 定位" --summary "使用 Cmd+Shift+G 直接输入路径"`
**When** 手动记录 takeover 经验
**Then** 直接创建 Memory 条目，无需等待运行触发

### Story 15.2: Takeover 结构化标记

As a 用户,
I want takeover 有结构化的标记和反馈机制,
So that 接管经验可以被系统精确理解和复用.

**OpenClick 参考：**
- `src/trace.ts:34-51` — `InterventionPayload` 接口：run_id、issue、reason（InterventionReason 枚举）、step、user_action、learning、before（RunInterventionSnapshot）
- `src/trace.ts:18-32` — `InterventionReason` 类型：planner_blocked / needs_clarification / foreground_required / repeated_action_failure / verification_failed / permission_prompt / confirmation_dialog / login_or_2fa / captcha / native_modal / low_confidence / unexpected_screen_change / destructive_action_risk / user_requested_takeover
- `src/trace.ts:53-70` — `TakeoverResumeMarker` 接口：outcome（success/failed/cancelled）、issue、summary、reason_type、feedback（用户自由文本）、trajectory_path
- `src/cli.ts:389-426` — CLI `takeover finish` 命令：--run-id / --issue / --summary / --outcome / --reason-type / --feedback 参数，写入 TakeoverResumeMarker 文件
- `src/run.ts:417-440` — `handleTakeoverResume()` 函数：处理 takeover marker，调用 `recordTakeoverResumeLearning()` 记录学习

**Acceptance Criteria:**

**Given** takeover 恢复时
**When** 系统提示用户
**Then** 显示 "手动完成后按 Enter 继续。可选：输入反馈描述你的操作（如 '使用了 Cmd+Shift+G 输入路径'），或直接 Enter 跳过"

**Given** 用户输入了反馈文本
**When** 记录 takeover 学习
**Then** feedback 字段包含用户描述，作为 Memory 的 evidence 之一

**Given** 用户直接按 Enter（无反馈）
**When** 记录 takeover 学习
**Then** feedback 字段为空，Memory 仅包含 issue（阻塞原因）和 outcome

**Given** trace 记录
**When** takeover 事件发生
**Then** 记录 `takeover` 事件，包含 issue、summary、outcome、feedback、duration（用户花费的时间）

**Given** AxionBar 任务面板
**When** 显示 takeover 状态
**Then** 显示阻塞原因、手动操作提示和恢复按钮

---

## Epic 16: Daemon 模式与运维便利性

### Story 16.1: launchd Daemon 支持

As a 运维人员,
I want Axion server 作为 macOS launchd 守护进程运行,
So that 开机自启、崩溃自动重启，不需要手动管理.

**OpenClick 参考：**
- `src/daemon.ts:29-33` — `resolveLaunchAgentPath()` 函数：返回 `~/Library/LaunchAgents/${DAEMON_LABEL}.plist`
- `src/daemon.ts:42-79` — `buildLaunchAgentPlist()` 函数：生成完整 plist XML，包含 Label、ProgramArguments（node + server 脚本）、EnvironmentVariables（PATH、API key）、RunAtLoad=true、KeepAlive（CrashInterval=10，FailureInterval=300，MaxCrashes=5）、StandardOutPath/StandardErrorPath 日志路径
- `src/daemon.ts:83-96` — `installDaemon()` 函数：写 plist 文件（mode 0o644），执行 `launchctl load` 启动服务
- `src/daemon.ts:98-105` — `uninstallDaemon()` 函数：执行 `launchctl unload`，删除 plist 文件
- `src/daemon.ts:106-130` — `daemonStatus()` 函数：检查 plist 是否存在、launchctl list 查询 PID 和运行状态
- `src/cli.ts` — CLI 入口：`daemon install / status / uninstall` 子命令

**Acceptance Criteria:**

**Given** 运行 `axion daemon install --host 127.0.0.1 --port 4242`
**When** 安装完成
**Then** 创建 ~/Library/LaunchAgents/dev.axion.server.plist，注册 launchd 服务，立即启动

**Given** daemon 已安装
**When** macOS 重新启动并用户登录
**Then** Axion server 自动启动，监听配置的端口

**Given** Axion server 进程崩溃
**When** launchd 检测到退出
**Then** 10 秒后自动重启，连续崩溃 5 次后停止重启并记录日志

**Given** 运行 `axion daemon status`
**When** 检查
**Then** 显示 daemon 状态（running/stopped/not_installed）、PID、运行时长、端口

**Given** 运行 `axion daemon uninstall`
**When** 卸载
**Then** 停止服务、删除 plist 文件，清理日志（可选 --keep-logs）

**Given** daemon 安装时指定 --auth-key
**When** plist 配置
**Then** auth-key 作为环境变量传递给 server 进程

**Given** daemon 日志
**When** 查看
**Then** 写入 ~/.axion/server.log 和 ~/.axion/server.err.log

### Story 16.2: API Server 持久化运行恢复

As a 系统,
I want API server 重启后能恢复之前运行中的任务状态,
So that daemon 模式下的重启不会留下僵尸任务.

**OpenClick 参考：**
- `src/api-runs.ts:460-464` — `persistRecord()` 函数：将 StandardTaskOutput 写入 `~/.openclick/runs/{runId}/api-output.json`
- `src/api-runs.ts:466-469` — `persistEvent()` 函数：将 ApiRunEvent 追加写入 `~/.openclick/runs/{runId}/api-events.jsonl`
- `src/api-runs.ts:472-490` — `loadPersistedRecord()` 函数：从 api-output.json 加载 output，从 api-events.jsonl 加载 events，重建 ApiRunRecord
- `src/api-runs.ts:262-271` — `getOrLoadRecord()` 函数：先查内存 Map，miss 时从磁盘 load + recover
- `src/api-runs.ts:273-292` — `recoverLoadedRecord()` 函数：对 queued/running/intervention_needed/user_takeover/resuming 状态的记录标记为 failed + error="server interrupted"

**Acceptance Criteria:**

**Given** API server 有正在运行的异步任务
**When** server 进程重启
**Then** 从 `~/.axion/runs/{runId}/api-output.json` 加载持久化的任务状态

**Given** 持久化状态中 status = "running" 但子进程已退出
**When** 恢复检查
**Then** 标记为 failed，error = "server interrupted"，不再保持 running 状态

**Given** 持久化状态中 status = "intervention_needed"
**When** 恢复
**Then** 保持 intervention_needed 状态，等待用户通过 AxionBar 或 CLI 处理

**Given** 新的 SSE 连接订阅已恢复的任务
**When** 发送历史事件
**Then** 从 `api-events.jsonl` 重放所有历史事件，然后继续推送新事件

---

## Phase 4 FR 追溯

| FR | 来源 | Epic | 依赖 | 说明 |
|----|------|------|------|------|
| FR63 (Memory 生命周期) | Phase 4 新增 | Epic 12 | Epic 4 | candidate/active/retired + confidence |
| FR64 (三类记忆分类) | Phase 4 新增 | Epic 12 | Epic 4 | affordance/avoid/observation |
| FR65 (Memory 导入导出) | Phase 4 新增 | Epic 12 | Epic 4 | 多机器经验共享 |
| FR66 (桌面级运行锁) | Phase 4 新增 | Epic 13 | Epic 3/5 | 防止多任务桌面冲突 |
| FR67 (视觉增量检查) | Phase 4 新增 | Epic 13 | Epic 3 | 跳过无变化的 verifier 调用 |
| FR68 (精细预算控制) | Phase 4 新增 | Epic 13 | Epic 3 | max-model-calls/max-screenshots |
| FR69 (成本遥测) | Phase 4 新增 | Epic 13 | Epic 3 | trace 中的 LLM 成本记录 |
| FR70 (桌面活动检测) | Phase 4 新增 | Epic 13 | Epic 3 | 保护学习不被污染 |
| FR71 (StandardTaskOutput) | Phase 4 新增 | Epic 14 | Epic 5 | 规范化 API 输出契约 |
| FR72 (Capabilities 端点) | Phase 4 新增 | Epic 14 | Epic 5 | API 能力发现 |
| FR73 (Settings API) | Phase 4 新增 | Epic 14 | Epic 5 | HTTP 配置管理 |
| FR74 (Takeover 学习) | Phase 4 新增 | Epic 15 | Epic 7/12 | 接管经验转 Memory |
| FR75 (Takeover 结构化标记) | Phase 4 新增 | Epic 15 | Epic 7 | 结构化反馈机制 |
| FR76 (launchd Daemon) | Phase 4 新增 | Epic 16 | Epic 5 | 开机自启守护进程 |
| FR77 (运行状态恢复) | Phase 4 新增 | Epic 16 | Epic 5 | 重启后任务状态恢复 |

## Phase 4 新增 NFR

- NFR37: 视觉增量检查的截图对比耗时 < 50ms（downscaled 后比较）
- NFR38: 运行锁检测响应时间 < 10ms（文件锁检查）
- NFR39: Memory 导出/导入 1000 条记录耗时 < 2 秒
- NFR40: Daemon 模式下 server 崩溃到自动重启 < 15 秒
- NFR41: StandardTaskOutput 序列化/反序列化 < 5ms
- NFR42: 桌面活动检测的 CPU 开销 < 2%（仅监听目标窗口）

## Phase 4 优先级与依赖

| 优先级 | Epic | 依赖 | 理由 |
|--------|------|------|------|
| P0 | Epic 13 (执行安全与成本控制) | Epic 3, 5 | 安全第一，成本控制直接影响使用意愿 |
| P1 | Epic 12 (Memory 生命周期) | Epic 4 | 记忆质量是 AI 自动化的核心竞争力 |
| P1 | Epic 15 (Takeover 学习) | Epic 7, 12 | 与 Memory 生命周期协同，人工经验转自动化 |
| P2 | Epic 14 (API 规范化) | Epic 5 | 外部集成的基础，但不阻塞核心功能 |
| P3 | Epic 16 (Daemon 模式) | Epic 5 | 运维便利性，可最后推进 |

**实施建议顺序：Epic 13（Story 13.1 运行锁）→ Epic 12 → Epic 15 → Epic 13（Story 13.2-13.4）→ Epic 14 → Epic 16**

**理由：**
- Epic 13 Story 13.1（运行锁）最简单且价值最高，可快速交付
- Epic 12 是 Epic 15 的前置（Takeover 学习需要 Memory 生命周期）
- Epic 13 其余 Stories 可与 Epic 12 并行
- Epic 14 和 16 为 API 和运维改进，优先级靠后

---

# Phase 5 — SDK Skill 系统集成 Epics

> Phase 1-4（Epic 1-16）均已完成或接近完成。Phase 5 将 OpenAgentSDK 的 Skill 系统接入 Axion，让用户通过 `/skill-name` 语法或自然语言描述触发技能执行，同时预置桌面自动化领域的内置技能。
>
> **核心理念：** Axion 不只是"每次都思考"的 LLM Agent——通过 SDK Skill 系统，常用操作变成一键技能调用，LLM 只在需要判断力时参与。
>
> **核心依赖：** OpenAgentSDK 的 Skill 系统（SkillLoader、SkillRegistry、SkillTool、BuiltInSkills），已在 SDK Epic 11 中实现。

## Phase 5 Epic List

### Epic 17: SDK Skill 系统集成

将 OpenAgentSDK 的 SkillLoader、SkillRegistry、SkillTool 接入 Axion 的 Agent 创建和执行流程。用户可以通过 `/skill-name` 显式触发技能，也可以通过自然语言描述让 LLM 自动匹配技能。同时实现双轨查找——prompt 技能（SKILL.md）和录制技能（JSON）统一入口。

**核心价值：** Axion 获得与 Claude Code 一致的 `/command` 技能触发能力，同时复用 `~/.claude/skills/` 和 `~/.agents/skills/` 下已有的技能生态。
**依赖：** SDK Epic 11（Skill 系统）、Axion Epic 9（录制技能，双轨查找的基础）

### Epic 18: Axion 桌面技能增强

在 Epic 17 的基础设施上，为 Axion 预置桌面自动化领域的内置技能（SKILL.md prompt 模板），实现技能与 Memory 的联动，以及 HTTP API 对 prompt 技能的统一支持。

**核心价值：** 开箱即用的桌面技能 + 技能越用越聪明的 Memory 联动 + API 统一触发入口。
**依赖：** Epic 17（Skill 基础设施）、Epic 4/12（Memory 系统）、Epic 5（HTTP API）

---

## Epic 17: SDK Skill 系统集成

### Story 17.1: RunCommand 集成 SkillRegistry

As a 用户,
I want Axion 启动时自动发现并加载 `~/.claude/skills/` 和 `~/.agents/skills/` 下的技能,
So that 我不需要手动配置就能使用已有的技能生态.

**Acceptance Criteria:**

**Given** `~/.claude/skills/polyv-live-cli/SKILL.md` 存在
**When** 用户运行 `axion run "任意任务"`
**Then** RunCommand 创建 Agent 前，调用 `SkillLoader.discoverSkills()` 扫描默认目录，将发现的技能注册到 `SkillRegistry`

**Given** `SkillRegistry` 中有已注册技能
**When** Agent 创建完成
**Then** `createSkillTool(registry:)` 作为工具注册到 Agent 的工具池，LLM 可通过 Skill 工具发现和调用技能

**Given** 多个目录下有同名技能（如 `~/.claude/skills/foo/` 和 `~/.agents/skills/foo/`）
**When** 加载完成
**Then** 按目录优先级 last-wins 去重（SDK SkillLoader 已实现此逻辑）

**Given** 扫描目录中没有 SKILL.md 文件
**When** 启动 Agent
**Then** SkillRegistry 为空，SkillTool 仍注册但不可用，不影响正常任务执行

### Story 17.2: 双轨技能查找

As a 用户,
I want `/xxx` 触发时 Axion 先查 prompt 技能（SKILL.md），再查录制技能（JSON）,
So that 两种技能类型共享统一的 `/xxx` 触发入口，我不需要关心技能的实现方式.

**Acceptance Criteria:**

**Given** `polyv-live-cli` 是 prompt 技能（SKILL.md），`open_calculator` 是录制技能（JSON）
**When** 用户输入 `/polyv-live-cli 获取频道列表`
**Then** 先查 SkillRegistry 命中 prompt 技能，走 Agent + promptTemplate 执行路径

**Given** 只有 `open_calculator` 存在于 `~/.axion/skills/`（JSON 录制技能），SkillRegistry 中无同名技能
**When** 用户输入 `/open_calculator`
**Then** 查 SkillRegistry 未命中，再查 `~/.axion/skills/*.json` 命中录制技能，走 SkillExecutor 回放路径

**Given** 同名技能同时存在于 SkillRegistry 和 `~/.axion/skills/`
**When** 用户输入 `/xxx`
**Then** SkillRegistry 优先命中（prompt 技能优先）

**Given** 用户输入 `/nonexistent-skill`
**When** 两轨均未命中
**Then** 整句作为普通 prompt 发送给 LLM 执行，不报错

### Story 17.3: 显式 `/skill-name` 触发

As a 用户,
I want 在 prompt 中用 `/skill-name` 语法显式触发技能,
So that 我可以精确控制使用哪个技能完成任务.

**Acceptance Criteria:**

**Given** `polyv-live-cli` 技能已注册
**When** 用户运行 `axion run "/polyv-live-cli 获取最新10个频道信息"`
**Then** RunCommand 解析出技能名 `polyv-live-cli` 和参数 `获取最新10个频道信息`
**And** 将技能的 promptTemplate 作为 Agent 的主要指令，参数作为任务描述注入
**And** 如果技能有 `allowed-tools` 限制，Agent 的可用工具集被限定为指定范围

**Given** `open_calculator` 是录制技能（JSON），有参数 `{{url}}`
**When** 用户运行 `axion run "/open_calculator"`
**Then** 走 SkillExecutor 回放路径，不调用 LLM
**And** 如有必需参数缺失，提示用户

**Given** 用户输入 `axion run "请帮我/polyv-live-cli获取频道"`（`/` 不在句首）
**When** 解析 prompt
**Then** `/` 不被识别为技能触发，整句作为普通 prompt 发送给 LLM（LLM 可能通过隐式触发匹配到该技能）

**Given** 技能有 `model` 覆盖（如 `claude-opus-4-6`）
**When** 显式触发该技能
**Then** Agent 使用指定模型执行，执行完毕后恢复默认模型

### Story 17.4: 隐式技能触发

As a 用户,
I want 用自然语言描述意图时，LLM 自动匹配并执行对应技能,
So that 我不需要知道技能名称，只要描述我想做什么.

**Acceptance Criteria:**

**Given** SkillRegistry 中有 `polyv-live-cli` 技能，`whenToUse` 为 "用户需要管理直播频道、配置推流设置、管理商品、处理优惠券、查看直播数据或管理回放录像时使用"
**When** 用户运行 `axion run "帮我获取保利威最新的10个频道信息"`
**Then** SkillRegistry.formatSkillsForPrompt() 将技能描述注入 system prompt
**And** LLM 通过 SkillTool 自动匹配到 `polyv-live-cli` 技能并执行

**Given** 技能列表有 10 个技能，formatSkillsForPrompt() token 预算为 500
**When** 注入 system prompt
**Then** 按注册顺序列出技能，超出预算时截断尾部技能描述（SDK SkillRegistry 已实现）

**Given** 某技能 `isAvailable()` 返回 false
**When** formatSkillsForPrompt() 生成技能列表
**Then** 该技能不出现在列表中，LLM 无法发现和调用

**Given** 用户运行 `axion run --no-skills "帮我获取频道信息"`
**When** 启动 Agent
**Then** 不注入技能列表到 system prompt，SkillTool 不注册，LLM 无法调用技能

---

## Epic 18: Axion 桌面技能增强

### Story 18.1: 内置桌面技能

As a 用户,
I want Axion 预置桌面自动化领域的技能（screenshot-analyze、data-extract、form-fill）,
So that 常见桌面操作有开箱即用的高质量 prompt 模板.

**Acceptance Criteria:**

**Given** Axion 启动
**When** 内置技能注册完成
**Then** SkillRegistry 中包含 `screenshot-analyze`、`data-extract`、`form-fill` 三个技能
**And** 每个技能的 `toolRestrictions` 限定为 Helper MCP 工具（screenshot、get_window_state、list_windows、click、type_text、press_key 等）
**And** 每个技能的 `isAvailable` 检查 Helper 是否已连接

**Given** 用户运行 `axion run "/screenshot-analyze 分析当前屏幕"`
**When** 技能执行
**Then** Agent 按技能 promptTemplate 指示，调用 screenshot + get_window_state，综合分析并输出结构化描述

**Given** 用户运行 `axion run "帮我提取 Finder 当前目录的文件列表"`
**When** Finder 窗口打开
**Then** LLM 通过隐式触发匹配到 `data-extract` 技能，Agent 通过 AX tree 提取文件名列表

**Given** 三个内置技能已注册
**When** 用户运行 `axion skill list`（如果扩展该命令显示 SDK 技能）
**Then** 显示内置技能，标记为 `type: prompt`，来源为 `built-in`

**技术要点：**
- 内置技能作为 SDK `Skill` struct 的代码定义（类似 SDK 的 `BuiltInSkills`），不从文件系统加载
- toolRestrictions 需要支持 Helper MCP 工具名——当前 SDK `ToolRestriction` 枚举只包含 SDK 内置工具，需要评估是否需要扩展或使用字符串形式的 allowed-tools

### Story 18.2: 技能 + Memory 联动

As a 系统,
I want 技能执行过程中的经验自动沉淀为 Memory，且 Memory 能指导后续技能执行,
So that 技能越用越精准——记住哪些操作路径有效，哪些窗口结构需要特殊处理.

**Acceptance Criteria:**

**Given** 用户执行 `axion run "/screenshot-analyze 分析 Chrome"`
**When** 技能执行成功
**Then** 自动生成一条 affordance 类型 Memory：scope=`skill:screenshot-analyze`，domain 为 App bundle identifier，content 包含技能名和执行摘要

**Given** 上次 screenshot-analyze 在某 App 中失败（因窗口最小化）
**When** 用户再次在同一 App 中调用该技能
**Then** 技能执行前注入相关的 avoid 类型 Memory 到 promptTemplate 末尾

**Given** 用户运行 `axion run --no-memory "/screenshot-analyze 分析当前屏幕"`
**When** 技能执行
**Then** 不注入 Memory 上下文，也不记录技能执行经验（尊重 `--no-memory` 标志）

**Given** 同一技能同一 App 积累了 5 条以上 Memory
**When** 技能执行前注入 Memory
**Then** 只注入 confidence 最高的前 3 条，按 affordance → avoid → observation 优先级排序

**Given** 录制技能（JSON）执行成功
**When** SkillExecutor 回放完成
**Then** 也记录 Memory（技能名、App、成功/失败），与 prompt 技能共享同一套 Memory 逻辑

**技术要点：**
- Memory scope 格式：`skill:{skillName}`，方便按技能过滤
- 复用 `MemoryContextProvider.buildFactMemoryContext()`，增加 skillName 过滤参数
- prompt 技能的 Memory 注入：在 promptTemplate 末尾追加 Memory section
- 录制技能的 Memory 注入不适用（无 LLM prompt），但 Memory 记录仍可产生

### Story 18.3: HTTP API 支持 Skill 触发

As a 外部集成方（AxionBar、第三方 Agent）,
I want 通过 HTTP API 触发 prompt 技能执行，并获取实时 SSE 事件流,
So that 菜单栏 UI 和外部系统也能使用 SDK Skill 系统的所有技能.

**Acceptance Criteria:**

**Given** `polyv-live-cli` 技能已通过 SkillLoader 加载
**When** 发送 `POST /v1/skills/polyv-live-cli/run` body: `{"task": "获取最新10个频道信息"}`
**Then** 服务端创建 Agent，注入 polyv-live-cli 的 promptTemplate + 用户 task 作为任务描述
**And** SSE 推送执行进度（step_started, step_completed 等事件）
**And** 返回 run_id 供后续查询

**Given** `open_calculator` 是录制技能（JSON）
**When** 发送 `POST /v1/skills/open_calculator/run`
**Then** 走现有 SkillAPIRunner 逻辑（无 LLM 调用），行为不变

**Given** 发送 `GET /v1/skills`
**When** 查询技能列表
**Then** 返回两种技能：录制技能（来自 `~/.axion/skills/*.json`）和 prompt 技能（来自 SkillRegistry）
**And** 每项带 `type` 字段：`"recorded"` 或 `"prompt"`

**Given** AxionBar QuickRun 中用户输入 `/polyv-live-cli 获取频道`
**When** AxionBar 提交任务
**Then** 路由到 `POST /v1/skills/polyv-live-cli/run`，而非 `POST /v1/runs`

**Given** 指定技能名在两个来源中都不存在
**When** 发送 `POST /v1/skills/nonexistent/run`
**Then** 返回 HTTP 404，body: `{"error": "Skill not found"}`

**技术要点：**
- prompt 技能的 API 执行复用 `AgentRunner.runAgent()`，systemPrompt 改为技能的 promptTemplate
- SSE 事件流复用现有 `EventBroadcaster` 管线
- `GET /v1/skills` 端点合并两个来源：遍历 `~/.axion/skills/*.json` + 查询 SkillRegistry
- AxionBar `SkillService` 适配新的 `type` 字段和 `/xxx` 路由逻辑

---

## Phase 5 FR 追溯

| FR | 来源 | Epic | SDK 依赖 | 说明 |
|----|------|------|----------|------|
| FR63 (Skill 加载) | Phase 5 新增 | Epic 17 | SkillLoader, SkillRegistry | 多目录技能发现 |
| FR64 (显式技能触发) | Phase 5 新增 | Epic 17 | SkillTool | `/skill-name` 语法 |
| FR65 (隐式技能触发) | Phase 5 新增 | Epic 17 | SkillTool, formatSkillsForPrompt | LLM 自动匹配 |
| FR66 (双轨技能查找) | Phase 5 新增 | Epic 17 | 无 | prompt 技能 + 录制技能统一入口 |
| FR67 (内置桌面技能) | Phase 5 新增 | Epic 18 | Skill struct | 预置 SKILL.md prompt 模板 |
| FR68 (技能 Memory 联动) | Phase 5 新增 | Epic 18 | 无 | 技能经验沉淀和注入 |
| FR69 (API Skill 触发) | Phase 5 新增 | Epic 18 | 无 | HTTP API 统一支持 prompt 技能 |

## Phase 5 新增 NFR

- NFR43: SkillLoader 扫描并加载 20 个技能耗时 < 500ms
- NFR44: 显式 `/skill-name` 触发到技能执行开始延迟 < 100ms（不含 LLM 响应时间）
- NFR45: formatSkillsForPrompt() 生成的技能描述占用 system prompt < 500 token
- NFR46: 隐式触发场景下，SkillTool 调用增加的延迟 < 1 轮 LLM 交互

## Phase 5 优先级与依赖

| 优先级 | Epic | 依赖 | 理由 |
|--------|------|------|------|
| P0 | Epic 17 (Skill 系统集成) | SDK Epic 11 | 基础设施，解锁所有技能能力 |
| P1 | Epic 18 Story 18.1 (内置技能) | Epic 17 | 开箱即用体验，只需编写 SKILL.md |
| P2 | Epic 18 Story 18.3 (API Skill 触发) | Epic 17, Epic 5 | 外部集成增强，依赖 HTTP API |
| P3 | Epic 18 Story 18.2 (Memory 联动) | Epic 17, Epic 12 | 锦上添花，需要 Memory 生命周期 |

**实施建议顺序：17.1 → 17.3（显式触发）→ 17.2（双轨查找）→ 17.4（隐式触发）→ 18.1（内置技能）→ 18.3（API）→ 18.2（Memory 联动）**

**理由：**
- 17.1 是所有后续 Story 的前置——没有 SkillRegistry 注册就没有技能可用
- 17.3 先于 17.2——显式触发是核心体验，双轨查找是增强
- 17.4 可与 17.2/17.3 并行——隐式触发是独立的 LLM 侧逻辑
- 18.1 极轻量——只需编写几个 SKILL.md prompt 模板
- 18.3 依赖 HTTP API 基础设施（Epic 5），但可复用 SkillAPIRunner 的 SSE 管线
- 18.2 优先级最低——Memory 联动是长期价值，不影响核心功能

## Phase 6 Epic List

### Epic 19: SDK 使用方式对齐重构

将 Axion 对 OpenAgentSDK 的使用方式从「越权模式」重构为「正确模式」，参照 SwiftWork 项目的最佳实践。当前 Axion 应用层越权做了大量 SDK 应该做的事（自建 Agent Loop、手动构建 skill prompt、手动设置 allowedTools、不传 skillRegistry），导致 skill 体系失效、代码重复、维护成本高。重构目标：应用层只负责「准备输入 + 处理输出」，agent 生命周期完全交给 SDK。

**核心价值：** SDK 的愿景是让开发一个 agent 应用变得简单。Axion 应该是最能体现这个愿景的项目——而不是反例。
**依赖：** Phase 1-5 全部完成
**参考：** `/Users/nick/CascadeProjects/swiftwork/SwiftWork/SDKIntegration/AgentBridge.swift` — 正确使用 SDK 的参考实现

**重构后架构：**

```
用户输入
  ├── CLI: axion run "..."     → RunCommand（薄层：CLI 参数解析 → 共享函数 → 终端输出）
  └── API: POST /api/runs      → ApiRunner（薄层：HTTP 请求解析 → 共享函数 → SSE/DB 输出）
                                      ↓
                              共享函数：buildAndRunAgent()
                                - 加载配置、注册 skill
                                - 构建 SafetyHook（shared seat mode）
                                - 加载 Memory 上下文注入 system prompt
                                - 构建 AgentOptions（传 skillRegistry、tools、mcpServers、hookRegistry、memoryStore）
                                - 调用 agent.stream()
                                - 由 SDK 管理 agent 生命周期
```

### Epic 20: 死代码清理与架构精简

删除 Axion 中从未被使用的自建 Agent Loop 及其依赖的协议和模型。当前 Engine/、Executor/、Planner/、Verifier/、Output/ 目录下的代码以及 AxionCore 中对应的协议定义都是死代码——RunEngine 从未被实例化。这些代码增加了理解成本和维护负担。

**核心价值：** 删代码比写代码更重要。每一行死代码都是未来重构的障碍。
**依赖：** 无（可独立于 Epic 19 执行）
**参考：** `RunEngine.swift`、`LLMPlanner.swift`、`StepExecutor.swift`、`PlanParser.swift` 从未被引用

---

## Epic 19: SDK 使用方式对齐重构

### Story 19.1: 统一 Agent 执行入口

As a 开发者,
I want RunCommand 和 ApiRunner 共用同一个 Agent 构建函数,
So that 配置逻辑、prompt 构建、工具注册只在一处维护, 不会出现"修了 CLI 忘了 API"的问题.

**现状问题：**
- `RunCommand.run()` 和 `AgentRunner.runAgent()` 各有 ~300 行几乎一样的代码
- 两处都有 skill prompt 手动构建、allowedTools 手动设置的 bug
- 两处都不传 `skillRegistry` 给 AgentOptions
- `AgentRunner.runSkillAgent()` 又复制了第三遍

**重构方案：**
- 将 `AgentRunner` 重命名为 `ApiRunner`，消除与 SDK `Agent` 类的语义冲突
- 提取共享函数 `buildAndRunAgent()`，RunCommand 和 ApiRunner 都调用它
- RunCommand 只负责 CLI 参数解析 + 终端输出
- ApiRunner 只负责 HTTP 请求解析 + SSE/DB 输出

**SwiftWork 参考模式：**
- `AgentBridge.configure()` — 一个函数准备所有 AgentOptions
- `AgentBridge.sendMessage()` / `startNextQueuedMessage()` — 统一的执行入口

**Acceptance Criteria:**

**Given** RunCommand (CLI) 和 ApiRunner (API) 都需要执行 agent 任务
**When** 构建和运行 Agent
**Then** 两者调用同一个共享函数 `buildAndRunAgent(config:task:options:)` 构建 AgentOptions 并执行

**Given** 共享函数创建 AgentOptions
**When** 构建选项
**Then** 必须传入 `skillRegistry`（启用 SDK 的 ToolRestrictionStack）
**And** 必须传入 `tools`（SDK core + specialist 工具）
**And** MCP servers 通过 `mcpServers` 参数传入
**And** 必须传入 `hookRegistry`（SafetyHook，shared seat mode 下阻止前台工具）
**And** 必须传入 `memoryStore`（Memory 上下文注入 system prompt）
**And** 不手动设置 `allowedTools`（由 SDK 的 restrictionStack 管理）

---

### Story 19.2: Skill 处理对齐 SwiftWork 模式

As a 用户,
I want `/skill-name` 触发的技能由 SDK 完整管理,
So that skill 的 prompt 注入、工具限制、生命周期都正确工作, 不会出现 LLM 调用 screenshot 而不是 bash 的问题.

**现状问题：**
- RunCommand 用 `skill.promptTemplate` 手动构建 system prompt
- `allowedTools` 由应用层手动设置，但过滤不生效（case-sensitive 问题、MCP 工具绕过）
- `skillRegistry` 不传给 SDK → `ToolRestrictionStack` 永远 nil
- `AgentRunner.runSkillAgent()` 有完全相同的 bug（重构后为 `ApiRunner`）

**SwiftWork 参考模式：**
- `resolveExplicitSlashSkillRequest()` — 预解析 skill，格式化为 user message
- `AgentOptions` 中传 `skillRegistry` — 启用 SDK 的 restrictionStack
- Skill 的 prompt 和限制通过 SkillTool 的返回值传递给 LLM

**Acceptance Criteria:**

**Given** 用户输入 `/polyv-live-cli 获取频道信息`
**When** RunCommand 检测到显式 skill 触发
**Then** 预解析 skill（参照 SwiftWork 的 `resolveExplicitSlashSkillRequest`）
**And** 将解析结果格式化为 user message 传给 `agent.stream()`
**And** 不修改 system prompt、不设置 allowedTools

**Given** skill 有 `allowed-tools: Bash(...)` 限制
**When** SkillTool 被 LLM 调用（或预解析执行 SkillTool）
**Then** SDK 的 ToolRestrictionStack.push(restrictions) 被调用
**And** 后续 turn 中 ToolExecutor 只允许 Bash 工具
**And** MCP 工具（screenshot、type_text 等）被自动过滤

**Given** AgentOptions 构建
**When** 传入 skillRegistry
**Then** SDK 内部的 `restrictionStack` 不再是 nil
**And** `Agent.swift:1097` 的判断 `options.skillRegistry != nil` 为 true

---

### Story 19.3: API 路径对齐

As a API 用户,
I want HTTP API 的 skill 和普通任务执行与 CLI 使用相同的代码路径,
So that CLI 和 API 的行为一致, 不会出现"CLI 能用但 API 不行"的问题.

**现状问题：**
- `AgentRunner.runAgent()` 不传 `tools`、不传 `skillRegistry`（重构后为 `ApiRunner`）
- `AgentRunner.runSkillAgent()` 复制了 RunCommand 的所有 skill bug
- SSE 事件格式化、CostTracking 等应用层逻辑散落在两个独立函数中

**重构方案：**
- 将 `AgentRunner.swift` 重命名为 `ApiRunner.swift`，类/枚举名同步修改
- ApiRunner 调用共享函数 `buildAndRunAgent()`，不再自行构建 AgentOptions
- SSE 事件、CostTracking、SeatMonitor 等 API 特有逻辑保留在 ApiRunner 中

**Acceptance Criteria:**

**Given** HTTP API 的 `/api/runs` 端点收到任务请求
**When** ApiRunner 执行任务
**Then** 使用与 RunCommand 相同的共享构建函数
**And** 传入 skillRegistry、tools、mcpServers
**And** SSE 事件和 CostTracking 仍然正常工作

**Given** HTTP API 的 skill 触发端点
**When** 执行 skill 任务
**Then** 使用与 CLI `/skill-name` 相同的预解析 + user message 模式
**And** skill 的工具限制由 SDK 的 ToolRestrictionStack 强制执行

---

## Epic 20: 死代码清理与架构精简

### Story 20.1: 删除自建 Agent Loop 死代码

As a 开发者,
I want 删除从未被使用的 RunEngine 全套代码,
So that 代码库更清晰, 新贡献者不会被死代码误导.

**待删除文件清单：**
- `Sources/AxionCLI/Engine/RunEngine.swift` — 自建 plan→execute→verify→replan 循环，从未实例化
- `Sources/AxionCLI/Planner/LLMPlanner.swift` — 自建 LLM planner，直接调 LLM API 和 MCP，仅被 RunEngine 使用
- `Sources/AxionCLI/Planner/PlanParser.swift` — 解析 LLM 输出为 Plan 结构体，仅被 LLMPlanner 使用
- `Sources/AxionCLI/Executor/StepExecutor.swift` — 直接 MCP 步骤执行器，仅被 RunEngine 使用
- `Sources/AxionCLI/Executor/PlaceholderResolver.swift` — `$pid`/`$window_id` 占位符解析
- `Sources/AxionCLI/Executor/SafetyChecker.swift` — 步骤级安全检查（shared seat mode 的 Hook 已替代）
- `Sources/AxionCLI/Verifier/TaskVerifier.swift` — 任务验证器，仅被 RunEngine 使用
- `Sources/AxionCLI/Verifier/StopConditionEvaluator.swift` — 停止条件评估
- `Sources/AxionCLI/Verifier/VisualDeltaChecker.swift` — 视觉增量检查
- `Sources/AxionCLI/Output/JSONOutput.swift` — RunEngine 的 JSON 输出（非 CLI `--json` 输出）
- `Sources/AxionCLI/Output/TerminalOutput.swift` — RunEngine 的终端输出

**AxionCore 中待清理的协议/模型（需确认无其他引用）：**
- `PlannerProtocol`、`ExecutorProtocol`、`VerifierProtocol`、`OutputProtocol` — 仅被死代码引用
- `MCPClientProtocol` — 被 StepExecutor 和 LLMPlanner 使用（死代码），也被 HelperMCPClientAdapter 使用（需评估）
- `Plan`、`Step`、`ExecutedStep`、`RunContext`、`RunState` 等模型 — 检查是否仅被死代码引用

**Acceptance Criteria:**

**Given** 上述文件列表
**When** 删除所有文件
**Then** `swift build` 编译通过
**And** `swift test --filter "AxionCLITests"` 全部通过
**And** `swift test --filter "AxionCoreTests"` 全部通过

**Given** 删除后的代码库
**When** 搜索 `RunEngine`、`LLMPlanner`、`StepExecutor`、`PlanParser`
**Then** 零引用

---

## Phase 6 FR 追溯

| FR | Epic | Story |
|----|------|-------|
| FR36 | Epic 19 | 19.1 — 统一 Agent 执行入口，使用 SDK Agent 循环 |
| FR37 | Epic 19 | 19.1 — SDK MCP client 连接，不再手动调 MCP |
| FR38 | Epic 19 | 19.1 — SDK 工具注册，不再手动筛工具 |
| FR39 | — | 已在 Phase 1 实现（HookRegistry），Phase 6 保持不变 |
| FR40 | Epic 19 | 19.1 — SDK 流式消息，统一入口 |
| FR41 | Epic 19 | 19.2 — 明确 SDK 边界：skill 生命周期由 SDK 管理 |

## Phase 6 新增 NFR

- NFR47: RunCommand 和 ApiRunner 的 Agent 构建逻辑代码重复率 < 10%（共享函数提取）
- NFR48: 显式 skill 触发后，LLM 不再调用 skill 限制范围外的工具（由 SDK ToolRestrictionStack 保证，不依赖应用层过滤）
- NFR49: 删除死代码后，AxionCLI 模块文件数减少 ≥ 11 个
- NFR50: Phase 6 重构完成后，`grep -rl "RunEngine\|LLMPlanner\|StepExecutor\|PlanParser" Sources/` 返回空

## Phase 6 优先级与依赖

| 优先级 | Epic | 依赖 | 理由 |
|--------|------|------|------|
| P0 | Epic 20 (死代码清理) | 无 | 独立、低风险、先清理再重构，减少干扰 |
| P1 | Epic 19 Story 19.1 (统一入口) | Epic 20 | 核心重构，删除死代码后代码库更清晰 |
| P2 | Epic 19 Story 19.2 (Skill 对齐) | 19.1 | 依赖统一入口完成后才能正确传入 skillRegistry |
| P3 | Epic 19 Story 19.3 (API 对齐 + AgentRunner→ApiRunner 重命名) | 19.2 | 最后统一 API 路径，复用 CLI 的 skill 逻辑；同时重命名消除语义冲突 |

**实施建议顺序：20.1 → 19.1 → 19.2 → 19.3**

**理由：**
- 20.1 先行——删掉死代码让整个代码库变小，重构时搜索和验证更准确
- 19.1 是基础——统一入口后，19.2 和 19.3 的改动只需改一处
- 19.2 解决用户痛点——当前 skill 执行有 bug（调 screenshot 而不是 bash）
- 19.3 最后——API 路径依赖 CLI 路径验证通过后再对齐，同时完成 AgentRunner → ApiRunner 重命名

**实施约束：** Phase 6 的详细架构设计见 `_bmad-output/planning-artifacts/phase6-refactor-architecture.md`（重构前后 Mermaid 对比图 + 职责划分表 + 数据流）。实施时必须参照此文档，确保每层只做自己职责内的事，不重复犯应用层越权的错误。
