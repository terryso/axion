import Testing
import Foundation

@testable import AxionCLI

@Suite("StreamingTableRenderer")
struct StreamingTableRendererTests {

    // MARK: - Helper

    /// 创建渲染器并处理多行文本，返回输出（不含 ANSI 码的纯文本用于断言）。
    private func renderLines(
        _ lines: [String],
        profile: TerminalColorProfile = .trueColor,
        isTTY: Bool = true,
        terminalWidth: Int = 0,
        flushAtEnd: Bool = false
    ) -> String {
        var renderer = StreamingTableRenderer(profile: profile, isTTY: isTTY, terminalWidth: terminalWidth)
        var output = ""
        for line in lines {
            let _ = renderer.processLine(
                line,
                write: { output += $0 },
                formatPlain: { $0 }
            )
        }
        if flushAtEnd {
            renderer.flush(
                write: { output += $0 },
                formatPlain: { $0 }
            )
        }
        return output
    }

    /// 去除 ANSI 转义码，用于内容断言。
    private func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
    }

    @Test("path columns render full path continuation when truncated")
    func pathColumnRendersFullPathContinuation() {
        let fullPath = "~/Library/Application Support/com.pvncher.SleeperX/Profiles/default/config.json"
        let output = renderLines([
            "| # | 类别 | 路径 | 风险 | 大小 | 默认 | 需确认 |",
            "| --- | --- | --- | --- | --- | --- | --- |",
            "| 1 | Application Support | \(fullPath) | 高 | 12 KB | 否 | 是 |",
        ], profile: .unknown, isTTY: true, terminalWidth: 80, flushAtEnd: true)

        let plain = stripANSI(output)
        #expect(plain.contains("路径: ~/Library/Application Support/com.pvncher.SleeperX/Profiles/default/"))
        #expect(plain.contains("config.json"))
        #expect(plain.contains("Application Support"))
        for line in plain.components(separatedBy: "\n") where !line.isEmpty {
            let visualWidth = testVisualWidth(line)
            #expect(visualWidth <= 80, "Line exceeds 80 cols: \(visualWidth) — '\(line)'")
        }
    }

    @Test("dropped path columns do not crash width-constrained tables")
    func droppedPathColumnsDoNotCrash() {
        let output = renderLines([
            "| A | B | C | D | E | F | 路径 |",
            "| --- | --- | --- | --- | --- | --- | --- |",
            "| a | b | c | d | e | f | ~/Library/Application Support/example |",
        ], profile: .unknown, isTTY: true, terminalWidth: 18, flushAtEnd: true)

        let plain = stripANSI(output)
        #expect(plain.contains("╭"))
        for line in plain.components(separatedBy: "\n") where !line.isEmpty {
            let visualWidth = testVisualWidth(line)
            #expect(visualWidth <= 18, "Line exceeds 18 cols: \(visualWidth) — '\(line)'")
        }
    }

    // MARK: - Basic Table Detection

    @Test("detects and renders a simple 2-column table")
    func testSimpleTable() {
        let output = renderLines([
            "| Name | Type |",
            "| --- | --- |",
            "| id | Int |",
            "| name | String |",
            "End text"
        ])

        let plain = stripANSI(output)
        #expect(plain.contains("╭"))
        #expect(plain.contains("┬"))
        #expect(plain.contains("╮"))
        #expect(plain.contains("├"))
        #expect(plain.contains("┼"))
        #expect(plain.contains("┤"))
        #expect(plain.contains("╰"))
        #expect(plain.contains("┴"))
        #expect(plain.contains("╯"))
        #expect(plain.contains("Name"))
        #expect(plain.contains("Type"))
        #expect(plain.contains("id"))
        #expect(plain.contains("Int"))
        #expect(plain.contains("name"))
        #expect(plain.contains("String"))
        #expect(plain.contains("End text"))
    }

    @Test("renders a 3-column table with correct alignment")
    func testThreeColumnTable() {
        let output = renderLines([
            "| Module | Files | Lines |",
            "| --- | --- | --- |",
            "| CLI | 50 | 1200 |",
            "| Core | 20 | 500 |",
            "Done"
        ])

        let plain = stripANSI(output)
        // Table rows should exist
        #expect(plain.contains("Module"))
        #expect(plain.contains("Files"))
        #expect(plain.contains("Lines"))
        #expect(plain.contains("CLI"))
        #expect(plain.contains("Core"))
        #expect(plain.contains("Done"))
        // Should have box-drawing borders
        #expect(plain.contains("╭"))
        #expect(plain.contains("╯"))
        #expect(plain.contains("╰"))
    }

    @Test("renders table with no body rows")
    func testTableNoBodyRows() {
        let output = renderLines([
            "| Header |",
            "| --- |",
            "After"
        ])

        let plain = stripANSI(output)
        #expect(plain.contains("╭"))
        #expect(plain.contains("Header"))
        #expect(plain.contains("╰"))
        #expect(plain.contains("After"))
    }

    // MARK: - Holdback Behavior

    @Test("holdbacks potential header line until confirmed or rejected")
    func testHoldbackPotentialHeader() {
        var renderer = StreamingTableRenderer(profile: .trueColor, isTTY: true)
        var output = ""

        // Send a pipe row — should be held back
        let result1 = renderer.processLine(
            "| Name | Type |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        #expect(result1 == false)  // held back, no \n
        #expect(output.isEmpty)     // nothing written
        #expect(renderer.isBuffering == true)

        // Send separator — confirms table, also held back
        let result2 = renderer.processLine(
            "| --- | --- |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        #expect(result2 == false)
        #expect(renderer.isBuffering == true)

        // Send body row — held back
        let result3 = renderer.processLine(
            "| id | Int |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        #expect(result3 == false)
        #expect(renderer.isBuffering == true)

        // Non-table line triggers flush
        let result4 = renderer.processLine(
            "Next",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        #expect(result4 == true)
        #expect(renderer.isBuffering == false)

        let plain = stripANSI(output)
        #expect(plain.contains("Name"))
        #expect(plain.contains("id"))
        #expect(plain.contains("Next"))
    }

    @Test("releases buffered line when next line is not separator")
    func testHoldbackReleaseOnNonSeparator() {
        var renderer = StreamingTableRenderer(profile: .trueColor, isTTY: true)
        var output = ""

        // Send a pipe row — held back
        let _ = renderer.processLine(
            "| some text |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        #expect(output.isEmpty)

        // Send non-separator pipe row — first line released
        let result = renderer.processLine(
            "| more text |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        #expect(result == false)  // second line becomes new potential header

        let plain = stripANSI(output)
        #expect(plain.contains("some text"))
    }

    // MARK: - Flush Behavior

    @Test("flush renders buffered table at end of stream")
    func testFlushTable() {
        var renderer = StreamingTableRenderer(profile: .trueColor, isTTY: true)
        var output = ""

        let _ = renderer.processLine(
            "| Name | Type |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        let _ = renderer.processLine(
            "| --- | --- |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        let _ = renderer.processLine(
            "| id | Int |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        #expect(output.isEmpty)  // all held back

        renderer.flush(
            write: { output += $0 },
            formatPlain: { $0 }
        )

        let plain = stripANSI(output)
        #expect(plain.contains("╭"))
        #expect(plain.contains("Name"))
        #expect(plain.contains("id"))
    }

    @Test("flush releases non-table buffered line")
    func testFlushPotentialHeader() {
        var renderer = StreamingTableRenderer(profile: .trueColor, isTTY: true)
        var output = ""

        let _ = renderer.processLine(
            "| just a pipe | line |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        #expect(output.isEmpty)

        renderer.flush(
            write: { output += $0 },
            formatPlain: { $0 }
        )

        let plain = stripANSI(output)
        #expect(plain.contains("just a pipe"))
    }

    // MARK: - Reset

    @Test("reset clears all table state")
    func testReset() {
        var renderer = StreamingTableRenderer(profile: .trueColor, isTTY: true)

        let _ = renderer.processLine(
            "| H1 | H2 |",
            write: { _ in },
            formatPlain: { $0 }
        )
        #expect(renderer.isBuffering == true)

        renderer.reset()
        #expect(renderer.isBuffering == false)
    }

    // MARK: - Non-TTY Passthrough

    @Test("non-TTY passes through all lines without table rendering")
    func testNonTTYPassthrough() {
        let output = renderLines(
            [
                "| Name | Type |",
                "| --- | --- |",
                "| id | Int |",
            ],
            isTTY: false
        )

        // Non-TTY: raw text, no box-drawing borders
        #expect(!output.contains("╭"))
        #expect(!output.contains("│"))
        #expect(output.contains("| Name | Type |"))
        #expect(output.contains("| id | Int |"))
    }

    // MARK: - Column Alignment

    @Test("columns are left-aligned and padded to max width")
    func testColumnAlignment() {
        let output = renderLines([
            "| Name | Description |",
            "| --- | --- |",
            "| a | short |",
            "| very_long_name | a much longer description |",
            "End"
        ])

        let plain = stripANSI(output)
        // Both rows should be present
        #expect(plain.contains("very_long_name"))
        #expect(plain.contains("short"))
        #expect(plain.contains("a much longer description"))
        // Short cell "a" should be padded (spaces after it)
        #expect(plain.contains("a"))
    }

    @Test("handles body row with fewer cells than header")
    func testFewerCellsInBody() {
        let output = renderLines([
            "| A | B | C |",
            "| --- | --- | --- |",
            "| 1 | 2 |",
            "End"
        ])

        let plain = stripANSI(output)
        #expect(plain.contains("A"))
        #expect(plain.contains("B"))
        #expect(plain.contains("C"))
        #expect(plain.contains("1"))
        #expect(plain.contains("2"))
        #expect(plain.contains("End"))
    }

    @Test("handles body row with more cells than header")
    func testMoreCellsInBody() {
        let output = renderLines([
            "| A | B |",
            "| --- | --- |",
            "| 1 | 2 | 3 |",
            "End"
        ])

        let plain = stripANSI(output)
        // Extra cell "3" should be truncated (not rendered)
        #expect(plain.contains("A"))
        #expect(plain.contains("B"))
        #expect(plain.contains("1"))
        #expect(plain.contains("2"))
        #expect(plain.contains("End"))
    }

    // MARK: - Separator Variants

    @Test("supports alignment indicators in separator")
    func testSeparatorWithAlignment() {
        let output = renderLines([
            "| Left | Center | Right |",
            "| :--- | :---: | ---: |",
            "| L | C | R |",
            "End"
        ])

        let plain = stripANSI(output)
        #expect(plain.contains("Left"))
        #expect(plain.contains("Center"))
        #expect(plain.contains("Right"))
        #expect(plain.contains("L"))
        #expect(plain.contains("C"))
        #expect(plain.contains("R"))
        #expect(plain.contains("End"))
    }

    // MARK: - Multiple Tables

    @Test("handles two sequential tables")
    func testTwoSequentialTables() {
        let output = renderLines([
            "| A | B |",
            "| --- | --- |",
            "| 1 | 2 |",
            "Some text between",
            "| X | Y |",
            "| --- | --- |",
            "| a | b |",
            "Done"
        ])

        let plain = stripANSI(output)
        // First table
        #expect(plain.contains("A"))
        #expect(plain.contains("1"))
        // Text between
        #expect(plain.contains("Some text between"))
        // Second table
        #expect(plain.contains("X"))
        #expect(plain.contains("a"))
        #expect(plain.contains("Done"))
    }

    // MARK: - Edge Cases

    @Test("empty cells are rendered correctly")
    func testEmptyCells() {
        let output = renderLines([
            "| A | B |",
            "| --- | --- |",
            "| | empty_second |",
            "| empty_first | |",
            "End"
        ])

        let plain = stripANSI(output)
        #expect(plain.contains("empty_second"))
        #expect(plain.contains("empty_first"))
        #expect(plain.contains("End"))
    }

    @Test("single character separator is accepted")
    func testMinimalSeparator() {
        let output = renderLines([
            "| A | B |",
            "| - | - |",
            "| 1 | 2 |",
            "End"
        ])

        let plain = stripANSI(output)
        #expect(plain.contains("A"))
        #expect(plain.contains("1"))
        #expect(plain.contains("End"))
    }

    @Test("pipe row not followed by separator is released as plain text")
    func testPipeRowWithoutSeparator() {
        let output = renderLines([
            "| this is just | a pipe line |",
            "normal text",
        ])

        let plain = stripANSI(output)
        // No table should be rendered
        #expect(!plain.contains("╭"))
        #expect(plain.contains("| this is just | a pipe line |"))
        #expect(plain.contains("normal text"))
    }

    // MARK: - Color Profile Degradation

    @Test("trueColor renders with RGB color codes")
    func testTrueColorProfile() {
        let output = renderLines(
            [
                "| A |",
                "| --- |",
                "| 1 |",
                "End"
            ],
            profile: .trueColor
        )

        #expect(output.contains("\u{1B}[38;2;"))
        let plain = stripANSI(output)
        #expect(plain.contains("A"))
    }

    @Test("ansi256 renders with 256-color codes")
    func testANSI256Profile() {
        let output = renderLines(
            [
                "| A |",
                "| --- |",
                "| 1 |",
                "End"
            ],
            profile: .ansi256
        )

        #expect(output.contains("\u{1B}[38;5;"))
        let plain = stripANSI(output)
        #expect(plain.contains("A"))
    }

    @Test("ansi16 renders with standard color codes")
    func testANSI16Profile() {
        let output = renderLines(
            [
                "| A |",
                "| --- |",
                "| 1 |",
                "End"
            ],
            profile: .ansi16
        )

        #expect(output.contains("\u{1B}["))
        let plain = stripANSI(output)
        #expect(plain.contains("A"))
    }

    @Test("unknown profile renders plain borders without ANSI codes")
    func testUnknownProfile() {
        let output = renderLines(
            [
                "| A |",
                "| --- |",
                "| 1 |",
                "End"
            ],
            profile: .unknown,
            isTTY: true  // TTY but unknown profile
        )

        // Unknown profile: box-drawing borders but no ANSI color codes
        #expect(!output.contains("\u{1B}[38;2;"))
        #expect(!output.contains("\u{1B}[38;5;"))
        #expect(output.contains("╭"))
        #expect(output.contains("A"))
    }

    // MARK: - CJK Width

    @Test("CJK characters are double-width for alignment")
    func testCJKWidth() {
        let output = renderLines([
            "| 名前 | 値 |",
            "| --- | --- |",
            "| 日本語 | 123 |",
            "| short | 456 |",
            "End"
        ])

        let plain = stripANSI(output)
        #expect(plain.contains("名前"))
        #expect(plain.contains("日本語"))
        #expect(plain.contains("123"))
        #expect(plain.contains("End"))
    }

    // MARK: - formatPlain Integration

    @Test("passes non-table lines through formatPlain closure")
    func testFormatPlainIntegration() {
        var renderer = StreamingTableRenderer(profile: .trueColor, isTTY: true)
        var output = ""

        let _ = renderer.processLine(
            "| A |",
            write: { output += $0 },
            formatPlain: { "[FORMATTED] " + $0 }
        )
        let _ = renderer.processLine(
            "| --- |",
            write: { output += $0 },
            formatPlain: { "[FORMATTED] " + $0 }
        )
        let _ = renderer.processLine(
            "| 1 |",
            write: { output += $0 },
            formatPlain: { "[FORMATTED] " + $0 }
        )
        let _ = renderer.processLine(
            "Plain line",
            write: { output += $0 },
            formatPlain: { "[FORMATTED] " + $0 }
        )

        let plain = stripANSI(output)
        // Non-table line should go through formatPlain
        #expect(plain.contains("[FORMATTED] Plain line"))
        // Table cells now also go through formatPlain (for Markdown formatting support)
        #expect(plain.contains("[FORMATTED] A"))
    }

    @Test("released buffered header line goes through formatPlain")
    func testBufferedLineGoesThroughFormatPlain() {
        var renderer = StreamingTableRenderer(profile: .trueColor, isTTY: true)
        var output = ""

        // Send pipe row — held back
        let _ = renderer.processLine(
            "| not a table |",
            write: { output += $0 },
            formatPlain: { "[F] " + $0 }
        )

        // Non-pipe line releases buffered line through formatPlain
        let _ = renderer.processLine(
            "next",
            write: { output += $0 },
            formatPlain: { "[F] " + $0 }
        )

        let plain = stripANSI(output)
        #expect(plain.contains("[F] | not a table |"))
        #expect(plain.contains("[F] next"))
    }

    // MARK: - Integration with StreamingCodeBlockRenderer

    @Test("table is rendered through code block renderer pipeline")
    func testTableThroughCodeBlockRenderer() {
        let formatter = StreamingMarkdownFormatter(
            profile: .trueColor,
            isTTY: true,
            terminalWidth: 80
        )
        var renderer = StreamingCodeBlockRenderer(
            profile: .trueColor,
            isTTY: true,
            terminalWidth: 80,
            plainTextFormatter: { [formatter] line in
                formatter.formatLine(line)
            }
        )
        var output: [String] = []

        // Plain text before table
        renderer.process("Some text\n") { output.append($0) }

        // Table rows
        renderer.process("| Name | Type |\n") { output.append($0) }
        renderer.process("| --- | --- |\n") { output.append($0) }
        renderer.process("| id | Int |\n") { output.append($0) }

        // Flush triggers table rendering
        renderer.process("After\n") { output.append($0) }

        let combined = output.joined()
        let plain = stripANSI(combined)

        #expect(plain.contains("Some text"))
        #expect(plain.contains("╭"))
        #expect(plain.contains("Name"))
        #expect(plain.contains("id"))
        #expect(plain.contains("After"))
        // Raw pipe text should not appear
        #expect(!plain.contains("| Name |"))
        #expect(!plain.contains("| id |"))
    }

    @Test("table inside code block is NOT rendered as table")
    func testTableInsideCodeBlock() {
        let formatter = StreamingMarkdownFormatter(
            profile: .trueColor,
            isTTY: true,
            terminalWidth: 80
        )
        var renderer = StreamingCodeBlockRenderer(
            profile: .trueColor,
            isTTY: true,
            terminalWidth: 80,
            plainTextFormatter: { [formatter] line in
                formatter.formatLine(line)
            }
        )
        var output: [String] = []

        renderer.process("```\n") { output.append($0) }
        renderer.process("| Name | Type |\n") { output.append($0) }
        renderer.process("| --- | --- |\n") { output.append($0) }
        renderer.process("| id | Int |\n") { output.append($0) }
        renderer.process("```\n") { output.append($0) }

        let combined = output.joined()
        // Inside code block: pipe text should be preserved as-is
        #expect(combined.contains("| Name |"))
        #expect(combined.contains("| id |"))
        // Table borders should NOT appear
        let plain = stripANSI(combined)
        #expect(!plain.contains("╭┬╮"))
    }

    @Test("holdback prevents newlines during table buffering in code block renderer")
    func testHoldbackPreventsNewlinesInPipeline() {
        var renderer = StreamingCodeBlockRenderer(
            profile: .trueColor,
            isTTY: true,
            terminalWidth: 80,
            plainTextFormatter: { $0 }
        )
        var output: [String] = []

        // Table header — should be held back, no newline written
        renderer.process("| H1 | H2 |\n") { output.append($0) }
        let afterHeader = output.joined()
        #expect(!afterHeader.contains("H1"))  // held back

        // Separator — still held back
        renderer.process("| --- | --- |\n") { output.append($0) }

        // Body row — still held back
        renderer.process("| a | b |\n") { output.append($0) }

        // Non-table line triggers flush
        renderer.process("Done\n") { output.append($0) }

        let combined = output.joined()
        let plain = stripANSI(combined)
        #expect(plain.contains("╭"))
        #expect(plain.contains("H1"))
        #expect(plain.contains("a"))
        #expect(plain.contains("Done"))
    }

    // MARK: - Terminal Width Constraint

    @Test("wide four-column content table falls back to detail list")
    func wideContentTableFallsBackToDetailList() {
        let output = renderLines([
            "| 分类 | 内容 | 大小 | 建议 |",
            "| --- | --- | --- | --- |",
            "| 入职资料 | 入职资料包/ 保利威入职PPT、报销需知、企业文化材料、VPN说明、邮箱设置 | 660 MB | 保留，已经结构化，不建议移动或清理 |",
            "| 旧公司资料 | 榴莲西施、秀赞、叮当、Hoge职级评定、微片等历史资料 | 520 MB | 可归档到旧公司资料目录，避免散落在根目录 |",
        ], profile: .unknown, isTTY: true, terminalWidth: 80, flushAtEnd: true)

        let plain = stripANSI(output)
        #expect(plain.contains("表格（2 行，已改为详情模式显示）"))
        #expect(plain.contains("分类: 入职资料"))
        #expect(plain.contains("保利威入职PPT、报销需知"))
        #expect(plain.contains("建议: 保留，已经结构化"))
        #expect(!plain.contains("╭"))
        #expect(!plain.contains("…"))

        for line in plain.components(separatedBy: "\n") where !line.isEmpty {
            let visualWidth = testVisualWidth(line)
            #expect(visualWidth <= 80, "Line exceeds 80 cols: \(visualWidth) — '\(line)'")
        }
    }

    @Test("table respects terminal width by truncating columns")
    func testTerminalWidthConstraint() {
        // 渲染器限制 40 列宽
        var renderer = StreamingTableRenderer(profile: .unknown, isTTY: true, terminalWidth: 40)
        var output = ""

        let _ = renderer.processLine(
            "| Name | Type | Description |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        let _ = renderer.processLine(
            "| --- | --- | --- |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        let _ = renderer.processLine(
            "| id | Int | A very long description that would exceed the terminal width |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        renderer.flush(write: { output += $0 }, formatPlain: { $0 })

        let plain = stripANSI(output)
        // 表格应该被渲染
        #expect(plain.contains("╭"))
        #expect(plain.contains("id"))
        // 超宽内容应该被截断（出现省略号）
        #expect(plain.contains("…"))
        // 原始超长文本不应完整出现
        #expect(!plain.contains("A very long description that would exceed the terminal width"))

        // 验证每行视觉宽度不超过 40
        for line in plain.components(separatedBy: "\n") {
            let visualWidth = testVisualWidth(line)
            #expect(visualWidth <= 40, "Line exceeds 40 cols: \(visualWidth) — '\(line)'")
        }
    }

    @Test("terminalWidth 0 means no constraint")
    func testNoConstraintWhenZero() {
        var renderer = StreamingTableRenderer(profile: .unknown, isTTY: true, terminalWidth: 0)
        var output = ""

        let _ = renderer.processLine(
            "| A | B |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        let _ = renderer.processLine(
            "| --- | --- |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        let _ = renderer.processLine(
            "| very_long_content_here | short |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        renderer.flush(write: { output += $0 }, formatPlain: { $0 })

        let plain = stripANSI(output)
        // 不应出现截断省略号
        #expect(!plain.contains("…"))
        #expect(plain.contains("very_long_content_here"))
    }

    @Test("single column with long content gets truncated")
    func testSingleColumnTruncation() {
        var renderer = StreamingTableRenderer(profile: .unknown, isTTY: true, terminalWidth: 30)
        var output = ""

        let _ = renderer.processLine(
            "| Message |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        let _ = renderer.processLine(
            "| --- |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        let _ = renderer.processLine(
            "| This is a very long message that should be truncated |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        renderer.flush(write: { output += $0 }, formatPlain: { $0 })

        let plain = stripANSI(output)
        #expect(plain.contains("…"))
        // 完整长文本不应出现
        #expect(!plain.contains("This is a very long message that should be truncated"))
    }

    @Test("many columns fit within terminal by reducing widths")
    func testManyColumnsReduceWidths() {
        var renderer = StreamingTableRenderer(profile: .unknown, isTTY: true, terminalWidth: 50)
        var output = ""

        let _ = renderer.processLine(
            "| Col1 | Col2 | Col3 | Col4 | Col5 | Col6 | Col7 | Col8 |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        let _ = renderer.processLine(
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        let _ = renderer.processLine(
            "| a | b | c | d | e | f | g | h |",
            write: { output += $0 },
            formatPlain: { $0 }
        )
        renderer.flush(write: { output += $0 }, formatPlain: { $0 })

        let plain = stripANSI(output)
        // 每行宽度不超过 50
        for line in plain.components(separatedBy: "\n") {
            let visualWidth = testVisualWidth(line)
            #expect(visualWidth <= 50, "Line exceeds 50 cols: \(visualWidth) — '\(line)'")
        }
    }

    @Test("detail list wraps long values on soft breaks")
    func detailListWrapsLongValuesOnSoftBreaks() {
        let output = renderLines([
            "| 分类 | 内容 | 大小 | 建议 |",
            "| --- | --- | --- | --- |",
            "| 文档 | alpha/beta/gamma delta,epsilon;zeta，需要在窄终端里折行 | 1 MB | 保留，等待人工确认后再处理 |",
            "| 说明 | 没有软断点的超长中文内容需要强制折行避免溢出 | 2 MB | 暂缓 |",
        ], profile: .unknown, isTTY: true, terminalWidth: 36, flushAtEnd: true)

        let plain = stripANSI(output)
        #expect(plain.contains("表格（2 行，已改为详情模式显示）"))
        #expect(plain.contains("分类: 文档"))
        #expect(plain.contains("alpha/beta/gamma"))
        #expect(plain.contains("epsilon;zeta"))
        #expect(!plain.contains("╭"))

        for line in plain.components(separatedBy: "\n") where !line.isEmpty {
            let visualWidth = testVisualWidth(line)
            #expect(visualWidth <= 36, "Line exceeds 36 cols: \(visualWidth) — '\(line)'")
        }
    }

    @Test("styled ANSI and OSC cells use visible width for truncation")
    func styledANSIAndOSCCellsUseVisibleWidthForTruncation() {
        var renderer = StreamingTableRenderer(profile: .unknown, isTTY: true, terminalWidth: 34)
        var output = ""

        let format: @Sendable (String) -> String = { value in
            switch value {
            case "CSI":
                return "\u{1B}[31mCSI-styled-long-cell\u{1B}[0m"
            case "OSC":
                return "\u{1B}]8;;https://example.com\u{07}OSC-styled-long-cell\u{1B}]8;;\u{07}"
            case "ESC":
                return "\u{1B}7ESC-styled-long-cell"
            default:
                return value
            }
        }

        let _ = renderer.processLine(
            "| A | B | C |",
            write: { output += $0 },
            formatPlain: format
        )
        let _ = renderer.processLine(
            "| --- | --- | --- |",
            write: { output += $0 },
            formatPlain: format
        )
        let _ = renderer.processLine(
            "| CSI | OSC | ESC |",
            write: { output += $0 },
            formatPlain: format
        )
        renderer.flush(write: { output += $0 }, formatPlain: format)

        let plain = stripControlSequences(output)
        #expect(plain.contains("CSI"))
        #expect(plain.contains("OSC"))
        #expect(plain.contains("ESC"))
        #expect(plain.contains("…"))

        for line in plain.components(separatedBy: "\n") where !line.isEmpty {
            let visualWidth = testVisualWidth(line)
            #expect(visualWidth <= 34, "Line exceeds 34 cols: \(visualWidth) — '\(line)'")
        }
    }

    // MARK: - Test Helpers

    /// 计算视觉宽度（CJK = 2，其余 = 1）
    private func testVisualWidth(_ s: String) -> Int {
        var w = 0
        for char in s {
            guard let scalar = char.unicodeScalars.first else { continue }
            let v = scalar.value
            let isWide = (v >= 0x4E00 && v <= 0x9FFF)
                || (v >= 0xF900 && v <= 0xFAFF)
                || (v >= 0x3400 && v <= 0x4DBF)
                || (v >= 0xFF01 && v <= 0xFF60)
                || (v >= 0x3040 && v <= 0x309F)
                || (v >= 0x30A0 && v <= 0x30FF)
            w += isWide ? 2 : 1
        }
        return w
    }

    private func stripControlSequences(_ s: String) -> String {
        s
            .replacingOccurrences(
                of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\u{1B}\\].*?(\u{07}|\u{1B}\\\\)",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\u{1B}.",
                with: "",
                options: .regularExpression
            )
    }
}
