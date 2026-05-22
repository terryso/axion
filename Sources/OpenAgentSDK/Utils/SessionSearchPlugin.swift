import Foundation

/// A self-evolution plugin that enables full-text search across all persisted sessions.
///
/// Supports three search modes (discover, scroll, browse) via the ``SessionSearchEngine``.
/// On `.prefetch`, performs an auto-search if `currentQuery` is non-nil and auto-search
/// is enabled in config. Returns tool schemas for the LLM to invoke search on demand.
public actor SessionSearchPlugin: SelfEvolutionPlugin {

    public nonisolated let name: String = "session-search"
    public nonisolated let supportedPhases: Set<PluginLifecyclePhase> = [.initialize, .prefetch]

    private let searchEngine: SessionSearchEngine
    private let pluginConfig: EvolutionPluginConfig?
    private var store: SessionStore?

    public init(config: EvolutionPluginConfig? = nil) {
        self.pluginConfig = config

        let ctxWindow: Int
        if let str = config?.config?["contextWindow"], let val = Int(str) {
            ctxWindow = val
        } else {
            ctxWindow = SessionSearchEngine.defaultDiscoverContextWindow
        }
        self.searchEngine = SessionSearchEngine(discoverContextWindow: ctxWindow)
    }

    public func initialize(sessionId: String) async throws {
        if store == nil {
            if let dir = pluginConfig?.config?["sessionsDir"] {
                store = SessionStore(sessionsDir: dir)
            } else {
                store = SessionStore()
            }
        }
    }

    public func onPhase(_ phase: PluginLifecyclePhase, context: PluginContext) async throws -> PluginResult {
        switch phase {
        case .prefetch:
            guard let store else { return .none }

            let autoSearch = pluginConfig?.config?["autoSearch"] ?? "true"

            if autoSearch == "true", let query = context.currentQuery, !query.isEmpty {
                let searchQuery = SessionSearchQuery(mode: .discover, query: query, limit: maxResults)
                do {
                    let searchResults = try await searchEngine.search(searchQuery, store: store)
                    if !searchResults.isEmpty {
                        return .systemPromptBlock(formatSearchResults(searchResults))
                    }
                } catch {
                    Logger.shared.warn("SessionSearchPlugin", "auto_search_failed", data: [
                        "error": error.localizedDescription
                    ])
                }
            }

            return .toolSchemas(SendableToolSchemaList(schemas: [sessionSearchToolSchema()]))

        case .initialize:
            return .none

        default:
            return .none
        }
    }

    public func shutdown() async {
        store = nil
    }

    // MARK: - Config Helpers

    private var maxResults: Int {
        guard let str = pluginConfig?.config?["maxResults"], let val = Int(str) else { return 5 }
        return val
    }

    // MARK: - Tool Schema

    private func sessionSearchToolSchema() -> [String: Any] {
        return [
            "type": "object",
            "title": "session_search",
            "description": "Search across session transcripts",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Search keywords for discover mode"
                ],
                "session_id": [
                    "type": "string",
                    "description": "Session ID for scroll mode"
                ],
                "mode": [
                    "type": "string",
                    "enum": ["discover", "scroll", "browse"],
                    "description": "Search mode"
                ]
            ],
            "required": ["mode"]
        ]
    }

    // MARK: - Formatting

    private func formatSearchResults(_ results: [SessionSearchResult]) -> String {
        var lines = ["[Session Search Results]"]
        for result in results {
            if let sessionId = result.matchedSessionId {
                lines.append("- Session: \(sessionId)")
            }
            for msg in result.messages {
                let preview = String((msg.content ?? "").prefix(200))
                lines.append("  [\(msg.role.rawValue)] \(preview)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
