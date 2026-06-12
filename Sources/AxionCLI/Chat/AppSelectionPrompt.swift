import Darwin

enum AppSelectionResult: Equatable {
    case selected(AppListItem)
    case cancelled
    case requestDeepSearch
    case nonTTYListOnly
}

struct AppSelectionPrompt {
    let isTTY: Bool
    let keyReader: (any KeyReading)?
    let writeOutput: (String) -> Void
    let maxItems: Int
    let terminalWidth: Int
    let detailProvider: (any AppDetailProviding)?

    init(
        isTTY: Bool = isatty(STDIN_FILENO) != 0,
        keyReader: (any KeyReading)? = nil,
        writeOutput: @escaping (String) -> Void,
        maxItems: Int = AppListFormatter.defaultMaxItems,
        terminalWidth: Int = ChatComposer.terminalColumns(),
        detailProvider: (any AppDetailProviding)? = nil
    ) {
        self.isTTY = isTTY
        self.keyReader = keyReader
        self.writeOutput = writeOutput
        self.maxItems = maxItems
        self.terminalWidth = max(1, terminalWidth)
        self.detailProvider = detailProvider
    }

    func run(result: AppListResult) async -> AppSelectionResult {
        if !isTTY {
            writeOutput(AppListFormatter.renderList(
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
            writeOutput(AppListFormatter.renderList(
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

        let allItems = result.candidates
        let pageSize = max(1, maxItems)
        var selectedIndex = allItems.isEmpty ? -1 : 0
        var startIndex = 0
        var showingDetail = false
        var renderedLines = 0
        renderList(result: result, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)

        while true {
            guard let event = reader.readNext() else { return .cancelled }
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
            case .enter:
                guard selectedIndex >= 0, selectedIndex < allItems.count else {
                    return .cancelled
                }
                if !showingDetail {
                    showingDetail = true
                    renderDetail(
                        item: allItems[selectedIndex],
                        detailInfo: detailProvider == nil ? .empty : .analyzing,
                        renderedLines: &renderedLines
                    )
                    if let detailProvider {
                        let detailInfo = await detailProvider.detail(for: allItems[selectedIndex])
                        renderDetail(
                            item: allItems[selectedIndex],
                            detailInfo: detailInfo,
                            renderedLines: &renderedLines
                        )
                    }
                    continue
                }
                writeOutput("\r\n")
                return .selected(allItems[selectedIndex])
            case .left where showingDetail:
                showingDetail = false
                renderList(result: result, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)
            case .printable(let char) where showingDetail && char.lowercased() == "b":
                showingDetail = false
                renderList(result: result, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)
            case .escape, .ctrl("c"), .eof:
                writeOutput("\r\n")
                return .cancelled
            case .printable(let char) where !showingDetail && char.lowercased() == "a" && result.deepSearchAvailable:
                writeOutput("\r\n")
                return .requestDeepSearch
            default:
                break
            }
        }
    }

    private func renderList(result: AppListResult, selectedIndex: Int, startIndex: Int, renderedLines: inout Int) {
        let rendered = AppListFormatter.renderList(
            result,
            selectedIndex: selectedIndex,
            maxItems: maxItems,
            startIndex: startIndex,
            includeControls: true,
            terminalWidth: terminalWidth
        )
        replaceRenderedContent(with: rendered, renderedLines: &renderedLines)
    }

    private func renderDetail(item: AppListItem, detailInfo: AppDetailInfo, renderedLines: inout Int) {
        let rendered = AppListFormatter.renderDetail(item, detailInfo: detailInfo, terminalWidth: terminalWidth)
        replaceRenderedContent(with: rendered, renderedLines: &renderedLines)
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
