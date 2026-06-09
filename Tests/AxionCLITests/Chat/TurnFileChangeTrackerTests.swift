import Foundation
import Testing

@testable import AxionCLI

// MARK: - TurnFileChangeTracker Tests

@Suite("TurnFileChangeTracker")
struct TurnFileChangeTrackerTests {

    // MARK: - recordToolUse

    @Test("recordToolUse ignores non-file tools")
    func test_recordToolUse_ignoresNonFileTools() {
        var tracker = TurnFileChangeTracker()
        tracker.recordToolUse(toolName: "Bash", input: #"{"command": "ls"}"#)
        tracker.recordToolUse(toolName: "Read", input: #"{"file_path": "/tmp/test.swift"}"#)
        #expect(tracker.changes.isEmpty)
    }

    @Test("recordToolUse tracks Edit tool with line changes")
    func test_recordToolUse_editTool() {
        var tracker = TurnFileChangeTracker()
        let input = """
            {"file_path":"Sources/Test.swift","old_string":"line1\\nline2\\nline3","new_string":"line1\\nline4"}
            """
        tracker.recordToolUse(toolName: "Edit", input: input)

        #expect(tracker.changes.count == 1)
        let change = tracker.changes[0]
        #expect(change.filePath == "Sources/Test.swift")
        // Gross change: 3 old lines removed, 2 new lines added
        #expect(change.addedLines == 2)
        #expect(change.removedLines == 3)
    }

    @Test("recordToolUse tracks Edit tool with only additions")
    func test_recordToolUse_editAdditionOnly() {
        var tracker = TurnFileChangeTracker()
        let input = """
            {"file_path":"Sources/Add.swift","old_string":"line1","new_string":"line1\\nline2\\nline3"}
            """
        tracker.recordToolUse(toolName: "Edit", input: input)

        #expect(tracker.changes.count == 1)
        let change = tracker.changes[0]
        // Gross: 1 removed, 3 added
        #expect(change.addedLines == 3)
        #expect(change.removedLines == 1)
    }

    @Test("recordToolUse tracks Edit tool with only removals")
    func test_recordToolUse_editRemovalOnly() {
        var tracker = TurnFileChangeTracker()
        let input = """
            {"file_path":"Sources/Remove.swift","old_string":"a\\nb\\nc","new_string":"a"}
            """
        tracker.recordToolUse(toolName: "Edit", input: input)

        #expect(tracker.changes.count == 1)
        let change = tracker.changes[0]
        // Gross: 3 removed, 1 added
        #expect(change.addedLines == 1)
        #expect(change.removedLines == 3)
    }

    @Test("recordToolUse tracks Edit tool with same line count (pure replacement)")
    func test_recordToolUse_editSameLineCount() {
        var tracker = TurnFileChangeTracker()
        let input = """
            {"file_path":"Sources/Replace.swift","old_string":"old1\\nold2","new_string":"new1\\nnew2"}
            """
        tracker.recordToolUse(toolName: "Edit", input: input)

        #expect(tracker.changes.count == 1)
        let change = tracker.changes[0]
        // Gross: 2 removed, 2 added (replacement of equal size)
        #expect(change.addedLines == 2)
        #expect(change.removedLines == 2)
    }

    @Test("recordToolUse tracks Write tool with line count")
    func test_recordToolUse_writeTool() {
        var tracker = TurnFileChangeTracker()
        let input = """
            {"file_path":"Sources/New.swift","content":"line1\\nline2\\nline3\\nline4\\nline5"}
            """
        tracker.recordToolUse(toolName: "Write", input: input)

        #expect(tracker.changes.count == 1)
        let change = tracker.changes[0]
        #expect(change.filePath == "Sources/New.swift")
        #expect(change.addedLines == 5)
        #expect(change.removedLines == 0)
    }

    @Test("recordToolUse handles invalid JSON gracefully")
    func test_recordToolUse_invalidJSON() {
        var tracker = TurnFileChangeTracker()
        tracker.recordToolUse(toolName: "Edit", input: "not valid json")
        #expect(tracker.changes.isEmpty)
    }

    @Test("recordToolUse handles missing keys gracefully")
    func test_recordToolUse_missingKeys() {
        var tracker = TurnFileChangeTracker()
        tracker.recordToolUse(toolName: "Edit", input: #"{"file_path":"test.swift"}"#)
        #expect(tracker.changes.isEmpty)

        tracker.recordToolUse(toolName: "Write", input: #"{"file_path":"test.swift"}"#)
        #expect(tracker.changes.isEmpty)
    }

    @Test("recordToolUse tracks multiple changes to different files")
    func test_recordToolUse_multipleFiles() {
        var tracker = TurnFileChangeTracker()
        tracker.recordToolUse(
            toolName: "Edit",
            input: #"{"file_path":"A.swift","old_string":"x","new_string":"x\ny"}"#
        )
        tracker.recordToolUse(
            toolName: "Write",
            input: #"{"file_path":"B.swift","content":"line1\nline2\nline3"}"#
        )
        tracker.recordToolUse(
            toolName: "Edit",
            input: #"{"file_path":"C.swift","old_string":"a\nb\nc","new_string":"d"}"#
        )
        #expect(tracker.changes.count == 3)
    }

    @Test("recordToolUse tracks multiple edits to same file")
    func test_recordToolUse_sameFileMultipleEdits() {
        var tracker = TurnFileChangeTracker()
        tracker.recordToolUse(
            toolName: "Edit",
            input: #"{"file_path":"Test.swift","old_string":"a","new_string":"a\nb"}"#
        )
        tracker.recordToolUse(
            toolName: "Edit",
            input: #"{"file_path":"Test.swift","old_string":"c","new_string":"c\nd\ne"}"#
        )
        #expect(tracker.changes.count == 2)
        #expect(tracker.deduplicatedChanges.count == 1)

        let merged = tracker.deduplicatedChanges[0]
        #expect(merged.filePath == "Test.swift")
        // Gross: edit1 (+2, -1), edit2 (+3, -1) → merged (+5, -2)
        #expect(merged.addedLines == 5)
        #expect(merged.removedLines == 2)
    }

    // MARK: - reset

    @Test("reset clears all tracked changes")
    func test_reset() {
        var tracker = TurnFileChangeTracker()
        tracker.recordToolUse(
            toolName: "Edit",
            input: #"{"file_path":"Test.swift","old_string":"a","new_string":"b"}"#
        )
        #expect(tracker.hasChanges)

        tracker.reset()
        #expect(!tracker.hasChanges)
        #expect(tracker.changes.isEmpty)
    }

    // MARK: - hasChanges

    @Test("hasChanges is false initially")
    func test_hasChanges_initial() {
        let tracker = TurnFileChangeTracker()
        #expect(!tracker.hasChanges)
    }

    // MARK: - FileChange.displayString

    @Test("FileChange displayString with additions and removals")
    func test_fileChangeDisplayString_both() {
        let change = TurnFileChangeTracker.FileChange(
            filePath: "Test.swift", addedLines: 5, removedLines: 3
        )
        #expect(change.displayString == "Test.swift (+5 -3)")
    }

    @Test("FileChange displayString with additions only")
    func test_fileChangeDisplayString_addedOnly() {
        let change = TurnFileChangeTracker.FileChange(
            filePath: "Test.swift", addedLines: 10, removedLines: 0
        )
        #expect(change.displayString == "Test.swift (+10)")
    }

    @Test("FileChange displayString with removals only")
    func test_fileChangeDisplayString_removedOnly() {
        let change = TurnFileChangeTracker.FileChange(
            filePath: "Test.swift", addedLines: 0, removedLines: 7
        )
        #expect(change.displayString == "Test.swift (-7)")
    }

    @Test("FileChange displayString with no changes")
    func test_fileChangeDisplayString_none() {
        let change = TurnFileChangeTracker.FileChange(
            filePath: "Test.swift", addedLines: 0, removedLines: 0
        )
        #expect(change.displayString == "Test.swift")
    }

    // MARK: - renderSummary

    @Test("renderSummary returns nil when no changes")
    func test_renderSummary_noChanges() {
        let tracker = TurnFileChangeTracker()
        #expect(tracker.renderSummary(isTTY: false) == nil)
    }

    @Test("renderSummary plain text format")
    func test_renderSummary_plainText() {
        var tracker = TurnFileChangeTracker()
        tracker.recordToolUse(
            toolName: "Edit",
            input: #"{"file_path":"Sources/Test.swift","old_string":"a\nb","new_string":"x\ny\nz"}"#
        )
        let result = tracker.renderSummary(isTTY: false, profile: .unknown)
        #expect(result != nil)
        #expect(result!.contains("[changes:"))
        #expect(result!.contains("1 file changed"))
        // Gross: 2 removed, 3 added
        #expect(result!.contains("+3 -2"))
        #expect(result!.contains("[change:"))
    }

    @Test("renderSummary plain text with multiple files")
    func test_renderSummary_plainTextMultiple() {
        var tracker = TurnFileChangeTracker()
        tracker.recordToolUse(
            toolName: "Edit",
            input: #"{"file_path":"A.swift","old_string":"x","new_string":"x\ny"}"#
        )
        tracker.recordToolUse(
            toolName: "Write",
            input: #"{"file_path":"B.swift","content":"line1\nline2"}"#
        )
        let result = tracker.renderSummary(isTTY: false, profile: .unknown)
        #expect(result != nil)
        #expect(result!.contains("2 files changed"))
        // A.swift: +2 -1 (gross), B.swift: +2 (write) → total +4 -1
        #expect(result!.contains("+4 -1"))
    }

    @Test("renderSummary TTY format contains ANSI codes")
    func test_renderSummary_ttyFormat() {
        var tracker = TurnFileChangeTracker()
        tracker.recordToolUse(
            toolName: "Edit",
            input: #"{"file_path":"Sources/Test.swift","old_string":"a","new_string":"a\nb"}"#
        )
        let result = tracker.renderSummary(isTTY: true, profile: .trueColor)
        #expect(result != nil)
        // Should contain dim ANSI code
        #expect(result!.contains("\u{1B}[38;2;120;120;120m"))
        // Should contain green for additions
        #expect(result!.contains("\u{1B}[38;2;76;175;80m"))
        // Should contain reset
        #expect(result!.contains("\u{1B}[0m"))
    }

    @Test("renderSummary TTY with removals contains red ANSI code")
    func test_renderSummary_ttyWithRemovals() {
        var tracker = TurnFileChangeTracker()
        tracker.recordToolUse(
            toolName: "Edit",
            input: #"{"file_path":"Sources/Test.swift","old_string":"a\nb\nc","new_string":"x"}"#
        )
        let result = tracker.renderSummary(isTTY: true, profile: .trueColor)
        #expect(result != nil)
        // Should contain red for removals
        #expect(result!.contains("\u{1B}[38;2;244;67;54m"))
    }

    @Test("renderSummary ANSI256 color profile")
    func test_renderSummary_ansi256() {
        var tracker = TurnFileChangeTracker()
        tracker.recordToolUse(
            toolName: "Edit",
            input: #"{"file_path":"Test.swift","old_string":"x","new_string":"x\ny"}"#
        )
        let result = tracker.renderSummary(isTTY: true, profile: .ansi256)
        #expect(result != nil)
        #expect(result!.contains("\u{1B}[38;5;244m"))  // dim
        #expect(result!.contains("\u{1B}[38;5;71m"))   // green
    }

    @Test("renderSummary ANSI16 color profile")
    func test_renderSummary_ansi16() {
        var tracker = TurnFileChangeTracker()
        tracker.recordToolUse(
            toolName: "Edit",
            input: #"{"file_path":"Test.swift","old_string":"x","new_string":"x\ny"}"#
        )
        let result = tracker.renderSummary(isTTY: true, profile: .ansi16)
        #expect(result != nil)
        #expect(result!.contains("\u{1B}[2m"))    // dim
        #expect(result!.contains("\u{1B}[32m"))   // green
    }

    @Test("renderSummary deduplicates same file across multiple edits")
    func test_renderSummary_deduplicates() {
        var tracker = TurnFileChangeTracker()
        // Two edits to same file
        tracker.recordToolUse(
            toolName: "Edit",
            input: #"{"file_path":"BigFile.swift","old_string":"a","new_string":"a\nb"}"#
        )
        tracker.recordToolUse(
            toolName: "Edit",
            input: #"{"file_path":"BigFile.swift","old_string":"c","new_string":"c\nd\ne"}"#
        )
        let result = tracker.renderSummary(isTTY: false, profile: .unknown)
        #expect(result != nil)
        #expect(result!.contains("1 file changed"))
        // Gross: edit1 (+2, -1), edit2 (+3, -1) → merged (+5, -2)
        #expect(result!.contains("+5 -2"))
        // Should only have one [change: line
        let changeOccurrences = result!.components(separatedBy: "[change:").count - 1
        #expect(changeOccurrences == 1)
    }

    @Test("renderSummary header shows singular 'file' for one change")
    func test_renderSummary_singularFile() {
        var tracker = TurnFileChangeTracker()
        tracker.recordToolUse(
            toolName: "Write",
            input: #"{"file_path":"New.swift","content":"hello"}"#
        )
        let result = tracker.renderSummary(isTTY: false, profile: .unknown)
        #expect(result!.contains("1 file changed"))
        #expect(!result!.contains("1 files changed"))
    }

    @Test("renderSummary header shows plural 'files' for multiple changes")
    func test_renderSummary_pluralFiles() {
        var tracker = TurnFileChangeTracker()
        tracker.recordToolUse(
            toolName: "Write",
            input: #"{"file_path":"A.swift","content":"a"}"#
        )
        tracker.recordToolUse(
            toolName: "Write",
            input: #"{"file_path":"B.swift","content":"b"}"#
        )
        let result = tracker.renderSummary(isTTY: false, profile: .unknown)
        #expect(result!.contains("2 files changed"))
    }

    @Test("renderSummary truncates long file paths")
    func test_renderSummary_truncatesLongPaths() {
        var tracker = TurnFileChangeTracker()
        let longPath = "Sources/SomeVeryLongDirectoryName/AnotherLongName/AndAnother/Deeply/Nested/File.swift"
        tracker.recordToolUse(
            toolName: "Edit",
            input: #"{"file_path":"\#(longPath)","old_string":"x","new_string":"y"}"#
        )
        let result = tracker.renderSummary(maxWidth: 60, isTTY: false, profile: .unknown)
        #expect(result != nil)
        // Path should be truncated via center truncation
        #expect(result!.contains("…"))
    }
}
