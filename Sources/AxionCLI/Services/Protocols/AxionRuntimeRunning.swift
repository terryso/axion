import AxionCore

protocol AxionRuntimeRunning: Sendable {
    func registerHandler(_ handler: any EventHandler) async
    func startEventLoop() async
    func stopEventLoop() async
    func execute(
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: AxionRuntime.RunOverrides
    ) async throws -> AxionRunResult
}
