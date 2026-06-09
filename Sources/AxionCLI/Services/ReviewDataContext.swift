import Foundation
import OpenAgentSDK

/// Thread-safe box for sharing agent + messages with ReviewScheduler.
final class ReviewDataContext: @unchecked Sendable {
    private let lock = NSLock()
    private var _agent: Agent?
    private var _messages: [SDKMessage] = []
    private var _reviewOrchestrator: (any ReviewOrchestrating)?
    private var _messagesReady = false

    var agent: Agent? {
        lock.lock()
        defer { lock.unlock() }
        return _agent
    }

    var messages: [SDKMessage] {
        lock.lock()
        defer { lock.unlock() }
        return _messages
    }

    var reviewOrchestrator: (any ReviewOrchestrating)? {
        lock.lock()
        defer { lock.unlock() }
        return _reviewOrchestrator
    }

    /// Whether post-stream messages have been written.
    var messagesReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _messagesReady
    }

    func update(agent: Agent, messages: [SDKMessage], reviewOrchestrator: (any ReviewOrchestrating)?) {
        lock.lock()
        _agent = agent
        _messages = messages
        _reviewOrchestrator = reviewOrchestrator
        _messagesReady = !messages.isEmpty
        lock.unlock()
    }

    /// Wait until post-stream messages are available (max 5 seconds).
    func waitForMessages() async -> [SDKMessage] {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if readMessagesReady() { return readMessages() }
            try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        return readMessages()
    }

    // Synchronous accessors for use from async waitForMessages
    private func readMessagesReady() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _messagesReady
    }

    private func readMessages() -> [SDKMessage] {
        lock.lock()
        defer { lock.unlock() }
        return _messages
    }
}
