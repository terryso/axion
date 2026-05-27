import Foundation
import OpenAgentSDK

import AxionCore

protocol AgentBuilding: Sendable {
    func build(_ config: AgentBuilder.BuildConfig) async throws -> AgentBuildResult
    func buildSkillAgent(config: AxionConfig, skill: OpenAgentSDK.Skill, maxSteps: Int?, verbose: Bool, eventBus: EventBus?) async throws -> Agent
}

public struct DefaultAgentBuilder: AgentBuilding {
    public init() {}
    func build(_ config: AgentBuilder.BuildConfig) async throws -> AgentBuildResult {
        try await AgentBuilder.build(config)
    }

    func buildSkillAgent(config: AxionConfig, skill: OpenAgentSDK.Skill, maxSteps: Int?, verbose: Bool, eventBus: EventBus?) async throws -> Agent {
        try await AgentBuilder.buildSkillAgent(config: config, skill: skill, maxSteps: maxSteps, verbose: verbose, eventBus: eventBus)
    }
}
