import Testing
import Foundation

@testable import AxionCLI

@Suite("TakeoverIO")
struct TakeoverIOTests {

    @Test("TakeoverAction from nil returns resume")
    func takeoverActionResumeFromNil() {
        let action = TakeoverAction.fromInput(nil)
        #expect(action == .resume)
    }

    @Test("TakeoverAction from empty returns resume")
    func takeoverActionResumeFromEmpty() {
        let action = TakeoverAction.fromInput("")
        #expect(action == .resume)
    }

    @Test("TakeoverAction from newline returns resume")
    func takeoverActionResumeFromEnter() {
        let action = TakeoverAction.fromInput("\n")
        #expect(action == .resume)
    }

    @Test("TakeoverAction from 'continue' returns resume")
    func takeoverActionResumeFromContinue() {
        let action = TakeoverAction.fromInput("continue")
        #expect(action == .resume)
    }

    @Test("TakeoverAction from 'skip' returns skip")
    func takeoverActionSkip() {
        let action = TakeoverAction.fromInput("skip")
        #expect(action == .skip)
    }

    @Test("TakeoverAction from 'abort' returns abort")
    func takeoverActionAbort() {
        let action = TakeoverAction.fromInput("abort")
        #expect(action == .abort)
    }

    @Test("TakeoverAction from 'quit' returns abort")
    func takeoverActionAbortFromQuit() {
        let action = TakeoverAction.fromInput("quit")
        #expect(action == .abort)
    }

    @Test("TakeoverAction is case insensitive")
    func takeoverActionCaseInsensitive() {
        #expect(TakeoverAction.fromInput("Skip") == .skip)
        #expect(TakeoverAction.fromInput("ABORT") == .abort)
        #expect(TakeoverAction.fromInput("CONTINUE") == .resume)
    }

    @Test("TakeoverAction whitespace is trimmed")
    func takeoverActionWhitespaceTrimmed() {
        #expect(TakeoverAction.fromInput("  skip  ") == .skip)
        #expect(TakeoverAction.fromInput(" abort ") == .abort)
    }

    @Test("displayTakeoverPrompt outputs reason")
    func displayTakeoverPromptOutputsReason() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "continue" }
        )

        let result = io.displayTakeoverPrompt(
            reason: "无法找到目标按钮",
            allowForeground: false
        )

        #expect(result.action == .resume)
        let combined = output.joined(separator: "\n")
        #expect(combined.contains("无法找到目标按钮"))
    }

    @Test("displayTakeoverPrompt with allowForeground shows hint")
    func displayTakeoverPromptAllowForegroundShowsHint() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "skip" }
        )

        let result = io.displayTakeoverPrompt(
            reason: "受阻",
            allowForeground: true
        )

        #expect(result.action == .skip)
        let combined = output.joined(separator: "\n")
        #expect(combined.contains("前台"))
    }

    @Test("displayTakeoverPrompt without foreground shows no hint")
    func displayTakeoverPromptNoForegroundHintWhenDisabled() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "abort" }
        )

        let _ = io.displayTakeoverPrompt(
            reason: "受阻",
            allowForeground: false
        )

        let combined = output.joined(separator: "\n")
        #expect(!combined.contains("前台"))
    }

    @Test("displayTakeoverPrompt abort action")
    func displayTakeoverPromptAbortAction() {
        let io = TakeoverIO(
            write: { _ in },
            readLine: { "abort" }
        )

        let result = io.displayTakeoverPrompt(
            reason: "test",
            allowForeground: false
        )
        #expect(result.action == .abort)
    }

    @Test("displayTakeoverPrompt abort with steps shows summary")
    func displayTakeoverPromptAbortWithStepsShowsSummary() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "abort" }
        )

        let result = io.displayTakeoverPrompt(
            reason: "受阻",
            allowForeground: false,
            completedSteps: 5
        )
        #expect(result.action == .abort)
        let combined = output.joined(separator: "\n")
        #expect(combined.contains("已完成 5 步"))
    }

    @Test("displayTakeoverPrompt abort without steps shows zero")
    func displayTakeoverPromptAbortWithoutStepsShowsZero() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "quit" }
        )

        let result = io.displayTakeoverPrompt(
            reason: "test",
            allowForeground: false
        )
        #expect(result.action == .abort)
        let combined = output.joined(separator: "\n")
        #expect(combined.contains("已完成 0 步"))
    }

    @Test("displayTakeoverPrompt returns user input on resume")
    func displayTakeoverPromptReturnsUserInputOnResume() {
        let io = TakeoverIO(
            write: { _ in },
            readLine: { "帐号: test@example.com 密码: secret123" }
        )

        let result = io.displayTakeoverPrompt(
            reason: "需要凭据",
            allowForeground: false
        )
        #expect(result.action == .resume)
        #expect(result.userInput == "帐号: test@example.com 密码: secret123")
    }

    @Test("displayTakeoverPrompt returns nil userInput on empty Enter")
    func displayTakeoverPromptReturnsNilUserInputOnEmptyEnter() {
        let io = TakeoverIO(
            write: { _ in },
            readLine: { "" }
        )

        let result = io.displayTakeoverPrompt(
            reason: "受阻",
            allowForeground: false
        )
        #expect(result.action == .resume)
        #expect(result.userInput == "")
    }

    @Test("displayTakeoverPrompt returns userInput on skip")
    func displayTakeoverPromptReturnsUserInputOnSkip() {
        let io = TakeoverIO(
            write: { _ in },
            readLine: { "skip" }
        )

        let result = io.displayTakeoverPrompt(
            reason: "受阻",
            allowForeground: false
        )
        #expect(result.action == .skip)
        #expect(result.userInput == "skip")
    }
}
