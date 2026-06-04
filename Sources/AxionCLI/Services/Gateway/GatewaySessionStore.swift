import Foundation

import AxionCore
import OpenAgentSDK

/// Persisted state for a single chatId, tracking session history and review turn counting.
struct ChatSessionState: Codable, Sendable, Equatable {
    var sessionIds: [String]
    var userTurnCount: Int
    var turnsSinceMemory: Int
    var lastActivityAt: String
}

/// Root container for gateway-sessions.json — uses String keys for chatId (Codable compatibility).
private struct GatewaySessionsPayload: Codable, Equatable {
    var chatSessions: [String: ChatSessionState]
}

/// Actor that persists chatId → session state mappings to `gateway-sessions.json`.
/// Supports gateway restart recovery and transcript-based count hydration.
actor GatewaySessionStore {
    private var states: [Int64: ChatSessionState] = [:]
    private let filePath: String

    init(filePath: String) {
        self.filePath = filePath
    }

    // MARK: - Persistence

    func load() throws {
        guard FileManager.default.fileExists(atPath: filePath) else { return }
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let payload = try JSONDecoder().decode(GatewaySessionsPayload.self, from: data)
        states = [:]
        for (key, value) in payload.chatSessions {
            guard let chatId = Int64(key) else { continue }
            states[chatId] = value
        }
    }

    func save() throws {
        var payload = GatewaySessionsPayload(chatSessions: [:])
        for (chatId, state) in states {
            payload.chatSessions[String(chatId)] = state
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(payload)
        let url = URL(fileURLWithPath: filePath)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func saveSafely() {
        do {
            try save()
        } catch {
            fputs("[axion] GatewaySessionStore: failed to persist state: \(error.localizedDescription)\n", stderr)
        }
    }

    // MARK: - Access

    func state(for chatId: Int64) -> ChatSessionState? {
        states[chatId]
    }

    // MARK: - Mutation

    /// Record a new user turn for the given chatId. Called at enqueue time for non-resume tasks.
    func recordTurn(chatId: Int64, sessionId: String) {
        let now = ISO8601DateFormatter().string(from: Date())
        if var existing = states[chatId] {
            existing.userTurnCount += 1
            existing.turnsSinceMemory += 1
            if !sessionId.isEmpty && !existing.sessionIds.contains(sessionId) {
                existing.sessionIds.append(sessionId)
            }
            existing.lastActivityAt = now
            states[chatId] = existing
        } else {
            var sessionIds: [String] = []
            if !sessionId.isEmpty {
                sessionIds.append(sessionId)
            }
            states[chatId] = ChatSessionState(
                sessionIds: sessionIds,
                userTurnCount: 1,
                turnsSinceMemory: 1,
                lastActivityAt: now
            )
        }
        saveSafely()
    }

    /// Append a sessionId after execution completes (sessionId not known at enqueue time for new tasks).
    func recordSessionId(chatId: Int64, sessionId: String) {
        guard var existing = states[chatId] else { return }
        if !existing.sessionIds.contains(sessionId) {
            existing.sessionIds.append(sessionId)
            states[chatId] = existing
            saveSafely()
        }
    }

    /// Reset the memory review counter after a review triggers.
    func resetMemoryCounter(chatId: Int64) {
        guard var existing = states[chatId] else { return }
        existing.turnsSinceMemory = 0
        states[chatId] = existing
        saveSafely()
    }

    /// Clear all state for a chatId (e.g. /new command).
    func clearSession(chatId: Int64) {
        states.removeValue(forKey: chatId)
        saveSafely()
    }

    /// Recover counts from SessionStore transcripts when gateway-sessions.json has no entry for a chatId.
    /// Counts user role messages across all known sessions, applies `% nudgeInterval` to preserve cadence.
    func hydrateFromTranscripts(
        chatId: Int64,
        sessionIds: [String],
        sessionStore: SessionStore,
        nudgeInterval: Int
    ) async {
        var totalUserTurns = 0
        for sid in sessionIds {
            guard let data = try? await sessionStore.load(sessionId: sid) else { continue }
            for msg in data.messages {
                if let role = msg["role"] as? String, role == "user" {
                    totalUserTurns += 1
                }
            }
        }
        guard totalUserTurns > 0 else { return }

        let now = ISO8601DateFormatter().string(from: Date())
        states[chatId] = ChatSessionState(
            sessionIds: sessionIds,
            userTurnCount: totalUserTurns,
            turnsSinceMemory: totalUserTurns % nudgeInterval,
            lastActivityAt: now
        )
        saveSafely()
    }
}
