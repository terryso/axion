import Foundation
import Testing
@testable import AxionCLI

@Suite("CommandHistoryStore recent slash usage window")
struct CommandHistoryStoreRecentUsageWindowTests {
    final class RecentUsageMockFile: @unchecked Sendable {
        var content: String?
        init(content: String?) {
            self.content = content
        }
    }

    private func makeStore(initialContent: String?) -> CommandHistoryStore {
        let mock = RecentUsageMockFile(content: initialContent)
        return CommandHistoryStore(
            readFile: { _ in mock.content },
            appendFile: { _, line in mock.content = (mock.content ?? "") + line + "\n" },
            writeFile: { _, content in mock.content = content }
        )
    }

    private func makeJSONLine(_ text: String, ts: String) -> String {
        let obj: [String: String] = ["text": text, "ts": ts]
        let data = try! JSONSerialization.data(withJSONObject: obj, options: .sortedKeys)
        return String(data: data, encoding: .utf8)!
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    @Test("P1: usage counts include exact cutoff and exclude old or future entries")
    func recentSlashUsageCountsRespectsSevenDayWindow() {
        let content = [
            makeJSONLine("/help", ts: "2026-06-06T00:00:00Z"),
            makeJSONLine("/help", ts: "2026-06-05T23:59:59Z"),
            makeJSONLine("/cost", ts: "2026-06-13T00:00:01Z"),
            makeJSONLine("/model sonnet", ts: "2026-06-13T00:00:00Z")
        ].joined(separator: "\n")
        let store = makeStore(initialContent: content)

        let result = store.recentSlashUsageCounts(
            filePath: "/dev/null",
            now: date("2026-06-13T00:00:00Z"),
            days: 7
        )

        #expect(result["/help"] == 1)
        #expect(result["/model"] == 1)
        #expect(result["/cost"] == nil)
    }
}
