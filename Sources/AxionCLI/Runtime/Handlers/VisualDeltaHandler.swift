import Foundation
import OpenAgentSDK

actor VisualDeltaHandler: EventHandler {
    let identifier = "visual-delta"
    let subscribedEventTypes: [any AgentEvent.Type] = [ToolCompletedEvent.self]

    private let tracker: VisualDeltaTracker?
    private var checked = 0
    private var skipped = 0

    init(noVisualDelta: Bool) {
        self.tracker = noVisualDelta ? nil : VisualDeltaTracker()
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard let toolEvent = event as? ToolCompletedEvent else { return }
        guard toolEvent.toolName.contains("screenshot") else { return }
        guard !toolEvent.isError else { return }
        guard let tracker else { return }
        guard let base64 = toolEvent.output else { return }

        let result = await tracker.processScreenshot(base64: base64)
        checked += 1
        if result.shouldSkipVerifier {
            skipped += 1
        }
    }
}
