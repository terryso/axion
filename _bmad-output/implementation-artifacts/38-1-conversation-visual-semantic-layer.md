---
baseline_commit: b00337b546e3900a35297fb759d2d8a311545f52
---

# Story 38.1: 对话视觉语义层

Status: review

## Story

As a Axion CLI 用户,
I want 用户提问、AI 回复、工具事件、审批事件在终端里有稳定的视觉标识,
so that 长对话中我能快速扫读上下文，而不是面对一整段连续文本。

## Acceptance Criteria

1. **AC1: 用户消息角色标识** — 用户发送消息后，终端左侧显示用户角色蓝色圆点 `●`，该轮消息主体与后续 assistant/tool block 明确分层。

2. **AC2: AI 回复角色标识** — assistant 流式输出时以 AI 角色绿色圆点样式输出，与工具调用、错误、审批请求有可区分视觉语义。同一轮 assistant 输出在视觉上组成一个 block（共享左侧绿色圆点标记）。

3. **AC3: 工具/审批角色标识** — tool call / tool result / approval request 输出时左侧或标题区域有固定语义标识（黄色圆点 `●` 标记工具，红色圆点 `●` 标记 warning/approval），颜色和图标的含义在整场会话中保持一致。

4. **AC4: 非 TTY 回退** — 终端不支持 ANSI 颜色（如 pipe 模式、`isatty()` 返回 false）时，回退为纯文本前缀标识（如 `[user]`、`[ai]`、`[tool]`、`[warn]`）。

5. **AC5: tmux/screen 兼容** — 在 tmux / screen 会话中运行 Axion 时，圆点正常渲染，不依赖 OSC 背景色查询，不出现背景色相关乱码。

6. **AC6: 窄终端兼容** — 终端宽度 < 40 列时，圆点仍正常显示，消息正文正常换行，不出现圆点与文字重叠或行错位。

7. **AC7: 颜色降级链** — 终端颜色探测结果缓存为 `TerminalColorProfile`，所有视觉输出通过 `ChatTheme` 统一适配。TrueColor 终端用精确 RGB 色，Ansi256 用最近色匹配，Ansi16 用 dim 回退，Unknown/无色终端回退纯文本前缀。

8. **AC8: NFR — 渲染性能** — 角色圆点渲染不增加可感知的输出延迟（单字符 ANSI 输出，< 1ms 额外开销）。

## Tasks / Subtasks

- [x] Task 1: 创建 `TerminalColorProfile` enum（AC7）
  - [x] 定义 enum: `trueColor | ansi256 | ansi16 | unknown`
  - [x] 实现启动探测：`detect()` 静态方法（检查 `TERM`、`COLORTERM`、`TERM_PROGRAM` 环境变量 + `isatty()` 检测）
  - [x] 实现 `ansiColor(for:)` 方法：将语义角色颜色（蓝/绿/黄/红）映射到对应 profile 的 ANSI 色码
  - [x] TrueColor: 24-bit RGB `\033[38;2;R;G;Bm`
  - [x] Ansi256: 216 色立方体 `\033[38;5;Nm` 最近色匹配
  - [x] Ansi16: 标准 16 色回退（blue=34, green=32, yellow=33, red=31）
  - [x] Unknown: 无颜色输出，回退纯文本

- [x] Task 2: 创建 `ChatTheme` struct（AC7）
  - [x] 接收 `TerminalColorProfile` + `isTTY: Bool`
  - [x] 提供 `formatRoleDot(role:)` → 带颜色的圆点字符串
  - [x] 提供 `formatPlainText(role:)` → 纯文本前缀 `[user]`/`[ai]`/`[tool]`/`[warn]`
  - [x] 提供 `formatBlock(role:content:)` → 完整的角色消息块格式化
  - [x] 提供 `separatorLine` → 块间分隔线（可选，dim 色 `───`）
  - [x] 纯函数/struct，无 I/O，全部计算属性和方法

- [x] Task 3: 创建 `TranscriptRenderer`（AC1/AC2/AC3）
  - [x] 定义 `TranscriptRole` enum: `user | assistant | tool | warning`
  - [x] 提供 `renderUserMessage(text:)` — 蓝色圆点 + 用户消息
  - [x] 提供 `renderAssistantBlockStart()` — 绿色圆点 + assistant block 开始
  - [x] 提供 `renderToolEvent(name:summary:duration:isError:)` — 黄色圆点 + 工具事件
  - [x] 提供 `renderWarning(message:)` — 红色圆点 + 警告/审批
  - [x] 提供 `renderResult(subtype:)` — 结果状态（复用现有 ⚠️/❌ 图标 + 红色圆点）
  - [x] 所有方法接受 `ChatTheme` 参数，输出格式化字符串
  - [x] 纯函数，无 I/O

- [x] Task 4: 修改 `ChatOutputFormatter` 集成 TranscriptRenderer（AC1/AC2/AC3）
  - [x] 新增 `theme: ChatTheme` 属性（init 注入）
  - [x] 新增 `transcriptRenderer: TranscriptRenderer` 属性
  - [x] 新增 `assistantBlockStarted: Bool` 状态追踪 — 同一轮 assistant 输出共享圆点标记
  - [x] 修改 `handle(.toolUse)` — 用 `renderToolEvent` 替代现有 `⏳` + `✅`/`❌` 格式
  - [x] 修改 `handle(.toolResult)` — 用 `renderToolEvent` 替代
  - [x] 修改 `handle(.result)` — warning 类型用 `renderWarning`
  - [x] 修改 `handle(.system .paused*)` — 用 `renderWarning`
  - [x] 保持 `.partialMessage` / `.assistant` 直接输出文本不变（LLM 文本不加前缀）
  - [x] assistant block 生命周期：收到 `.toolUse` 或 `.result` 时重置 `assistantBlockStarted`

- [x] Task 5: 修改 `ChatCommand` REPL 循环集成用户消息标识（AC1）
  - [x] 在用户消息发送前（`agent.stream(trimmed)` 调用前），输出用户角色圆点 + 消息预览
  - [x] 使用 `TranscriptRenderer.renderUserMessage(text:)` 格式化
  - [x] 输出到 stderr（与 prompt 一致），不混入 agent stream 输出

- [x] Task 6: 编写单元测试（AC1–AC8）
  - [x] `TerminalColorProfileTests`: 各 profile 的 `ansiColor(for:)` 返回正确 ANSI 码
  - [x] `ChatThemeTests`: `formatRoleDot` / `formatPlainText` / `formatBlock` 各 role 正确
  - [x] `ChatThemeTests`: unknown profile 回退纯文本前缀
  - [x] `TranscriptRendererTests`: 各 `render*` 方法输出包含正确角色标识
  - [x] `TranscriptRendererTests`: 窄终端 < 40 列不崩溃、圆点正常
  - [x] `ChatOutputFormatterTests`: 修改后的 formatter 仍通过现有测试 + 新增角色标识测试
  - [x] 性能测试：`formatRoleDot` < 1ms

## Dev Notes

### 核心设计决策

**圆点方案（已确定为最终方案）：** 采用左侧彩色实心圆点 `●` 作为角色视觉标识，替代 Codex 的微妙背景色方案。

选择圆点的理由：
1. 圆点在所有终端类型（TrueColor / Ansi256 / Ansi16 / 无色）下都可靠渲染
2. 背景色在许多终端模拟器中不可靠（tmux、screen、某些 SSH 客户端不支持 OSC 背景色查询）
3. 圆点在窄终端（< 40 列）下仍可辨识，背景色在窄终端下可能破坏布局

角色圆点颜色方案：
| 角色 | 颜色 | 圆点 | Ansi16 码 | 纯文本回退 |
|------|------|------|-----------|-----------|
| 用户 | 蓝色 | `●` | `\033[34m` | `[user]` |
| AI | 绿色 | `●` | `\033[32m` | `[ai]` |
| 工具 | 黄色 | `●` | `\033[33m` | `[tool]` |
| 警告/审批 | 红色 | `●` | `\033[31m` | `[warn]` |

### 架构约束

**模块边界：**
- 所有新文件放在 `Sources/AxionCLI/Chat/Theme/` 目录
- `TerminalColorProfile` 和 `ChatTheme` 是纯 struct/enum，零外部依赖（仅 Foundation）
- `TranscriptRenderer` 是纯函数 struct，仅依赖 `ChatTheme`
- `ChatOutputFormatter` 修改仅限注入 `ChatTheme` + 调用 `TranscriptRenderer` 方法

**绝对禁止：**
- 不能在 `TranscriptRenderer` 或 `ChatTheme` 中做任何 I/O（fputs/print/write）
- 不能引入新的第三方依赖
- 不能修改 `MarkdownTerminalRenderer` 或 `SpinnerRenderer`（本 Story 不涉及）
- 不能破坏现有 `ChatOutputFormatterTests` 中的断言——角色圆点是**增量添加**，不是替换现有 `⏳`/`✅`/`❌` 图标

### 与现有代码的关系

**`ChatOutputFormatter`（主要修改文件）：**
当前格式化输出流程：
```
用户消息 → 无标识（直接发给 agent）
LLM 文本 → 直接 fputs（无前缀）
工具调用 → ⏳ <name>: <summary>
工具结果 → ✅ <summary> [duration] / ❌ <summary>
结果状态 → ⚠️ 提示 / ❌ 错误
```

修改后：
```
用户消息 → 🔵 用户消息预览（在 agent.stream() 前输出到 stderr）
LLM 文本 → 直接 fputs（无前缀，不加圆点——流式 token 不适合加静态标记）
工具调用 → 🟡 ⏳ <name>: <summary>（黄色圆点 + 现有格式）
工具结果 → 🟡 ✅ <summary> [duration] / 🟡 ❌ <summary>（黄色圆点 + 现有格式）
结果状态 → 🔴 ⚠️ 提示 / 🔴 ❌ 错误（红色圆点 + 现有格式）
```

**关键：LLM 流式文本不加前缀圆点。** 理由：
1. 流式 `.partialMessage` 是逐 token 输出，每加一个前缀会导致重复
2. assistant block 的圆点应在 block 开始时输出一次（在首个 `.partialMessage` 或 `.toolUse` 前由调用方控制）
3. Codex 的做法是 AI 消息靠缩进和 dim `•` 前缀区分，但 Axion REPL 模式下流式输出加前缀不实际

**实际做法：** assistant block 的圆点标记在 `ChatCommand` REPL 循环中输出——在调用 `agent.stream(trimmed)` 前输出用户圆点，在 `outputHandler.handle(.partialMessage)` 首次调用时输出 AI 圆点。

### 颜色探测策略

不使用 Codex 的 OSC 10/11 背景色查询（在 tmux/screen 中不可靠）。使用**环境变量探测**：

```swift
static func detect() -> TerminalColorProfile {
    guard isatty(STDOUT_FILENO) != 0 else { return .unknown }

    let colorterm = ProcessInfo.processInfo.environment["COLORTERM"]
    if colorterm == "truecolor" || colorterm == "24bit" { return .trueColor }

    let term = ProcessInfo.processInfo.environment["TERM"] ?? ""
    if term.hasPrefix("xterm-256color") || term.hasPrefix("screen-256color")
       || term.hasPrefix("tmux-256color") { return .ansi256 }

    if term.hasPrefix("xterm") || term.hasPrefix("vt") || term.hasPrefix("linux") { return .ansi16 }

    return .ansi16  // 默认安全回退
}
```

**注意：** tmux 环境下 `TERM` 通常为 `tmux-256color` 或 `screen-256color`，会正确探测为 `.ansi256`。SSH 连接时环境变量透传，也能正确探测。

### 零宽度问题

圆点 `●` (U+25CF BLACK CIRCLE) 在所有现代终端中宽度为 1。但需要确认：
- tmux 中宽度正确（tmux 的 Unicode 宽度表可能不同）
- 窄终端中圆点不会导致行溢出（测试 AC6）

**实现建议：** 圆点后紧跟一个空格 `● ` 共 2 字符宽度。在 < 40 列终端中仍可正常显示。

### 纯函数 + DI 模式

遵循 Epic 37 建立的 Chat/ 模块架构模式（Epic 37 回顾 L4）：
- `TerminalColorProfile.detect()` — 静态方法，可通过注入 `detectFn: () -> TerminalColorProfile` 覆盖
- `ChatTheme` — 纯 struct，无状态
- `TranscriptRenderer` — 纯 struct，无状态，所有方法返回 String
- 测试中通过注入 Mock `detectFn` 覆盖颜色探测

### 文件清单

**新增文件：**
```
Sources/AxionCLI/Chat/Theme/
├── TerminalColorProfile.swift   # ~80 行：enum + detect() + ansiColor()
├── ChatTheme.swift              # ~60 行：struct，角色颜色映射 + 格式化
└── TranscriptRenderer.swift     # ~100 行：struct，角色消息块渲染

Tests/AxionCLITests/Chat/Theme/
├── TerminalColorProfileTests.swift   # ~120 行
├── ChatThemeTests.swift              # ~100 行
└── TranscriptRendererTests.swift     # ~150 行
```

**修改文件：**
```
Sources/AxionCLI/Chat/ChatOutputFormatter.swift   # 注入 ChatTheme + 集成 TranscriptRenderer
Sources/AxionCLI/Commands/ChatCommand.swift        # 用户消息圆点输出 + ChatTheme 初始化
Tests/AxionCLITests/Chat/TerminalOutputTests.swift # 新增角色标识测试
```

### Epic 37 回顾教训（必须遵循）

1. **L1: 接线验证是独立任务** — 每个新函数必须在 `ChatCommand` / `ChatOutputFormatter` 中有对应调用点，用 `// AC#` 注释标注。创建完组件后，显式追踪每个方法在消费端的调用。

2. **L4: 纯函数 + DI 模式** — 所有新组件（TerminalColorProfile、ChatTheme、TranscriptRenderer）必须使用纯函数或注入闭包。测试中通过注入覆盖颜色探测。

3. **C3: AC10 未知命令是死代码的教训** — 确保 `ChatTheme` 和 `TranscriptRenderer` 的每个公共方法都在 `ChatOutputFormatter` 或 `ChatCommand` 中有实际调用。

4. **TD3: MarkdownTerminalRenderer 未接线** — 本 Story 的 `TranscriptRenderer` 必须立即接线到 `ChatOutputFormatter`，不能留下"已实现但未使用"的组件。

### 测试策略

**单元测试（Mock 策略）：**

| 组件 | Mock 策略 | 理由 |
|------|---------|------|
| `TerminalColorProfile.detect()` | 注入 `detectFn` 闭包覆盖 | 避免探测真实终端环境 |
| `ChatTheme` | 直接测试（纯 struct） | 无外部依赖 |
| `TranscriptRenderer` | 直接测试（纯 struct） | 无外部依赖 |
| `ChatOutputFormatter` | 注入 Mock `writeStdout`/`writeStderr` + Mock `ChatTheme` | 验证角色标识输出 |

**测试命名规范（Swift Testing）：**
```swift
@Suite("TerminalColorProfile")
struct TerminalColorProfileTests {
    @Test("trueColor: 蓝色角色返回 24-bit RGB ANSI 码")
    func trueColorBlueRole() { ... }
}
```

**关键测试场景：**
- 各 profile 下的角色圆点颜色正确性
- unknown profile 回退纯文本前缀（无 ANSI 码）
- 非 TTY (`isatty=false`) 时使用纯文本
- 窄终端（< 40 列）下 `formatBlock` 不崩溃
- `ChatOutputFormatter` 在角色圆点集成后仍输出工具摘要（向后兼容）
- tmux 环境变量 (`TERM=tmux-256color`) 正确探测为 `.ansi256`

### Codex 参考文件（仅参考，不照搬）

| Codex 文件 | 行数 | 参考内容 |
|-----------|------|---------|
| `tui/src/color.rs` | ~150 | 颜色混合、亮度检测、perceptual_distance |
| `tui/src/style.rs` | ~100 | 自适应样式 |
| `tui/src/terminal_palette.rs` | ~200 | 颜色降级链（TrueColor→Ansi256→Ansi16） |
| `tui/src/history_cell/messages.rs` | ~300 | 角色样式 |
| `tui/src/status_indicator_widget.rs` | ~300 | 状态指示器格式 |

**Codex 与 Axion 的关键差异：**
- Codex 用背景色区分角色 → Axion 用圆点（更可靠）
- Codex 通过 OSC 10/11 探测背景亮度 → Axion 通过环境变量探测颜色能力（更安全）
- Codex 是全屏 TUI → Axion 是行式 REPL（圆点方案更适合行式输出）

### Project Structure Notes

- 新目录 `Sources/AxionCLI/Chat/Theme/` 遵循 Chat/ 模块的子目录模式
- 测试目录 `Tests/AxionCLITests/Chat/Theme/` 镜像源结构
- 文件命名遵循 PascalCase（`TerminalColorProfile.swift`、`ChatTheme.swift`、`TranscriptRenderer.swift`）
- Import 顺序：`Foundation`（仅依赖）

### References

- [Source: docs/epics/epic-38-terminal-conversation-ux.md#Story 38.1]
- [Source: docs/specs/swift-tui-framework-design.md#Architecture]
- [Source: _bmad-output/project-context.md#交互聊天模式]
- [Source: _bmad-output/implementation-artifacts/epic-37-retro-2026-06-08.md#Lessons Learned]
- [Source: Sources/AxionCLI/Chat/ChatOutputFormatter.swift]
- [Source: Sources/AxionCLI/Chat/MarkdownTerminalRenderer.swift]
- [Source: Sources/AxionCLI/Chat/SpinnerRenderer.swift]
- [Source: Sources/AxionCLI/Commands/ChatCommand.swift]
- [Source: Tests/AxionCLITests/Chat/TerminalOutputTests.swift]

### ATDD Artifacts

- Checklist: `_bmad-output/test-artifacts/atdd-checklist-38-1-conversation-visual-semantic-layer.md`
- Unit tests:
  - `Tests/AxionCLITests/Chat/Theme/TerminalColorProfileTests.swift` (~120 行, 16 测试)
  - `Tests/AxionCLITests/Chat/Theme/ChatThemeTests.swift` (~100 行, 16 测试)
  - `Tests/AxionCLITests/Chat/Theme/TranscriptRendererTests.swift` (~150 行, 16 测试)
  - `Tests/AxionCLITests/Chat/Theme/TranscriptIntegrationTests.swift` (~150 行, 10 测试)

## Dev Agent Record

### Agent Model Used
GLM-5.1

### Debug Log References
无调试问题。

### Completion Notes List
- Task 1: TerminalColorProfile enum 实现。支持 TrueColor/Ansi256/Ansi16/Unknown 四级降级链，通过环境变量探测（COLORTERM, TERM）+ isTTY 检测。纯函数，无 I/O。
- Task 2: ChatTheme struct 实现。formatRoleDot/formatPlainText/formatBlock/separatorLine 四个核心方法。TTY+颜色→ANSI圆点；非TTY或unknown→纯文本前缀。纯 struct，无 I/O。
- Task 3: TranscriptRenderer + TranscriptRole 实现。TranscriptRole 四种角色（user/assistant/tool/warning），TranscriptRenderer 五个 render 方法。纯函数 struct。
- Task 4: ChatOutputFormatter 集成。theme 可选注入（nil 保持原行为向后兼容）。toolUse→黄色圆点+⏳，toolResult success→黄色圆点+✅，toolResult error→红色圆点+❌，result warning→红色圆点，system paused→红色圆点。assistantBlockStarted 追踪首次 partialMessage 输出 AI 圆点。
- Task 5: ChatCommand REPL 集成。在 agent.stream(trimmed) 前创建 ChatTheme + TranscriptRenderer，输出用户消息蓝色圆点到 stderr。
- Task 6: 测试全部通过。91 个 Chat+Theme 测试（含 66 个新增 Theme 测试），2173 个全量单元测试零回归。
- 修复测试文件编译错误：TranscriptIntegrationTests 中 TokenUsage nil 推断、SystemData init 缺 message 参数、Int64 转换。

### File List

**新增文件：**
- Sources/AxionCLI/Chat/Theme/TerminalColorProfile.swift
- Sources/AxionCLI/Chat/Theme/ChatTheme.swift
- Sources/AxionCLI/Chat/Theme/TranscriptRenderer.swift

**修改文件：**
- Sources/AxionCLI/Chat/ChatOutputFormatter.swift
- Sources/AxionCLI/Commands/ChatCommand.swift
- Tests/AxionCLITests/Chat/Theme/TranscriptRendererTests.swift (修复 Int64 转换)
- Tests/AxionCLITests/Chat/Theme/TranscriptIntegrationTests.swift (修复编译错误)

## Change Log

- 2026-06-07: 完成对话视觉语义层实现 — TerminalColorProfile + ChatTheme + TranscriptRenderer + ChatOutputFormatter/ChatCommand 集成 (Story 38-1)
