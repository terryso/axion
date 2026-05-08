---
stepsCompleted:
  - step-01-document-discovery
  - step-02-prd-analysis
  - step-03-epic-coverage-validation
  - step-04-ux-alignment
  - step-05-epic-quality-review
  - step-06-final-assessment
documentInventory:
  prd:
    - _bmad-output/planning-artifacts/prd.md
  architecture:
    - _bmad-output/planning-artifacts/architecture.md
  epics:
    - _bmad-output/planning-artifacts/epics.md
  ux: []
---

# Implementation Readiness Assessment Report

**Date:** 2026-05-08
**Project:** axion

## PRD Analysis

### Functional Requirements

| ID | 需求 |
|----|------|
| FR1 | 用户可以通过 Homebrew 一行命令安装 Axion（CLI + Helper 同时安装） |
| FR2 | 用户可以通过 `axion setup` 完成首次配置（API Key 输入、权限引导） |
| FR3 | 用户可以通过 `axion doctor` 检查系统环境、权限状态和依赖完整性 |
| FR4 | 用户可以通过配置文件（`~/.axion/config.json`）管理 API Key、模型选择和执行参数 |
| FR5 | 用户可以通过环境变量覆盖配置文件中的设置 |
| FR6 | 用户可以通过自然语言描述执行桌面自动化任务（`axion run "任务描述" --live`） |
| FR7 | 用户可以在干跑模式下预览执行计划而不实际操作桌面（`axion run "任务描述"` 无 `--live`） |
| FR8 | 用户可以限制任务的最大步数和最大批次（`--max-steps`、`--max-batches`） |
| FR9 | 用户可以随时通过 Ctrl-C 中断正在执行的任务 |
| FR10 | 用户可以在前台模式运行，允许使用全局光标和焦点操作（`--allow-foreground`） |
| FR11 | 系统可以根据任务描述和当前屏幕状态，通过 LLM 生成小批量工具调用序列（plan） |
| FR12 | 系统可以将截图和 AX tree 作为视觉上下文附加到规划请求中 |
| FR13 | 系统可以在执行失败或验证未通过时，携带失败上下文重新规划 |
| FR14 | 系统可以将规划结果解析为结构化的步骤序列（工具名、参数、目的、预期变化） |
| FR15 | 系统可以解析和修正 LLM 输出中的常见格式错误（markdown 围栏、前导文本等） |
| FR16 | 系统可以按顺序执行 planner 生成的步骤，通过 MCP 调用 AxionHelper |
| FR17 | 系统可以解析 `$pid` 和 `$window_id` 占位符，从已执行步骤的结果中填充后续步骤的参数 |
| FR18 | 系统可以在 AX 定位操作前自动刷新窗口状态，避免使用过期的元素索引 |
| FR19 | 系统可以处理步骤执行失败，记录失败位置和原因，触发重规划 |
| FR20 | 系统可以在共享座椅后台模式下阻止前台/全局操作，保障用户桌面可用性 |
| FR21 | 系统可以在每个批次执行完成后，通过截图和 AX tree 验证任务是否已完成 |
| FR22 | 系统可以根据 planner 定义的 `stopWhen` 条件判断任务完成状态 |
| FR23 | 系统可以区分任务完成（done）、被阻塞（blocked）和需要澄清（needs_clarification）状态 |
| FR24 | Helper 可以启动和列举 macOS 应用（launch_app、list_apps） |
| FR25 | Helper 可以列举和管理窗口（list_windows、get_window_state） |
| FR26 | Helper 可以执行鼠标操作（click、double_click、right_click、drag、scroll） |
| FR27 | Helper 可以执行键盘操作（type_text、press_key、hotkey） |
| FR28 | Helper 可以截取指定窗口的屏幕截图 |
| FR29 | Helper 可以获取窗口的 Accessibility tree（AX tree） |
| FR30 | Helper 可以在默认浏览器中打开 URL |
| FR31 | Helper 作为 MCP stdio server 运行，通过 stdin/stdout JSON-RPC 通信 |
| FR32 | Helper 在 CLI 启动时自动被拉起，CLI 退出时随之退出 |
| FR33 | 系统可以在终端实时显示每个步骤的执行状态（工具名、目的、结果） |
| FR34 | 系统可以显示任务完成的汇总信息（总步数、耗时、重规划次数） |
| FR35 | 系统可以结构化输出 JSON 格式的执行结果（`--json`） |
| FR36 | 系统使用 SDK 的 Agent 循环编排 planner/executor/verify 的完整工作流 |
| FR37 | 系统使用 SDK 的 MCP client 连接 AxionHelper 并调用工具 |
| FR38 | 系统使用 SDK 的工具注册机制注册 Helper 提供的桌面操作工具 |
| FR39 | 系统使用 SDK 的 Hooks 机制实现执行前的安全策略检查 |
| FR40 | 系统使用 SDK 的流式消息机制输出实时进度 |
| FR41 | 产出的 SDK 边界文档明确记录每个模块的归属（SDK / 应用层）和理由 |

**Total FRs: 41**

### Non-Functional Requirements

| ID | 需求 | 类别 |
|----|------|------|
| NFR1 | CLI 冷启动到首次 LLM 请求发出 < 2 秒（不含网络延迟） | 性能 |
| NFR2 | AxionHelper 启动到 MCP 连接就绪 < 500 毫秒 | 性能 |
| NFR3 | 单个 AX 操作（点击、输入）从 MCP 请求到结果返回 < 200 毫秒 | 性能 |
| NFR4 | CLI 进程常驻内存 < 30MB，Helper 进程常驻内存 < 20MB | 性能 |
| NFR5 | Helper 单次操作失败不导致 CLI 崩溃，错误通过 ToolResult 返回 | 可靠性 |
| NFR6 | LLM API 调用失败时自动重试（最多 3 次，指数退避） | 可靠性 |
| NFR7 | 规划结果解析失败时记录原始响应，不静默丢弃 | 可靠性 |
| NFR8 | 用户 Ctrl-C 中断时正确清理 Helper 进程，不留僵尸进程 | 可靠性 |
| NFR9 | API Key 不出现在日志、trace 或终端输出中 | 安全性 |
| NFR10 | 共享座椅模式下默认阻止前台操作（移动光标、抢焦点），防止干扰用户 | 安全性 |
| NFR11 | Helper 仅响应来自本地 CLI 的 MCP 请求，不监听网络端口 | 安全性 |
| NFR12 | 截图和 AX tree 数据仅用于当前任务，不在磁盘持久化（除非用户启用 trace） | 安全性 |
| NFR13 | `axion setup` 提供清晰的逐步引导，非技术用户可在 5 分钟内完成 | 可用性 |
| NFR14 | `axion doctor` 输出明确的修复建议，不只是报错 | 可用性 |
| NFR15 | 任务执行过程中终端输出实时更新，用户无需猜测进度 | 可用性 |
| NFR16 | 错误信息使用自然语言描述，不暴露内部异常堆栈 | 可用性 |
| NFR17 | CLI 代码与 SDK 通过 SPM 依赖解耦，SDK 更新只需修改版本号 | 可维护性 |
| NFR18 | Helper 工具集可独立扩展，新增工具无需修改 CLI 核心逻辑 | 可维护性 |
| NFR19 | Planner 的 system prompt 可独立修改，不硬编码在代码中 | 可维护性 |
| NFR20 | 每次运行生成 trace 文件（`~/.axion/runs/{runId}/trace.json`），用于调试和回溯 | 可维护性 |
| NFR21 | 支持 macOS 14（Sonoma）及以上版本 | 兼容性 |
| NFR22 | 不依赖 Xcode Command Line Tools 以外的系统级软件 | 兼容性 |
| NFR23 | 支持 Apple Silicon（arm64）和 Intel（x86_64） | 兼容性 |

**Total NFRs: 23**

### Additional Requirements

- **约束条件：** 1 人开发（Nick），SDK + 应用并行
- **参考项目：** OpenClick（竞品/参考实现）、OpenAgentSDK（核心依赖）
- **核心假设：** OpenAgentSDK 的公共 API 足以编排完整的桌面自动化 Agent，不需要绕过 SDK
- **MVP 核心场景：** Calculator、TextEdit、Finder、Chrome/Safari 基本导航

### PRD Completeness Assessment

PRD 质量较高，具备以下特点：
- 功能需求编号完整（FR1-FR41），覆盖安装配置、任务执行、规划引擎、本地执行、任务验证、Helper 操作、进度反馈、SDK 集成共 8 个领域
- 非功能需求编号完整（NFR1-NFR23），覆盖性能、可靠性、安全性、可用性、可维护性、兼容性共 6 个维度
- 有明确的成功标准和可衡量成果
- 有用户旅程支撑需求来源
- 有分阶段交付策略（MVP → 成长 → 愿景）
- 有技术架构概览和 SDK vs 应用层边界定义
- 有风险缓解策略

## Epic Coverage Validation

### Coverage Matrix

| FR | PRD 需求摘要 | Epic 覆盖 | Story 覆盖 | 状态 |
|----|------------|----------|-----------|------|
| FR1 | Homebrew 一行命令安装 | Epic 2 | Story 2.5 | ✓ Covered |
| FR2 | axion setup 首次配置 | Epic 2 | Story 2.3 | ✓ Covered |
| FR3 | axion doctor 环境检查 | Epic 2 | Story 2.4 | ✓ Covered |
| FR4 | 配置文件管理 | Epic 2 | Story 2.2 | ✓ Covered |
| FR5 | 环境变量覆盖 | Epic 2 | Story 2.2 | ✓ Covered |
| FR6 | 自然语言任务执行 | Epic 3 | Story 3.6 | ✓ Covered |
| FR7 | 干跑模式 | Epic 3 | Story 3.6 | ✓ Covered |
| FR8 | 步数/批次限制 | Epic 3 | Story 3.6 | ✓ Covered |
| FR9 | Ctrl-C 中断 | Epic 3 | Story 3.1 + 3.6 | ✓ Covered |
| FR10 | 前台模式 | Epic 3 | Story 3.3 + 3.6 | ✓ Covered |
| FR11 | LLM 规划引擎 | Epic 3 | Story 3.2 | ✓ Covered |
| FR12 | 视觉上下文附加 | Epic 3 | Story 3.2 | ✓ Covered |
| FR13 | 失败重规划 | Epic 3 | Story 3.4 + 3.6 | ✓ Covered |
| FR14 | 结构化步骤解析 | Epic 3 | Story 3.2 | ✓ Covered |
| FR15 | LLM 输出格式修正 | Epic 3 | Story 3.2 | ✓ Covered |
| FR16 | 步骤执行 | Epic 3 | Story 3.3 | ✓ Covered |
| FR17 | 占位符解析 | Epic 3 | Story 3.3 | ✓ Covered |
| FR18 | 窗口状态刷新 | Epic 3 | Story 3.3 | ✓ Covered |
| FR19 | 步骤失败处理 | Epic 3 | Story 3.3 | ✓ Covered |
| FR20 | 共享座椅安全策略 | Epic 3 | Story 3.3 | ✓ Covered |
| FR21 | 任务完成验证 | Epic 3 | Story 3.4 | ✓ Covered |
| FR22 | stopWhen 条件评估 | Epic 3 | Story 3.4 | ✓ Covered |
| FR23 | 任务状态区分 | Epic 3 | Story 3.4 | ✓ Covered |
| FR24 | 应用启动和列举 | Epic 1 | Story 1.3 | ✓ Covered |
| FR25 | 窗口管理 | Epic 1 | Story 1.3 | ✓ Covered |
| FR26 | 鼠标操作 | Epic 1 | Story 1.4 | ✓ Covered |
| FR27 | 键盘操作 | Epic 1 | Story 1.4 | ✓ Covered |
| FR28 | 屏幕截图 | Epic 1 | Story 1.5 | ✓ Covered |
| FR29 | AX tree 获取 | Epic 1 | Story 1.5 | ✓ Covered |
| FR30 | URL 打开 | Epic 1 | Story 1.5 | ✓ Covered |
| FR31 | MCP stdio server | Epic 1 | Story 1.2 | ✓ Covered |
| FR32 | Helper 自动启停 | Epic 1 | Story 1.6 + Story 3.1 | ✓ Covered |
| FR33 | 终端实时进度 | Epic 3 | Story 3.5 | ✓ Covered |
| FR34 | 任务汇总信息 | Epic 3 | Story 3.5 | ✓ Covered |
| FR35 | JSON 输出 | Epic 3 | Story 3.5 | ✓ Covered |
| FR36 | SDK Agent 循环编排 | Epic 3 | Story 3.7 | ✓ Covered |
| FR37 | SDK MCP client | Epic 3 | Story 3.7 | ✓ Covered |
| FR38 | SDK 工具注册 | Epic 3 | Story 3.7 | ✓ Covered |
| FR39 | SDK Hooks 安全检查 | Epic 3 | Story 3.7 | ✓ Covered |
| FR40 | SDK 流式消息 | Epic 3 | Story 3.7 | ✓ Covered |
| FR41 | SDK 边界文档 | Epic 3 | Story 3.8 | ✓ Covered |

### Missing Requirements

**无缺失的功能需求。** 所有 41 条 FR 都在 Epic 文档中有明确的覆盖映射和对应的 Story。

### Coverage Statistics

- Total PRD FRs: **41**
- FRs covered in epics: **41**
- Coverage percentage: **100%**

## UX Alignment Assessment

### UX Document Status

**未找到 UX 文档。** Epic 文档明确说明：「Axion 为 CLI + Helper 工具，终端输出为唯一用户界面。」

### UX 需求在 PRD 中的覆盖

Axion 无图形界面，UX 需求通过 PRD 中的 CLI 输出相关功能需求和可用性非功能需求充分定义：

| UX 相关需求 | 覆盖方式 |
|-----------|---------|
| 终端实时进度（FR33） | Story 3.5 详细定义了输出格式 |
| 任务汇总信息（FR34） | Story 3.5 定义了汇总格式 |
| JSON 输出（FR35） | Story 3.5 定义了结构化输出 |
| 安装引导体验（NFR13） | Story 2.3 定义了逐步引导流程 |
| 错误修复建议（NFR14） | Story 2.4 定义了 doctor 输出格式 |
| 实时进度更新（NFR15） | Story 3.5 确保实时更新 |
| 自然语言错误信息（NFR16） | 贯穿多个 Story |

### Architecture 对 UX 的支持

- 终端输出通过 TerminalOutput 和 JSONOutput 两个输出协议实现，架构支持灵活切换
- TraceRecorder 提供调试回溯能力
- SDK Streaming（AsyncStream<SDKMessage>）管道支持实时进度推送

### Warnings

⚠️ **低风险警告：** 虽然无需独立 UX 文档，但以下方面在 Story 实施时需关注：
- 终端输出的具体格式（颜色、对齐、进度条样式）在 Story 3.5 中未完全定义，建议实施时参考 PRD 用户旅程中的输出示例
- 错误信息的措辞和本地化（中英文）策略未在 PRD 或 Story 中明确

## Epic Quality Review

### Epic 结构验证

#### Epic 1: AxionHelper — macOS 桌面自动化引擎

- **用户价值：** ✅ 通过 — Helper 为用户提供 macOS 桌面操作能力，是核心产品功能
- **独立性：** ✅ 通过 — Helper 是独立 MCP server，可独立运行和测试
- **标题：** 🟡 偏技术化（"自动化引擎"），但描述中明确了用户价值
- **Stories：** 6 个，渐进式构建（脚手架 → MCP 基础 → 操作工具 → 集成打包）

#### Epic 2: CLI 安装配置与首次运行体验

- **用户价值：** ✅ 通过 — 用户可安装、配置和验证环境
- **独立性：** ✅ 通过 — CLI 配置不依赖 Epic 3
- **标题：** ✅ 用户导向 — "首次运行体验"
- **Stories：** 5 个，从 CLI 骨架到完整分发

#### Epic 3: 自然语言任务执行

- **用户价值：** ✅ 通过 — 核心产品能力：自然语言 → 桌面自动化
- **独立性：** ✅ 合理 — 依赖 Epic 1（Helper）和 Epic 2（CLI 入口），均为前序 Epic，无前向依赖
- **标题：** ✅ 用户导向
- **Stories：** 8 个，从 MCP 连接到端到端验证

### 依赖分析

#### Epic 间依赖（✅ 无违规）

```
Epic 1 (Helper) ← 独立
Epic 2 (Config) ← 独立
Epic 3 (Execute) ← 依赖 Epic 1 + Epic 2（均为前序）
```

无前向依赖，无循环依赖。

#### Epic 内依赖（✅ 无违规）

**Epic 1:** 1.1 → 1.2 → {1.3, 1.4, 1.5} → 1.6（清晰的线性/扇出依赖）
**Epic 2:** 2.1 → 2.2 → {2.3, 2.4}，2.5 依赖全部（合理的集成顺序）
**Epic 3:** 3.1 → 3.2 → 3.3 → 3.4 → 3.6 → 3.7 → 3.8，3.5 与 3.3-3.4 并行（清晰）

### Story 质量评估

#### 验收标准质量

| Story | Given/When/Then | 可测试 | 完整性 | 评价 |
|-------|----------------|--------|--------|------|
| 1.1 | ✅ | ✅ | ✅ | 6 组 AC，覆盖核心模型 |
| 1.2 | ✅ | ✅ | ✅ | 4 组 AC，覆盖 MCP 基础交互 |
| 1.3 | ✅ | ✅ | ✅ | 5 组 AC，含错误场景 |
| 1.4 | ✅ | ✅ | ✅ | 6 组 AC，覆盖所有操作类型 |
| 1.5 | ✅ | ✅ | ✅ | 5 组 AC，含边界条件（截断） |
| 1.6 | ✅ | ✅ | ✅ | 4 组 AC，集成验证 + NFR |
| 2.1 | ✅ | ✅ | ✅ | 3 组 AC，基础 CLI |
| 2.2 | ✅ | ✅ | ✅ | 5 组 AC，覆盖分层覆盖优先级 |
| 2.3 | ✅ | ✅ | ✅ | 5 组 AC，完整 setup 流程 |
| 2.4 | ✅ | ✅ | ✅ | 5 组 AC，含修复建议 |
| 2.5 | ✅ | ✅ | ✅ | 5 组 AC，覆盖签名和分发 |
| 3.1 | ✅ | ✅ | ✅ | 6 组 AC，含崩溃恢复 |
| 3.2 | ✅ | ✅ | ✅ | 6 组 AC，含重试和错误处理 |
| 3.3 | ✅ | ✅ | ✅ | 6 组 AC，含安全策略 |
| 3.4 | ✅ | ✅ | ✅ | 3 组 AC，覆盖三种状态 |
| 3.5 | ✅ | ✅ | ✅ | 6 组 AC，覆盖终端和 JSON |
| 3.6 | ✅ | ✅ | ✅ | 6 组 AC，覆盖所有状态转换 |
| 3.7 | ✅ | ✅ | ✅ | 5 组 AC，验证 SDK 集成点 |
| 3.8 | ✅ | ✅ | ✅ | 4 组 AC + 4 个端到端场景 |

### 质量问题

#### 🟠 Major Issues

**1. Story 1.1 是"大爆炸"模型创建故事**
- Story 1.1 一次性创建所有共享模型（Plan、Step、RunState、AxionConfig、AxionError + 5 个 Protocol）
- 最佳实践建议：每个 Story 应按需创建模型，而非预先创建全部
- **缓解因素：** SPM 项目结构要求编译目标存在，且这些模型被几乎所有后续 Story 使用。对于编译型语言项目，提前定义核心类型是务实的做法
- **建议：** 可接受现状，但需确保模型定义准确——因为后续所有 Story 依赖这些模型，错误会级联传播

#### 🟡 Minor Concerns

**1. Epic 1 标题偏技术化**
- "macOS 桌面自动化引擎"更偏技术描述
- 建议：可改为 "AxionHelper — 桌面操作能力" 以更突出用户价值

**2. Story 3.6 粒度较大**
- Run Engine 状态机是整个系统的集成点，涵盖 6 组 AC
- 虽然功能内聚，但实现工作量可能较大
- 建议：可考虑拆分为"状态机核心"和"边界条件处理"，但当前内聚性尚可

**3. 终端输出格式定义粒度**
- Story 3.5 定义了输出内容，但颜色、对齐等视觉细节未指定
- 建议：实施时参考 PRD 用户旅程中的输出示例作为标准

### 最佳实践合规检查清单

| 检查项 | Epic 1 | Epic 2 | Epic 3 |
|--------|--------|--------|--------|
| Epic 交付用户价值 | ✅ | ✅ | ✅ |
| Epic 可独立运作 | ✅ | ✅ | ✅ (依赖 E1+E2) |
| Story 粒度合理 | 🟠 1.1 偏大 | ✅ | 🟡 3.6 偏大 |
| 无前向依赖 | ✅ | ✅ | ✅ |
| 模型按需创建 | 🟠 1.1 预建 | N/A | ✅ |
| 验收标准清晰 | ✅ | ✅ | ✅ |
| FR 可追溯性 | ✅ | ✅ | ✅ |

## Summary and Recommendations

### Overall Readiness Status

**✅ READY — 有条件就绪**

Axion 的规划文档整体质量较高，可以进入实施阶段。PRD 需求完整（41 FR + 23 NFR），Epic 覆盖率 100%，架构决策清晰，Story 验收标准具体且可测试。发现的问题均为非阻塞性，可在实施过程中消化。

### Critical Issues Requiring Immediate Action

**无阻塞性问题。** 以下问题建议在实施前了解，但不阻止开发启动：

1. **🟠 Story 1.1 模型预建风险** — 所有共享模型在第一个 Story 中一次性创建。如果模型定义不准确，错误会级联到后续所有 Story。建议在开始 Epic 1 之前，仔细审查架构文档中的数据模型定义，确保 Plan、Step、RunState、AxionConfig 等核心类型的字段设计到位。

### Recommended Next Steps

1. **开始实施 Epic 1** — 从 Story 1.1（SPM 脚手架）开始，实施时特别注意核心模型的准确性，参考架构文档中的数据模型定义
2. **实施过程中参考 PRD 用户旅程** — Story 3.5（输出/进度显示）的终端输出格式以 PRD 旅程一中的输出示例为准
3. **记录 SDK 边界发现** — 在实施 Epic 3 过程中持续更新 SDK 边界文档（Story 3.8），不要等到最后才写
4. **终端输出中英文策略** — 确定错误信息和进度输出是使用中文、英文还是跟随系统语言，并在实施中保持一致

### Assessment Summary

| 评估维度 | 状态 | 详情 |
|---------|------|------|
| PRD 完整性 | ✅ 通过 | 41 FR + 23 NFR，8 个需求领域 + 6 个 NFR 维度 |
| Epic FR 覆盖率 | ✅ 100% | 41/41 FR 全部映射到 Epic 和 Story |
| UX 对齐 | ✅ 通过 | CLI 工具无需独立 UX 文档，PRD 可用性需求充分 |
| Epic 结构 | ✅ 通过 | 3 个 Epic，用户价值导向，无前向依赖 |
| Story 质量 | ✅ 通过 | 19 个 Story，全部使用 Given/When/Then，AC 具体 |
| 依赖关系 | ✅ 通过 | 所有依赖均为前序依赖，无循环 |
| 阻塞性问题 | ✅ 无 | 0 个 Critical，1 个 Major，3 个 Minor |

### Final Note

本次评估共发现 **4 个问题**（0 Critical / 1 Major / 3 Minor），分布在 3 个类别中。无阻塞性问题，建议在实施 Epic 1 前注意 Story 1.1 的模型定义准确性。可以直接进入实施阶段。

---
**评估人：** Implementation Readiness Checker
**评估日期：** 2026-05-08
**报告路径：** `_bmad-output/planning-artifacts/implementation-readiness-report-2026-05-08.md`
