import Foundation
import OpenAgentSDK

actor LLMInfoHandler: EventHandler {
    let identifier = "llm-info"
    let subscribedEventTypes: [any AgentEvent.Type] = [
        LLMCostEvent.self,
    ]

    private var round = 0

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        if let e = event as? LLMCostEvent {
            round += 1
            var parts: [String] = ["\(e.inputTokens)in/\(e.outputTokens)out"]
            if let cached = e.cacheReadInputTokens, cached > 0 {
                parts.append("cache:\(cached)")
            }
            if let created = e.cacheCreationInputTokens, created > 0 {
                parts.append("cache+:\(created)")
            }
            parts.append("$\(String(format: "%.4f", e.estimatedCostUsd))")
            fputs("[axion] LLM #\(round) 响应: \(parts.joined(separator: ", "))\n", stderr)
        }
    }
}
