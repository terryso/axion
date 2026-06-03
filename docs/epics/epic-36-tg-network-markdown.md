---
project_name: 'axion'
user_name: 'Nick'
date: '2026-06-03'
status: 'draft'
epic: 36
title: 'TG 网络容错与 Markdown 增强（可选，P3）'
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-tg-enhancement-hermes-parity/prd.md
  - docs/epics/epic-32-telegram-experience-upgrades.md
---

# Epic 36: TG 网络容错与 Markdown 增强（可选，P3）

提升 TG 生产环境的网络稳定性和 Markdown 渲染精度。当前网络层和渲染已够用，本 Epic 视实际生产环境反馈决定是否推进。

**FRs covered:** 无独立 FR — 属于增强/打磨
**NFRs:** 网络可靠性、渲染精度
**依赖:** 无

**优先级：** P3，可延后。

---

### Story 36.1: 网络重连增强

As a Axion Gateway 运维者,
I want TG 网络中断时自动恢复，而不是崩溃或停止响应,
So that gateway 在不稳定网络环境下保持可用。

**Acceptance Criteria:**

**Given** TG API 请求超时或连接被重置
**When** `TGAPIClient` 检测到 transient 错误
**Then** 自动重试（最多 3 次，指数退避：1s, 2s, 4s）
**And** 重试成功后无缝继续，用户无感知

**Given** TG API 返回 429 Too Many Requests
**When** `TGAPIClient` 检测到限流
**Then** 读取 `Retry-After` header
**And** 等待指定时间后重试
**And** 无 `Retry-After` 则默认等待 5 秒

**Given** TG API 返回 401/403（认证失败）
**When** `TGAPIClient` 检测到 permanent 错误
**Then** 不重试，记录错误日志
**And** 通知用户 "TG Bot 认证失败，请检查 token 配置"

**Given** 多个 gateway 实例同时轮询同一 bot
**When** TG API 返回 409 Conflict
**Then** 检测到 polling conflict
**And** graceful degrade：停止当前轮询，等待 30 秒后重试
**And** 连续 3 次 conflict 后停止轮询并通知用户

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift` | 增强 `performRequest()` 的错误分类和重试逻辑；新增 conflict 检测 |
| `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` | `pollLoop()` 增加 conflict 降级逻辑 |

---

### Story 36.2: MarkdownV2 格式化管线对齐 Hermes

As a Axion Telegram 用户,
I want agent 回复中的所有富文本格式（斜体、删除线、剧透、表格）在 TG 中正确渲染,
So that 我看到的是格式完整的回复，不会因为格式缺失而丢失信息。

**当前差距（对比 Hermes 12 步管线）：**

| 能力 | Hermes | Axion 现状 |
|------|--------|-----------|
| 代码块 placeholder 保护 | 先替换 placeholder，处理后恢复 | 直接处理，无 placeholder |
| Italic `*text*` / `_text_` | ✅ | ❌ 缺失 |
| Strikethrough `~~text~~` | ✅ | ❌ 缺失 |
| Spoiler `\|\|text\|\|` | ✅ | ❌ 缺失 |
| 表格等宽对齐渲染 | `_wrap_markdown_tables` 列宽对齐 | 仅 key/value 降级 |
| 安全网兜底 | 最终 try/catch 回退纯文本 | 无 |

**Acceptance Criteria:**

**Given** agent 回复包含斜体格式 `*text*` 或 `_text_`
**When** `TGMessageFormatter` 渲染 MarkdownV2
**Then** 斜体正确转换为 TG MarkdownV2 的 `_text_` 语法
**And** 不与 bold `**text**` 冲突（先处理 bold 再处理 italic）

**Given** agent 回复包含删除线格式 `~~text~~`
**When** `TGMessageFormatter` 渲染 MarkdownV2
**Then** 删除线正确转换为 TG MarkdownV2 的 `~text~` 语法

**Given** agent 回复包含剧透格式 `||text||`
**When** `TGMessageFormatter` 渲染 MarkdownV2
**Then** 剧透正确转换为 TG MarkdownV2 的 `\|\|text\|\|` 语法

**Given** agent 回复包含 GFM 表格（`| col1 | col2 |` 格式，3 列以上）
**When** `TGMessageFormatter` 格式化文本
**Then** 检测表格结构（连续的 `|` 分隔行）
**And** 将表格转换为等宽文本（`<pre>` 格式），列宽对齐
**And** 2 列表格继续使用现有 key/value 降级

**Given** 表格列数超过 4 列或列内容很长
**When** 等宽文本超过 4096 字符
**Then** 只显示前 N 行 + "... (共 M 行)"
**And** 提示 "表格已截断"

**Given** 代码块内容包含会被错误转义的特殊字符
**When** `TGMessageFormatter` 处理代码块
**Then** 先将代码块替换为 placeholder（如 `\x00CODEBLOCK_0\x00`）
**And** 处理完所有 inline 格式后恢复 placeholder
**And** 代码块内容不做任何转义

**Given** `renderMarkdownV2` 处理过程中发生异常或产出无效 MarkdownV2
**When** TG API 拒绝格式（返回 parse error）
**Then** 安全网兜底：回退到 `renderPlain()` 纯文本输出
**And** 用户仍能收到完整内容，只是无格式

**Given** HTML fallback 路径
**When** MarkdownV2 失败后降级到 HTML
**Then** HTML 渲染也支持新增的 italic/strikethrough/spoiler
**And** 使用 `<i>`、`<s>`、`<span class="tg-spoiler">` 对应标签

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Services/Telegram/TGMessageFormatter.swift` | 重构为 placeholder 保护模式；`renderInlineMarkdownV2` 新增 italic/strikethrough/spoiler 处理；表格渲染增强为等宽对齐；新增安全网 `safeFormat()` 方法；`renderInlineHTML` 同步新增对应标签 |

---

### Story 36.3: /reasoning 和 /verbose 命令

As a Axion Telegram 用户,
I want 控制推理力度和工具进度显示,
So that 我能根据任务复杂度调整 agent 行为。

**前置依赖：** RunOverrides 扩展（新增 `effortOverride` 字段），见 Epic 34 基础设施前置说明。

**SDK 能力：** `AgentOptions.effort: EffortLevel?` 支持 .low/.medium/.high/.max。`ThinkingConfig` 支持 .adaptive/.enabled(budgetTokens:)/.disabled。

**Acceptance Criteria:**

**Given** 用户发送 `/reasoning high`
**When** 当前模型支持推理力度控制
**Then** 设置推理力度为 high
**And** 回复 "推理力度: high（深度思考）"

**Given** 用户发送 `/reasoning` 不带参数
**When** 查询当前推理力度
**Then** 回复当前推理力度设置
**And** 提示可用级别：low/medium/high

**Given** 用户发送 `/verbose`
**When** 当前工具进度显示为开启
**Then** 切换为关闭
**And** 回复 "工具进度: ❌ 隐藏"

**Given** 用户再次发送 `/verbose`
**When** 当前工具进度显示为关闭
**Then** 切换为开启
**And** 回复 "工具进度: ✅ 显示"

**实现参考：**

| 文件 | 变更 |
|------|------|
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | 注册 `/reasoning` 和 `/verbose` 命令 |
| `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` | 新增 `setReasoning(chatId:level:)`、`toggleVerbose(chatId:)` 方法 |
