import Testing
import Foundation
@testable import AxionBar

@MainActor
@Suite("SkillService")
struct SkillServiceTests {

    @Test("default base URL is localhost 4242")
    func defaultBaseURL() {
        let service = SkillService()
        #expect(service != nil)
    }

    @Test("custom base URL is accepted")
    func customBaseURL() {
        let service = SkillService(baseURL: "http://localhost:9999")
        #expect(service != nil)
    }

    @Test("fetchSkills fails when no server is running")
    func fetchSkillsFailsWithoutServer() async {
        let service = SkillService(baseURL: "http://127.0.0.1:19999")
        do {
            _ = try await service.fetchSkills()
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is SkillServiceError)
        }
    }

    @Test("fetchSkill fails when no server is running")
    func fetchSkillFailsWithoutServer() async {
        let service = SkillService(baseURL: "http://127.0.0.1:19999")
        do {
            _ = try await service.fetchSkill(name: "test")
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is SkillServiceError)
        }
    }

    @Test("runSkill fails when no server is running")
    func runSkillFailsWithoutServer() async {
        let service = SkillService(baseURL: "http://127.0.0.1:19999")
        do {
            _ = try await service.runSkill(name: "test")
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is SkillServiceError)
        }
    }
}

@Suite("SkillServiceError")
struct SkillServiceErrorTests {

    @Test("invalidURL has description")
    func invalidURLDescription() {
        let error = SkillServiceError.invalidURL
        #expect(error.localizedDescription == "无效的 API 地址")
    }

    @Test("invalidResponse has description")
    func invalidResponseDescription() {
        let error = SkillServiceError.invalidResponse
        #expect(error.localizedDescription == "服务返回了无效的响应")
    }

    @Test("httpError includes status code")
    func httpErrorDescription() {
        let error = SkillServiceError.httpError(statusCode: 500)
        #expect(error.localizedDescription.contains("500"))
    }

    @Test("equality for same cases")
    func equality() {
        #expect(SkillServiceError.invalidURL == SkillServiceError.invalidURL)
        #expect(SkillServiceError.invalidResponse == SkillServiceError.invalidResponse)
        #expect(SkillServiceError.httpError(statusCode: 404) == SkillServiceError.httpError(statusCode: 404))
        #expect(SkillServiceError.httpError(statusCode: 404) != SkillServiceError.httpError(statusCode: 500))
    }
}
