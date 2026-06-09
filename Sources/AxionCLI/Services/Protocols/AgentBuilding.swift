import OpenAgentSDK

import AxionCore

protocol AgentBuilding: Sendable {
    func build(_ config: AgentBuilder.BuildConfig, eventBus: EventBus?) async throws -> AgentBuildResult
    func buildSkillAgent(config: AxionConfig, skill: OpenAgentSDK.Skill, maxSteps: Int?, verbose: Bool, eventBus: EventBus?) async throws -> (agent: Agent, runCompleteBox: RunCompleteContextBox)
}

public struct DefaultAgentBuilder: AgentBuilding {
    public init() {}
    func build(_ config: AgentBuilder.BuildConfig, eventBus: EventBus? = nil) async throws -> AgentBuildResult {
        try await AgentBuilder.build(config, eventBus: eventBus)
    }

    func buildSkillAgent(config: AxionConfig, skill: OpenAgentSDK.Skill, maxSteps: Int?, verbose: Bool, eventBus: EventBus?) async throws -> (agent: Agent, runCompleteBox: RunCompleteContextBox) {
        try await AgentBuilder.buildSkillAgent(config: config, skill: skill, maxSteps: maxSteps, verbose: verbose, eventBus: eventBus)
    }
}
