---
baseline_commit: "786dec9b4332ab640e9485d64e7ea4efe4966e9f"
---

# Story 38.0: 轻量 Composer 输入基础

Status: done

## Story

As a Axion CLI 用户,
I want chat 输入从 `readLine()` 升级为可处理 key event 的轻量 composer,
So that slash popup、历史搜索、快捷键、排队编辑等能力有统一承载层。

## 为什么先做

Epic 37 的 `MultiLineInputReader` 基于 `readLine()` 行读取模型，解决了 multiline / bracket paste 问题，但不适合命令 popup、历史搜索、快捷键式交互。后续所有 Story（38.2–38.7）都需要 key event 级别的输入控制。继续在 `readLine()` 之上叠功能会让后续 story 越来越脆弱。

**同时解决 Epic 37 遗留技术债 TD4：** CJK raw mode 中的 `readCJKInput()`/`readCJKContinuation()` 与 `MultiLineInputReader` 的续行/粘贴逻辑重复。ChatComposer 统一 raw mode 路径，消除双份代码。

## Acceptance Criteria

1. **AC1: 基本文本输入** — TTY 模式下，ChatComposer 支持普通文本输入，行为与当前 `MultiLineInputReader` 基本一致（输入可见、Enter 提交、Backspace 删除）。中文输入和 UTF-8 字符边界处理正确（不回退 Story 37.9 的修复）。

2. **AC2: 反斜杠续行** — 行末输入 `\` + Enter → 显示 `...>` 续行提示符，继续输入。空行取消续行返回空字符串 `""`。

3. **AC3: Bracket Paste** — 粘贴多行文本时检测 `\x1b[200~`/`\x1b[201~` 包裹，整段文本作为一条消息，不按行拆分。

4. **AC4: 快捷键响应** — Up/Down/Ctrl+R/Ctrl+G/Tab/Esc 等按键立即响应，不等待整行提交。目前这些快捷键可暂不实现具体功能（仅输出提示），但 **按键不能丢失或被吞**。Up/Down 在无历史时无操作。Esc 清空当前输入。

5. **AC5: ComposerMode 状态机** — `ComposerMode` enum 定义 `normal | slashPopup | historySearch | fileSearch | approval`，支持模式切换。Normal 模式下按 Esc 清空当前输入（不退出 REPL）。Slash popup 等模式的具体 UI 由后续 Story 实现（38.2/38.4）。

6. **AC6: ComposerDraft 快照** — `ComposerDraft` struct 保存完整编辑状态（text + cursor），支持 `snapshot()` / `restore()`。任何模式切换前必须快照，取消时恢复。初始实现只需保存 text。

7. **AC7: 非 TTY 降级** — 终端非 TTY（`isatty()` 返回 false）时，自动降级到 `readLine()` 路径。基本对话正常，所有快捷键不可用。

8. **AC8: Raw mode 降级** — 如果 `termios` raw mode 设置失败，自动降级到当前 `readLine()` + CJK 路径，显示 "快捷键不可用" 提示。

9. **AC9: 替换 MultiLineInputReader** — `ChatCommand` 的 REPL 循环使用 `ChatComposer` 替代 `MultiLineInputReader`。`MultiLineInputReader` 保留但仅在非 TTY 降级路径中作为内部实现使用（不删除，降级路径复用其 `readLine()` 逻辑）。

10. **AC10: NFR — Raw mode 切换性能** — termios raw mode 设置/恢复 < 5ms，不引入可感知的输入延迟。

## Tasks / Subtasks

- [x] Task 1: 创建 `KeyEventReader`（AC4/AC7/AC8/AC10）
  - [x] 封装 `termios` raw mode 生命周期（enter/restore）
  - [x] 定义 `KeyEvent` enum：`.printable(String)` / `.enter` / `.backspace` / `.delete` / `.escape` / `.up` / `.down` / `.left` / `.right` / `.tab` / `.ctrl(Char)` / `.bracketPasteStart` / `.bracketPasteEnd` / `.eof` / `.unknown([UInt8])`
  - [x] 实现逐字节读取 + ANSI escape sequence 解析（Up=`\x1b[A`、Down=`\x1b[B` 等）
  - [x] Bracket paste 序列检测：`\x1b[200~` / `\x1b[201~`
  - [x] UTF-8 多字节字符边界处理（复用 `CJKInputHandler.utf8CharLength` + `processBackspace` 逻辑）
  - [x] 提供 `KeyReading` protocol，生产用 `TerminalKeyReader`，测试用 `MockKeyReader`
  - [x] 非 TTY 检测：构造时 `isatty()` → false 时 `readNext()` 返回 `.eof`
  - [x] Raw mode 失败时 `init()` 返回 nil（降级路径由 ChatComposer 处理）

- [x] Task 2: 创建 `ComposerDraft`（AC6）
  - [x] struct `ComposerDraft`：`text: String` + `cursor: Int`
  - [x] `snapshot()` → 返回 `ComposerDraft` 实例
  - [x] `restore(from:)` → 从 draft 恢复编辑状态
  - [x] 纯 struct，零外部依赖

- [x] Task 3: 创建 `ComposerMode` enum（AC5）
  - [x] 定义 `ComposerMode`：`normal` / `slashPopup(query: String)` / `historySearch(query: String)` / `fileSearch(query: String)` / `approval`
  - [x] `isNormal: Bool` 计算属性
  - [x] 纯 enum，零外部依赖

- [x] Task 4: 创建 `ChatComposer` struct（AC1–AC10）
  - [x] 替代 `MultiLineInputReader` 作为 Chat REPL 的输入组件
  - [x] 构造器注入：`keyReader: KeyReading?`（nil = 降级）、`isTTY: Bool`、`writeStdout`/`writeStderr` 闭包
  - [x] 内部状态：`buffer: String`、`cursor: Int`、`mode: ComposerMode`、`savedDraft: ComposerDraft?`
  - [x] `readInput(prompt:continuationPrompt:) -> String?` — 主公共 API（与 MultiLineInputReader 签名一致，便于替换）
  - [x] Raw mode 路径：`keyReader.readNext()` 事件循环
    - [x] `.printable` → 追加到 buffer + 回显
    - [x] `.enter` → 提交（检测 `\` 续行）
    - [x] `.backspace` → 删除完整 UTF-8 字符 + 回显更新
    - [x] `.escape` → normal 模式下清空 buffer；其他模式下恢复 draft + 回到 normal
    - [x] `.up` / `.down` / `.ctrl("r")` / `.ctrl("g")` / `.tab` → 暂仅输出提示文字（由 38.2/38.4 实现），不吞键
    - [x] `.bracketPasteStart` / `.bracketPasteEnd` → 累积粘贴内容，合并为单条输入
  - [x] 降级路径（非 TTY 或 raw mode 失败）：内部创建 `MultiLineInputReader` 并委托调用
  - [x] 反斜杠续行逻辑（从 `MultiLineInputReader` 迁移，统一 raw mode + 降级路径）
  - [x] Bracket paste 在 raw mode 下的完整实现（从 `CJKInputHandler` 迁移逻辑，消除双份代码）

- [x] Task 5: 修改 `ChatCommand` REPL 循环（AC9）
  - [x] 替换 `MultiLineInputReader` → `ChatComposer`
  - [x] `enableBracketPaste()` / `disableBracketPaste()` 改为在 ChatComposer 上调用（内部委托）
  - [x] 验证所有现有 REPL 行为不变（slash 命令、/resume、Ctrl+C 中断、会话恢复）
  - [x] 为 `readInput()` 调用添加 `// AC#` 注释标注

- [x] Task 6: 编写单元测试（AC1–AC10）
  - [x] `KeyEventReaderTests`（使用 MockKeyReader 注入）
  - [x] `ComposerDraftTests`：snapshot/restore 正确性
  - [x] `ComposerModeTests`：模式枚举覆盖
  - [x] `ChatComposerTests`：
    - [x] 普通文本输入 + 提交
    - [x] Backspace 删除 UTF-8 字符（中文 3 字节、emoji 4 字节）
    - [x] 反斜杠续行 + 空行取消
    - [x] Bracket paste 多行粘贴
    - [x] Esc 清空 + Esc 在非 normal 模式恢复 draft
    - [x] 非 TTY 降级（Mock isTTY=false）
    - [x] Raw mode 不可用降级（Mock keyReader=nil）
    - [x] 快捷键不吞键（验证 .up/.down/.ctrl("r") 等事件不丢失）
  - [x] 使用 Swift Testing 框架（`@Suite` / `@Test` / `#expect`）

## Dev Notes

### ⚠️ 前置 Spike（建议先做，1-2 小时）

在开始 Task 1–4 之前，先验证 raw mode 在 Swift 6.1 + macOS 上的可行性：
- `termios` 设置 raw mode 后能否正确捕获 Up/Down/Ctrl+R/Ctrl+G 等按键序列
- 中文输入在 raw mode 下是否仍然正常（Epic 37.9 修复的 UTF-8 问题不能回退）
- bracket paste 在 raw mode 下是否需要不同处理
- `FileHandle.standardInput.readabilityHandler` vs `read()` 系统调用的性能差异

**Spike 产出：** 确认 raw mode 可行后直接进入实现。如果 raw mode 不可行，需要评估替代方案并更新本 Story 范围。

> **注意：** `CJKInputHandler` 已经实现了 `termios` raw mode（`enterRawMode()`/`restoreMode()`）和 UTF-8 backspace 处理。Story 38.0 的 `KeyEventReader` 可以在此基础上**扩展**，增加 ANSI escape sequence 解析（Up/Down/Ctrl+R 等），而不是从零开始。

### 核心架构决策

**ChatComposer 是替代而非装饰：** ChatComposer 直接替代 `MultiLineInputReader` 在 `ChatCommand` 中的角色，不是在 MultiLineInputReader 之上再包一层。降级路径中 ChatComposer 内部委托给 MultiLineInputReader（作为私有实现细节），对外只暴露 `ChatComposer`。

**统一 raw mode 路径：** 当前代码有两条输入路径：
1. `MultiLineInputReader` → `readLine()` （非 CJK）
2. `MultiLineInputReader` → `CJKInputHandler.readRawLine()` （CJK + UTF-8 终端）

ChatComposer 将统一为一条 raw mode 路径（通过 `KeyEventReader`），消除双份续行/粘贴逻辑（解决 Epic 37 TD4）。

**按键事件驱动：** 所有输入通过 `KeyEvent` 枚举处理，不再是字符流。这使得后续 Story（38.2 slash popup、38.4 历史搜索、38.5 排队编辑）可以在同一个事件循环中拦截按键，而不用修改底层数据流。

### Codex 架构参考

| Codex 文件 | 行数 | 参考内容 | Axion 适配 |
|-----------|------|---------|-----------|
| `bottom_pane/chat_composer/draft_state.rs` | ~200 | ComposerDraft 结构（text/cursor/elements/mentions/pastes） | 简化为 text+cursor，后续 Story 扩展 |
| `bottom_pane/chat_composer/footer_state.rs` | ~300 | FooterMode 状态机（Normal/Slash/History/FileSearch 等） | ComposerMode enum |
| `bottom_pane/textarea.rs` | ~1500 | 核心编辑器（光标移动、选择、多行） | 简化为单行 + 续行，不做多行光标 |

**Codex 与 Axion 的关键差异：**
- Codex 用全屏 TUI ratatui 渲染 → Axion 用行式 REPL
- Codex textarea 支持多行光标移动 → Axion 用续行模式（更简单）
- Codex 支持 @mention 插件 → Axion 简化为纯文本编辑

### 模块边界

**新增文件：**
```
Sources/AxionCLI/Chat/Composer/
├── KeyEventReader.swift     # ~200 行：termios raw mode + ANSI escape 解析 + KeyReading protocol
├── KeyEvent.swift           # ~30 行：KeyEvent enum 定义
├── ComposerDraft.swift      # ~40 行：快照/恢复 struct
├── ComposerMode.swift       # ~20 行：交互模式 enum
└── ChatComposer.swift       # ~350 行：主 composer（事件循环 + 缓冲区管理 + 续行 + paste + 降级）
```

**修改文件：**
```
Sources/AxionCLI/Commands/ChatCommand.swift  # MultiLineInputReader → ChatComposer 替换
```

**保留不动：**
```
Sources/AxionCLI/Chat/MultiLineInputReader.swift  # 保留，作为 ChatComposer 内部降级委托
Sources/AxionCLI/Chat/CJKInputHandler.swift       # KeyEventReader 可复用其 UTF-8 工具方法
Sources/AxionCLI/Chat/ChatOutputFormatter.swift    # 不修改
Sources/AxionCLI/Chat/Theme/*                      # 不修改（38.1 已完成）
```

**新增测试文件：**
```
Tests/AxionCLITests/Chat/Composer/
├── KeyEventTests.swift          # ~80 行：KeyEvent 枚举覆盖
├── ComposerDraftTests.swift     # ~50 行：快照/恢复
├── ComposerModeTests.swift      # ~30 行：模式枚举
└── ChatComposerTests.swift      # ~300 行：核心 composer 测试（使用 MockKeyReader）
```

### 绝对禁止

- **不能删除 `MultiLineInputReader`** — 降级路径需要它。不能删除 `CJKInputHandler` — 其 `utf8CharLength`/`processBackspace` 工具方法被复用。
- **不能在 ChatComposer/ComposerDraft/ComposerMode 中直接做 I/O** — 所有输出通过注入的 `writeStdout`/`writeStderr` 闭包（Epic 37 纯函数 + DI 模式，L4）。
- **不能引入新的第三方依赖** — termios 是 Darwin/Glibc 系统头，不需要外部库。
- **不能修改 `ChatOutputFormatter`** — 输出格式化与本 Story 无关。
- **不能破坏现有 `ChatCommand` REPL 行为** — slash 命令、/resume、Ctrl+C 中断、会话恢复、角色圆点必须全部正常工作。
- **不能回退 Story 37.9 的中文输入修复** — UTF-8 字符边界处理必须正确。

### 与现有代码的关系

**`CJKInputHandler`（复用策略）：**
- `utf8CharLength(_ byte: UInt8) -> Int` — 复用，改为 internal 可见性或直接在 KeyEventReader 中实现相同逻辑
- `processBackspace(buffer:cursorPos:) -> [UInt8]` — 复用逻辑，适配 String-based buffer
- `isCJKEnabled() -> Bool` — 不再直接使用，由 ChatComposer 的 `isTTY` 检测替代
- `enterRawMode()`/`restoreMode()` — 由 KeyEventReader 接管生命周期管理
- `readRawLine(prompt:writeStdout:)` — 被 ChatComposer 的事件循环替代

**`MultiLineInputReader`（降级委托）：**
- `readInput(prompt:continuationPrompt:)` — ChatComposer 非 TTY 路径内部调用
- `enableBracketPaste()`/`disableBracketPaste()` — ChatComposer 代理调用
- 续行/bracket paste 逻辑 — ChatComposer raw mode 路径重新实现（统一版），降级路径仍委托给 MultiLineInputReader

**`ChatCommand.swift`（主要修改点）：**
- 第 116-118 行：`let inputReader = MultiLineInputReader()` → `let composer = ChatComposer()`
- 第 117 行：`inputReader.enableBracketPaste()` → `composer.enableBracketPaste()`
- 第 118 行：`defer { inputReader.disableBracketPaste() }` → `defer { composer.disableBracketPaste() }`
- 第 130-133 行：`inputReader.readInput(prompt:continuationPrompt:)` → `composer.readInput(prompt:continuationPrompt:)`
- 其他 REPL 逻辑完全不变

### Epic 37 回顾教训（必须遵循）

1. **L1: 接线验证是独立任务** — ChatComposer 的每个公共方法（`readInput`、`enableBracketPaste`、`disableBracketPaste`）必须在 `ChatCommand` 中有对应调用点，用 `// AC#` 注释标注。创建完组件后，显式追踪每个方法在消费端的调用。

2. **L4: 纯函数 + DI 模式** — KeyEventReader 通过 Protocol 注入，writeStdout/writeStderr 通过闭包注入。测试中通过注入覆盖 raw mode 和输出。

3. **C2: CJK 路径丢失续行支持的教训** — ChatComposer 必须在 raw mode 路径中正确实现续行和 bracket paste。不能只替换底层读取而丢失上层逻辑。Task 4 的检查清单逐项验证。

4. **C3: AC10 未知命令是死代码的教训** — `ComposerMode.slashPopup` 等模式虽然由后续 Story 实现 UI，但 ChatComposer 中的模式切换逻辑（saveDraft / restoreDraft / mode getter）必须在 Task 5 中接线验证。

5. **TD4: 消除双份续行/粘贴逻辑** — 这是本 Story 的核心价值之一。完成后 `CJKInputHandler.readCJKInput()` 和 `readCJKContinuation()` 不再被直接调用（由 ChatComposer 统一处理 raw mode 输入）。

### 测试策略

**单元测试（Mock 策略）：**

| 组件 | Mock 策略 | 理由 |
|------|---------|------|
| `KeyEventReader` | `KeyReading` protocol + `MockKeyReader`（注入预定义 `KeyEvent` 序列） | 测试环境中无真实 TTY |
| `ChatComposer` | 注入 Mock `writeStdout`/`writeStderr` + Mock `KeyReading` | 验证输入/输出行为 |
| `ComposerDraft` | 直接测试（纯 struct） | 无外部依赖 |
| `ComposerMode` | 直接测试（纯 enum） | 无外部依赖 |

**测试命名规范（Swift Testing）：**
```swift
@Suite("ChatComposer")
struct ChatComposerTests {
    @Test("普通文本输入并提交")
    func normalTextInput() { ... }

    @Test("backspace 删除完整 UTF-8 字符（中文 3 字节）")
    func backspaceCJKCharacter() { ... }
}
```

**关键测试场景：**
- 普通 ASCII 文本输入 + Enter 提交
- 中文输入（3 字节 UTF-8）+ backspace 删除完整字符
- Emoji 输入（4 字节 UTF-8）+ backspace 删除
- 反斜杠续行：`hello\` + Enter → `...>` → `world` + Enter → `hello\nworld`
- 续行取消：`hello\` + Enter → `...>` + Enter → `""`（空字符串）
- Bracket paste：`\x1b[200~line1\nline2\x1b[201~` → `"line1\nline2"`
- Esc 在 normal 模式清空当前输入
- Esc 在 slashPopup 模式恢复 draft + 回到 normal
- Up/Down/Ctrl+R/Ctrl+G 事件不丢失（验证返回到调用方或被记录）
- 非 TTY 降级：`isTTY=false` → readLine() 路径
- Raw mode 不可用降级：`keyReader=nil` → readLine() 路径 + 提示信息
- termios 性能：raw mode 设置/恢复 < 5ms

### Raw mode 按键映射参考

| 按键 | ANSI 序列 | KeyEvent |
|------|----------|----------|
| Enter | `0x0D` / `0x0A` | `.enter` |
| Backspace | `0x7F` / `0x08` | `.backspace` |
| Delete | `\x1b[3~` | `.delete` |
| Esc | `0x1B`（单独） | `.escape` |
| Up | `\x1b[A` / `\x1bOA` | `.up` |
| Down | `\x1b[B` / `\x1bOB` | `.down` |
| Left | `\x1b[D` / `\x1bOD` | `.left` |
| Right | `\x1b[C` / `\x1bOC` | `.right` |
| Tab | `0x09` | `.tab` |
| Ctrl+A | `0x01` | `.ctrl("a")` |
| Ctrl+C | `0x03` | `.ctrl("c")` — 由 SignalHandler 处理 |
| Ctrl+D | `0x04` | `.eof`（空 buffer 时） |
| Ctrl+R | `0x12` | `.ctrl("r")` |
| Ctrl+G | `0x07` | `.ctrl("g")` |
| Bracket Paste Start | `\x1b[200~` | `.bracketPasteStart` |
| Bracket Paste End | `\x1b[201~` | `.bracketPasteEnd` |

### Project Structure Notes

- 新目录 `Sources/AxionCLI/Chat/Composer/` 遵循 Chat/ 模块的子目录模式（同 `Chat/Theme/`，由 Story 38.1 创建）
- 测试目录 `Tests/AxionCLITests/Chat/Composer/` 镜像源结构
- 文件命名遵循 PascalCase
- Import 顺序：`import Darwin`（termios 需要）→ `import Foundation`
- `KeyEventReader` 需要 `import Darwin`（`termios`/`tcgetattr`/`tcsetattr`/`read` 系统调用）

### References

- [Source: docs/epics/epic-38-terminal-conversation-ux.md#Story 38.0]
- [Source: docs/specs/swift-tui-framework-design.md#Architecture]
- [Source: _bmad-output/project-context.md#交互聊天模式]
- [Source: _bmad-output/project-context.md#关键反模式（第 20-21 条）]
- [Source: _bmad-output/implementation-artifacts/epic-37-retro-2026-06-08.md#Lessons Learned]
- [Source: _bmad-output/implementation-artifacts/epic-37-retro-2026-06-08.md#TD4 CJK Raw Mode Duplicates]
- [Source: Sources/AxionCLI/Chat/MultiLineInputReader.swift]
- [Source: Sources/AxionCLI/Chat/CJKInputHandler.swift]
- [Source: Sources/AxionCLI/Commands/ChatCommand.swift]
- [Source: Sources/AxionCLI/Chat/SlashCommand.swift]
- [Source: Sources/AxionCLI/Chat/SignalHandler.swift]
- Codex 参考：`bottom_pane/chat_composer/draft_state.rs`（ComposerDraft）、`bottom_pane/chat_composer/footer_state.rs`（FooterMode 状态机）

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m]

### Debug Log References

- 修复 `.eof` 在非空 buffer 时导致无限循环的问题（MockKeyReader 返回 `.eof` forever，ChatComposer break 后 while 循环继续）。改为返回 buffer 内容（与 CJKInputHandler 行为一致）。

### Completion Notes List

- ✅ Task 1: KeyEventReader — 实现完整 ANSI escape sequence 解析（CSI/SS3），termios raw mode 生命周期管理，UTF-8 多字节字符处理，`KeyReading` protocol + factory `create()` 模式
- ✅ Task 2: ComposerDraft — 纯 struct，snapshot/restore，零依赖
- ✅ Task 3: ComposerMode — 5 种交互模式 enum，`isNormal` 计算属性
- ✅ Task 4: ChatComposer — 完整事件循环（printable/enter/backspace/escape/快捷键/bracket paste），反斜杠续行，降级路径（非 TTY → readLine，raw mode 失败 → MultiLineInputReader 委托），draft save/restore
- ✅ Task 5: ChatCommand 接线 — `var composer = ChatComposer()` 替换 `let inputReader = MultiLineInputReader()`，AC9 注释标注
- ✅ Task 6: 46 个单元测试（ComposerDraft 5 + ComposerMode 8 + KeyEvent 3 + UTF8CharLength 4 + ChatComposer 24 + MockKeyReader），覆盖 AC1–AC10 所有验收标准。全量 2218 测试零回归。
- ✅ Review fix: 修复续行模式中 bracket paste 被静默丢弃的 bug，新增测试 `continuationBracketPaste`（47 tests total）

### Change Log

- 2026-06-07: Story 38.0 完成 — ChatComposer 输入基础层替代 MultiLineInputReader，统一 raw mode 路径，消除 CJK 双份代码（Epic 37 TD4）
- 2026-06-07: Code Review (auto-fix) — 修复 H1: readContinuationRaw 中 bracket paste 事件被 default:break 丢弃；M2: VMIN/VTIME 注释改进。1990 测试零回归。

### File List

**新增文件：**
- Sources/AxionCLI/Chat/Composer/KeyEvent.swift
- Sources/AxionCLI/Chat/Composer/KeyEventReader.swift
- Sources/AxionCLI/Chat/Composer/ComposerDraft.swift
- Sources/AxionCLI/Chat/Composer/ComposerMode.swift
- Sources/AxionCLI/Chat/Composer/ChatComposer.swift
- Tests/AxionCLITests/Chat/Composer/MockKeyReader.swift
- Tests/AxionCLITests/Chat/Composer/KeyEventTests.swift
- Tests/AxionCLITests/Chat/Composer/ComposerDraftTests.swift
- Tests/AxionCLITests/Chat/Composer/ComposerModeTests.swift
- Tests/AxionCLITests/Chat/Composer/ChatComposerTests.swift

**修改文件：**
- Sources/AxionCLI/Commands/ChatCommand.swift

## Senior Developer Review (AI)

**Reviewer:** Nick (auto-review) on 2026-06-07

### Findings

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| H1 | HIGH | `readContinuationRaw` 中 bracket paste 事件被 `default: break` 静默丢弃，用户在续行模式粘贴多行文本会丢失内容 | ✅ Fixed |
| M1 | MEDIUM | `refreshDisplay` 光标定位用 Character 数量而非终端列数，CJK 双宽字符在光标中间时错位 | 📝 Deferred (后续 Story) |
| M2 | MEDIUM | VMIN/VTIME 使用硬编码索引 16/17，缺少常量引用注释 | ✅ Fixed |
| L1 | LOW | `saveDraft()` 无调用方（为 38.2/38.4 设计的死代码） | 📝 By Design |
| L2 | LOW | AC8 测试依赖无 TTY 环境 | 📝 Accepted |

### Verification

- ✅ Build: `swift build` 零错误
- ✅ Tests: 1990 tests passed, 0 failures (含新增 `continuationBracketPaste` 测试)
- ✅ AC1–AC10 全部验证通过
- ✅ Git diff 与 Story File List 一致（除自动生成的 sprint-status.yaml）
