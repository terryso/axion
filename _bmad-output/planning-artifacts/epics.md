---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
  - step-04-final-validation
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
FR6: 用户可以通过自然语言描述执行桌面自动化任务（`axion run "任务描述" --live`）
FR7: 用户可以在干跑模式下预览执行计划而不实际操作桌面（`axion run "任务描述"` 无 `--live`）
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
NFR21: 支持 macOS 13（Ventura）及以上版本
NFR22: 不依赖 Xcode Command Line Tools 以外的系统级软件
NFR23: 支持 Apple Silicon（arm64）和 Intel（x86_64）

### Additional Requirements

- AR1: 使用自定义 SPM 项目结构（三目标：AxionCLI / AxionHelper / AxionCore），无现成 starter template
- AR2: API Key 存储使用 macOS Keychain（Security.framework），不存明文 config（D1）
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
用户可以安装 Axion（brew install）、完成首次配置（axion setup：API Key 输入、权限引导）、验证系统环境（axion doctor）。配置系统支持分层覆盖（默认值 → config.json → 环境变量 → CLI 参数），API Key 安全存储于 macOS Keychain。

**FRs covered:** FR1, FR2, FR3, FR4, FR5
**ARs covered:** AR2, AR5

### Epic 3: 自然语言任务执行
用户输入 `axion run "打开计算器，计算 17 乘以 23" --live`，Axion 完成完整的 plan → execute → verify → replan 循环：Planner 调用 LLM 生成结构化执行计划，Executor 通过 MCP 调用 Helper 逐步执行，Verifier 通过截图和 AX tree 验证结果，失败时携带上下文自动重规划。整个过程中终端实时显示进度，支持干跑模式、步数限制、Ctrl-C 中断和前台模式。所有核心编排通过 SDK 公共 API 完成（Agent Loop、MCP Client、Tool Registry、Hooks、Streaming），产出清晰的 SDK 边界文档。

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

用户可以安装 Axion、完成首次配置、验证系统环境。配置系统支持分层覆盖，API Key 安全存储于 Keychain。

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

### Story 2.2: 配置系统与 Keychain 安全存储

As a 用户,
I want API Key 安全存储在 Keychain 中，配置文件管理其他参数,
So that 我的凭证不会泄露，且可以通过配置文件和环境变量调整行为.

**Acceptance Criteria:**

**Given** 首次使用
**When** 调用 KeychainStore.save(key:)
**Then** API Key 写入 macOS Keychain（service: "com.axion.cli"）

**Given** API Key 已存储在 Keychain
**When** 调用 KeychainStore.load()
**Then** 返回正确的 API Key

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
**Then** 将 API Key 安全存储到 Keychain

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
**Then** 报告 Keychain 中是否存在有效的 API Key

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

**Given** 运行 `axion run "打开计算器" --live`
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

**Given** 运行 `axion run "任务"` 不带 --live
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

**Given** 运行 `axion run "打开计算器，计算 17 乘以 23" --live`
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
**When** 运行 `axion run "打开计算器，计算 17 乘以 23" --live`
**Then** 成功完成，Calculator 显示 391

**Given** TextEdit 场景
**When** 运行 `axion run "打开 TextEdit，输入 Hello World" --live`
**Then** 成功完成，TextEdit 中包含 Hello World

**Given** Finder 场景
**When** 运行 `axion run "打开 Finder，进入下载目录" --live`
**Then** 成功完成，Finder 导航到下载目录

**Given** 浏览器场景
**When** 运行 `axion run "打开 Safari，访问 example.com" --live`
**Then** 成功完成，Safari 打开 example.com
