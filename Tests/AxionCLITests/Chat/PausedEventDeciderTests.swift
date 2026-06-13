import Testing
import Foundation

@testable import AxionCLI

@Suite("PausedEventDecider")
struct PausedEventDeciderTests {

    // MARK: - resume

    @Test("resume + 空输入 → 默认确认 context")
    func resumeEmptyInputDefaultContext() {
        let decision = PausedEventDecider.decide(
            canResume: true,
            action: .resume,
            text: ""
        )
        #expect(decision == .resume(context: "用户已确认继续"))
    }

    @Test("resume + nil 输入 → 默认确认 context")
    func resumeNilInputDefaultContext() {
        let decision = PausedEventDecider.decide(
            canResume: true,
            action: .resume,
            text: nil
        )
        #expect(decision == .resume(context: "用户已确认继续"))
    }

    @Test("resume + 纯空白输入 → 默认确认 context（trim 后为空）")
    func resumeWhitespaceInputDefaultContext() {
        let decision = PausedEventDecider.decide(
            canResume: true,
            action: .resume,
            text: "   \n  "
        )
        #expect(decision == .resume(context: "用户已确认继续"))
    }

    @Test("resume + 反馈输入 → trim 后的反馈作为 context")
    func resumeFeedbackAsContext() {
        let decision = PausedEventDecider.decide(
            canResume: true,
            action: .resume,
            text: "  排除了 3 个项目  "
        )
        #expect(decision == .resume(context: "排除了 3 个项目"))
    }

    // MARK: - skip

    @Test("skip → resume(context: \"skip\")")
    func skipResumesWithSkipContext() {
        let decision = PausedEventDecider.decide(
            canResume: true,
            action: .skip,
            text: "skip"
        )
        #expect(decision == .resume(context: "skip"))
    }

    // MARK: - abort

    @Test("abort → interrupt")
    func abortInterrupts() {
        let decision = PausedEventDecider.decide(
            canResume: true,
            action: .abort,
            text: "abort"
        )
        #expect(decision == .interrupt)
    }

    // MARK: - 边界 A：canResume == false

    @Test("canResume == false + resume 动作 → 强制 interrupt（边界 A 回归）")
    func canResumeFalseForcesInterruptOnResume() {
        let decision = PausedEventDecider.decide(
            canResume: false,
            action: .resume,
            text: "继续"
        )
        #expect(decision == .interrupt)
    }

    @Test("canResume == false + skip 动作 → 强制 interrupt")
    func canResumeFalseForcesInterruptOnSkip() {
        let decision = PausedEventDecider.decide(
            canResume: false,
            action: .skip,
            text: "skip"
        )
        #expect(decision == .interrupt)
    }

    @Test("canResume == false + abort 动作 → interrupt")
    func canResumeFalseForcesInterruptOnAbort() {
        let decision = PausedEventDecider.decide(
            canResume: false,
            action: .abort,
            text: "abort"
        )
        #expect(decision == .interrupt)
    }
}
