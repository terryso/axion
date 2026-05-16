import Foundation

actor ConcurrencyLimiter {
    let maxConcurrent: Int
    private var activeCount = 0
    private var waitQueue: [CheckedContinuation<Int, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    /// Non-blocking acquire. Returns true if a slot was immediately available.
    func tryAcquire() -> Bool {
        if activeCount < maxConcurrent {
            activeCount += 1
            return true
        }
        return false
    }

    /// Blocking acquire. Waits until a slot is available. Returns -1 if cancelled.
    func acquire() async -> Int {
        if activeCount < maxConcurrent {
            activeCount += 1
            return 0
        }
        return await withCheckedContinuation { continuation in
            waitQueue.append(continuation)
        }
    }

    /// Release a slot and wake the next waiter if any.
    func release() {
        guard activeCount > 0 else { return }
        activeCount -= 1
        if let waiter = waitQueue.first {
            waitQueue.removeFirst()
            activeCount += 1
            waiter.resume(returning: 0)
        }
    }

    /// Cancel all queued waiters, resuming them with -1.
    func cancelAll() {
        for waiter in waitQueue {
            waiter.resume(returning: -1)
        }
        waitQueue.removeAll()
    }

    var isAvailable: Bool { activeCount < maxConcurrent }
    var activeRunCount: Int { activeCount }
    var queueDepth: Int { waitQueue.count }
}
