import Foundation

/// Codex-inspired tool category visual formatter.
///
/// Maps tool names to semantic categories and provides category-specific
/// formatting for tool "started" and "completed" display, with distinct
/// icons, labels, colors, and result formatting per category.
///
/// Codex's `render_item_started()` / `render_item_completed()` use different
/// visual treatments per tool type:
/// - `exec` → magenta italic label + bold command + cwd
/// - `mcp:` → bold label + cyan tool name + dimmed status
/// - `apply patch` → bold label + dimmed path list
///
/// Axion adapts this for line-based output with category icons, color-coded
/// labels, and smart result summarization.
struct ToolCategoryFormatter {

    /// Semantic tool category — determines visual treatment.
    enum ToolCategory: String, Sendable, Equatable {
        case shell       // bash, shell command execution
        case edit        // file editing (Edit tool)
        case fileWrite   // file creation/overwrite (Write tool)
        case fileRead    // file reading (Read, cat, head, tail)
        case search      // searching (grep, glob, search, find)
        case memory      // memory/skill operations
        case `default`   // uncategorized tools
    }

    /// Category-specific styling configuration.
    struct CategoryStyle: Sendable {
        let icon: String
        let label: String
        let labelColorANSI: (trueColor: String, ansi256: String, ansi16: String)

        /// Returns the ANSI color code for the given profile.
        func colorCode(for profile: TerminalColorProfile) -> String {
            switch profile {
            case .trueColor: return labelColorANSI.trueColor
            case .ansi256: return labelColorANSI.ansi256
            case .ansi16: return labelColorANSI.ansi16
            case .unknown: return ""
            }
        }
    }

    // MARK: - Category Styles

    /// Pre-defined styles per category, inspired by Codex's color scheme.
    static let categoryStyles: [ToolCategory: CategoryStyle] = [
        .shell: CategoryStyle(
            icon: "🔧",
            label: "exec",
            labelColorANSI: (
                trueColor: "\u{1B}[38;2;197;145;205m",  // purple-magenta (Codex's italic magenta)
                ansi256: "\u{1B}[38;5;176m",
                ansi16: "\u{1B}[35m"
            )
        ),
        .edit: CategoryStyle(
            icon: "✏️",
            label: "edit",
            labelColorANSI: (
                trueColor: "\u{1B}[38;2;255;183;77m",   // orange
                ansi256: "\u{1B}[38;5;215m",
                ansi16: "\u{1B}[33m"
            )
        ),
        .fileWrite: CategoryStyle(
            icon: "📝",
            label: "write",
            labelColorANSI: (
                trueColor: "\u{1B}[38;2;255;167;38m",   // deep orange
                ansi256: "\u{1B}[38;5;208m",
                ansi16: "\u{1B}[33m"
            )
        ),
        .fileRead: CategoryStyle(
            icon: "📄",
            label: "read",
            labelColorANSI: (
                trueColor: "\u{1B}[38;2;129;140;248m",  // purple-blue
                ansi256: "\u{1B}[38;5;104m",
                ansi16: "\u{1B}[34m"
            )
        ),
        .search: CategoryStyle(
            icon: "🔍",
            label: "search",
            labelColorANSI: (
                trueColor: "\u{1B}[38;2;52;211;153m",   // teal-green
                ansi256: "\u{1B}[38;5;79m",
                ansi16: "\u{1B}[36m"
            )
        ),
        .memory: CategoryStyle(
            icon: "🧠",
            label: "memory",
            labelColorANSI: (
                trueColor: "\u{1B}[38;2;244;114;182m",  // pink
                ansi256: "\u{1B}[38;5;211m",
                ansi16: "\u{1B}[35m"
            )
        ),
        .default: CategoryStyle(
            icon: "⚡",
            label: "tool",
            labelColorANSI: (
                trueColor: "\u{1B}[38;2;148;163;184m",  // gray-blue
                ansi256: "\u{1B}[38;5;109m",
                ansi16: "\u{1B}[37m"
            )
        ),
    ]

    private static let reset = "\u{1B}[0m"

    // MARK: - Tool Name → Category Mapping

    /// Maps a tool name to its semantic category.
    ///
    /// Coding agent tools:
    /// - `bash` / `shell` → shell
    /// - `edit` → edit
    /// - `write` → fileWrite
    /// - `read` → fileRead
    /// - `grep` / `glob` / `search` / `find` → search
    /// - `memory` → memory
    ///
    /// Desktop automation tools (Axion MCP):
    /// - `click` / `type_text` / `press_key` / `scroll` / `launch_app` → shell
    /// - `screenshot` / `get_window_state` / `list_windows` → fileRead
    static func categorize(toolName: String) -> ToolCategory {
        let name = toolName.lowercased()

        // Shell/execution tools
        if name == "bash" || name == "shell" || name.hasSuffix("_exec") || name == "command" {
            return .shell
        }

        // File editing
        if name == "edit" || name == "replace" || name == "update_file" || name == "apply_patch" {
            return .edit
        }

        // File writing
        if name == "write" || name == "create_file" || name == "save_file" {
            return .fileWrite
        }

        // File reading
        if name == "read" || name == "cat" || name == "head" || name == "tail"
            || name == "view" || name == "get_file" || name == "list_files" {
            return .fileRead
        }

        // Search tools
        if name == "grep" || name == "glob" || name == "search" || name == "find"
            || name == "ripgrep" || name == "list_directory" {
            return .search
        }

        // Memory/skill tools
        if name == "memory" || name == "skill" || name.hasPrefix("memory_") || name.hasPrefix("skill_") {
            return .memory
        }

        // Desktop automation (AX) — treat interaction tools as shell
        if name == "click" || name == "type_text" || name == "press_key"
            || name == "scroll" || name == "launch_app" || name == "drag"
            || name == "hotkey" || name == "open_url" {
            return .shell
        }

        // Desktop observation — treat as read
        if name == "screenshot" || name == "get_window_state" || name == "list_windows"
            || name == "get_ax_tree" || name == "get_element_info" {
            return .fileRead
        }

        return .default
    }

    // MARK: - Started Formatting

    /// Formats the "tool started" display line with category-specific styling.
    ///
    /// Codex-inspired patterns:
    /// - Shell: `🔧 exec: ls -la in /Users/...`
    /// - Edit: `✏️ edit: /path/to/file.swift (+3/-2)`
    /// - Read: `📄 read: /path/to/file.swift`
    /// - Search: `🔍 search: "pattern" in /path`
    /// - Default: `⚡ toolName: input_summary`
    ///
    /// - Parameters:
    ///   - toolName: The tool's name
    ///   - input: Raw JSON input string
    ///   - isTTY: Whether output is to a TTY
    ///   - colorProfile: Terminal color capability
    /// - Returns: Formatted start line (including newline)
    static func formatStarted(
        toolName: String,
        input: String,
        isTTY: Bool = isatty(STDOUT_FILENO) != 0,
        colorProfile: TerminalColorProfile = .detect()
    ) -> String {
        let category = categorize(toolName: toolName)
        let style = categoryStyles[category] ?? categoryStyles[.default]!

        guard isTTY else {
            let summary = extractInputSummary(toolName: toolName, input: input, category: category)
            return "\(style.icon) \(style.label): \(summary)\n"
        }

        let colorCode = style.colorCode(for: colorProfile)
        let summary = extractInputSummary(toolName: toolName, input: input, category: category)

        return "\(style.icon) \(colorCode)\(style.label)\(reset): \(summary)\n"
    }

    /// Formats the "tool completed" display line with category-specific styling.
    ///
    /// Codex-inspired patterns:
    /// - Shell success: `✓ [350ms]` (green)
    /// - Shell failure: `✗ exit 1 [350ms]` (red)
    /// - Edit success: `✓ edited [120ms]`
    /// - Default: `✓ [duration]`
    ///
    /// - Parameters:
    ///   - toolName: The tool's name
    ///   - content: Result content string
    ///   - isError: Whether the tool returned an error
    ///   - durationMs: Tool execution duration in milliseconds (nil if unknown)
    ///   - isTTY: Whether output is to a TTY
    ///   - colorProfile: Terminal color capability
    /// - Returns: Formatted completion line (including newline)
    static func formatCompleted(
        toolName: String,
        content: String,
        isError: Bool,
        durationMs: Int?,
        isTTY: Bool = isatty(STDOUT_FILENO) != 0,
        colorProfile: TerminalColorProfile = .detect()
    ) -> String {
        let category = categorize(toolName: toolName)
        let durationStr = durationMs.map { formatDurationMs($0) } ?? ""
        let durationSuffix = durationStr.isEmpty ? "" : " [\(durationStr)]"

        let statusIcon: String
        let statusLabel: String
        let outputPreview: String

        if isError {
            statusIcon = "✗"
            statusLabel = formatErrorLabel(category: category, content: content)
            outputPreview = extractErrorPreview(content: content, category: category)
        } else {
            statusIcon = "✓"
            statusLabel = formatSuccessLabel(category: category, content: content)
            outputPreview = extractSuccessPreview(content: content, category: category)
        }

        guard isTTY else {
            let parts = [statusIcon, statusLabel, outputPreview].filter { !$0.isEmpty }
            return "\(parts.joined(separator: " "))\(durationSuffix)\n"
        }

        // Color the status icon based on success/error
        let iconColor = isError
            ? statusColorError(profile: colorProfile)
            : statusColorSuccess(profile: colorProfile)
        let dimCode = "\u{1B}[2m"  // dim for output preview

        var result = "\(iconColor)\(statusIcon)\(reset) \(statusLabel)"

        // Codex-inspired: Shell commands show multi-line output inline
        // (like Codex's aggregated_output pattern), all other categories
        // show single-line preview on the same line.
        if category == .shell && !isError && !content.isEmpty {
            let outputLines = renderShellOutput(
                content: content,
                maxLines: 4,
                maxWidth: 100
            )
            if outputLines.numberOfLines > 0 {
                result += "\(durationSuffix)\n"
                result += outputLines.text
                return result
            }
        }

        if !outputPreview.isEmpty {
            result += " \(dimCode)\(outputPreview)\(reset)"
        }
        result += "\(durationSuffix)\n"

        return result
    }

    // MARK: - Input Summary Extraction

    /// Extracts a category-appropriate summary from tool input JSON.
    private static func extractInputSummary(
        toolName: String,
        input: String,
        category: ToolCategory
    ) -> String {
        guard let json = parseJSONDict(from: input) else {
            return ToolOutputFormatter.truncateText(input, maxLength: 80)
        }

        switch category {
        case .shell:
            // "command" parameter → show command + cwd
            if let command = json["command"] as? String {
                let cmd = ToolOutputFormatter.truncateText(command, maxLength: 60)
                if let cwd = json["cwd"] as? String {
                    let displayCwd = ToolOutputFormatter.truncatePathCenter(cwd, maxWidth: 30)
                    return "\(cmd) in \(displayCwd)"
                }
                return cmd
            }
            return extractFirstValue(json: json)

        case .edit:
            // "file_path" + "old_string"/"new_string" → show file + line count
            if let filePath = json["file_path"] as? String {
                let display = ToolOutputFormatter.truncatePathCenter(filePath, maxWidth: 50)
                let linker = TerminalHyperlinkFormatter()
                let linked = linker.formatFilePath(filePath, visibleText: display)
                var summary = linked

                if let old = json["old_string"] as? String,
                   let newStr = json["new_string"] as? String {
                    let removed = old.components(separatedBy: "\n").count
                    let added = newStr.components(separatedBy: "\n").count
                    summary += " (\(formatLineChange(added: added, removed: removed)))"
                }
                return summary
            }
            return extractFirstValue(json: json)

        case .fileWrite:
            // "file_path" → show path + content size
            if let filePath = json["file_path"] as? String {
                let display = ToolOutputFormatter.truncatePathCenter(filePath, maxWidth: 60)
                let linker = TerminalHyperlinkFormatter()
                let linked = linker.formatFilePath(filePath, visibleText: display)
                if let content = json["content"] as? String {
                    let lines = content.components(separatedBy: "\n").count
                    return "\(linked) (\(lines) lines)"
                }
                return linked
            }
            return extractFirstValue(json: json)

        case .fileRead:
            // "file_path" → show path
            if let filePath = json["file_path"] as? String ?? json["path"] as? String {
                let display = ToolOutputFormatter.truncatePathCenter(filePath, maxWidth: 70)
                let linker = TerminalHyperlinkFormatter()
                return linker.formatFilePath(filePath, visibleText: display)
            }
            return extractFirstValue(json: json)

        case .search:
            // "pattern"/"query" → show search query
            if let pattern = json["pattern"] as? String ?? json["query"] as? String ?? json["search"] as? String {
                let truncated = ToolOutputFormatter.truncateText(pattern, maxLength: 50)
                var summary = "\"\(truncated)\""
                if let path = json["path"] as? String {
                    let display = ToolOutputFormatter.truncatePathCenter(path, maxWidth: 30)
                    summary += " in \(display)"
                }
                return summary
            }
            return extractFirstValue(json: json)

        case .memory:
            // Memory tools → show operation
            if let operation = json["operation"] as? String ?? json["action"] as? String {
                return operation
            }
            if let domain = json["domain"] as? String {
                return domain
            }
            return extractFirstValue(json: json)

        case .default:
            // Use existing summarizeInput logic
            if let filePath = json["file_path"] as? String {
                let display = ToolOutputFormatter.truncatePathCenter(filePath, maxWidth: 60)
                let linker = TerminalHyperlinkFormatter()
                return linker.formatFilePath(filePath, visibleText: display)
            }
            if let path = json["path"] as? String {
                let display = ToolOutputFormatter.truncatePathCenter(path, maxWidth: 60)
                let linker = TerminalHyperlinkFormatter()
                return linker.formatFilePath(path, visibleText: display)
            }
            return extractFirstValue(json: json)
        }
    }

    // MARK: - Result Formatting Helpers

    private static func formatSuccessLabel(category: ToolCategory, content: String) -> String {
        switch category {
        case .shell:
            // Check for exit code in output
            if let exitCode = extractExitCode(from: content) {
                return exitCode == 0 ? "completed" : "exited \(exitCode)"
            }
            return "completed"
        case .edit:
            return "edited"
        case .fileWrite:
            return "written"
        case .fileRead:
            return "read"
        case .search:
            if let matchCount = extractMatchCount(from: content) {
                return "\(matchCount) result\(matchCount == 1 ? "" : "s")"
            }
            return "completed"
        case .memory:
            return "ok"
        case .default:
            return "completed"
        }
    }

    private static func formatErrorLabel(category: ToolCategory, content: String) -> String {
        switch category {
        case .shell:
            if let exitCode = extractExitCode(from: content) {
                return "exited \(exitCode)"
            }
            return "failed"
        case .edit:
            return "edit failed"
        case .fileWrite:
            return "write failed"
        case .fileRead:
            return "read failed"
        case .search:
            return "search failed"
        case .memory:
            return "memory error"
        case .default:
            return "failed"
        }
    }

    private static func extractSuccessPreview(content: String, category: ToolCategory) -> String {
        switch category {
        case .shell:
            // TTY mode uses renderShellOutput() multi-line block in formatCompleted.
            // Non-TTY fallback still needs a single-line preview here.
            let firstLine = content.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ToolOutputFormatter.truncateText(firstLine, maxLength: 60)
        case .edit, .fileWrite:
            return ""  // File operations — path already shown in start line
        case .fileRead:
            let lineCount = content.components(separatedBy: "\n").count
            return lineCount > 1 ? "\(lineCount) lines" : ""
        case .search:
            return ""  // Match count shown in label
        case .memory, .default:
            return ToolOutputFormatter.truncateText(content, maxLength: 60)
        }
    }

    private static func extractErrorPreview(content: String, category: ToolCategory) -> String {
        let summary = ToolOutputFormatter.truncateText(content, maxLength: 100)
        return summary
    }

    // MARK: - Shell Output Rendering (Codex-inspired)

    /// Result of rendering multi-line shell output.
    private struct ShellOutputResult {
        let text: String
        let numberOfLines: Int
    }

    /// Renders shell command output as an indented, dimmed multi-line block.
    ///
    /// Codex-inspired: Codex's `EventProcessorWithHumanOutput.render_item_completed`
    /// shows `aggregated_output` inline after the completion status line.
    /// Axion adapts this with:
    /// - Indented output lines (3-space prefix) for visual hierarchy
    /// - Dimmed ANSI styling for non-intrusive display
    /// - Smart truncation: up to `maxLines` shown, "...N more lines" indicator
    /// - Per-line truncation to prevent terminal overflow
    /// - Strip ANSI escape sequences from command output (avoids garbled display)
    /// - Skip empty lines and box-drawing borders for cleaner output
    ///
    /// Example TTY output:
    /// ```
    /// ✓ completed [350ms]
    ///     total 32
    ///     drwxr-xr-x  5 user  staff  160 Jun 10...
    ///     -rw-r--r--  1 user  staff  847 Jun 10...
    ///     … 12 more lines
    /// ```
    ///
    /// - Parameters:
    ///   - content: Raw tool result content (may contain JSON wrapper or plain text)
    ///   - maxLines: Maximum output lines to display (default 4)
    ///   - maxWidth: Maximum characters per line (default 100)
    ///   - isTTY: Whether output is to a TTY (enables colors/indentation)
    ///   - profile: Terminal color capability
    /// - Returns: ShellOutputResult with formatted text and line count
    private static func renderShellOutput(
        content: String,
        maxLines: Int = 4,
        maxWidth: Int = 100,
        isTTY: Bool = isatty(STDERR_FILENO) != 0,
        profile: TerminalColorProfile = .detect()
    ) -> ShellOutputResult {
        // Extract actual output text — may be wrapped in JSON by SDK
        let outputText = extractShellOutputText(from: content)
        guard !outputText.isEmpty else {
            return ShellOutputResult(text: "", numberOfLines: 0)
        }

        // Strip ANSI escape sequences from command output
        let cleaned = outputText.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )

        // Split into lines, clean whitespace, filter empty/border lines
        let allLines = cleaned.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isBoxDrawingBorder($0) }

        guard !allLines.isEmpty else {
            return ShellOutputResult(text: "", numberOfLines: 0)
        }

        let dimANSI: String
        let resetANSI: String
        if isTTY {
            dimANSI = Self.dimCode(for: profile)
            resetANSI = reset
        } else {
            dimANSI = ""
            resetANSI = ""
        }

        let indent = "   "  // 3-space indent for visual hierarchy
        let visibleLines = allLines.prefix(maxLines)
        let hasMore = allLines.count > maxLines

        var result = ""
        for line in visibleLines {
            let truncated = ToolOutputFormatter.truncateText(line, maxLength: maxWidth)
            result += "\(dimANSI)\(indent)\(truncated)\(resetANSI)\n"
        }

        if hasMore {
            let remaining = allLines.count - maxLines
            result += "\(dimANSI)\(indent)… \(remaining) more lines\(resetANSI)\n"
        }

        return ShellOutputResult(text: result, numberOfLines: allLines.count)
    }

    /// Extracts the actual command output text from tool result content.
    ///
    /// SDK may wrap bash results as JSON with "output"/"stdout" field,
    /// or the content may be plain text. This method handles both cases.
    private static func extractShellOutputText(from content: String) -> String {
        // Try JSON wrapper first (SDK bash tool format)
        if let json = parseJSONDict(from: content) {
            if let output = json["output"] as? String {
                return output
            }
            if let stdout = json["stdout"] as? String {
                return stdout
            }
            // JSON but no output field — might be just exit code
            if json["exitCode"] != nil || json["exit_code"] != nil {
                // Return empty if only exit code (no actual output)
                return json.values
                    .compactMap { $0 as? String }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            }
        }
        // Plain text — return as-is
        return content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : content
    }

    /// Returns the dim ANSI code for the given terminal color profile.
    private static func dimCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;120;120;120m"
        case .ansi256: return "\u{1B}[38;5;244m"
        case .ansi16: return "\u{1B}[2m"
        case .unknown: return ""
        }
    }

    // MARK: - JSON Parsing Helpers

    /// Attempts to parse a JSON dictionary from a string.
    private static func parseJSONDict(from input: String) -> [String: Any]? {
        guard let data = input.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Extracts the first value from a JSON dict as a truncated string.
    private static func extractFirstValue(json: [String: Any]) -> String {
        if let first = json.values.first {
            let str = String(describing: first)
            return ToolOutputFormatter.truncateText(str, maxLength: 80)
        }
        return ""
    }

    /// Formats line change counts in git diff convention.
    private static func formatLineChange(added: Int, removed: Int) -> String {
        var parts: [String] = []
        if added > 0 { parts.append("+\(added)") }
        if removed > 0 { parts.append("-\(removed)") }
        return parts.isEmpty ? "0 changes" : parts.joined(separator: "/")
    }

    /// Extracts exit code from shell tool output.
    private static func extractExitCode(from content: String) -> Int? {
        // SDK wraps bash results as JSON with optional exitCode field
        if let json = parseJSONDict(from: content),
           let exitCode = json["exitCode"] as? Int ?? json["exit_code"] as? Int {
            return exitCode
        }
        return nil
    }

    /// Extracts match count from search tool output.
    private static func extractMatchCount(from content: String) -> Int? {
        // Grep/search tools often report count in output
        if let json = parseJSONDict(from: content),
           let count = json["count"] as? Int ?? json["matches"] as? Int ?? json["numResults"] as? Int {
            return count
        }
        // Try counting lines for line-based grep output
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        if lines.count > 0 && lines.count <= 100 {
            // Heuristic: if output looks like grep results (lines with colons)
            let grepLike = lines.filter { $0.contains(":") }.count
            if grepLike > 0 && grepLike == lines.count {
                return grepLike
            }
        }
        return nil
    }

    // MARK: - Color Helpers

    private static func statusColorSuccess(profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;76;175;80m"    // green
        case .ansi256: return "\u{1B}[38;5;71m"
        case .ansi16: return "\u{1B}[32m"
        case .unknown: return ""
        }
    }

    private static func statusColorError(profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;244;67;54m"    // red
        case .ansi256: return "\u{1B}[38;5;160m"
        case .ansi16: return "\u{1B}[31m"
        case .unknown: return ""
        }
    }

    /// Formats milliseconds as duration string.
    private static func formatDurationMs(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        }
        return String(format: "%.1fs", Double(ms) / 1000.0)
    }
}
