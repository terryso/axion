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
}
