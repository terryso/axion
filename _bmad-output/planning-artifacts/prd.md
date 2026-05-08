---
stepsCompleted:
  - step-01-init
  - step-02-discovery
  - step-02b-vision
  - step-02c-executive-summary
  - step-03-success
  - step-04-journeys
  - step-05-domain-skipped
  - step-06-innovation-skipped
  - step-07-project-type
  - step-08-scoping
  - step-09-functional
  - step-10-nonfunctional
  - step-11-polish
  - step-12-complete
inputDocuments:
  - _bmad-output/planning-artifacts/product-brief-open-agent-sdk-swift.md
  - _bmad-output/planning-artifacts/product-brief-open-agent-sdk-swift-distillate.md
  - docs/product-plan.md
  - _bmad-output/project-context.md
  - _bmad-output/planning-artifacts/architecture.md
documentCounts:
  briefs: 2
  research: 0
  projectDocs: 1
  projectContext: 1
  architecture: 1
  openClickReference: direct-source-study
classification:
  projectType: cli_tool_with_macos_helper
  domain: macos_desktop_automation_ai_agent
  complexity: medium-high
  projectContext: brownfield-sdk-greenfield-cli-greenfield-helper
  productName: Axion
  cliBinary: axion
  helperApp: AxionHelper
  configDir: ~/.axion
  newRepo: axion
workflowType: 'prd'
documentLanguage: 'zh-CN'
---

# 产品需求文档 — Axion

**作者:** Nick
**日期:** 2026-05-08

## 执行摘要

Axion 是一个 Swift 原生的 macOS 桌面自动化 CLI 工具。用户输入自然语言指令（如「打开计算器，计算 17 乘以 23」），Axion 自动规划并执行桌面操作 — 点击、输入、打开应用、浏览网页。

Axion 基于 OpenAgentSDK（Swift Agent SDK）构建，同时扮演两个角色：

1. **独立产品** — 一个零 Node.js 依赖的 Mac 自动化工具，`brew install axion` 开箱即用
2. **SDK 旗舰应用** — 通过真实产品开发验证 SDK 能力，发现短板，反向驱动 SDK 补全能力

Axion 的技术架构分两层：CLI 主进程负责规划、执行、记忆和 API 服务；AxionHelper（签名的 macOS App）负责实际的 Accessibility API 操作、截图和窗口管理。CLI 通过 MCP stdio 协议与 Helper 通信。

### 核心差异化

**零运行时依赖。** OpenClick 需要 Bun/Node.js 运行时 + npm 全局安装，Axion 是一个静态编译的 Swift 二进制，加上一个签名 Helper App。用户不需要安装任何运行时环境。

**进程内工具执行。** OpenClick 的每个 AX 操作都要 fork cua-driver 子进程，AxionHelper 作为 MCP server 长驻，工具调用走 stdio 管道，消除进程创建开销。

**SDK 原生集成。** Axion 直接依赖 OpenAgentSDK 的 Agent 循环、工具系统、MCP client、Hooks 和 Session 管理，而非像 OpenClick 那样绕过 SDK 自己实现 planner/executor 循环。SDK 不够用的地方，先补 SDK，再在 Axion 里使用。

## 项目分类

| 维度 | 分类 |
|------|------|
| 项目类型 | CLI 工具 + macOS Helper App（签名） |
| 领域 | macOS 桌面自动化 / AI Agent |
| 复杂度 | 中高 |
| 项目上下文 | 棕地 SDK（OpenAgentSDK）+ 绿地 CLI + 绿地 Helper |
| 独立仓库 | `axion`（SPM 包，依赖 OpenAgentSDK） |

## 成功标准

### 用户成功

- 用户通过 `brew install axion` 安装后，5 分钟内跑通第一个桌面任务（如「打开计算器，计算 17 × 23」）
- 用户能用自然语言完成多步桌面操作（打开 App → 导航 → 输入 → 验证结果）
- 用户不需要安装 Node.js、npm、Bun 或任何 JavaScript 运行时
- 错误场景有清晰的反馈，不是静默失败

### 业务成功

- Axion 能跑通 OpenClick 的核心场景：Calculator、TextEdit、Finder、Chrome/Safari 导航
- GitHub 获得社区关注（开发者对 Swift 原生 Agent 方案的认可）
- 至少 3 个非作者的早期用户试用并反馈

### 技术成功（SDK 边界打磨）

这是 Axion 存在的核心价值：

- Axion 的核心流程（规划 → 执行 → 验证 → 重规划）**完全通过 SDK 公共 API 编排**，不绕过 SDK
- Planner、Executor、Memory 等模块的归属明确：属于应用层的写应用层，属于 SDK 的补进 SDK
- 每个 SDK 短板的发现都有清晰的边界推理：为什么这个能力应该由 SDK 提供，而不是应用自己实现
- 最终产出一份清晰的 **SDK vs 应用层边界文档**，成为后续 SDK 版本的指导

### 可衡量成果

- Axion 能成功执行 OpenClick README 中的 `openclick run "open Calculator and calculate 17 times 23" --live` 等价任务
- SDK 新增的能力都有对应的 Axion 集成测试覆盖
- Axion 代码中 `import OpenAgentSDK` 之后，应用层代码量显著少于 OpenClick 的 ~14k 行 TypeScript

## 产品范围

### MVP — 证明可行

- CLI 入口（`axion run "任务描述" --live`、`axion setup`、`axion doctor`）
- AxionHelper（签名 macOS App）：AX 操作、截图、窗口管理，通过 MCP stdio 暴露
- Planner：小批量规划引擎，调用 Sonnet 生成工具调用序列
- Executor：本地执行 planner 输出的步骤，通过 MCP 调用 AxionHelper
- 验证循环：截图 + AX tree 验证任务是否完成，失败则重规划
- 支持核心场景：Calculator、TextEdit、Finder、Chrome/Safari 基本导航
- SDK 边界文档：明确哪些在 SDK，哪些在应用

### 成长功能（MVP 后）

- 本地 App Memory（跨次运行的学习系统）
- HTTP API server + MCP server（外部集成）
- `--fast` 模式（小批量规划 + 本地执行，不走 Agent SDK）
- 用户接管（takeover）机制
- 更多 App 支持（基于 memory 积累）

### 愿景（未来）

- 复杂多窗口、多 App 工作流
- 录制 → 编译 → 技能复用
- macOS 菜单栏 UI
- 第三方基于 SDK 开发自己的 Agent 应用

## 用户旅程

### 旅程一：李明 — Mac 普通用户，第一次尝试桌面自动化

**背景：** 李明是一个产品经理，不是开发者。他每天要在 Mac 上做很多重复操作 — 打开企业微信看消息、在浏览器里查数据、把结果粘贴到 Excel 里。他听说了「用自然语言操控 Mac」这个概念，搜到了 Axion。

**开场：** 李明打开终端，输入 `brew install axion`。30 秒后安装完成。他运行 `axion setup`，系统引导他授权 Accessibility 和屏幕录制权限，并输入 Anthropic API Key。全程 2 分钟。

**发展：** 李明输入了他的第一个命令：

```
axion run "打开计算器，计算 17 乘以 23" --live
```

他看到终端输出：

```
[axion] 模式: 规划执行（小批量）
[axion] 运行 ID: 20260508-a3f2k1
[axion] 步骤 1/3: 启动 Calculator — 通过 launch_app
[axion] 步骤 2/3: 输入表达式 — 通过 press_key 序列
[axion] 步骤 3/3: 验证结果显示 391 — ✓ 通过
[axion] 完成。3 步，耗时 8.2 秒。
```

他看到 Calculator 真的打开了，结果真的是 391。

**高潮：** 李明试了一个更复杂的任务：

```
axion run "打开 Finder，进入下载目录，把最新的 PDF 文件移到桌面的 Reports 文件夹"
```

Axion 规划了 5 步，一步步执行。中间 Finder 的窗口位置跟预期不同，Axion 自动重规划了 1 次，最终成功。

**结局：** 李明觉得「这就是我需要的工具」。他不需要写脚本，不需要 Automator，不需要 AppleScript。说一句话就行。

**揭示需求：** 首次运行体验、权限引导、实时进度反馈、错误恢复/重规划、直观的结果确认。

### 旅程二：陈薇 — 开发者，想基于 SDK 开发自己的 Agent

**背景：** 陈薇是一个 Swift 开发者，她想做一个「自动化测试 Agent」— 自动操作她的 iOS 模拟器。她发现了 OpenAgentSDK，但不确定 SDK 能力够不够。

**开场：** 陈薇 clone 了 Axion 仓库，读了一遍代码。她看到 Axion 只用了 `import OpenAgentSDK` 就完成了 planner/executor 的编排。核心逻辑只有 ~2000 行 Swift，比她预想的少得多。

**发展：** 她发现了 SDK vs 应用层的边界文档。看到 Planner 和 Executor 是应用层逻辑，但 Agent 循环、MCP client、工具注册、Session 管理都是 SDK 提供的。她意识到自己只需要写：自定义工具（模拟器操作）+ 自定义 system prompt。

**高潮：** 陈薇用 SDK 的 `createAgent` + `defineTool` 在一个下午搭出了自己的 Agent 原型。工具注册、并发执行、错误捕获全部开箱即用。

**结局：** 陈薇在 GitHub 上 star 了 SDK 仓库，写了一篇博客「如何用 50 行 Swift 搭一个自定义 Agent」。

**揭示需求：** SDK 边界文档、清晰的公共 API、工具注册便利性、Agent 循环可定制性、代码示例。

### 旅程三：王强 — API 集成者，把 Axion 接入企业工作流

**背景：** 王强是一个企业的 DevOps 工程师，他想把 Axion 接入内部自动化平台，让 Agent 按计划执行 Mac 桌面任务。

**开场：** 王强启动 Axion 的 HTTP API server：`axion server --port 4242`。他发送第一个请求：

```bash
curl -X POST http://localhost:4242/v1/runs \
  -d '{"task": "打开 Chrome，访问内部看板，截图发到企业微信"}'
```

**发展：** 他收到一个 run ID，通过 SSE 事件流监听进度。任务成功完成，他拿到了截图文件路径。

**高潮：** 王强把 Axion 的 API 接入了公司的 Airflow 调度系统。每天早上 9 点，Axion 自动打开内部报表网站，截图，发送到企业微信群。

**结局：** 团队不再需要手动截日报了。王强开始探索更多自动化场景。

**揭示需求：** HTTP API、异步任务管理、SSE 事件流、MCP stdio 集成。（成长功能）

### 旅程需求总结

| 需求领域 | 来源旅程 | 优先级 |
|----------|----------|--------|
| 安装与首次运行体验 | 旅程一（李明） | MVP |
| 权限引导（Accessibility + 屏幕录制） | 旅程一（李明） | MVP |
| 实时进度反馈（终端输出） | 旅程一（李明） | MVP |
| Planner 规划引擎 | 旅程一（李明） | MVP |
| Executor + MCP 调用 Helper | 旅程一（李明） | MVP |
| 错误恢复与重规划 | 旅程一（李明） | MVP |
| SDK 边界文档与公共 API 清晰度 | 旅程二（陈薇） | MVP |
| HTTP API + 异步任务 | 旅程三（王强） | 成长功能 |
| SSE 事件流 | 旅程三（王强） | 成长功能 |
| MCP server（供外部 Agent 调用） | 旅程三（王强） | 成长功能 |

## CLI 工具 + macOS Helper 特定需求

### CLI 使用模式

| 模式 | 命令 | 说明 |
|------|------|------|
| 一次性执行 | `axion run "任务描述" --live` | 执行单个任务，完成后退出 |
| 可脚本化 | `axion run "任务" --live --max-steps 10 --max-batches 6` | 参数化控制，可被其他工具调用 |
| 安装与配置 | `axion setup` / `axion doctor` | 首次运行引导，权限检查 |
| API 服务 | `axion server --port 4242` | HTTP API + SSE 事件流（成长功能） |
| MCP 服务 | `axion mcp` | 作为 MCP stdio server 供外部 Agent 调用（成长功能） |

### 输出格式

| 格式 | 标志 | 用途 |
|------|------|------|
| 纯文本进度 | 默认 | 终端用户，实时显示步骤、结果、错误 |
| JSON 结构化 | `--json` | 脚本化调用，管道集成 |
| SSE 事件流 | API server 模式 | 外部集成者监听异步任务进度 |

### 配置系统

- 配置文件：`~/.axion/config.json`
- 环境变量覆盖（`AXION_API_KEY`、`AXION_MODEL` 等）
- 主要配置项：API Key、默认模型、最大步数、执行策略

### Helper 分发与生命周期

- **内嵌分发**：AxionHelper.app 打包在 CLI 安装包内（`libexec/axion/AxionHelper.app`）
- **安装**：`brew install axion` 一步完成 CLI + Helper
- **首次运行**：`axion setup` 引导授权 Accessibility + 屏幕录制权限
- **Helper 启动**：CLI 首次需要 AX 操作时自动启动 Helper（MCP stdio server），无需用户干预
- **Helper 生命周期**：随 CLI 进程退出而退出，不长驻系统

### 系统集成要求

| 要求 | 说明 |
|------|------|
| macOS 版本 | 14+（Sonoma 及以上） |
| Accessibility 权限 | AxionHelper 需要用户手动授权 |
| 屏幕录制权限 | 截图和视觉验证需要 |
| Apple Developer 签名 | AxionHelper 必须签名，否则权限授权不持久 |
| 无沙盒 | CLI 和 Helper 都不走 App Store，不启用沙盒 |

### 实现考量

- **Helper 通信**：通过 MCP stdio 协议（stdin/stdout JSON-RPC），不走网络
- **Helper 工具集**：launch_app、list_windows、get_window_state、click、type_text、press_key、hotkey、screenshot、scroll、open_url
- **CLI 入口**：Swift ArgumentParser，单二进制，静态编译
- **SPM 依赖**：OpenAgentSDK（Agent 引擎）、mcp-swift-sdk（Helper 端 MCP server）、ArgumentParser（CLI 解析）

## 项目范围与分阶段交付

### MVP 策略

**方法：** 问题验证型 MVP — 用最小功能集证明「Swift 原生桌面自动化」可行且有价值。

**团队：** 1 人（Nick），全栈（Swift + macOS + Agent 设计）

**MVP 核心假设：** OpenAgentSDK 的公共 API 足以编排一个完整的桌面自动化 Agent，不需要绕过 SDK。

### Phase 1 — MVP 功能集

**支撑的用户旅程：**
- 旅程一（李明）核心路径：安装 → 配置 → 执行任务 → 看到结果
- 旅程二（陈薇）部分路径：阅读代码 → 理解 SDK 边界 → 确认可基于 SDK 开发

**必须具备的能力：**

| 能力 | 说明 | 归属 |
|------|------|------|
| CLI 入口 | `axion run`、`axion setup`、`axion doctor` | 应用层 |
| AxionHelper | AX 操作、截图、窗口管理，MCP stdio server | 应用层（独立 App） |
| Planner | 调用 LLM 生成小批量工具调用序列 | 应用层 |
| Executor | 执行 planner 输出，通过 MCP 调用 Helper | 应用层 |
| 验证循环 | 截图 + AX tree 判断任务完成，失败则重规划 | 应用层 |
| Agent 循环编排 | planner/executor/verify 的循环控制 | **SDK** |
| MCP client | 连接 Helper，调用工具 | **SDK** |
| 工具注册 | 注册 Helper 工具到 Agent | **SDK** |
| Hooks | 执行前安全检查（共享座椅模式） | **SDK** |
| 流式输出 | 终端实时显示进度 | **SDK** |
| 配置管理 | API Key、模型、参数的读写 | 应用层 |
| SDK 边界文档 | 记录每个模块的归属和理由 | 文档 |

**核心场景覆盖：**
- Calculator（键盘输入 + 验证结果）
- TextEdit（打开文件 + 输入文本）
- Finder（导航目录 + 文件操作）
- Chrome/Safari 基本导航（打开 URL + 页面交互）

### Phase 2 — 成长功能

**依赖：** Phase 1 完成 + SDK 边界打磨成熟

| 能力 | 说明 |
|------|------|
| 本地 App Memory | 跨次运行的学习系统，积累操作经验 |
| HTTP API server | 异步任务提交 + SSE 事件流 |
| MCP server 模式 | 供外部 Agent 通过 stdio 调用 Axion |
| 用户接管 | 自动化受阻时暂停，用户手动完成后继续 |
| `--fast` 模式 | 小批量规划 + 本地执行，减少 LLM 调用 |
| JSON 输出 | `--json` 标志，脚本化调用 |

### Phase 3 — 愿景

| 能力 | 说明 |
|------|------|
| 多窗口、多 App 工作流 | 跨应用协调操作 |
| 录制 → 编译 → 技能复用 | 用户演示一遍，自动生成可复用技能 |
| macOS 菜单栏 UI | 原生图形界面 |
| 第三方生态 | 基于SDK开发自己的 Agent 应用 |

### 风险缓解

| 风险类型 | 风险 | 缓解策略 |
|----------|------|----------|
| 技术风险 | SDK 公共 API 不够用，需要 hack 绕过 | 这是预期内的 — 发现短板就补 SDK，这是 Axion 的核心价值 |
| 技术风险 | AxionHelper 签名和权限问题复杂 | 参考 OpenClick 的 OpenclickHelper 实现，路径已验证（本地路径：`/Users/nick/CascadeProjects/openclick`） |
| 市场风险 | 桌面自动化需求不如预期 | MVP 成本低（~2000 行 Swift），验证成本小 |
| 资源风险 | 1 人开发，SDK + 应用并行 | 先做 MVP，发现 SDK 短板时暂停 Axion 补 SDK，再回来继续 |

## 功能需求

### 安装与配置

- FR1: 用户可以通过 Homebrew 一行命令安装 Axion（CLI + Helper 同时安装）
- FR2: 用户可以通过 `axion setup` 完成首次配置（API Key 输入、权限引导）
- FR3: 用户可以通过 `axion doctor` 检查系统环境、权限状态和依赖完整性
- FR4: 用户可以通过配置文件（`~/.axion/config.json`）管理 API Key、模型选择和执行参数
- FR5: 用户可以通过环境变量覆盖配置文件中的设置

### 任务执行

- FR6: 用户可以通过自然语言描述执行桌面自动化任务（`axion run "任务描述" --live`）
- FR7: 用户可以在干跑模式下预览执行计划而不实际操作桌面（`axion run "任务描述"` 无 `--live`）
- FR8: 用户可以限制任务的最大步数和最大批次（`--max-steps`、`--max-batches`）
- FR9: 用户可以随时通过 Ctrl-C 中断正在执行的任务
- FR10: 用户可以在前台模式运行，允许使用全局光标和焦点操作（`--allow-foreground`）

### 规划引擎

- FR11: 系统可以根据任务描述和当前屏幕状态，通过 LLM 生成小批量工具调用序列（plan）
- FR12: 系统可以将截图和 AX tree 作为视觉上下文附加到规划请求中
- FR13: 系统可以在执行失败或验证未通过时，携带失败上下文重新规划
- FR14: 系统可以将规划结果解析为结构化的步骤序列（工具名、参数、目的、预期变化）
- FR15: 系统可以解析和修正 LLM 输出中的常见格式错误（markdown 围栏、前导文本等）

### 本地执行

- FR16: 系统可以按顺序执行 planner 生成的步骤，通过 MCP 调用 AxionHelper
- FR17: 系统可以解析 `$pid` 和 `$window_id` 占位符，从已执行步骤的结果中填充后续步骤的参数
- FR18: 系统可以在 AX 定位操作前自动刷新窗口状态，避免使用过期的元素索引
- FR19: 系统可以处理步骤执行失败，记录失败位置和原因，触发重规划
- FR20: 系统可以在共享座椅后台模式下阻止前台/全局操作，保障用户桌面可用性

### 任务验证

- FR21: 系统可以在每个批次执行完成后，通过截图和 AX tree 验证任务是否已完成
- FR22: 系统可以根据 planner 定义的 `stopWhen` 条件判断任务完成状态
- FR23: 系统可以区分任务完成（done）、被阻塞（blocked）和需要澄清（needs_clarification）状态

### AxionHelper（macOS 桌面操作）

- FR24: Helper 可以启动和列举 macOS 应用（launch_app、list_apps）
- FR25: Helper 可以列举和管理窗口（list_windows、get_window_state）
- FR26: Helper 可以执行鼠标操作（click、double_click、right_click、drag、scroll）
- FR27: Helper 可以执行键盘操作（type_text、press_key、hotkey）
- FR28: Helper 可以截取指定窗口的屏幕截图
- FR29: Helper 可以获取窗口的 Accessibility tree（AX tree）
- FR30: Helper 可以在默认浏览器中打开 URL
- FR31: Helper 作为 MCP stdio server 运行，通过 stdin/stdout JSON-RPC 通信
- FR32: Helper 在 CLI 启动时自动被拉起，CLI 退出时随之退出

### 进度反馈

- FR33: 系统可以在终端实时显示每个步骤的执行状态（工具名、目的、结果）
- FR34: 系统可以显示任务完成的汇总信息（总步数、耗时、重规划次数）
- FR35: 系统可以结构化输出 JSON 格式的执行结果（`--json`）

### SDK 集成与边界

- FR36: 系统使用 SDK 的 Agent 循环编排 planner/executor/verify 的完整工作流
- FR37: 系统使用 SDK 的 MCP client 连接 AxionHelper 并调用工具
- FR38: 系统使用 SDK 的工具注册机制注册 Helper 提供的桌面操作工具
- FR39: 系统使用 SDK 的 Hooks 机制实现执行前的安全策略检查
- FR40: 系统使用 SDK 的流式消息机制输出实时进度
- FR41: 产出的 SDK 边界文档明确记录每个模块的归属（SDK / 应用层）和理由

## 非功能需求

### 性能

- NFR1: CLI 冷启动到首次 LLM 请求发出 < 2 秒（不含网络延迟）
- NFR2: AxionHelper 启动到 MCP 连接就绪 < 500 毫秒
- NFR3: 单个 AX 操作（点击、输入）从 MCP 请求到结果返回 < 200 毫秒
- NFR4: CLI 进程常驻内存 < 30MB，Helper 进程常驻内存 < 20MB

### 可靠性

- NFR5: Helper 单次操作失败不导致 CLI 崩溃，错误通过 ToolResult 返回
- NFR6: LLM API 调用失败时自动重试（最多 3 次，指数退避）
- NFR7: 规划结果解析失败时记录原始响应，不静默丢弃
- NFR8: 用户 Ctrl-C 中断时正确清理 Helper 进程，不留僵尸进程

### 安全性

- NFR9: API Key 不出现在日志、trace 或终端输出中
- NFR10: 共享座椅模式下默认阻止前台操作（移动光标、抢焦点），防止干扰用户
- NFR11: Helper 仅响应来自本地 CLI 的 MCP 请求，不监听网络端口
- NFR12: 截图和 AX tree 数据仅用于当前任务，不在磁盘持久化（除非用户启用 trace）

### 可用性

- NFR13: `axion setup` 提供清晰的逐步引导，非技术用户可在 5 分钟内完成
- NFR14: `axion doctor` 输出明确的修复建议，不只是报错
- NFR15: 任务执行过程中终端输出实时更新，用户无需猜测进度
- NFR16: 错误信息使用自然语言描述，不暴露内部异常堆栈

### 可维护性

- NFR17: CLI 代码与 SDK 通过 SPM 依赖解耦，SDK 更新只需修改版本号
- NFR18: Helper 工具集可独立扩展，新增工具无需修改 CLI 核心逻辑
- NFR19: Planner 的 system prompt 可独立修改，不硬编码在代码中
- NFR20: 每次运行生成 trace 文件（`~/.axion/runs/{runId}/trace.json`），用于调试和回溯

### 兼容性

- NFR21: 支持 macOS 14（Sonoma）及以上版本
- NFR22: 不依赖 Xcode Command Line Tools 以外的系统级软件
- NFR23: 支持 Apple Silicon（arm64）和 Intel（x86_64）

---

## 技术架构概览

```
┌─────────────────────────────────────────────────┐
│  Axion CLI (Swift, 单二进制)                      │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ Argument │  │ Planner  │  │   Executor    │  │
│  │  Parser  │  │ (LLM 调用)│  │ (MCP 调用)    │  │
│  └──────────┘  └──────────┘  └───────────────┘  │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ Verifier │  │ Config   │  │   Trace       │  │
│  │ (验证循环)│  │ Manager  │  │   Recorder    │  │
│  └──────────┘  └──────────┘  └───────────────┘  │
├─────────────────────────────────────────────────┤
│  OpenAgentSDK (SPM 依赖)                          │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  Agent   │  │   MCP    │  │     Hooks     │  │
│  │  Loop    │  │  Client  │  │   Registry    │  │
│  ├──────────┤  ├──────────┤  ├───────────────┤  │
│  │  Tool    │  │ Streaming│  │   Session     │  │
│  │ Registry │  │ (AsyncStm)│  │    Store      │  │
│  └──────────┘  └──────────┘  └───────────────┘  │
├─────────────────────────────────────────────────┤
│  MCP stdio 协议 (stdin/stdout JSON-RPC)          │
├─────────────────────────────────────────────────┤
│  AxionHelper (签名 macOS App)                     │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  MCP     │  │   AX     │  │  Screenshot   │  │
│  │  Server  │  │  Engine  │  │   Service     │  │
│  └──────────┘  └──────────┘  └───────────────┘  │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ Keyboard │  │  Mouse   │  │  App Launch   │  │
│  │  Service │  │ Service  │  │   Service     │  │
│  └──────────┘  └──────────┘  └───────────────┘  │
└─────────────────────────────────────────────────┘
```

### SDK vs 应用层边界

| 模块 | 归属 | 理由 |
|------|------|------|
| Agent 循环（turn 管理、tool_use 分发） | **SDK** | 通用 Agent 能力，所有 Agent 应用都需要 |
| MCP Client（连接、工具发现、调用） | **SDK** | 通用 MCP 协议实现，与具体工具无关 |
| 工具注册（ToolProtocol、defineTool） | **SDK** | 通用工具定义框架 |
| Hooks 系统（生命周期拦截） | **SDK** | 通用安全/策略框架 |
| 流式消息（AsyncStream<SDKMessage>） | **SDK** | 通用消息管道 |
| Session 管理（保存/恢复对话） | **SDK** | 通用会话持久化 |
| Planner（LLM 规划、prompt engineering） | **应用层** | 规划策略因应用而异，不属于通用 Agent 引擎 |
| Executor（步骤执行、占位符解析） | **应用层** | 执行策略因应用而异，OpenClick 的 batch 模式是一种特定策略 |
| Verifier（截图/AX 验证） | **应用层** | 验证逻辑与具体任务类型强相关 |
| AxionHelper（AX 操作、截图） | **应用层** | macOS 桌面操作是 Axion 特有的，不是通用 Agent 能力 |
| 配置管理（~/.axion/config.json） | **应用层** | 配置格式和存储方式因应用而异 |
| Trace 记录 | **应用层** | trace 格式因应用而异 |

### 参考项目本地路径

| 项目 | 本地路径 | 关系 |
|------|---------|------|
| OpenClick | `/Users/nick/CascadeProjects/openclick` | 竞品/参考实现（TypeScript + cua-driver），Helper App 签名配置、MCP 工具参数、Planner prompt 的主要参考来源 |
| OpenAgentSDK | `/Users/nick/CascadeProjects/open-agent-sdk-swift` | Axion 的核心依赖（SPM 本地包），Agent Loop、MCP Client、工具注册等能力的来源 |

**OpenClick 参考范围：** 架构文档中的「OpenClick 参考指南」部分按模块逐一映射了具体文件路径和提取内容，创建 Story 时应按该映射决定何时参考 OpenClick 源码。
