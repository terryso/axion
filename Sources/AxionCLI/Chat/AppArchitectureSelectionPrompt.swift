import Darwin
import Foundation

enum AppArchitectureSelectionResult: Equatable {
    case requestAppUninstall(AppArchitectureItem)
    case cancelled
    case nonTTYListOnly
}

struct AppArchitectureSelectionPrompt {
    let isTTY: Bool
    let keyReader: (any KeyReading)?
    let writeOutput: (String) -> Void
    let maxItems: Int
    let terminalWidth: Int
    let upgradePlanner: (any AppArchitectureUpgradePlanning)?
    let upgradeExecutor: (any AppArchitectureUpgradeExecuting)?
    let postUpgradeScanner: (any AppArchitecturePostUpgradeScanning)?
    let listScanner: (any AppArchitectureScanning)?
    let detailProvider: (any AppArchitectureDetailProviding)?

    init(
        isTTY: Bool = isatty(STDIN_FILENO) != 0,
        keyReader: (any KeyReading)? = nil,
        writeOutput: @escaping (String) -> Void,
        maxItems: Int = AppArchitectureFormatter.defaultInteractiveMaxItems,
        terminalWidth: Int = ChatComposer.terminalColumns(),
        upgradePlanner: (any AppArchitectureUpgradePlanning)? = nil,
        upgradeExecutor: (any AppArchitectureUpgradeExecuting)? = nil,
        postUpgradeScanner: (any AppArchitecturePostUpgradeScanning)? = nil,
        listScanner: (any AppArchitectureScanning)? = nil,
        detailProvider: (any AppArchitectureDetailProviding)? = nil
    ) {
        self.isTTY = isTTY
        self.keyReader = keyReader
        self.writeOutput = writeOutput
        self.maxItems = max(1, maxItems)
        self.terminalWidth = max(1, terminalWidth)
        self.upgradePlanner = upgradePlanner
        self.upgradeExecutor = upgradeExecutor
        self.postUpgradeScanner = postUpgradeScanner
        self.listScanner = listScanner
        self.detailProvider = detailProvider
    }

    func run(result: AppArchitectureScanResult) async -> AppArchitectureSelectionResult {
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

        var currentResult = result
        var allItems = currentResult.visibleItems()
        let pageSize = max(1, maxItems)
        var selectedIndex = allItems.isEmpty ? -1 : 0
        var startIndex = 0
        var showingDetail = false
        var showingUpgradeResult = false
        var shouldRescanListOnReturn = false
        var currentPlan: AppArchitectureUpgradePlan?
        var currentDetailInfo: AppArchitectureDetailInfo = .empty
        var renderedLines = 0
        renderList(result: currentResult, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)

        while true {
            guard let event = reader.readNext() else { return cancel() }
            switch event {
            case .up where !showingDetail:
                if selectedIndex > 0 {
                    selectedIndex -= 1
                    if selectedIndex < startIndex {
                        startIndex = selectedIndex
                    }
                    renderList(result: currentResult, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)
                }
            case .down where !showingDetail:
                if selectedIndex >= 0, selectedIndex < allItems.count - 1 {
                    selectedIndex += 1
                    if selectedIndex >= startIndex + pageSize {
                        startIndex = selectedIndex - pageSize + 1
                    }
                    renderList(result: currentResult, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)
                }
            case .enter where !showingDetail:
                guard selectedIndex >= 0, selectedIndex < allItems.count else {
                    return cancel()
                }
                showingDetail = true
                showingUpgradeResult = false
                currentPlan = nil
                currentDetailInfo = detailProvider == nil ? .empty : .analyzing
                renderDetail(
                    item: allItems[selectedIndex],
                    upgradePlan: nil,
                    detailInfo: currentDetailInfo,
                    renderedLines: &renderedLines
                )
                if let upgradePlanner {
                    currentPlan = await upgradePlanner.plan(for: allItems[selectedIndex])
                    renderDetail(
                        item: allItems[selectedIndex],
                        upgradePlan: currentPlan,
                        detailInfo: currentDetailInfo,
                        renderedLines: &renderedLines
                    )
                }
                if let detailProvider {
                    currentDetailInfo = await detailProvider.detail(for: allItems[selectedIndex])
                    renderDetail(
                        item: allItems[selectedIndex],
                        upgradePlan: currentPlan,
                        detailInfo: currentDetailInfo,
                        renderedLines: &renderedLines
                    )
                }
            case .printable(let char) where showingDetail && !showingUpgradeResult && char.lowercased() == "u":
                guard selectedIndex >= 0,
                      selectedIndex < allItems.count,
                      let plan = currentPlan,
                      AppArchitectureFormatter.canExecuteUpgrade(plan: plan),
                      let upgradeExecutor
                else {
                    break
                }
                let item = allItems[selectedIndex]
                renderUpgradeConfirmation(
                    item: item,
                    plan: plan,
                    renderedLines: &renderedLines
                )
                guard let confirmation = reader.readNext() else {
                    return cancel()
                }
                switch confirmation {
                case .printable(let value) where value.lowercased() == "y":
                    renderUpgradeRunning(
                        item: item,
                        plan: plan,
                        renderedLines: &renderedLines
                    )
                    let progressDisplay = AppArchitectureUpgradeProgressDisplay(
                        writeOutput: writeOutput,
                        terminalWidth: terminalWidth,
                        initialRenderedLines: renderedLines,
                        item: item,
                        plan: plan
                    )
                    let executionResult = await upgradeExecutor.execute(plan: plan) { progress in
                        progressDisplay.record(progress)
                    }
                    renderedLines = progressDisplay.currentRenderedLines()
                    let after = await postUpgradeScanner?.rescan(item: item)
                    renderUpgradeResult(
                        item: item,
                        before: item,
                        after: after,
                        result: executionResult,
                        renderedLines: &renderedLines
                    )
                    showingUpgradeResult = true
                    shouldRescanListOnReturn = executionResult.isSucceeded
                case .escape, .ctrl("c"), .eof:
                    return cancel()
                default:
                    showingUpgradeResult = false
                    renderDetail(
                        item: item,
                        upgradePlan: currentPlan,
                        detailInfo: currentDetailInfo,
                        renderedLines: &renderedLines
                    )
                }
            case .enter where showingDetail && !showingUpgradeResult:
                guard selectedIndex >= 0, selectedIndex < allItems.count else {
                    return cancel()
                }
                let item = allItems[selectedIndex]
                guard AppArchitectureFormatter.canRequestAppUninstall(for: item) else {
                    break
                }
                writeOutput("\r\n")
                return .requestAppUninstall(item)
            case .left where showingDetail:
                let previousItem = selectedIndex >= 0 && selectedIndex < allItems.count ? allItems[selectedIndex] : nil
                if shouldRescanListOnReturn {
                    if let refreshed = await refreshList(
                        currentResult: currentResult,
                        previousItem: previousItem,
                        previousIndex: selectedIndex
                    ) {
                        currentResult = refreshed.result
                        allItems = refreshed.items
                        selectedIndex = refreshed.selectedIndex
                        startIndex = normalizedStartIndex(for: selectedIndex, currentStartIndex: startIndex, total: allItems.count, pageSize: pageSize)
                    }
                    shouldRescanListOnReturn = false
                }
                showingDetail = false
                showingUpgradeResult = false
                renderList(result: currentResult, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)
            case .printable(let char) where showingDetail && char.lowercased() == "b":
                let previousItem = selectedIndex >= 0 && selectedIndex < allItems.count ? allItems[selectedIndex] : nil
                if shouldRescanListOnReturn {
                    if let refreshed = await refreshList(
                        currentResult: currentResult,
                        previousItem: previousItem,
                        previousIndex: selectedIndex
                    ) {
                        currentResult = refreshed.result
                        allItems = refreshed.items
                        selectedIndex = refreshed.selectedIndex
                        startIndex = normalizedStartIndex(for: selectedIndex, currentStartIndex: startIndex, total: allItems.count, pageSize: pageSize)
                    }
                    shouldRescanListOnReturn = false
                }
                showingDetail = false
                showingUpgradeResult = false
                renderList(result: currentResult, selectedIndex: selectedIndex, startIndex: startIndex, renderedLines: &renderedLines)
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

    private func refreshList(
        currentResult: AppArchitectureScanResult,
        previousItem: AppArchitectureItem?,
        previousIndex: Int
    ) async -> (result: AppArchitectureScanResult, items: [AppArchitectureItem], selectedIndex: Int)? {
        guard let listScanner else { return nil }
        let scanned = await listScanner.scan(options: currentResult.options)
        let refreshed = AppArchitectureScanResult(
            options: currentResult.options,
            items: scanned.items,
            warnings: scanned.warnings
        )
        let items = refreshed.visibleItems()
        return (
            refreshed,
            items,
            selectedIndexAfterRefresh(previousItem: previousItem, previousIndex: previousIndex, items: items)
        )
    }

    private func selectedIndexAfterRefresh(
        previousItem: AppArchitectureItem?,
        previousIndex: Int,
        items: [AppArchitectureItem]
    ) -> Int {
        guard !items.isEmpty else { return -1 }
        if let previousItem,
           let matchingIndex = items.firstIndex(where: { candidate in
               candidate.name == previousItem.name && candidate.source == previousItem.source
           })
        {
            return matchingIndex
        }
        return min(max(previousIndex, 0), items.count - 1)
    }

    private func normalizedStartIndex(
        for selectedIndex: Int,
        currentStartIndex: Int,
        total: Int,
        pageSize: Int
    ) -> Int {
        guard selectedIndex >= 0, total > 0 else { return 0 }
        let lastStart = max(0, total - pageSize)
        if selectedIndex < currentStartIndex {
            return selectedIndex
        }
        if selectedIndex >= currentStartIndex + pageSize {
            return min(lastStart, selectedIndex - pageSize + 1)
        }
        return min(max(0, currentStartIndex), lastStart)
    }

    private func renderDetail(
        item: AppArchitectureItem,
        upgradePlan: AppArchitectureUpgradePlan?,
        detailInfo: AppArchitectureDetailInfo,
        renderedLines: inout Int
    ) {
        let rendered = AppArchitectureFormatter.renderDetail(
            item,
            upgradePlan: upgradePlan,
            detailInfo: detailInfo,
            terminalWidth: terminalWidth
        )
        replaceRenderedContent(with: rendered, renderedLines: &renderedLines)
    }

    private func renderUpgradeConfirmation(
        item: AppArchitectureItem,
        plan: AppArchitectureUpgradePlan,
        renderedLines: inout Int
    ) {
        let rendered = AppArchitectureFormatter.renderUpgradeConfirmation(
            item: item,
            plan: plan,
            terminalWidth: terminalWidth
        )
        replaceRenderedContent(with: rendered, renderedLines: &renderedLines)
    }

    private func renderUpgradeRunning(
        item: AppArchitectureItem,
        plan: AppArchitectureUpgradePlan,
        renderedLines: inout Int
    ) {
        let rendered = AppArchitectureFormatter.renderUpgradeRunning(
            item: item,
            plan: plan,
            terminalWidth: terminalWidth
        )
        replaceRenderedContent(with: rendered, renderedLines: &renderedLines)
    }

    private func renderUpgradeResult(
        item: AppArchitectureItem,
        before: AppArchitectureItem,
        after: AppArchitectureItem?,
        result: AppArchitectureUpgradeExecutionResult,
        renderedLines: inout Int
    ) {
        let rendered = AppArchitectureFormatter.renderUpgradeResult(
            item: item,
            before: before,
            after: after,
            result: result,
            terminalWidth: terminalWidth
        )
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

private final class AppArchitectureUpgradeProgressDisplay: @unchecked Sendable {
    private let lock = NSLock()
    private let writeOutput: (String) -> Void
    private let terminalWidth: Int
    private let item: AppArchitectureItem
    private let plan: AppArchitectureUpgradePlan
    private let startedAt: Date
    private var renderedLines: Int
    private var recentOutputLines: [String] = []

    init(
        writeOutput: @escaping (String) -> Void,
        terminalWidth: Int,
        initialRenderedLines: Int,
        item: AppArchitectureItem,
        plan: AppArchitectureUpgradePlan
    ) {
        self.writeOutput = writeOutput
        self.terminalWidth = terminalWidth
        self.renderedLines = initialRenderedLines
        self.item = item
        self.plan = plan
        startedAt = Date()
    }

    func record(_ progress: AppArchitectureUpgradeProgress) {
        let newLines = Self.progressLines(from: progress)
        guard !newLines.isEmpty else { return }

        lock.lock()
        recentOutputLines.append(contentsOf: newLines)
        if recentOutputLines.count > 6 {
            recentOutputLines = Array(recentOutputLines.suffix(6))
        }
        let rendered = AppArchitectureFormatter.renderUpgradeRunning(
            item: item,
            plan: plan,
            elapsedSeconds: Date().timeIntervalSince(startedAt),
            recentOutputLines: recentOutputLines,
            terminalWidth: terminalWidth
        )
        replaceRenderedContent(with: rendered)
        lock.unlock()
    }

    func currentRenderedLines() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return renderedLines
    }

    private func replaceRenderedContent(with rendered: String) {
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

    private static func progressLines(from progress: AppArchitectureUpgradeProgress) -> [String] {
        let prefix = progress.stream == .stderr ? "stderr" : "stdout"
        return progress.text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "\(prefix): \($0)" }
    }
}

private extension AppArchitectureUpgradeExecutionResult {
    var isSucceeded: Bool {
        guard case .succeeded = status else { return false }
        return true
    }
}
