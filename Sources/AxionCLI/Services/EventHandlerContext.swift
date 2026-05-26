import Foundation
import OpenAgentSDK

import AxionCore

struct EventHandlerContext: Sendable {
    let sessionId: String?
    let config: AxionConfig
    let eventBus: EventBus?
    let externallyModified: Bool
    let takeoverEvent: RunMemoryProcessor.TakeoverEventContext?
    let runCompleteContext: RunCompleteContext?
    let sessionStore: SessionStore
}
