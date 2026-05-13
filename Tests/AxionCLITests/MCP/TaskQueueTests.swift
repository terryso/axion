import XCTest
@testable import AxionCLI

// [P0] ATDD GREEN-PHASE — Story 6.1 AC3 (TaskQueue serialization)

/// Actor to safely track test execution state across concurrent closures.
actor TestCounter {
    private var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
    func decrement() { value -= 1 }
    var current: Int { value }
}

actor OrderTracker {
    private var items: [Int] = []
    func append(_ item: Int) { items.append(item) }
    var values: [Int] { items }
}

final class TaskQueueTests: XCTestCase {

    // MARK: - Serial execution

    func test_taskQueue_executesSingleTask() async throws {
        let queue = TaskQueue()
        let counter = TestCounter()

        await queue.enqueue {
            let _ = await counter.increment()
        }

        try await Task.sleep(for: .milliseconds(100))
        let count = await counter.current
        XCTAssertEqual(count, 1)
    }

    func test_taskQueue_executesMultipleTasksInOrder() async throws {
        let queue = TaskQueue()
        let tracker = OrderTracker()

        await queue.enqueue { await tracker.append(1) }
        await queue.enqueue { await tracker.append(2) }
        await queue.enqueue { await tracker.append(3) }

        try await Task.sleep(for: .milliseconds(300))
        let order = await tracker.values
        XCTAssertEqual(order, [1, 2, 3])
    }

    // MARK: - Concurrency

    func test_taskQueue_serializesConcurrentRequests() async throws {
        let queue = TaskQueue()
        let activeCount = TestCounter()
        let maxTracker = MaxTracker()

        await queue.enqueue {
            let _ = await activeCount.increment()
            await maxTracker.record(await activeCount.current)
            try? await Task.sleep(for: .milliseconds(100))
            await activeCount.decrement()
        }
        await queue.enqueue {
            let _ = await activeCount.increment()
            await maxTracker.record(await activeCount.current)
            try? await Task.sleep(for: .milliseconds(100))
            await activeCount.decrement()
        }
        await queue.enqueue {
            let _ = await activeCount.increment()
            await maxTracker.record(await activeCount.current)
            try? await Task.sleep(for: .milliseconds(100))
            await activeCount.decrement()
        }

        try await Task.sleep(for: .milliseconds(600))
        let maxActive = await maxTracker.value
        XCTAssertEqual(maxActive, 1, "Only one task should execute at a time")
    }

    // MARK: - Graceful shutdown

    func test_taskQueue_gracefulShutdown_waitsForRunningTask() async throws {
        let queue = TaskQueue()
        let counter = TestCounter()

        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(150))
            let _ = await counter.increment()
        }

        // Give the enqueued task time to start executing
        try await Task.sleep(for: .milliseconds(50))

        // Shutdown should wait for the running task to complete
        await queue.gracefulShutdown()

        let count = await counter.current
        XCTAssertEqual(count, 1, "Running task should complete before shutdown returns")
    }

    func test_taskQueue_gracefulShutdown_cancelsPendingTasks() async throws {
        let queue = TaskQueue()
        let tracker = OrderTracker()

        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(100))
            await tracker.append(1)
        }
        await queue.enqueue {
            await tracker.append(2)
        }

        // Shutdown immediately — first task is running, second is pending
        await queue.gracefulShutdown()

        // Give extra time to ensure pending task doesn't run
        try await Task.sleep(for: .milliseconds(200))
        let order = await tracker.values
        XCTAssertEqual(order, [1], "Only the running task should complete; pending should be cancelled")
    }
}

actor MaxTracker {
    private var maxValue = 0
    func record(_ value: Int) {
        maxValue = max(maxValue, value)
    }
    var value: Int { maxValue }
}
