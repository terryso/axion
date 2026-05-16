import Foundation
import Testing

@testable import AxionCLI

@Suite("RunCommand Helpers")
struct RunCommandHelpersTests {

    // MARK: - computeEffectiveMaxSteps

    @Test("standard mode returns config maxSteps when no override")
    func computeEffectiveMaxStepsStandardNoOverride() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: false, maxSteps: nil, configMaxSteps: 20)
        #expect(result == 20)
    }

    @Test("standard mode returns CLI override when provided")
    func computeEffectiveMaxStepsStandardWithOverride() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: false, maxSteps: 10, configMaxSteps: 20)
        #expect(result == 10)
    }

    @Test("fast mode caps at 5 when config is higher")
    func computeEffectiveMaxStepsFastCapsAt5() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: true, maxSteps: nil, configMaxSteps: 20)
        #expect(result == 5)
    }

    @Test("fast mode respects CLI override when lower than 5")
    func computeEffectiveMaxStepsFastRespectsLowerOverride() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: true, maxSteps: 3, configMaxSteps: 20)
        #expect(result == 3)
    }

    @Test("fast mode caps at 5 even with higher override")
    func computeEffectiveMaxStepsFastCapsOverrideAt5() {
        let result = RunCommand.computeEffectiveMaxSteps(fast: true, maxSteps: 10, configMaxSteps: 20)
        #expect(result == 5)
    }

    // MARK: - computeEffectiveMaxTokens

    @Test("standard mode returns 4096")
    func computeEffectiveMaxTokensStandard() {
        let result = RunCommand.computeEffectiveMaxTokens(fast: false)
        #expect(result == 4096)
    }

    @Test("fast mode returns 2048")
    func computeEffectiveMaxTokensFast() {
        let result = RunCommand.computeEffectiveMaxTokens(fast: true)
        #expect(result == 2048)
    }

    // MARK: - traceMode

    @Test("traceMode returns fast when fast is true")
    func traceModeFast() {
        #expect(RunCommand.traceMode(fast: true, dryrun: false) == "fast")
    }

    @Test("traceMode returns fast even when dryrun is also true")
    func traceModeFastPriority() {
        #expect(RunCommand.traceMode(fast: true, dryrun: true) == "fast")
    }

    @Test("traceMode returns dryrun when only dryrun is true")
    func traceModeDryrun() {
        #expect(RunCommand.traceMode(fast: false, dryrun: true) == "dryrun")
    }

    @Test("traceMode returns standard when neither is true")
    func traceModeStandard() {
        #expect(RunCommand.traceMode(fast: false, dryrun: false) == "standard")
    }

    // MARK: - generateRunId (tested indirectly via buildFullSystemPrompt, since it's private)
    // generateRunId is private — tested via traceMode and other public APIs that use it
}
