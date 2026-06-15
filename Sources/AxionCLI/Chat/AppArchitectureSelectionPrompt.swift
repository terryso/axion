import Darwin

enum AppArchitectureSelectionResult: Equatable {
    case cancelled
    case nonTTYListOnly
}

struct AppArchitectureSelectionPrompt {
    let isTTY: Bool
    let keyReader: (any KeyReading)?
    let writeOutput: (String) -> Void
    let maxItems: Int
    let terminalWidth: Int

    init(
        isTTY: Bool = isatty(STDIN_FILENO) != 0,
        keyReader: (any KeyReading)? = nil,
        writeOutput: @escaping (String) -> Void,
        maxItems: Int = AppArchitectureFormatter.defaultInteractiveMaxItems,
        terminalWidth: Int = ChatComposer.terminalColumns()
    ) {
        self.isTTY = isTTY
        self.keyReader = keyReader
        self.writeOutput = writeOutput
        self.maxItems = max(1, maxItems)
        self.terminalWidth = max(1, terminalWidth)
    }

    func run(result: AppArchitectureScanResult) -> AppArchitectureSelectionResult {
        if !isTTY {
            writeOutput(AppArchitectureFormatter.renderList(
                result,
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
            writeOutput(AppArchitectureFormatter.renderList(
                result,
                selectedIndex: nil,
                maxItems: maxItems,
                includeControls: false,
                numbered: true,
                terminalWidth: terminalWidth
            ))
            return .nonTTYListOnly
        }
        defer { ownedReader?.restore() }

        let allItems = result.visibleItems()
        let pageSize = max(1, maxItems)
        var selectedIndex = allItems.isEmpty ? -1 : 0
        var startIndex = 0
        var showingDetail = false
        var renderedLines = 0
        renderList(result: result, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)

        while true {
            guard let event = reader.readNext() else { return cancel() }
            switch event {
            case .up where !showingDetail:
                if selectedIndex > 0 {
                    selectedIndex -= 1
                    if selectedIndex < startIndex {
                        startIndex = selectedIndex
                    }
                    renderList(result: result, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)
                }
            case .down where !showingDetail:
                if selectedIndex >= 0, selectedIndex < allItems.count - 1 {
                    selectedIndex += 1
                    if selectedIndex >= startIndex + pageSize {
                        startIndex = selectedIndex - pageSize + 1
                    }
                    renderList(result: result, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)
                }
            case .enter where !showingDetail:
                guard selectedIndex >= 0, selectedIndex < allItems.count else {
                    return cancel()
                }
                showingDetail = true
                renderDetail(item: allItems[selectedIndex], renderedLines: &renderedLines)
            case .left where showingDetail:
                showingDetail = false
                renderList(result: result, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)
            case .printable(let char) where showingDetail && char.lowercased() == "b":
                showingDetail = false
                renderList(result: result, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)
            case .printable(let char) where char.lowercased() == "q":
                return cancel()
            case .escape, .ctrl("c"), .eof:
                return cancel()
            default:
                break
            }
        }
    }

    private func renderList(
        result: AppArchitectureScanResult,
        selectedIndex: Int,
        startIndex: Int,
        renderedLines: inout Int
    ) {
        let rendered = AppArchitectureFormatter.renderList(
            result,
            selectedIndex: selectedIndex,
            maxItems: maxItems,
            startIndex: startIndex,
            includeControls: true,
            terminalWidth: terminalWidth
        )
        replaceRenderedContent(with: rendered, renderedLines: &renderedLines)
    }

    private func renderDetail(item: AppArchitectureItem, renderedLines: inout Int) {
        let rendered = AppArchitectureFormatter.renderDetail(item, terminalWidth: terminalWidth)
        replaceRenderedContent(with: rendered, renderedLines: &renderedLines)
    }

    private func cancel() -> AppArchitectureSelectionResult {
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
