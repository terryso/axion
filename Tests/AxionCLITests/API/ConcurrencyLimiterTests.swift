import Testing
@testable import AxionCLI

@Suite("ConcurrencyLimiter")
struct ConcurrencyLimiterTests {

    @Test("Acquire below limit returns zero")
    func acquireBelowLimitReturnsZero() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 3)
        let position = await limiter.acquire()
        #expect(position == 0)
    }

    @Test("Acquire and release decrements count")
    func acquireReleaseDecrementsCount() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 3)
        _ = await limiter.acquire()
        let count1 = await limiter.activeRunCount
        #expect(count1 == 1)
        await limiter.release()
        let count2 = await limiter.activeRunCount
        #expect(count2 == 0)
    }

    @Test("isAvailable reflects state")
    func isAvailableReflectsState() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)
        let avail1 = await limiter.isAvailable
        #expect(avail1)
        _ = await limiter.acquire()
        let avail2 = await limiter.isAvailable
        #expect(avail2)
        _ = await limiter.acquire()
        let avail3 = await limiter.isAvailable
        #expect(!avail3)
    }

    @Test("Acquire at limit queues")
    func acquireAtLimitQueues() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire()

        let queued = Task { () -> Int in
            await limiter.acquire()
        }

        try await Task.sleep(for: .milliseconds(50))
        let activeCount = await limiter.activeRunCount
        #expect(activeCount == 1)

        await limiter.release()

        let _ = await queued.value
        let finalCount = await limiter.activeRunCount
        #expect(finalCount == 1)
    }

    @Test("Release wakes next waiter")
    func releaseWakesNextWaiter() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire()

        let queuedTask = Task { () -> Int in
            await limiter.acquire()
        }

        try await Task.sleep(for: .milliseconds(50))
        await limiter.release()

        let position = await queuedTask.value
        #expect(position >= 0)
    }

    @Test("Concurrent acquire does not exceed limit")
    func concurrentAcquireDoesNotExceedLimit() async throws {
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
        #expect(finalCount == 0)
    }

    @Test("Multiple queued tasks all eventually run")
    func multipleQueuedTasksAllEventuallyRun() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire()

        let task1 = Task { await limiter.acquire() }
        let task2 = Task { await limiter.acquire() }

        try await Task.sleep(for: .milliseconds(50))
        let countBeforeRelease = await limiter.activeRunCount
        #expect(countBeforeRelease == 1)

        await limiter.release()
        try await Task.sleep(for: .milliseconds(50))
        await limiter.release()
        try await Task.sleep(for: .milliseconds(50))

        _ = await task1.value
        _ = await task2.value

        let countAfter = await limiter.activeRunCount
        #expect(countAfter == 1)
    }

    @Test("Full lifecycle all released count returns to zero")
    func fullLifecycleAllReleasedCountReturnsToZero() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)

        _ = await limiter.acquire()
        _ = await limiter.acquire()

        let queuedTask = Task { await limiter.acquire() }
        try await Task.sleep(for: .milliseconds(50))

        await limiter.release()
        _ = await queuedTask.value

        await limiter.release()
        await limiter.release()

        let count = await limiter.activeRunCount
        #expect(count == 0)
    }

    @Test("Release on empty limiter does not crash")
    func releaseOnEmptyLimiterDoesNotCrash() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 3)
        await limiter.release()
        let count = await limiter.activeRunCount
        #expect(count == 0)
    }

    @Test("tryAcquire below limit returns true")
    func tryAcquireBelowLimitReturnsTrue() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)
        let result = await limiter.tryAcquire()
        #expect(result)
        let count = await limiter.activeRunCount
        #expect(count == 1)
    }

    @Test("tryAcquire at limit returns false")
    func tryAcquireAtLimitReturnsFalse() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.tryAcquire()
        let result = await limiter.tryAcquire()
        #expect(!result)
    }

    @Test("queueDepth reflects waiting count")
    func queueDepthReflectsWaitingCount() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire()
        let depth0 = await limiter.queueDepth
        #expect(depth0 == 0)

        _ = Task { await limiter.acquire() }
        try await Task.sleep(for: .milliseconds(50))
        let depth1 = await limiter.queueDepth
        #expect(depth1 == 1)

        _ = Task { await limiter.acquire() }
        try await Task.sleep(for: .milliseconds(50))
        let depth2 = await limiter.queueDepth
        #expect(depth2 == 2)
    }

    @Test("cancelAll resumes queued with minus one")
    func cancelAllResumesQueuedWithMinusOne() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire()

        let task1 = Task { await limiter.acquire() }
        let task2 = Task { await limiter.acquire() }
        try await Task.sleep(for: .milliseconds(50))

        let depthBefore = await limiter.queueDepth
        #expect(depthBefore == 2)
        await limiter.cancelAll()
        let depthAfter = await limiter.queueDepth
        #expect(depthAfter == 0)

        let pos1 = await task1.value
        let pos2 = await task2.value
        #expect(pos1 == -1)
        #expect(pos2 == -1)
    }

    @Test("cancelAll does not affect active runs")
    func cancelAllDoesNotAffectActiveRuns() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)
        _ = await limiter.acquire()
        _ = await limiter.acquire()

        _ = Task { await limiter.acquire() }
        try await Task.sleep(for: .milliseconds(50))

        await limiter.cancelAll()
        let activeCount = await limiter.activeRunCount
        #expect(activeCount == 2)
    }
}
