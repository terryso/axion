# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.13.6] - 2026-06-17

### Added

- **Claude Code-compatible subagent/skill tool chain** — registers Agent, Task, and Skill tools consistently across chat, run, and direct skill paths
- **Software architecture audit workflow** — adds `/arch` and `axion arch` to find Intel-only macOS apps and command-line packages across installed apps, Homebrew, and MacPorts
- **Task/subagent observability** — renders child task progress, failures, summaries, and tool-call categories in interactive chat
- **Telegram network resilience** — classifies transient TG failures, 429 rate limits, auth failures, and polling conflicts with targeted retry/degrade behavior

### Changed

- Upgraded OpenAgentSDK resolution through the subagent compatibility line, including SDK 0.12.0 tool-event support
- Improved tool inheritance, permission diagnostics, and slash-skill guidance for child agents and direct skill execution
- Added project-level BMAD story creation customization so Epic 24+ stories load authoritative specs from `docs/epics/`

### Fixed

- 5xx Telegram API responses now retry as transient failures instead of being treated as permanent errors
- 401/403 Telegram auth failures now stop polling immediately with a local token-configuration hint
- 409 Telegram polling conflicts now degrade gracefully and stop after repeated conflicts
- Invalid, non-positive, or non-finite `Retry-After` header values now fall back to 5 seconds instead of causing no-delay retry or runtime traps

## [0.13.5] - 2026-06-14

### Added

- **Configurable MCP servers** — `config.json` now supports additional `mcpServers` for stdio, SSE, and HTTP transports, including auth headers for remote servers
- **`/mcp` status browser** — interactive chat can inspect enabled MCP servers, open redacted details, and print the full configuration with `/mcp --all`
- **Remote MCP visibility** — MCP status output redacts header/env secrets while preserving useful server URL, command, and transport details

### Changed

- Improved external MCP tool rendering in chat output, including clearer tool categories and readable wide-table layout
- Strengthened desktop automation prompting so native macOS GUI tasks use AxionHelper MCP tools instead of shell/AppleScript fallbacks
- E2E and integration Makefile targets now use the debug Helper binary in source builds and run serially to avoid GUI/MCP contention

### Fixed

- Stabilized acceptance GUI automation by requiring Helper MCP discovery before the calculator E2E runs
- Stabilized real Safari/URL smoke tests by using a bounded MCP-only browser flow
- Made Helper path tests deterministic even when `.build/debug/AxionHelper` exists in the local checkout

## [0.13.4] - 2026-06-13

### Added

- **`pause_for_human` 确认门** — Chat 模式响应 SDK 的 `.system(.paused)` 事件，挂起的 agent 可通过交互式确认门恢复 / 跳过 / 终止，避免 REPL 卡死
- **TakeoverIO 确认提示** — 新增 `displayConfirmationPrompt`，面向 AI 工具调用后的确认 / 反馈场景，支持回车继续、可选补充说明、`skip` 跳过、`abort` 终止
- **PausedEventDecider** — 抽取纯函数 seam，把 (canResume, 用户动作) 映射为 `resume` / `interrupt` 决策，便于单测且不依赖 `Agent` / stdin / `SignalHandler`
- **GLM 适配说明** — README 中英文均标注 Axion 全功能可通过 OpenAI Compatible Provider 跑通 GLM 大模型

### Fixed

- 修复 `pause_for_human` 触发后 agent 挂起在 `CheckedContinuation` 导致 `for await` 永久阻塞、用户既无法输入也无法取消的死锁
- pause-abort 路径（经 readLine 终止）现通过 `simulateFire` 保持中断语义，避免 turn-end 误判为正常完成

## [0.13.3] - 2026-06-13

### Added

- **Mac Storage/File/App 管理域** — 新增安全文件扫描、语义整理计划、执行与撤销链路
- **App 卸载与支持数据扫描** — 支持 App 候选发现、详情分析、support data 审查与可撤销卸载
- **多入口存储审批** — `run` / `chat` / Telegram 共用审批语义；非交互入口保守拒绝副作用
- **/storage 与 /apps 体验** — 交互模式支持大文件扫描、目录整理、撤销和 App 候选选择
- **Storage E2E 套件** — 覆盖工具链、审批链和端到端存储场景

### Changed

- 统一 system prompt 架构，移除独立 coding-agent prompt
- 升级 OpenAgentSDK 到 0.8.3
- 优化存储整理和 App 清理输出，支持 app detail 分析缓存

### Fixed

- App 列表默认隐藏路径、显示大小，并支持候选分页
- Support data 表格显示完整路径，降低清理前误判风险
- 新启动应用的 AX window 获取增加重试，提升可访问性就绪稳定性

## [0.13.2] - 2026-06-11

### Added

- **SlashPopup 两列布局** — Claude Code 风格名称+描述列，CJK 宽字符折行，物理行光标修复
- **可配置提示栏** (PromptDisplayConfig) — 用户可在 config.json 中开关进度条、回合数、成本、Git 分支等显示段；长分支名自动截断并显示省略号
- **响应速度分析** (ResponseSpeedTracker) — 追踪 TTFT 和生成速度 (tok/s)，回合摘要显示为 `── 3.0s (think 800ms · 136 tok/s) · 2 tools · ↑1.2k ↓856 ──`
- **工具使用分析** (ToolUsageTracker) — 记录每工具调用次数，在 /status 和退出摘要中渲染频率分布图表
- **上下文压缩可视化** (CompactionDisplayFormatter) — 双进度条对比 + 节省空间指标 `✂ [█████████░] 90% → [█░░░░░░░░░] 8% · 节省 82k (91%)`
- **启动提示系统** — 首次运行显示欢迎信息，回访用户随机显示功能发现提示
- **Git 分支状态** — 提示栏显示当前分支名和 dirty 工作树标记
- **富 /status 面板** — 会话时长、回合数、工具使用、上下文进度条（绿/黄/红）、token 明细、预估成本
- **会话累计成本** — 提示栏实时花费可见 + 80% 上下文阈值主动 /compact 建议
- **会话日志** — 完整对话（用户输入、LLM 响应、工具调用）持久化到 `~/.axion/sessions/{id}.jsonl`
- **跨会话命令历史** — 用户输入持久化到 `~/.axion/history.jsonl`，支持 Up/Down 跨会话历史导航
- **Shell 输出增强** — 多行输出内联显示（最多 4 行，dimmed，缩进）

### Fixed

- 多行历史导航显示上移 bug + 续行空行提交问题

## [0.13.1] - 2026-06-10

### Fixed

- SDK 0.8.0 网络重试修复

## [0.13.0] - 2026-06-10

### Added

- **SlashPopup skill 补全** — 斜杠命令弹出层支持 skill 列表补全 + 表格终端宽度限制
- **系统事件渲染** (SystemEventRenderer) — 上下文压缩通知、系统状态、速率限制警告、任务完成通知四类 SDK 系统事件渲染
- **文件变更摘要** (FileChangeTracker) — 每轮 turn 结束自动追踪并渲染 Created/Edited/Read + 行数统计 + Unicode 树形结构
- **语法高亮** (CodeSyntaxHighlighter) — 16 种语言的轻量级正则高亮（关键字/字符串/注释/数字/内建类型），TrueColor/ANSI256/ANSI16 降级链
- **回合摘要增强** — 彩色上下文进度条 + 预估回合成本显示
- **剪贴板集成** (ClipboardService + /copy) — 支持 pbcopy/OSC 52/tmux 三后端自动降级
- **Markdown 图片渲染** — `![alt](url)` → `[📷 alt]` 彩色占位 + OSC 8 超链接；H1/H2 下划线装饰
- **Diff 感知代码块** — diff/patch 语言标签自动着色（绿色新增、红色删除、文件头、hunk 头）
- **Markdown 增强** — 删除线、任务列表（☐/☑）、内联链接（OSC 8 可点击超链接）
- **流式表格渲染** (StreamingTableRenderer) — 检测 Markdown pipe tables 并渲染 Unicode box-drawing 对齐表格
- **流式 Markdown 格式化** — 标题（H1-H4 着色）、粗体、行内代码、水平线

### Fixed

- 空缓冲区时 Ctrl+C 多余换行
- 代码块边框渲染三个问题
- 多行粘贴后显示错位（OPOST 禁用导致 `\n` 不转 `\r\n`）
- 多行粘贴后退格导致行重复
- 表格单元格内 Markdown 格式不渲染
- 粘贴需三次才能生效（EscapeInterruptListener 僵尸 Task 竞争 stdin）

## [0.12.1] - 2026-06-10

### Added

- 审批决策简化 — 单键输入（y/n/a）替代完整输入
- ESC/stdin 协调 — 改进 EscapeInterruptListener 与 stdin 的交互
- 错误消息透传 — SDK 错误信息直接显示给用户

## [0.12.0] - 2026-06-10

### Added

- **EscapeInterruptListener** — ESC 键中断 Agent 执行
- **Skill 执行** — `/skills` 列表 + `/skill-name` 直接执行
- **交互模式 E2E 测试** — Banner/Prompt/SlashCommand/Streaming/Interrupt/InputQueue/SessionWorkflow 覆盖
- **/clear 增强** — 清除对话上下文（清空 session store + agent 内存 + REPL 状态 + 清屏）
- **上下文进度条溢出** — >100% 用品红色 `▓` 显示
- **Shimmer 动画** — Codex 风格余弦扫光高亮带
- **审批 Diff 预览** (ApprovalDiffPreview) — Edit/Write 审批时显示绿色新增/红色删除
- **彩色 Diff 格式化** (DiffFormatter) — /diff 命令输出 ANSI 彩色 git diff
- **流式 Markdown 格式化** — 标题、粗体、行内代码、水平线的流式渲染
- **工具类别格式化** (ToolCategoryFormatter) — 7 类工具语义化图标/标签/颜色方案
- **流式代码块渲染** (StreamingCodeBlockRenderer) — Unicode box-drawing 边框 + 语言标签
- **快捷键提示** (KeyHintsFormatter) — 启动/恢复 banner 和 /help 中的分组提示
- **终端超链接** (TerminalHyperlinkFormatter) — OSC 8 序列，文件路径和 URL 可点击
- **回合文件变更摘要** (TurnFileChangeTracker) — 彩色编码 +/- 行数
- **工具输出格式化** (ToolOutputFormatter) — 紧凑 JSON、智能截断、路径感知中间截断

### Fixed

- SlashPopup 无匹配命令时 Enter 提交输入而非忽略
- Ctrl+C 中断后 spinner 残留和 SDK JSON 错误日志
- 交互模式长文本换行重绘 bug
- Slash popup 弹窗残留行 bug（raw mode OPOST 关闭）

## [0.11.0] - 2026-06-06

### Added

- **Skill 生命周期完成** — Skill 发现、save_skill 工具、系统提示注入

## [0.10.2] - 2026-06-04

### Added

- Session 感知的审查调度器 (GatewaySessionStore)
- MarkdownV2 格式化管道 + 通用记忆 (Universal Memory)

### Changed

- 移除 CostEventHandler 和 LLMInfoHandler，精简输出

## [0.10.1] - 2026-06-03

### Added

- LLM round timing 和 hook timing 输出
- 环境变量透传支持

## [0.10.0] - 2026-06-02

### Added

- **Telegram Gateway** — 完整的 Telegram Bot 集成
  - 富文本 MarkdownV2 渲染与可靠发送管道
  - Edit-based Streaming 与状态气泡复用
  - Typing UX 与 Draft Preview
  - 命令注册表、帮助输出与 Bot 菜单
  - 交互式审批、确认与 Clarify
  - Inline keyboard 分页
  - 工具结果反馈到 TG 流式体验
- **双轨记忆系统** — MEMORY.md + USER.md
  - 记忆操作工具 — Agent 主动读写记忆
  - 审查代理注入通用记忆工具
  - 安全扫描与冻结快照集成
  - CLI 记忆管理命令
- **AxionRuntime 执行引擎**
  - RunCommand 通过 AxionRuntime 执行
  - ApiRunner 通过 AxionRuntime 执行
  - Session Resume CLI 命令
  - Session List CLI 命令
  - Daemon 模式 AxionRuntime 集成
  - Skill 执行通过 AxionRuntime
- **EventHandler 体系** — 7 个 handler 实现 + RunCommand 集成
- **AxionRunState + Session 元数据** — 状态持久化

### Changed

- Protocol 抽象依赖注入 + 单元测试全面 Mock 化
- SDK 依赖升级

## [0.9.1] - 2026-05-28

### Fixed

- 运行日志重复输出

### Changed

- 中文 README 徽章改用 zread.ai
- 添加 BMAD/DeepWiki 徽章

## [0.9.0] - 2026-05-28

### Added

- **EventHandler 体系** — 7 个 handler 实现 + RunCommand 集成
- **Session 管理** — List / Resume CLI 命令 + 状态持久化 + 元数据
- **AxionRuntime 执行引擎** — RunCommand 和 ApiRunner 统一通过 AxionRuntime 执行
- **Daemon 模式** — AxionRuntime 集成
- **Skill 执行** — 通过 AxionRuntime 执行

### Changed

- Protocol 抽象依赖注入 + 单元测试全面 Mock 化
- SDK 依赖升级到 0.6.0

### Fixed

- 单元测试触发系统通知问题 + 多项代码清理

## [0.8.0] - 2026-05-25

### Added

- **Review 系统** — ReviewOrchestrator 接入 RunOrchestrator
  - SkillEvolver 集成 — 直接使用 SDK LLMSkillEvolver
  - IntelligentCurator 智能策展
  - Skill 使用追踪集成
  - Review 配置项与 CLI 标志
  - Review 结果日志与通知

## [0.7.0] - 2026-05-23

### Added

- **macOS 桌面通知** — 运行完成时显示桌面通知
- **AI 摘要** — 完成通知附带 AI 生成的运行摘要
- **终端重新激活** — 运行完成后自动恢复终端前台

## [0.6.1] - 2026-05-22

### Added

- **click_element 工具** — 简化按钮点击操作
- **AX 树预计算中心坐标** — 提升点击精度

## [0.6.0] - 2026-05-22

### Changed

- **SDK 提取重构** — 大规模架构重组
  - 用 SDK SDKMessageOutputHandler 替换输出处理
  - 用 SDK Memory 基础设施替换通用逻辑
  - 用 AgentOptions 替换 CostTracker + TraceRecorder
  - Axion 用 SDK 组件重建 HTTP API 层
  - 内部重构（ToolRegistrar 拆分、AgentBuilder 清理）
- 移除 AxionBar，适配新架构

## [0.5.6] - 2026-05-20

### Changed

- 重构为通用 Agent + 桌面自动化能力

## [0.5.5] - 2026-05-20

### Changed

- CLI skill 调用使用 executeSkillStream（无 MCP，节省一轮 LLM 调用）

## [0.5.4] - 2026-05-20

### Added

- **统一 Agent 执行入口** (Story 19.1)
- **SDK executeSkillStream()** — 消除手动 skill 解析

### Fixed

- 单元测试文件系统隔离 + 多项健壮性改进
- 集成测试隔离和 flaky 阈值修复

### Changed

- SDK 升级到 0.4.1 — 修复 MCP transport EXC_GUARD 崩溃

## [0.5.3] - 2026-05-18

### Fixed

- Prompts 目录路径解析相对于可执行文件（非 CWD 运行场景）

## [0.5.2] - 2026-05-18

### Fixed

- SDK 升级到 0.3.4 — 工具过滤改为大小写不敏感

## [0.5.1] - 2026-05-18

### Fixed

- SDK 升级到 0.3.3 — 移除 Skill 结果中的 allowedTools

## [0.5.0] - 2026-05-18

### Added

- **Skill 系统** — 双轨查找 + 显式/隐式触发 + Memory 联动
  - RunCommand 集成 SkillRegistry
  - 双轨技能查找（内置 + 外部）
  - 显式 /skill-name 触发
  - 隐式技能触发
  - 内置桌面技能
  - 技能 + Memory 联动
  - HTTP API 支持 Skill 触发

## [0.4.1] - 2026-05-17

### Fixed

- HelperPathResolver 符号链接解析 — 修复 Homebrew 安装路径
- CI release workflow 缺失 step id

## [0.4.0] - 2026-05-17

### Added

- **Homebrew 发布** — Homebrew 安装文档 + GitHub Action 自动发布
- **launchd Daemon** — API Server 持久化运行
- **Takeover 学习** — 经验自动学习 + 结构化标记
- **Settings API** — 配置端点
- **Capabilities 端点** — 能力查询
- **桌面活动检测** — 运行锁保护
- **精细预算控制** — 成本遥测
- **视觉增量检查** — 避免不必要的截图
- **记忆系统基础** — 三类分类（affordance/avoid/observation）+ 导入导出

## [0.3.0] - 2026-05-16

### Added

- **Playwright MCP Server** — Web 自动化支持
- **桌面 Takeover** — 接管桌面应用执行任务
  - 阻塞对话框检测
  - DispatchSource 信号处理 SIGINT
- **测试迁移** — 全面迁移到 Swift Testing 框架
- **记忆系统** — AppMemoryFact 模型 + 生命周期状态 + 置信度评分
- **窗口管理** — 应用启动、窗口列表、窗口状态

### Fixed

- SIGINT 处理改进
- 应用识别跨语言环境兼容
- UNUserNotificationCenter bundle 检查保护

## [0.1.0] - 2026-05-09

### Added

- **项目初始化** — SPM 脚手架 + AxionCore 共享模型
- **Helper MCP Server** — 15 个桌面自动化工具（截图、AX 树、URL 打开、鼠标/键盘模拟、应用启动、窗口管理）
- **CLI 入口** — ArgumentParser 骨架
- **ConfigManager** — 分层配置加载（命令行 > 环境变量 > config.json > 默认值）
- **axion setup** — 首次配置命令（API Key + provider + baseURL）
- **axion doctor** — 环境检查命令
- **CI** — GitHub Actions 单元测试 + 覆盖率报告
- **Helper App Bundle** — 打包脚本 + 集成测试

[0.13.3]: https://github.com/terryso/axion/releases/tag/v0.13.3
[0.13.2]: https://github.com/terryso/axion/releases/tag/v0.13.2
[0.13.1]: https://github.com/terryso/axion/releases/tag/v0.13.1
[0.13.0]: https://github.com/terryso/axion/releases/tag/v0.13.0
[0.12.1]: https://github.com/terryso/axion/releases/tag/v0.12.1
[0.12.0]: https://github.com/terryso/axion/releases/tag/v0.12.0
[0.11.0]: https://github.com/terryso/axion/releases/tag/v0.11.0
[0.10.2]: https://github.com/terryso/axion/releases/tag/v0.10.2
[0.10.1]: https://github.com/terryso/axion/releases/tag/v0.10.1
[0.10.0]: https://github.com/terryso/axion/releases/tag/v0.10.0
[0.9.1]: https://github.com/terryso/axion/releases/tag/v0.9.1
[0.9.0]: https://github.com/terryso/axion/releases/tag/v0.9.0
[0.8.0]: https://github.com/terryso/axion/releases/tag/v0.8.0
[0.7.0]: https://github.com/terryso/axion/releases/tag/v0.7.0
[0.6.1]: https://github.com/terryso/axion/releases/tag/v0.6.1
[0.6.0]: https://github.com/terryso/axion/releases/tag/v0.6.0
[0.5.6]: https://github.com/terryso/axion/releases/tag/v0.5.6
[0.5.5]: https://github.com/terryso/axion/releases/tag/v0.5.5
[0.5.4]: https://github.com/terryso/axion/releases/tag/v0.5.4
[0.5.3]: https://github.com/terryso/axion/releases/tag/v0.5.3
[0.5.2]: https://github.com/terryso/axion/releases/tag/v0.5.2
[0.5.1]: https://github.com/terryso/axion/releases/tag/v0.5.1
[0.5.0]: https://github.com/terryso/axion/releases/tag/v0.5.0
[0.4.1]: https://github.com/terryso/axion/releases/tag/v0.4.1
[0.4.0]: https://github.com/terryso/axion/releases/tag/v0.4.0
[0.3.0]: https://github.com/terryso/axion/releases/tag/v0.3.0
[0.1.0]: https://github.com/terryso/axion/releases/tag/v0.1.0
