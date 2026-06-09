
/// Common lifecycle operations shared by `AxionRuntimeRunning` and `AxionRuntimeResuming`.
/// Enables generic helpers (handler registration, event loop management) to work with either protocol.
protocol AxionRuntimeLifecycle: Sendable {
    func registerHandler(_ handler: any EventHandler) async
    func startEventLoop() async
    func stopEventLoop() async
}
