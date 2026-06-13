import Testing

@testable import AxionCLI

@Suite("MCP Selection Prompt")
struct MCPSelectionPromptTests {
    private final class OutputCapture {
        var text = ""
        func write(_ value: String) {
            text += value
        }
    }

    private func entry(_ name: String) -> MCPStatusEntry {
        MCPStatusEntry(
            name: name,
            type: "stdio",
            source: "config",
            state: "ready",
            details: [
                "command: npx -y \(name)",
                "env: TOKEN=<redacted>",
            ]
        )
    }

    @Test("down past first page opens detail for sixteenth server")
    func downPastFirstPageOpensDetail() {
        let output = OutputCapture()
        let events = Array(repeating: KeyEvent.down, count: 15) + [.enter, .escape]
        let prompt = MCPSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader(events),
            writeOutput: { output.write($0) },
            maxItems: 15,
            terminalWidth: 100
        )
        let result = prompt.run(entries: (1...20).map { entry("server-\($0)") })

        #expect(result == .cancelled)
        #expect(output.text.contains("显示 2-16 / 20"))
        #expect(output.text.contains("MCP server 详情"))
        #expect(output.text.contains("名称: server-16"))
        #expect(output.text.contains("command: npx -y server-16"))
    }

    @Test("b returns from detail to list")
    func bReturnsFromDetailToList() {
        let output = OutputCapture()
        let prompt = MCPSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .printable("b"), .down, .enter, .escape]),
            writeOutput: { output.write($0) },
            maxItems: 15,
            terminalWidth: 100
        )
        let result = prompt.run(entries: [entry("server-1"), entry("server-2")])

        #expect(result == .cancelled)
        #expect(output.text.contains("Enter 详情"))
        #expect(output.text.contains("MCP server 详情"))
        #expect(output.text.contains("名称: server-2"))
    }

    @Test("q cancels prompt")
    func qCancelsPrompt() {
        let output = OutputCapture()
        let prompt = MCPSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.printable("q")]),
            writeOutput: { output.write($0) },
            terminalWidth: 100
        )

        #expect(prompt.run(entries: [entry("server-1")]) == .cancelled)
        #expect(output.text.contains("server-1"))
        #expect(output.text.hasSuffix("\r\n"))
    }

    @Test("non-TTY renders numbered list")
    func nonTTYRendersNumberedList() {
        let output = OutputCapture()
        let prompt = MCPSelectionPrompt(
            isTTY: false,
            keyReader: nil,
            writeOutput: { output.write($0) },
            maxItems: 2,
            terminalWidth: 100
        )

        #expect(prompt.run(entries: [entry("server-1"), entry("server-2"), entry("server-3")]) == .nonTTYListOnly)
        #expect(output.text.contains("1. server-1"))
        #expect(output.text.contains("2. server-2"))
        #expect(!output.text.contains("server-3"))
        #expect(output.text.contains("使用 /mcp --all 查看完整配置"))
        #expect(output.text.contains("非交互模式"))
        #expect(!output.text.contains("↑/↓"))
    }
}
