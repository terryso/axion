import Foundation
import OpenAgentSDK

import AxionCore

actor NotificationHandler: EventHandler {
    let identifier = "notification"
    let subscribedEventTypes: [any AgentEvent.Type] = [
        AgentCompletedEvent.self,
        AgentFailedEvent.self,
        AgentInterruptedEvent.self,
    ]

    private let json: Bool
    private let notify: @Sendable (String, String?, String) -> Void

    init(json: Bool, notify: @escaping @Sendable (String, String?, String) -> Void = RunOrchestrator.sendDesktopNotification) {
        self.json = json
        self.notify = notify
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard !json else { return }
        guard let ctx = context.runCompleteContext else { return }

        let succeeded = event is AgentCompletedEvent
        let interrupted = event is AgentInterruptedEvent
        let statusText = succeeded ? "完成" : (interrupted ? "已取消" : "失败")
        let elapsedSec = ctx.durationMs / 1000
        let cost = ctx.totalCostUsd
        let stats = "耗时 \(elapsedSec)s · $\(String(format: "%.2f", cost))"

        let summary: String
        if succeeded, let text = extractSummary(from: ctx.task) {
            summary = String(text.prefix(100))
        } else {
            summary = ctx.task
        }

        notify(
            "Axion \(statusText)",
            stats,
            String(summary.prefix(200))
        )
    }

    private func extractSummary(from text: String) -> String? {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.last
    }
}
