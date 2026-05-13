import XCTest

@testable import AxionCLI

// MARK: - TakeoverAction Tests

final class TakeoverIOTests: XCTestCase {

    // MARK: - TakeoverAction Parsing

    func test_takeoverAction_resume_fromNil() {
        let action = TakeoverAction.fromInput(nil)
        XCTAssertEqual(action, .resume)
    }

    func test_takeoverAction_resume_fromEmpty() {
        let action = TakeoverAction.fromInput("")
        XCTAssertEqual(action, .resume)
    }

    func test_takeoverAction_resume_fromEnter() {
        let action = TakeoverAction.fromInput("\n")
        XCTAssertEqual(action, .resume)
    }

    func test_takeoverAction_resume_fromContinue() {
        let action = TakeoverAction.fromInput("continue")
        XCTAssertEqual(action, .resume)
    }

    func test_takeoverAction_skip() {
        let action = TakeoverAction.fromInput("skip")
        XCTAssertEqual(action, .skip)
    }

    func test_takeoverAction_abort() {
        let action = TakeoverAction.fromInput("abort")
        XCTAssertEqual(action, .abort)
    }

    func test_takeoverAction_abort_fromQuit() {
        let action = TakeoverAction.fromInput("quit")
        XCTAssertEqual(action, .abort)
    }

    func test_takeoverAction_caseInsensitive() {
        XCTAssertEqual(TakeoverAction.fromInput("Skip"), .skip)
        XCTAssertEqual(TakeoverAction.fromInput("ABORT"), .abort)
        XCTAssertEqual(TakeoverAction.fromInput("CONTINUE"), .resume)
    }

    func test_takeoverAction_whitespaceTrimmed() {
        XCTAssertEqual(TakeoverAction.fromInput("  skip  "), .skip)
        XCTAssertEqual(TakeoverAction.fromInput(" abort "), .abort)
    }

    // MARK: - TakeoverIO Display

    func test_displayTakeoverPrompt_outputsReason() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "continue" }
        )

        let action = io.displayTakeoverPrompt(
            reason: "无法找到目标按钮",
            allowForeground: false
        )

        XCTAssertEqual(action, .resume)
        let combined = output.joined(separator: "\n")
        XCTAssertTrue(combined.contains("无法找到目标按钮"))
    }

    func test_displayTakeoverPrompt_allowForegroundShowsHint() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "skip" }
        )

        let action = io.displayTakeoverPrompt(
            reason: "受阻",
            allowForeground: true
        )

        XCTAssertEqual(action, .skip)
        let combined = output.joined(separator: "\n")
        XCTAssertTrue(combined.contains("前台"))
    }

    func test_displayTakeoverPrompt_noForegroundHintWhenDisabled() {
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
        XCTAssertFalse(combined.contains("前台"))
    }

    func test_displayTakeoverPrompt_abortAction() {
        let io = TakeoverIO(
            write: { _ in },
            readLine: { "abort" }
        )

        let action = io.displayTakeoverPrompt(
            reason: "test",
            allowForeground: false
        )
        XCTAssertEqual(action, .abort)
    }

    func test_displayTakeoverPrompt_abortWithSteps_showsSummary() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "abort" }
        )

        let action = io.displayTakeoverPrompt(
            reason: "受阻",
            allowForeground: false,
            completedSteps: 5
        )
        XCTAssertEqual(action, .abort)
        let combined = output.joined(separator: "\n")
        XCTAssertTrue(combined.contains("已完成 5 步"))
    }

    func test_displayTakeoverPrompt_abortWithoutSteps_showsZero() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "quit" }
        )

        let action = io.displayTakeoverPrompt(
            reason: "test",
            allowForeground: false
        )
        XCTAssertEqual(action, .abort)
        let combined = output.joined(separator: "\n")
        XCTAssertTrue(combined.contains("已完成 0 步"))
    }
}
