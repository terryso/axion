import Foundation
import Testing
@testable import AxionCLI

@Suite("TerminalOutput")
struct TerminalOutputTests {

    @Test("type exists")
    func terminalOutputTypeExists() {
        let _ = TerminalOutput.self
    }

    @Test("displayRunStart shows runId and task")
    func terminalOutputDisplayRunStartShowsRunIdAndTask() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        let hasRunId = captured.contains { $0.contains("20260510-abc123") }
        #expect(hasRunId)

        let hasTask = captured.contains { $0.contains("Open Calculator") }
        #expect(hasTask)
    }

    @Test("displayRunStart outputs at least 3 lines")
    func terminalOutputDisplayRunStartAllThreeLines() {
        var captured: [String] = []
        let output = TerminalOutput { captured.append($0) }

        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        #expect(captured.count >= 3)

        let hasMode = captured.contains { $0.contains("plan_execute") || $0.lowercased().contains("mode") || $0.contains("模式") }
        #expect(hasMode)
    }

    @Test("all outputs have [axion] prefix")
    func terminalOutputAllOutputsHaveAxionPrefix() {
        var allOutput: [String] = []
        let output = TerminalOutput { allOutput.append($0) }

        output.displayRunStart(runId: "test-id", task: "task", mode: "mode")

        for line in allOutput where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            #expect(line.contains("[axion]"))
        }
    }

    @Test("no emoji in output")
    func terminalOutputNoEmojiInOutput() {
        var allOutput: [String] = []
        let output = TerminalOutput { allOutput.append($0) }

        output.displayRunStart(runId: "test-id", task: "task", mode: "mode")

        let combined = allOutput.joined()
        let hasEmoji = combined.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (v >= 0x1F600 && v <= 0x1F64F) ||
                   (v >= 0x1F300 && v <= 0x1F5FF) ||
                   (v >= 0x1F680 && v <= 0x1F6FF) ||
                   (v >= 0x1F1E0 && v <= 0x1F1FF) ||
                   (v >= 0x2600 && v <= 0x26FF) ||
                   (v >= 0x2700 && v <= 0x27BF)
        }
        #expect(!hasEmoji)
    }

    @Test("writeStream outputs without newline")
    func terminalOutputWriteStream() {
        let output = TerminalOutput()
        // writeStream prints without trailing newline — just verify it doesn't crash
        output.writeStream("test")
        output.endStream()
    }
}
