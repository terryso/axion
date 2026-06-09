import Foundation

// MARK: - Universal Memory Context (Story 31.1)

extension MemoryContextProvider {

    /// Build a universal memory context string from MEMORY.md and USER.md.
    ///
    /// Loads both files via `UniversalMemoryStore`, parses §-delimited entries,
    /// filters out suspicious/dangerous entries via `MemorySecurityScanner.scanEntry()`,
    /// and formats the result as a `[=== Universal Memory ===]` block.
    /// Returns `nil` if no safe entries remain (safe degradation).
    func buildUniversalMemoryContext(memoryDir: String) async -> String? {
        let store = UniversalMemoryStore(memoryDir: memoryDir)
        let scanner = MemorySecurityScanner()

        let memoryContent = await store.read(target: .memory)
        let userContent = await store.read(target: .user)

        let (safeMemoryEntries, filteredMemory) = filterEntries(
            from: memoryContent, using: scanner
        )
        let (safeUserEntries, filteredUser) = filterEntries(
            from: userContent, using: scanner
        )

        if filteredMemory > 0 || filteredUser > 0 {
            fputs(
                "UniversalMemory: filtered \(filteredMemory + filteredUser) suspicious entries\n",
                stderr
            )
        }

        guard !safeMemoryEntries.isEmpty || !safeUserEntries.isEmpty else {
            return nil
        }

        var sections: [String] = []
        sections.append("[=== Universal Memory ===]")

        if !safeMemoryEntries.isEmpty {
            sections.append("MEMORY.md:")
            sections.append(safeMemoryEntries.map { "§\n\($0)\n§" }.joined(separator: "\n"))
        }

        if !safeUserEntries.isEmpty {
            sections.append("USER.md:")
            sections.append(safeUserEntries.map { "§\n\($0)\n§" }.joined(separator: "\n"))
        }

        sections.append("[=== End Universal Memory ===]")
        return sections.joined(separator: "\n")
    }

    /// Parse §-delimited entries and filter out any that fail security scanning.
    /// Returns the safe entries and the count of filtered entries.
    func filterEntries(
        from content: String,
        using scanner: MemorySecurityScanner
    ) -> (safe: [String], filtered: Int) {
        let entries = parseEntries(from: content)
        var safe: [String] = []
        var filtered = 0
        for entry in entries {
            let result = scanner.scanEntry(content: entry)
            switch result {
            case .safe:
                safe.append(entry)
            case .rejected, .warning:
                filtered += 1
            }
        }
        return (safe, filtered)
    }

    /// Parse §-delimited entries from raw file content.
    func parseEntries(from content: String) -> [String] {
        content
            .components(separatedBy: "§")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
