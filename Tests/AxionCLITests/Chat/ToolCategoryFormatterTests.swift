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
