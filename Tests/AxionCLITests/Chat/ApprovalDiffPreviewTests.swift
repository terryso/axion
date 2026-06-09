import Testing
import Foundation

@testable import AxionCLI

// MARK: - ApprovalDiffPreview Tests

@Suite("ApprovalDiffPreview Tests")
struct ApprovalDiffPreviewTests {

    // MARK: - Config Tests

    @Test("Config defaults to non-TTY in test environment")
    func config_defaults_nonTTY() {
        let config = ApprovalDiffPreview.Config()
        #expect(config.maxPreviewLines == 15)
        // Test env is non-TTY → profile should be .unknown
        #expect(!config.isTTY || config.profile == .unknown)
    }

    @Test("Config custom values")
    func config_customValues() {
        let config = ApprovalDiffPreview.Config(
            maxPreviewLines: 5,
            isTTY: true,
            profile: .ansi16
        )
        #expect(config.maxPreviewLines == 5)
        #expect(config.isTTY == true)
        #expect(config.profile == .ansi16)
    }

    @Test("Config isTTY=false forces profile to unknown")
    func config_nonTTY_forcesUnknownProfile() {
        let config = ApprovalDiffPreview.Config(
            isTTY: false,
            profile: .trueColor
        )
        #expect(config.profile == .unknown)
    }

    // MARK: - Edit Preview (non-TTY)

    @Test("renderEditPreview non-TTY shows plain text summary and diff")
    func editPreview_nonTTY_plainText() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "Sources/Foo.swift",
            oldString: "line1\nline2\nline3",
            newString: "line1\nmodified\nline3",
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("Sources/Foo.swift"))
        // Non-TTY should show plain +/- lines
        #expect(result!.contains("-line2"))
        #expect(result!.contains("+modified"))
        // Should NOT contain ANSI escape codes
        #expect(!result!.contains("\u{1B}["))
    }

    @Test("renderEditPreview non-TTY with added lines")
    func editPreview_nonTTY_addedLines() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "Test.swift",
            oldString: "line1",
            newString: "line1\nline2\nline3",
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("+line2"))
        #expect(result!.contains("+line3"))
    }

    @Test("renderEditPreview non-TTY with removed lines")
    func editPreview_nonTTY_removedLines() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "Test.swift",
            oldString: "line1\nline2\nline3",
            newString: "line1",
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("-line2"))
        #expect(result!.contains("-line3"))
    }

    // MARK: - Edit Preview (TTY with colors)

    @Test("renderEditPreview TTY shows ANSI colored diff")
    func editPreview_tty_colored() {
        let config = ApprovalDiffPreview.Config(isTTY: true, profile: .trueColor)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "Sources/Bar.swift",
            oldString: "old line",
            newString: "new line",
            config: config
        )

        #expect(result != nil)
        // Should contain ANSI escape codes for colors
        #expect(result!.contains("\u{1B}["))
        // Should contain green (added) and red (removed) codes
        #expect(result!.contains("+new line"))
        #expect(result!.contains("-old line"))
        // Should contain the separator
        #expect(result!.contains("Changes"))
    }

    @Test("renderEditPreview TTY ansi256 profile")
    func editPreview_tty_ansi256() {
        let config = ApprovalDiffPreview.Config(isTTY: true, profile: .ansi256)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "File.swift",
            oldString: "a",
            newString: "b",
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("\u{1B}[38;5;"))  // ANSI 256 color codes
    }

    @Test("renderEditPreview TTY ansi16 profile")
    func editPreview_tty_ansi16() {
        let config = ApprovalDiffPreview.Config(isTTY: true, profile: .ansi16)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "File.swift",
            oldString: "x",
            newString: "y",
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("\u{1B}[32m"))  // ANSI 16 green
        #expect(result!.contains("\u{1B}[31m"))  // ANSI 16 red
    }

    // MARK: - Edit Preview (summary line)

    @Test("renderEditPreview summary shows removed and added counts")
    func editPreview_summary_bothRemovedAndAdded() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "App.swift",
            oldString: "a\nb\nc",
            newString: "a\nx\ny\nz\nc",
            config: config
        )

        #expect(result != nil)
        // Summary line should show -/+ counts
        let firstLine = result!.components(separatedBy: "\n").first!
        #expect(firstLine.contains("App.swift"))
        #expect(firstLine.contains("-"))
        #expect(firstLine.contains("+"))
    }

    @Test("renderEditPreview summary for same line count shows replacement")
    func editPreview_summary_sameLineCount() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "File.swift",
            oldString: "a\nb\nc",
            newString: "x\ny\nz",
            config: config
        )

        #expect(result != nil)
        let firstLine = result!.components(separatedBy: "\n").first!
        #expect(firstLine.contains("File.swift"))
    }

    // MARK: - Edit Preview (common prefix/suffix detection)

    @Test("renderEditPreview detects common prefix")
    func editPreview_commonPrefix() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "Test.swift",
            oldString: "import Foundation\nold code\nfunc main()",
            newString: "import Foundation\nnew code\nfunc main()",
            config: config
        )

        #expect(result != nil)
        // Should show context lines for common prefix/suffix
        #expect(result!.contains("import Foundation"))
        #expect(result!.contains("-old code"))
        #expect(result!.contains("+new code"))
    }

    @Test("renderEditPreview detects common suffix")
    func editPreview_commonSuffix() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "Test.swift",
            oldString: "header\nremoved1\nremoved2\nfooter",
            newString: "header\nadded1\nfooter",
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("-removed1"))
        #expect(result!.contains("-removed2"))
        #expect(result!.contains("+added1"))
    }

    @Test("renderEditPreview fully identical returns replacement summary")
    func editPreview_identical() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "Same.swift",
            oldString: "line1\nline2",
            newString: "line1\nline2",
            config: config
        )

        // Identical strings → no actual changes, summary shows "替换 N 行"
        #expect(result != nil)
        #expect(result!.contains("Same.swift"))
        #expect(result!.contains("替换 2 行"))
        // Should not contain diff markers
        #expect(!result!.contains("+line"))
        #expect(!result!.contains("-line"))
    }

    // MARK: - Edit Preview (truncation)

    @Test("renderEditPreview truncates long diffs with notice")
    func editPreview_truncation() {
        let config = ApprovalDiffPreview.Config(maxPreviewLines: 3, isTTY: false)

        // Create 10-line old → 10-line new (all different)
        let oldLines = (1...10).map { "old_\($0)" }.joined(separator: "\n")
        let newLines = (1...10).map { "new_\($0)" }.joined(separator: "\n")

        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "Long.swift",
            oldString: oldLines,
            newString: newLines,
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("还有"))
        #expect(result!.contains("行差异未显示"))
    }

    @Test("renderEditPreview TTY truncation shows colored notice")
    func editPreview_tty_truncation() {
        let config = ApprovalDiffPreview.Config(maxPreviewLines: 2, isTTY: true, profile: .trueColor)

        let oldLines = (1...8).map { "old_\($0)" }.joined(separator: "\n")
        let newLines = (1...8).map { "new_\($0)" }.joined(separator: "\n")

        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "Big.swift",
            oldString: oldLines,
            newString: newLines,
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("还有"))
        #expect(result!.contains("\u{1B}["))  // ANSI codes present
    }

    // MARK: - Write Preview

    @Test("renderWritePreview non-TTY shows plain text preview")
    func writePreview_nonTTY() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderWritePreview(
            filePath: "NewFile.swift",
            content: "import Foundation\n\nclass Foo {}\n",
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("NewFile.swift"))
        #expect(result!.contains("+import Foundation"))
        #expect(result!.contains("+class Foo {}"))
    }

    @Test("renderWritePreview TTY shows colored preview")
    func writePreview_tty() {
        let config = ApprovalDiffPreview.Config(isTTY: true, profile: .trueColor)
        let result = ApprovalDiffPreview.renderWritePreview(
            filePath: "App.swift",
            content: "line1\nline2\nline3",
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("\u{1B}["))
        #expect(result!.contains("+line1"))
        #expect(result!.contains("Changes"))
    }

    @Test("renderWritePreview returns nil for empty content")
    func writePreview_empty_returnsNil() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderWritePreview(
            filePath: "Empty.swift",
            content: "",
            config: config
        )
        #expect(result == nil)
    }

    @Test("renderWritePreview shows correct line count in summary")
    func writePreview_correctLineCount() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderWritePreview(
            filePath: "File.swift",
            content: "line1\nline2\nline3\n",
            config: config
        )

        #expect(result != nil)
        // Trailing empty line from trailing \n should be trimmed → 3 lines
        let firstLine = result!.components(separatedBy: "\n").first!
        #expect(firstLine.contains("3 行"))
    }

    @Test("renderWritePreview single line summary uses singular form")
    func writePreview_singleLine() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderWritePreview(
            filePath: "One.swift",
            content: "only line",
            config: config
        )

        #expect(result != nil)
        let firstLine = result!.components(separatedBy: "\n").first!
        #expect(firstLine.contains("1 行"))
    }

    @Test("renderWritePreview truncates long content")
    func writePreview_truncation() {
        let config = ApprovalDiffPreview.Config(maxPreviewLines: 3, isTTY: false)
        let content = (1...20).map { "line_\($0)" }.joined(separator: "\n")

        let result = ApprovalDiffPreview.renderWritePreview(
            filePath: "BigFile.swift",
            content: content,
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("还有"))
        #expect(result!.contains("行差异未显示"))
    }

    // MARK: - Edge Cases

    @Test("renderEditPreview with multiline old/new strings")
    func editPreview_multiline() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let oldStr = """
        func hello() {
            print("old")
        }
        """
        let newStr = """
        func hello() {
            print("new")
            print("extra")
        }
        """

        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "Code.swift",
            oldString: oldStr,
            newString: newStr,
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("-    print(\"old\")"))
        #expect(result!.contains("+    print(\"new\")"))
        #expect(result!.contains("+    print(\"extra\")"))
    }

    @Test("renderEditPreview with empty old_string")
    func editPreview_emptyOld() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "Insert.swift",
            oldString: "",
            newString: "new content",
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("+new content"))
    }

    @Test("renderEditPreview with empty new_string")
    func editPreview_emptyNew() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "Delete.swift",
            oldString: "old content",
            newString: "",
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("-old content"))
    }

    @Test("renderEditPreview very long lines are truncated")
    func editPreview_longLines_truncated() {
        let config = ApprovalDiffPreview.Config(isTTY: true, profile: .trueColor)
        let longLine = String(repeating: "x", count: 200)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "Wide.swift",
            oldString: longLine,
            newString: "short",
            config: config
        )

        #expect(result != nil)
        // The old line should be truncated (maxChars=78 → 77 chars + …)
        // Check that the result doesn't contain the full 200-char line in a diff line
        #expect(result!.contains("…"))
    }

    @Test("renderEditPreview handles Unicode content correctly")
    func editPreview_unicode() {
        let config = ApprovalDiffPreview.Config(isTTY: false)
        let result = ApprovalDiffPreview.renderEditPreview(
            filePath: "中文.swift",
            oldString: "旧代码 🚀",
            newString: "新代码 ✨",
            config: config
        )

        #expect(result != nil)
        #expect(result!.contains("-旧代码 🚀"))
        #expect(result!.contains("+新代码 ✨"))
    }

    // MARK: - ApprovalRenderer Integration

    @Test("ApprovalRenderer.renderDiffSummary uses enhanced preview for Edit")
    func approvalRenderer_editDiffSummary() {
        let input: [String: Any] = [
            "old_string": "old line",
            "new_string": "new line",
            "file_path": "Test.swift"
        ]
        let result = ApprovalRenderer.renderDiffSummary(toolName: "Edit", input: input)

        #expect(result != nil)
        // In test env (non-TTY), should show plain text diff
        #expect(result!.contains("Test.swift"))
    }

    @Test("ApprovalRenderer.renderDiffSummary uses enhanced preview for Write")
    func approvalRenderer_writeDiffSummary() {
        let input: [String: Any] = [
            "content": "import Foundation\n\nclass Foo {}",
            "file_path": "New.swift"
        ]
        let result = ApprovalRenderer.renderDiffSummary(toolName: "Write", input: input)

        #expect(result != nil)
        #expect(result!.contains("New.swift"))
    }

    @Test("ApprovalRenderer.renderDiffSummary returns nil for unknown tools")
    func approvalRenderer_unknownTool() {
        let input: [String: Any] = ["command": "ls"]
        let result = ApprovalRenderer.renderDiffSummary(toolName: "Bash", input: input)
        #expect(result == nil)
    }

    @Test("ApprovalRenderer.renderDiffSummary Edit returns nil for missing keys")
    func approvalRenderer_editMissingKeys() {
        let input: [String: Any] = ["file_path": "Test.swift"]
        let result = ApprovalRenderer.renderDiffSummary(toolName: "Edit", input: input)
        #expect(result == nil)
    }
}
