---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
  - step-04-final-validation
  - step-05-phase2-epics
  - step-06-phase3-epics
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
