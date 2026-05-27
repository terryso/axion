import AxionCore

protocol AxionRuntimeResuming: Sendable {
    func registerHandler(_ handler: any EventHandler) async
    func startEventLoop() async
    func stopEventLoop() async
    func resumeSession(
        _ sessionId: String,
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: AxionRuntime.RunOverrides
    ) async throws -> AxionRunResult
}
