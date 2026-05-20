import Foundation

// MARK: - ConcurrencyLimiter

/// Async semaphore for limiting concurrent agent runs.
/// Uses `CheckedContinuation` to avoid blocking threads (unlike DispatchSemaphore).
public actor ConcurrencyLimiter {

    // MARK: - Properties

    public let maxConcurrent: Int
    private var activeCount = 0
    private var waitQueue: [CheckedContinuation<Void, Never>] = []

    // MARK: - Initialization

    public init(maxConcurrent: Int = 5) {
        self.maxConcurrent = maxConcurrent
    }

    // MARK: - Acquire / Release

    /// Non-blocking acquire. Returns true if a slot was immediately available.
    public func tryAcquire() -> Bool {
        if activeCount < maxConcurrent {
            activeCount += 1
            return true
        }
        return false
    }

    /// Suspending acquire. Waits until a slot is available.
    public func acquire() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waitQueue.append(continuation)
        }
    }

    /// Release a slot and wake the next waiter if any.
    public func release() {
        guard activeCount > 0 else { return }
        activeCount -= 1
        if let waiter = waitQueue.first {
            waitQueue.removeFirst()
            activeCount += 1
            waiter.resume()
        }
    }

    // MARK: - Status

    /// Number of waiting acquire calls.
    public var queueDepth: Int { waitQueue.count }

    /// Whether a slot is available without waiting.
    public var isAvailable: Bool { activeCount < maxConcurrent }

    /// Current number of active runs.
    public var activeRunCount: Int { activeCount }
}
