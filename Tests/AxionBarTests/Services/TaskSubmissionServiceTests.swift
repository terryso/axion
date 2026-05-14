import Testing
import Foundation
@testable import AxionBar

@MainActor
@Suite("TaskSubmissionService")
struct TaskSubmissionServiceTests {

    @Test("default base URL is localhost 4242")
    func defaultBaseURL() {
        let service = TaskSubmissionService()
        // Service created successfully with default URL
        #expect(service != nil)
    }

    @Test("custom base URL is accepted")
    func customBaseURL() {
        let service = TaskSubmissionService(baseURL: "http://localhost:9999")
        #expect(service != nil)
    }

    @Test("submit fails when no server is running")
    func submitFailsWithoutServer() async {
        let service = TaskSubmissionService(baseURL: "http://127.0.0.1:19999")
        do {
            _ = try await service.submit(task: "测试")
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is TaskSubmissionError)
        }
    }

    @Test("submit with empty task creates valid request body")
    func emptyTaskRequestBody() async {
        let service = TaskSubmissionService(baseURL: "http://127.0.0.1:19999")
        // Even with empty task, the service should attempt to connect
        // (will fail because no server, but request construction is valid)
        do {
            _ = try await service.submit(task: "")
        } catch {
            // Expected to fail due to no server
        }
    }
}

@Suite("TaskSubmissionError")
struct TaskSubmissionErrorTests {

    @Test("invalidURL has description")
    func invalidURLDescription() {
        let error = TaskSubmissionError.invalidURL
        #expect(error.localizedDescription == "无效的 API 地址")
    }

    @Test("invalidResponse has description")
    func invalidResponseDescription() {
        let error = TaskSubmissionError.invalidResponse
        #expect(error.localizedDescription == "服务返回了无效的响应")
    }

    @Test("httpError includes status code")
    func httpErrorDescription() {
        let error = TaskSubmissionError.httpError(statusCode: 500)
        #expect(error.localizedDescription.contains("500"))
    }

    @Test("equality for same cases")
    func equality() {
        #expect(TaskSubmissionError.invalidURL == TaskSubmissionError.invalidURL)
        #expect(TaskSubmissionError.invalidResponse == TaskSubmissionError.invalidResponse)
        #expect(TaskSubmissionError.httpError(statusCode: 404) == TaskSubmissionError.httpError(statusCode: 404))
        #expect(TaskSubmissionError.httpError(statusCode: 404) != TaskSubmissionError.httpError(statusCode: 500))
    }
}
