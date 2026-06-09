import Testing
import Foundation
import OpenAgentSDK

@testable import AxionCLI

// MARK: - FileChangeTracker Tests

@Suite("FileChangeTracker")
struct FileChangeTrackerTests {

    // MARK: - Basic Recording

    @Test("recordWrite adds created entry")
    func test_recordWrite_addsCreatedEntry() {
        var tracker = FileChangeTracker()
        tracker.recordWrite(filePath: "src/Foo.swift", contentLineCount: 42)

        #expect(tracker.hasChanges)
        #expect(tracker.writeCount == 1)
        #expect(tracker.editCount == 0)
        #expect(tracker.readCount == 0)
        #expect(tracker.totalLinesAdded == 42)
        #expect(tracker.totalLinesRemoved == 0)

        let change = tracker.changes["src/Foo.swift"]
        #expect(change != nil)
        #expect(change?.kind == .created)
        #expect(change?.linesAdded == 42)
        #expect(change?.linesRemoved == 0)
    }

    @Test("recordEdit adds edited entry")
    func test_recordEdit_addsEditedEntry() {
        var tracker = FileChangeTracker()
        tracker.recordEdit(filePath: "src/Bar.swift", linesAdded: 5, linesRemoved: 3)

        #expect(tracker.hasChanges)
        #expect(tracker.writeCount == 0)
        #expect(tracker.editCount == 1)
        #expect(tracker.totalLinesAdded == 5)
        #expect(tracker.totalLinesRemoved == 3)
    }

    @Test("recordRead adds read entry")
    func test_recordRead_addsReadEntry() {
        var tracker = FileChangeTracker()
        tracker.recordRead(filePath: "README.md")

        #expect(tracker.hasChanges)
        #expect(tracker.readCount == 1)
        #expect(tracker.writeCount == 0)
        #expect(tracker.editCount == 0)
    }

    // MARK: - Deduplication / Upgrade

    @Test("read then write upgrades to created")
    func test_readThenWrite_upgradesToCreated() {
        var tracker = FileChangeTracker()
        tracker.recordRead(filePath: "src/main.swift")
        tracker.recordWrite(filePath: "src/main.swift", contentLineCount: 100)

        #expect(tracker.writeCount == 1)
        #expect(tracker.readCount == 0)
        #expect(tracker.changes["src/main.swift"]?.kind == .created)
        #expect(tracker.changes["src/main.swift"]?.linesAdded == 100)
    }

    @Test("read then edit upgrades to edited")
    func test_readThenEdit_upgradesToEdited() {
        var tracker = FileChangeTracker()
        tracker.recordRead(filePath: "config.json")
        tracker.recordEdit(filePath: "config.json", linesAdded: 2, linesRemoved: 1)

        #expect(tracker.editCount == 1)
        #expect(tracker.readCount == 0)
        #expect(tracker.changes["config.json"]?.linesAdded == 2)
        #expect(tracker.changes["config.json"]?.linesRemoved == 1)
    }

    @Test("multiple edits accumulate line counts")
    func test_multipleEdits_accumulateLineCounts() {
        var tracker = FileChangeTracker()
        tracker.recordEdit(filePath: "app.swift", linesAdded: 3, linesRemoved: 1)
        tracker.recordEdit(filePath: "app.swift", linesAdded: 5, linesRemoved: 2)

        #expect(tracker.editCount == 1)
        #expect(tracker.totalLinesAdded == 8)
        #expect(tracker.totalLinesRemoved == 3)
    }

    @Test("path normalization strips leading dot slash")
    func test_pathNormalization_stripsDotSlash() {
        var tracker = FileChangeTracker()
        tracker.recordWrite(filePath: "./src/Foo.swift", contentLineCount: 10)

        #expect(tracker.changes["src/Foo.swift"] != nil)
        #expect(tracker.changes["./src/Foo.swift"] == nil)
    }

    @Test("read does not override existing edit")
    func test_readDoesNotOverrideExistingEdit() {
        var tracker = FileChangeTracker()
        tracker.recordEdit(filePath: "file.swift", linesAdded: 5, linesRemoved: 2)
        tracker.recordRead(filePath: "file.swift")

        #expect(tracker.editCount == 1)
        #expect(tracker.readCount == 0)
        #expect(tracker.changes["file.swift"]?.linesAdded == 5)
    }

    // MARK: - Reset

    @Test("reset clears all tracked changes")
    func test_reset_clearsAllChanges() {
        var tracker = FileChangeTracker()
        tracker.recordWrite(filePath: "a.swift", contentLineCount: 10)
        tracker.recordEdit(filePath: "b.swift", linesAdded: 3, linesRemoved: 1)
        tracker.recordRead(filePath: "c.swift")

        #expect(tracker.hasChanges)
        tracker.reset()
        #expect(!tracker.hasChanges)
        #expect(tracker.changes.isEmpty)
        #expect(tracker.writeCount == 0)
        #expect(tracker.editCount == 0)
        #expect(tracker.readCount == 0)
    }

    // MARK: - extractFileInfo

    @Test("extractFileInfo detects Write tool")
    func test_extractFileInfo_detectsWrite() {
        let input = """
        {"file_path": "src/NewFile.swift", "content": "line1\\nline2\\nline3"}
        """
        let info = FileChangeTracker.extractFileInfo(toolName: "write", input: input)

        #expect(info != nil)
        #expect(info?.filePath == "src/NewFile.swift")
        #expect(info?.kind == .created)
        #expect(info?.linesAdded == 3)
        #expect(info?.linesRemoved == 0)
    }

    @Test("extractFileInfo detects Edit tool")
    func test_extractFileInfo_detectsEdit() {
        let input = """
        {"file_path": "src/App.swift", "old_string": "foo\\nbar", "new_string": "baz\\nqux\\nquux"}
        """
        let info = FileChangeTracker.extractFileInfo(toolName: "edit", input: input)

        #expect(info != nil)
        #expect(info?.filePath == "src/App.swift")
        #expect(info?.kind == .edited)
        #expect(info?.linesAdded == 3)
        #expect(info?.linesRemoved == 2)
    }

    @Test("extractFileInfo detects Read tool with file_path")
    func test_extractFileInfo_detectsReadFilePath() {
        let input = """
        {"file_path": "README.md"}
        """
        let info = FileChangeTracker.extractFileInfo(toolName: "read", input: input)

        #expect(info != nil)
        #expect(info?.filePath == "README.md")
        #expect(info?.kind == .read)
        #expect(info?.linesAdded == 0)
        #expect(info?.linesRemoved == 0)
    }

    @Test("extractFileInfo detects Read tool with path")
    func test_extractFileInfo_detectsReadPath() {
        let input = """
        {"path": "config.yaml"}
        """
        let info = FileChangeTracker.extractFileInfo(toolName: "read", input: input)

        #expect(info != nil)
        #expect(info?.filePath == "config.yaml")
        #expect(info?.kind == .read)
    }

    @Test("extractFileInfo returns nil for non-file tools")
    func test_extractFileInfo_returnsNilForNonFileTools() {
        let input = """
        {"command": "ls -la"}
        """
        let info = FileChangeTracker.extractFileInfo(toolName: "bash", input: input)
        #expect(info == nil)
    }

    @Test("extractFileInfo returns nil for invalid JSON")
    func test_extractFileInfo_returnsNilForInvalidJSON() {
        let info = FileChangeTracker.extractFileInfo(toolName: "write", input: "not json")
        #expect(info == nil)
    }

    // MARK: - TTY Rendering

    @Test("TTY render: single edited file shows inline path")
    func test_ttyRender_singleEditedFile_showsInlinePath() {
        var tracker = FileChangeTracker()
        tracker.recordEdit(filePath: "src/App.swift", linesAdded: 10, linesRemoved: 3)

        let output = tracker.renderSummary(isTTY: true, profile: .trueColor)

        #expect(output.contains("Edited"))
        #expect(output.contains("src/App.swift"))
        #expect(output.contains("+10"))
        #expect(output.contains("-3"))
        // Single file — no tree characters
        #expect(!output.contains("├──"))
        #expect(!output.contains("└──"))
    }

    @Test("TTY render: single created file shows inline path")
    func test_ttyRender_singleCreatedFile_showsInlinePath() {
        var tracker = FileChangeTracker()
        tracker.recordWrite(filePath: "src/New.swift", contentLineCount: 50)

        let output = tracker.renderSummary(isTTY: true, profile: .trueColor)

        #expect(output.contains("Created"))
        #expect(output.contains("src/New.swift"))
        #expect(output.contains("+50"))
    }

    @Test("TTY render: multiple files shows tree structure")
    func test_ttyRender_multipleFiles_showsTreeStructure() {
        var tracker = FileChangeTracker()
        tracker.recordWrite(filePath: "src/New.swift", contentLineCount: 20)
        tracker.recordEdit(filePath: "src/App.swift", linesAdded: 10, linesRemoved: 5)
        tracker.recordEdit(filePath: "tests/AppTests.swift", linesAdded: 8, linesRemoved: 2)

        let output = tracker.renderSummary(isTTY: true, profile: .trueColor)

        #expect(output.contains("Changed"))
        #expect(output.contains("3 files"))
        #expect(output.contains("+38"))
        #expect(output.contains("-7"))
        #expect(output.contains("├──"))
        #expect(output.contains("└──"))
    }

    @Test("TTY render: only reads shows read summary")
    func test_ttyRender_onlyReads_showsReadSummary() {
        var tracker = FileChangeTracker()
        tracker.recordRead(filePath: "README.md")
        tracker.recordRead(filePath: "Package.swift")
        tracker.recordRead(filePath: "Sources/Main.swift")

        let output = tracker.renderSummary(isTTY: true, profile: .trueColor)

        #expect(output.contains("Read"))
        #expect(output.contains("3 files"))
        // Multiple reads — show per-file tree
        #expect(output.contains("└──"))
    }

    @Test("TTY render: mixed writes and edits uses 'Changed' verb")
    func test_ttyRender_mixedWritesAndEdits_usesChangedVerb() {
        var tracker = FileChangeTracker()
        tracker.recordWrite(filePath: "new.swift", contentLineCount: 10)
        tracker.recordEdit(filePath: "old.swift", linesAdded: 5, linesRemoved: 3)

        let output = tracker.renderSummary(isTTY: true, profile: .trueColor)

        #expect(output.contains("Changed"))
        #expect(output.contains("2 files"))
    }

    @Test("TTY render: only writes uses 'Created' verb")
    func test_ttyRender_onlyWrites_usesCreatedVerb() {
        var tracker = FileChangeTracker()
        tracker.recordWrite(filePath: "a.swift", contentLineCount: 10)
        tracker.recordWrite(filePath: "b.swift", contentLineCount: 20)

        let output = tracker.renderSummary(isTTY: true, profile: .trueColor)

        #expect(output.contains("Created"))
        #expect(output.contains("2 files"))
    }

    @Test("TTY render: only edits uses 'Edited' verb")
    func test_ttyRender_onlyEdits_usesEditedVerb() {
        var tracker = FileChangeTracker()
        tracker.recordEdit(filePath: "a.swift", linesAdded: 5, linesRemoved: 2)
        tracker.recordEdit(filePath: "b.swift", linesAdded: 3, linesRemoved: 1)

        let output = tracker.renderSummary(isTTY: true, profile: .trueColor)

        #expect(output.contains("Edited"))
        #expect(output.contains("2 files"))
    }

    // MARK: - ANSI Color Profiles

    @Test("ANSI256 profile renders without trueColor codes")
    func test_ansi256Profile_rendersWithoutTrueColorCodes() {
        var tracker = FileChangeTracker()
        tracker.recordEdit(filePath: "app.swift", linesAdded: 5, linesRemoved: 2)

        let output = tracker.renderSummary(isTTY: true, profile: .ansi256)

        #expect(output.contains("Edited"))
        #expect(output.contains("app.swift"))
        #expect(output.contains("\u{1B}[38;5;"))  // ANSI256 codes
        #expect(!output.contains("\u{1B}[38;2;"))  // No trueColor codes
    }

    @Test("ANSI16 profile uses basic color codes")
    func test_ansi16Profile_usesBasicColorCodes() {
        var tracker = FileChangeTracker()
        tracker.recordEdit(filePath: "app.swift", linesAdded: 5, linesRemoved: 2)

        let output = tracker.renderSummary(isTTY: true, profile: .ansi16)

        #expect(output.contains("Edited"))
        #expect(output.contains("\u{1B}[32m"))  // ANSI16 green
        #expect(output.contains("\u{1B}[31m"))  // ANSI16 red
    }

    @Test("unknown profile renders without color-specific codes")
    func test_unknownProfile_rendersWithoutColorSpecificCodes() {
        var tracker = FileChangeTracker()
        tracker.recordEdit(filePath: "app.swift", linesAdded: 5, linesRemoved: 2)

        let output = tracker.renderSummary(isTTY: true, profile: .unknown)

        #expect(output.contains("Edited"))
        #expect(output.contains("app.swift"))
        // Unknown profile: no 256-color or true-color codes
        #expect(!output.contains("\u{1B}[38;2;"))  // No trueColor
        #expect(!output.contains("\u{1B}[38;5;"))  // No ANSI256
        // Basic ANSI16 codes (bold, dim, reset) may still be present
    }

    // MARK: - Non-TTY Rendering

    @Test("non-TTY renders plain text summary")
    func test_nonTTY_rendersPlainTextSummary() {
        var tracker = FileChangeTracker()
        tracker.recordWrite(filePath: "src/New.swift", contentLineCount: 20)
        tracker.recordEdit(filePath: "src/App.swift", linesAdded: 10, linesRemoved: 5)

        let output = tracker.renderSummary(isTTY: false, profile: .trueColor)

        #expect(output.hasPrefix("["))
        #expect(output.contains("2 files changed"))
        #expect(output.contains("+30"))
        #expect(output.contains("-5"))
        // Multiple files — show per-file entries
        #expect(output.contains("src/New.swift"))
        #expect(output.contains("src/App.swift"))
    }

    @Test("non-TTY single file shows compact header")
    func test_nonTTY_singleFile_showsCompactHeader() {
        var tracker = FileChangeTracker()
        tracker.recordEdit(filePath: "config.json", linesAdded: 2, linesRemoved: 1)

        let output = tracker.renderSummary(isTTY: false, profile: .trueColor)

        #expect(output.contains("1 file changed"))
        #expect(output.contains("+2"))
        #expect(output.contains("-1"))
    }

    @Test("non-TTY reads only shows read count")
    func test_nonTTY_readsOnly_showsReadCount() {
        var tracker = FileChangeTracker()
        tracker.recordRead(filePath: "README.md")

        let output = tracker.renderSummary(isTTY: false, profile: .trueColor)

        #expect(output.contains("1 file read"))
    }

    // MARK: - Edge Cases

    @Test("empty tracker returns empty string")
    func test_emptyTracker_returnsEmptyString() {
        let tracker = FileChangeTracker()
        let output = tracker.renderSummary(isTTY: true, profile: .trueColor)
        #expect(output.isEmpty)
    }

    @Test("zero line counts are handled correctly")
    func test_zeroLineCounts_handledCorrectly() {
        var tracker = FileChangeTracker()
        tracker.recordEdit(filePath: "file.swift", linesAdded: 0, linesRemoved: 0)

        let output = tracker.renderSummary(isTTY: true, profile: .trueColor)

        #expect(output.contains("Edited"))
        // No +/- numbers when both are 0
        let stripped = stripANSI(output)
        #expect(!stripped.contains("+0"))
        #expect(!stripped.contains("-0"))
    }

    @Test("only added lines shows +N only")
    func test_onlyAddedLines_showsPlusOnly() {
        var tracker = FileChangeTracker()
        tracker.recordWrite(filePath: "new.swift", contentLineCount: 100)

        let output = tracker.renderSummary(isTTY: true, profile: .trueColor)

        #expect(output.contains("+100"))
        let stripped = stripANSI(output)
        #expect(!stripped.contains("-0"))
    }

    @Test("only removed lines shows -N only")
    func test_onlyRemovedLines_showsMinusOnly() {
        var tracker = FileChangeTracker()
        tracker.recordEdit(filePath: "trim.swift", linesAdded: 0, linesRemoved: 15)

        let output = tracker.renderSummary(isTTY: true, profile: .trueColor)

        #expect(output.contains("-15"))
        let stripped = stripANSI(output)
        #expect(!stripped.contains("+0"))
    }

    @Test("sorting: writes before edits in tree output")
    func test_sorting_writesBeforeEdits() {
        var tracker = FileChangeTracker()
        tracker.recordEdit(filePath: "z_edit.swift", linesAdded: 1, linesRemoved: 1)
        tracker.recordWrite(filePath: "m_new.swift", contentLineCount: 5)

        let output = tracker.renderSummary(isTTY: true, profile: .trueColor)

        // Writes come first, then edits (per-file tree only shows changed files)
        let writePos = output.range(of: "m_new.swift")!.lowerBound
        let editPos = output.range(of: "z_edit.swift")!.lowerBound

        #expect(writePos < editPos)
    }

    @Test("sorting: reads are ordered alphabetically")
    func test_sorting_readsAlphabetically() {
        var tracker = FileChangeTracker()
        tracker.recordRead(filePath: "z_file.swift")
        tracker.recordRead(filePath: "a_file.swift")

        let output = tracker.renderSummary(isTTY: true, profile: .trueColor)

        // Alphabetically sorted reads
        let aPos = output.range(of: "a_file.swift")!.lowerBound
        let zPos = output.range(of: "z_file.swift")!.lowerBound
        #expect(aPos < zPos)
    }

    @Test("single read does not show tree structure")
    func test_singleRead_doesNotShowTree() {
        var tracker = FileChangeTracker()
        tracker.recordRead(filePath: "README.md")

        let output = tracker.renderSummary(isTTY: true, profile: .trueColor)

        #expect(output.contains("Read"))
        #expect(output.contains("1 file"))
        // Single file — no tree
        #expect(!output.contains("├──"))
    }

    // MARK: - Integration with ChatOutputFormatter

    @Test("ChatOutputFormatter integrates FileChangeTracker and outputs summary on result")
    func test_chatOutputFormatter_outputsFileChangeSummary() {
        var outputLog: [String] = []
        let formatter = ChatOutputFormatter(
            writeStdout: { outputLog.append($0) },
            writeStderr: { _ in },
            spinner: SpinnerRenderer(),
            theme: nil
        )

        // Simulate a turn: write file → result
        let writeInput = """
        {"file_path": "src/hello.swift", "content": "print(\\"hi\\")"}
        """
        formatter.handle(.toolUse(.init(toolName: "write", toolUseId: "t1", input: writeInput)))
        formatter.handle(.toolResult(.init(toolUseId: "t1", content: "ok", isError: false)))

        // Result triggers summary output
        formatter.handle(.result(.init(subtype: .success, text: "", usage: nil, numTurns: 1, durationMs: 100)))

        let combined = outputLog.joined()
        #expect(combined.contains("hello.swift"))
    }

    @Test("ChatOutputFormatter resets tracker after result")
    func test_chatOutputFormatter_resetsTrackerAfterResult() {
        var outputLog: [String] = []
        let formatter = ChatOutputFormatter(
            writeStdout: { outputLog.append($0) },
            writeStderr: { _ in },
            spinner: SpinnerRenderer(),
            theme: nil
        )

        // First turn with a file change
        formatter.handle(.toolUse(.init(toolName: "write", toolUseId: "t1", input: """
        {"file_path": "a.swift", "content": "hello"}
        """)))
        formatter.handle(.toolResult(.init(toolUseId: "t1", content: "ok", isError: false)))
        formatter.handle(.result(.init(subtype: .success, text: "", usage: nil, numTurns: 1, durationMs: 100)))

        // Second turn with no file changes
        outputLog.removeAll()
        formatter.handle(.result(.init(subtype: .success, text: "", usage: nil, numTurns: 2, durationMs: 50)))

        let secondTurnOutput = outputLog.joined()
        #expect(!secondTurnOutput.contains("a.swift"))
    }

    @Test("ChatOutputFormatter does not output summary when no file changes")
    func test_chatOutputFormatter_noSummaryWhenNoFileChanges() {
        var outputLog: [String] = []
        let formatter = ChatOutputFormatter(
            writeStdout: { outputLog.append($0) },
            writeStderr: { _ in },
            spinner: SpinnerRenderer(),
            theme: nil
        )

        // Shell command (no file changes)
        formatter.handle(.toolUse(.init(toolName: "bash", toolUseId: "t1", input: """
        {"command": "ls -la"}
        """)))
        formatter.handle(.toolResult(.init(toolUseId: "t1", content: "file1\nfile2", isError: false)))
        formatter.handle(.result(.init(subtype: .success, text: "", usage: nil, numTurns: 1, durationMs: 100)))

        let combined = outputLog.joined()
        #expect(!combined.contains("files changed"))
        #expect(!combined.contains("file read"))
    }

    @Test("ChatOutputFormatter tracks multiple file operations in one turn")
    func test_chatOutputFormatter_tracksMultipleFileOpsInOneTurn() {
        var outputLog: [String] = []
        let formatter = ChatOutputFormatter(
            writeStdout: { outputLog.append($0) },
            writeStderr: { _ in },
            spinner: SpinnerRenderer(),
            theme: nil
        )

        // Write new file
        formatter.handle(.toolUse(.init(toolName: "write", toolUseId: "t1", input: """
        {"file_path": "src/new.swift", "content": "line1\\nline2\\nline3"}
        """)))
        formatter.handle(.toolResult(.init(toolUseId: "t1", content: "ok", isError: false)))

        // Edit existing file
        formatter.handle(.toolUse(.init(toolName: "edit", toolUseId: "t2", input: """
        {"file_path": "src/app.swift", "old_string": "old", "new_string": "new1\\nnew2"}
        """)))
        formatter.handle(.toolResult(.init(toolUseId: "t2", content: "ok", isError: false)))

        // Read file
        formatter.handle(.toolUse(.init(toolName: "read", toolUseId: "t3", input: """
        {"file_path": "README.md"}
        """)))
        formatter.handle(.toolResult(.init(toolUseId: "t3", content: "# README", isError: false)))

        formatter.handle(.result(.init(subtype: .success, text: "", usage: nil, numTurns: 1, durationMs: 200)))

        let combined = outputLog.joined()
        #expect(combined.contains("new.swift"))
        #expect(combined.contains("app.swift"))
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
