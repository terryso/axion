import Testing
import Foundation

@testable import AxionCLI

@Suite("ToolCategoryFormatter")
struct ToolCategoryFormatterTests {

    // MARK: - Categorize

    @Test("Shell tools are categorized correctly")
    func test_categorize_shell() {
        #expect(ToolCategoryFormatter.categorize(toolName: "bash") == .shell)
        #expect(ToolCategoryFormatter.categorize(toolName: "Bash") == .shell)
        #expect(ToolCategoryFormatter.categorize(toolName: "BASH") == .shell)
        #expect(ToolCategoryFormatter.categorize(toolName: "shell") == .shell)
        #expect(ToolCategoryFormatter.categorize(toolName: "command") == .shell)
    }

    @Test("Edit tools are categorized correctly")
    func test_categorize_edit() {
        #expect(ToolCategoryFormatter.categorize(toolName: "edit") == .edit)
        #expect(ToolCategoryFormatter.categorize(toolName: "Edit") == .edit)
        #expect(ToolCategoryFormatter.categorize(toolName: "replace") == .edit)
        #expect(ToolCategoryFormatter.categorize(toolName: "apply_patch") == .edit)
    }

    @Test("File write tools are categorized correctly")
    func test_categorize_fileWrite() {
        #expect(ToolCategoryFormatter.categorize(toolName: "write") == .fileWrite)
        #expect(ToolCategoryFormatter.categorize(toolName: "Write") == .fileWrite)
        #expect(ToolCategoryFormatter.categorize(toolName: "create_file") == .fileWrite)
    }

    @Test("File read tools are categorized correctly")
    func test_categorize_fileRead() {
        #expect(ToolCategoryFormatter.categorize(toolName: "read") == .fileRead)
        #expect(ToolCategoryFormatter.categorize(toolName: "Read") == .fileRead)
        #expect(ToolCategoryFormatter.categorize(toolName: "cat") == .fileRead)
        #expect(ToolCategoryFormatter.categorize(toolName: "head") == .fileRead)
        #expect(ToolCategoryFormatter.categorize(toolName: "list_files") == .fileRead)
    }

    @Test("Search tools are categorized correctly")
    func test_categorize_search() {
        #expect(ToolCategoryFormatter.categorize(toolName: "grep") == .search)
        #expect(ToolCategoryFormatter.categorize(toolName: "Grep") == .search)
        #expect(ToolCategoryFormatter.categorize(toolName: "glob") == .search)
        #expect(ToolCategoryFormatter.categorize(toolName: "search") == .search)
        #expect(ToolCategoryFormatter.categorize(toolName: "find") == .search)
    }

    @Test("Memory tools are categorized correctly")
    func test_categorize_memory() {
        #expect(ToolCategoryFormatter.categorize(toolName: "memory") == .memory)
        #expect(ToolCategoryFormatter.categorize(toolName: "skill") == .memory)
        #expect(ToolCategoryFormatter.categorize(toolName: "memory_add") == .memory)
        #expect(ToolCategoryFormatter.categorize(toolName: "skill_run") == .memory)
    }

    @Test("Desktop automation tools are categorized correctly")
    func test_categorize_desktop() {
        #expect(ToolCategoryFormatter.categorize(toolName: "click") == .shell)
        #expect(ToolCategoryFormatter.categorize(toolName: "type_text") == .shell)
        #expect(ToolCategoryFormatter.categorize(toolName: "launch_app") == .shell)
        #expect(ToolCategoryFormatter.categorize(toolName: "screenshot") == .fileRead)
        #expect(ToolCategoryFormatter.categorize(toolName: "get_window_state") == .fileRead)
        #expect(ToolCategoryFormatter.categorize(toolName: "list_windows") == .fileRead)
    }

    @Test("Unknown tools default to .default")
    func test_categorize_default() {
        #expect(ToolCategoryFormatter.categorize(toolName: "unknown_tool") == .default)
        #expect(ToolCategoryFormatter.categorize(toolName: "custom") == .default)
        #expect(ToolCategoryFormatter.categorize(toolName: "xyz") == .default)
    }

    // MARK: - formatStarted

    @Test("formatStarted shell shows exec label with command and cwd")
    func test_formatStarted_shell() {
        let input = """
        {"command": "ls -la", "cwd": "/Users/test/project"}
        """
        let result = ToolCategoryFormatter.formatStarted(
            toolName: "bash",
            input: input,
            isTTY: false
        )
        #expect(result.contains("exec"))
        #expect(result.contains("ls -la"))
        #expect(result.contains("in"))
        #expect(result.hasSuffix("\n"))
    }

    @Test("formatStarted shell shows command without cwd")
    func test_formatStarted_shell_noCwd() {
        let input = """
        {"command": "git status"}
        """
        let result = ToolCategoryFormatter.formatStarted(
            toolName: "bash",
            input: input,
            isTTY: false
        )
        #expect(result.contains("exec"))
        #expect(result.contains("git status"))
        #expect(!result.contains("in"))
    }

    @Test("formatStarted edit shows file path and line counts")
    func test_formatStarted_edit() {
        let input = """
        {"file_path": "/Users/test/main.swift", "old_string": "hello\\nworld", "new_string": "hello\\nswift"}
        """
        let result = ToolCategoryFormatter.formatStarted(
            toolName: "edit",
            input: input,
            isTTY: false
        )
        #expect(result.contains("edit"))
        #expect(result.contains("main.swift"))
        #expect(result.contains("+"))
        #expect(result.contains("-"))
    }

    @Test("formatStarted read shows file path")
    func test_formatStarted_read() {
        let input = """
        {"file_path": "/Users/test/config.json"}
        """
        let result = ToolCategoryFormatter.formatStarted(
            toolName: "read",
            input: input,
            isTTY: false
        )
        #expect(result.contains("read"))
        #expect(result.contains("config.json"))
    }

    @Test("formatStarted search shows query pattern")
    func test_formatStarted_search() {
        let input = """
        {"pattern": "TODO", "path": "/Users/test/src"}
        """
        let result = ToolCategoryFormatter.formatStarted(
            toolName: "grep",
            input: input,
            isTTY: false
        )
        #expect(result.contains("search"))
        #expect(result.contains("TODO"))
    }

    @Test("formatStarted write shows file and line count")
    func test_formatStarted_write() {
        let input = """
        {"file_path": "/Users/test/new.swift", "content": "line1\\nline2\\nline3"}
        """
        let result = ToolCategoryFormatter.formatStarted(
            toolName: "write",
            input: input,
            isTTY: false
        )
        #expect(result.contains("write"))
        #expect(result.contains("new.swift"))
        #expect(result.contains("lines"))
    }

    @Test("formatStarted with TTY includes ANSI color codes")
    func test_formatStarted_tty() {
        let input = """
        {"command": "ls"}
        """
        let result = ToolCategoryFormatter.formatStarted(
            toolName: "bash",
            input: input,
            isTTY: true,
            colorProfile: .trueColor
        )
        #expect(result.contains("\u{1B}[38;2;"))  // Has TrueColor ANSI
        #expect(result.contains("\u{1B}[0m"))      // Has reset
    }

    @Test("formatStarted non-TTY has no ANSI codes")
    func test_formatStarted_noAnsi() {
        let input = """
        {"command": "ls"}
        """
        let result = ToolCategoryFormatter.formatStarted(
            toolName: "bash",
            input: input,
            isTTY: false
        )
        #expect(!result.contains("\u{1B}["))
    }

    // MARK: - formatCompleted

    @Test("formatCompleted success shows checkmark")
    func test_formatCompleted_success() {
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: "",
            isError: false,
            durationMs: 350,
            isTTY: false
        )
        #expect(result.contains("✓"))
        #expect(result.contains("[350ms]"))
        #expect(result.hasSuffix("\n"))
    }

    @Test("formatCompleted error shows cross mark")
    func test_formatCompleted_error() {
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: "command not found",
            isError: true,
            durationMs: 120,
            isTTY: false
        )
        #expect(result.contains("✗"))
        #expect(result.contains("[120ms]"))
        #expect(result.contains("command not found"))
    }

    @Test("formatCompleted shell shows exit code from JSON")
    func test_formatCompleted_shellExitCode() {
        let content = """
        {"exitCode": 0, "stdout": "file1.txt\\nfile2.txt"}
        """
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: content,
            isError: false,
            durationMs: nil,
            isTTY: false
        )
        #expect(result.contains("completed"))
    }

    @Test("formatCompleted shell shows exit code on error")
    func test_formatCompleted_shellExitError() {
        let content = """
        {"exitCode": 1, "stderr": "permission denied"}
        """
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: content,
            isError: true,
            durationMs: nil,
            isTTY: false
        )
        #expect(result.contains("exited 1"))
    }

    @Test("formatCompleted edit shows edited label")
    func test_formatCompleted_edit() {
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "edit",
            content: "",
            isError: false,
            durationMs: 80,
            isTTY: false
        )
        #expect(result.contains("edited"))
    }

    @Test("formatCompleted write shows written label")
    func test_formatCompleted_write() {
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "write",
            content: "",
            isError: false,
            durationMs: 50,
            isTTY: false
        )
        #expect(result.contains("written"))
    }

    @Test("formatCompleted read shows line count")
    func test_formatCompleted_read() {
        let content = "line 1\nline 2\nline 3"
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "read",
            content: content,
            isError: false,
            durationMs: 10,
            isTTY: false
        )
        #expect(result.contains("read"))
        #expect(result.contains("lines"))
    }

    @Test("formatCompleted search shows match count from JSON")
    func test_formatCompleted_searchMatchCount() {
        let content = """
        {"count": 5, "results": ["a", "b", "c", "d", "e"]}
        """
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "grep",
            content: content,
            isError: false,
            durationMs: 200,
            isTTY: false
        )
        #expect(result.contains("5 results"))
    }

    @Test("formatCompleted with nil duration omits brackets")
    func test_formatCompleted_nilDuration() {
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: "",
            isError: false,
            durationMs: nil,
            isTTY: false
        )
        #expect(!result.contains("["))
        #expect(!result.contains("ms"))
    }

    @Test("formatCompleted formats second durations")
    func test_formatCompleted_secondDuration() {
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: "",
            isError: false,
            durationMs: 1250,
            isTTY: false
        )
        #expect(result.contains("[1.2s]"))
    }

    @Test("formatCompleted with TTY includes color codes")
    func test_formatCompleted_tty() {
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: "",
            isError: false,
            durationMs: 100,
            isTTY: true,
            colorProfile: .trueColor
        )
        #expect(result.contains("\u{1B}[38;2;76;175;80m"))  // green for success
        #expect(result.contains("\u{1B}[0m"))
    }

    @Test("formatCompleted error with TTY uses red color")
    func test_formatCompleted_errorTty() {
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: "error",
            isError: true,
            durationMs: 100,
            isTTY: true,
            colorProfile: .trueColor
        )
        #expect(result.contains("\u{1B}[38;2;244;67;54m"))  // red for error
    }

    @Test("formatStarted TTY supports ANSI256 and ANSI16 category colors")
    func test_formatStarted_ttyColorProfiles() {
        let input = """
        {"command": "ls"}
        """
        let ansi256 = ToolCategoryFormatter.formatStarted(
            toolName: "bash",
            input: input,
            isTTY: true,
            colorProfile: .ansi256
        )
        let ansi16 = ToolCategoryFormatter.formatStarted(
            toolName: "bash",
            input: input,
            isTTY: true,
            colorProfile: .ansi16
        )
        let unknown = ToolCategoryFormatter.formatStarted(
            toolName: "bash",
            input: input,
            isTTY: true,
            colorProfile: .unknown
        )

        #expect(ansi256.contains("\u{1B}[38;5;176m"))
        #expect(ansi16.contains("\u{1B}[35m"))
        #expect(!unknown.contains("\u{1B}[38;"))
    }

    @Test("formatCompleted TTY supports ANSI256, ANSI16, and unknown status colors")
    func test_formatCompleted_ttyStatusColorProfiles() {
        let ansi256 = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: "",
            isError: false,
            durationMs: nil,
            isTTY: true,
            colorProfile: .ansi256
        )
        let ansi16Error = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: "error",
            isError: true,
            durationMs: nil,
            isTTY: true,
            colorProfile: .ansi16
        )
        let unknown = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: "",
            isError: false,
            durationMs: nil,
            isTTY: true,
            colorProfile: .unknown
        )

        #expect(ansi256.contains("\u{1B}[38;5;71m"))
        #expect(ansi16Error.contains("\u{1B}[31m"))
        #expect(!unknown.contains("\u{1B}[38;"))
    }

    @Test("formatCompleted shell TTY renders inline output and truncation")
    func test_formatCompleted_shellTTYRendersOutputBlock() {
        let content = """
        alpha
        beta
        gamma
        delta
        epsilon
        """
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: content,
            isError: false,
            durationMs: 1250,
            isTTY: true,
            colorProfile: .ansi16
        )

        #expect(result.contains("completed [1.2s]\n"))
        #expect(result.contains("alpha"))
        #expect(result.contains("delta"))
        #expect(result.contains("1 more lines"))
    }

    @Test("formatCompleted shell TTY extracts stdout from JSON wrapper")
    func test_formatCompleted_shellTTYExtractsJSONStdout() {
        let content = """
        {"exitCode":0,"stdout":"one\\ntwo"}
        """
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: content,
            isError: false,
            durationMs: nil,
            isTTY: true,
            colorProfile: .unknown
        )

        #expect(result.contains("one"))
        #expect(result.contains("two"))
        #expect(!result.contains("stdout"))
    }

    @Test("formatCompleted shell TTY filters ANSI and box drawing output")
    func test_formatCompleted_shellTTYFiltersNoise() {
        let content = "\u{1B}[31mred\u{1B}[0m\n┌────┐\nvalue"
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: content,
            isError: false,
            durationMs: nil,
            isTTY: true,
            colorProfile: .unknown
        )

        #expect(result.contains("red"))
        #expect(result.contains("value"))
        #expect(!result.contains("31mred"))
        #expect(!result.contains("┌────┐"))
    }

    @Test("formatCompleted search counts matches field and grep-like lines")
    func test_formatCompleted_searchMatchCountVariants() {
        let json = ToolCategoryFormatter.formatCompleted(
            toolName: "grep",
            content: #"{"matches":1}"#,
            isError: false,
            durationMs: nil,
            isTTY: false
        )
        let lines = ToolCategoryFormatter.formatCompleted(
            toolName: "grep",
            content: "a.swift:10:TODO\nb.swift:20:FIXME",
            isError: false,
            durationMs: nil,
            isTTY: false
        )
        let noCount = ToolCategoryFormatter.formatCompleted(
            toolName: "grep",
            content: "plain output",
            isError: false,
            durationMs: nil,
            isTTY: false
        )

        #expect(json.contains("1 result"))
        #expect(lines.contains("2 results"))
        #expect(noCount.contains("completed"))
    }

    @Test("formatCompleted category-specific success and error labels")
    func test_formatCompleted_categoryLabels() {
        #expect(ToolCategoryFormatter.formatCompleted(toolName: "read", content: "", isError: true, durationMs: nil, isTTY: false).contains("read failed"))
        #expect(ToolCategoryFormatter.formatCompleted(toolName: "write", content: "", isError: true, durationMs: nil, isTTY: false).contains("write failed"))
        #expect(ToolCategoryFormatter.formatCompleted(toolName: "edit", content: "", isError: true, durationMs: nil, isTTY: false).contains("edit failed"))
        #expect(ToolCategoryFormatter.formatCompleted(toolName: "grep", content: "", isError: true, durationMs: nil, isTTY: false).contains("search failed"))
        #expect(ToolCategoryFormatter.formatCompleted(toolName: "memory_add", content: "saved", isError: false, durationMs: nil, isTTY: false).contains("ok"))
        #expect(ToolCategoryFormatter.formatCompleted(toolName: "memory_add", content: "denied", isError: true, durationMs: nil, isTTY: false).contains("memory error"))
        #expect(ToolCategoryFormatter.formatCompleted(toolName: "custom", content: "done", isError: false, durationMs: nil, isTTY: false).contains("completed"))
        #expect(ToolCategoryFormatter.formatCompleted(toolName: "custom", content: "bad", isError: true, durationMs: nil, isTTY: false).contains("failed"))
    }

    @Test("formatStarted memory and default inputs use category-specific summaries")
    func test_formatStarted_memoryAndDefaultSummaries() {
        let memory = ToolCategoryFormatter.formatStarted(
            toolName: "memory_add",
            input: #"{"action":"add","domain":"global"}"#,
            isTTY: false
        )
        let defaultPath = ToolCategoryFormatter.formatStarted(
            toolName: "custom_tool",
            input: #"{"path":"/Users/test/project/file.swift"}"#,
            isTTY: false
        )
        let firstValue = ToolCategoryFormatter.formatStarted(
            toolName: "custom_tool",
            input: #"{"message":"hello"}"#,
            isTTY: false
        )

        #expect(memory.contains("memory"))
        #expect(memory.contains("add"))
        #expect(defaultPath.contains("file.swift"))
        #expect(firstValue.contains("hello"))
    }

    @Test("formatStarted edit counts empty old/new strings as single-line replacement")
    func test_formatStarted_editEmptyStringsCountAsSingleLine() {
        let input = """
        {"file_path": "/Users/test/main.swift", "old_string": "", "new_string": ""}
        """
        let result = ToolCategoryFormatter.formatStarted(
            toolName: "edit",
            input: input,
            isTTY: false
        )
        #expect(result.contains("+1/-1"))
    }

    @Test("formatStarted covers fallback summaries for edit, write, search, memory, and default")
    func test_formatStarted_fallbackSummaryBranches() {
        let editFallback = ToolCategoryFormatter.formatStarted(
            toolName: "edit",
            input: #"{"replacement":"fallback edit"}"#,
            isTTY: false
        )
        let writePathOnly = ToolCategoryFormatter.formatStarted(
            toolName: "write",
            input: #"{"file_path":"/Users/test/output.txt"}"#,
            isTTY: false
        )
        let writeFallback = ToolCategoryFormatter.formatStarted(
            toolName: "write",
            input: #"{"body":"fallback write"}"#,
            isTTY: false
        )
        let searchFallback = ToolCategoryFormatter.formatStarted(
            toolName: "grep",
            input: #"{"scope":"fallback search"}"#,
            isTTY: false
        )
        let memoryDomain = ToolCategoryFormatter.formatStarted(
            toolName: "memory_add",
            input: #"{"domain":"global"}"#,
            isTTY: false
        )
        let memoryFallback = ToolCategoryFormatter.formatStarted(
            toolName: "memory_add",
            input: #"{"value":"fallback memory"}"#,
            isTTY: false
        )
        let defaultFilePath = ToolCategoryFormatter.formatStarted(
            toolName: "custom_tool",
            input: #"{"file_path":"/Users/test/default.txt"}"#,
            isTTY: false
        )

        #expect(editFallback.contains("fallback edit"))
        #expect(writePathOnly.contains("output.txt"))
        #expect(writeFallback.contains("fallback write"))
        #expect(searchFallback.contains("fallback search"))
        #expect(memoryDomain.contains("global"))
        #expect(memoryFallback.contains("fallback memory"))
        #expect(defaultFilePath.contains("default.txt"))
    }

    @Test("formatCompleted shell TTY handles JSON output and empty output branches")
    func test_formatCompleted_shellTTYOutputBranches() {
        let outputJSON = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: #"{"exitCode":0,"output":"from output field"}"#,
            isError: false,
            durationMs: nil,
            isTTY: true,
            colorProfile: .ansi256
        )
        let exitCodeOnly = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: #"{"exitCode":0}"#,
            isError: false,
            durationMs: nil,
            isTTY: true,
            colorProfile: .ansi16
        )
        let borderOnly = ToolCategoryFormatter.formatCompleted(
            toolName: "bash",
            content: "┌────┐\n└────┘",
            isError: false,
            durationMs: nil,
            isTTY: true,
            colorProfile: .unknown
        )

        #expect(outputJSON.contains("from output field"))
        #expect(outputJSON.contains("\u{1B}[38;5;71m"))
        #expect(exitCodeOnly.contains("completed"))
        #expect(exitCodeOnly.contains(#"{"exitCode":0}"#))
        #expect(borderOnly.contains("completed"))
        #expect(borderOnly.contains("┌────┐"))
    }

    // MARK: - Category Styles

    @Test("All categories have defined styles")
    func test_allCategoriesHaveStyles() {
        let categories: [ToolCategoryFormatter.ToolCategory] = [
            .shell, .edit, .fileWrite, .fileRead, .search, .memory, .default
        ]
        for cat in categories {
            let style = ToolCategoryFormatter.categoryStyles[cat]
            #expect(style != nil, "Missing style for category: \(cat)")
            #expect(!(style?.icon.isEmpty ?? true), "Empty icon for category: \(cat)")
            #expect(!(style?.label.isEmpty ?? true), "Empty label for category: \(cat)")
        }
    }

    @Test("Category icons are distinct")
    func test_categoryIconsAreDistinct() {
        let styles = ToolCategoryFormatter.categoryStyles
        let icons = styles.values.map(\.icon)
        let uniqueIcons = Set(icons)
        #expect(uniqueIcons.count == icons.count, "Category icons should be unique")
    }

    @Test("Category labels are distinct")
    func test_categoryLabelsAreDistinct() {
        let styles = ToolCategoryFormatter.categoryStyles
        let labels = styles.values.map(\.label)
        let uniqueLabels = Set(labels)
        #expect(uniqueLabels.count == labels.count, "Category labels should be unique")
    }

    // MARK: - Edge Cases

    @Test("formatStarted with invalid JSON falls back gracefully")
    func test_formatStarted_invalidJson() {
        let result = ToolCategoryFormatter.formatStarted(
            toolName: "bash",
            input: "not json at all",
            isTTY: false
        )
        #expect(result.contains("exec"))
        #expect(result.hasSuffix("\n"))
    }

    @Test("formatStarted with empty JSON object uses default extraction")
    func test_formatStarted_emptyJson() {
        let result = ToolCategoryFormatter.formatStarted(
            toolName: "bash",
            input: "{}",
            isTTY: false
        )
        #expect(result.contains("exec"))
    }

    @Test("formatCompleted with very long content is truncated")
    func test_formatCompleted_longContent() {
        let longContent = String(repeating: "x", count: 500)
        let result = ToolCategoryFormatter.formatCompleted(
            toolName: "unknown_tool",
            content: longContent,
            isError: true,
            durationMs: 100,
            isTTY: false
        )
        #expect(result.count < 500)  // Should be truncated
    }
}
