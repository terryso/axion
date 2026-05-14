import AxionCore
import Foundation
import Testing

@testable import AxionCLI

// MARK: - SkillCompileE2ETests
// E2E tests for the `axion skill compile` pipeline:
// recording file on disk → RecordingCompiler → skill file on disk → verify

@Suite("Skill Compile E2E Tests")
struct SkillCompileE2ETests {

    // MARK: - Helpers

    private func withTempDirs(_ body: (URL, URL) async throws -> Void) async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let recordingsDir = tempRoot.appendingPathComponent("recordings")
        let skillsDir = tempRoot.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try await body(recordingsDir, skillsDir)
    }

    private func writeRecording(_ recording: Recording, to dir: URL, name: String) throws -> URL {
        let safeName = RecordCommand.sanitizeFileName(name)
        let fileURL = dir.appendingPathComponent("\(safeName).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(recording).write(to: fileURL)
        return fileURL
    }

    private func compileAndSave(
        recording: Recording,
        recordingsDir: URL,
        skillsDir: URL,
        name: String,
        paramNames: [String] = []
    ) throws -> (skill: Skill, skillData: Data, result: RecordingCompiler.CompileResult) {
        let safeName = RecordCommand.sanitizeFileName(name)

        // Write recording file
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let recordingData = try encoder.encode(recording)
        let recordingURL = recordingsDir.appendingPathComponent("\(safeName).json")
        try recordingData.write(to: recordingURL)

        // Load recording (simulates SkillCompileCommand.run file loading)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(Recording.self, from: recordingData)

        // Compile
        let compiler = RecordingCompiler()
        let result = compiler.compile(recording: loaded, paramNames: paramNames)

        // Save skill file (simulates SkillCompileCommand.run file saving)
        let skillData = try encoder.encode(result.skill)
        let skillURL = skillsDir.appendingPathComponent("\(safeName).json")
        try FileManager.default.createDirectory(
            at: skillsDir, withIntermediateDirectories: true
        )
        try skillData.write(to: skillURL)

        return (result.skill, skillData, result)
    }

    // MARK: - AC1: Full Pipeline - Recording → Skill File

    @Test("Full pipeline: recording file → compile → skill file on disk")
    func test_fullPipeline_recordingToSkillFile() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let events = [
                RecordedEvent(type: .appSwitch, timestamp: 0.1,
                              parameters: ["app_name": .string("Calculator")],
                              windowContext: nil),
                RecordedEvent(type: .click, timestamp: 0.5,
                              parameters: ["x": .int(500), "y": .int(300)],
                              windowContext: nil),
                RecordedEvent(type: .typeText, timestamp: 1.0,
                              parameters: ["text": .string("42")],
                              windowContext: nil),
            ]
            let recording = Recording(
                name: "open_calculator",
                createdAt: Date(timeIntervalSince1970: 1_715_658_000),
                durationSeconds: 5.0,
                events: events,
                windowSnapshots: []
            )

            let (skill, skillData, result) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "open_calculator"
            )

            // Verify skill file exists and is valid JSON
            let skillURL = skillsDir.appendingPathComponent("open_calculator.json")
            #expect(FileManager.default.fileExists(atPath: skillURL.path))

            let loadedData = try Data(contentsOf: skillURL)
            let loadedJSON = try JSONSerialization.jsonObject(with: loadedData) as! [String: Any]
            #expect(loadedJSON["name"] as? String == "open_calculator")

            // Verify compilation result
            #expect(result.skill.steps.count == 3)
            #expect(result.skill.steps[0].tool == "launch_app")
            #expect(result.skill.steps[1].tool == "click")
            #expect(result.skill.steps[2].tool == "type_text")
        }
    }

    // MARK: - AC2: Auto Parameter Detection Through Pipeline

    @Test("Auto-detect URL parameter in compiled skill file")
    func test_pipeline_autoDetectURL() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let events = [
                RecordedEvent(type: .typeText, timestamp: 0.1,
                              parameters: ["text": .string("https://example.com/search?q=test")],
                              windowContext: nil),
            ]
            let recording = Recording(
                name: "web_search",
                createdAt: Date(),
                durationSeconds: 2.0,
                events: events,
                windowSnapshots: []
            )

            let (skill, _, _) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "web_search"
            )

            #expect(skill.parameters.count == 1)
            #expect(skill.parameters[0].name == "url")
            #expect(skill.steps[0].arguments["text"] == "{{url}}")
        }
    }

    @Test("Auto-detect multiple parameter types in single skill")
    func test_pipeline_autoDetectMultipleParams() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let longText = "this is a really long search query that exceeds twenty chars"
            let events = [
                RecordedEvent(type: .typeText, timestamp: 0.1,
                              parameters: ["text": .string("https://example.com")],
                              windowContext: nil),
                RecordedEvent(type: .click, timestamp: 0.2,
                              parameters: ["x": .int(100), "y": .int(200)],
                              windowContext: nil),
                RecordedEvent(type: .typeText, timestamp: 0.3,
                              parameters: ["text": .string("/Users/nick/Documents/report.pdf")],
                              windowContext: nil),
                // Insert click between type_text events to prevent merging
                RecordedEvent(type: .click, timestamp: 0.35,
                              parameters: ["x": .int(50), "y": .int(50)],
                              windowContext: nil),
                RecordedEvent(type: .typeText, timestamp: 0.4,
                              parameters: ["text": .string(longText)],
                              windowContext: nil),
            ]
            let recording = Recording(
                name: "multi_param",
                createdAt: Date(),
                durationSeconds: 3.0,
                events: events,
                windowSnapshots: []
            )

            let (skill, _, result) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "multi_param"
            )

            #expect(result.detectedParameterCount == 3)
            let paramNames = skill.parameters.map(\.name)
            #expect(paramNames.contains("url"))
            #expect(paramNames.contains("file_path"))
            #expect(paramNames.contains("text"))
        }
    }

    @Test("Auto-detect increments parameter names for duplicate patterns")
    func test_pipeline_autoDetect_incrementalNaming() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            // Separate URL type_text events with a click to prevent merging
            let events = [
                RecordedEvent(type: .typeText, timestamp: 0.1,
                              parameters: ["text": .string("https://example.com")],
                              windowContext: nil),
                RecordedEvent(type: .click, timestamp: 0.15,
                              parameters: ["x": .int(100), "y": .int(200)],
                              windowContext: nil),
                RecordedEvent(type: .typeText, timestamp: 0.2,
                              parameters: ["text": .string("https://other.com/page")],
                              windowContext: nil),
            ]
            let recording = Recording(
                name: "two_urls",
                createdAt: Date(),
                durationSeconds: 2.0,
                events: events,
                windowSnapshots: []
            )

            let (skill, _, _) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "two_urls"
            )

            let paramNames = skill.parameters.map(\.name)
            #expect(paramNames.contains("url"))
            #expect(paramNames.contains("url_2"))
        }
    }

    // MARK: - AC3: Manual Parameters Through Pipeline

    @Test("Manual --param through full pipeline replaces values")
    func test_pipeline_manualParam() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let events = [
                RecordedEvent(type: .typeText, timestamp: 0.1,
                              parameters: ["text": .string("hello world")],
                              windowContext: nil),
                RecordedEvent(type: .click, timestamp: 0.2,
                              parameters: ["x": .int(100), "y": .int(200)],
                              windowContext: nil),
            ]
            let recording = Recording(
                name: "manual_param",
                createdAt: Date(),
                durationSeconds: 2.0,
                events: events,
                windowSnapshots: []
            )

            let (skill, _, _) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "manual_param",
                paramNames: ["search_term"]
            )

            #expect(skill.steps[0].arguments["text"] == "{{search_term}}")
            let param = skill.parameters.first { $0.name == "search_term" }
            #expect(param != nil)
            #expect(param?.description == "手动指定参数")
        }
    }

    @Test("Multiple manual params through full pipeline")
    func test_pipeline_multipleManualParams() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            // Separate type_text events with a click to prevent merging
            let events = [
                RecordedEvent(type: .typeText, timestamp: 0.1,
                              parameters: ["text": .string("first value")],
                              windowContext: nil),
                RecordedEvent(type: .click, timestamp: 0.15,
                              parameters: ["x": .int(100), "y": .int(200)],
                              windowContext: nil),
                RecordedEvent(type: .typeText, timestamp: 0.2,
                              parameters: ["text": .string("second value")],
                              windowContext: nil),
            ]
            let recording = Recording(
                name: "multi_manual",
                createdAt: Date(),
                durationSeconds: 2.0,
                events: events,
                windowSnapshots: []
            )

            let (skill, _, _) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "multi_manual",
                paramNames: ["input_1", "input_2"]
            )

            let manualParams = skill.parameters.filter { $0.name.hasPrefix("input_") }
            #expect(manualParams.count == 2)
        }
    }

    // MARK: - AC4: Skill File Format Spec Compliance

    @Test("Compiled skill file JSON matches spec format (snake_case keys)")
    func test_skillFile_specCompliance() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let events = [
                RecordedEvent(type: .appSwitch, timestamp: 0.1,
                              parameters: ["app_name": .string("Calculator")],
                              windowContext: nil),
                RecordedEvent(type: .typeText, timestamp: 0.5,
                              parameters: ["text": .string("https://example.com")],
                              windowContext: nil),
            ]
            let recording = Recording(
                name: "spec_test",
                createdAt: Date(timeIntervalSince1970: 1_715_658_000),
                durationSeconds: 3.0,
                events: events,
                windowSnapshots: []
            )

            let (skill, skillData, _) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "spec_test"
            )

            let json = try JSONSerialization.jsonObject(with: skillData) as! [String: Any]

            // Required top-level keys
            #expect(json["name"] as? String == "spec_test")
            #expect(json["description"] != nil)
            #expect(json["version"] as? Int == 1)
            #expect(json["created_at"] != nil)
            #expect(json["source_recording"] as? String == "spec_test")
            #expect(json["parameters"] != nil)
            #expect(json["steps"] != nil)

            // Verify step structure
            let steps = json["steps"] as! [[String: Any]]
            #expect(steps.count == 2)
            let firstStep = steps[0]
            #expect(firstStep["tool"] != nil)
            #expect(firstStep["arguments"] != nil)
            #expect(firstStep["wait_after_seconds"] != nil)

            // Verify parameter structure
            let params = json["parameters"] as! [[String: Any]]
            #expect(params.count == 1)
            let param = params[0]
            #expect(param["name"] != nil)
            #expect(param["default_value"] != nil)  // nil encodes as JSON null
            #expect(param["description"] != nil)
        }
    }

    @Test("Skill file is human-readable pretty-printed JSON")
    func test_skillFile_prettyPrinted() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let events = [
                RecordedEvent(type: .click, timestamp: 0.1,
                              parameters: ["x": .int(100), "y": .int(200)],
                              windowContext: nil),
            ]
            let recording = Recording(
                name: "pretty_test",
                createdAt: Date(),
                durationSeconds: 1.0,
                events: events,
                windowSnapshots: []
            )

            let (_, skillData, _) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "pretty_test"
            )

            let jsonString = String(data: skillData, encoding: .utf8)!
            // Pretty-printed JSON has newlines
            #expect(jsonString.contains("\n"))
            // Should not be minified (single line)
            #expect(jsonString.contains("\n  "))
        }
    }

    // MARK: - AC5: Redundancy Optimization Through Pipeline

    @Test("Full pipeline optimizes redundant operations")
    func test_pipeline_optimizesRedundancy() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let events = [
                // 3 identical clicks → should become 1
                RecordedEvent(type: .click, timestamp: 0.1, parameters: ["x": .int(100), "y": .int(200)], windowContext: nil),
                RecordedEvent(type: .click, timestamp: 0.2, parameters: ["x": .int(100), "y": .int(200)], windowContext: nil),
                RecordedEvent(type: .click, timestamp: 0.3, parameters: ["x": .int(100), "y": .int(200)], windowContext: nil),
                // Consecutive type_text → should merge
                RecordedEvent(type: .typeText, timestamp: 0.4, parameters: ["text": .string("hello")], windowContext: nil),
                RecordedEvent(type: .typeText, timestamp: 0.5, parameters: ["text": .string(" world")], windowContext: nil),
                // A→B→A app switch → should remove redundant
                RecordedEvent(type: .appSwitch, timestamp: 0.6, parameters: ["app_name": .string("Safari")], windowContext: nil),
                RecordedEvent(type: .appSwitch, timestamp: 0.7, parameters: ["app_name": .string("Calculator")], windowContext: nil),
                RecordedEvent(type: .appSwitch, timestamp: 0.8, parameters: ["app_name": .string("Safari")], windowContext: nil),
            ]
            let recording = Recording(
                name: "redundant",
                createdAt: Date(),
                durationSeconds: 5.0,
                events: events,
                windowSnapshots: []
            )

            let (skill, _, result) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "redundant"
            )

            // 8 input events → optimized to 3 steps (1 click + 1 type_text + 1 launch_app)
            #expect(skill.steps.count == 3)
            #expect(result.optimizedStepCount == 5)
            #expect(skill.steps[0].tool == "click")
            #expect(skill.steps[1].tool == "type_text")
            #expect(skill.steps[1].arguments["text"] == "hello world")
            #expect(skill.steps[2].tool == "launch_app")
            #expect(skill.steps[2].arguments["app_name"] == "Safari")
        }
    }

    // MARK: - Error Events Skipped in Pipeline

    @Test("Error events are filtered out in full pipeline")
    func test_pipeline_errorEventsSkipped() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let events = [
                RecordedEvent(type: .click, timestamp: 0.1, parameters: ["x": .int(100), "y": .int(200)], windowContext: nil),
                RecordedEvent(type: .error, timestamp: 0.15, parameters: ["message": .string("tap failed")], windowContext: nil),
                RecordedEvent(type: .error, timestamp: 0.16, parameters: [:], windowContext: nil),
                RecordedEvent(type: .hotkey, timestamp: 0.2, parameters: ["keys": .string("cmd+c")], windowContext: nil),
            ]
            let recording = Recording(
                name: "with_errors",
                createdAt: Date(),
                durationSeconds: 2.0,
                events: events,
                windowSnapshots: []
            )

            let (skill, _, _) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "with_errors"
            )

            #expect(skill.steps.count == 2)
            #expect(skill.steps[0].tool == "click")
            #expect(skill.steps[1].tool == "hotkey")
        }
    }

    // MARK: - Error Handling

    @Test("Missing recording file produces clear error")
    func test_error_missingRecordingFile() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let recordingURL = recordingsDir.appendingPathComponent("nonexistent.json")
            #expect(!FileManager.default.fileExists(atPath: recordingURL.path))

            // Attempting to load non-existent file should throw
            #expect(throws: Error.self) {
                try Data(contentsOf: recordingURL)
            }
        }
    }

    @Test("Invalid recording data produces decode error")
    func test_error_invalidRecordingData() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let invalidData = "not valid json".data(using: .utf8)!
            let fileURL = recordingsDir.appendingPathComponent("bad.json")
            try invalidData.write(to: fileURL)

            #expect(throws: DecodingError.self) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                _ = try decoder.decode(Recording.self, from: invalidData)
            }
        }
    }

    @Test("Path traversal in recording name is sanitized")
    func test_error_pathTraversalSanitized() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let safeName = RecordCommand.sanitizeFileName("../../etc/passwd")
            #expect(!safeName.contains(".."))
            #expect(safeName == "____etc_passwd")

            // Verify the sanitized name produces a safe file path
            let path = (recordingsDir.path as NSString).appendingPathComponent("\(safeName).json")
            #expect(!path.contains(".."))
        }
    }

    // MARK: - NFR36: Skill File Size Under 100KB

    @Test("Skill file stays under 100KB for recording with 200 events")
    func test_nfr36_skillFileSizeUnder100KB() async throws {
        var events: [RecordedEvent] = []
        for i in 0..<200 {
            let eventType = i % 5
            switch eventType {
            case 0:
                events.append(RecordedEvent(type: .click, timestamp: Double(i) * 0.1,
                    parameters: ["x": .int(i * 10), "y": .int(i * 5)],
                    windowContext: WindowContext(appName: "TestApp", pid: 12345, windowId: 1, windowTitle: "Window")))
            case 1:
                events.append(RecordedEvent(type: .typeText, timestamp: Double(i) * 0.1,
                    parameters: ["text": .string("sample text \(i)")],
                    windowContext: nil))
            case 2:
                events.append(RecordedEvent(type: .hotkey, timestamp: Double(i) * 0.1,
                    parameters: ["keys": .string("cmd+\(i % 10)")],
                    windowContext: nil))
            case 3:
                events.append(RecordedEvent(type: .appSwitch, timestamp: Double(i) * 0.1,
                    parameters: ["app_name": .string("App\(i % 3)")],
                    windowContext: nil))
            default:
                events.append(RecordedEvent(type: .scroll, timestamp: Double(i) * 0.1,
                    parameters: ["dx": .int(0), "dy": .int(-5)],
                    windowContext: nil))
            }
        }

        let recording = Recording(
            name: "stress_test",
            createdAt: Date(),
            durationSeconds: 20.0,
            events: events,
            windowSnapshots: []
        )

        let compiler = RecordingCompiler()
        let result = compiler.compile(recording: recording)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let skillData = try encoder.encode(result.skill)

        let sizeKB = Double(skillData.count) / 1024.0
        #expect(sizeKB < 100.0, "Skill file is \(sizeKB)KB, exceeds 100KB NFR36 limit")
    }

    // MARK: - Round-Trip: Skill File Load After Compile

    @Test("Compiled skill file can be loaded back as Skill model")
    func test_skillFile_roundTrip() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let events = [
                RecordedEvent(type: .appSwitch, timestamp: 0.1,
                              parameters: ["app_name": .string("Safari")],
                              windowContext: nil),
                RecordedEvent(type: .click, timestamp: 0.5,
                              parameters: ["x": .int(300), "y": .int(400)],
                              windowContext: nil),
                RecordedEvent(type: .typeText, timestamp: 1.0,
                              parameters: ["text": .string("https://example.com/search")],
                              windowContext: nil),
                RecordedEvent(type: .hotkey, timestamp: 1.5,
                              parameters: ["keys": .string("cmd+c")],
                              windowContext: nil),
            ]
            let recording = Recording(
                name: "roundtrip",
                createdAt: Date(timeIntervalSince1970: 1_715_658_000),
                durationSeconds: 5.0,
                events: events,
                windowSnapshots: []
            )

            let (skill, skillData, _) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "roundtrip"
            )

            // Load skill file back
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode(Skill.self, from: skillData)

            // Verify all fields except Date (ISO8601 truncates sub-seconds)
            #expect(loaded.name == skill.name)
            #expect(loaded.description == skill.description)
            #expect(loaded.version == skill.version)
            #expect(loaded.sourceRecording == skill.sourceRecording)
            #expect(loaded.parameters == skill.parameters)
            #expect(loaded.steps == skill.steps)
            #expect(loaded.steps.count == 4)
            #expect(loaded.parameters.count == 1)
            #expect(loaded.steps[2].arguments["text"] == "{{url}}")
        }
    }

    // MARK: - Mixed Event Types Pipeline

    @Test("Mixed event types all correctly compiled")
    func test_pipeline_allEventTypes() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let events = [
                RecordedEvent(type: .appSwitch, timestamp: 0.0,
                              parameters: ["app_name": .string("Notes")], windowContext: nil),
                RecordedEvent(type: .click, timestamp: 0.1,
                              parameters: ["x": .int(100), "y": .int(200)], windowContext: nil),
                RecordedEvent(type: .typeText, timestamp: 0.2,
                              parameters: ["text": .string("hello")], windowContext: nil),
                RecordedEvent(type: .hotkey, timestamp: 0.3,
                              parameters: ["keys": .string("cmd+a")], windowContext: nil),
                RecordedEvent(type: .scroll, timestamp: 0.4,
                              parameters: ["dx": .int(0), "dy": .int(-10)], windowContext: nil),
                RecordedEvent(type: .error, timestamp: 0.5,
                              parameters: ["message": .string("oops")], windowContext: nil),
            ]
            let recording = Recording(
                name: "all_types",
                createdAt: Date(),
                durationSeconds: 2.0,
                events: events,
                windowSnapshots: []
            )

            let (skill, _, _) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "all_types"
            )

            // 6 events minus 1 error = 5 steps
            #expect(skill.steps.count == 5)
            #expect(skill.steps[0].tool == "launch_app")
            #expect(skill.steps[1].tool == "click")
            #expect(skill.steps[2].tool == "type_text")
            #expect(skill.steps[3].tool == "hotkey")
            #expect(skill.steps[4].tool == "scroll")
        }
    }

    // MARK: - Empty Recording Edge Case

    @Test("Empty recording compiles to empty skill")
    func test_pipeline_emptyRecording() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let recording = Recording(
                name: "empty",
                createdAt: Date(),
                durationSeconds: 0.0,
                events: [],
                windowSnapshots: []
            )

            let (skill, skillData, _) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "empty"
            )

            #expect(skill.steps.isEmpty)
            #expect(skill.parameters.isEmpty)
            #expect(skill.name == "empty")

            // Verify file is still valid JSON
            let json = try JSONSerialization.jsonObject(with: skillData) as! [String: Any]
            #expect((json["steps"] as? [Any])?.isEmpty == true)
            #expect((json["parameters"] as? [Any])?.isEmpty == true)
        }
    }

    // MARK: - Skill Description Format

    @Test("Skill description follows convention")
    func test_skillDescription_format() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let recording = Recording(
                name: "my_task",
                createdAt: Date(),
                durationSeconds: 1.0,
                events: [],
                windowSnapshots: []
            )

            let (skill, _, _) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "my_task"
            )

            #expect(skill.description == "操作录制: my_task (编译自录制文件)")
        }
    }

    // MARK: - Window Context Preserved in Recording Load

    @Test("Recording with window context compiles correctly")
    func test_pipeline_withWindowContext() async throws {
        try await withTempDirs { recordingsDir, skillsDir in
            let events = [
                RecordedEvent(type: .click, timestamp: 0.1,
                              parameters: ["x": .int(100), "y": .int(200)],
                              windowContext: WindowContext(appName: "Safari", pid: 12345, windowId: 1, windowTitle: "Google")),
            ]
            let recording = Recording(
                name: "with_context",
                createdAt: Date(),
                durationSeconds: 1.0,
                events: events,
                windowSnapshots: []
            )

            let (skill, _, _) = try compileAndSave(
                recording: recording,
                recordingsDir: recordingsDir,
                skillsDir: skillsDir,
                name: "with_context"
            )

            // Window context in recording should not affect compiled skill
            #expect(skill.steps.count == 1)
            #expect(skill.steps[0].tool == "click")
            #expect(skill.steps[0].arguments["x"] == "100")
            #expect(skill.steps[0].arguments["y"] == "200")
        }
    }
}
