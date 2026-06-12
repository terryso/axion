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

    @Test("enter opens detail before selecting app")
    func enterOpensDetailBeforeSelecting() {
        let output = OutputCapture()
        let prompt = AppSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.down, .enter, .escape]),
            writeOutput: { output.write($0) }
        )

        let selected = prompt.run(result: result([
            item("Slack", bundleId: "com.example.slack"),
            item("Zoom", bundleId: "us.zoom.xos"),
        ]))

        #expect(selected == .cancelled)
        #expect(output.text.contains("App 详情"))
        #expect(output.text.contains("Zoom"))
        #expect(output.text.contains("Bundle ID: us.zoom.xos"))
        #expect(output.text.contains("Enter 继续卸载流程"))
    }

    @Test("enter on detail selects app")
    func enterOnDetailSelectsApp() {
        let output = OutputCapture()
        let prompt = AppSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.down, .enter, .enter]),
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

    @Test("down past first page scrolls window and selects twenty first app")
    func downPastFirstPageSelectsTwentyFirst() {
        let output = OutputCapture()
        let events = Array(repeating: KeyEvent.down, count: 20) + [.enter, .enter]
        let prompt = AppSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader(events),
            writeOutput: { output.write($0) },
            maxItems: 20
        )
        let items = (1...25).map { index in
            item("App \(index)", bundleId: "com.example.app\(index)")
        }

        let selected = prompt.run(result: result(items))

        #expect(selected == .selected(item("App 21", bundleId: "com.example.app21")))
        #expect(output.text.contains("App 21"))
        #expect(output.text.contains("显示 2-21 / 25"))
    }

    @Test("b returns from detail to list")
    func bReturnsFromDetailToList() {
        let output = OutputCapture()
        let prompt = AppSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .printable("b"), .down, .enter, .enter]),
            writeOutput: { output.write($0) }
        )

        let selected = prompt.run(result: result([
            item("Slack", bundleId: "com.example.slack"),
            item("Zoom", bundleId: "us.zoom.xos"),
        ]))

        #expect(selected == .selected(item("Zoom", bundleId: "us.zoom.xos")))
        #expect(output.text.contains("Enter 详情"))
        #expect(output.text.contains("App 详情"))
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
