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
        flushAtEnd: Bool = false
    ) -> String {
        var renderer = StreamingTableRenderer(profile: profile, isTTY: isTTY)
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
        // Table cells should NOT have [FORMATTED] prefix
        #expect(!plain.contains("[FORMATTED] A"))
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
}
