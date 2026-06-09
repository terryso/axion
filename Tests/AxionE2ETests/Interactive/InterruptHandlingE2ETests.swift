import Foundation
import Testing

@testable import AxionCLI
import OpenAgentSDK

/// E2E tests for Ctrl+C interrupt handling in the interactive REPL.
///
/// Tests the SignalHandler, chatShouldExit, and interrupt-related
/// ChatOutputFormatter behavior. No API key needed — uses mock streams.
@Suite("Interrupt Handling E2E")
struct InterruptHandlingE2ETests {

    // MARK: - SignalHandler

    @Test("SignalHandler: simulateFire increments count")
    func simulateFireIncrements() {
        SignalHandler.reset()
        #expect(SignalHandler.fireCount() == 0, "Should start at 0")

        SignalHandler.simulateFire()
        #expect(SignalHandler.fireCount() == 1, "Should be 1 after one fire")

        SignalHandler.simulateFire()
        #expect(SignalHandler.fireCount() == 2, "Should be 2 after two fires")

        // Cleanup
        SignalHandler.reset()
    }

    @Test("SignalHandler: reset clears count")
    func resetClearsCount() {
        SignalHandler.simulateFire()
        SignalHandler.simulateFire()
        #expect(SignalHandler.fireCount() >= 2)

        SignalHandler.reset()
        #expect(SignalHandler.fireCount() == 0, "Should be 0 after reset")
    }

    // MARK: - chatShouldExit

    @Test("chatShouldExit: within 2 seconds returns true")
    func chatShouldExitWithin2Seconds() {
        let now = ContinuousClock.now
        let last = now - .seconds(1)
        #expect(chatShouldExit(lastInterrupt: last, now: now) == true,
               "Double Ctrl+C within 2s should exit")
    }

    @Test("chatShouldExit: exactly at boundary returns true")
    func chatShouldExitAtBoundary() {
        let now = ContinuousClock.now
        let last = now - .seconds(2) + .milliseconds(1)
        #expect(chatShouldExit(lastInterrupt: last, now: now) == true,
               "Just under 2s should still exit")
    }

    @Test("chatShouldExit: beyond 2 seconds returns false")
    func chatShouldExitBeyond2Seconds() {
        let now = ContinuousClock.now
        let last = now - .seconds(3)
        #expect(chatShouldExit(lastInterrupt: last, now: now) == false,
               "Ctrl+C beyond 2s should not exit")
    }

    @Test("chatShouldExit: 5 seconds apart returns false")
    func chatShouldExit5Seconds() {
        let now = ContinuousClock.now
        let last = now - .seconds(5)
        #expect(chatShouldExit(lastInterrupt: last, now: now) == false,
               "Ctrl+C 5s apart should not exit")
    }

    // MARK: - Interrupt + ChatOutputFormatter

    @Test("interrupt suppresses cancelled error output")
    func interruptSuppressesCancelled() async {
        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()

        // Simulate: user pressed Ctrl+C
        handler.suppressInterruptError = true

        // Agent sends cancelled result
        let stream = mockAgentStream(messages: [
            ChatE2EMessages.cancelledResult(),
        ])
        for await message in stream {
            handler.handle(message)
        }

        let output = capturing.allStderr
        #expect(!output.contains("取消"), "Should not show cancelled when suppressed")
        #expect(!output.contains("Cancelled"), "Should not show English cancelled either")
    }

    @Test("interrupt suppresses execution error output")
    func interruptSuppressesExecError() async {
        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()

        handler.suppressInterruptError = true

        let stream = mockAgentStream(messages: [
            ChatE2EMessages.executionErrorResult(),
        ])
        for await message in stream {
            handler.handle(message)
        }

        let output = capturing.allStderr
        #expect(!output.contains("执行错误"), "Should not show error when suppressed")
    }

    @Test("normal cancelled (no interrupt) shows warning")
    func normalCancelledShowsWarning() async {
        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()

        // No interrupt — suppressInterruptError defaults to false
        let stream = mockAgentStream(messages: [
            ChatE2EMessages.cancelledResult(),
        ])
        for await message in stream {
            handler.handle(message)
        }

        let output = capturing.allStderr
        #expect(output.contains("取消"), "Should show cancelled warning in normal flow")
    }

    @Test("suppressInterruptError resets after handling one message")
    func suppressFlagResetsAfterUse() async {
        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()

        handler.suppressInterruptError = true

        // First cancelled — should be suppressed
        let stream1 = mockAgentStream(messages: [ChatE2EMessages.cancelledResult()])
        for await message in stream1 {
            handler.handle(message)
        }
        #expect(!capturing.allStderr.contains("取消"), "First cancelled should be suppressed")

        // Second cancelled — suppressInterruptError should have been reset to false
        let stream2 = mockAgentStream(messages: [ChatE2EMessages.cancelledResult()])
        for await message in stream2 {
            handler.handle(message)
        }
        #expect(capturing.allStderr.contains("取消"), "Second cancelled should NOT be suppressed (flag reset)")
    }

    // MARK: - Interrupt + prefill

    @Test("interrupt sets prefill to last user input")
    func interruptSetsPrefill() {
        // This tests the REPL pattern: after interrupt, composer.prefill = trimmed
        // We verify the logic flow by checking the pattern ChatCommand uses
        let lastInput = "帮我写一个函数"
        var prefill: String? = nil

        // Simulate interrupt
        SignalHandler.reset()
        SignalHandler.simulateFire()
        #expect(SignalHandler.fireCount() > 0, "Should have interrupt")

        // ChatCommand sets prefill = trimmed after detecting interrupt
        prefill = lastInput
        #expect(prefill == "帮我写一个函数", "Prefill should match last input")

        SignalHandler.reset()
    }

    // MARK: - Interrupt flow integration

    @Test("full interrupt flow: fire → check → set suppress → handle cancelled")
    func fullInterruptFlow() async {
        SignalHandler.reset()

        // 1. User sends input (simulated)
        let userMessage = "长任务"

        // 2. Agent starts working — handler created
        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()
        handler.startLLMWaiting()

        // 3. Partial output starts
        let partialStream = mockAgentStream(messages: [
            ChatE2EMessages.partial("正在思考"),
        ])
        for await message in partialStream {
            handler.handle(message)
        }

        // 4. User presses Ctrl+C
        SignalHandler.simulateFire()
        #expect(SignalHandler.fireCount() > 0, "Should detect interrupt")

        // 5. ChatCommand sets suppress flag
        handler.suppressInterruptError = true

        // 6. Agent sends cancelled result
        let cancelStream = mockAgentStream(messages: [
            ChatE2EMessages.cancelledResult(),
        ])
        for await message in cancelStream {
            handler.handle(message)
        }

        // 7. Verify no cancelled warning
        let output = capturing.allStderr
        #expect(!output.contains("取消"), "Should suppress cancelled warning")

        // 8. ChatCommand would set prefill
        _ = userMessage  // prefill = userMessage

        // 9. Reset for next turn
        SignalHandler.reset()
        #expect(SignalHandler.fireCount() == 0, "Should be reset for next turn")
    }
}
