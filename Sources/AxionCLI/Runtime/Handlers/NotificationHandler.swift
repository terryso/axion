import Foundation
import OpenAgentSDK


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

        let succeeded = event is AgentCompletedEvent
        let interrupted = event is AgentInterruptedEvent
        let statusText = succeeded ? "完成" : (interrupted ? "已取消" : "失败")

        let elapsedSec: Int
        let summary: String
        let cost: Double

        if let completed = event as? AgentCompletedEvent {
            elapsedSec = completed.durationMs / 1000
            summary = completed.resultText ?? context.sessionId ?? "任务完成"
            cost = context.runCompleteContext?.totalCostUsd ?? 0
        } else if let failed = event as? AgentFailedEvent {
            elapsedSec = 0
            summary = failed.error ?? "未知错误"
            cost = 0
        } else {
            elapsedSec = 0
            summary = context.sessionId ?? "已取消"
            cost = 0
        }

        let stats = "耗时 \(elapsedSec)s · $\(String(format: "%.2f", cost))"

        notify(
            "Axion \(statusText)",
            stats,
            String(summary.prefix(200))
        )
    }
}
