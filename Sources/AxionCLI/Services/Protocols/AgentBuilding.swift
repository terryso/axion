protocol AgentBuilding: Sendable {
    func build(_ config: AgentBuilder.BuildConfig) async throws -> AgentBuildResult
}

public struct DefaultAgentBuilder: AgentBuilding {
    public init() {}
    func build(_ config: AgentBuilder.BuildConfig) async throws -> AgentBuildResult {
        try await AgentBuilder.build(config)
    }
}
