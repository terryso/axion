import AxionCore

protocol SessionListing: Sendable {
    func listSessions(limit: Int?) async throws -> [SessionInfo]
}
