import Foundation

// MARK: - EventBroadcaster

/// Actor-based multi-client event broadcaster for SSE event streaming.
/// Manages subscriber registration, event distribution, replay buffering,
/// and lifecycle cleanup for completed streams.
actor EventBroadcaster {

    // MARK: - Properties

    /// Subscribers organized by runId. Each subscriber has a unique UUID
    /// to allow individual removal on stream termination.
    private var subscribers: [String: [UUID: AsyncStream<SSEEvent>.Continuation]] = [:]

    /// Replay buffer per runId — caches events for late subscribers (AC4).
    private var replayBuffer: [String: [SSEEvent]] = [:]

    /// Cleanup tasks scheduled for completed runs.
    private var cleanupTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Subscription

    /// Subscribe to events for a given runId.
    /// Returns an AsyncStream that yields SSEEvent values as they are emitted.
    /// - Parameter runId: The run to subscribe to.
    /// - Returns: An AsyncStream<SSEEvent> for consuming events.
    func subscribe(runId: String) -> AsyncStream<SSEEvent> {
        AsyncStream { continuation in
            let id = UUID()
            subscribers[runId, default: [:]][id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(runId: runId, id: id) }
            }
        }
    }

    /// Subscribe to events for a given runId, first replaying any buffered events.
    /// Used for late subscribers connecting after events have already been emitted (AC4).
    /// - Parameter runId: The run to subscribe to.
    /// - Returns: An AsyncStream<SSEEvent> that first yields replayed events.
    func subscribeWithReplay(runId: String) -> AsyncStream<SSEEvent> {
        AsyncStream { continuation in
            let id = UUID()
            subscribers[runId, default: [:]][id] = continuation

            // Replay buffered events first
            if let buffered = replayBuffer[runId] {
                for event in buffered {
                    continuation.yield(event)
                }
            }

            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(runId: runId, id: id) }
            }
        }
    }

    // MARK: - Emission

    /// Emit an event to all subscribers of the given runId.
    /// Also appends the event to the replay buffer.
    /// - Parameters:
    ///   - runId: The run to emit the event for.
    ///   - event: The SSEEvent to broadcast.
    func emit(runId: String, event: SSEEvent) {
        replayBuffer[runId, default: []].append(event)
        for (_, continuation) in subscribers[runId, default: [:]] {
            continuation.yield(event)
        }
    }

    // MARK: - Completion

    /// Complete all subscriber streams for the given runId.
    /// Call this when the run finishes to close all SSE connections.
    /// Schedules a delayed cleanup of the replay buffer.
    /// - Parameter runId: The run to complete.
    func complete(runId: String) {
        for (_, continuation) in subscribers[runId, default: [:]] {
            continuation.finish()
        }
        subscribers.removeValue(forKey: runId)

        // Schedule cleanup of replay buffer after 5 minutes
        cleanupTasks[runId] = Task {
            try? await Task.sleep(for: .seconds(300))
            await self.removeCompletedStreams(runId: runId)
        }
    }

    // MARK: - Cleanup

    /// Remove completed stream resources (replay buffer, subscriber entries).
    /// - Parameter runId: The run to clean up.
    func removeCompletedStreams(runId: String) {
        replayBuffer.removeValue(forKey: runId)
        subscribers.removeValue(forKey: runId)
        cleanupTasks.removeValue(forKey: runId)?.cancel()
    }

    /// Get the replay buffer contents for a given runId.
    /// Used by the SSE endpoint to check if events are available for replay.
    /// - Parameter runId: The run to get events for.
    /// - Returns: Array of cached SSEEvents.
    func getReplayBuffer(runId: String) -> [SSEEvent] {
        replayBuffer[runId] ?? []
    }

    // MARK: - Private Helpers

    /// Remove a single subscriber by its UUID.
    private func removeSubscriber(runId: String, id: UUID) {
        subscribers[runId]?.removeValue(forKey: id)
        if subscribers[runId]?.isEmpty == true {
            subscribers.removeValue(forKey: runId)
        }
    }
}
