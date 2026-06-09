import Foundation

/// Tracks file changes (Edit/Write) during a single agent turn and renders a
/// compact summary after the turn completes.
///
/// Codex-inspired: Codex's `FileChange` thread item and `TurnDiffUpdated`
/// notification show a real-time diff of files changed during a turn.
/// Axion's version tracks Edit/Write tool inputs to produce a per-turn
/// file change summary with +/- line counts and color-coded indicators.
///
/// Example output (TTY):
/// ```
/// 📝 2 files changed (+57 -3)
///    Sources/AxionCLI/Chat/BannerRenderer.swift (+12 -3)
///    Tests/…/BannerRendererTests.swift (+45)
/// ```
///
/// Non-TTY fallback:
/// ```
/// [changes: 2 files changed (+57 -3)]
/// [change: BannerRenderer.swift +12 -3]
/// [change: BannerRendererTests.swift +45]
/// ```
struct TurnFileChangeTracker: Sendable {

    /// A single file change record with line-level diff stats.
    struct FileChange: Sendable, Equatable {
        /// Relative or absolute file path.
        let filePath: String
        /// Number of lines added.
        let addedLines: Int
        /// Number of lines removed.
        let removedLines: Int

        /// Human-readable display string without color codes.
        var displayString: String {
            var parts: [String] = []
            if addedLines > 0 { parts.append("+\(addedLines)") }
            if removedLines > 0 { parts.append("-\(removedLines)") }
            let stats = parts.isEmpty ? "" : " (\(parts.joined(separator: " ")))"
            return "\(filePath)\(stats)"
        }
    }

    /// Accumulated file changes during this turn.
    private(set) var changes: [FileChange] = []

    /// Whether any file changes have been recorded.
    var hasChanges: Bool { !changes.isEmpty }

    // MARK: - Recording

    /// Records a file change from a tool use event.
    ///
    /// Only processes "Edit" and "Write" tools; all others are ignored.
    /// For Edit: counts all old_string lines as removed, all new_string lines as added
    /// (git diff convention — the replaced section is shown as both - and + lines).
    /// For Write: counts all content lines as added.
    ///
    /// - Parameters:
    ///   - toolName: The tool name (e.g. "Edit", "Write").
    ///   - input: Raw JSON input string from the tool use event.
    mutating func recordToolUse(toolName: String, input: String) {
        guard toolName == "Edit" || toolName == "Write" else { return }
        guard let json = parseJSONDict(from: input) else { return }

        switch toolName {
        case "Edit":
            if let filePath = json["file_path"] as? String,
               let oldString = json["old_string"] as? String,
               let newString = json["new_string"] as? String
            {
                let removedLines = oldString.components(separatedBy: "\n").count
                let addedLines = newString.components(separatedBy: "\n").count
                changes.append(FileChange(
                    filePath: filePath,
                    addedLines: addedLines,
                    removedLines: removedLines
                ))
            }
        case "Write":
            if let filePath = json["file_path"] as? String,
               let content = json["content"] as? String
            {
                let lineCount = content.components(separatedBy: "\n").count
                changes.append(FileChange(
                    filePath: filePath,
                    addedLines: lineCount,
                    removedLines: 0
                ))
            }
        default:
            break
        }
    }

    /// Resets the tracker for a new turn.
    mutating func reset() {
        changes.removeAll()
    }

    // MARK: - Rendering

    /// Deduplicates changes by file path, aggregating line counts.
    ///
    /// When the agent makes multiple edits to the same file in one turn,
    /// this merges them into a single entry with summed line counts.
    var deduplicatedChanges: [FileChange] {
        var seen: [String: FileChange] = [:]
        for change in changes {
            if let existing = seen[change.filePath] {
                seen[change.filePath] = FileChange(
                    filePath: change.filePath,
                    addedLines: existing.addedLines + change.addedLines,
                    removedLines: existing.removedLines + change.removedLines
                )
            } else {
                seen[change.filePath] = change
            }
        }
        return Array(seen.values)
    }

    /// Renders a compact file change summary after turn completion.
    ///
    /// Returns `nil` when no files were changed during the turn.
    /// Uses the same dim/gray style as the turn summary separator for visual
    /// consistency. Line count indicators use green (+) and red (-) following
    /// git diff convention.
    ///
    /// - Parameters:
    ///   - maxWidth: Maximum line width for path truncation (default 80).
    ///   - isTTY: Whether output goes to a TTY (enables colors and box-drawing).
    ///   - profile: Terminal color profile for ANSI code selection.
    /// - Returns: Formatted summary string, or `nil` if no changes.
    func renderSummary(
        maxWidth: Int = 80,
        isTTY: Bool = isatty(STDERR_FILENO) != 0,
        profile: TerminalColorProfile = .detect()
    ) -> String? {
        let files = deduplicatedChanges
        guard !files.isEmpty else { return nil }

        let fileCount = files.count
        let totalAdded = files.reduce(0) { $0 + $1.addedLines }
        let totalRemoved = files.reduce(0) { $0 + $1.removedLines }

        // Build header
        let header = "📝 \(fileCount) file\(fileCount == 1 ? "" : "s") changed"
        var stats: [String] = []
        if totalAdded > 0 { stats.append("+\(totalAdded)") }
        if totalRemoved > 0 { stats.append("-\(totalRemoved)") }
        let fullHeader = stats.isEmpty ? header : "\(header) (\(stats.joined(separator: " ")))"

        if isTTY {
            return renderTTYSummary(
                files: files,
                header: fullHeader,
                maxWidth: maxWidth,
                profile: profile
            )
        } else {
            return renderPlainSummary(files: files, header: fullHeader, maxWidth: maxWidth)
        }
    }

    // MARK: - Private Rendering

    private func renderTTYSummary(
        files: [FileChange],
        header: String,
        maxWidth: Int,
        profile: TerminalColorProfile
    ) -> String {
        let dim = dimCode(for: profile)
        let reset = "\u{1B}[0m"
        let green = greenCode(for: profile)
        let red = redCode(for: profile)
        let linker = TerminalHyperlinkFormatter()

        var lines: [String] = []
        lines.append("\(dim)\(header)\(reset)")

        for change in files {
            let truncatedPath = ToolOutputFormatter.truncatePathCenter(
                change.filePath, maxWidth: maxWidth - 15
            )
            // Wrap file path in OSC 8 hyperlink (clickable in supported terminals)
            let displayPath = linker.formatFilePath(
                change.filePath, visibleText: truncatedPath
            )
            var changeParts: [String] = []
            if change.addedLines > 0 {
                changeParts.append("\(green)+\(change.addedLines)\(reset)")
            }
            if change.removedLines > 0 {
                changeParts.append("\(red)-\(change.removedLines)\(reset)")
            }
            let changeStr = changeParts.isEmpty ? "" : " (\(changeParts.joined(separator: " ")))"
            lines.append("\(dim)   \(displayPath)\(changeStr)\(reset)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func renderPlainSummary(
        files: [FileChange],
        header: String,
        maxWidth: Int
    ) -> String {
        var lines: [String] = []
        lines.append("[changes: \(header)]")
        for change in files {
            let path = ToolOutputFormatter.truncatePathCenter(
                change.filePath, maxWidth: maxWidth - 15
            )
            var parts: [String] = []
            if change.addedLines > 0 { parts.append("+\(change.addedLines)") }
            if change.removedLines > 0 { parts.append("-\(change.removedLines)") }
            let stats = parts.isEmpty ? "" : " \(parts.joined(separator: " "))"
            lines.append("[change: \(path)\(stats)]")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - ANSI Helpers

    private func dimCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;120;120;120m"
        case .ansi256: return "\u{1B}[38;5;244m"
        case .ansi16: return "\u{1B}[2m"
        case .unknown: return ""
        }
    }

    private func greenCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;76;175;80m"
        case .ansi256: return "\u{1B}[38;5;71m"
        case .ansi16: return "\u{1B}[32m"
        case .unknown: return ""
        }
    }

    private func redCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;244;67;54m"
        case .ansi256: return "\u{1B}[38;5;160m"
        case .ansi16: return "\u{1B}[31m"
        case .unknown: return ""
        }
    }
}
