import Foundation

/// Actor that serializes concurrent `run_task` requests.
/// Ensures only one agent.prompt() call executes at a time,
/// since the Agent shares a single Helper MCP connection.
actor TaskQueue {

    // MARK: - Properties

    private var isRunning = false
    private var isShuttingDown = false
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []
    private var completionContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Public API

    /// Enqueue a closure for serial execution.
    /// Returns immediately after scheduling; the closure runs when all
    /// previously enqueued work has completed. Silently dropped during shutdown.
    func enqueue(_ work: @Sendable @escaping () async -> Void) {
        guard !isShuttingDown else { return }
        Task {
            await waitForCapacity()
            guard !isShuttingDown else { return }
            await work()
            taskCompleted()
        }
    }

    /// Wait for the currently running task to complete and cancel all pending tasks.
    /// Called during graceful shutdown to satisfy AC5 (wait for in-flight tasks).
    func gracefulShutdown() async {
        isShuttingDown = true
        for continuation in pendingContinuations {
            continuation.resume()
        }
        pendingContinuations.removeAll()
        if isRunning {
            await withCheckedContinuation { continuation in
                self.completionContinuation = continuation
            }
        }
    }

    // MARK: - Private

    private func waitForCapacity() async {
        guard isRunning else {
            isRunning = true
            return
        }
        await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)
        }
    }

    private func taskCompleted() {
        isRunning = false
        if let continuation = completionContinuation {
            completionContinuation = nil
            continuation.resume()
            return
        }
        if let continuation = pendingContinuations.first {
            pendingContinuations.removeFirst()
            isRunning = true
            continuation.resume()
        }
    }
}
