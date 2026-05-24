import Foundation
import OpenAgentSDK

/// Configurable mock for ``SkillEvolver`` used in unit tests.
struct MockSkillEvolver: SkillEvolver, Sendable {
    let result: SkillEvolutionResult

    init(result: SkillEvolutionResult = SkillEvolutionResult(
        evolvedSkill: nil,
        appliedSignals: [],
        skippedSignals: [],
        changes: []
    )) {
        self.result = result
    }

    func evolve(
        skill: Skill,
        signals: [SkillSignal],
        config: SkillEvolutionConfig
    ) async throws -> SkillEvolutionResult {
        result
    }
}
