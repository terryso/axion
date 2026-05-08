import Foundation

/// Holds service instances used by MCP tools.
///
/// In production, initialized with real implementations.
/// In unit tests, swapped with mocks via `ServiceContainer.shared = ...`.
struct ServiceContainer: Sendable {
    var appLauncher: any AppLaunching
    var accessibilityEngine: any WindowManaging
    var inputSimulation: any InputSimulating

    nonisolated(unsafe) static var shared = ServiceContainer(
        appLauncher: AppLauncherService(),
        accessibilityEngine: AccessibilityEngineService(),
        inputSimulation: InputSimulationService()
    )
}
