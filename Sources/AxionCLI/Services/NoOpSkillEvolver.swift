import Foundation
import OpenAgentSDK

/// No-op `SkillEvolver` used until Story 22.5 provides `FileBasedSkillUsageStore`
/// and Story 22.2 wires `LLMSkillEvolver` with a shared `LLMClient`.
struct NoOpSkillEvolver: SkillEvolver, Sendable {
    func evolve(
        skill: Skill,
        signals: [SkillSignal],
        config: SkillEvolutionConfig
    ) async throws -> SkillEvolutionResult {
        SkillEvolutionResult(
            evolvedSkill: nil,
            appliedSignals: [],
            skippedSignals: signals,
            changes: []
        )
    }
}
