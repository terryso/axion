import Foundation
import OpenAgentSDK

import AxionCore

actor MemoryProcessingHandler: EventHandler {
    let identifier = "memory-processing"
    let subscribedEventTypes: [any AgentEvent.Type] = [
        AgentCompletedEvent.self,
        AgentFailedEvent.self,
        AgentInterruptedEvent.self,
    ]

    private let noMemory: Bool
    private let memoryDir: String

    init(noMemory: Bool, memoryDir: String) {
        self.noMemory = noMemory
        self.memoryDir = memoryDir
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard !noMemory else { return }
        guard let ctx = context.runCompleteContext else { return }

        let succeeded = event is AgentCompletedEvent
        let interrupted = event is AgentInterruptedEvent

        let memoryStore = FileBasedMemoryStore(memoryDir: memoryDir)

        await RunMemoryProcessor.processRunResult(
            toolPairs: ctx.toolPairs,
            task: ctx.task,
            runId: ctx.runId ?? UUID().uuidString,
            memoryStore: memoryStore,
            memoryDir: memoryDir,
            noMemory: noMemory,
            externallyModified: context.externallyModified,
            takeoverEvent: context.takeoverEvent,
            runSucceeded: succeeded,
            runCompleted: !interrupted
        )
    }
}
