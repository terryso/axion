import Foundation

/// Search mode for session search operations.
///
/// Maps to the Hermes `session_search` API patterns:
/// - `discover`: keyword search across all sessions
/// - `scroll`: browse messages around a specific point in one session
/// - `browse`: list recent sessions
public enum SessionSearchMode: String, Codable, Sendable, Equatable, CaseIterable {
    case discover
    case scroll
    case browse
}

/// A validated search query for session search operations.
///
/// Validation rules per mode:
/// - `discover`: requires non-nil `query`
/// - `scroll`: requires non-nil `sessionId`
/// - `browse`: requires nil `query` and nil `sessionId`
public struct SessionSearchQuery: Sendable, Equatable {
    /// The search mode.
    public let mode: SessionSearchMode
    /// Search keywords. Required for `discover`, must be nil for `browse`.
    public let query: String?
    /// Target session. Required for `scroll`, must be nil for `browse`.
    public let sessionId: String?
    /// Center index for `scroll` mode. Nil unless scrolling.
    public let aroundMessageIndex: Int?
    /// Maximum number of results. Defaults to 10.
    public let limit: Int

    public init(
        mode: SessionSearchMode,
        query: String? = nil,
        sessionId: String? = nil,
        aroundMessageIndex: Int? = nil,
        limit: Int = 10
    ) {
        self.mode = mode
        self.query = query
        self.sessionId = sessionId
        self.aroundMessageIndex = aroundMessageIndex
        self.limit = limit
    }

    /// Validate the query fields against mode requirements.
    /// - Throws: `SDKError.invalidConfiguration` for invalid field combinations.
    public func validate() throws {
        switch mode {
        case .discover:
            guard query != nil else {
                throw SDKError.invalidConfiguration("discover mode requires a non-nil query")
            }
        case .scroll:
            guard sessionId != nil else {
                throw SDKError.invalidConfiguration("scroll mode requires a non-nil sessionId")
            }
        case .browse:
            if query != nil {
                throw SDKError.invalidConfiguration("browse mode requires nil query")
            }
            if sessionId != nil {
                throw SDKError.invalidConfiguration("browse mode requires nil sessionId")
            }
        }
    }
}

/// A single search result from a session search operation.
///
/// Content varies by mode:
/// - `discover`: contains matching message and surrounding context (±5 messages)
/// - `scroll`: contains messages around `aroundMessageIndex`
/// - `browse`: contains `matchedSessionId` with summary, `messages` is empty
public struct SessionSearchResult: Sendable, Equatable {
    /// The mode that produced this result.
    public let mode: SessionSearchMode
    /// The session ID that matched. Nil when no specific session is targeted.
    public let matchedSessionId: String?
    /// Index of the primary matched message. Nil for browse or when not applicable.
    public let matchedMessageIndex: Int?
    /// Context window of messages around the match. Empty for browse mode.
    public let messages: [SessionMessage]
    /// Total matches found. Nil for scroll/browse modes.
    public let totalMatches: Int?
    /// Whether more results are available beyond this batch.
    public let hasMore: Bool

    public init(
        mode: SessionSearchMode,
        matchedSessionId: String? = nil,
        matchedMessageIndex: Int? = nil,
        messages: [SessionMessage] = [],
        totalMatches: Int? = nil,
        hasMore: Bool = false
    ) {
        self.mode = mode
        self.matchedSessionId = matchedSessionId
        self.matchedMessageIndex = matchedMessageIndex
        self.messages = messages
        self.totalMatches = totalMatches
        self.hasMore = hasMore
    }
}
