import XCTest
@testable import AxionCLI
@testable import AxionCore

// [P0] 基础设施验证
// [P1] 行为验证

final class PromptBuilderTests: XCTestCase {

    // MARK: - P0 类型存在性

    func test_promptBuilder_typeExists() async throws {
        // 验证 PromptBuilder 类型存在
        let _ = PromptBuilder.self
    }

    // MARK: - P0 Prompt 文件加载 (AC1)

    func test_load_existingFile_returnsContent() async throws {
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

        XCTAssertEqual(result, "Hello Alice, welcome to Axion!")
    }

    func test_load_missingFile_throwsError() async throws {
        XCTAssertThrowsError(
            try PromptBuilder.load(
                name: "nonexistent",
                variables: [:],
                fromDirectory: "/tmp/empty-dir-\(UUID().uuidString)"
            )
        )
    }

    func test_load_noVariables_returnsRawContent() async throws {
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

        XCTAssertEqual(result, "No variables here, just plain text.")
    }

    func test_load_multipleOccurrences_replacesAll() async throws {
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

        XCTAssertEqual(result, "Hi Bob! Hi again.")
    }

    // MARK: - P0 模板变量注入 (AC1)

    func test_templateVariable_injectedCorrectly() async throws {
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

        XCTAssertTrue(result.contains(toolList))
        XCTAssertFalse(result.contains("{{tools}}"))
    }

    // MARK: - P0 工具列表格式化 (AC1)

    func test_buildToolListDescription_formatsToolNames() async throws {
        let tools = ["launch_app", "click", "type_text", "screenshot"]
        let description = PromptBuilder.buildToolListDescription(from: tools)

        // 验证每个工具名出现在描述中
        for tool in tools {
            XCTAssertTrue(description.contains(tool), "Description should contain '\(tool)'")
        }
    }

    func test_buildToolListDescription_emptyList_returnsEmpty() async throws {
        let description = PromptBuilder.buildToolListDescription(from: [])
        XCTAssertTrue(description.isEmpty)
    }

    // MARK: - P1 完整 Planner Prompt 组装 (AC1)

    func test_buildPlannerPrompt_includesTask() async throws {
        let prompt = PromptBuilder.buildPlannerPrompt(
            task: "Open Calculator and compute 17 * 23",
            currentStateSummary: "Desktop is visible",
            maxStepsPerPlan: 10,
            replanContext: nil
        )

        XCTAssertTrue(prompt.contains("Open Calculator"))
        XCTAssertTrue(prompt.contains("10"))
    }

    func test_buildPlannerPrompt_withReplanContext_includesFailureInfo() async throws {
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

        XCTAssertTrue(prompt.contains("REPLAN"))
        XCTAssertTrue(prompt.contains("Element not found"))
        XCTAssertTrue(prompt.contains("launch_app"))
    }

    // MARK: - P1 Prompt 目录查找

    func test_resolvePromptDirectory_returnsValidPath() async throws {
        let path = PromptBuilder.resolvePromptDirectory()
        XCTAssertFalse(path.isEmpty)
    }

    // MARK: - P1 未使用变量保留原样

    func test_load_unresolvedVariables_remainAsPlaceholders() async throws {
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

        XCTAssertEqual(result, "Hello Alice, your {{unknown_var}} is ready.")
    }

    // MARK: - Story 8.2 Cross-Application Prompt Content

    func test_plannerPrompt_containsCrossAppWorkflowPatterns() async throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20"],
            fromDirectory: promptDir
        )
        XCTAssertTrue(content.contains("Cross-Application Workflow Patterns"),
            "Planner prompt should contain Cross-Application Workflow Patterns section")
    }

    func test_plannerPrompt_containsClipboardVerification() async throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20"],
            fromDirectory: promptDir
        )
        XCTAssertTrue(content.contains("Clipboard verification"),
            "Planner prompt should contain clipboard verification guidance")
    }

    func test_plannerPrompt_containsCrossAppFailureRecovery() async throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20"],
            fromDirectory: promptDir
        )
        XCTAssertTrue(content.contains("Cross-app failure"),
            "Planner prompt should contain cross-app failure recovery guidance")
        XCTAssertTrue(content.contains("Application not found"),
            "Planner prompt should contain application not found guidance")
    }

    // MARK: - Story 8.3 Window Layout Prompt Content

    func test_plannerPrompt_containsWindowLayoutGuidance() async throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20"],
            fromDirectory: promptDir
        )
        XCTAssertTrue(content.contains("arrange_windows"),
            "Planner prompt should reference arrange_windows tool")
        XCTAssertTrue(content.contains("tile-left-right"),
            "Planner prompt should describe tile-left-right layout")
        XCTAssertTrue(content.contains("tile-top-bottom"),
            "Planner prompt should describe tile-top-bottom layout")
        XCTAssertTrue(content.contains("cascade"),
            "Planner prompt should describe cascade layout")
        XCTAssertTrue(content.contains("resize_window"),
            "Planner prompt should reference resize_window tool")
    }
}
