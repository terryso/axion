import OpenAgentSDK

/// Protocol for event handlers that subscribe to specific AgentEvent types.
///
/// All handlers must be actors — AxionRuntime dispatches events in independent Tasks,
/// and actor isolation guarantees thread-safe mutable state.
protocol EventHandler: Actor {
    /// Unique identifier for logging and debugging.
    var identifier: String { get }

    /// Event types this handler subscribes to.
    /// Empty array means subscribe to all events.
    var subscribedEventTypes: [any AgentEvent.Type] { get }

    /// Handle a dispatched event.
    /// - Parameters:
    ///   - event: The AgentEvent that was emitted.
    ///   - context: Runtime context with session info, config, and state.
    func handle(_ event: any AgentEvent, context: EventHandlerContext) async
}
