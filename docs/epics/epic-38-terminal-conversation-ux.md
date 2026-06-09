# Axion Epic 38: 终端对话体验增强

> **状态：提议中**
> **优先级：P1**
> **前置依赖：** Epic 37（交互聊天模式基础能力）✅ **已完成**，feat/interactive-chat 分支已全部落地
> **对标参考：** Codex CLI TUI / Composer 交互体验（仅迁移对 Axion coding agent 真正有价值的部分）
> **分析基准：** codex-rs/tui/src（331 个 Rust 源文件，2026-06-07 深度代码分析）

### Epic 37 → 38 的关系

Epic 37 已全部完成，Axion chat 已具备：系统提示 + CLAUDE.md 加载、slash 命令（help/clear/compact/model/cost/resume/config/exit）、Ctrl+C 中断、启动横幅、工具输出优化、权限审批（y/n）、多行输入 + bracket paste、上下文管理 + 自动 compact、会话恢复、中文输入修复。

Epic 38 是在 Epic 37 之上的**交互层增强**，不是重新实现。具体演进关系：

| Epic 37 已有 | Epic 38 演进 |
|---|---|
| `SlashCommand` 枚举 + `parse()` + 路由 | 38.2 增加命令发现层（列表、过滤、补全、特性门控） |
| `ChatOutputFormatter`（⏳/✅/❌ + spinner + Markdown） | 38.1 在外层包 `TranscriptRenderer` 做角色装饰（圆点 + 缩进 + 统一样式） |
| `PermissionHandler`（y/n 确认 + 三种模式） | 38.3 扩展选项粒度（once/session/prefix）+ `SessionAllowList` |
| `MultiLineInputReader`（bracket paste + 续行） | 38.0 **替换**为 `ChatComposer`（raw mode + 多交互模式），保留 multiline/paste |
| `SessionResumeManager`（/resume 列表恢复） | 38.7 扩展为 new/fork/archive + 会话状态增强 |

## 背景与目标

Epic 37 解决的是 **"Axion 变成一个可用的交互式 coding agent"**：进入 chat、流式输出、权限确认、slash 命令、多行输入、上下文管理、会话恢复。这些能力让 Axion 从单次 `run` 进化到多轮对话，但整体仍然更像一个"增强版 REPL"，还不是一个真正**顺手、可扫读、可控、可连续工作**的终端 coding agent。

本 Epic 的目标不是增加新的 agent 核心能力，而是把 **已有能力做成更高质量的交互层**：

1. **更好读**：用户消息、AI 回复、工具动作、审批请求一眼区分
2. **更好输**：减少"必须整句输入完再提交"的摩擦，补齐历史、排队、搜索、外部编辑
3. **更好控**：slash 命令、审批、会话切换、旁路探索都更易发现、更低心智负担
4. **更连续**：长会话、忙时补充、临时分叉、恢复上下文都更自然

---

## 设计原则

### 1. 保持 Axion 的终端 REPL 形态，不在本 Epic 重写为全屏 TUI

Codex 的很多交互来自全屏 TUI（ratatui + crossterm），但 Axion 当前的产品形态是 line-oriented chat REPL。本 Epic 只引入 **对 REPL 友好的增强**：语义化输出、轻量 popup / picker、键盘交互增强、局部 raw mode 输入控制。

**不做：**
- 不把 `ChatCommand` 改造成 ratatui 全屏应用
- 不引入 pets / theme picker / realtime voice / apps / plugins 等与 coding agent 主路径弱相关能力

### 2. 先建立"语义化交互层"，再补高级体验

彩色圆点、消息块、审批样式、状态行、命令面板都应共享一套视觉语义，而不是 story 各自输出一套格式。

### 3. 键盘优先，但必须优雅降级

TTY 环境下可用快捷键、popup、raw-input；非 TTY / pipe 模式下保留现有简单行为，不影响脚本化使用。

### 4. 只迁移对 Axion 真正有价值的 Codex 体验

只吸收这些维度：
- command discoverability
- approval ergonomics
- composer efficiency
- queued input
- session workflow
- side conversation
- workspace context shortcuts
- transcript readability

---

## Codex 架构模式总结（跨 Story 复用）

> 以下是从 Codex 331 个 Rust 源文件中提炼的**跨模块架构模式**，每个 Story 实现时都应参考。

### CM-1: 事件驱动解耦

Codex 的核心架构是 `AppEvent` 枚举驱动的事件循环。所有交互（命令分发、审批响应、文件搜索结果）都通过事件通道传递，UI 层和业务层完全解耦。

**Axion 适配：** Axion 已有 `EventBus`（SDK 提供），Epic 38 的交互增强应继续通过 EventBus 发送/接收事件，而不是在 `ChatCommand` 主循环中直接调用。

**Codex 参考：** `app_event.rs` — `AppEvent` 枚举（100+ 变体），`app_event_sender.rs` — 类型安全的发送接口

### CM-2: 状态机驱动交互

Codex 中每个交互模式都是一个显式状态机：
- 历史搜索：`Idle → Searching → Match → NoMatch`
- 审批 overlay：排队 → 激活 → 已处理
- @ 提及：`Results → FilesystemOnly → Tools`（左右切换）
- 终端重排：`observed_width` vs `reflow_width` 分离 + 75ms 防抖

**Axion 适配：** 每个 Story 应定义清晰的 Swift enum 状态机（如 `HistorySearchStatus`），而不是散落的 Bool 标志。

### CM-3: 终端颜色自适应

Codex 通过三层颜色适配确保在各种终端中可读：

1. **启动探测**：发送 OSC 10/11 查询终端前景/背景色
2. **亮度判断**：ITU-R BT.601 公式 `Y = 0.299R + 0.587G + 0.114B`，阈值 128
3. **颜色降级链**：TrueColor → Ansi256（perceptual_distance 最近色） → Ansi16（dim 回退）

**Axion 适配：** Axion 当前 `ChatOutputFormatter` 直接硬编码 ANSI 色码。Epic 38 应引入 `TerminalColorProfile` 枚举，启动时探测并缓存，所有视觉输出都通过它适配。

**Codex 参考：** `color.rs`（blend/is_light/perceptual_distance）、`terminal_palette.rs`（颜色降级链）

### CM-4: 草稿快照与恢复

Codex 的 `ComposerDraft` 支持完整快照和原子恢复：

```rust
struct ComposerDraft {
    text: String,                    // 文本内容
    cursor: usize,                   // 光标位置
    text_elements: Vec<TextElement>, // 结构化元素（如 @mention 占位符）
    local_image_paths: Vec<PathBuf>, // 图片
    mention_bindings: Vec<MentionBinding>, // @ 绑定
    pending_pastes: Vec<(String, String)>, // 粘贴缓冲
}
```

任何可能中断编辑的操作（历史搜索、外部编辑器）都先 `snapshot_draft()`，取消时 `restore_draft()`。

**Axion 适配：** `ChatComposer`（Story 38.0）应内置 `ComposerDraft` 结构，支持保存/恢复完整编辑状态。

**Codex 参考：** `bottom_pane/chat_composer/draft_state.rs`

### CM-5: 特性门控

Codex 的 `BuiltinCommandFlags` 通过一组 Bool 标志控制哪些命令在当前上下文中可见：

```rust
struct BuiltinCommandFlags {
    collaboration_modes_enabled: bool,  // 控制 /plan
    connectors_enabled: bool,           // 控制 /apps
    side_conversation_active: bool,     // 限制 side 可用命令
    // ... 10+ 标志
}
```

**Axion 适配：** Axion 的 `SlashCommand` 注册系统应根据当前状态（是否在 side 会话、任务是否运行中、权限模式）动态过滤可用命令。

**Codex 参考：** `bottom_pane/slash_commands.rs` — `builtins_for_input()` + `BuiltinCommandFlags`

---

## Axion 当前基础（Epic 37 已有）

当前 Axion chat 已具备以下交互基础，可作为 Epic 38 的依托：

- 启动横幅 + context prompt：`BannerRenderer.swift`
- 工具调用 / spinner / Markdown 渲染：`ChatOutputFormatter.swift`、`SpinnerRenderer.swift`、`MarkdownTerminalRenderer.swift`
- slash 命令基础：`SlashCommand.swift`、`SlashCommandHandler.swift`
- 权限模式基础：`PermissionHandler.swift`
- 多行输入 / bracket paste：`MultiLineInputReader.swift`
- 会话恢复基础：`SessionResumeManager.swift`

**当前仍缺失：**

- 用户 / AI / Tool / Approval 的统一视觉层
- slash 命令发现性（只能靠记忆）
- 审批粒度（当前接近 yes/no）
- 输入历史搜索、外部编辑、忙时排队编辑
- `@file` / `/diff` / richer `/status`
- `/new`、`/fork`、`/archive`、`/side`

---

## Codex 交互体验深度盘点（本 Epic 的输入）

### 1. Slash 命令系统

| 维度 | Codex 实现 | Axion 吸收要点 |
|------|-----------|---------------|
| 命令定义 | `SlashCommand` 枚举 48 变体 + strum 宏驱动 `EnumString`/`EnumIter` | Axion 用 Swift `enum SlashCommand` + `CaseIterable`，每个 case 携带 `description`/`aliases`/`acceptsArgs`/`availableDuringTask`/`availableInSide` 元数据 |
| 命令过滤 | `CommandPopup` 大小写不敏感前缀匹配，精确匹配优先排列 | REPL 模式下列表式输出 + 高亮匹配字符 |
| 特性门控 | `BuiltinCommandFlags` 10+ 标志，side 会话只暴露 6 个命令 | Axion 按当前状态动态过滤 |
| 命令路由 | `dispatch_command()` match 分发 → `AppEvent` 异步解耦 | 通过 EventBus 路由到 ChatCommand 主循环 |
| 别名机制 | strum `serialize` 属性：btw→side, quit→exit, clean→stop | Swift 无原生支持，用 static var aliases: [String] 手动映射 |
| 行内参数 | `/side <question>`、`/resume <id>` — 参数区可继续编辑 | SlashCommand.acceptsArgs 标记，解析时分离命令名和参数 |

**Codex 关键文件：** `slash_command.rs`（枚举定义）、`bottom_pane/slash_commands.rs`（过滤）、`bottom_pane/command_popup.rs`（UI）、`bottom_pane/chat_composer/slash_input.rs`（输入解析）、`chatwidget/slash_dispatch.rs`（路由）

### 2. 审批 Overlay

| 维度 | Codex 实现 | Axion 吸收要点 |
|------|-----------|---------------|
| 粒度层级 | Exec: once / session / prefix / network-policy; Patch: once / session; Permissions: turn / turn+strict / session | Axion 至少支持：once / session / prefix（命令前缀匹配）|
| 动态选项 | 后端通过 `available_decisions` 字段告诉 TUI 展示哪些选项 | Axion 的 `PermissionHandler` 应根据操作类型动态生成选项列表 |
| 审批排队 | `enqueue_request` → `advance_queue`，支持多请求排队 | Axion 的 REPL 模式下一次只处理一个审批，但应支持排队 |
| 全屏详情 | Ctrl+Shift+A 触发全屏查看 diff / 长命令 | REPL 模式下可用 `less`/`bat` pager 展示详情 |
| 快捷键 | y=once, a=session, p=prefix, d=deny, Esc=cancel | Axion 复用类似快捷键映射 |
| 安全设计 | MCP Elicitation 中 Esc **永远**映射为 cancel，即使用户自定义了 keymap | Axion 审批中 Esc 同样硬编码为安全退出 |
| 跨线程 | `thread_label` 标记来自其他 agent 线程的请求 | Axion 暂无多 agent 线程，预留字段即可 |

**Codex 关键文件：** `bottom_pane/approval_overlay.rs`（~1900 行）、`protocol/src/request_permissions.rs`（`PermissionGrantScope: Turn/Session`）

### 3. Composer 效率

| 维度 | Codex 实现 | Axion 吸收要点 |
|------|-----------|---------------|
| 历史搜索状态机 | `HistorySearchStatus`: Idle → Searching → Match → NoMatch | Axion `HistorySearchSession` 模仿此状态机 |
| 统一偏移空间 | `[0, persistent_count)` = 持久化历史（异步），`[persistent_count, total)` = 本地历史（同步） | Axion 用 `SessionStore` + 文件持久化 |
| 搜索算法 | 大小写不敏感子串匹配 + `HashSet<String>` 去重 | 直接复用，无需模糊匹配 |
| Ctrl+R 流程 | 触发 → 快照草稿 → footer 切换搜索模式 → 逐条匹配 → Enter 采纳 / Esc 恢复 | Axion 在 composer 中实现相同流程 |
| 外部编辑器 | `$VISUAL` → `$EDITOR` → 报错；`.md` 临时文件 → 编辑 → 回填 | Axion 直接复用此模式 |
| 草稿快照 | `ComposerDraft` 包含 text/cursor/elements/mentions/pastes | Axion `ComposerDraft` struct |

**Codex 关键文件：** `bottom_pane/chat_composer/history_search.rs`（`HistorySearchSession`）、`bottom_pane/chat_composer/draft_state.rs`（`ComposerDraft`）、`external_editor.rs`（编辑器集成）、`insert_history.rs`（历史回填）

### 4. 输入排队

| 维度 | Codex 实现 | Axion 吸收要点 |
|------|-----------|---------------|
| 队列结构 | `VecDeque<QueuedUserMessage>` 无固定容量限制，FIFO | Axion 用 `[UserMessage]` 数组即可 |
| 消息类型 | `QueuedInputAction`: Plain / ParseSlash / RunShell | Axion 简化为 Plain / ParseSlash |
| 入队条件 | 会话未配置完成 或 当前有 turn 在运行 | Axion 判断 `isAgentBusy` 标志 |
| 消费机制 | turn 结束后自动弹出队列头部，slash 命令可能触发 `QueueDrain::Stop` | Axion 在 EventBus 收到 turn 完成事件时消费 |
| 预览 UI | `preview()` 返回 `PendingInputPreview`（排队/steer/rejected 三类） | Axion 在 prompt 行下方显示排队消息预览 |
| 编辑排队 | 弹出最近一条排队消息恢复到 composer | 支持快捷键回退编辑 |

**Codex 关键文件：** `chatwidget/input_queue.rs`（`InputQueueState`）、`chatwidget/user_messages.rs`（类型定义）

### 5. 会话管理

| 维度 | Codex 实现 | Axion 吸收要点 |
|------|-----------|---------------|
| Fork | 调用 `app_server.fork_thread()` 继承 model/reasoning/cwd，创建新线程 | Axion 用 `SessionStore` 复制当前会话历史到新 session |
| Archive | `archived: Some(false)` 过滤归档会话，不出现在 resume 列表 | Axion 的 `SessionResumeManager` 增加 `archived` 标志 |
| New | 发送 `NewSession` 事件，当前会话保留可恢复 | Axion 直接创建新 session |
| Resume Picker | 全屏 TUI 分页列表 + 搜索 + 预览 + 排序 | Axion 用简单的编号列表 + 筛选（非全屏） |
| Session State | `ThreadSessionState` 含 thread_id/forked_from_id/model/cwd/approval_policy 等 | Axion 已有类似结构，需增加 `archived`/`forkParentId` |

**Codex 关键文件：** `session_state.rs`（`ThreadSessionState`）、`session_resume.rs`（恢复逻辑）、`resume_picker.rs`（~6300 行，全屏选择器）

### 6. Side Conversation

| 维度 | Codex 实现 | Axion 吸收要点 |
|------|-----------|---------------|
| 生命周期 | 创建临时 fork → 执行 → 自动返回 → 销毁 | Axion 临时创建子 session |
| 边界提示词 | `SIDE_BOUNDARY_PROMPT` 隐藏 user 消息：标记边界、禁止继续继承历史的指令、仅允许非变更探索 | Axion 直接复用此设计，注入隐藏消息 |
| 约束 | 同时只允许一个 side；主线程必须已开始对话；side 不可重命名 | Axion 相同约束 |
| 命令限制 | side 中只有 Copy/Raw/Diff/Mention/Status/Ide 可用 | Axion 限制为 /copy /diff /status /mention |
| 父线程状态追踪 | `SideParentStatus`: NeedsInput / NeedsApproval / Failed / ... | Axion 简化为主线程"等待中"状态提示 |
| 自动返回 | side 完成且无 overlay/popup/composer 内容时自动切回 | Axion 在 side turn 结束后提示返回 |

**Codex 关键文件：** `app/side.rs`（`SideThreadState` + `SIDE_BOUNDARY_PROMPT`）

### 7. 工作区上下文与视觉

| 维度 | Codex 实现 | Axion 吸收要点 |
|------|-----------|---------------|
| @ 文件搜索 | `FileSearchManager` 异步搜索 + session_token 防过期覆盖 | Axion 用 `FileManager.enumerator` 同步搜索（repo 足够小） |
| @ 提及系统 | Skills + Plugins + Files + Directories 混合候选，三种搜索模式切换 | Axion 简化为 Files + Directories |
| 角色视觉 | User: 微妙背景色（12% dark / 4% light）+ `› ` 前缀；AI: `• ` 前缀 + dim | Axion 用彩色圆点 + 前缀（见 Story 38.1）|
| 颜色自适应 | ITU-R BT.601 亮度 + TrueColor/256/16 降级链 | Axion 需实现终端颜色探测和降级 |
| Transcript 重排 | 75ms 防抖 + 流式期间标记 + 流结束修复 | Axion REPL 模式下无需重排（行式输出） |
| 状态指示器 | Spinner + shimmer + 耗时 + 快捷键提示 + 最多 3 行详情 | Axion 复用现有 SpinnerRenderer 增强 |
| 文本格式化 | JSON 紧凑化 + grapheme 截断 + 路径中心截断 | Axion 复用工具输出格式化 |

**Codex 关键文件：** `file_search.rs`、`bottom_pane/mentions_v2/`（8 文件）、`style.rs`、`color.rs`、`terminal_palette.rs`、`status_indicator_widget.rs`、`transcript_reflow.rs`

---

## Epic 范围

本 Epic 聚焦 **终端 conversation UX**，不新增底层 agent 能力：

### In Scope

- 消息角色视觉语义（包括**左侧不同颜色实心圆点**）
- 输入器升级（从 `readLine` 型输入迈向可处理 key event 的轻量 composer）
- slash 命令面板与命令补全
- 审批交互升级
- 历史、外部编辑、忙时排队
- 工作区快捷上下文和会话流转
- side conversation

### Out of Scope

- 语音、图片、宠物、主题商店、插件市场
- IDE 集成上下文
- 多 agent 线程切换器
- 全屏 TUI 重写
- 终端 resize 重排（REPL 模式下不需要）
- Apps / Plugins / Rollout / Feedback / Personality / Realtime（Codex 有但 Axion 不搬）

---

## Story 依赖关系

```text
38.0 轻量 Composer 输入基础
  ├──► 38.2 Slash 命令面板与补全
  ├──► 38.3 审批中心 v2
  ├──► 38.4 Composer 效率增强
  ├──► 38.5 Busy-turn 输入排队
  ├──► 38.6 工作区快捷上下文
  └──► 38.7 会话工作流

38.1 对话视觉语义层 ── 独立，可尽早交付

38.8 Side Conversation ── ⚠️ 建议延后至 Epic 39
```

**建议实施顺序：** 38.1 → 38.0 → 38.2 → 38.3 → 38.4 → 38.5 → 38.6 → 38.7

> 注：38.8（Side Conversation）因架构复杂度高，建议延后到 Epic 39 单独实施，不阻塞 Epic 38 的交付。

---

## Stories

### Story 38.0: 轻量 Composer 输入基础

As a Axion CLI 用户,
I want chat 输入从 `readLine()` 升级为可处理 key event 的轻量 composer,
So that slash popup、历史搜索、快捷键、排队编辑等能力有统一承载层。

**为什么先做：** Epic 37 的 `MultiLineInputReader` 基于 `readLine()` 行读取模型，解决了 multiline / bracket paste 问题，但不适合命令 popup、历史搜索、快捷键式交互。后续所有 Story（38.2–38.7）都需要 key event 级别的输入控制。继续在 `readLine()` 之上叠功能会让后续 story 越来越脆弱。

> ⚠️ **前置 Spike（建议 1-2 天）：** 本 Story 开始前，先验证 raw mode 在 Swift 6.1 + macOS 上的可行性：
> - `termios` 设置 raw mode 后能否正确捕获 Up/Down/Ctrl+R/Ctrl+G 等按键序列
> - 中文输入在 raw mode 下是否仍然正常（Epic 37.9 修复的 UTF-8 问题不能回退）
> - bracket paste 在 raw mode 下是否需要不同处理（`\e[200~` / `\e[201~` 序列解析）
> - `FileHandle.standardInput.readabilityHandler` vs `read()` 系统调用的性能差异
>
> Spike 产出：一个可编译运行的 `RawModeDemo.swift`，验证上述 4 点。如果 raw mode 不可行，需要评估替代方案（如 linenoise-swift 或其他 Swift 终端输入库）。

**Codex 架构参考：**

Codex 的 `DraftState` 是 composer 的核心状态容器，包含：
- `textarea`（编辑区状态）
- `pending_pastes`（粘贴缓冲）
- `mention_bindings`（@mention 绑定映射）
- `input_enabled`（输入启用/禁用）
- `paste_burst`（粘贴爆发合并机制）

所有交互模式（历史搜索、@文件、slash popup）都是 composer 的**叠加态**，通过 `FooterMode` 枚举切换。

**迁移策略（替换 MultiLineInputReader）：**

Epic 37.6 已实现的 `MultiLineInputReader` 提供 multiline 输入 + bracket paste + 续行支持。38.0 的 `ChatComposer` 需要**完全替代**它，同时保留所有已有能力：

| MultiLineInputReader 能力 | ChatComposer 对应 |
|---|---|
| `readLine()` 行读取 | raw mode 逐字节读取 + 行缓冲 |
| Bracket paste (`\e[200~` / `\e[201~`) | 保留，在 raw mode 下解析 ANSI 序列 |
| `\` 续行 (`...>` 提示符) | 保留，composer 内部状态管理 |
| UTF-8 中文输入 (37.9 修复) | 保留，raw mode 下手动 UTF-8 解码 |
| 非 TTY 降级到 `readLine()` | 保留，`isatty()` 检测后分支 |

**Axion 适配要点：**
- `ChatComposer` struct **替代** `MultiLineInputReader`，内部管理 raw mode 生命周期
- `ComposerDraft` struct 支持完整快照/恢复（text + cursor + 附件状态）
- `ComposerMode` enum: `normal | slashPopup | historySearch | fileSearch | approval`
- 非 TTY 自动降级到当前 `readLine()` 路径（复用 `MultiLineInputReader.readLine()` 方法）
- 键盘事件通过 `termios` raw mode + `FileHandle.standardInput` 捕获
- REPL 模式下"弹出"slash popup 的视觉方案：在 prompt 行下方**追加输出**编号命令列表（append-only，非 overlay）

**Acceptance Criteria：**

**Given** 用户在 TTY 中运行 `axion`
**When** 输入普通文本
**Then** 行为与当前 chat 基本一致
**And** 仍支持多行输入和 bracket paste
**And** 中文输入和 backspace 行为正常（不回退 37.9 的修复）

**Given** 用户按下快捷键（如 Up / Down / Ctrl+R / Ctrl+G / Tab）
**When** composer 处理输入
**Then** 不需要等待整行提交后再响应
**And** 非 TTY 模式下自动降级到现有 `readLine()` 路径

**Given** 用户处于某个交互模式（如 slash popup）
**When** 按 Esc
**Then** 回到 normal 模式，草稿内容完整恢复

**Given** 用户使用 `\` 续行（Epic 37.6 行为）
**When** 在行末输入 `\` 后回车
**Then** 显示 `...>` 续行提示，继续输入

**Given** 用户粘贴多行文本（bracket paste）
**When** 粘贴完成
**Then** 整段文本作为一条消息，不按行拆分

**Given** 终端不支持 raw mode（如 SSH 到旧系统）
**When** 启动 chat
**Then** 自动降级到 `MultiLineInputReader` 的 `readLine()` 路径
**And** 所有快捷键不可用，但基本对话正常

**实现参考：**
- `Sources/AxionCLI/Chat/MultiLineInputReader.swift`（**被替换**，保留降级路径）
- 新增 `Sources/AxionCLI/Chat/Composer/ChatComposer.swift`
- 新增 `Sources/AxionCLI/Chat/Composer/ComposerDraft.swift`
- 新增 `Sources/AxionCLI/Chat/Composer/ComposerMode.swift`
- 新增 `Sources/AxionCLI/Chat/Composer/KeyEventReader.swift`（termios raw mode 封装）
- 新增 `Sources/AxionCLI/Chat/Composer/RawModeSpike.swift`（前置验证）
- Codex 参考：`bottom_pane/chat_composer/draft_state.rs`、`bottom_pane/chat_composer/footer_state.rs`

---

### Story 38.1: 对话视觉语义层

As a Axion CLI 用户,
I want 用户提问、AI 回复、工具事件、审批事件在终端里有稳定的视觉标识,
So that 长对话中我能快速扫读上下文，而不是面对一整段连续文本。

**核心设计（已确定为最终方案）：**

采用**左侧彩色实心圆点**作为角色视觉标识（替代 Codex 的微妙背景色方案）。选择圆点而非背景色的原因：
1. 圆点在所有终端（TrueColor / Ansi256 / Ansi16 / 无色）下都可靠渲染
2. 背景色在许多终端模拟器中不可靠（tmux、screen、某些 SSH 客户端不支持 OSC 背景色查询）
3. 圆点在窄终端（<40 列）下仍可辨识，背景色在窄终端下可能破坏布局

角色圆点颜色方案：
- 用户：蓝色 `●`
- AI：绿色 `●`
- Tool：黄色 `●`
- Approval / Warning：红色 `●`

辅助设计：
- 同一轮 assistant 输出在视觉上组成一个 block（共享左侧绿色圆点标记）
- tool/result/approval 使用统一的缩进和标题样式
- 非 TTY / 不支持 ANSI 时自动回退为纯文本前缀（如 `[user]`、`[ai]`）

**Codex 架构参考：**

Codex 的角色视觉区分策略：

| 元素 | 暗色背景 | 亮色背景 |
|------|---------|---------|
| User 消息 | 白色 12% alpha 背景 + `› ` 前缀（bold dim） | 黑色 4% alpha 背景 + `› ` 前缀 |
| AI 消息 | `• ` 前缀（dim）+ 无特殊背景 | 同左 |
| 工具/Status | Spinner + shimmer 动画 | 同左 |
| 强调/活跃 | Cyan + Bold | RGB(0,95,135) + Bold |

关键设计：
- 用户消息通过**微妙背景色变化**区分，不依赖前景色
- AI 消息无背景色，靠前缀和缩进形成视觉层级
- 颜色系统通过 `is_light(bg)` 自适应亮暗终端

**Axion 适配要点：**
- 新增 `TerminalColorProfile` enum: `trueColor | ansi256 | ansi16 | unknown`
- 启动时通过 `TerminalAdapter.detectColorSupport()` 探测并缓存
- 所有视觉输出通过 `ChatTheme` 统一适配
- 圆点颜色在 ansi16 终端下降级为默认色（无圆点或 dim 圆点）

**Acceptance Criteria：**

**Given** 用户发送一条消息
**When** 该消息进入 transcript
**Then** 终端左侧显示用户角色圆点
**And** 该轮消息主体与后续 assistant/tool block 明确分层

**Given** assistant 开始回复
**When** 流式输出进行中
**Then** assistant 文本以 AI 角色样式输出
**And** 与工具调用、错误、审批请求有可区分视觉语义

**Given** tool call / tool result / approval request
**When** 输出到终端
**Then** 左侧或标题区域有固定语义标识
**And** 颜色和图标的含义在整场会话中保持一致

**Given** 终端不支持 ANSI 颜色（如 pipe 模式）
**When** 输出消息
**Then** 回退为纯文本前缀标识（如 `[user]`、`[ai]`、`[tool]`）

**Given** 用户在 tmux / screen 会话中运行 Axion
**When** 输出角色圆点
**Then** 圆点正常渲染（不依赖 OSC 背景色查询）
**And** 不出现背景色相关的乱码

**Given** 终端宽度 < 40 列
**When** 输出带圆点的消息
**Then** 圆点仍正常显示，消息正文正常换行
**And** 不出现圆点与文字重叠或行错位

**实现参考：**
- `Sources/AxionCLI/Chat/ChatOutputFormatter.swift`
- `Sources/AxionCLI/Chat/MarkdownTerminalRenderer.swift`
- 新增 `Sources/AxionCLI/Chat/Theme/ChatTheme.swift`
- 新增 `Sources/AxionCLI/Chat/Theme/TerminalColorProfile.swift`
- 新增 `Sources/AxionCLI/Chat/Theme/TranscriptRenderer.swift`
- Codex 参考：`style.rs`（自适应样式）、`color.rs`（亮度检测 + 颜色降级）、`terminal_palette.rs`（探测链）、`history_cell/messages.rs`（角色样式）

---

### Story 38.2: Slash 命令面板与补全

As a Axion CLI 用户,
I want 输入 `/` 时看到命令列表、描述和筛选结果,
So that 我不必记住所有 slash 命令。

**Codex 架构参考：**

Codex 的 Slash 命令系统是**四层架构**：

1. **定义层**（`slash_command.rs`）：`SlashCommand` 枚举，strum 宏驱动 `from_str`/`iter`/`serialize`，每个变体携带 `description()`/`aliases()` 元数据
2. **过滤层**（`bottom_pane/slash_commands.rs`）：`BuiltinCommandFlags` 特性门控 + `builtins_for_input()` 链式 `.filter()`
3. **UI 层**（`command_popup.rs` + `slash_input.rs`）：`CommandPopup` Widget 渲染列表，`SlashInput` 管理输入验证
4. **路由层**（`chatwidget/slash_dispatch.rs`）：`dispatch_command()` match → `AppEvent` 异步分发

命令的可用性分三个维度控制：
- `available_during_task`：任务运行中是否可用（如 `/status` 可用，`/new` 不可用）
- `available_in_side`：side 会话中是否可用（仅 6 个命令可用）
- `accepts_args`：是否支持行内参数（如 `/side <question>`）

**Axion 适配要点：**
- `SlashCommand` enum 增加 `CaseIterable` + 计算属性 `description`/`aliases`/`acceptsArgs`/`availableDuringTask`/`availableInSide`
- REPL 模式下命令列表输出为编号列表（非 popup），高亮匹配字符
- 过滤逻辑：大写不敏感前缀匹配，精确匹配优先
- `SlashCommandHandler` 增加上下文感知过滤（当前是否在 side 会话、是否 agent 忙碌）

**Acceptance Criteria：**

**Given** 用户在空输入或行首输入 `/`
**When** composer 进入 slash 模式
**Then** 显示可用命令列表和简要描述
**And** 列表根据当前上下文动态过滤（side 会话中只显示可用命令）

**Given** 用户继续输入 `/re`
**When** 命令面板过滤
**Then** 只显示匹配命令（如 `/resume`、未来的 `/review`）
**And** Enter 可补全当前高亮项

**Given** 命令支持 inline 参数（如 `/resume <id>`）
**When** 用户完成命令名
**Then** 参数区仍可继续编辑
**And** 不把整条命令误判为普通消息

**Given** agent 正在执行任务
**When** 用户输入 `/`
**Then** 不显示 `/new`、`/fork`、`/archive`、`/resume` 等结构性命令

**实现参考：**
- `Sources/AxionCLI/Chat/SlashCommand.swift`
- `Sources/AxionCLI/Chat/SlashCommandHandler.swift`
- 新增 `Sources/AxionCLI/Chat/Composer/SlashPopup.swift`
- Codex 参考：`slash_command.rs`（枚举 + 元数据）、`bottom_pane/slash_commands.rs`（过滤门控）、`bottom_pane/command_popup.rs`（UI + 匹配算法）、`bottom_pane/chat_composer/slash_input.rs`（输入解析）、`chatwidget/slash_dispatch.rs`（路由分发）

---

### Story 38.3: 审批中心 v2

As a Axion CLI 用户,
I want 在危险操作确认时拥有一次允许、会话允许、命令前缀允许和查看详情等选择,
So that 安全性和操作流畅度能同时兼顾。

**Codex 架构参考：**

Codex 的审批系统设计了 5 种决策粒度：

| 决策 | 标签 | 快捷键 | 含义 |
|------|------|--------|------|
| `Accept` | "Yes, just this once" | `y` | 仅本次允许 |
| `AcceptForSession` | "Yes, and don't ask again for this command in this session" | `a` | 本会话对相同命令允许 |
| `AcceptWithExecpolicyAmendment` | "Yes, and don't ask again for commands that start with `...`" | `p` | 注册命令前缀规则 |
| `Decline` | "No, continue without running it" | `d` | 拒绝但继续对话 |
| `Cancel` | "No, and tell Codex what to do differently" | `Esc`/`c` | 拒绝并要求 agent 调整 |

关键设计：
- **动态选项**：后端通过 `available_decisions` 字段告诉 UI 应展示哪些选项（不是硬编码展示全部）
- **审批排队**：`enqueue_request` → `advance_queue`，支持多请求排队处理
- **安全底线**：MCP Elicitation 中 Esc **永远**映射为 cancel，即使用户自定义了 keymap
- **全屏详情**：Ctrl+Shift+A 触发全屏查看 diff/长命令
- **历史记录**：每次审批决策插入一条 `InsertHistoryCell` 记录

**Axion 适配要点：**
- `PermissionHandler` 增加 `ApprovalDecision` enum: `once / session / prefix / decline / cancel`
- `ApprovalOption` struct: `label` + `shortcut` + `decision`
- 动态生成选项列表：文件修改显示 diff 摘要，Bash 命令显示前缀匹配提示
- 会话级允许用 `[String]` 数组存储已允许的命令模式
- 前缀允许策略："first N tokens" 方案——将命令按空格拆分为 tokens，用户选择前缀允许时注册前 N 个 token（如 `git commit -m "msg"` → 注册 `["git", "commit"]`，后续所有 `git commit ...` 自动放行）。避免 `hasPrefix()` 的误匹配（如 `git` 前缀会匹配 `git push --force`）
- REPL 模式下选项以编号列表展示，快捷键直接响应

**Acceptance Criteria：**

**Given** agent 要执行危险 Bash 命令
**When** 审批触发
**Then** 用户至少可以选择：
1. 仅本次允许（y）
2. 本会话对相同命令允许（a）
3. 对命令前缀允许（p）— 显示前缀匹配提示
4. 拒绝（d）
5. 拒绝并告诉 agent 换种方式（Esc）

**Given** agent 要修改文件
**When** 审批触发
**Then** 用户可以查看目标文件、修改摘要或 diff 摘要
**And** 不需要在"盲批"状态下做决定

**Given** 用户选择"会话允许"
**When** 同一命令再次出现
**Then** 自动放行，不弹审批
**And** 会话允许列表在会话结束时自动清除

**Given** 非 TTY 环境
**When** 审批触发
**Then** 保持当前安全默认：拒绝危险操作

**实现参考：**
- `Sources/AxionCLI/Chat/PermissionHandler.swift`
- `Sources/AxionCLI/Commands/ChatCommand.swift`
- 新增 `Sources/AxionCLI/Chat/Approval/ApprovalDecision.swift`
- 新增 `Sources/AxionCLI/Chat/Approval/SessionAllowList.swift`
- 新增 `Sources/AxionCLI/Chat/Approval/PrefixMatcher.swift`
- Codex 参考：`bottom_pane/approval_overlay.rs`（~1900 行，完整审批系统）、`protocol/src/request_permissions.rs`（`PermissionGrantScope`）

---

### Story 38.4: Composer 效率增强

As a Axion CLI 用户,
I want 用历史浏览、Ctrl+R 搜索和外部编辑器快速修改 prompt,
So that 长 prompt 和重复 prompt 的输入成本大幅下降。

**Codex 架构参考：**

**历史搜索状态机（`HistorySearchSession`）：**

```
Idle（query=""，无预览）
  ↓ [输入字符]
Searching（等待持久化历史加载）
  ↓ [找到匹配]
Match（预览匹配项，Enter 采纳 / Ctrl+R 继续找更旧的）
  ↓ [无匹配]
NoMatch（恢复原草稿，显示 "no match"）
```

搜索算法：
- 大小写不敏感子串匹配：`entry.text.lowercased().contains(query.lowercased())`
- 去重：`Set<String>` 记录已匹配文本
- 统一偏移空间：`[0, persistentCount)` = 文件持久化历史（异步），`[persistentCount, total)` = 当前会话历史（同步）

**外部编辑器流程：**
1. 解析 `$VISUAL` → `$EDITOR` → 报错
2. 创建 `.md` 临时文件，写入当前草稿
3. 恢复终端到 normal mode
4. 启动编辑器子进程（继承 stdin/stdout/stderr）
5. 等待编辑器退出
6. 读取临时文件内容，去除尾部空白
7. 回填到 composer

**草稿快照机制（`ComposerDraft`）：**
- 进入搜索前 `snapshot_draft()` 保存完整状态（text + cursor + 附件）
- 取消搜索时 `restore_draft()` 原子恢复
- Enter 采纳搜索结果时草稿被替换为新内容

**Axion 适配要点：**
- **历史搜索范围**：当前会话内用户发送的所有消息（当前 session 的 `userMessageHistory: [String]` 数组）。跨会话历史搜索作为未来增强（需要持久化历史索引），本 Story 不实现
- 历史搜索复用当前会话中记录的用户消息列表（`ChatCommand` 已维护 `sessionHistory` 数组）
- `HistorySearchSession` struct 管理状态转换
- 搜索结果在 composer 上方以 `reverse-i-search: <query>` footer 提示
- Up/Down 在非搜索模式下回填最近历史（`localHistory` 数组）
- 外部编辑器用 `Process.launch()` 启动

**Acceptance Criteria：**

**Given** 用户按 Up / Down
**When** composer 中没有正在编辑的复杂多行草稿
**Then** 可以回填和浏览最近历史消息

**Given** 用户按 Ctrl+R
**When** 进入搜索模式
**Then** 底部显示 `reverse-i-search: ` 提示
**And** 继续输入字符实时过滤历史

**Given** 搜索找到匹配项
**When** 按 Ctrl+R 继续搜索
**Then** 跳到更旧的匹配
**And** 按 Ctrl+S 跳到更新的匹配

**Given** 用户按 Enter
**When** 当前有匹配项
**Then** 采纳匹配项作为可编辑草稿
**And** 退出搜索模式

**Given** 用户按 Esc / Ctrl+C
**When** 处于搜索模式
**Then** 取消搜索，恢复进入搜索前的原始草稿

**Given** 用户按 Ctrl+G
**When** 本机设置了 `VISUAL` 或 `EDITOR`
**Then** Axion 在外部编辑器打开当前草稿
**And** 保存退出后内容回填到 composer

**Given** 未设置编辑器环境变量
**When** 按 Ctrl+G
**Then** 显示提示 "请设置 VISUAL 或 EDITOR 环境变量"

**实现参考：**
- 新增 `Sources/AxionCLI/Chat/Composer/HistorySearchSession.swift`
- 新增 `Sources/AxionCLI/Chat/Composer/ExternalEditorLauncher.swift`
- 新增 `Sources/AxionCLI/Chat/Composer/ComposerDraft.swift`
- Codex 参考：`bottom_pane/chat_composer/history_search.rs`（`HistorySearchSession` + 状态机）、`bottom_pane/chat_composer/draft_state.rs`（`ComposerDraft`）、`external_editor.rs`（编辑器集成）、`insert_history.rs`（历史回填到终端 scrollback）

---

### Story 38.5: Busy-turn 输入排队

As a Axion CLI 用户,
I want 在 agent 还在执行时先输入下一条消息并排队,
So that 我不用傻等当前回合结束才能补充信息。

**Codex 架构参考：**

Codex 的 `InputQueueState` 核心：
- `queued_user_messages: VecDeque<QueuedUserMessage>` — FIFO 无容量限制
- `QueuedInputAction` 枚举：`Plain / ParseSlash / RunShell`
- 入队条件：会话未配置完成 **或** 当前有 turn 运行
- 消费机制：turn 结束后 `maybe_send_next_queued_input()` 逐条弹出
- `preview()` 方法返回排队消息预览，更新底部面板 UI
- 支持弹出最近排队消息回退到 composer 编辑

**Axion 适配要点：**
- `InputQueue` struct：`[QueuedMessage]` 数组 + FIFO 语义，**最大容量 5 条**（防止用户无意识排队过多消息）。超出时提示"排队已满，请等待当前任务完成"
- agent 忙碌时（`isAgentBusy` 标志），新消息自动入队
- 入队反馈：在 prompt 行下方显示 `⏳ 已排队 (1条等待): "消息预览..."`
- turn 结束事件触发自动发送队列头部
- 快捷键（如 Ctrl+E）弹出最近排队消息到 composer
- **依赖 Story 38.0**：队列的 UI 交互（Ctrl+E 弹出编辑、排队预览显示）需要 composer 的 raw mode 支持。如果 38.0 尚未完成，本 Story 可先实现核心队列逻辑（入队/消费/FIFO），UI 反馈降级为文本输出

**Acceptance Criteria：**

**Given** 当前 turn 正在执行
**When** 用户提交新的普通消息
**Then** 该消息进入 queued 状态
**And** 终端明确显示"已排队"的反馈和消息预览

**Given** 当前 turn 结束
**When** 队列里有待发送消息
**Then** 下一条消息自动进入执行
**And** 队列顺序保持 FIFO

**Given** 用户发现排队消息写错了
**When** 触发"编辑最近排队消息"快捷键（Ctrl+E）
**Then** 最近一条排队消息恢复到 composer 中可编辑
**And** 从队列中移除

**Given** 队列中有多条消息
**When** 连续 turn 结束
**Then** 每轮只自动发送一条，剩余继续排队
**And** 排队列表实时更新

**实现参考：**
- 新增 `Sources/AxionCLI/Chat/InputQueue.swift`
- 修改 `ChatCommand.swift` 主循环（turn 结束事件处理增加队列消费）
- Codex 参考：`chatwidget/input_queue.rs`（`InputQueueState` 完整实现）、`chatwidget/user_messages.rs`（类型定义）

---

### Story 38.6: 工作区快捷上下文

As a Axion CLI 用户,
I want 用最短路径把 repo 里的关键上下文送进会话,
So that 我不必手写冗长 prompt 描述文件和 diff。

**Codex 架构参考：**

Codex 的 @ 提及系统（mentions_v2）包含 8 个模块：

| 模块 | 职责 |
|------|------|
| `candidate.rs` | `MentionType` 枚举（Plugin/Skill/File/Directory）+ `Selection` 输出 |
| `search_catalog.rs` | 从 Skills/Plugins 构建初始候选目录 |
| `filter.rs` | 模糊匹配 + 文件搜索合并 + 排序（类型优先级: Plugin>Skill>File） |
| `search_mode.rs` | 三种模式状态机：Results → FilesystemOnly → Tools → 循环 |
| `popup.rs` | 主交互组件 |
| `render.rs` | 列表渲染 + 匹配高亮 + 类型标签颜色 |
| `footer.rs` | 底部操作提示栏 |

文件搜索流程：
1. `ChatComposer` 检测 `@` token → 发布 `AppEvent::StartFileSearch(query)`
2. `FileSearchManager` 创建搜索 session（含 `session_token` 防过期）
3. 异步搜索完成后发布 `AppEvent::FileSearchResult`
4. 结果与 Skills/Plugins 合并、排序后显示在 popup

**Axion 适配要点：**
- `@` 文件搜索：同步扫描当前目录（`FileManager.enumerator(at:)`），足够快不需要异步
- 候选列表以编号列表输出（REPL 模式），非 popup
- `/diff` 命令：执行 `Process.launch("git", "diff", "--stat")` 捕获输出
- `/status` 命令：展示 model、permission mode、session ID、context tokens、cwd、累计 token usage

**Acceptance Criteria：**

**Given** 用户输入 `@`
**When** 开始输入文件名
**Then** 显示匹配文件候选列表（编号 + 路径）
**And** 选中后把路径插入当前消息

**Given** 用户输入 `/diff`
**When** 命令执行
**Then** 终端展示当前 git diff 摘要（含未跟踪文件）
**And** 用户可将其作为当前会话的快捷上下文

**Given** 用户输入 `/status`
**When** 命令执行
**Then** 显示当前会话状态卡：模型、权限模式、session ID、context 使用量、cwd、累计 token
**And** 比现有 `/config` 更贴近"当前会话状态卡"

**实现参考：**
- 新增 `Sources/AxionCLI/Chat/Commands/DiffCommand.swift`
- 新增 `Sources/AxionCLI/Chat/Commands/StatusCommand.swift`
- 新增 `Sources/AxionCLI/Chat/Composer/FileSearchPopup.swift`
- Codex 参考：`file_search.rs`（`FileSearchManager`）、`bottom_pane/mentions_v2/`（8 文件完整 @ 系统）、`status_indicator_widget.rs`（状态展示格式）

---

### Story 38.7: 会话工作流

As a Axion CLI 用户,
I want 有 `/new`、`/fork`、`/archive` 这类会话命令,
So that 我可以自然地开始新话题、分叉旧思路或整理会话。

**Codex 架构参考：**

Codex 的会话管理核心结构是 `ThreadSessionState`：

```rust
struct ThreadSessionState {
    thread_id: ThreadId,
    forked_from_id: Option<ThreadId>,   // fork 来源
    thread_name: Option<String>,
    model: String,
    approval_policy: ApprovalPolicy,
    cwd: PathBuf,
    // ... 10+ 字段
}
```

关键操作：
- `/new` → `AppEvent::NewSession`：直接创建新会话，当前会话保留可恢复
- `/fork` → `AppEvent::ForkCurrentSession`：调用 `app_server.fork_thread()` 继承所有上下文创建分支
- `/archive` → 确认对话框 → `AppEvent::ArchiveCurrentThread`：标记归档，不出现在 resume 列表
- `/resume` → 无参数弹选择器 / 有参数直接恢复：支持按 ID 或名称匹配

Resume Picker（~6300 行）是全屏 TUI，支持分页加载（每页 25 条）、前后端双层搜索、排序切换、对话预览。Axion 不搬全屏 TUI，用编号列表替代。

**Axion 适配要点：**
- `SessionStore` 增加 `archive(sessionId:)` / `fork(sessionId:)` / `create()` 方法
- `SessionState` 增加 `archived: Bool` / `forkParentId: String?` 字段
- `/resume` 无参数时列出最近 N 个未归档会话（编号 + 首行预览 + 时间）
- `/fork` 复制当前会话历史到新 session，继承 model/cwd/config

**Acceptance Criteria：**

**Given** 用户输入 `/new`
**When** 命令执行
**Then** 开始一个新会话
**And** 当前会话自动保存，可恢复

**Given** 用户输入 `/fork`
**When** 命令执行
**Then** 从当前会话分叉出一个新 session
**And** 继承当前对话历史、model、cwd、config
**And** 后续消息互不污染

**Given** 用户输入 `/archive`
**When** 命令执行
**Then** 弹出确认提示
**And** 确认后当前会话被归档
**And** 默认 resume 列表中不显示归档会话

**Given** 用户输入 `/resume`（无参数）
**When** 命令执行
**Then** 列出最近 10 个未归档会话（编号 + 时间 + 首行预览）
**And** 用户输入编号恢复对应会话

**Given** 用户输入 `/resume <id>`
**When** 命令执行
**Then** 直接恢复指定会话

**实现参考：**
- `Sources/AxionCLI/Chat/SessionResumeManager.swift`
- `Sources/AxionCLI/Services/SessionStore.swift`
- 新增 `Sources/AxionCLI/Chat/Commands/NewCommand.swift`
- 新增 `Sources/AxionCLI/Chat/Commands/ForkCommand.swift`
- 新增 `Sources/AxionCLI/Chat/Commands/ArchiveCommand.swift`
- 修改 `SlashCommand.swift` 增加新命令枚举
- Codex 参考：`session_state.rs`（`ThreadSessionState`）、`session_resume.rs`（恢复逻辑）、`resume_picker.rs`（选择器，Axion 简化为列表）

---

### Story 38.8: Side Conversation ⚠️ 建议延后到 Epic 39

> **⚠️ 延后建议：** 本 Story 优先级最低（P3），架构风险最高（需要 session 临时 fork + 边界提示词注入 + 命令限制 + 生命周期管理），建议移至 Epic 39 单独评估。Epic 38 聚焦 Story 38.0–38.7 的交付。

As a Axion CLI 用户,
I want 在主线程之外临时开一个 side conversation 提问或探索,
So that 我可以查一个问题、试一个思路，而不污染主任务线程。

**Codex 架构参考：**

Codex 的 Side Conversation 是一个**临时一次性 fork**，核心机制：

1. **边界提示词**（`SIDE_BOUNDARY_PROMPT`）：注入为隐藏 user 消息
   - 标记 side conversation 的边界
   - 声明边界前的历史仅为参考上下文，不可继续执行
   - 禁止继续执行继承历史中的任何指令、计划、工具调用
   - 允许非变更性检查（读文件、搜索等）
   - 只在用户明确要求时才允许修改操作

2. **生命周期**：
   - 创建：fork 当前线程 → 注入边界提示词 → 切换到 side 线程
   - 执行：仅暴露 6 个命令（Copy/Raw/Diff/Mention/Status/Ide）
   - 销毁：side turn 结束 → 自动返回主线程 → 清理本地状态

3. **约束**：
   - 同时只允许一个 side conversation
   - 主线程必须已开始对话
   - `ephemeral = true`，不持久化
   - 不可重命名

**Axion 适配要点：**
- Side session 是一个临时 `SessionState`，不写入 `SessionStore` 持久化
- 边界提示词复用 Codex 的 `SIDE_BOUNDARY_PROMPT` 设计思路，适配 Axion 的工具白名单
- Side 中限制可用的 slash 命令（/diff /status /copy 等，不允许 /new /fork /archive）
- Side turn 结束后显示"按 Enter 返回主线程"提示
- 用 `sideSessionId` 和 `mainSessionId` 标记当前模式

**Acceptance Criteria：**

**Given** 当前主会话已经开始
**When** 用户输入 `/side <question>` 或 `/btw <question>`
**Then** Axion 创建一个临时 side session
**And** 注入边界提示词，明确告诉 agent：主线程历史只作参考，不是当前 side 任务
**And** 主线程状态保持不变

**Given** 用户在 side 会话中进行轻量探索
**When** side turn 结束
**Then** 显示"Side 完成，按 Enter 返回主线程"提示
**And** side 会话默认不改动主线程的目标和执行节奏

**Given** 用户未明确要求修改
**When** side conversation 中执行动作
**Then** 默认仅允许非破坏性探索，不主动修改工作区

**Given** 已有一个 side conversation 正在进行
**When** 用户尝试再次输入 `/side`
**Then** 提示"已有 side 会话在进行中，先完成或取消当前 side"

**Given** 用户按 Ctrl+C / Esc
**When** 在 side 会话中
**Then** 中止 side 会话，返回主线程
**And** 主线程上下文不受影响

**实现参考：**
- 新增 `Sources/AxionCLI/Chat/Side/SideConversationManager.swift`
- 新增 `Sources/AxionCLI/Chat/Side/SideBoundaryPrompt.swift`
- 修改 `SlashCommand.swift` 增加 `.side` / `.btw` 枚举
- 修改 `ChatCommand.swift` 增加 side session 生命周期管理
- Codex 参考：`app/side.rs`（`SideThreadState` + `SIDE_BOUNDARY_PROMPT` + 生命周期管理）

---

## 非目标与延后项

以下 Codex 能力本 Epic 明确不搬：

| Codex 能力 | 不搬原因 |
|-----------|---------|
| `pets` / `theme` / `personality` | 与 coding agent 主路径弱相关 |
| `realtime` voice / `audio_device` | 语音交互不在 Axion 范围 |
| `apps` / `plugins` / `connectors` | Axion 无插件市场 |
| `rollout` / `feedback` | 运营功能，非交互体验 |
| 多 agent 线程切换器（`/agent`/`/subagents`） | Axion 暂无多 agent 线程 |
| 图片附件（`local_images`/`remote_image_urls`） | 终端 REPL 不适合图片 |
| 全屏 transcript overlay / pager | REPL 模式下不需要 |
| 终端 resize transcript 重排（`transcript_reflow.rs`） | REPL 行式输出不受 resize 影响 |
| Vim 编辑模式（`bottom_pane/textarea/vim.rs`） | 过度复杂，可用外部编辑器替代 |
| `clipboard_copy` / `clipboard_paste` | 可延后 |
| `onboarding` / `local_chatgpt_auth` | Codex 专有认证流程 |
| `collaboration_modes`（plan mode） | 独立 feature，不在此 Epic |
| `goal` / `rename` / `title` / `statusline` | 低优先级，可后续补充 |
| `skills` / `hooks` / `memories` 管理 UI | Axion 已有 CLI 命令覆盖 |
| `mcp` 列表 / `ide` 上下文 / `init` (AGENTS.md) | Axion 生态不同 |

这些能力可以在未来单独评估，但不应干扰 Epic 38 的核心目标：**把 Axion chat 做成一个顺手的 terminal coding conversation surface。**

---

## 非功能性需求（NFR）

| 指标 | 目标 | 相关 Story |
|------|------|-----------|
| 文件搜索响应时间 | < 100ms（同步扫描当前 repo，最多 10,000 文件） | 38.6 |
| Slash 命令列表渲染 | < 50ms（CaseIterable 遍历 + 过滤 + 输出） | 38.2 |
| 外部编辑器回填延迟 | 0ms（编辑器关闭后立即回填，无额外等待） | 38.4 |
| 历史搜索响应时间 | < 50ms（当前会话内搜索，通常 < 200 条记录） | 38.4 |
| 输入排队入队延迟 | < 10ms（数组 append 操作） | 38.5 |
| Composer raw mode 切换 | < 5ms（termios 设置切换） | 38.0 |
| 角色圆点渲染 | 不增加可感知的输出延迟（单字符 ANSI 输出） | 38.1 |
| 内存占用增长 | 整个 Epic 完成后，空闲状态内存增长 < 5MB | 全部 |

---

## 测试策略

### 单元测试（Mock 策略）

终端交互组件的单元测试需要 Mock 以下依赖：

| 组件 | Mock 策略 | 原因 |
|------|---------|------|
| `KeyEventReader` | Protocol `KeyReading` + `MockKeyReader`（注入预定义按键序列） | 测试环境中无真实 TTY |
| `TerminalColorProfile` | Protocol `ColorProfileDetecting` + `MockColorProfile` | 避免探测真实终端 |
| `FileSearchPopup` | Protocol `FileSearching` + `MockFileSearcher` | 避免扫描真实文件系统 |
| `ExternalEditorLauncher` | Protocol `EditorLaunching` + `MockEditorLauncher` | 避免启动真实编辑器 |
| `InputQueue` | 直接测试（纯逻辑，无外部依赖） | FIFO + 容量限制可完全单元测试 |
| `HistorySearchSession` | 直接测试（状态机 + 纯字符串搜索） | 无外部依赖 |
| `SessionAllowList` | 直接测试（前缀匹配 + 集合操作） | 无外部依赖 |

### 手动测试清单

以下场景需要人工在真实终端中验证：

- [ ] **Raw mode 基础**：在 iTerm2、Terminal.app、Alacritty、WezTerm 中分别测试 Up/Down/Ctrl+R/Ctrl+G/Tab/Esc 按键响应
- [ ] **中文输入**：raw mode 下输入中文字符 + backspace 删除（验证 37.9 修复不回退）
- [ ] **Bracket paste**：从文本编辑器复制多行文本粘贴到 raw mode composer
- [ ] **tmux 环境**：在 tmux session 中测试所有交互（slash popup、历史搜索、审批选项）
- [ ] **窄终端**：终端宽度 < 40 列时消息和圆点的布局
- [ ] **SSH 远程**：通过 SSH 连接后测试（验证非 TTY 降级和 limited color）
- [ ] **外部编辑器**：`VISUAL=vim`、`EDITOR=nano`、未设置 环境变量三种场景
- [ ] **Pipe 模式**：`echo "hello" \| axion chat` 验证降级路径
- [ ] **审批排队**：agent 连续请求多个审批时的交互流程
- [ ] **会话恢复**：`/fork` 后 `/resume` 验证 fork 历史完整性

---

## 错误处理

| 错误场景 | 处理策略 | 相关 Story |
|---------|---------|-----------|
| 文件搜索遇到权限拒绝目录 | 跳过该目录，继续搜索其他目录，不报错中断 | 38.6 |
| 文件搜索超时（repo 过大） | 超过 100ms 后截断结果，显示 "显示前 N 条结果（共 M 个文件）" | 38.6 |
| 外部编辑器进程崩溃 | 捕获 `SIGCHLD` + 非零退出码，恢复终端到 raw mode，显示 "编辑器异常退出" | 38.4 |
| 外部编辑器未设置 | 显示 "请设置 VISUAL 或 EDITOR 环境变量" 提示，不崩溃 | 38.4 |
| 临时文件创建失败 | 捕获错误，显示 "无法创建临时文件: <原因>"，不崩溃 | 38.4 |
| 会话文件损坏（/resume 恢复时） | 显示 "会话文件损坏，无法恢复"，跳过该会话，列出其他可用会话 | 38.7 |
| Raw mode 设置失败 | 自动降级到 `MultiLineInputReader.readLine()` 路径，显示 "快捷键不可用" 提示 | 38.0 |
| 终端颜色探测失败 | 默认使用 `ansi16` profile，确保基本可读性 | 38.1 |
| 队列溢出（超过 5 条） | 拒绝新消息，显示 "排队已满（5/5），请等待当前任务完成" | 38.5 |
| Side session 创建失败 | 显示错误信息，保持在主线程中，不崩溃 | 38.8 |

---

## 产品结论

Epic 37 定义的是 **"Axion 有了交互 chat mode"**。
Epic 38 定义的是 **"Axion 的交互 chat mode 值得长期使用"**。

如果说 Epic 37 把 Axion 从 `run` 带到了 `chat`，那么 Epic 38 要把 Axion 从 **"能对话"** 带到 **"好对话"**。

---

## 附录：Codex 关键文件索引

| 模块 | 文件路径 | 行数 | Axion 对应 Story |
|------|---------|------|-----------------|
| Slash 命令定义 | `tui/src/slash_command.rs` | ~800 | 38.2 |
| 命令过滤 | `tui/src/bottom_pane/slash_commands.rs` | ~300 | 38.2 |
| 命令 Popup | `tui/src/bottom_pane/command_popup.rs` | ~200 | 38.2 |
| 输入解析 | `tui/src/bottom_pane/chat_composer/slash_input.rs` | ~150 | 38.2 |
| 命令路由 | `tui/src/chatwidget/slash_dispatch.rs` | ~400 | 38.2 |
| 审批 Overlay | `tui/src/bottom_pane/approval_overlay.rs` | ~1900 | 38.3 |
| 权限协议 | `protocol/src/request_permissions.rs` | ~100 | 38.3 |
| 历史搜索 | `tui/src/bottom_pane/chat_composer/history_search.rs` | ~300 | 38.4 |
| 草稿状态 | `tui/src/bottom_pane/chat_composer/draft_state.rs` | ~200 | 38.0/38.4 |
| 外部编辑器 | `tui/src/external_editor.rs` | ~200 | 38.4 |
| 历史回填 | `tui/src/insert_history.rs` | ~150 | 38.4 |
| 输入队列 | `tui/src/chatwidget/input_queue.rs` | ~400 | 38.5 |
| Side Conversation | `tui/src/app/side.rs` | ~500 | 38.8 |
| 会话状态 | `tui/src/session_state.rs` | ~200 | 38.7 |
| 会话恢复 | `tui/src/session_resume.rs` | ~300 | 38.7 |
| Resume Picker | `tui/src/resume_picker.rs` | ~6300 | 38.7 |
| 文件搜索 | `tui/src/file_search.rs` | ~150 | 38.6 |
| @ 提及系统 | `tui/src/bottom_pane/mentions_v2/` (8 文件) | ~800 | 38.6 |
| 颜色系统 | `tui/src/color.rs` | ~150 | 38.1 |
| 样式系统 | `tui/src/style.rs` | ~100 | 38.1 |
| 终端调色板 | `tui/src/terminal_palette.rs` | ~200 | 38.1 |
| 角色样式 | `tui/src/history_cell/messages.rs` | ~300 | 38.1 |
| 状态指示器 | `tui/src/status_indicator_widget.rs` | ~300 | 38.1 |
| 文本格式化 | `tui/src/text_formatting.rs` | ~200 | 38.1 |
| 快捷键映射 | `tui/src/keymap.rs` | ~1200 | 跨 Story |
| 事件定义 | `tui/src/app_event.rs` | ~300 | 跨 Story |
| Transcript 重排 | `tui/src/transcript_reflow.rs` | ~200 | 不搬 |
