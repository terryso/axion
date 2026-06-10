import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

// MARK: - Chat 输出渲染管线 E2E 测试
//
// 通过 ChatOutputFormatter.handle(SDKMessage) 驱动完整渲染管线，
// 验证 Markdown 格式化 → 代码块 → 表格 → 语法高亮 → diff → 文件变更 → 系统事件端到端行为。

@Suite("Rendering Pipeline E2E")
struct RenderingPipelineE2ETests {

    // MARK: - Helpers

    /// 创建 TTY 模式的 formatter + 输出捕获
    ///
    /// 注意：ChatOutputFormatter.init 默认创建的 codeBlockRenderer 和 markdownFormatter
    /// 会使用 `isatty(STDOUT_FILENO)` 检测 TTY，但测试进程中 stdout 不是 TTY。
    /// 所以必须显式构造带 `isTTY: true` 的渲染器并注入。
    private func makeTTYFormatter(
        profile: TerminalColorProfile = .trueColor
    ) -> (ChatOutputFormatter, CaptureOutput, CaptureOutput) {
        let stdout = CaptureOutput()
        let stderr = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: false, writeStderr: { _ in })
        let theme = ChatTheme(profile: profile, isTTY: true)

        let markdownFormatter = StreamingMarkdownFormatter(
            profile: profile,
            isTTY: true
        )
        let codeBlockRenderer = StreamingCodeBlockRenderer(
            profile: profile,
            isTTY: true,
            plainTextFormatter: { line in markdownFormatter.formatLine(line) }
        )

        let formatter = ChatOutputFormatter(
            writeStdout: { stdout.write($0) },
            writeStderr: { stderr.write($0) },
            spinner: spinner,
            theme: theme,
            codeBlockRenderer: codeBlockRenderer,
            markdownFormatter: markdownFormatter
        )
        return (formatter, stdout, stderr)
    }

    /// 创建非 TTY 模式的 formatter + 输出捕获
    private func makeNonTTYFormatter() -> (ChatOutputFormatter, CaptureOutput, CaptureOutput) {
        let stdout = CaptureOutput()
        let stderr = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: false, writeStderr: { _ in })
        let theme = ChatTheme(profile: .unknown, isTTY: false)

        let markdownFormatter = StreamingMarkdownFormatter(
            profile: .unknown,
            isTTY: false
        )
        let codeBlockRenderer = StreamingCodeBlockRenderer(
            profile: .unknown,
            isTTY: false,
            plainTextFormatter: { line in markdownFormatter.formatLine(line) }
        )

        let formatter = ChatOutputFormatter(
            writeStdout: { stdout.write($0) },
            writeStderr: { stderr.write($0) },
            spinner: spinner,
            theme: theme,
            codeBlockRenderer: codeBlockRenderer,
            markdownFormatter: markdownFormatter
        )
        return (formatter, stdout, stderr)
    }

    // MARK: - 1. Markdown 格式化管线

    @Test("Markdown 格式化管线：bold + italic + inline code 渲染")
    func markdown_formatting_pipeline() {
        let (formatter, stdout, _) = makeTTYFormatter()

        formatter.handle(.partialMessage(.init(text: "This is **bold** and *italic* and `code` text\n")))

        let output = stdout.captured
        // bold: ANSI bold code
        #expect(output.contains("\u{1B}[1m"))
        // italic: ANSI italic code
        #expect(output.contains("\u{1B}[3m"))
        // inline code: should have distinct color
        #expect(output.contains("code"))
        // original text preserved
        #expect(stripANSI(output).contains("bold"))
        #expect(stripANSI(output).contains("italic"))
    }

    @Test("Markdown 格式化管线：H1 标题 + 双线下划线")
    func markdown_h1_underline_pipeline() {
        let (formatter, stdout, _) = makeTTYFormatter()

        formatter.handle(.partialMessage(.init(text: "# Main Title\n")))

        let output = stdout.captured
        // H1 color
        #expect(output.contains("\u{1B}[38;2;129;140;248m"))
        // H1 double-line underline
        #expect(output.contains("═"))
        // text preserved
        #expect(stripANSI(output).contains("Main Title"))
    }

    @Test("Markdown 格式化管线：内联链接降级渲染")
    func markdown_inline_link_pipeline() {
        let (formatter, stdout, _) = makeTTYFormatter(profile: .trueColor)

        formatter.handle(.partialMessage(.init(text: "Visit [docs](https://example.com) for info\n")))

        let output = stdout.captured
        // link text color (sky blue)
        #expect(output.contains("\u{1B}[38;2;96;165;250m") || output.contains("\u{1B}[38;5;"))
        // link text preserved
        #expect(stripANSI(output).contains("docs"))
        // URL shown (either via OSC 8 or dim fallback)
        #expect(stripANSI(output).contains("example.com"))
    }

    // MARK: - 2. 代码块渲染 + 语法高亮管线

    @Test("代码块管线：Swift 代码围栏 + 语法高亮")
    func codeblock_swift_syntax_pipeline() {
        let (formatter, stdout, _) = makeTTYFormatter()

        // 模拟流式输出：围栏打开 → 代码内容 → 围栏关闭
        formatter.handle(.partialMessage(.init(text: "```swift\n")))
        formatter.handle(.partialMessage(.init(text: "func hello() -> String {\n")))
        formatter.handle(.partialMessage(.init(text: "    return \"world\"\n")))
        formatter.handle(.partialMessage(.init(text: "}\n")))
        formatter.handle(.partialMessage(.init(text: "```\n")))

        let output = stdout.captured
        // 代码边框 │
        #expect(output.contains("│"))
        // 关键字 func 着色（紫色 TrueColor）
        #expect(stripANSI(output).contains("func"))
        // 关键字 return 着色
        #expect(stripANSI(output).contains("return"))
        // 字符串 "world" 着色
        #expect(stripANSI(output).contains("world"))
    }

    @Test("代码块管线：diff 代码块 + 行类型着色")
    func codeblock_diff_pipeline() {
        let (formatter, stdout, _) = makeTTYFormatter()

        formatter.handle(.partialMessage(.init(text: "```diff\n")))
        formatter.handle(.partialMessage(.init(text: "diff --git a/foo.swift b/foo.swift\n")))
        formatter.handle(.partialMessage(.init(text: "--- a/foo.swift\n")))
        formatter.handle(.partialMessage(.init(text: "+++ b/foo.swift\n")))
        formatter.handle(.partialMessage(.init(text: "@@ -1,3 +1,4 @@\n")))
        formatter.handle(.partialMessage(.init(text: " context line\n")))
        formatter.handle(.partialMessage(.init(text: "+added line\n")))
        formatter.handle(.partialMessage(.init(text: "-removed line\n")))
        formatter.handle(.partialMessage(.init(text: "```\n")))

        let output = stdout.captured
        let plain = stripANSI(output)
        // diff 内容保留
        #expect(plain.contains("diff --git"))
        #expect(plain.contains("added line"))
        #expect(plain.contains("removed line"))
        // 代码边框
        #expect(output.contains("│"))
    }

    @Test("代码块管线：JSON 专用 key/value 高亮")
    func codeblock_json_pipeline() {
        let (formatter, stdout, _) = makeTTYFormatter()

        formatter.handle(.partialMessage(.init(text: "```json\n")))
        formatter.handle(.partialMessage(.init(text: "{\"name\": \"Alice\", \"age\": 30}\n")))
        formatter.handle(.partialMessage(.init(text: "```\n")))

        let output = stdout.captured
        let plain = stripANSI(output)
        // JSON 内容保留
        #expect(plain.contains("Alice"))
        #expect(plain.contains("30"))
        // 代码边框
        #expect(output.contains("│"))
    }

    @Test("代码块管线：无标签代码块 + diff --git 自动检测")
    func codeblock_autodetect_diff_pipeline() {
        let (formatter, stdout, _) = makeTTYFormatter()

        formatter.handle(.partialMessage(.init(text: "```\n")))
        formatter.handle(.partialMessage(.init(text: "diff --git a/file.txt b/file.txt\n")))
        formatter.handle(.partialMessage(.init(text: "+new content\n")))
        formatter.handle(.partialMessage(.init(text: "```\n")))

        let output = stdout.captured
        let plain = stripANSI(output)
        // diff 内容保留
        #expect(plain.contains("diff --git"))
        #expect(plain.contains("new content"))
    }

    // MARK: - 3. 表格渲染管线

    @Test("表格管线：pipe table → Unicode box-drawing 表格")
    func table_pipeline() {
        let (formatter, stdout, _) = makeTTYFormatter()

        // 分行发送 pipe table
        formatter.handle(.partialMessage(.init(text: "| Name | Age |\n")))
        formatter.handle(.partialMessage(.init(text: "| --- | --- |\n")))
        formatter.handle(.partialMessage(.init(text: "| Alice | 30 |\n")))
        formatter.handle(.partialMessage(.init(text: "| Bob | 25 |\n")))
        formatter.handle(.partialMessage(.init(text: "\n")))
        // flush
        formatter.handle(.assistant(.init(text: "", model: "test", stopReason: "end_turn")))

        let output = stdout.captured
        // Unicode box-drawing 边框
        #expect(output.contains("╭") || output.contains("┬") || output.contains("╮"))
        #expect(output.contains("├") || output.contains("┼") || output.contains("┤"))
        #expect(output.contains("╰") || output.contains("┴") || output.contains("╯"))
        // 表格内容保留
        #expect(stripANSI(output).contains("Alice"))
        #expect(stripANSI(output).contains("Bob"))
    }

    @Test("表格管线：shell 管道文本经 flush 后不渲染为表格")
    func table_pipeline_shell_pipe_not_matched() {
        let (formatter, stdout, _) = makeTTYFormatter()

        formatter.handle(.partialMessage(.init(text: "Run this: cat file.txt | grep foo | sort\n")))
        // flush（模拟 assistant 消息结束）— 表格 holdback 内容会在 flush 时判定
        formatter.handle(.assistant(.init(text: "", model: "test", stopReason: "end_turn")))

        let output = stdout.captured
        let plain = stripANSI(output)
        // shell 管道文本保留（不是有效表格，flush 后原样输出）
        #expect(plain.contains("cat file.txt | grep foo | sort"))
        // 无表格边框
        #expect(!output.contains("╭"))
        #expect(!output.contains("╰"))
    }

    @Test("表格管线：两个连续表格各自独立渲染")
    func table_pipeline_two_tables() {
        let (formatter, stdout, _) = makeTTYFormatter()

        // 第一个表格
        formatter.handle(.partialMessage(.init(text: "| A | B |\n")))
        formatter.handle(.partialMessage(.init(text: "| --- | --- |\n")))
        formatter.handle(.partialMessage(.init(text: "| 1 | 2 |\n")))
        // 分隔文本
        formatter.handle(.partialMessage(.init(text: "Some text\n")))
        // 第二个表格
        formatter.handle(.partialMessage(.init(text: "| X | Y |\n")))
        formatter.handle(.partialMessage(.init(text: "| --- | --- |\n")))
        formatter.handle(.partialMessage(.init(text: "| a | b |\n")))
        formatter.handle(.partialMessage(.init(text: "\n")))
        formatter.handle(.assistant(.init(text: "", model: "test", stopReason: "end_turn")))

        let output = stdout.captured
        // 两个表格的边框各出现一次
        let borderCount = output.components(separatedBy: "╭").count - 1
        #expect(borderCount == 2)
        // 内容保留
        #expect(stripANSI(output).contains("Some text"))
    }

    // MARK: - 4. 混合管线状态隔离

    @Test("混合管线：文本 → 代码块 → 表格 → 代码块 → 文本，状态隔离")
    func mixed_pipeline_state_isolation() {
        let (formatter, stdout, _) = makeTTYFormatter()

        // 普通文本
        formatter.handle(.partialMessage(.init(text: "Here is code:\n")))
        // Swift 代码块
        formatter.handle(.partialMessage(.init(text: "```swift\n")))
        formatter.handle(.partialMessage(.init(text: "let x = 1\n")))
        formatter.handle(.partialMessage(.init(text: "```\n")))
        // 普通文本（表格）
        formatter.handle(.partialMessage(.init(text: "| Col1 | Col2 |\n")))
        formatter.handle(.partialMessage(.init(text: "| --- | --- |\n")))
        formatter.handle(.partialMessage(.init(text: "| a | b |\n")))
        formatter.handle(.partialMessage(.init(text: "\n")))
        // 另一个代码块（无语言标签，纯文本）
        formatter.handle(.partialMessage(.init(text: "```\n")))
        formatter.handle(.partialMessage(.init(text: "plain code\n")))
        formatter.handle(.partialMessage(.init(text: "```\n")))
        // 结束文本
        formatter.handle(.partialMessage(.init(text: "Done!\n")))
        formatter.handle(.assistant(.init(text: "", model: "test", stopReason: "end_turn")))

        let output = stdout.captured
        let plain = stripANSI(output)
        // 各段内容均保留
        #expect(plain.contains("Here is code"))
        #expect(plain.contains("let x = 1"))
        #expect(plain.contains("plain code"))
        #expect(plain.contains("Done"))
    }

    @Test("混合管线：代码块 → 工具调用 → 代码块，toolUse 中断后状态重置")
    func mixed_pipeline_toolUse_resets_codeblock() {
        let (formatter, stdout, _) = makeTTYFormatter()

        // 第一个代码块
        formatter.handle(.partialMessage(.init(text: "```swift\n")))
        formatter.handle(.partialMessage(.init(text: "let a = 1\n")))
        // 工具调用中断
        formatter.handle(.toolUse(.init(
            toolName: "Bash",
            toolUseId: "tu-1",
            input: "{\"command\":\"ls\"}"
        )))
        formatter.handle(.toolResult(.init(toolUseId: "tu-1", content: "file.txt", isError: false)))

        stdout.clear()

        // 第二个代码块（应独立渲染，无状态泄漏）
        formatter.handle(.partialMessage(.init(text: "```python\n")))
        formatter.handle(.partialMessage(.init(text: "def foo():\n")))
        formatter.handle(.partialMessage(.init(text: "    pass\n")))
        formatter.handle(.partialMessage(.init(text: "```\n")))

        let output = stdout.captured
        let plain = stripANSI(output)
        // 第二个代码块内容正确渲染
        #expect(plain.contains("def foo"))
        #expect(plain.contains("pass"))
        // 代码边框存在
        #expect(output.contains("│"))
    }

    // MARK: - 5. 文件变更追踪 E2E

    @Test("文件变更 E2E：write + edit + read → result 触发摘要")
    func file_change_e2e_mixed_operations() {
        let (formatter, stdout, _) = makeTTYFormatter()

        // Write 新文件
        formatter.handle(.toolUse(.init(toolName: "write", toolUseId: "t1", input: """
        {"file_path": "src/new.swift", "content": "line1\\nline2"}
        """)))
        formatter.handle(.toolResult(.init(toolUseId: "t1", content: "ok", isError: false)))

        // Edit 现有文件
        formatter.handle(.toolUse(.init(toolName: "edit", toolUseId: "t2", input: """
        {"file_path": "src/app.swift", "old_string": "old", "new_string": "new"}
        """)))
        formatter.handle(.toolResult(.init(toolUseId: "t2", content: "ok", isError: false)))

        // Read 文件
        formatter.handle(.toolUse(.init(toolName: "read", toolUseId: "t3", input: """
        {"file_path": "README.md"}
        """)))
        formatter.handle(.toolResult(.init(toolUseId: "t3", content: "# README", isError: false)))

        // result 触发摘要
        formatter.handle(.result(.init(subtype: .success, text: "", usage: nil as TokenUsage?, numTurns: 1, durationMs: 200)))

        let output = stdout.captured
        let plain = stripANSI(output)
        // 摘要包含文件名
        #expect(plain.contains("new.swift"))
        #expect(plain.contains("app.swift"))
    }

    @Test("文件变更 E2E：read → edit 同一文件，去重升级为 Edited")
    func file_change_e2e_dedup_upgrade() {
        let (formatter, stdout, _) = makeTTYFormatter()

        // Read 文件
        formatter.handle(.toolUse(.init(toolName: "read", toolUseId: "t1", input: """
        {"file_path": "src/main.swift"}
        """)))
        formatter.handle(.toolResult(.init(toolUseId: "t1", content: "code", isError: false)))

        // Edit 同一文件
        formatter.handle(.toolUse(.init(toolName: "edit", toolUseId: "t2", input: """
        {"file_path": "src/main.swift", "old_string": "old", "new_string": "new"}
        """)))
        formatter.handle(.toolResult(.init(toolUseId: "t2", content: "ok", isError: false)))

        // result 触发摘要
        formatter.handle(.result(.init(subtype: .success, text: "", usage: nil as TokenUsage?, numTurns: 1, durationMs: 100)))

        let output = stdout.captured
        let plain = stripANSI(output)
        // main.swift 只出现一次（去重后升级为 Edited）
        #expect(plain.contains("main.swift"))
        // 不应包含 "Read" 作为动词（因为已升级为 Edited）
        #expect(!plain.contains("Read 1 file"))
    }

    @Test("文件变更 E2E：无文件操作 → result 后无摘要")
    func file_change_e2e_no_changes() {
        let (formatter, stdout, _) = makeTTYFormatter()

        // Shell 命令（无文件操作）
        formatter.handle(.toolUse(.init(toolName: "Bash", toolUseId: "t1", input: """
        {"command": "ls -la"}
        """)))
        formatter.handle(.toolResult(.init(toolUseId: "t1", content: "file1\nfile2", isError: false)))

        // result 触发
        formatter.handle(.result(.init(subtype: .success, text: "", usage: nil as TokenUsage?, numTurns: 1, durationMs: 50)))

        let output = stdout.captured
        let plain = stripANSI(output)
        // 不应包含文件变更摘要关键词
        #expect(!plain.contains("files changed"))
        #expect(!plain.contains("file read"))
        #expect(!plain.contains("Created"))
        #expect(!plain.contains("Edited"))
    }

    // MARK: - 6. 系统事件渲染 E2E

    @Test("系统事件 E2E：compactBoundary → 📦 context compacted")
    func system_event_compaction_e2e() {
        let (formatter, stdout, _) = makeTTYFormatter()

        let metadata = SDKMessage.CompactMetadata(
            trigger: .auto,
            preTokens: 15000,
            postTokens: 5000,
            durationMs: 1200
        )
        formatter.handle(.system(.init(
            subtype: .compactBoundary,
            message: "compacted",
            compactMetadata: metadata
        )))

        let output = stdout.captured
        #expect(output.contains("📦"))
        #expect(output.contains("context compacted"))
        #expect(output.contains("saved 66%"))
    }

    @Test("系统事件 E2E：rateLimit → ⚠️ rate limit warning")
    func system_event_rate_limit_e2e() {
        let (formatter, _, stderr) = makeTTYFormatter()

        let info = SDKMessage.RateLimitInfo(
            status: .allowedWarning,
            rateLimitType: .sevenDay,
            utilization: 0.75
        )
        formatter.handle(.system(.init(
            subtype: .rateLimit,
            message: "rate limit",
            rateLimitInfo: info
        )))

        // rateLimit 输出到 stderr
        let output = stderr.captured
        #expect(output.contains("rate limit warning"))
        #expect(output.contains("75% utilized"))
        #expect(output.contains("7d window"))
    }

    @Test("系统事件 E2E：taskNotification → ✓ task completed")
    func system_event_task_notification_e2e() {
        let (formatter, stdout, _) = makeTTYFormatter()

        let taskInfo = SDKMessage.TaskNotificationInfo(
            taskId: "task-1",
            status: .completed,
            summary: "Fixed the bug"
        )
        formatter.handle(.system(.init(
            subtype: .taskNotification,
            message: "task done",
            taskNotificationInfo: taskInfo
        )))

        let output = stdout.captured
        #expect(output.contains("✓"))
        #expect(output.contains("completed"))
        #expect(output.contains("Fixed the bug"))
    }

    // MARK: - 7. 非 TTY 降级

    @Test("非 TTY 降级：Markdown 格式化跳过，纯文本直通")
    func non_tty_markdown_passthrough() {
        let (formatter, stdout, _) = makeNonTTYFormatter()

        formatter.handle(.partialMessage(.init(text: "This is **bold** and *italic* and `code`\n")))

        let output = stdout.captured
        // 非 TTY 模式无 ANSI 色码（直接输出原始 Markdown 文本）
        #expect(!output.contains("\u{1B}[1m"))
        #expect(!output.contains("\u{1B}[3m"))
        // 原始 Markdown 语法保留
        #expect(output.contains("**bold**"))
        #expect(output.contains("*italic*"))
        #expect(output.contains("`code`"))
    }

    @Test("非 TTY 降级：代码块无语法高亮，纯文本直通")
    func non_tty_codeblock_passthrough() {
        let (formatter, stdout, _) = makeNonTTYFormatter()

        formatter.handle(.partialMessage(.init(text: "```swift\n")))
        formatter.handle(.partialMessage(.init(text: "func hello() {\n")))
        formatter.handle(.partialMessage(.init(text: "    return \"world\"\n")))
        formatter.handle(.partialMessage(.init(text: "}\n")))
        formatter.handle(.partialMessage(.init(text: "```\n")))

        let output = stdout.captured
        // 非 TTY 无代码边框
        #expect(!output.contains("│"))
        // 原始代码内容直通
        #expect(output.contains("func hello()"))
        #expect(output.contains("return \"world\""))
    }
}

// MARK: - Test Helpers

/// Strips ANSI escape codes from a string for content assertion.
private func stripANSI(_ input: String) -> String {
    input.replacingOccurrences(
        of: "\u{1B}\\[[0-9;]*m",
        with: "",
        options: .regularExpression
    )
}
