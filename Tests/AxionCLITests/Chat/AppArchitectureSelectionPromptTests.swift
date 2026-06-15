import Testing

@testable import AxionCLI

@Suite("App Architecture Selection Prompt")
struct AppArchitectureSelectionPromptTests {
    private final class OutputCapture {
        var text = ""
        func write(_ value: String) {
            text += value
        }
    }

    private func item(
        _ name: String,
        path: String? = nil,
        architectures: Set<AppBinaryArchitecture> = [.x86_64],
        source: AppArchitectureSource = .application
    ) -> AppArchitectureItem {
        let displayPath = path ?? "/Applications/\(name).app"
        return AppArchitectureItem(
            name: name,
            displayPath: displayPath,
            executablePath: displayPath + "/Contents/MacOS/\(name)",
            architectures: architectures,
            isSystemApp: false,
            source: source
        )
    }

    private func result(_ items: [AppArchitectureItem]) -> AppArchitectureScanResult {
        AppArchitectureScanResult(
            options: AppArchitectureScanOptions(includeAllArchitectures: false, limit: 80),
            items: items,
            warnings: []
        )
    }

    @Test("enter opens architecture detail")
    func enterOpensDetail() {
        let output = OutputCapture()
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.down, .enter, .escape]),
            writeOutput: { output.write($0) }
        )

        #expect(prompt.run(result: result([
            item("Slack"),
            item("Zoom", path: "/Applications/Zoom.app"),
        ])) == .cancelled)
        #expect(output.text.contains("软件架构候选"))
        #expect(output.text.contains("架构详情"))
        #expect(output.text.contains("Zoom"))
        #expect(output.text.contains("可执行文件"))
        #expect(output.text.contains("b 返回列表"))
    }

    @Test("b returns from detail to architecture list")
    func bReturnsFromDetailToList() {
        let output = OutputCapture()
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .printable("b"), .down, .enter, .escape]),
            writeOutput: { output.write($0) }
        )

        #expect(prompt.run(result: result([
            item("Slack"),
            item("Zoom"),
        ])) == .cancelled)
        #expect(output.text.contains("架构详情"))
        #expect(output.text.contains("▶ Zoom"))
    }

    @Test("down past first page scrolls architecture list")
    func downPastFirstPageScrollsList() {
        let output = OutputCapture()
        let events = Array(repeating: KeyEvent.down, count: 20) + [.enter, .escape]
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader(events),
            writeOutput: { output.write($0) },
            maxItems: 20
        )
        let items = (1...25).map { index in
            item("Tool \(index)", path: "/opt/homebrew/Cellar/tool\(index)/bin/tool\(index)", source: .homebrew)
        }

        #expect(prompt.run(result: result(items)) == .cancelled)
        #expect(output.text.contains("Tool 21"))
        #expect(output.text.contains("显示 2-21 / 25"))
    }

    @Test("non-TTY renders numbered list")
    func nonTTYListOnly() {
        let output = OutputCapture()
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: false,
            keyReader: nil,
            writeOutput: { output.write($0) }
        )

        #expect(prompt.run(result: result([item("Slack")])) == .nonTTYListOnly)
        #expect(output.text.contains("1."))
        #expect(output.text.contains("Slack"))
        #expect(output.text.contains("非交互模式"))
        #expect(!output.text.contains("↑/↓"))
    }
}
