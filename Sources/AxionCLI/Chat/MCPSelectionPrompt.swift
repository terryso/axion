import Darwin

enum MCPSelectionResult: Equatable {
    case cancelled
    case nonTTYListOnly
}

struct MCPSelectionPrompt {
    let isTTY: Bool
    let keyReader: (any KeyReading)?
    let writeOutput: (String) -> Void
    let maxItems: Int
    let terminalWidth: Int

    init(
        isTTY: Bool = isatty(STDIN_FILENO) != 0,
        keyReader: (any KeyReading)? = nil,
        writeOutput: @escaping (String) -> Void,
        maxItems: Int = MCPStatusFormatter.defaultMaxItems,
        terminalWidth: Int = ChatComposer.terminalColumns()
    ) {
        self.isTTY = isTTY
        self.keyReader = keyReader
        self.writeOutput = writeOutput
        self.maxItems = max(1, maxItems)
        self.terminalWidth = max(1, terminalWidth)
    }

    func run(entries: [MCPStatusEntry]) -> MCPSelectionResult {
        if !isTTY {
            writeOutput(MCPStatusFormatter.renderList(
                entries,
                selectedIndex: nil,
                maxItems: maxItems,
                includeControls: false,
                numbered: true,
                terminalWidth: terminalWidth
            ))
            return .nonTTYListOnly
        }

        let reader: any KeyReading
        var ownedReader: KeyEventReader?
        if let keyReader {
            reader = keyReader
        } else if let created = KeyEventReader.create() {
            ownedReader = created
            reader = created
        } else {
            writeOutput(MCPStatusFormatter.renderList(
                entries,
                selectedIndex: nil,
                maxItems: maxItems,
                includeControls: false,
                numbered: true,
                terminalWidth: terminalWidth
            ))
            return .nonTTYListOnly
        }
        defer { ownedReader?.restore() }

        let pageSize = max(1, maxItems)
        var selectedIndex = entries.isEmpty ? -1 : 0
        var startIndex = 0
        var showingDetail = false
        var renderedLines = 0
        renderList(entries: entries, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)

        while true {
            guard let event = reader.readNext() else { return .cancelled }
            switch event {
            case .up where !showingDetail:
                if selectedIndex > 0 {
                    selectedIndex -= 1
                    if selectedIndex < startIndex {
                        startIndex = selectedIndex
                    }
                    renderList(entries: entries, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)
                }
            case .down where !showingDetail:
                if selectedIndex >= 0, selectedIndex < entries.count - 1 {
                    selectedIndex += 1
                    if selectedIndex >= startIndex + pageSize {
                        startIndex = selectedIndex - pageSize + 1
                    }
                    renderList(entries: entries, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)
                }
            case .enter where !showingDetail:
                guard selectedIndex >= 0, selectedIndex < entries.count else {
                    return cancel()
                }
                showingDetail = true
                renderDetail(entry: entries[selectedIndex], renderedLines: &renderedLines)
            case .left where showingDetail:
                showingDetail = false
                renderList(entries: entries, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)
            case .printable(let char) where showingDetail && char.lowercased() == "b":
                showingDetail = false
                renderList(entries: entries, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)
            case .printable(let char) where char.lowercased() == "q":
                return cancel()
            case .escape, .ctrl("c"), .eof:
                return cancel()
            default:
                break
            }
        }
    }

    private func renderList(entries: [MCPStatusEntry], selectedIndex: Int, startIndex: Int, renderedLines: inout Int) {
        let rendered = MCPStatusFormatter.renderList(
            entries,
            selectedIndex: selectedIndex,
            maxItems: maxItems,
            startIndex: startIndex,
            includeControls: true,
            terminalWidth: terminalWidth
        )
        replaceRenderedContent(with: rendered, renderedLines: &renderedLines)
    }

    private func renderDetail(entry: MCPStatusEntry, renderedLines: inout Int) {
        let rendered = MCPStatusFormatter.renderDetail(entry, terminalWidth: terminalWidth)
        replaceRenderedContent(with: rendered, renderedLines: &renderedLines)
    }

    private func cancel() -> MCPSelectionResult {
        writeOutput("\r\n")
        return .cancelled
    }

    private func replaceRenderedContent(with rendered: String, renderedLines: inout Int) {
        var output = ""
        if renderedLines > 0 {
            output += "\u{1B}[\(renderedLines)A\u{1B}[J"
        }
        renderedLines = physicalLineCount(rendered)
        writeOutput(output + rendered.replacingOccurrences(of: "\n", with: "\r\n"))
    }

    private func physicalLineCount(_ rendered: String) -> Int {
        let printable = rendered.hasSuffix("\n") ? String(rendered.dropLast()) : rendered
        guard !printable.isEmpty else { return 0 }
        return ChatComposer.calculatePhysicalLines(rendered: printable, termWidth: terminalWidth)
    }
}
