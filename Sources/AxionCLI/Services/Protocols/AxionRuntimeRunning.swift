import AxionCore
import OpenAgentSDK

protocol AxionRuntimeRunning: AxionRuntimeLifecycle, Sendable {
    func setContextOverrides(chatId: Int64?, shouldReviewMemory: Bool, shouldReviewSkills: Bool) async
    func execute(
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: AxionRuntime.RunOverrides,
        sessionId: String?
    ) async throws -> AxionRunResult

    func resumeSession(
        _ sessionId: String,
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: AxionRuntime.RunOverrides
    ) async throws -> AxionRunResult
    func executeSkill(
        skill: OpenAgentSDK.Skill,
        task: String,
        config: AxionConfig,
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: AxionRuntime.RunOverrides
    ) async throws -> AxionRunResult
}
