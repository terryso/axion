import XCTest
@testable import AxionCLI

final class ConcurrencyLimiterTests: XCTestCase {

    // MARK: - Basic acquire/release

    func test_acquire_belowLimit_returnsZero() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 3)
        let position = await limiter.acquire()
        XCTAssertEqual(position, 0, "Below limit should return position 0")
    }

    func test_acquire_release_decrementsCount() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 3)
        _ = await limiter.acquire()
        let count1 = await limiter.activeRunCount
        XCTAssertEqual(count1, 1)
        await limiter.release()
        let count2 = await limiter.activeRunCount
        XCTAssertEqual(count2, 0)
    }

    func test_isAvailable_reflectsState() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)
        let avail1 = await limiter.isAvailable
        XCTAssertTrue(avail1)
        _ = await limiter.acquire()
        let avail2 = await limiter.isAvailable
        XCTAssertTrue(avail2)
        _ = await limiter.acquire()
        let avail3 = await limiter.isAvailable
        XCTAssertFalse(avail3)
    }

    // MARK: - Queueing when full

    func test_acquire_atLimit_queues() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire()

        let queued = Task { () -> Int in
            await limiter.acquire()
        }

        try await Task.sleep(for: .milliseconds(50))
        let activeCount = await limiter.activeRunCount
        XCTAssertEqual(activeCount, 1, "Only one should be active")

        await limiter.release()

        let position = try await queued.value
        let finalCount = await limiter.activeRunCount
        XCTAssertEqual(finalCount, 1, "Should be back to 1 after release+acquire")
    }

    func test_release_wakesNextWaiter() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire()

        let queuedTask = Task { () -> Int in
            await limiter.acquire()
        }

        try await Task.sleep(for: .milliseconds(50))
        await limiter.release()

        let position = try await queuedTask.value
        XCTAssertGreaterThanOrEqual(position, 0, "Queued task should be woken")
    }

    // MARK: - Concurrent safety

    func test_concurrentAcquire_doesNotExceedLimit() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 3)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let pos = await limiter.acquire()
                    if pos == 0 {
                        try? await Task.sleep(for: .milliseconds(50))
                        await limiter.release()
                    }
                }
            }
        }

        let finalCount = await limiter.activeRunCount
        XCTAssertEqual(finalCount, 0, "All should be released after completion")
    }

    // MARK: - Story 5.3: Full lifecycle and position tracking

    func test_multipleQueuedTasks_allEventuallyRun() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire() // Fill the slot

        let task1 = Task { await limiter.acquire() }
        let task2 = Task { await limiter.acquire() }

        try await Task.sleep(for: .milliseconds(50))
        let countBeforeRelease = await limiter.activeRunCount
        XCTAssertEqual(countBeforeRelease, 1, "Only 1 should be active while queued")

        // Release sequentially — each release wakes the next waiter
        await limiter.release()
        try await Task.sleep(for: .milliseconds(50))
        await limiter.release()
        try await Task.sleep(for: .milliseconds(50))

        _ = try await task1.value
        _ = try await task2.value

        let countAfter = await limiter.activeRunCount
        XCTAssertEqual(countAfter, 1, "One slot active after all queued tasks acquired")
    }

    func test_fullLifecycle_allReleased_countReturnsToZero() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)

        _ = await limiter.acquire()
        _ = await limiter.acquire()

        let queuedTask = Task { await limiter.acquire() }
        try await Task.sleep(for: .milliseconds(50))

        await limiter.release() // wakes queued task
        _ = try await queuedTask.value

        await limiter.release()
        await limiter.release()

        let count = await limiter.activeRunCount
        XCTAssertEqual(count, 0, "All slots should be released")
    }

    func test_release_onEmptyLimiter_doesNotCrash() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 3)
        // Release without acquire — should be a no-op
        await limiter.release()
        let count = await limiter.activeRunCount
        XCTAssertEqual(count, 0, "Releasing on empty limiter should not go negative")
    }

    // MARK: - Story 5.3 AC3: tryAcquire / cancelAll / queueDepth (graceful shutdown)

    func test_tryAcquire_belowLimit_returnsTrue() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)
        let result = await limiter.tryAcquire()
        XCTAssertTrue(result, "tryAcquire should succeed when below limit")
        let count = await limiter.activeRunCount
        XCTAssertEqual(count, 1)
    }

    func test_tryAcquire_atLimit_returnsFalse() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.tryAcquire()
        let result = await limiter.tryAcquire()
        XCTAssertFalse(result, "tryAcquire should fail when at limit")
    }

    func test_queueDepth_reflectsWaitingCount() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire()
        let depth0 = await limiter.queueDepth
        XCTAssertEqual(depth0, 0)

        _ = Task { await limiter.acquire() }
        try await Task.sleep(for: .milliseconds(50))
        let depth1 = await limiter.queueDepth
        XCTAssertEqual(depth1, 1, "One task should be queued")

        _ = Task { await limiter.acquire() }
        try await Task.sleep(for: .milliseconds(50))
        let depth2 = await limiter.queueDepth
        XCTAssertEqual(depth2, 2, "Two tasks should be queued")
    }

    func test_cancelAll_resumesQueuedWithMinusOne() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire()

        let task1 = Task { await limiter.acquire() }
        let task2 = Task { await limiter.acquire() }
        try await Task.sleep(for: .milliseconds(50))

        let depthBefore = await limiter.queueDepth
        XCTAssertEqual(depthBefore, 2)
        await limiter.cancelAll()
        let depthAfter = await limiter.queueDepth
        XCTAssertEqual(depthAfter, 0)

        let pos1 = try await task1.value
        let pos2 = try await task2.value
        XCTAssertEqual(pos1, -1, "Cancelled waiter should receive -1")
        XCTAssertEqual(pos2, -1, "Cancelled waiter should receive -1")
    }

    func test_cancelAll_doesNotAffectActiveRuns() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)
        _ = await limiter.acquire()
        _ = await limiter.acquire()

        _ = Task { await limiter.acquire() }
        try await Task.sleep(for: .milliseconds(50))

        await limiter.cancelAll()
        let activeCount = await limiter.activeRunCount
        XCTAssertEqual(activeCount, 2, "cancelAll should not affect active runs")
    }
}
