import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

@Suite("PromptBuilder")
struct PromptBuilderTests {

    @Test("type exists")
    func promptBuilderTypeExists() async throws {
        // 验证 PromptBuilder 类型存在
        let _ = PromptBuilder.self
    }

    @Test("load existing file returns content")
    func loadExistingFileReturnsContent() async throws {
        // 创建临时 prompt 文件
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Prompts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = "Hello {{name}}, welcome to {{place}}!"
        let fileURL = tempDir.appendingPathComponent("test-prompt.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try PromptBuilder.load(
            name: "test-prompt",
            variables: ["name": "Alice", "place": "Axion"],
            fromDirectory: tempDir.path
        )

        #expect(result == "Hello Alice, welcome to Axion!")
    }

    @Test("load missing file throws error")
    func loadMissingFileThrowsError() async throws {
        do {
            try PromptBuilder.load(
                name: "nonexistent",
                variables: [:],
                fromDirectory: "/tmp/empty-dir-\(UUID().uuidString)"
            )
            Issue.record("Should have thrown")
        } catch {
            // Expected
        }
    }

    @Test("load with no variables returns raw content")
    func loadNoVariablesReturnsRawContent() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Prompts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = "No variables here, just plain text."
        let fileURL = tempDir.appendingPathComponent("plain.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try PromptBuilder.load(
            name: "plain",
            variables: [:],
            fromDirectory: tempDir.path
        )

        #expect(result == "No variables here, just plain text.")
    }

    @Test("load with multiple occurrences replaces all")
    func loadMultipleOccurrencesReplacesAll() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Prompts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = "{{greeting}} {{name}}! {{greeting}} again."
        let fileURL = tempDir.appendingPathComponent("multi.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try PromptBuilder.load(
            name: "multi",
            variables: ["greeting": "Hi", "name": "Bob"],
            fromDirectory: tempDir.path
        )

        #expect(result == "Hi Bob! Hi again.")
    }

    @Test("template variable injected correctly")
    func templateVariableInjectedCorrectly() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Prompts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = "Available tools: {{tools}}"
        let fileURL = tempDir.appendingPathComponent("tools.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let toolList = "launch_app, click, type_text"
        let result = try PromptBuilder.load(
            name: "tools",
            variables: ["tools": toolList],
            fromDirectory: tempDir.path
        )

        #expect(result.contains(toolList))
        #expect(!result.contains("{{tools}}"))
    }

    @Test("buildToolListDescription formats tool names")
    func buildToolListDescriptionFormatsToolNames() async throws {
        let tools = ["launch_app", "click", "type_text", "screenshot"]
        let description = PromptBuilder.buildToolListDescription(from: tools)

        // 验证每个工具名出现在描述中
        for tool in tools {
            #expect(description.contains(tool))
        }
    }

    @Test("buildToolListDescription empty list returns empty")
    func buildToolListDescriptionEmptyListReturnsEmpty() async throws {
        let description = PromptBuilder.buildToolListDescription(from: [])
        #expect(description.isEmpty)
    }

    @Test("buildPlannerPrompt includes task")
    func buildPlannerPromptIncludesTask() async throws {
        let prompt = PromptBuilder.buildPlannerPrompt(
            task: "Open Calculator and compute 17 * 23",
            currentStateSummary: "Desktop is visible",
            maxStepsPerPlan: 10,
            replanContext: nil
        )

        #expect(prompt.contains("Open Calculator"))
        #expect(prompt.contains("10"))
    }

    @Test("buildPlannerPrompt with replanContext includes failure info")
    func buildPlannerPromptWithReplanContextIncludesFailureInfo() async throws {
        let replanContext = ReplanContext(
            failedStepIndex: 2,
            failedStep: Step(index: 2, tool: "click", parameters: ["x": .int(100), "y": .int(200)], purpose: "Click button", expectedChange: "Button clicked"),
            errorMessage: "Element not found at coordinates",
            executedSteps: [
                Step(index: 0, tool: "launch_app", parameters: ["name": .string("Safari")], purpose: "Launch Safari", expectedChange: "Safari opens"),
                Step(index: 1, tool: "click", parameters: ["x": .int(50), "y": .int(50)], purpose: "Click URL bar", expectedChange: "URL bar focused"),
            ],
            liveAxTree: nil,
            runHistory: nil
        )

        let prompt = PromptBuilder.buildPlannerPrompt(
            task: "Open Safari",
            currentStateSummary: "Safari is running",
            maxStepsPerPlan: 5,
            replanContext: replanContext
        )

        #expect(prompt.contains("REPLAN"))
        #expect(prompt.contains("Element not found"))
        #expect(prompt.contains("launch_app"))
    }

    @Test("resolvePromptDirectory returns valid path")
    func resolvePromptDirectoryReturnsValidPath() async throws {
        let path = PromptBuilder.resolvePromptDirectory()
        #expect(!path.isEmpty)
    }

    @Test("load with unresolved variables remain as placeholders")
    func loadUnresolvedVariablesRemainAsPlaceholders() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Prompts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = "Hello {{name}}, your {{unknown_var}} is ready."
        let fileURL = tempDir.appendingPathComponent("partial.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try PromptBuilder.load(
            name: "partial",
            variables: ["name": "Alice"],
            fromDirectory: tempDir.path
        )

        #expect(result == "Hello Alice, your {{unknown_var}} is ready.")
    }

    @Test("planner prompt contains cross-app workflow patterns")
    func plannerPromptContainsCrossAppWorkflowPatterns() async throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20"],
            fromDirectory: promptDir
        )
        #expect(content.contains("Cross-Application Workflow Patterns"))
    }

    @Test("planner prompt contains clipboard verification")
    func plannerPromptContainsClipboardVerification() async throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20"],
            fromDirectory: promptDir
        )
        #expect(content.contains("Clipboard verification"))
    }

    @Test("planner prompt contains cross-app failure recovery")
    func plannerPromptContainsCrossAppFailureRecovery() async throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20"],
            fromDirectory: promptDir
        )
        #expect(content.contains("Cross-app failure"))
        #expect(content.contains("Application not found"))
    }

    @Test("planner prompt contains window layout guidance")
    func plannerPromptContainsWindowLayoutGuidance() async throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20"],
            fromDirectory: promptDir
        )
        #expect(content.contains("arrange_windows"))
        #expect(content.contains("tile-left-right"))
        #expect(content.contains("tile-top-bottom"))
        #expect(content.contains("cascade"))
        #expect(content.contains("resize_window"))
    }
}
