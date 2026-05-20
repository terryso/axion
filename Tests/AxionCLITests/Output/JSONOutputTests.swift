import Foundation
import Testing
@testable import AxionCLI

@Suite("JSONOutput")
struct JSONOutputTests {

    @Test("type exists")
    func jsonOutputTypeExists() {
        let _ = JSONOutput.self
    }

    @Test("finalize produces valid JSON")
    func jsonOutputFinalizeProducesValidJSON() {
        let output = JSONOutput()
        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        let json = output.finalize()

        let jsonData = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: jsonData)
        #expect(parsed != nil)
    }

    @Test("finalize contains runId")
    func jsonOutputFinalizeContainsRunId() {
        let output = JSONOutput()
        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        let json = output.finalize()
        let dict = parseJSON(json)

        #expect(dict?["runId"] as? String == "20260510-abc123")
    }

    @Test("finalize contains task")
    func jsonOutputFinalizeContainsTask() {
        let output = JSONOutput()
        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        let json = output.finalize()
        let dict = parseJSON(json)

        #expect(dict?["task"] as? String == "Open Calculator")
    }

    @Test("finalize contains state done")
    func jsonOutputFinalizeContainsStateDone() {
        let output = JSONOutput()
        output.displayRunStart(runId: "test", task: "test", mode: "test")

        let json = output.finalize()
        let dict = parseJSON(json)

        #expect(dict?["state"] as? String == "done")
    }

    @Test("displayRunStart stores run info")
    func jsonOutputDisplayRunStartStoresRunInfo() {
        let output = JSONOutput()
        output.displayRunStart(runId: "20260510-xyz789", task: "Calculate 17*23", mode: "plan_execute")

        let json = output.finalize()
        let dict = parseJSON(json)

        #expect(dict?["runId"] as? String == "20260510-xyz789")
        #expect(dict?["task"] as? String == "Calculate 17*23")
        #expect(dict?["mode"] as? String == "plan_execute")
    }

    @Test("finalize without displayRunStart uses empty defaults")
    func jsonOutputFinalizeWithoutDisplayRunStart() {
        let output = JSONOutput()

        let json = output.finalize()
        let dict = parseJSON(json)

        #expect(dict?["runId"] as? String == "")
        #expect(dict?["task"] as? String == "")
        #expect(dict?["mode"] as? String == "")
    }

    private func parseJSON(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
