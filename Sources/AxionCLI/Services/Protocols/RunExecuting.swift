import OpenAgentSDK


protocol RunExecuting: Sendable {
    func execute(buildResult: AgentBuildResult, runConfig: RunOrchestrator.RunConfig) async throws -> RunOrchestrator.RunResult
    func generateRunId() -> String
}

public struct DefaultRunExecutor: RunExecuting {
    public init() {}
    func execute(buildResult: AgentBuildResult, runConfig: RunOrchestrator.RunConfig) async throws -> RunOrchestrator.RunResult {
        try await RunOrchestrator.execute(buildResult: buildResult, runConfig: runConfig)
    }

    func generateRunId() -> String {
        RunOrchestrator.generateRunId()
    }
}
