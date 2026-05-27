import ArgumentParser
import AxionCore
import Foundation

struct SessionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sessions",
        abstract: "List all historical agent sessions"
    )

    nonisolated(unsafe) static var createLister: @Sendable () -> any SessionListing = { AxionRuntime() }

    @Flag(name: .long, help: "Show only active (running) sessions")
    var active: Bool = false

    @Option(name: .long, help: "Maximum number of sessions to display (default: 20)")
    var limit: Int = 20

    func validate() throws {
        guard limit > 0 else {
            throw ValidationError("--limit must be greater than 0")
        }
    }

    func run() async throws {
        let lister = Self.createLister()
        var sessions = try await lister.listSessions(limit: nil)

        if active {
            sessions = Self.filterActive(sessions)
        }

        sessions = Self.sortByMostRecent(sessions)
        sessions = Self.applyLimit(sessions, limit: limit)

        let output = Self.renderTable(sessions)
        print(output)
    }

    // MARK: - Public Static API (for testing)

    static func filterActive(_ sessions: [SessionInfo]) -> [SessionInfo] {
        sessions.filter { $0.status == "running" }
    }

    static func applyLimit(_ sessions: [SessionInfo], limit: Int) -> [SessionInfo] {
        Array(sessions.prefix(limit))
    }

    static func sortByMostRecent(_ sessions: [SessionInfo]) -> [SessionInfo] {
        sessions.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (l?, r?): return l > r
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    static func renderTable(_ sessions: [SessionInfo]) -> String {
        guard !sessions.isEmpty else {
            return "No sessions found"
        }

        let header = pad("SESSION", to: 12) + pad("TASK", to: 30) + pad("STATUS", to: 12) + pad("STEPS", to: 6) + pad("DURATION", to: 10) + "CREATED"

        var lines = [header]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        for session in sessions {
            let sessionId = truncate(session.sessionId, maxLength: 8)
            let task = truncate(session.summary ?? "-", maxLength: 27)
            let status = session.status
            let steps = "\(session.totalSteps)"
            let duration = formatDuration(session.durationMs)
            let created = session.createdAt.map { dateFormatter.string(from: $0) } ?? "-"

            let line = pad(sessionId, to: 12) + pad(task, to: 30) + pad(status, to: 12) + pad(steps, to: 6) + pad(duration, to: 10) + created
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private static func pad(_ string: String, to width: Int) -> String {
        if string.count >= width {
            return string
        }
        return string + String(repeating: " ", count: width - string.count)
    }

    private static func truncate(_ string: String, maxLength: Int) -> String {
        if string.count > maxLength {
            return String(string.prefix(maxLength)) + "..."
        }
        return string
    }

    private static func formatDuration(_ ms: Int?) -> String {
        guard let ms else { return "-" }
        let totalSeconds = ms / 1000
        if totalSeconds < 60 {
            return totalSeconds == 0 ? "<1s" : "\(totalSeconds)s"
        }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes)m \(seconds)s"
    }
}
