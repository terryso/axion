import Foundation
import Testing

@testable import AxionCLI

@Suite("App Selection Prompt")
struct AppSelectionPromptTests {
    private final class OutputCapture {
        var text = ""
        func write(_ value: String) {
            text += value
        }
    }

    private func item(_ name: String, bundleId: String = "com.example.app") -> AppListItem {
        AppListItem(
            displayName: name,
            bundleIdentifier: bundleId,
            bundlePath: "/Applications/\(name).app",
            version: "1.0",
            sizeBytes: 1024,
            isRunning: false,
            isSystemProtected: false,
            source: .applications
        )
    }

    private func result(_ items: [AppListItem], deepAvailable: Bool = true) -> AppListResult {
        AppListResult(
            scope: .fast,
            filter: nil,
            candidates: items,
            protectedMatches: [],
            warnings: [],
            deepSearchAvailable: deepAvailable
        )
    }

    @Test("down then enter selects second app")
    func downThenEnterSelectsSecond() {
        let output = OutputCapture()
        let prompt = AppSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.down, .enter]),
            writeOutput: { output.write($0) }
        )

        let selected = prompt.run(result: result([
            item("Slack", bundleId: "com.example.slack"),
            item("Zoom", bundleId: "us.zoom.xos"),
        ]))

        #expect(selected == .selected(item("Zoom", bundleId: "us.zoom.xos")))
        #expect(output.text.contains("↑/↓"))
        #expect(output.text.contains("\u{1B}["))
        #expect(output.text.contains("\r\n"))
    }

    @Test("escape cancels selection")
    func escapeCancels() {
        let output = OutputCapture()
        let prompt = AppSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.escape]),
            writeOutput: { output.write($0) }
        )

        #expect(prompt.run(result: result([item("Slack")])) == .cancelled)
    }

    @Test("a requests deep search when available")
    func aRequestsDeepSearch() {
        let output = OutputCapture()
        let prompt = AppSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.printable("a")]),
            writeOutput: { output.write($0) }
        )

        #expect(prompt.run(result: result([item("Slack")], deepAvailable: true)) == .requestDeepSearch)
    }

    @Test("a is ignored when deep search unavailable")
    func aIgnoredWhenDeepUnavailable() {
        let output = OutputCapture()
        let prompt = AppSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.printable("a"), .escape]),
            writeOutput: { output.write($0) }
        )

        #expect(prompt.run(result: result([item("Slack")], deepAvailable: false)) == .cancelled)
    }

    @Test("non-TTY renders list and returns nonTTYListOnly")
    func nonTTYListOnly() {
        let output = OutputCapture()
        let prompt = AppSelectionPrompt(
            isTTY: false,
            keyReader: nil,
            writeOutput: { output.write($0) }
        )

        #expect(prompt.run(result: result([item("Slack")])) == .nonTTYListOnly)
        #expect(output.text.contains("Slack"))
        #expect(output.text.contains("1."))
        #expect(output.text.contains("非交互模式"))
        #expect(!output.text.contains("↑/↓"))
    }
}
