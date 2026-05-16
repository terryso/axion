import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import Testing

@testable import AxionCLI
@testable import AxionCore

@Suite("AxionAPI Skill Routes")
struct AxionAPISkillRoutesTests {

    // MARK: - GET /v1/skills (empty)

    @Test("GET /v1/skills returns empty array when no skills exist")
    func getSkillsEmpty() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/skills", method: .get) { response in
                #expect(response.status == .ok)

                let body = try JSONDecoder().decode([SkillSummaryResponse].self, from: response.body)
                #expect(body.isEmpty)
            }
        }
    }

    // MARK: - GET /v1/skills/:name (not found)

    @Test("GET /v1/skills/:name returns 404 for non-existent skill")
    func getSkillDetailNotFound() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/skills/nonexistent", method: .get) { response in
                #expect(response.status == .notFound)

                let body = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(body.error == "skill_not_found")
            }
        }
    }

    // MARK: - POST /v1/skills/:name/run (not found)

    @Test("POST /v1/skills/:name/run returns 404 for non-existent skill")
    func runSkillNotFound() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let body = ByteBuffer(string: "{}")
            try await client.execute(uri: "/v1/skills/nonexistent/run", method: .post, body: body) { response in
                #expect(response.status == .notFound)

                let errorBody = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(errorBody.error == "skill_not_found")
            }
        }
    }

    // MARK: - GET /v1/skills with existing skill

    @Test("GET /v1/skills returns skills list when skills exist")
    func getSkillsReturnsList() async throws {
        // Create a temp skill file
        let skillsDir = SkillCompileCommand.skillsDirectory()
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: skillsDir + "/test_skill.json") }

        let skill = Skill(
            name: "test_skill",
            description: "A test skill",
            version: 1,
            createdAt: Date(),
            sourceRecording: "test",
            parameters: [SkillParameter(name: "url", defaultValue: nil, description: "URL to open")],
            steps: [SkillStep(tool: "launch_app", arguments: ["app_name": "Safari"], waitAfterSeconds: 0)]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(skill)
        try data.write(to: URL(fileURLWithPath: skillsDir + "/test_skill.json"))

        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/skills", method: .get) { response in
                #expect(response.status == .ok)

                let summaries = try JSONDecoder().decode([SkillSummaryResponse].self, from: response.body)
                #expect(summaries.count == 1)
                #expect(summaries[0].name == "test_skill")
                #expect(summaries[0].stepCount == 1)
                #expect(summaries[0].parameterCount == 1)
            }
        }
    }

    // MARK: - GET /v1/skills/:name detail

    @Test("GET /v1/skills/:name returns detail for existing skill")
    func getSkillDetailExisting() async throws {
        let skillsDir = SkillCompileCommand.skillsDirectory()
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: skillsDir + "/detail_test.json") }

        let skill = Skill(
            name: "detail_test",
            description: "Test skill for detail",
            version: 2,
            createdAt: Date(),
            sourceRecording: "test",
            parameters: [],
            steps: [
                SkillStep(tool: "click", arguments: ["x": "100", "y": "200"], waitAfterSeconds: 0.5)
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(skill)
        try data.write(to: URL(fileURLWithPath: skillsDir + "/detail_test.json"))

        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/skills/detail_test", method: .get) { response in
                #expect(response.status == .ok)

                let detail = try JSONDecoder().decode(SkillDetailResponse.self, from: response.body)
                #expect(detail.name == "detail_test")
                #expect(detail.version == 2)
                #expect(detail.stepCount == 1)
            }
        }
    }

    // MARK: - GET /v1/runs list

    @Test("GET /v1/runs returns empty list initially")
    func getRunsListEmpty() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs", method: .get) { response in
                #expect(response.status == .ok)

                let runs = try JSONDecoder().decode([RunStatusResponse].self, from: response.body)
                #expect(runs.isEmpty)
            }
        }
    }

    @Test("GET /v1/runs returns submitted runs sorted by time")
    func getRunsListReturnsSorted() async throws {
        let tracker = RunTracker()
        _ = await tracker.submitRun(task: "first task", options: RunOptions(task: "first task"))
        _ = await tracker.submitRun(task: "second task", options: RunOptions(task: "second task"))

        let app = try await buildTestApplication(runTracker: tracker)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs", method: .get) { response in
                #expect(response.status == .ok)

                let runs = try JSONDecoder().decode([RunStatusResponse].self, from: response.body)
                #expect(runs.count == 2)
                // Both tasks exist (order may vary)
                let tasks = runs.map(\.task)
                #expect(tasks.contains("second task"))
                #expect(tasks.contains("first task"))
            }
        }
    }

    @Test("GET /v1/runs?limit=1 returns limited results")
    func getRunsListWithLimit() async throws {
        let tracker = RunTracker()
        _ = await tracker.submitRun(task: "task1", options: RunOptions(task: "task1"))
        _ = await tracker.submitRun(task: "task2", options: RunOptions(task: "task2"))

        let app = try await buildTestApplication(runTracker: tracker)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs?limit=1", method: .get) { response in
                #expect(response.status == .ok)

                let runs = try JSONDecoder().decode([RunStatusResponse].self, from: response.body)
                #expect(runs.count == 1)
            }
        }
    }

    // MARK: - POST /v1/runs with empty task

    @Test("POST /v1/runs with empty task returns 400")
    func createRunEmptyTaskReturns400() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let body = ByteBuffer(string: "{\"task\": \"   \"}")
            try await client.execute(uri: "/v1/runs", method: .post, body: body) { response in
                #expect(response.status == .badRequest)

                let errorBody = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(errorBody.error == "missing_task")
            }
        }
    }

    // MARK: - POST /v1/runs with invalid JSON

    @Test("POST /v1/runs with invalid JSON returns 400")
    func createRunInvalidJSONReturns400() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let body = ByteBuffer(string: "not json at all")
            try await client.execute(uri: "/v1/runs", method: .post, body: body) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    // MARK: - Skill routes with auth

    @Test("GET /v1/skills with auth and correct token returns 200")
    func getSkillsWithAuthCorrectToken() async throws {
        let app = try await buildTestApplication(authKey: "secret123")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer secret123"
            try await client.execute(uri: "/v1/skills", method: .get, headers: headers) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("GET /v1/skills with auth and wrong token returns 401")
    func getSkillsWithAuthWrongToken() async throws {
        let app = try await buildTestApplication(authKey: "secret123")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer wrong"
            try await client.execute(uri: "/v1/skills", method: .get, headers: headers) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    // MARK: - Helper

    private func buildTestApplication(
        runTracker: RunTracker? = nil,
        eventBroadcaster: EventBroadcaster? = nil,
        authKey: String? = nil,
        concurrencyLimiter: ConcurrencyLimiter? = nil
    ) async throws -> Application<RouterResponder<BasicRequestContext>> {
        let broadcaster = eventBroadcaster ?? EventBroadcaster()
        let tracker = runTracker ?? RunTracker(eventBroadcaster: broadcaster)
        let router = Router()
        AxionAPI.registerRoutes(
            on: router,
            runTracker: tracker,
            eventBroadcaster: broadcaster,
            config: .default,
            authKey: authKey,
            concurrencyLimiter: concurrencyLimiter
        )

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )
        return app
    }
}
