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

    init(
        isTTY: Bool = isatty(STDIN_FILENO) != 0,
        keyReader: (any KeyReading)? = nil,
        writeOutput: @escaping (String) -> Void,
        maxItems: Int = AppListFormatter.defaultMaxItems,
        terminalWidth: Int = ChatComposer.terminalColumns()
    ) {
        self.isTTY = isTTY
        self.keyReader = keyReader
        self.writeOutput = writeOutput
        self.maxItems = maxItems
        self.terminalWidth = max(1, terminalWidth)
    }

    func run(result: AppListResult) -> AppSelectionResult {
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

        let visibleItems = Array(result.candidates.prefix(maxItems))
        var selectedIndex = visibleItems.isEmpty ? -1 : 0
        var renderedLines = 0
        render(result: result, selectedIndex: selectedIndex, renderedLines: &renderedLines)

        while true {
            guard let event = reader.readNext() else { return .cancelled }
            switch event {
            case .up:
                if selectedIndex > 0 {
                    selectedIndex -= 1
                    render(result: result, selectedIndex: selectedIndex, renderedLines: &renderedLines)
                }
            case .down:
                if selectedIndex >= 0, selectedIndex < visibleItems.count - 1 {
                    selectedIndex += 1
                    render(result: result, selectedIndex: selectedIndex, renderedLines: &renderedLines)
                }
            case .enter:
                guard selectedIndex >= 0, selectedIndex < visibleItems.count else {
                    return .cancelled
                }
                writeOutput("\r\n")
                return .selected(visibleItems[selectedIndex])
            case .escape, .ctrl("c"), .eof:
                writeOutput("\r\n")
                return .cancelled
            case .printable(let char) where char.lowercased() == "a" && result.deepSearchAvailable:
                writeOutput("\r\n")
                return .requestDeepSearch
            default:
                break
            }
        }
    }

    private func render(result: AppListResult, selectedIndex: Int, renderedLines: inout Int) {
        let rendered = AppListFormatter.renderList(
            result,
            selectedIndex: selectedIndex,
            maxItems: maxItems,
            includeControls: true,
            terminalWidth: terminalWidth
        )
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
