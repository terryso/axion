import Testing
import Foundation
@testable import AxionCore

@Suite("Skill Models")
struct SkillTests {

    // MARK: - SkillParameter

    @Test("SkillParameter Codable round-trip preserves all fields")
    func test_skillParameter_roundTrip() throws {
        let original = SkillParameter(
            name: "url",
            defaultValue: nil,
            description: "自动检测: URL 模式"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SkillParameter.self, from: data)
        #expect(decoded == original)
    }

    @Test("SkillParameter with default value Codable round-trip")
    func test_skillParameter_withDefault_roundTrip() throws {
        let original = SkillParameter(
            name: "search_term",
            defaultValue: "hello",
            description: "搜索关键词"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SkillParameter.self, from: data)
        #expect(decoded == original)
    }

    @Test("SkillParameter JSON uses snake_case keys")
    func test_skillParameter_snakeCaseKeys() throws {
        let param = SkillParameter(name: "url", defaultValue: nil, description: "test")
        let data = try JSONEncoder().encode(param)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["default_value"] != nil)
        #expect(json["name"] != nil)
        #expect(json["description"] != nil)
    }

    // MARK: - SkillStep

    @Test("SkillStep Codable round-trip preserves all fields")
    func test_skillStep_roundTrip() throws {
        let original = SkillStep(
            tool: "click",
            arguments: ["x": "500", "y": "300"],
            waitAfterSeconds: 0.5
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SkillStep.self, from: data)
        #expect(decoded == original)
    }

    @Test("SkillStep with placeholder argument Codable round-trip")
    func test_skillStep_placeholderArg_roundTrip() throws {
        let original = SkillStep(
            tool: "type_text",
            arguments: ["text": "{{url}}"],
            waitAfterSeconds: 0.1
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SkillStep.self, from: data)
        #expect(decoded == original)
    }

    @Test("SkillStep JSON uses snake_case keys")
    func test_skillStep_snakeCaseKeys() throws {
        let step = SkillStep(tool: "click", arguments: [:], waitAfterSeconds: 1.0)
        let data = try JSONEncoder().encode(step)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["wait_after_seconds"] != nil)
    }

    // MARK: - Skill

    @Test("Skill Codable round-trip preserves all fields")
    func test_skill_roundTrip() throws {
        let original = Skill(
            name: "open_calculator",
            description: "操作录制: open_calculator (编译自录制文件)",
            version: 1,
            createdAt: Date(timeIntervalSince1970: 1_715_658_000),
            sourceRecording: "open_calculator",
            parameters: [
                SkillParameter(name: "url", defaultValue: nil, description: "自动检测: URL 模式"),
            ],
            steps: [
                SkillStep(tool: "launch_app", arguments: ["app_name": "Calculator"], waitAfterSeconds: 0.5),
                SkillStep(tool: "click", arguments: ["x": "500", "y": "300"], waitAfterSeconds: 0),
                SkillStep(tool: "type_text", arguments: ["text": "{{url}}"], waitAfterSeconds: 0.1),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Skill.self, from: data)
        #expect(decoded == original)
    }

    @Test("Skill JSON uses snake_case keys and matches expected format")
    func test_skill_jsonFormat() throws {
        let skill = Skill(
            name: "test_skill",
            description: "A test skill",
            createdAt: Date(timeIntervalSince1970: 1_715_658_000),
            sourceRecording: "test",
            steps: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(skill)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["name"] != nil)
        #expect(json["description"] != nil)
        #expect(json["version"] != nil)
        #expect(json["created_at"] != nil)
        #expect(json["source_recording"] != nil)
        #expect(json["parameters"] != nil)
        #expect(json["steps"] != nil)
    }

    @Test("Skill with empty parameters and steps")
    func test_skill_emptyCollections() throws {
        let original = Skill(
            name: "simple",
            description: "simple skill",
            createdAt: Date(),
            sourceRecording: "simple",
            parameters: [],
            steps: []
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Skill.self, from: data)
        #expect(decoded == original)
        #expect(decoded.parameters.isEmpty)
        #expect(decoded.steps.isEmpty)
    }

    // MARK: - Execution Metadata

    @Test("Skill with lastUsedAt and executionCount round-trip")
    func test_skill_executionMetadata_roundTrip() throws {
        let original = Skill(
            name: "test_skill",
            description: "test",
            createdAt: Date(timeIntervalSince1970: 1_715_658_000),
            sourceRecording: "test",
            steps: [],
            lastUsedAt: Date(timeIntervalSince1970: 1_715_660_000),
            executionCount: 5
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Skill.self, from: data)
        #expect(decoded == original)
        #expect(decoded.executionCount == 5)
        #expect(decoded.lastUsedAt != nil)
    }

    @Test("Skill defaults executionCount to 0 and lastUsedAt to nil when missing")
    func test_skill_backwardCompatibility() throws {
        // JSON without last_used_at or execution_count fields
        let json = """
        {
            "name": "old_skill",
            "description": "old",
            "version": 1,
            "created_at": "2024-05-14T00:00:00Z",
            "source_recording": "old",
            "parameters": [],
            "steps": []
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Skill.self, from: data)
        #expect(decoded.executionCount == 0)
        #expect(decoded.lastUsedAt == nil)
    }

    @Test("Skill execution metadata uses snake_case keys in JSON")
    func test_skill_executionMetadata_snakeCaseKeys() throws {
        let skill = Skill(
            name: "test",
            description: "test",
            createdAt: Date(),
            sourceRecording: "test",
            steps: [],
            lastUsedAt: Date(),
            executionCount: 3
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(skill)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["last_used_at"] != nil)
        #expect(json["execution_count"] != nil)
    }

    @Test("Skill executionCount and lastUsedAt are mutable")
    func test_skill_executionMetadata_mutable() {
        var skill = Skill(
            name: "test",
            description: "test",
            createdAt: Date(),
            sourceRecording: "test",
            steps: []
        )
        #expect(skill.executionCount == 0)
        #expect(skill.lastUsedAt == nil)

        skill.executionCount = 1
        skill.lastUsedAt = Date()
        #expect(skill.executionCount == 1)
        #expect(skill.lastUsedAt != nil)
    }
}
