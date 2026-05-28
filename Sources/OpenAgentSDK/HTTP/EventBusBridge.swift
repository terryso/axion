import Foundation

/// Bridges ``EventBus`` events to ``EventBroadcaster`` SSE events.
///
/// Subscribes to an ``EventBus``, maps each ``AgentEvent`` through
/// ``AgentEventSSEMapping/map(_:stepIndex:)``, forwards non-nil results
/// to the ``EventBroadcaster``, and terminates on terminal agent events.
public actor EventBusBridge {

    private let eventBus: EventBus
    private let broadcaster: EventBroadcaster
    private let runId: String
    private var stepIndex: Int = 0
    private var subscriptionId: UUID?
    private var streamTask: _Concurrency.Task<Void, Never>?

    public init(eventBus: EventBus, broadcaster: EventBroadcaster, runId: String) {
        self.eventBus = eventBus
        self.broadcaster = broadcaster
        self.runId = runId
    }

    /// Start consuming events from the EventBus.
    ///
    /// Events are mapped via ``AgentEventSSEMapping/map(_:stepIndex:)`` and forwarded
    /// to the broadcaster. On terminal events the stream ends and `onComplete` is called.
    public func start(onComplete: @Sendable @escaping () async -> Void) async {
        let (id, stream) = await eventBus.subscribe()
        subscriptionId = id

        streamTask = _Concurrency.Task { [broadcaster, runId] in
            for await event in stream {
                if _Concurrency.Task.isCancelled { break }

                let isTerminal = event is AgentCompletedEvent
                    || event is AgentFailedEvent
                    || event is AgentInterruptedEvent

                let sseEvent = AgentEventSSEMapping.map(event, stepIndex: self.stepIndex)
                if let sseEvent {
                    await broadcaster.emit(runId: runId, event: sseEvent)
                }

                if event is ToolCompletedEvent {
                    self.stepIndex += 1
                }

                if isTerminal {
                    await broadcaster.complete(runId: runId)
                    await onComplete()
                    break
                }
            }
        }
    }

    /// Cancel the event subscription and stop processing.
    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        if let id = subscriptionId {
            subscriptionId = nil
            _Concurrency.Task { [eventBus] in await eventBus.unsubscribe(id) }
        }
    }
}
