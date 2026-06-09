---
story_id: 37.6
epic: 37
title: 多行输入支持
status: done
created: 2026-06-07
baseline_commit: c37d8f0c9bc32fb6e0353043fc08e7608b2c31b9
---

# Story 37.6: 多行输入支持

As a CLI 用户,
I want 能粘贴多行代码片段或用反斜杠续行,
So that 我可以输入复杂的 prompt 而不需要写成一行.

## Acceptance Criteria

1. **AC1 — 反斜杠续行**：用户在 `axion>` 提示符下输入 `print(\` + 回车，显示 `...>` 续行提示，用户继续输入 `)` + 回车后，两行合并为 `print()` 发送给 agent

2. **AC2 — Bracket Paste 多行粘贴**：用户从剪贴板粘贴一段多行代码（终端支持 bracket paste mode），整段代码作为一条消息发送给 agent，不按行拆分

3. **AC3 — TTY 检测与非交互降级**：管道/重定向输入模式下不启用 bracket paste mode 和续行，保持原有 `readLine()` 行为

4. **AC4 — Bracket Paste 生命周期**：进入 REPL 时启用 bracket paste mode (`\e[?2004h`)，退出时恢复 (`\e[?2004l`)，异常退出（SIGKILL 等）不残留终端状态

5. **AC5 — 无回归**：`axion run "task"` 行为完全不受影响；slash 命令、Ctrl+C 中断、权限审批、Banner、输出格式化等现有功能正常

6. **AC6 — 续行取消**：续行模式下（`...>` 提示符）输入空行（直接回车），取消本次续行，丢弃已输入内容，回到 `axion>` 提示符

## Tasks / Subtasks

- [x] Task 1: 创建 MultiLineInputReader 组件 (AC: #1, #2, #3, #6)
  - [x] 1.1 新建 `Sources/AxionCLI/Chat/MultiLineInputReader.swift`
  - [x] 1.2 实现 `struct MultiLineInputReader` — 封装多行输入读取逻辑
  - [x] 1.3 实现 `static func isTTY() -> Bool` — `isatty(STDIN_FILENO) != 0`
  - [x] 1.4 实现 `func readInput(prompt: String, continuationPrompt: String) -> String?` — 主入口方法
  - [x] 1.5 实现 bracket paste 检测：解析 `\u{1B}[200~` / `\u{1B}[201~` 包裹的内容
  - [x] 1.6 实现反斜杠续行：行末 `\` + 回车 → 累积续行，显示 `...>` 提示符
  - [x] 1.7 实现续行取消：续行模式下空行输入 → 返回空字符串（取消信号）
  - [x] 1.8 非 TTY 模式：直接调用 `readLine()`，不处理 bracket paste 和续行

- [x] Task 2: Bracket Paste Mode 生命周期管理 (AC: #4)
  - [x] 2.1 实现 `enableBracketPaste()` — 输出 `\u{1B}[?2004h` 到 stderr
  - [x] 2.2 实现 `disableBracketPaste()` — 输出 `\u{1B}[?2004l` 到 stderr
  - [x] 2.3 在 `ChatCommand` REPL 循环开始前调用 `enableBracketPaste()`
  - [x] 2.4 在 `ChatCommand` 退出路径（正常退出、double Ctrl+C、异常）调用 `disableBracketPaste()`
  - [x] 2.5 使用 `defer` 确保异常退出时也恢复终端状态

- [x] Task 3: 集成到 ChatCommand REPL 循环 (AC: #1-#6)
  - [x] 3.1 在 `ChatCommand.run()` 中创建 `MultiLineInputReader` 实例
  - [x] 3.2 替换现有 `readLine(strippingNewline: true)` 为 `reader.readInput(prompt:continuationPrompt:)`
  - [x] 3.3 处理返回值：`nil` → EOF 或取消（续行取消时 `continue`，EOF 时 `break`）
  - [x] 3.4 确保返回的完整输入传递给 slash 命令检查和 `agent.stream()`
  - [x] 3.5 验证 TTY 检测：管道输入 `echo "hello" | axion chat` 仍正常工作

- [x] Task 4: 单元测试 (AC: #1, #2, #3, #6)
  - [x] 4.1 新建 `Tests/AxionCLITests/Chat/MultiLineInputReaderTests.swift`
  - [x] 4.2 测试反斜杠续行：单行无 `\` 直接返回
  - [x] 4.3 测试反斜杠续行：行末 `\` + 下一行输入 → 合并（去除 `\` 和换行）
  - [x] 4.4 测试反斜杠续行：多级续行（3 行 `\` 续行）
  - [x] 4.5 测试续行取消：续行模式下空行输入 → 取消信号
  - [x] 4.6 测试 bracket paste 检测：`\u{1B}[200~...\u{1B}[201~` → 内容原样返回
  - [x] 4.7 测试 bracket paste 检测：无包裹序列 → 正常 readLine 行为
  - [x] 4.8 测试非 TTY 降级：`isTTY: false` 时直接 readLine，不处理 paste/续行
  - [x] 4.9 测试终端恢复：`enableBracketPaste` / `disableBracketPaste` 输出正确 ANSI 序列

## Dev Notes

### 当前代码位置

**ChatCommand.swift 第 116 行 — 输入读取点：**
```swift
guard let line = readLine(strippingNewline: true) else {
    // readLine returns nil — check if SIGINT caused it (AC3)
    if SignalHandler.fireCount() > 0 {
        lastInterruptTime = ContinuousClock.now
        continue  // AC3: idle Ctrl+C → new prompt
    }
    break
}
let trimmed = line.trimmingCharacters(in: .whitespaces)
```

这是**唯一的修改点** — 将 `readLine()` 替换为 `MultiLineInputReader.readInput()`。

**ChatCommand.swift 第 107-179 行 — REPL 主循环：** 不改变循环结构，仅替换输入读取方式。

**SignalHandler.swift** — 已有 SIGINT 处理。续行模式下的 Ctrl+C 由同一 handler 处理（`readLine()` 返回 `nil`），逻辑不变。

### Bracket Paste Mode 技术细节

终端 bracket paste mode 是 xterm/iTerm2/Terminal.app/WezTerm 等主流终端支持的标准功能：

- **启用**：向终端输出 `\x1b[?2004h`
- **禁用**：向终端输出 `\x1b[?2004l`
- **粘贴开始标记**：`\x1b[200~`
- **粘贴结束标记**：`\x1b[201~`
- 用户手动输入时，终端不发送这些标记；只有粘贴操作才会包裹

**关键：** `readLine()` 不会解析 ANSI escape sequences — 当终端发送 `\x1b[200~hello\nworld\x1b[201~` 时，`readLine()` 会在 `\n` 处截断，只返回 `\x1b[200~hello`。所以**不能用 `readLine()`** 来读取 bracket paste 内容。

### 实现架构

```
MultiLineInputReader
  │
  ├── isTTY: Bool (注入，便于测试)
  ├── readLineFn: () -> String? (注入，便于测试)
  │
  ├── readInput(prompt:continuationPrompt:) → String?
  │       │
  │       ├── 非 TTY → readLineFn() 直接返回
  │       │
  │       ├── TTY 模式:
  │       │       readLineFn() → 检查内容
  │       │       │
  │       │       ├── 包含 \x1b[200~ → bracket paste 模式
  │       │       │       累积读取直到 \x1b[201~
  │       │       │       去除包裹标记，合并为单条
  │       │       │
  │       │       ├── 行末有 \ → 续行模式
  │       │       │       去除 \，显示 continuationPrompt
  │       │       │       继续读取下一行
  │       │       │       空行 → 取消（返回特殊信号）
  │       │       │
  │       │       └── 普通输入 → 直接返回
  │       │
  │       └── nil → EOF
  │
  ├── enableBracketPaste() → fputs("\x1b[?2004h", stderr)
  └── disableBracketPaste() → fputs("\x1b[?2004l", stderr)
```

### Bracket Paste 读取策略

由于 `readLine()` 会在 `\n` 处截断，bracket paste 的多行内容会被拆成多次 `readLine()` 调用。策略：

1. 第一次 `readLine()` 返回以 `\x1b[200~` 开头的内容 → 进入 paste 累积模式
2. 继续调用 `readLine()` 累积每一行，直到某行以 `\x1b[201~` 结尾
3. 去除首尾 ANSI 标记，将所有行用 `\n` 连接
4. 整段作为一条输入返回

```swift
// 示例：粘贴 3 行代码
// 第一次 readLine: "\u{1B}[200~line1"
// 第二次 readLine: "line2"
// 第三次 readLine: "line3\u{1B}[201~"
// 结果: "line1\nline2\nline3"
```

### 续行逻辑细节

```swift
// 单行无续行
"hello" → "hello"

// 行末 \ 续行（去除 \ 和换行，合并）
"print(\" → 显示 "...>" 续行提示
  "hello)" → 合并为 "print(hello)"

// 多级续行
"func foo(" → 显示 "...>"
  "  bar: String," → 显示 "...>"
  "  baz: Int" → 显示 "...>"
  ")" → 合并为 "func foo(\n  bar: String,\n  baz: Int\n)"

// 续行取消：空行
"print(\" → 显示 "...>"
  "" → 取消，丢弃 "print("，回到主提示符
```

**注意：** 续行合并时，用 `\n` 连接各部分（保留原始换行），但去除行末的 `\` 字符。

### ChatCommand 修改方案

```swift
// 替换第 114-116 行
// 旧代码:
// fputs(prompt, stdout); fflush(stdout)
// guard let line = readLine(strippingNewline: true) else { ... }

// 新代码:
let reader = MultiLineInputReader()
guard let fullInput = reader.readInput(
    prompt: prompt,
    continuationPrompt: "...> "
) else {
    // nil — check if SIGINT caused it (AC3)
    if SignalHandler.fireCount() > 0 {
        lastInterruptTime = ContinuousClock.now
        continue
    }
    break
}
let trimmed = fullInput.trimmingCharacters(in: .whitespaces)
```

在 REPL 循环**之前**启用 bracket paste：
```swift
let reader = MultiLineInputReader()
reader.enableBracketPaste()
defer { reader.disableBracketPaste() }
```

### Bracket Paste 启用位置

```
ChatCommand.run()
  │
  ├── ... 构建 buildResult, 显示 Banner ...
  │
  ├── let reader = MultiLineInputReader()
  ├── reader.enableBracketPaste()           // ← 启用
  ├── defer { reader.disableBracketPaste() } // ← 确保退出时恢复
  │
  ├── while true { ... REPL ... }
  │
  ├── SignalHandler.uninstall()
  └── try? await buildResult.agent.close()
  // defer 自动执行 reader.disableBracketPaste()
```

### 关键设计决策

1. **依赖注入 readLineFn** — 不直接调用 `readLine()`，通过闭包注入，便于测试（Mock 为预设输入序列）。同模式参考 `PermissionHandler.createCanUseTool(readUserInput:)`。

2. **续行取消返回特殊值** — 续行模式下空行输入不应视为 EOF，需要一个区分"取消续行"和"EOF"的信号。方案：`readInput` 返回 `String?`，nil = EOF；续行取消时返回空字符串 `""`（与正常输入区分，空输入在后续 `trimmed.isEmpty` 检查中被跳过）。

3. **Bracket paste 检测是启发式的** — 检查 `readLine()` 返回内容是否以 `\u{1B}[200~` 开头。如果终端不支持 bracket paste mode（或用户手动输入了这些字符），行为会退化到普通文本处理，不会崩溃。

4. **不在 `readInput` 中处理 SIGINT** — SignalHandler 已在 REPL 循环层管理 SIGINT。`readInput` 只负责读取输入，Ctrl+C 导致 `readLine()` 返回 nil 的逻辑在 ChatCommand 层处理（现有逻辑不变）。

5. **`enableBracketPaste` 输出到 stderr** — 与 BannerRenderer、PermissionHandler 保持一致（stderr 用于控制序列，stdout 用于数据输出）。

6. **MultiLineInputReader 是 struct** — 无状态（除注入的闭包），纯函数式设计，线程安全。

### 关键反模式（必须避免）

1. **不要修改 `RunCommand`** — `axion run "task"` 不受影响，不使用 `MultiLineInputReader`
2. **不要使用 `print()`** — 控制序列用 `fputs()` + `stderr`/`stdout`（project-context.md 反模式 #3）
3. **不要在 `readInput` 中直接调用 `isatty()`** — 通过构造器注入 `isTTY` 参数，便于测试
4. **不要忘记 `defer` 恢复终端** — bracket paste mode 未恢复会导致终端行为异常（粘贴时出现 `0~` `1~` 标记）
5. **不要在非 TTY 模式下输出 ANSI 序列** — 管道/重定向时跳过 bracket paste 启用/禁用
6. **不要用 `FileHandle.standardInput` 替代 `readLine()`** — `readLine()` 是阻塞的同步调用，适合 REPL 场景；`FileHandle` 的异步读取增加了不必要的复杂度
7. **不要阻塞 REPL 主线程** — 续行模式下的 `readLine()` 调用是同步的，与现有 REPL 循环一致

### 测试策略

- **单元测试（必须 Mock）：**
  - `MultiLineInputReader` — 通过注入 `isTTY` 和 `readLineFn` 闭包来测试
  - 反斜杠续行 — 单行、多级续行、续行取消
  - Bracket paste 检测 — 有/无包裹序列
  - 非 TTY 降级 — 不处理 paste/续行
  - 终端恢复 — enable/disable 输出正确序列
  - **Mock 策略：** 注入 `readLineFn` 返回预设输入序列（`["line1\\", "line2", nil]`），注入 `isTTY` 控制模式

- **不写集成测试** — 不启动真实终端

### Project Structure Notes

- 新文件 `MultiLineInputReader.swift` 放在 `Sources/AxionCLI/Chat/` 目录（与 BannerRenderer、SlashCommand、SignalHandler、ChatOutputFormatter、PermissionHandler 同级）
- 测试文件放在 `Tests/AxionCLITests/Chat/MultiLineInputReaderTests.swift`（镜像源结构）
- 使用 Swift Testing 框架（`import Testing`、`@Suite`、`@Test`、`#expect`）

### References

- [Source: docs/epics/epic-37-interactive-chat-mode.md#Story 37.6] — 完整 story 定义和 AC
- [Source: Sources/AxionCLI/Commands/ChatCommand.swift:116] — 当前 `readLine()` 调用位置
- [Source: Sources/AxionCLI/Commands/ChatCommand.swift:107-179] — REPL 主循环
- [Source: Sources/AxionCLI/Chat/PermissionHandler.swift:25] — `isatty()` 注入模式参考
- [Source: Sources/AxionCLI/Chat/SpinnerRenderer.swift:14] — `isatty()` 使用参考
- [Source: Sources/AxionCLI/Chat/SignalHandler.swift] — SIGINT 处理器（不需修改）
- [Source: _bmad-output/implementation-artifacts/37-5-permission-approval-mechanism.md] — Story 37.5 完成记录（前序 story）
- [Bracket Paste Mode 规范] — xterm extension #2004，所有主流终端支持

### Previous Story Intelligence (37.5)

- **PermissionHandler 已完成** — 使用闭包注入模式（`readUserInput`、`isTTY`），MultiLineInputReader 应复用同一模式
- **ChatCommand 结构已稳定** — ~197 行，REPL 循环 + signal handler + slash commands + permission mode
- **isatty() 已有注入先例** — `PermissionHandler.createCanUseTool(isTTY:)` 和 `SpinnerRenderer.init(isTTY:)`
- **28 个 PermissionHandler 测试** — 注入闭包的测试模式可参考
- **BuildConfig 已有 permissionMode/canUseTool** — MultiLineInputReader 不影响 BuildConfig

### Previous Story Intelligence (37.4)

- **ChatOutputFormatter 已完成** — 实现 `SDKMessageOutputHandler` 协议，处理流式输出
- **SDKTerminalOutputHandler 在 ChatCommand 不再使用** — 已替换为 ChatOutputFormatter

### Previous Story Intelligence (37.3)

- **BannerRenderer 已完成** — 纯函数 struct，static methods
- **renderPrompt()** — 返回 `axion [Xk/Yk]> ` 格式提示符

### Previous Story Intelligence (37.2)

- **SignalHandler 已完成** — DispatchSource 模式，agent.interrupt() 回调
- **lastInterruptTime** — 双击退出检测变量

### Previous Story Intelligence (37.1)

- **Slash 命令系统已完成** — 8 个命令 + 未知命令拦截
- **Chat/ 目录已创建** — 所有 Chat 组件文件在此目录

### Previous Story Intelligence (37.0)

- **Coding Agent 系统提示已完成** — `coding-agent-system.md` 模板
- **CLAUDE.md 加载** — `buildCodingSystemPrompt()` 已实现
- **maxTokens: 131_072** — 128K 输出

### Git Intelligence

最近 5 个提交：
- `c37d8f0` feat(story-37.5): 权限审批机制 — 新增 PermissionHandler.swift，修改 ChatCommand (flags + canUseTool)，修改 AgentBuilder (BuildConfig + build)，修改 SlashCommandHandler (动态 permissionMode)
- `9f71692` feat(story-37.4): 终端输出优化 — 新增 ChatOutputFormatter + MarkdownTerminalRenderer + SpinnerRenderer
- `9c7e56f` feat(story-37.3): 启动横幅 + 会话信息 — 新增 BannerRenderer
- `3cb12d6` feat(story-37.2): Ctrl+C 优雅中断 — 新增 SignalHandler
- `aff3118` feat(story-37.1): Slash 命令体系 — 新增 SlashCommand + SlashCommandHandler

本 Story 37.6 修改 ChatCommand（替换 readLine 为 MultiLineInputReader），新增 MultiLineInputReader.swift 独立文件。与 SlashCommand、SignalHandler、PermissionHandler 等 Chat 组件互不干扰。

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m]

### Debug Log References

无调试问题。

### Completion Notes List

- ✅ **Task 1 完成**: 创建 `MultiLineInputReader.swift` — struct 封装多行输入读取，支持反斜杠续行、bracket paste 检测、续行取消、非 TTY 降级。所有外部依赖（isatty、readLine、fputs）通过构造器注入。
- ✅ **Task 2 完成**: 实现 bracket paste mode 生命周期管理 — `enableBracketPaste()` / `disableBracketPaste()` 输出正确 ANSI 序列，非 TTY 模式自动跳过。
- ✅ **Task 3 完成**: 集成到 ChatCommand REPL 循环 — 替换 `readLine()` + `fputs(prompt)` 为 `inputReader.readInput()`，使用 `defer` 确保退出时恢复终端状态。续行取消返回空字符串 `""`，在后续 `trimmed.isEmpty` 检查中被跳过（回到主提示符）。
- ✅ **Task 4 完成**: 22 个单元测试全部通过，覆盖反斜杠续行、bracket paste、续行取消、非 TTY 降级、终端恢复、提示符输出、whitespace 续行、bracket paste EOF。使用 `LineProvider` + `OutputCapture` 类实现闭包状态共享。
- ✅ **回归测试**: 全部 1812 个 AxionCLI 单元测试通过，无回归。

### File List

- `Sources/AxionCLI/Chat/MultiLineInputReader.swift` — 新增：多行输入读取器（~165 行）
- `Sources/AxionCLI/Commands/ChatCommand.swift` — 修改：集成 MultiLineInputReader，替换 readLine()
- `Tests/AxionCLITests/Chat/MultiLineInputReaderTests.swift` — 新增：22 个单元测试

## Change Log

- 2026-06-07: Story 37.6 完成 — 新增 MultiLineInputReader 支持反斜杠续行和 bracket paste 多行粘贴，集成到 ChatCommand REPL 循环
- 2026-06-07: **Review 自动修复** — (1) 修复 Ctrl+C 续行提交部分内容 bug：ChatCommand 信号检查移至 nil guard 之前，覆盖续行 Ctrl+C 场景 (2) 简化 `writeStdout` 签名为 `(String) -> Void`，与 `writeStderr` 一致 (3) 非 TTY 模式跳过 prompt 输出 (4) `readContinuation` 返回类型改为非 Optional `String` (5) 新增 3 个测试：nonTTY prompt、whitespace 续行、bracket paste EOF
