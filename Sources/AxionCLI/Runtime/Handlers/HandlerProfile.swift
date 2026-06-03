import Foundation
import OpenAgentSDK

import AxionCore

/// Describes which handlers an execution context needs. Call `buildHandlers()` to get the
/// complete, context-appropriate handler list — all call sites (CLI, Gateway, API) use this
/// so handler changes only need to be made in one place.
struct HandlerProfile: Sendable {
    enum Context: Sendable {
        /// `axion run` / `axion resume` — full desktop experience with visual delta, seat monitor
        case cli
        /// Gateway TG/HTTP — review + memory enabled, no desktop-specific handlers
        case gateway
        /// API skill execution — minimal: cost + trace only
        case api
    }

    let context: Context
    let config: AxionConfig
    let memoryDir: String
    let traceDir: String
    let noMemory: Bool
    let noReview: Bool
    let noVisualDelta: Bool
    let reviewDataContext: ReviewDataContext?

    /// Build the handler list for this profile. Callers may append domain-specific handlers
    /// (e.g. TGEventHandler, CuratorScheduler) after this call.
    func buildHandlers() -> [any EventHandler] {
        var handlers: [any EventHandler] = []

        // All contexts: cost + trace + llm-info + memory
        handlers.append(CostEventHandler())
        handlers.append(TraceEventHandler(traceDir: traceDir))
        handlers.append(LLMInfoHandler())

        if context != .api {
            handlers.append(MemoryProcessingHandler(noMemory: noMemory, memoryDir: memoryDir))
        }

        // CLI-only: visual delta + seat monitor
        if context == .cli {
            handlers.append(VisualDeltaHandler(noVisualDelta: noVisualDelta))
            handlers.append(SeatMonitorHandler(sharedSeatMode: config.sharedSeatMode))
        }

        // CLI + Gateway: review (skip for API and when explicitly disabled)
        if context != .api && !noReview && !noMemory, let rdc = reviewDataContext {
            handlers.append(ReviewScheduler(
                noReview: noReview,
                noMemory: noMemory,
                reviewDataContext: rdc,
                traceDir: traceDir,
                memoryDir: memoryDir
            ))
        }

        return handlers
    }
}
