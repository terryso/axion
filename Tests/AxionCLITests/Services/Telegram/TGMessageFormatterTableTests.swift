// Tests for Story 36.2: MarkdownV2 Table Block Rendering
// Validates block-level table detection and Hermes-style space-aligned code block rendering.
// 2-column tables → key/value fallback (preserves bold). 3+ column tables → code block.

import Testing
import Foundation
@testable import AxionCLI

@Suite("TGMessageFormatter Table Block Rendering")
struct TGMessageFormatterTableTests {

    // MARK: - AC1: 3+ column table rendered as space-aligned code block

    @Test("[P0][AC1] 3-column table renders as code block with space-aligned columns")
    func threeColumnTableRendersAsAlignedCodeBlock() {
        let input = """
        | Name  | Age | City |
        |-------|-----|------|
        | Alice | 30  | NYC  |
        | Bob   | 25  | LA   |
        """
        let (result, mode) = TGMessageFormatter.format(input)
        #expect(mode == .markdownV2)

        // Should be wrapped in a code block
        #expect(result.contains("```"), "3+ column table should be wrapped in a code block")

        // Data rows present
        #expect(result.contains("Alice"))
        #expect(result.contains("Bob"))

        // Separator row removed
        #expect(!result.contains("---"), "Separator row should be removed")

        // Should NOT contain pipe separators (Hermes-style: space-aligned, no pipes)
        let codeContent = result.extractCodeBlockContent()
        #expect(!codeContent.contains("|"), "Should NOT use pipe separators inside code block")
    }

    @Test("[P0][AC1] 4-column table renders all data")
    func fourColumnTableRendersAllRows() {
        let input = """
        | Metric | Value | Status | Note |
        |--------|-------|--------|------|
        | CPU    | 95%   | High   | Hot  |
        | Memory | 2GB   | OK     | Fine |
        | Disk   | 500GB | Low    | Good |
        """
        let (result, _) = TGMessageFormatter.format(input)

        #expect(result.contains("```"))
        #expect(result.contains("CPU"))
        #expect(result.contains("Memory"))
        #expect(result.contains("Disk"))
        #expect(result.contains("Metric"))
        #expect(!result.contains("--------"))
    }

    @Test("[P0][AC1] Column alignment uses display width (CJK = 2)")
    func columnAlignmentUsesDisplayWidth() {
        let input = """
        | 排名 | 电影     | 票房     | 年份 |
        |------|----------|----------|------|
        | 1    | 阿凡达   | $29.24亿 | 2009 |
        | 2    | 复联4    | $27.99亿 | 2019 |
        """
        let (result, _) = TGMessageFormatter.format(input)

        // Should be in code block
        #expect(result.contains("```"))

        // Data present
        #expect(result.contains("阿凡达"))
        #expect(result.contains("复联4"))
    }

    @Test("[P0][AC1] Separator row with alignment markers (:---:) is removed")
    func separatorRowWithAlignmentMarkersRemoved() {
        let input = """
        | Left | Center | Right |
        |:-----|:------:|------:|
        | L    | C      | R     |
        """
        let (result, _) = TGMessageFormatter.format(input)

        #expect(!result.contains(":-----"))
        #expect(!result.contains("------:"))
        #expect(result.contains("Left"))
        #expect(result.contains("Center"))
        #expect(result.contains("Right"))
    }

    @Test("[P1][AC1] 3-column table with empty cells renders correctly")
    func tableWithEmptyCellsRenders() {
        let input = """
        | Name | Value | Extra |
        |------|-------|-------|
        | Key1 |       | E1    |
        |      | Val2  | E2    |
        | K3   | V3    |       |
        """
        let (result, _) = TGMessageFormatter.format(input)

        #expect(result.contains("```"))
        #expect(result.contains("Key1"))
        #expect(result.contains("Val2"))
        #expect(result.contains("K3"))
    }

    // MARK: - AC2: Table content NOT MarkdownV2-escaped (inside code block)

    @Test("[P0][AC2] 3+ column table content is NOT MarkdownV2-escaped")
    func tableBlockContentNotEscaped() {
        let input = """
        | Setting | Value  | Note |
        |---------|--------|------|
        | path.to | a-b.c  | ok   |
        | host.ip | 1.2.3  | fine |
        """
        let (result, _) = TGMessageFormatter.format(input)

        // Inside code block, dots and dashes should NOT be escaped
        #expect(!result.contains("path\\.to"), "Inside code block, dots should NOT be escaped")
        #expect(!result.contains("a\\-b"), "Inside code block, dashes should NOT be escaped")
    }

    @Test("[P0][AC2] 3+ column table block is a single contiguous code block")
    func tableBlockIsSingleCodeBlock() {
        let input = """
        | Col1 | Col2 | Col3 |
        |------|------|------|
        | A    | B    | X    |
        | C    | D    | Y    |
        | E    | F    | Z    |
        """
        let (result, _) = TGMessageFormatter.format(input)

        let fenceCount = result.components(separatedBy: "```").count - 1
        #expect(fenceCount == 2, "Should have exactly 2 code fences, got \(fenceCount)")
    }

    @Test("[P1][AC2] Table with many rows stays in single code block")
    func manyRowTableInSingleCodeBlock() {
        var rows = ["| ID | Name | Score |"]
        rows.append("|----|------|-------|")
        for i in 1...10 {
            rows.append("| \(i)  | Item\(i) | \(i * 10) |")
        }
        let input = rows.joined(separator: "\n")
        let (result, _) = TGMessageFormatter.format(input)

        let fenceCount = result.components(separatedBy: "```").count - 1
        #expect(fenceCount == 2, "Should be single code block even with many rows")

        for i in 1...10 {
            #expect(result.contains("Item\(i)"), "Row \(i) should be present")
        }
    }

    // MARK: - AC3: Mixed content — table block detected among paragraphs

    @Test("[P0][AC3] 3+ column table between heading and paragraph renders correctly")
    func tableBetweenHeadingAndParagraph() {
        let input = """
        ## Results

        | Metric | Score | Grade |
        |--------|-------|-------|
        | Speed  | 95    | A     |
        | Acc    | 88    | B     |

        This is a conclusion paragraph.
        """
        let (result, _) = TGMessageFormatter.format(input)

        #expect(result.contains("**Results**"), "Heading should render as bold")
        #expect(result.contains("```"), "3+ column table should be in code block")
        #expect(result.contains("conclusion"))
        #expect(!result.contains("--------"))
    }

    @Test("[P0][AC3] 3+ column table after unordered list renders correctly")
    func tableAfterUnorderedList() {
        let input = """
        - Item 1
        - Item 2

        | Key | Val | Extra |
        |-----|-----|-------|
        | A   | B   | C     |
        """
        let (result, _) = TGMessageFormatter.format(input)

        #expect(result.contains("• Item 1"))
        #expect(result.contains("• Item 2"))
        #expect(result.contains("```"))
        #expect(result.contains("Key"))
    }

    @Test("[P0][AC3] 3+ column table preceded and followed by different block types")
    func tableSurroundedByMixedBlocks() {
        let input = """
        # Title

        > A quote

        | X | Y | Z |
        |---|---|---|
        | 1 | 2 | 3 |

        1. First
        2. Second
        """
        let (result, _) = TGMessageFormatter.format(input)

        #expect(result.contains("**Title**"))
        #expect(result.contains(">"))
        #expect(result.contains("```"), "3+ column table should be in code block")
        #expect(result.contains("1\\."))
    }

    @Test("[P1][AC3] Two separate 3+ column tables with text between them")
    func twoSeparateTablesWithTextBetween() {
        let input = """
        | A | B | C |
        |---|---|---|
        | 1 | 2 | 3 |

        Middle text.

        | D | E | F |
        |---|---|---|
        | 4 | 5 | 6 |
        """
        let (result, _) = TGMessageFormatter.format(input)

        let fenceCount = result.components(separatedBy: "```").count - 1
        #expect(fenceCount == 4, "Should have 4 fences (2 tables x 2), got \(fenceCount)")
        #expect(result.contains("Middle text") || result.contains("Middle\\.text"))
    }

    // MARK: - AC4: HTML mode — 3+ column table renders as <pre><code> block

    @Test("[P1][AC4] HTML mode renders 3+ column table as pre-code block")
    func htmlModeRendersTableAsPreCodeBlock() {
        let input = """
        | Name | Value | Type |
        |------|-------|------|
        | Key1 | Val1  | A    |
        | Key2 | Val2  | B    |
        """
        let (result, mode) = TGMessageFormatter.formatAsHTML(input)
        #expect(mode == .html)

        #expect(result.contains("<pre><code>"))
        #expect(result.contains("</code></pre>"))
        #expect(result.contains("Key1"))
        #expect(result.contains("Val2"))
        #expect(!result.contains("------"))
    }

    @Test("[P1][AC4] HTML mode mixed content with 3+ column table")
    func htmlModeMixedContent() {
        let input = """
        ## Stats

        | M | V | U |
        |---|---|---|
        | 1 | 2 | 3 |

        End.
        """
        let (result, _) = TGMessageFormatter.formatAsHTML(input)

        #expect(result.contains("<b>Stats</b>"))
        #expect(result.contains("<pre><code>"))
        #expect(result.contains("End."))
    }

    // MARK: - AC5: Plain mode — 3+ column table renders as indented text

    @Test("[P1][AC5] Plain mode renders 3+ column table as indented aligned text")
    func plainModeRendersTableAsIndented() {
        let input = """
        | Name | Value | Extra |
        |------|-------|-------|
        | A    | B     | C     |
        | CC   | DD    | EE    |
        """
        let (result, mode) = TGMessageFormatter.formatAsPlain(input)
        #expect(mode == .plain)

        #expect(result.contains("Name"))
        #expect(result.contains("CC"))
        #expect(result.contains("DD"))
        #expect(!result.contains("------"))
        #expect(!result.contains("**"))
        #expect(!result.contains("<pre>"))
    }

    @Test("[P1][AC5] Plain mode 3+ column table rows are aligned")
    func plainModeTableRowsAligned() {
        let input = """
        | X | Y | Z |
        |---|---|---|
        | 1 | 2 | 3 |
        | 4 | 5 | 6 |
        """
        let (result, _) = TGMessageFormatter.formatAsPlain(input)

        #expect(result.contains("1"))
        #expect(result.contains("2"))
        #expect(result.contains("4"))
        #expect(result.contains("6"))
    }

    @Test("[P2][AC5] Plain mode 3+ column table after heading")
    func plainModeTableAfterHeading() {
        let input = """
        # Report

        | Col | Val | N |
        |-----|-----|---|
        | A   | B   | 1 |
        """
        let (result, _) = TGMessageFormatter.formatAsPlain(input)

        #expect(result.contains("REPORT"))
        #expect(result.contains("Col"))
    }

    // MARK: - AC6: Split preserves table block integrity

    @Test("[P0][AC6] Split does not break a table code block across chunks")
    func splitPreservesTableBlockIntegrity() {
        var rows = ["| Column1 | Column2 | Column3 |"]
        rows.append("|---------|---------|---------|")
        for i in 1...5 {
            rows.append("| Data\(i)  | Value\(i) | Extra\(i) |")
        }
        let table = rows.joined(separator: "\n")

        let prefix = String(repeating: "A", count: 3000) + "\n\n"
        let suffix = "\n\n" + String(repeating: "B", count: 1000)
        let fullInput = prefix + table + suffix

        let (formatted, _) = TGMessageFormatter.format(fullInput)
        let chunks = TGMessageFormatter.split(formattedText: formatted, parseMode: .markdownV2)

        for (idx, chunk) in chunks.enumerated() {
            let fenceCount = chunk.components(separatedBy: "```").count - 1
            #expect(fenceCount % 2 == 0,
                    "Chunk \(idx) has unbalanced code blocks (\(fenceCount) fences)")
        }
    }

    @Test("[P0][AC6] Oversized table splits with balanced code blocks")
    func oversizedTableSplitsByRows() {
        var rows = ["| Column1 | Column2 | Column3 | Column4 |"]
        rows.append("|---------|---------|---------|---------|")
        for i in 1...100 {
            rows.append("| DataEntryNumber\(i) | ValueDataEntry\(i) | ExtraInfo\(i) | PaddingData\(i) |")
        }
        let table = rows.joined(separator: "\n")
        let (formatted, _) = TGMessageFormatter.format(table)

        #expect(formatted.utf8.count > 4096, "Test table should exceed 4096 bytes, got \(formatted.utf8.count)")

        let chunks = TGMessageFormatter.split(formattedText: formatted, parseMode: .markdownV2)
        #expect(chunks.count > 1, "Large table should be split into multiple chunks")

        for (idx, chunk) in chunks.enumerated() {
            let fenceCount = chunk.components(separatedBy: "```").count - 1
            #expect(fenceCount % 2 == 0,
                    "Chunk \(idx) has unbalanced code blocks: \(fenceCount) fences")
        }
    }

    // MARK: - AC7: 3+ column table uses code block; 2-column and single-row fall back to key/value

    @Test("[P0][AC7] 3+ column multi-row table uses code block")
    func multiColumnTableUsesCodeBlock() {
        let input = """
        | Name | Age | City |
        |------|-----|------|
        | Alice | 30 | NYC |
        | Bob | 25 | LA |
        """
        let (result, _) = TGMessageFormatter.format(input)

        #expect(!result.contains("**Name**:"), "Should not use key/value for 3+ column table")
        #expect(result.contains("```"), "Should use code block for 3+ column table")
    }

    @Test("[P0][AC7] 2-column multi-row table falls back to key/value")
    func twoColumnTableFallsBackToKeyValue() {
        let input = """
        | 项目 | 详情 |
        |------|------|
        | 频道ID | 5762133 |
        | 名称 | 测试频道 |
        """
        let (result, _) = TGMessageFormatter.format(input)

        // 2-column table should NOT be in code block
        #expect(!result.contains("```"), "2-column table should NOT use code block")

        // Should use key/value format with bold key
        #expect(result.contains("**频道ID**:"), "2-column table should use key/value format")
        #expect(result.contains("**名称**:"), "2-column table should use key/value format")
    }

    @Test("[P0][AC7] Single-row table falls back to key/value")
    func singleRowTableFallsBackToKeyValue() {
        let input = "| Key | Value |"
        let (result, _) = TGMessageFormatter.format(input)

        #expect(result.contains("**Key**:"), "Single row should use key/value fallback")
        #expect(result.contains("Value"))
    }

    // MARK: - Edge Cases

    @Test("[P2] 3+ column table with special characters renders correctly in code block")
    func tableWithSpecialCharsInCells() {
        let input = """
        | Setting | Value | Cat |
        |---------|-------|-----|
        | regex   | a.*b  | R   |
        | path    | /a/b  | P   |
        """
        let (result, _) = TGMessageFormatter.format(input)

        #expect(result.contains("```"))
        #expect(result.contains("a.*b"))
        #expect(result.contains("/a/b"))
    }

    @Test("[P2] Table cell containing pipe character is handled correctly")
    func tableWithPipeInCellContent() {
        let input = """
        | Name | Cmd | Note |
        |------|-----|------|
        | Pipe | a \\| b | ok |
        """
        let (result, _) = TGMessageFormatter.format(input)
        #expect(result.contains("Pipe"))
    }

    @Test("[P2] Consecutive 3+ column tables without blank line rendered as separate blocks")
    func consecutiveTablesWithoutBlankLine() {
        let input = """
        | A | B | C |
        |---|---|---|
        | 1 | 2 | 3 |
        | D | E | F |
        |---|---|---|
        | 4 | 5 | 6 |
        """
        let (result, _) = TGMessageFormatter.format(input)

        let fenceCount = result.components(separatedBy: "```").count - 1
        #expect(fenceCount == 4, "Should have 4 fences (2 tables x 2), got \(fenceCount)")

        #expect(!result.contains("---"))
        #expect(result.contains("1"))
        #expect(result.contains("4"))
        #expect(result.contains("D"))
    }
}

// MARK: - Test Helpers

extension String {
    func extractCodeBlockContent() -> String {
        let parts = self.components(separatedBy: "```")
        guard parts.count >= 3 else { return "" }
        return parts[1]
    }
}
