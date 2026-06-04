import Foundation
import OpenAgentSDK

import AxionCore

/// Thread-safe mutable flag for handler-to-runtime state propagation.
/// Handlers (e.g. SeatMonitorHandler) set this; AxionRuntime reads it before dispatching subsequent events.
final class ExternallyModifiedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    func setTrue() {
        lock.lock()
        _value = true
        lock.unlock()
    }
}

struct EventHandlerContext: Sendable {
    let sessionId: String?
    let config: AxionConfig
    let eventBus: EventBus?
    let externallyModified: Bool
    let externallyModifiedFlag: ExternallyModifiedFlag?
    let takeoverEvent: RunMemoryProcessor.TakeoverEventContext?
    let runCompleteContext: RunCompleteContext?
    let sessionStore: SessionStore
    let chatId: Int64?
    let shouldReviewMemory: Bool
    let shouldReviewSkills: Bool

    init(
        sessionId: String?,
        config: AxionConfig,
        eventBus: EventBus?,
        externallyModified: Bool,
        externallyModifiedFlag: ExternallyModifiedFlag?,
        takeoverEvent: RunMemoryProcessor.TakeoverEventContext?,
        runCompleteContext: RunCompleteContext?,
        sessionStore: SessionStore,
        chatId: Int64? = nil,
        shouldReviewMemory: Bool = false,
        shouldReviewSkills: Bool = false
    ) {
        self.sessionId = sessionId
        self.config = config
        self.eventBus = eventBus
        self.externallyModified = externallyModified
        self.externallyModifiedFlag = externallyModifiedFlag
        self.takeoverEvent = takeoverEvent
        self.runCompleteContext = runCompleteContext
        self.sessionStore = sessionStore
        self.chatId = chatId
        self.shouldReviewMemory = shouldReviewMemory
        self.shouldReviewSkills = shouldReviewSkills
    }
}
