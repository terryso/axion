import Foundation
import Testing
@testable import AxionCLI

private final class LinesCollector {
    var lines: [String] = []
}

@Suite("TerminalOutputImplementation")
struct TerminalOutputImplementationTests {

    private func makeOutput() -> (TerminalOutput, LinesCollector) {
        let collector = LinesCollector()
        let output = TerminalOutput(write: { collector.lines.append($0) })
        return (output, collector)
    }

    @Test("displayRunStart prints mode runId task")
    func displayRunStartPrintsModeRunIdTask() {
        let (output, collector) = makeOutput()
        output.displayRunStart(runId: "r1", task: "Open Calc", mode: "standard")
        #expect(collector.lines.contains(where: { $0.contains("standard") }))
        #expect(collector.lines.contains(where: { $0.contains("r1") }))
        #expect(collector.lines.contains(where: { $0.contains("Open Calc") }))
    }

    @Test("writeStream does not crash")
    func writeStreamDoesNotCrash() {
        let output = TerminalOutput(write: { _ in })
        output.writeStream("hello")
    }

    @Test("endStream does not crash")
    func endStreamDoesNotCrash() {
        let output = TerminalOutput(write: { _ in })
        output.endStream()
    }

    @Test("all lines have [axion] prefix")
    func allLinesHaveAxionPrefix() {
        let (output, collector) = makeOutput()
        output.displayRunStart(runId: "r1", task: "test", mode: "standard")
        for line in collector.lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            #expect(line.contains("[axion]"))
        }
    }
}

@Suite("JSONOutputImplementation")
struct JSONOutputImplementationTests {

    private func makeOutput() -> JSONOutput {
        JSONOutput()
    }

    @Test("displayRunStart stores data")
    func displayRunStartStoresData() {
        let output = makeOutput()
        output.displayRunStart(runId: "r1", task: "Open Calc", mode: "standard")
        let json = output.finalize()
        #expect(json.contains("r1"))
        #expect(json.contains("Open Calc"))
        #expect(json.contains("standard"))
    }

    @Test("finalize produces valid JSON with required fields")
    func finalizeProducesValidJSON() {
        let output = makeOutput()
        output.displayRunStart(runId: "r1", task: "t", mode: "m")
        let json = output.finalize()
        let data = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed != nil)
        #expect(parsed?["runId"] != nil)
        #expect(parsed?["task"] != nil)
        #expect(parsed?["mode"] != nil)
        #expect(parsed?["state"] != nil)
    }
}
