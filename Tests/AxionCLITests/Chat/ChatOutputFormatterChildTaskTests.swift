import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

// MARK: - ChatOutputFormatter Child-Task (Task/Agent) Wiring Tests (Story 40.8 AC5)
//
// Drives the full ChatOutputFormatter.handle(SDKMessage) pipeline for Task/Agent
// subagent tools to confirm the toolInputs dict is tracked on .toolUse and
// threaded into formatCompleted on .toolResult — surfacing description/command on
// start and error/retry on failure. No real AgentBuilder / SDK agent.stream /
// Helper / MCP: only the pure formatter pipeline fed synthetic SDKMessage values
// (SDKMessage.toolUse / toolResult have public initializers).

@Suite("ChatOutputFormatter Child-Task Wiring")
struct ChatOutputFormatterChildTaskTests {

    /// Builds a ChatOutputFormatter whose stdout is captured into `captured`.
    /// Uses all-default renderers (theme nil → non-TTY formatting path), so no
    /// real terminal I/O occurs.
    private func makeCapturingFormatter() -> (ChatOutputFormatter, () -> String) {
        var captured = ""
        let formatter = ChatOutputFormatter(
            writeStdout: { captured += $0 },
            writeStderr: { _ in }
        )
        return (formatter, { captured })
    }

    @Test("Task toolUse start line shows description + command (AC5/AC2 wiring)")
    func taskStart_showsDescriptionAndCommand() {
        let (formatter, capture) = makeCapturingFormatter()

        formatter.handle(.toolUse(.init(
            toolName: "Task",
            toolUseId: "task-1",
            input: #"{"prompt":"Please run /bmad-create-story 1-1 yolo now","description":"Create story"}"#
        )))

        let output = capture()
        #expect(output.contains("task"))            // .subagent label
        #expect(output.contains("Create story"))    // description surfaced
        #expect(output.contains("/bmad-create-story"))  // command surfaced
    }

    @Test("Task toolResult failure surfaces error + retry command (AC5/AC4 wiring)")
    func taskFailure_surfacesErrorAndRetry() {
        let (formatter, capture) = makeCapturingFormatter()

        formatter.handle(.toolUse(.init(
            toolName: "Task",
            toolUseId: "task-2",
            input: #"{"prompt":"Please run /missing-skill demo","description":"Demo missing"}"#
        )))
        formatter.handle(.toolResult(.init(
            toolUseId: "task-2",
            content: #"Skill "missing-skill" not found or not registered"#,
            isError: true
        )))

        let output = capture()
        #expect(output.contains("✗"))
        #expect(output.contains("failed"))
        #expect(output.contains("not found or not registered"))
        // retry command requires the toolInputs dict to have been threaded through
        #expect(output.contains("retry:"))
        #expect(output.contains("/missing-skill demo"))
    }

    @Test("Task toolResult success surfaces completion status (AC5/AC3 wiring)")
    func taskSuccess_surfacesCompleted() {
        let (formatter, capture) = makeCapturingFormatter()

        formatter.handle(.toolUse(.init(
            toolName: "Task",
            toolUseId: "task-3",
            input: #"{"prompt":"Run /bmad-create-story 1-1 yolo","description":"Create story"}"#
        )))
        formatter.handle(.toolResult(.init(
            toolUseId: "task-3",
            content: "Story draft created and saved.",
            isError: false
        )))

        let output = capture()
        #expect(output.contains("✓"))
        #expect(output.contains("completed"))
        #expect(output.contains("Story draft created"))
    }

    @Test("toolInputs dict is pair-cleared — no cross-turn leakage")
    func toolInputs_clearedAfterResult() {
        let (formatter, capture) = makeCapturingFormatter()

        // First Task step — failure with retry command
        formatter.handle(.toolUse(.init(
            toolName: "Task",
            toolUseId: "task-a",
            input: #"{"prompt":"Run /foo bar","description":"Step A"}"#
        )))
        formatter.handle(.toolResult(.init(
            toolUseId: "task-a",
            content: "failed step A",
            isError: true
        )))
        let firstOutput = capture()

        // Second, unrelated non-subagent tool result arrives with an unknown toolUseId.
        // Because toolInputs was pair-cleared on task-a's result, a stray result for a
        // different id must NOT accidentally pick up task-a's input (no retry line).
        formatter.handle(.toolResult(.init(
            toolUseId: "orphan",
            content: "orphan result",
            isError: true
        )))
        let secondOutput = capture().dropFirst(firstOutput.count)

        #expect(firstOutput.contains("retry:"))       // task-a retry surfaced
        #expect(firstOutput.contains("/foo bar"))
        #expect(!secondOutput.contains("/foo bar"))   // no leakage into orphan result
        #expect(!secondOutput.contains("Step A"))
    }

    @Test("Non-subagent tools are unaffected by the toolInputs wiring")
    func nonSubagentTools_unaffected() {
        let (formatter, capture) = makeCapturingFormatter()

        // A bash tool use/result must render exactly as before 40.8 (no task/retry).
        formatter.handle(.toolUse(.init(
            toolName: "bash",
            toolUseId: "bash-1",
            input: #"{"command":"echo hi"}"#
        )))
        formatter.handle(.toolResult(.init(
            toolUseId: "bash-1",
            content: "hi",
            isError: false
        )))

        let output = capture()
        #expect(output.contains("exec"))      // shell label
        #expect(output.contains("echo hi"))
        #expect(output.contains("✓"))
        #expect(!output.contains("task:"))     // not formatted as subagent
        #expect(!output.contains("retry:"))
    }
}
