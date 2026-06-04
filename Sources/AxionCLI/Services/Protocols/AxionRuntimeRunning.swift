import AxionCore
import OpenAgentSDK

protocol AxionRuntimeRunning: Sendable {
    func registerHandler(_ handler: any EventHandler) async
    func setContextOverrides(chatId: Int64?, shouldReviewMemory: Bool, shouldReviewSkills: Bool) async
    func startEventLoop() async
    func stopEventLoop() async
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
