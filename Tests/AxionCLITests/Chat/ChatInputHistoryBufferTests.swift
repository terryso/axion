import Testing

@testable import AxionCLI

@Suite("ChatInputHistoryBuffer")
struct ChatInputHistoryBufferTests {
    @Test("records raw slash input in current REPL history")
    func recordsRawSlashInputInCurrentHistory() {
        var buffer = ChatInputHistoryBuffer()

        buffer.record("/arch --packages-only")

        #expect(buffer.entries == ["/arch --packages-only"])
        #expect(buffer.merged(with: ["previous"]) == ["previous", "/arch --packages-only"])
    }

    @Test("generated task text does not replace raw slash history")
    func generatedTaskTextDoesNotReplaceRawSlashHistory() {
        var buffer = ChatInputHistoryBuffer()

        buffer.record("/storage large ~/Downloads")

        #expect(!buffer.entries.contains("请扫描 Downloads 中的大文件"))
        #expect(buffer.merged(with: []).last == "/storage large ~/Downloads")
    }
}
