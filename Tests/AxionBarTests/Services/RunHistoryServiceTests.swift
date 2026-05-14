import Testing
import Foundation
@testable import AxionBar

@MainActor
@Suite("RunHistoryService")
struct RunHistoryServiceTests {

    @Test("default initialization succeeds")
    func defaultInit() {
        let service = RunHistoryService()
        #expect(service != nil)
    }

    @Test("fetchHistory fails when no server is running")
    func fetchHistoryFailsWithoutServer() async {
        let service = RunHistoryService(baseURL: "http://127.0.0.1:19999")
        do {
            _ = try await service.fetchHistory(limit: 20)
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is RunHistoryError)
        }
    }

    @Test("fetchRun fails when no server is running")
    func fetchRunFailsWithoutServer() async {
        let service = RunHistoryService(baseURL: "http://127.0.0.1:19999")
        do {
            _ = try await service.fetchRun(runId: "test-id")
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is RunHistoryError)
        }
    }
}

@Suite("RunHistoryError")
struct RunHistoryErrorTests {

    @Test("invalidURL has description")
    func invalidURLDescription() {
        let error = RunHistoryError.invalidURL
        #expect(error.localizedDescription == "无效的 API 地址")
    }

    @Test("httpError includes status code")
    func httpErrorDescription() {
        let error = RunHistoryError.httpError(statusCode: 404)
        #expect(error.localizedDescription.contains("404"))
    }

    @Test("equality for same cases")
    func equality() {
        #expect(RunHistoryError.invalidURL == RunHistoryError.invalidURL)
        #expect(RunHistoryError.invalidResponse == RunHistoryError.invalidResponse)
        #expect(RunHistoryError.httpError(statusCode: 404) == RunHistoryError.httpError(statusCode: 404))
        #expect(RunHistoryError.httpError(statusCode: 404) != RunHistoryError.httpError(statusCode: 500))
    }
}
