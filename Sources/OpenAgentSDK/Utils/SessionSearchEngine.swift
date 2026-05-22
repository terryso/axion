import Foundation

/// Pure computation engine for session search.
///
/// Performs discover (keyword), scroll (context window), and browse (list)
/// operations against a ``SessionStore``. All modes are pure database/file
/// operations with zero LLM calls.
public struct SessionSearchEngine: Sendable {

    /// Default context window half-size for discover mode (±5 messages).
    public static let defaultDiscoverContextWindow = 5

    /// Default context window half-size for scroll mode (±10 messages).
    public static let defaultScrollContextWindow = 10

    /// Context window half-size used for discover mode results.
    public let discoverContextWindow: Int

    /// Context window half-size used for scroll mode results.
    public let scrollContextWindow: Int

    public init(
        discoverContextWindow: Int = defaultDiscoverContextWindow,
        scrollContextWindow: Int = defaultScrollContextWindow
    ) {
        self.discoverContextWindow = discoverContextWindow
        self.scrollContextWindow = scrollContextWindow
    }

    /// Perform a search using the given query and store.
    /// - Parameters:
    ///   - query: A validated ``SessionSearchQuery``.
    ///   - store: The ``SessionStore`` to search against.
    /// - Returns: Array of ``SessionSearchResult`` matching the query.
    /// - Throws: ``SDKError/invalidConfiguration`` if the query is invalid,
    ///           or rethrows store errors.
    public func search(_ query: SessionSearchQuery, store: SessionStore) async throws -> [SessionSearchResult] {
        try query.validate()

        switch query.mode {
        case .discover:
            return try await discover(query: query, store: store)
        case .scroll:
            return try await scroll(query: query, store: store)
        case .browse:
            return try await browse(query: query, store: store)
        }
    }

    // MARK: - Discover

    private func discover(query: SessionSearchQuery, store: SessionStore) async throws -> [SessionSearchResult] {
        guard let searchTerm = query.query else {
            return []
        }

        let sessions = try await store.list()
        let lowercasedSearch = searchTerm.lowercased()
        var results: [SessionSearchResult] = []

        for sessionMeta in sessions {
            guard let sessionData = try await store.load(sessionId: sessionMeta.id) else {
                continue
            }

            let typedMessages = sessionData.messages.compactMap { SessionMessage(from: $0) }

            // Find first matching message index
            guard let matchIndex = typedMessages.firstIndex(where: { msg in
                msg.content?.lowercased().contains(lowercasedSearch) ?? false
            }) else {
                continue
            }

            let windowStart = max(0, matchIndex - discoverContextWindow)
            let windowEnd = min(typedMessages.count - 1, matchIndex + discoverContextWindow)
            let windowMessages = Array(typedMessages[windowStart...windowEnd])

            let totalMatchCount = typedMessages.filter { msg in
                msg.content?.lowercased().contains(lowercasedSearch) ?? false
            }.count

            // Check if there are more sessions beyond this one
            let sessionIndex = sessions.firstIndex(where: { $0.id == sessionMeta.id }) ?? 0
            let remainingSessions = sessions.count - sessionIndex - 1
            let hasMoreResults = results.count + 1 >= query.limit && remainingSessions > 0

            results.append(SessionSearchResult(
                mode: .discover,
                matchedSessionId: sessionMeta.id,
                matchedMessageIndex: matchIndex,
                messages: windowMessages,
                totalMatches: totalMatchCount,
                hasMore: hasMoreResults
            ))

            if results.count >= query.limit {
                break
            }
        }

        return results
    }

    // MARK: - Scroll

    private func scroll(query: SessionSearchQuery, store: SessionStore) async throws -> [SessionSearchResult] {
        guard let sessionId = query.sessionId else { return [] }

        guard let sessionData = try await store.load(sessionId: sessionId) else {
            return []
        }

        let typedMessages = sessionData.messages.compactMap { SessionMessage(from: $0) }
        let centerIndex = query.aroundMessageIndex ?? 0

        let clampedCenter = max(0, min(centerIndex, max(0, typedMessages.count - 1)))
        let windowStart = max(0, clampedCenter - scrollContextWindow)
        let windowEnd = min(typedMessages.count - 1, clampedCenter + scrollContextWindow)

        let windowMessages: [SessionMessage]
        if typedMessages.isEmpty {
            windowMessages = []
        } else {
            windowMessages = Array(typedMessages[windowStart...windowEnd])
        }

        return [SessionSearchResult(
            mode: .scroll,
            matchedSessionId: sessionId,
            matchedMessageIndex: clampedCenter,
            messages: windowMessages,
            totalMatches: nil,
            hasMore: false
        )]
    }

    // MARK: - Browse

    private func browse(query: SessionSearchQuery, store: SessionStore) async throws -> [SessionSearchResult] {
        // Query one extra to detect whether more results exist beyond the limit
        let allSessions = try await store.list(limit: query.limit + 1)
        let hasMoreResults = allSessions.count > query.limit
        let sessions = hasMoreResults ? Array(allSessions.prefix(query.limit)) : allSessions

        return sessions.enumerated().map { index, meta in
            SessionSearchResult(
                mode: .browse,
                matchedSessionId: meta.id,
                matchedMessageIndex: nil,
                messages: [],
                totalMatches: nil,
                hasMore: index == sessions.count - 1 && hasMoreResults
            )
        }
    }
}
