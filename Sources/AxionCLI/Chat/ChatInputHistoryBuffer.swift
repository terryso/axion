struct ChatInputHistoryBuffer: Equatable, Sendable {
    private(set) var entries: [String] = []

    mutating func record(_ text: String) {
        entries.append(text)
    }

    func merged(with persistentHistory: [String]) -> [String] {
        persistentHistory + entries
    }
}
