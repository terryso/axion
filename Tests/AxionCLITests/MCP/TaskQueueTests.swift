import Testing
@testable import AxionCLI

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

@Suite("TaskQueue")
struct TaskQueueTests {

    @Test("executes single task")
    func executesSingleTask() async throws {
        let queue = TaskQueue()
        let counter = TestCounter()

        await queue.enqueue {
            let _ = await counter.increment()
        }

        try await Task.sleep(for: .milliseconds(100))
        let count = await counter.current
        #expect(count == 1)
    }

    @Test("executes multiple tasks in order")
    func executesMultipleTasksInOrder() async throws {
        let queue = TaskQueue()
        let tracker = OrderTracker()

        await queue.enqueue { await tracker.append(1) }
        await queue.enqueue { await tracker.append(2) }
        await queue.enqueue { await tracker.append(3) }

        try await Task.sleep(for: .milliseconds(300))
        let order = await tracker.values
        #expect(order == [1, 2, 3])
    }

    @Test("serializes concurrent requests")
    func serializesConcurrentRequests() async throws {
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
        #expect(maxActive == 1)
    }

    @Test("graceful shutdown waits for running task")
    func gracefulShutdownWaitsForRunningTask() async throws {
        let queue = TaskQueue()
        let counter = TestCounter()

        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(150))
            let _ = await counter.increment()
        }

        try await Task.sleep(for: .milliseconds(50))

        await queue.gracefulShutdown()

        let count = await counter.current
        #expect(count == 1)
    }

    @Test("graceful shutdown cancels pending tasks")
    func gracefulShutdownCancelsPendingTasks() async throws {
        let queue = TaskQueue()
        let tracker = OrderTracker()

        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(100))
            await tracker.append(1)
        }
        await queue.enqueue {
            await tracker.append(2)
        }

        await queue.gracefulShutdown()

        try await Task.sleep(for: .milliseconds(200))
        let order = await tracker.values
        #expect(order == [1])
    }
}

actor MaxTracker {
    private var maxValue = 0
    func record(_ value: Int) {
        maxValue = max(maxValue, value)
    }
    var value: Int { maxValue }
}
