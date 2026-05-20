import Foundation

// MARK: - EventBroadcaster

/// Actor-based multi-client event broadcaster for SSE event streaming.
/// Manages subscriber registration, event distribution, replay buffering,
/// and lifecycle cleanup for completed streams.
public actor EventBroadcaster {

    // MARK: - Properties

    /// Subscribers organized by runId.
    private var subscribers: [String: [UUID: AsyncStream<AgentSSEEvent>.Continuation]] = [:]

    /// Replay buffer per runId for late subscribers.
    private var replayBuffer: [String: [AgentSSEEvent]] = [:]

    /// Cleanup tasks scheduled for completed runs.
    private var cleanupTasks: [String: _Concurrency.Task<Void, Never>] = [:]

    /// Disk persistence service.
    private let persistenceService: RunPersistenceService?

    // MARK: - Initialization

    public init(persistenceService: RunPersistenceService? = nil) {
        self.persistenceService = persistenceService
    }

    // MARK: - Subscription

    /// Subscribe to events for a given runId.
    public func subscribe(runId: String) -> AsyncStream<AgentSSEEvent> {
        AsyncStream { continuation in
            let id = UUID()
            subscribers[runId, default: [:]][id] = continuation
            continuation.onTermination = { [weak self] _ in
                _Concurrency.Task { await self?.removeSubscriber(runId: runId, id: id) }
            }
        }
    }

    /// Subscribe with replay of buffered events for late subscribers.
    public func subscribeWithReplay(runId: String) -> AsyncStream<AgentSSEEvent> {
        AsyncStream { continuation in
            let id = UUID()
            subscribers[runId, default: [:]][id] = continuation

            if let buffered = replayBuffer[runId] {
                for event in buffered {
                    continuation.yield(event)
                }
            } else if let diskEvents = persistenceService?.loadEvents(runId: runId),
                      !diskEvents.isEmpty
            {
                replayBuffer[runId] = diskEvents
                for event in diskEvents {
                    continuation.yield(event)
                }
            }

            continuation.onTermination = { [weak self] _ in
                _Concurrency.Task { await self?.removeSubscriber(runId: runId, id: id) }
            }
        }
    }

    // MARK: - Emission

    /// Emit an event to all subscribers of the given runId.
    public func emit(runId: String, event: AgentSSEEvent) {
        replayBuffer[runId, default: []].append(event)
        persistenceService?.persistEventSafely(runId: runId, event: event)
        for (_, continuation) in subscribers[runId, default: [:]] {
            continuation.yield(event)
        }
    }

    // MARK: - Completion

    /// Complete all subscriber streams for the given runId.
    /// Schedules a delayed cleanup of the replay buffer after 5 minutes.
    public func complete(runId: String) {
        for (_, continuation) in subscribers[runId, default: [:]] {
            continuation.finish()
        }
        subscribers.removeValue(forKey: runId)

        cleanupTasks[runId] = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .seconds(300))
            await self.removeCompletedStreams(runId: runId)
        }
    }

    // MARK: - Cleanup

    /// Remove completed stream resources.
    public func removeCompletedStreams(runId: String) {
        replayBuffer.removeValue(forKey: runId)
        subscribers.removeValue(forKey: runId)
        cleanupTasks.removeValue(forKey: runId)?.cancel()
    }

    /// Get the replay buffer contents for a given runId.
    public func getReplayBuffer(runId: String) -> [AgentSSEEvent] {
        replayBuffer[runId] ?? []
    }

    /// Restore persisted events to the replay buffer for recovery.
    public func restoreReplayBuffer(runId: String, events: [AgentSSEEvent]) {
        replayBuffer[runId] = events
    }

    // MARK: - Private Helpers

    private func removeSubscriber(runId: String, id: UUID) {
        subscribers[runId]?.removeValue(forKey: id)
        if subscribers[runId]?.isEmpty == true {
            subscribers.removeValue(forKey: runId)
        }
    }
}
