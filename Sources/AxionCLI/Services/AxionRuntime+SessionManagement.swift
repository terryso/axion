import Foundation
import OpenAgentSDK

import AxionCore

extension AxionRuntime {
    // MARK: - Session Lifecycle

    func createSession(task: String, config: AxionConfig) throws -> String {
        let sid = executor.generateRunId()
        sessionId = sid
        createdAt = Date()
        try writeAxionState(
            sessionId: sid, status: AxionRunState.created.rawValue,
            totalSteps: 0, durationMs: 0
        )
        return sid
    }

    // MARK: - Session Queries

    func listSessions(limit: Int? = nil) async throws -> [SessionInfo] {
        let metadataList = try await sessionStore.list(limit: limit)
        return metadataList.map { md in
            let overlay = loadOverlay(sessionId: md.id)
            return SessionInfo(
                sessionId: md.id,
                cwd: md.cwd,
                model: md.model,
                createdAt: md.createdAt,
                updatedAt: md.updatedAt,
                messageCount: md.messageCount,
                summary: md.summary ?? md.firstPrompt,
                status: overlay?.status ?? "unknown",
                totalSteps: overlay?.totalSteps ?? 0,
                durationMs: overlay?.durationMs
            )
        }
    }

    // MARK: - Axion State Persistence

    /// Visible for testing — writes axion-state.json for a session.
    func writeAxionState(sessionId: String, status: String, totalSteps: Int, durationMs: Int) throws {
        let sessionDir = (sessionsDir as NSString).appendingPathComponent(sessionId)
        try FileManager.default.createDirectory(
            atPath: sessionDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let overlay = AxionStateOverlay(
            status: status,
            totalSteps: totalSteps,
            durationMs: durationMs,
            updatedAt: axionISO8601Formatter.string(from: Date())
        )
        let data = try axionSortedEncoder.encode(overlay)
        let statePath = (sessionDir as NSString).appendingPathComponent("axion-state.json")
        FileManager.default.createFile(
            atPath: statePath,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        )
    }

    func loadOverlay(sessionId: String) -> AxionStateOverlay? {
        let statePath = ((sessionsDir as NSString).appendingPathComponent(sessionId) as NSString)
            .appendingPathComponent("axion-state.json")
        return loadDecodableFile(statePath, as: AxionStateOverlay.self)
    }

    /// Save firstPrompt into the session transcript so `sessions` can display the task.
    /// Re-reads the existing transcript, injects firstPrompt, and saves back.
    func saveSessionFirstPrompt(sessionId: String, task: String) async throws {
        let transcriptPath = ((sessionsDir as NSString).appendingPathComponent(sessionId) as NSString)
            .appendingPathComponent("transcript.json")
        guard let data = FileManager.default.contents(atPath: transcriptPath),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var metadata = dict["metadata"] as? [String: Any]
        else { return }

        if metadata["firstPrompt"] == nil {
            metadata["firstPrompt"] = task
            dict["metadata"] = metadata
            if let updated = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                FileManager.default.createFile(atPath: transcriptPath, contents: updated, attributes: [.posixPermissions: 0o600])
            }
        }
    }
}
