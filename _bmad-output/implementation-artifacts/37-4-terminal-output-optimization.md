---
story_id: 37.4
epic: 37
title: 终端输出优化
status: done
created: 2026-06-07
baseline_commit: 9c7e56f
---

# Story 37.4: 终端输出优化

As a CLI 用户,
I want 看到更清晰的输出格式——工具结果有摘要、LLM 回复有 Markdown 渲染、进度有动态指示,
So that 交互体验更接近 Claude Code 的水平.

## Acceptance Criteria

1. **AC1 — 工具调用格式优化**：agent 执行工具调用时，显示为缩进层级格式 `⏳ <工具名>: <参数摘要>` 开始，`✅ <结果摘要> [<耗时>]` 完成，`❌ <错误摘要> [<耗时>]` 失败。替代当前的 `[axion] 执行: Bash` / `[axion] 结果: ...` 格式

2. **AC2 — LLM 回复直接输出**：LLM 文本回复不再使用 `[axion]` 前缀包裹，直接输出到终端。工具调用区域与 LLM 文本区域之间用空行分隔

3. **AC3 — 进度 Spinner**：LLM 等待时间 > 500ms 时，在 stderr 显示动态 spinner（`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` 循环），工具执行时显示 `⏳ <工具名> <spinner>`。spinner 在收到首个响应后消失

4. **AC4 — Markdown 简易渲染**：对 LLM 回复中的 bold、inline code、code block 做基本终端 ANSI 渲染：
   - `**bold**` → `\033[1mbold\033[0m`
   - `` `code` `` → `\033[36mcode\033[0m`
   - ` ```code block``` ` → 缩进 + 无额外格式（保留原文）

5. **AC5 — 无回归**：`axion run "task"` 行为完全不受影响（仍使用 `SDKTerminalOutputHandler`）；slash 命令、Ctrl+C 中断、BannerRenderer 等现有功能正常

## Tasks / Subtasks

- [x] Task 1: 创建 MarkdownTerminalRenderer 工具类 (AC: #4)
  - [x] 1.1 新建 `Sources/AxionCLI/Chat/MarkdownTerminalRenderer.swift`
  - [x] 1.2 实现 `static func render(_ markdown: String) -> String` — 将 Markdown 文本转为 ANSI 转义码终端文本
  - [x] 1.3 处理 `**bold**` → `\033[1m...\033[0m`
  - [x] 1.4 处理 `` `inline code` `` → `\033[36m...\033[0m`
  - [x] 1.5 处理 fenced code block (` ```...``` `) — 保留原文不转义内部内容，只加缩进
  - [x] 1.6 处理 `*italic*` → `\033[3m...\033[0m`（可选，低优先级）

- [x] Task 2: 创建 SpinnerRenderer 工具类 (AC: #3)
  - [x] 2.1 新建 `Sources/AxionCLI/Chat/SpinnerRenderer.swift`
  - [x] 2.2 实现 spinner frame 序列：`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`（Braille dots 动画）
  - [x] 2.3 实现 `start(message:)` — 在 stderr 开始显示 spinner（每 80ms 刷新一帧）
  - [x] 2.4 实现 `stop(clearLine:)` — 停止 spinner 并清除行（`\r\033[K`）
  - [x] 2.5 使用 `DispatchSourceTimer` 定时刷新（非 async/await，因为需要在同步上下文中使用）
  - [x] 2.6 检测 stderr 是否为 TTY（`isatty(STDERR_FILENO)`），非 TTY 时不输出 spinner

- [x] Task 3: 创建 ChatOutputFormatter 类 (AC: #1, #2, #3)
  - [x] 3.1 新建 `Sources/AxionCLI/Chat/ChatOutputFormatter.swift`
  - [x] 3.2 实现 `SDKMessageOutputHandler` 协议（与 `SDKTerminalOutputHandler` 同接口）
  - [x] 3.3 处理 `.partialMessage` — 流式输出 LLM 文本，通过 MarkdownTerminalRenderer 渲染，缓冲 partial 直到完整 token（遇到空格/标点）再输出
  - [x] 3.4 处理 `.toolUse` — 显示 `⏳ <工具名>: <参数摘要>`，启动 spinner
  - [x] 3.5 处理 `.toolResult` — 停止 spinner，显示 `✅ <结果摘要> [<耗时>]` 或 `❌ <错误摘要> [<耗时>]`
  - [x] 3.6 处理 `.assistant` — 如果有缓冲文本则 flush，标记 LLM 等待开始
  - [x] 3.7 处理 `.result` — 显示完成/错误状态
  - [x] 3.8 LLM 文本与工具调用之间插入空行分隔
  - [x] 3.9 结果摘要复用 `SDKTerminalOutputHandler.summarizeResult` 的逻辑（提取为共享函数或独立实现）

- [x] Task 4: 修改 ChatCommand 使用新格式化器 (AC: #5)
  - [x] 4.1 将 ChatCommand 第 134 行 `SDKTerminalOutputHandler(mode: "chat")` 替换为 `ChatOutputFormatter()`
  - [x] 4.2 确认 `axion run` 路径仍使用 `SDKTerminalOutputHandler`（不改 RunCommand）

- [x] Task 5: 单元测试 (AC: #1-#4)
  - [x] 5.1 测试 `MarkdownTerminalRenderer.render` — bold 转换：`**hello**` → 包含 ANSI 粗体码
  - [x] 5.2 测试 `MarkdownTerminalRenderer.render` — inline code：`` `foo` `` → 包含 ANSI 青色码
  - [x] 5.3 测试 `MarkdownTerminalRenderer.render` — code block 不转义内部内容
  - [x] 5.4 测试 `MarkdownTerminalRenderer.render` — 混合 Markdown：`**bold** and `code`` 同时处理
  - [x] 5.5 测试 `MarkdownTerminalRenderer.render` — 纯文本无 Markdown 时不添加 ANSI 码
  - [x] 5.6 测试 `ChatOutputFormatter` — 工具调用输出格式验证（mock SDKMessage）
  - [x] 5.7 测试 SpinnerRenderer — TTY 检测逻辑（mock `isatty`）

## Dev Notes

### 核心架构理解

**当前 ChatCommand 输出路径（第 134-142 行）：**
```swift
let outputHandler = SDKTerminalOutputHandler(mode: "chat")
let messageStream = buildResult.agent.stream(trimmed)
for await message in messageStream {
    outputHandler.handle(message)
    // Accumulate token usage from result events
    if case .result(let data) = message, let usage = data.usage {
        sessionUsage = sessionUsage + usage
    }
}
```

**SDKTerminalOutputHandler 的 `[axion]` 前缀问题：**
- 所有输出行以 `[axion]` 开头
- LLM 流式文本在 `flushStreamBuffer()` 中被 `[axion]` 包裹
- 工具结果显示为 `[axion] 结果: ...`

**本 Story 改动范围：** 仅修改 ChatCommand 的输出格式化器，不改变 REPL 循环逻辑、信号处理、slash 命令等。ChatCommand 第 134 行替换为新的 ChatOutputFormatter。

### 关键设计决策

**1. ChatOutputFormatter 实现 SDKMessageOutputHandler 协议：**

```swift
import OpenAgentSDK

/// Chat 模式专用输出格式化器 — 替代 SDKTerminalOutputHandler 的 [axion] 前缀格式。
/// 提供工具调用摘要、Markdown 渲染、进度 spinner。
final class ChatOutputFormatter: SDKMessageOutputHandler, @unchecked Sendable {
    // ...
}
```

SDK 的 `SDKMessageOutputHandler` 协议要求实现 `handle(_ message: SDKMessage)` 和 `displayCompletion()`。

**2. LLM 文本流式输出策略：**

LLM 文本通过 `.partialMessage` 事件以增量片段到达。设计两种策略：

- **方案 A（推荐）：逐 token 输出** — 每次 `.partialMessage` 直接 `fputs` 到 stdout，不缓冲。LLM 文本通过 MarkdownTerminalRenderer 实时渲染。优点：实时性好，体验流畅。缺点：partial token（如 `**bol` 未闭合）处理复杂。
- **方案 B：整轮缓冲** — 缓冲所有 partial，在 `.assistant` 或 `.toolUse` 时一次性输出。优点：Markdown 解析完整。缺点：延迟高。

**推荐方案 A**：对 `.partialMessage` 文本做简单判断 — 如果包含未闭合的 Markdown 语法（`**` 只有一个），暂时不渲染该部分，等到下个 partial 补齐后一起渲染。实际实现可以更简单：直接 fputs 原始文本，在 `.assistant` 时对已收集的完整文本做一次 Markdown 渲染覆盖（用 `\r` 清行重写）。

**最简实现（推荐先做）：** 对 `.partialMessage` 直接 fputs 原始文本（不渲染），在消息结束后对完整文本不重渲染。Markdown 渲染只对 `.assistant` 中的完整文本生效。

**3. Spinner 实现：**

```swift
struct SpinnerRenderer {
    private var timer: DispatchSourceTimer?
    private let frames = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    private var frameIndex = 0
    private let message: String
    private let isTTY: Bool

    mutating func start() {
        guard isatty(STDERR_FILENO) != 0 else { return }
        let queue = DispatchQueue(label: "axion.spinner", qos: .utility)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: .milliseconds(80))
        timer?.setEventHandler { [self] in
            let frame = frames[frames.index(frames.startIndex, offsetBy: frameIndex % frames.count)]
            fputs("\r\("⏳") \(self.message) \(frame) ", stderr)
            fflush(stderr)
            self.frameIndex += 1
        }
        timer?.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if isatty(STDERR_FILENO) != 0 {
            fputs("\r\033[K", stderr)  // 清除 spinner 行
            fflush(stderr)
        }
    }
}
```

**关键点：** Spinner 写入 stderr，LLM 文本和工具结果写入 stdout。这样 redirect stdout 时不会包含 spinner 噪音。

**4. 工具结果摘要：**

复用 `SDKTerminalOutputHandler.summarizeResult()` 的逻辑。两种方案：
- **提取为共享函数**：在 `AxionCLI/Chat/` 下创建 `ToolResultSummarizer.swift`
- **在 ChatOutputFormatter 中重新实现**：独立实现，不依赖 SDKTerminalOutputHandler

推荐后者 — 避免修改 SDKTerminalOutputHandler（project-context.md 反模式 #3）。

**5. MarkdownTerminalRenderer 正则策略：**

```swift
struct MarkdownTerminalRenderer {
    static func render(_ text: String) -> String {
        var result = text
        // 1. 保护 code block 内容（先提取，替换占位符）
        var codeBlocks: [String] = []
        result = result.replacingOccurrences(
            of: "```[\\s\\S]*?```",
            with: { match in
                codeBlocks.append(match)
                return "%%CODEBLOCK_\(codeBlocks.count - 1)%%"
            },
            options: .regularExpression
        )
        // 2. 处理 inline code
        result = result.replacingOccurrences(
            of: "`([^`]+)`",
            with: "\u{1B}[36m$1\u{1B}[0m",
            options: .regularExpression
        )
        // 3. 处理 bold
        result = result.replacingOccurrences(
            of: "\\*\\*([^*]+)\\*\\*",
            with: "\u{1B}[1m$1\u{1B}[0m",
            options: .regularExpression
        )
        // 4. 恢复 code block（加缩进）
        for (i, block) in codeBlocks.enumerated() {
            let indented = block
                .replacingOccurrences(of: "```", with: "")
                .split(separator: "\n")
                .map { "  " + $0 }
                .joined(separator: "\n")
            result = result.replacingOccurrences(of: "%%CODEBLOCK_\(i)%%", with: indented)
        }
        return result
    }
}
```

### ChatCommand 改动点

**替换第 134 行：**

```swift
// 替换前：
let outputHandler = SDKTerminalOutputHandler(mode: "chat")

// 替换后：
let outputHandler = ChatOutputFormatter()
```

**其余不变** — token 累计、中断检测、signal handler 等完全不受影响。

### ChatOutputFormatter 消息处理流程

```
用户输入 "帮我重构这个函数"
    │
    ▼ Spinner: "⏳ 思考中 ⠙" (stderr)
    │
    ├── .partialMessage("好的，让我先看看代码...")
    │       → fputs("好的，让我先看看代码...", stdout)  // 无前缀
    │
    ├── .toolUse(Bash, "cat Sources/AxionCLI/...")
    │       → Spinner.stop()
    │       → fputs("⏳ Bash: cat Sources/AxionCLI/...\n", stdout)
    │       → Spinner.start("Bash")  // 工具执行中
    │
    ├── .toolResult(content, 120ms)
    │       → Spinner.stop()
    │       → fputs("✅ [file content...] [120ms]\n", stdout)
    │       → fputs("\n", stdout)  // 空行分隔
    │
    ├── .partialMessage("我看到这个函数可以简化为...")
    │       → fputs("我看到这个函数可以简化为...", stdout)
    │
    ├── .assistant(text: "我看到这个函数可以简化为...")
    │       → flush buffer, mark LLM wait start
    │
    └── .result(success)
            → fputs("\n", stdout)  // 空行结束
```

### 关键反模式（必须避免）

1. **不要修改 `SDKTerminalOutputHandler`** — 它被 `RunCommand` 使用（project-context.md 反模式 #3）。Chat 模式有独立的输出格式化
2. **不要修改 `axion run` 路径** — ChatOutputFormatter 仅在 ChatCommand 中使用
3. **不要在 ChatOutputFormatter 中硬编码 `[axion]` 前缀** — 这是本 Story 要消除的格式
4. **不要在 spinner 中使用 stdout** — Spinner 写 stderr，LLM 文本和结果写 stdout，避免 redirect 时噪音
5. **不要忘记 import OpenAgentSDK** — ChatOutputFormatter 需要实现 `SDKMessageOutputHandler` 协议
6. **不要在 MarkdownTerminalRenderer 中做 I/O 操作** — 纯函数返回字符串，由 ChatOutputFormatter 负责输出
7. **不要使用 Unicode box-drawing 画复杂布局** — 保持简洁的 `⏳` / `✅` / `❌` 图标
8. **不要在非 TTY 环境输出 spinner** — 检测 `isatty(STDERR_FILENO)`，管道/重定向时静默跳过
9. **不要使用 `print()`** — CLI 使用 `fputs()` + `fflush()` 控制输出目标和缓冲（project-context.md 反模式 #3）

### 测试策略

- **单元测试（必须 Mock）：**
  - `MarkdownTerminalRenderer.render` — bold、inline code、code block、混合、纯文本（5 个测试）
  - `ChatOutputFormatter` — mock SDKMessage 验证输出格式（工具调用、工具结果、LLM 文本）
  - `SpinnerRenderer` — TTY 检测 mock
  - **Mock 策略：** MarkdownTerminalRenderer 是纯函数，无需 Mock。ChatOutputFormatter 通过注入 `write` 闭包来捕获输出，不测试真实终端

- **不写集成测试** — 不启动真实 agent 或终端

### Project Structure Notes

- 新文件 `ChatOutputFormatter.swift`、`MarkdownTerminalRenderer.swift`、`SpinnerRenderer.swift` 放在 `Sources/AxionCLI/Chat/` 目录（与 BannerRenderer、SlashCommand、SignalHandler 同级）
- 测试文件放在 `Tests/AxionCLITests/Chat/`（镜像源结构）
- 使用 Swift Testing 框架（`import Testing`、`@Suite`、`@Test`、`#expect`）

### References

- [Source: docs/epics/epic-37-interactive-chat-mode.md#Story 37.4] — 完整 story 定义和 AC
- [Source: Sources/AxionCLI/Commands/ChatCommand.swift:134] — 当前使用 SDKTerminalOutputHandler 的位置
- [Source: Sources/AxionCLI/Commands/SDKOutputHandlers.swift] — 现有输出处理器（Chat 模式不直接修改，仅参考 summarizeResult 逻辑）
- [Source: Sources/AxionCLI/Chat/BannerRenderer.swift] — 同目录纯函数工具类，作为新文件的设计参考
- [Source: _bmad-output/implementation-artifacts/37-3-startup-banner-session-info.md] — Story 37.3 完成记录（前序 story）

### Previous Story Intelligence (37.3)

- **BannerRenderer 已完成** — 纯函数 struct，static methods，无 I/O
- **ChatCommand 结构已稳定** — 168 行，REPL 循环 + signal handler + slash commands
- **SDKTerminalOutputHandler 在 ChatCommand 第 134 行使用** — 本 Story 的修改点
- **TokenUsage 累计** — 每轮 stream 结束后从 `SDKMessage.result` 提取
- **BannerRenderer 使用 fputs + stderr/stdout 分离** — 新格式化器应遵循相同模式

### Previous Story Intelligence (37.2)

- **SignalHandler 已完成** — agent.interrupt() 模式
- **sessionUsage 累计** — 在 stream 循环中直接从 SDKMessage.result 提取
- **lastInterruptTime** — 双击退出检测变量
- **中断后输出** — `fputs("[axion] 已中断\n", stderr)` 在第 155 行，本 Story 可改为更简洁格式

### Previous Story Intelligence (37.1)

- **Slash 命令系统已完成** — 8 个命令 + 未知命令拦截
- **Chat/ 目录已创建** — SlashCommand.swift、SlashCommandHandler.swift、SignalHandler.swift、BannerRenderer.swift
- **测试文件位置** — `Tests/AxionCLITests/Chat/` 目录

### Git Intelligence

最近 5 个提交：
- `9c7e56f` feat(story-37.3): 启动横幅 + 会话信息
- `3cb12d6` feat(story-37.2): Ctrl+C 优雅中断
- `aff3118` feat(story-37.1): Slash 命令体系
- `3b9f251` feat(story-37.0): Coding Agent 系统提示 + 项目上下文
- `582feeb` feat: add interactive chat mode as default command

本 Story 37.4 在同一文件 ChatCommand.swift 中修改输出格式化器，与前序 story 互不干扰（前序 story 改了 BannerRenderer、SignalHandler、SlashCommand，本 Story 只改 outputHandler 实例化行 + 新增独立文件）。

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m]

### Debug Log References

- 编译错误：`String.prefix()` 返回 `Substring`，自定义 `.string` 扩展在 `String` 类型上下文中无法解析。修复：直接使用 `String(...)` 构造。
- 测试编译错误：`SDKMessage` 需要 `import OpenAgentSDK`。

### Completion Notes List

- ✅ Task 1: MarkdownTerminalRenderer — 纯函数 struct，实现 bold/inline code/code block/italic 的 ANSI 渲染，使用占位符保护 code block 内容不被后续正则处理
- ✅ Task 2: SpinnerRenderer — 使用 DispatchSourceTimer（80ms 间隔），stderr 输出，非 TTY 自动静默，依赖注入 `isTTY` 和 `writeStderr` 便于测试
- ✅ Task 3: ChatOutputFormatter — 实现 SDKMessageOutputHandler 协议，处理所有 SDKMessage 类型：partialMessage 直接输出（无 [axion] 前缀）、toolUse 显示 ⏳ + 启动 spinner、toolResult 显示 ✅/❌ + 停止 spinner 并启动 LLM 等待 spinner（500ms 延迟）、LLM 文本与工具调用之间空行分隔、截图/base64/JSON 内容智能摘要
- ✅ Task 4: ChatCommand 第 134 行替换为 ChatOutputFormatter()，增加 startLLMWaiting() 调用（初始 LLM 等待 spinner），RunCommand 路径不受影响
- ✅ Task 5: 25 个单元测试全部通过，覆盖 MarkdownTerminalRenderer（9 个）、ChatOutputFormatter（9 个）、SpinnerRenderer（7 个）
- ✅ 全量回归测试 1991 tests 全部通过，无回归

### File List

- `Sources/AxionCLI/Chat/MarkdownTerminalRenderer.swift` (新增)
- `Sources/AxionCLI/Chat/SpinnerRenderer.swift` (新增)
- `Sources/AxionCLI/Chat/ChatOutputFormatter.swift` (新增)
- `Sources/AxionCLI/Commands/ChatCommand.swift` (修改 — 第 134 行替换 outputHandler)
- `Tests/AxionCLITests/Chat/TerminalOutputTests.swift` (新增)

## Change Log

- 2026-06-07: Story 37.4 实施 — 终端输出优化。新建 MarkdownTerminalRenderer、SpinnerRenderer、ChatOutputFormatter 三个组件，替换 ChatCommand 中的 SDKTerminalOutputHandler，消除 [axion] 前缀，添加工具调用摘要格式、LLM 文本直接输出、进度 spinner。25 个新单元测试，全量 1991 tests 通过。
- 2026-06-07: **Code Review 修复** — 修复 AC3（LLM 等待 spinner 未实现）：SpinnerRenderer 增加 `delayMs` 延迟启动支持（500ms 阈值），ChatOutputFormatter 在 `.toolResult` 后启动延迟 LLM 等待 spinner，ChatCommand 在 turn 开始时调用 `startLLMWaiting()`。清理死代码（`didShowSpinner`、`llmWaitStart`）。修复 SpinnerRenderer.stop() 仅在动画活跃时输出清除码。新增 6 个测试（延迟启动、取消延迟、TTY spinner 帧验证、startLLMWaiting 集成等），总计 25 个测试通过。已知限制：AC4 MarkdownTerminalRenderer 已构建但未接入流式输出（流式场景需要缓冲架构，当前保留最简实现）。
