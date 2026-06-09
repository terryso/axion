import Foundation
import Testing

@testable import AxionCLI

@Suite("SignalHandler", .serialized)
struct SignalHandlerTests {

    // MARK: - install / uninstall 不崩溃

    @Test("install + uninstall 不崩溃")
    func installUninstallNoCrash() {
        SignalHandler.install { }
        #expect(SignalHandler.fireCount() == 0)
        SignalHandler.uninstall()
    }

    @Test("install 幂等 — 重复调用不崩溃")
    func installIdempotent() {
        SignalHandler.install { }
        SignalHandler.install { }  // 第二次应被忽略
        SignalHandler.uninstall()
    }

    // MARK: - fireCount() 和 reset()

    @Test("fireCount 初始为 0")
    func fireCountInitiallyZero() {
        SignalHandler.reset()
        #expect(SignalHandler.fireCount() == 0)
    }

    @Test("fireCount — simulateFire 后递增")
    func fireCountIncrements() {
        SignalHandler.reset()
        SignalHandler.simulateFire()
        #expect(SignalHandler.fireCount() == 1)
    }

    @Test("多次 simulateFire 累计计数")
    func multipleFiresAccumulate() {
        SignalHandler.reset()
        SignalHandler.simulateFire()
        SignalHandler.simulateFire()
        SignalHandler.simulateFire()
        #expect(SignalHandler.fireCount() == 3)
    }

    @Test("reset 后 fireCount 归零")
    func resetClearsCount() {
        SignalHandler.reset()
        SignalHandler.simulateFire()
        #expect(SignalHandler.fireCount() >= 1)

        SignalHandler.reset()
        #expect(SignalHandler.fireCount() == 0)
    }

    @Test("uninstall 后状态干净")
    func uninstallCleanState() {
        SignalHandler.reset()
        SignalHandler.install { }
        SignalHandler.uninstall()

        SignalHandler.reset()
        #expect(SignalHandler.fireCount() == 0)
    }

    // MARK: - chatShouldExit 双击检测

    @Test("chatShouldExit — 2 秒内双击返回 true")
    func shouldExitWithinTwoSeconds() {
        let now = ContinuousClock.now
        let last = now - .seconds(1)
        #expect(chatShouldExit(lastInterrupt: last, now: now) == true)
    }

    @Test("chatShouldExit — 超过 2 秒返回 false")
    func shouldNotExitAfterTwoSeconds() {
        let now = ContinuousClock.now
        let last = now - .seconds(3)
        #expect(chatShouldExit(lastInterrupt: last, now: now) == false)
    }

    @Test("chatShouldExit — 刚好 2 秒返回 false（边界）")
    func shouldNotExitExactlyTwoSeconds() {
        let now = ContinuousClock.now
        let last = now - .seconds(2)
        #expect(chatShouldExit(lastInterrupt: last, now: now) == false)
    }

    @Test("chatShouldExit — 0 秒差返回 true（同时）")
    func shouldExitSameInstant() {
        let now = ContinuousClock.now
        #expect(chatShouldExit(lastInterrupt: now, now: now) == true)
    }

    // MARK: - 无回归：SlashCommand 解析不受影响

    @Test("SlashCommand.parse 不受 SignalHandler 影响")
    func slashCommandUnaffectedBySignalHandler() {
        SignalHandler.reset()
        SignalHandler.install { }

        #expect(SlashCommand.parse("/help") == .help)
        #expect(SlashCommand.parse("/exit") == .exit)
        #expect(SlashCommand.parse("/cost") == .cost)
        #expect(SlashCommand.parse("/foo") == nil)
        #expect(SlashCommand.parse("hello") == nil)

        SignalHandler.uninstall()
    }
}
