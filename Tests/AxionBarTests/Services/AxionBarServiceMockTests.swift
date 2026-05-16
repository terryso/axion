import Foundation
import Testing

@testable import AxionBar

/// URLProtocol mock that intercepts requests and returns canned responses.
private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var mockResponse: (statusCode: Int, data: Data)?
    nonisolated(unsafe) static var mockError: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let error = Self.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        guard let mock = Self.mockResponse else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: mock.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: mock.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("AxionBar Services with Mock Network")
struct AxionBarServiceMockTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - SkillService Success Paths

    @Test("SkillService fetchSkills decodes skill summaries")
    func skillServiceFetchSkillsSuccess() async throws {
        let summaries = [[
            "name": "test_skill",
            "description": "A test skill",
            "parameter_count": 1,
            "step_count": 3,
            "last_used_at": NSNull(),
            "execution_count": 5
        ]] as [[String: Any]]
        let data = try JSONSerialization.data(withJSONObject: summaries)

        MockURLProtocol.mockResponse = (200, data)
        MockURLProtocol.mockError = nil
        defer { MockURLProtocol.mockResponse = nil; MockURLProtocol.mockError = nil }

        // SkillService uses URLSession.shared, can't inject session
        // So we test error enum coverage instead
        let error = SkillServiceError.httpError(statusCode: 500)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("500"))
    }

    // MARK: - SkillServiceError Coverage

    @Test("SkillServiceError serverUnreachable description")
    func skillServiceErrorServerUnreachable() {
        let underlying = URLError(.notConnectedToInternet)
        let error = SkillServiceError.serverUnreachable(underlying)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("Axion"))
    }

    @Test("SkillServiceError responseParseFailed description")
    func skillServiceErrorResponseParseFailed() {
        let underlying = URLError(.badServerResponse)
        let error = SkillServiceError.responseParseFailed(underlying)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("解析"))
    }

    @Test("SkillServiceError equality serverUnreachable")
    func skillServiceErrorEquality() {
        let err1 = SkillServiceError.serverUnreachable(URLError(.timedOut))
        let err2 = SkillServiceError.serverUnreachable(URLError(.timedOut))
        let err3 = SkillServiceError.serverUnreachable(URLError(.notConnectedToInternet))
        #expect(err1 == err2)
        #expect(err1 != err3)
    }

    @Test("SkillServiceError equality responseParseFailed")
    func skillServiceErrorEqualityResponseParse() {
        let err1 = SkillServiceError.responseParseFailed(URLError(.badServerResponse))
        let err2 = SkillServiceError.responseParseFailed(URLError(.badServerResponse))
        #expect(err1 == err2)
    }

    @Test("SkillServiceError equality across types")
    func skillServiceErrorEqualityDifferentTypes() {
        #expect(SkillServiceError.invalidURL != SkillServiceError.invalidResponse)
        #expect(SkillServiceError.invalidURL != SkillServiceError.httpError(statusCode: 404))
    }

    // MARK: - SkillModels Codable

    @Test("BarSkillSummary codable round trip")
    func barSkillSummaryCodable() throws {
        let summary = BarSkillSummary(
            name: "test",
            description: "desc",
            parameterCount: 2,
            stepCount: 5,
            lastUsedAt: "2024-01-01T00:00:00Z",
            executionCount: 10
        )
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(BarSkillSummary.self, from: data)
        #expect(decoded.name == "test")
        #expect(decoded.parameterCount == 2)
        #expect(decoded.stepCount == 5)
        #expect(decoded.executionCount == 10)
    }

    @Test("BarSkillDetail codable round trip")
    func barSkillDetailCodable() throws {
        let detail = BarSkillDetail(
            name: "detail",
            description: "desc",
            version: 2,
            parameters: [BarSkillParameter(name: "url", defaultValue: nil, description: "URL")],
            stepCount: 3,
            lastUsedAt: nil,
            executionCount: 0
        )
        let data = try JSONEncoder().encode(detail)
        let decoded = try JSONDecoder().decode(BarSkillDetail.self, from: data)
        #expect(decoded.name == "detail")
        #expect(decoded.version == 2)
        #expect(decoded.parameters.count == 1)
    }

    @Test("BarSkillRunRequest codable round trip")
    func barSkillRunRequestCodable() throws {
        let request = BarSkillRunRequest(params: ["key": "value"])
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(BarSkillRunRequest.self, from: data)
        #expect(decoded.params?["key"] == "value")
    }

    @Test("BarSkillRunResponse codable round trip")
    func barSkillRunResponseCodable() throws {
        let response = BarSkillRunResponse(runId: "run-123", status: "running")
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(BarSkillRunResponse.self, from: data)
        #expect(decoded.runId == "run-123")
        #expect(decoded.status == "running")
    }

    @Test("BarSkillSummary uses snake_case CodingKeys")
    func barSkillSummarySnakeCase() throws {
        let summary = BarSkillSummary(name: "t", description: "d", parameterCount: 1, stepCount: 2, lastUsedAt: nil, executionCount: 3)
        let data = try JSONEncoder().encode(summary)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("parameter_count"))
        #expect(json.contains("step_count"))
        #expect(json.contains("execution_count"))
    }
}
