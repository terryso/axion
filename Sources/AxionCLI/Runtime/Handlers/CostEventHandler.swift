import Foundation
import OpenAgentSDK

actor CostEventHandler: EventHandler {
    let identifier = "cost"
    let subscribedEventTypes: [any AgentEvent.Type] = [
        AgentCompletedEvent.self,
        AgentFailedEvent.self,
        AgentInterruptedEvent.self,
    ]

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard let ctx = context.runCompleteContext else { return }
        let msg = Self.formatSummary(
            numTurns: ctx.numTurns,
            totalTokens: ctx.usage.inputTokens + ctx.usage.outputTokens,
            totalCostUsd: ctx.totalCostUsd
        )
        fputs(msg, stderr)
    }

    nonisolated static func formatSummary(numTurns: Int, totalTokens: Int, totalCostUsd: Double) -> String {
        "[axion] LLM 调用: \(numTurns)轮, Tokens: \(totalTokens), 预估成本: $\(String(format: "%.4f", totalCostUsd))\n"
    }
}
