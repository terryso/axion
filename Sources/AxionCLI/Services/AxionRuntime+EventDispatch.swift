import Foundation
import OpenAgentSDK

import AxionCore

// MARK: - Event Dispatch

extension AxionRuntime {

    /// Dispatches an event to all registered handlers that subscribe to its type.
    ///
    /// AgentCompletedEvent/AgentFailedEvent fire during stream completion,
    /// before execute() returns. Read runCompleteContext directly from the box
    /// that SDK's onRunComplete callback populates.
    func dispatchToHandlers(_ event: any AgentEvent) async {
        let context = EventHandlerContext(
            sessionId: sessionId,
            config: AxionConfig(apiKey: ""),
            eventBus: eventBus,
            externallyModified: externallyModified,
            externallyModifiedFlag: externallyModifiedFlag,
            takeoverEvent: takeoverEvent,
            runCompleteContext: runCompleteBox?.context,
            sessionStore: sessionStore,
            chatId: contextChatId,
            shouldReviewMemory: contextShouldReviewMemory,
            shouldReviewSkills: contextShouldReviewSkills
        )
        for handler in handlers {
            let shouldDispatch = await shouldDispatch(event: event, to: handler)
            guard shouldDispatch else { continue }
            await handler.handle(event, context: context)
        }
        // Sync flag back from handlers (e.g. SeatMonitorHandler sets it on external activity)
        if externallyModifiedFlag.value {
            externallyModified = true
        }
    }

    /// Checks whether a handler subscribes to the given event type.
    private func shouldDispatch(event: any AgentEvent, to handler: any EventHandler) async -> Bool {
        let types = await handler.subscribedEventTypes
        if types.isEmpty { return true }
        return types.contains { type(of: event) == $0 }
    }
}
