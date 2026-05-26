import Foundation
import OpenAgentSDK

actor SeatMonitorHandler: EventHandler {
    let identifier = "seat-monitor"
    let subscribedEventTypes: [any AgentEvent.Type] = [ToolStartedEvent.self]

    private let enabled: Bool
    private var monitor: SeatActivityMonitor?

    init(sharedSeatMode: Bool) {
        self.enabled = sharedSeatMode
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard enabled else { return }
        guard let toolEvent = event as? ToolStartedEvent else { return }
        guard toolEvent.toolName.hasPrefix("mcp__axion-helper__") else { return }

        if monitor == nil {
            monitor = SeatActivityMonitor.create()
        }
        guard let monitor else { return }

        if let activity = await monitor.check() {
            fputs("[axion] seat-monitor: external activity detected — \(activity)\n", stderr)
        }
    }
}
