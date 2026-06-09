import Testing
import Foundation

@testable import AxionCLI

@Suite("StreamingCodeBlockRenderer Diff Rendering")
struct StreamingCodeBlockRendererDiffTests {

    // MARK: - Diff Language Detection

    @Test("detects 'diff' language and applies diff coloring")
    func testDiffLanguageDetection() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()
        r.process("+added line\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("│"))
        #expect(combined.contains("+added line"))
        // Should contain green color code for added line
        #expect(combined.contains("\u{1B}[38;2;76;175;80m"))
    }

    @Test("detects 'patch' language as diff")
    func testPatchLanguageDetection() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        r.process("```patch\n") { output.append($0) }
        output.removeAll()
        r.process("-removed line\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("-removed line"))
        // Should contain red color code for removed line
        #expect(combined.contains("\u{1B}[38;2;244;67;54m"))
    }

    @Test("detects 'udiff' language as diff")
    func testUdiffLanguageDetection() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        r.process("```udiff\n") { output.append($0) }
        output.removeAll()
        r.process("+new code\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("+new code"))
        #expect(combined.contains("\u{1B}[38;2;76;175;80m"))
    }

    // MARK: - Auto-detection from Content

    @Test("auto-detects diff from 'diff --git' first content line")
    func testAutoDetectDiffFromContent() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 80)
        var output: [String] = []
        var r = renderer

        // No diff language tag — just a plain code block
        r.process("```\n") { output.append($0) }
        output.removeAll()
        // First content line starts with "diff --git" → triggers diff mode
        r.process("diff --git a/file.swift b/file.swift\n") { output.append($0) }
        let headerCombined = output.joined()
        #expect(headerCombined.contains("diff --git"))
        // File header should use purple-blue color
        #expect(headerCombined.contains("\u{1B}[38;2;129;140;248m"))

        output.removeAll()
        r.process("+added content\n") { output.append($0) }
        let addedCombined = output.joined()
        #expect(addedCombined.contains("+added content"))
        // Should now use green color (diff mode activated)
        #expect(addedCombined.contains("\u{1B}[38;2;76;175;80m"))

        output.removeAll()
        r.process("```\n") { output.append($0) }
    }

    @Test("does not auto-detect diff when first line is not diff header")
    func testNoAutoDetectDiffWhenNotDiffContent() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        r.process("```\n") { output.append($0) }
        output.removeAll()
        // First content line is NOT a diff header
        r.process("let x = 1\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("let x = 1"))
        // Should use standard dim style, not diff green
        #expect(!combined.contains("\u{1B}[38;2;76;175;80m"))
    }

    // MARK: - Diff Line Type Coloring

    @Test("colors added lines green in TrueColor")
    func testAddedLineTrueColor() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()
        r.process("+new function() {\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("│"))
        #expect(combined.contains("+new function() {"))
        #expect(combined.contains("\u{1B}[38;2;76;175;80m"))
    }

    @Test("colors removed lines red in TrueColor")
    func testRemovedLineTrueColor() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()
        r.process("-old code here\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("-old code here"))
        #expect(combined.contains("\u{1B}[38;2;244;67;54m"))
    }

    @Test("colors hunk headers with dim cyan in TrueColor")
    func testHunkHeaderTrueColor() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 80)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()
        r.process("@@ -10,7 +10,8 @@ class Foo {\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("@@ -10,7 +10,8 @@ class Foo {"))
        #expect(combined.contains("\u{1B}[38;2;100;150;170m"))
    }

    @Test("colors file headers with purple-blue in TrueColor")
    func testFileHeaderTrueColor() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 80)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()
        r.process("diff --git a/file.swift b/file.swift\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("diff --git"))
        #expect(combined.contains("\u{1B}[38;2;129;140;248m"))
    }

    @Test("colors --- and +++ file headers with purple-blue")
    func testOldNewFileHeaders() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 80)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()
        r.process("--- a/file.swift\n") { output.append($0) }
        let oldCombined = output.joined()
        #expect(oldCombined.contains("--- a/file.swift"))
        #expect(oldCombined.contains("\u{1B}[38;2;129;140;248m"))

        output.removeAll()
        r.process("+++ b/file.swift\n") { output.append($0) }
        let newCombined = output.joined()
        #expect(newCombined.contains("+++ b/file.swift"))
        #expect(newCombined.contains("\u{1B}[38;2;129;140;248m"))
    }

    @Test("colors context lines with dim")
    func testContextLines() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()
        // Context lines start with a space
        r.process(" unchanged line\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains(" unchanged line"))
        // Context lines should use dim color, not green or red
        #expect(!combined.contains("\u{1B}[38;2;76;175;80m"))
        #expect(!combined.contains("\u{1B}[38;2;244;67;54m"))
    }

    // MARK: - Complete Diff Block

    @Test("renders complete diff block with all line types")
    func testCompleteDiffBlock() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 80)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()

        r.process("diff --git a/hello.swift b/hello.swift\n") { output.append($0) }
        r.process("index abc123..def456 100644\n") { output.append($0) }
        r.process("--- a/hello.swift\n") { output.append($0) }
        r.process("+++ b/hello.swift\n") { output.append($0) }
        r.process("@@ -1,5 +1,6 @@\n") { output.append($0) }
        r.process(" import Foundation\n") { output.append($0) }
        r.process("+import AxionCore\n") { output.append($0) }
        r.process(" \n") { output.append($0) }
        r.process("-print(\"hello\")\n") { output.append($0) }
        r.process("+print(\"world\")\n") { output.append($0) }
        r.process("```\n") { output.append($0) }

        let combined = output.joined()

        // Verify all content preserved
        #expect(combined.contains("diff --git"))
        #expect(combined.contains("--- a/hello.swift"))
        #expect(combined.contains("+++ b/hello.swift"))
        #expect(combined.contains("@@ -1,5 +1,6 @@"))
        #expect(combined.contains("import Foundation"))
        #expect(combined.contains("+import AxionCore"))
        #expect(combined.contains("-print(\"hello\")"))
        #expect(combined.contains("+print(\"world\")"))

        // Verify color codes present
        let green = "\u{1B}[38;2;76;175;80m"
        let red = "\u{1B}[38;2;244;67;54m"
        let purple = "\u{1B}[38;2;129;140;248m"

        #expect(combined.contains(green))   // +import AxionCore, +print("world")
        #expect(combined.contains(red))     // -print("hello")
        #expect(combined.contains(purple))  // diff --git, ---, +++

        // Verify no raw fence markers
        #expect(!combined.contains("```diff"))
        #expect(!combined.contains("```\n"))

        // Verify close border present
        #expect(combined.contains("╯"))
    }

    // MARK: - Color Profile Degradation

    @Test("diff rendering works with ANSI256 profile")
    func testDiffANSI256() {
        let renderer = StreamingCodeBlockRenderer(profile: .ansi256, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()
        r.process("+added\n") { output.append($0) }
        r.process("-removed\n") { output.append($0) }

        let combined = output.joined()
        // ANSI256 green
        #expect(combined.contains("\u{1B}[38;5;71m"))
        // ANSI256 red
        #expect(combined.contains("\u{1B}[38;5;160m"))
    }

    @Test("diff rendering works with ANSI16 profile")
    func testDiffANSI16() {
        let renderer = StreamingCodeBlockRenderer(profile: .ansi16, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()
        r.process("+added\n") { output.append($0) }
        r.process("-removed\n") { output.append($0) }

        let combined = output.joined()
        // ANSI16 green
        #expect(combined.contains("\u{1B}[32m"))
        // ANSI16 red
        #expect(combined.contains("\u{1B}[31m"))
    }

    @Test("diff rendering with unknown profile uses no color codes")
    func testDiffUnknownProfile() {
        let renderer = StreamingCodeBlockRenderer(profile: .unknown, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()
        r.process("+added\n") { output.append($0) }
        r.process("-removed\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("+added"))
        #expect(combined.contains("-removed"))
        // No color codes in unknown profile
        #expect(!combined.contains("\u{1B}[38;2;"))
        #expect(!combined.contains("\u{1B}[38;5;"))
        #expect(!combined.contains("\u{1B}[3"))
    }

    // MARK: - Non-TTY Passthrough

    @Test("non-TTY passes through diff content without coloring")
    func testDiffNonTTYPassthrough() {
        let renderer = StreamingCodeBlockRenderer(profile: .unknown, isTTY: false)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        r.process("+added line\n") { output.append($0) }
        r.process("-removed line\n") { output.append($0) }
        r.process("```\n") { output.append($0) }

        let combined = output.joined()
        // Non-TTY: raw markdown passthrough
        #expect(combined.contains("```diff"))
        #expect(combined.contains("+added line"))
        #expect(combined.contains("-removed line"))
        #expect(combined.contains("```"))
    }

    // MARK: - Diff State Reset

    @Test("diff state resets when code block closes")
    func testDiffStateResetsOnBlockClose() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        // First block: diff
        r.process("```diff\n") { output.append($0) }
        r.process("+added\n") { output.append($0) }
        r.process("```\n") { output.append($0) }

        // Second block: regular code
        output.removeAll()
        r.process("```swift\n") { output.append($0) }
        output.removeAll()
        r.process("let x = 1\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("let x = 1"))
        // Regular code block should NOT have diff green coloring
        #expect(!combined.contains("\u{1B}[38;2;76;175;80m"))
    }

    @Test("diff state resets on renderer reset()")
    func testDiffStateResetsOnReset() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        // Start a diff block
        r.process("```diff\n") { output.append($0) }
        r.process("+added\n") { output.append($0) }

        // Reset (simulates turn boundary)
        r.reset()
        #expect(r.inCodeBlock == false)

        // After reset, new code block should not inherit diff state
        output.removeAll()
        r.process("```swift\n") { output.append($0) }
        output.removeAll()
        r.process("let x = 1\n") { output.append($0) }

        let combined = output.joined()
        #expect(!combined.contains("\u{1B}[38;2;76;175,80m"))
    }

    // MARK: - Edge Cases

    @Test("+++ and --- are treated as file headers, not added/removed lines")
    func testTriplePlusMinusAreFileHeaders() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 80)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()

        r.process("--- a/file.txt\n") { output.append($0) }
        let oldHeader = output.joined()
        // --- should be purple-blue file header, NOT red removed line
        #expect(oldHeader.contains("\u{1B}[38;2;129;140;248m"))
        #expect(!oldHeader.contains("\u{1B}[38;2;244;67;54m"))

        output.removeAll()
        r.process("+++ b/file.txt\n") { output.append($0) }
        let newHeader = output.joined()
        // +++ should be purple-blue file header, NOT green added line
        #expect(newHeader.contains("\u{1B}[38;2;129;140;248m"))
        #expect(!newHeader.contains("\u{1B}[38;2;76;175;80m"))
    }

    @Test("handles diff with only added lines")
    func testDiffOnlyAddedLines() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()
        r.process("+line 1\n") { output.append($0) }
        r.process("+line 2\n") { output.append($0) }
        r.process("+line 3\n") { output.append($0) }
        r.process("```\n") { output.append($0) }

        let combined = output.joined()
        let greenCount = combined.components(separatedBy: "\u{1B}[38;2;76;175;80m").count - 1
        #expect(greenCount == 3)
    }

    @Test("handles diff with only removed lines")
    func testDiffOnlyRemovedLines() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()
        r.process("-line 1\n") { output.append($0) }
        r.process("-line 2\n") { output.append($0) }
        r.process("```\n") { output.append($0) }

        let combined = output.joined()
        let redCount = combined.components(separatedBy: "\u{1B}[38;2;244;67;54m").count - 1
        #expect(redCount == 2)
    }

    @Test("handles empty lines in diff block")
    func testDiffWithEmptyLines() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        r.process("```diff\n") { output.append($0) }
        output.removeAll()
        r.process("+added\n") { output.append($0) }
        r.process("\n") { output.append($0) }
        r.process("+more\n") { output.append($0) }
        r.process("```\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("+added"))
        #expect(combined.contains("+more"))
        // Empty line should be between them
        #expect(combined.contains("│"))
    }

    @Test("regular code block after diff block is not affected")
    func testRegularCodeAfterDiff() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        // Diff block
        r.process("```diff\n") { output.append($0) }
        r.process("+added\n") { output.append($0) }
        r.process("```\n") { output.append($0) }

        // Plain text between blocks
        r.process("Some explanation\n") { output.append($0) }

        // Regular code block
        r.process("```python\n") { output.append($0) }
        output.removeAll()
        r.process("x = 1\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("x = 1"))
        // Should use standard dim style, not diff green
        #expect(!combined.contains("\u{1B}[38;2;76;175;80m"))
    }

    @Test("handles diff block split across chunks")
    func testDiffSplitAcrossChunks() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        // Split fence and content across multiple chunks
        r.process("``") { output.append($0) }
        r.process("`diff\n") { output.append($0) }
        output.removeAll()
        r.process("+add") { output.append($0) }
        r.process("ed line\n") { output.append($0) }
        r.process("```\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("+added line"))
        #expect(combined.contains("\u{1B}[38;2;76;175;80m"))
    }
}
