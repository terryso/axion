import Foundation

/// Codex-inspired file change tracker — monitors file operations during a turn
/// and renders a compact summary at turn end.
///
/// Codex's `create_diff_summary` shows:
/// - Header: "• Edited 3 files (+42 -18)"
/// - Per-file entries with tree-drawing characters (├, └)
/// - Each file shows path and +/- line counts
///
/// Axion adapts this for line-based terminal output with:
/// - Three change types: created, edited, read
/// - Per-file line change counts (added/removed)
/// - Full TerminalColorProfile degradation
/// - Non-TTY plain text fallback
/// - OSC 8 hyperlinks for file paths
struct FileChangeTracker: Sendable {

    // MARK: - Types

    /// Change type for a tracked file.
    enum ChangeKind: String, Sendable, Equatable {
        case created   // new file created (Write tool)
        case edited    // existing file modified (Edit tool)
        case read      // file read (Read tool)
    }

    /// A single file's change record.
    struct FileChange: Sendable, Equatable {
        let filePath: String
        let kind: ChangeKind
        let linesAdded: Int
        let linesRemoved: Int

        /// For .created files, linesAdded represents total content lines.
        /// For .edited files, linesAdded/linesRemoved represent diff hunks.
        /// For .read files, both are 0 (informational only).
    }

    // MARK: - State

    /// Tracked file changes, keyed by file path for deduplication.
    private(set) var changes: [String: FileChange] = [:]

    // MARK: - Mutation

    /// Record a file write operation (new file or overwrite).
    mutating func recordWrite(filePath: String, contentLineCount: Int) {
        let path = normalizePath(filePath)
        if let existing = changes[path] {
            // Upgrade from read → created/edited
            switch existing.kind {
            case .read:
                changes[path] = FileChange(
                    filePath: path,
                    kind: .created,
                    linesAdded: contentLineCount,
                    linesRemoved: 0
                )
            case .edited, .created:
                // Already tracked as edit/create — update line count
                changes[path] = FileChange(
                    filePath: path,
                    kind: existing.kind,
                    linesAdded: contentLineCount,
                    linesRemoved: existing.linesRemoved
                )
            }
        } else {
            changes[path] = FileChange(
                filePath: path,
                kind: .created,
                linesAdded: contentLineCount,
                linesRemoved: 0
            )
        }
    }

    /// Record a file edit operation (existing file modification).
    mutating func recordEdit(filePath: String, linesAdded: Int, linesRemoved: Int) {
        let path = normalizePath(filePath)
        if let existing = changes[path] {
            // Accumulate edits
            switch existing.kind {
            case .read:
                changes[path] = FileChange(
                    filePath: path,
                    kind: .edited,
                    linesAdded: linesAdded,
                    linesRemoved: linesRemoved
                )
            case .edited, .created:
                changes[path] = FileChange(
                    filePath: path,
                    kind: existing.kind,
                    linesAdded: existing.linesAdded + linesAdded,
                    linesRemoved: existing.linesRemoved + linesRemoved
                )
            }
        } else {
            changes[path] = FileChange(
                filePath: path,
                kind: .edited,
                linesAdded: linesAdded,
                linesRemoved: linesRemoved
            )
        }
    }

    /// Record a file read operation (informational).
    mutating func recordRead(filePath: String) {
        let path = normalizePath(filePath)
        // Only add if not already tracked as a more significant change
        if changes[path] == nil {
            changes[path] = FileChange(
                filePath: path,
                kind: .read,
                linesAdded: 0,
                linesRemoved: 0
            )
        }
    }

    /// Reset all tracked changes (call at start of each turn).
    mutating func reset() {
        changes.removeAll()
    }

    // MARK: - Query

    /// Whether there are any file changes to display.
    var hasChanges: Bool { !changes.isEmpty }

    /// Count of write/create operations.
    var writeCount: Int { changes.values.filter { $0.kind == .created }.count }

    /// Count of edit operations.
    var editCount: Int { changes.values.filter { $0.kind == .edited }.count }

    /// Count of read operations.
    var readCount: Int { changes.values.filter { $0.kind == .read }.count }

    /// Total lines added across all changes.
    var totalLinesAdded: Int { changes.values.reduce(0) { $0 + $1.linesAdded } }

    /// Total lines removed across all changes.
    var totalLinesRemoved: Int { changes.values.reduce(0) { $0 + $1.linesRemoved } }

    // MARK: - Rendering

    /// Renders the file change summary as a formatted string.
    ///
    /// TTY output (Codex-inspired tree structure):
    /// ```
    /// • Edited 3 files (+42 -18)
    ///   ├── src/Foo.swift (+30 -12)
    ///   ├── src/Bar.swift (+12)
    ///   └── src/Baz.swift (-6)
    /// ```
    ///
    /// Non-TTY output:
    /// ```
    /// [files: 3 changed, +42 -18]
    ///   src/Foo.swift (+30 -12)
    ///   src/Bar.swift (+12)
    ///   src/Baz.swift (-6)
    /// ```
    func renderSummary(
        isTTY: Bool = isatty(STDOUT_FILENO) != 0,
        profile: TerminalColorProfile = .detect()
    ) -> String {
        guard hasChanges else { return "" }

        let sorted = sortedChanges()
        let totalFiles = sorted.count
        let totalAdded = sorted.reduce(0) { $0 + $1.linesAdded }
        let totalRemoved = sorted.reduce(0) { $0 + $1.linesRemoved }

        if isTTY {
            return renderTTYSummary(
                sorted: sorted,
                totalFiles: totalFiles,
                totalAdded: totalAdded,
                totalRemoved: totalRemoved,
                profile: profile
            )
        } else {
            return renderPlainSummary(
                sorted: sorted,
                totalFiles: totalFiles,
                totalAdded: totalAdded,
                totalRemoved: totalRemoved
            )
        }
    }

    // MARK: - Private Helpers

    /// Sort changes: writes first, then edits, then reads. Within each group, alphabetically by path.
    private func sortedChanges() -> [FileChange] {
        changes.values.sorted { a, b in
            let orderA = changeKindOrder(a.kind)
            let orderB = changeKindOrder(b.kind)
            if orderA != orderB { return orderA < orderB }
            return a.filePath.localizedStandardCompare(b.filePath) == .orderedAscending
        }
    }

    private func changeKindOrder(_ kind: ChangeKind) -> Int {
        switch kind {
        case .created: return 0
        case .edited: return 1
        case .read: return 2
        }
    }

    /// Normalize file path: remove leading "./" if present.
    private func normalizePath(_ path: String) -> String {
        if path.hasPrefix("./") {
            return String(path.dropFirst(2))
        }
        return path
    }

    // MARK: - TTY Rendering

    private func renderTTYSummary(
        sorted: [FileChange],
        totalFiles: Int,
        totalAdded: Int,
        totalRemoved: Int,
        profile: TerminalColorProfile
    ) -> String {
        let reset = "\u{1B}[0m"
        let dim = dimANSI(for: profile)
        let bold = "\u{1B}[1m"
        let green = greenANSI(for: profile)
        let red = redANSI(for: profile)
        let cyan = cyanANSI(for: profile)
        let orange = orangeANSI(for: profile)

        // Build header line
        var header = "\(dim)• \(reset)"

        // Determine primary verb
        let writes = sorted.filter { $0.kind == .created }
        let edits = sorted.filter { $0.kind == .edited }
        let reads = sorted.filter { $0.kind == .read }

        // Only count writes and edits as "changed" files
        let changedFiles = writes.count + edits.count

        if changedFiles == 0 && reads.count > 0 {
            // Only reads — show "Read N files"
            header += "\(bold)Read\(reset) \(reads.count) file\(reads.count == 1 ? "" : "s")"
        } else if changedFiles == 1, let single = (writes.first ?? edits.first) {
            // Single file change — inline the path
            let verb = single.kind == .created ? "Created" : "Edited"
            let pathDisplay = renderPath(single.filePath, profile: profile)
            header += "\(bold)\(verb)\(reset) \(pathDisplay)"
            header += " \(formatLineCounts(single.linesAdded, single.linesRemoved, green: green, red: red, reset: reset))"
        } else {
            // Multiple files
            var verb = "Edited"
            if writes.count > 0 && edits.count == 0 {
                verb = "Created"
            } else if writes.count > 0 && edits.count > 0 {
                verb = "Changed"
            }
            header += "\(bold)\(verb)\(reset) \(changedFiles) file\(changedFiles == 1 ? "" : "s")"
            header += " \(formatLineCounts(totalAdded, totalRemoved, green: green, red: red, reset: reset))"
        }

        var output = "\(header)\n"

        // Per-file entries (skip if only reads or single file — already shown in header)
        if changedFiles > 1 || (changedFiles == 0 && reads.count > 1) {
            let entries = changedFiles > 0
                ? sorted.filter { $0.kind != .read }
                : sorted

            for (idx, change) in entries.enumerated() {
                let isLast = idx == entries.count - 1
                let prefix = isLast ? "  └── " : "  ├── "
                let pathDisplay = renderPath(change.filePath, profile: profile)

                let kindLabel: String
                let kindColor: String
                switch change.kind {
                case .created:
                    kindLabel = "created"
                    kindColor = green
                case .edited:
                    kindLabel = "edited"
                    kindColor = orange
                case .read:
                    kindLabel = "read"
                    kindColor = cyan
                }

                output += "\(dim)\(prefix)\(reset)\(kindColor)\(kindLabel)\(reset) \(pathDisplay)"
                if change.linesAdded > 0 || change.linesRemoved > 0 {
                    output += " \(formatLineCounts(change.linesAdded, change.linesRemoved, green: green, red: red, reset: reset))"
                }
                output += "\n"
            }
        }

        return output
    }

    /// Render a file path, optionally as an OSC 8 hyperlink.
    private func renderPath(_ path: String, profile: TerminalColorProfile) -> String {
        let display = ToolOutputFormatter.truncatePathCenter(path, maxWidth: 60)
        let linker = TerminalHyperlinkFormatter()
        return linker.formatFilePath(path, visibleText: display)
    }

    /// Format +N/-M line counts in Codex style.
    private func formatLineCounts(_ added: Int, _ removed: Int, green: String, red: String, reset: String) -> String {
        var parts: [String] = []
        if added > 0 {
            parts.append("\(green)+\(added)\(reset)")
        }
        if removed > 0 {
            parts.append("\(red)-\(removed)\(reset)")
        }
        guard !parts.isEmpty else { return "" }
        return "(\(parts.joined(separator: " ")))"
    }

    // MARK: - Plain Text Rendering

    private func renderPlainSummary(
        sorted: [FileChange],
        totalFiles: Int,
        totalAdded: Int,
        totalRemoved: Int
    ) -> String {
        let changedFiles = sorted.filter { $0.kind != .read }.count
        let reads = sorted.filter { $0.kind == .read }.count

        var parts: [String] = []
        if changedFiles > 0 {
            parts.append("\(changedFiles) file\(changedFiles == 1 ? "" : "s") changed")
        }
        if totalAdded > 0 { parts.append("+\(totalAdded)") }
        if totalRemoved > 0 { parts.append("-\(totalRemoved)") }
        if reads > 0 && changedFiles == 0 {
            parts.append("\(reads) file\(reads == 1 ? "" : "s") read")
        }

        guard !parts.isEmpty else { return "" }

        var output = "[\(parts.joined(separator: ", "))]\n"

        // Per-file entries only for multiple changed files
        let changed = sorted.filter { $0.kind != .read }
        if changed.count > 1 {
            for change in changed {
                let verb = change.kind == .created ? "created" : "edited"
                var line = "  \(change.filePath) (\(verb)"
                if change.linesAdded > 0 { line += " +\(change.linesAdded)" }
                if change.linesRemoved > 0 { line += " -\(change.linesRemoved)" }
                line += ")"
                output += "\(line)\n"
            }
        }

        return output
    }

    // MARK: - ANSI Color Helpers

    private func dimANSI(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;120;120;140m"
        case .ansi256: return "\u{1B}[38;5;244m"
        case .ansi16: return "\u{1B}[2m"
        case .unknown: return ""
        }
    }

    private func greenANSI(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;76;175;80m"
        case .ansi256: return "\u{1B}[38;5;71m"
        case .ansi16: return "\u{1B}[32m"
        case .unknown: return ""
        }
    }

    private func redANSI(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;244;67;54m"
        case .ansi256: return "\u{1B}[38;5;160m"
        case .ansi16: return "\u{1B}[31m"
        case .unknown: return ""
        }
    }

    private func cyanANSI(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;129;140;248m"
        case .ansi256: return "\u{1B}[38;5;104m"
        case .ansi16: return "\u{1B}[36m"
        case .unknown: return ""
        }
    }

    private func orangeANSI(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;255;183;77m"
        case .ansi256: return "\u{1B}[38;5;215m"
        case .ansi16: return "\u{1B}[33m"
        case .unknown: return ""
        }
    }

    // MARK: - Tool Integration

    /// Extracts file path and relevant info from a tool use event.
    /// Returns nil if the tool doesn't involve file operations.
    static func extractFileInfo(toolName: String, input: String) -> (filePath: String, kind: ChangeKind, linesAdded: Int, linesRemoved: Int)? {
        guard let json = parseJSONDict(from: input) else { return nil }

        let category = ToolCategoryFormatter.categorize(toolName: toolName)

        switch category {
        case .fileWrite:
            guard let filePath = json["file_path"] as? String else { return nil }
            let contentLines = (json["content"] as? String)?.components(separatedBy: "\n").count ?? 0
            return (filePath: filePath, kind: .created, linesAdded: contentLines, linesRemoved: 0)

        case .edit:
            guard let filePath = json["file_path"] as? String else { return nil }
            let removed = (json["old_string"] as? String)?.components(separatedBy: "\n").count ?? 0
            let added = (json["new_string"] as? String)?.components(separatedBy: "\n").count ?? 0
            return (filePath: filePath, kind: .edited, linesAdded: added, linesRemoved: removed)

        case .fileRead:
            if let filePath = json["file_path"] as? String ?? json["path"] as? String {
                return (filePath: filePath, kind: .read, linesAdded: 0, linesRemoved: 0)
            }
            return nil

        default:
            return nil
        }
    }

    /// Parses a JSON dictionary from a string.
    private static func parseJSONDict(from input: String) -> [String: Any]? {
        guard let data = input.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
