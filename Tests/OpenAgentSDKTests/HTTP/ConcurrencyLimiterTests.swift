import XCTest
@testable import OpenAgentSDK

final class ConcurrencyLimiterTests: XCTestCase {

    // MARK: - Acquire & Release

    func testTryAcquireWithinCapacity() async {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)
        let result = await limiter.tryAcquire()
        XCTAssertTrue(result)
        let count = await limiter.activeRunCount
        XCTAssertEqual(count, 1)
    }

    func testTryAcquireAtCapacity() async {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.tryAcquire()
        let result = await limiter.tryAcquire()
        XCTAssertFalse(result)
    }

    func testAcquireSuspendsUntilRelease() async {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        await limiter.acquire()

        let expectation = expectation(description: "acquire resumed")
        _Concurrency.Task {
            await limiter.acquire()
            expectation.fulfill()
        }

        try? await _Concurrency.Task.sleep(for: .milliseconds(50))
        let depth = await limiter.queueDepth
        XCTAssertEqual(depth, 1)

        await limiter.release()
        await fulfillment(of: [expectation], timeout: 2)
        let count = await limiter.activeRunCount
        XCTAssertEqual(count, 1)
    }

    func testReleaseFreesSlot() async {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)
        await limiter.acquire()
        await limiter.acquire()
        let countBefore = await limiter.activeRunCount
        XCTAssertEqual(countBefore, 2)

        await limiter.release()
        let countAfter = await limiter.activeRunCount
        XCTAssertEqual(countAfter, 1)

        let canAcquire = await limiter.tryAcquire()
        XCTAssertTrue(canAcquire)
    }

    // MARK: - Queue Depth

    func testQueueDepthReflectsWaitingCount() async {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        await limiter.acquire()

        _Concurrency.Task { await limiter.acquire() }
        _Concurrency.Task { await limiter.acquire() }

        try? await _Concurrency.Task.sleep(for: .milliseconds(100))
        let depth = await limiter.queueDepth
        XCTAssertGreaterThanOrEqual(depth, 1)
    }

    // MARK: - Default Configuration

    func testDefaultMaxConcurrent() async {
        let limiter = ConcurrencyLimiter()
        let maxConcurrent = await limiter.maxConcurrent
        XCTAssertEqual(maxConcurrent, 5)
    }

    func testIsAvailableWhenBelowCapacity() async {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)
        let available = await limiter.isAvailable
        XCTAssertTrue(available)
    }

    func testIsNotAvailableAtCapacity() async {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        await limiter.acquire()
        let available = await limiter.isAvailable
        XCTAssertFalse(available)
    }
}
