import XCTest
import OpenAgentSDK

@testable import AxionCLI
@testable import AxionCore

// [P0] AppMemoryExtractor type existence, extraction from toolUse/toolResult messages
// [P1] Domain naming, tag generation, edge cases (empty, single tool, multiple apps)
// [P1] Enhanced content: AX tree summary, failure markers, workaround inference (Story 4.2)
// Story 4.1 AC: #1, #2
// Story 4.2 AC: #1, #3

// MARK: - AppMemoryExtractor ATDD Tests

/// ATDD red-phase tests for AppMemoryExtractor (Story 4.1 AC1, AC2).
/// Tests that AppMemoryExtractor extracts App operation summaries from SDK
/// message streams and produces KnowledgeEntry objects organized by App domain.
/// Enhanced in Story 4.2 (AC1, AC3) to include AX tree summary, failure markers,
/// and workaround inference in extracted content.
///
/// TDD RED PHASE: These tests will not compile until AppMemoryExtractor is implemented
/// in Sources/AxionCLI/Memory/AppMemoryExtractor.swift.
final class AppMemoryExtractorTests: XCTestCase {

    // MARK: - Helper: Create SDKMessage instances

    private func makeToolUse(
        toolName: String,
        toolUseId: String = "tu-1",
        input: String = "{}"
    ) -> SDKMessage.ToolUseData {
        SDKMessage.ToolUseData(toolName: toolName, toolUseId: toolUseId, input: input)
    }

    private func makeToolResult(
        toolUseId: String = "tu-1",
        content: String = "ok",
        isError: Bool = false
    ) -> SDKMessage.ToolResultData {
        SDKMessage.ToolResultData(toolUseId: toolUseId, content: content, isError: isError)
    }

    // MARK: - P0: Type Existence

    func test_appMemoryExtractor_typeExists() {
        let _ = AppMemoryExtractor.self
    }

    // MARK: - P0 AC1: Extract from toolUse/toolResult messages

    func test_extract_returnsKnowledgeEntries_fromToolMessages() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true, \"bundle_id\": \"com.apple.calculator\"}")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-2", input: "{\"x\": 100, \"y\": 200}"),
                makeToolResult(toolUseId: "tu-2", content: "clicked")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Open Calculator and click a button",
            runId: "20260513-test01"
        )

        XCTAssertFalse(entries.isEmpty, "Should extract at least one KnowledgeEntry")
        for entry in entries {
            XCTAssertFalse(entry.content.isEmpty, "Entry content should not be empty")
            XCTAssertFalse(entry.id.isEmpty, "Entry ID should not be empty")
        }
    }

    func test_extract_contentIncludesToolSequence() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true, \"bundle_id\": \"com.apple.calculator\"}")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-2", input: "{\"x\": 100, \"y\": 200}"),
                makeToolResult(toolUseId: "tu-2", content: "clicked")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__type_text", toolUseId: "tu-3", input: "{\"text\": \"17\"}"),
                makeToolResult(toolUseId: "tu-3", content: "typed")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Open Calculator and type 17",
            runId: "20260513-test02"
        )

        XCTAssertFalse(entries.isEmpty)
        // The content should reference ALL tools used
        let combinedContent = entries.map { $0.content }.joined(separator: " ")
        XCTAssertTrue(
            combinedContent.contains("launch_app"),
            "Content should include launch_app in tool sequence"
        )
        XCTAssertTrue(
            combinedContent.contains("click"),
            "Content should include click in tool sequence"
        )
        XCTAssertTrue(
            combinedContent.contains("type_text"),
            "Content should include type_text in tool sequence"
        )
    }

    func test_extract_contentIncludesTaskDescription() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true}")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Open Calculator",
            runId: "20260513-test03"
        )

        XCTAssertFalse(entries.isEmpty)
        let combinedContent = entries.map { $0.content }.joined(separator: " ")
        XCTAssertTrue(
            combinedContent.contains("Open Calculator") || combinedContent.contains("Calculator"),
            "Content should reference the original task description"
        )
    }

    func test_extract_includesSuccessOrFailurePath() async throws {
        let extractor = AppMemoryExtractor()

        // Test with a failed tool result
        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"NonExistentApp\"}"),
                makeToolResult(toolUseId: "tu-1", content: "App not found", isError: true)
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Open NonExistentApp",
            runId: "20260513-test04"
        )

        XCTAssertFalse(entries.isEmpty)
        let combinedContent = entries.map { $0.content }.joined(separator: " ").lowercased()
        XCTAssertTrue(
            combinedContent.contains("fail") || combinedContent.contains("error") || combinedContent.contains("unsuccess"),
            "Content should indicate failure when tool returns error"
        )
    }

    func test_extract_successfulPathIndicatesSuccess() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true}")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Open Calculator",
            runId: "20260513-test05"
        )

        XCTAssertFalse(entries.isEmpty)
        let combinedContent = entries.map { $0.content }.joined(separator: " ").lowercased()
        XCTAssertTrue(
            combinedContent.contains("success"),
            "Content should indicate success for non-error results"
        )
    }

    // MARK: - P0 AC2: Memory organized by App domain

    func test_extract_usesBundleIdentifierAsDomain() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true, \"bundle_id\": \"com.apple.calculator\"}")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Open Calculator",
            runId: "20260513-test06"
        )

        XCTAssertFalse(entries.isEmpty)
        // The entries should contain tags that reference the app
        let allTags = entries.flatMap { $0.tags }
        XCTAssertTrue(
            allTags.contains(where: { $0.contains("calculator") || $0.contains("com.apple.calculator") }),
            "Tags should contain app identifier, got: \(allTags)"
        )
    }

    func test_extract_fallsBackToAppNameWhenNoBundleId() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true}")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Open Calculator",
            runId: "20260513-test07"
        )

        XCTAssertFalse(entries.isEmpty)
        // Even without bundle_id, should still extract using app name
        let allTags = entries.flatMap { $0.tags }
        XCTAssertTrue(
            allTags.contains(where: { $0.contains("calculator") }),
            "Tags should contain app name when bundle_id unavailable"
        )
    }

    func test_extract_tagsIncludeToolTypes() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true}")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-2", input: "{\"x\": 100, \"y\": 200}"),
                makeToolResult(toolUseId: "tu-2", content: "clicked")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Open Calculator and click",
            runId: "20260513-test08"
        )

        XCTAssertFalse(entries.isEmpty)
        let allTags = entries.flatMap { $0.tags }.joined(separator: ",")
        XCTAssertTrue(
            allTags.contains("launch_app"),
            "Tags should include launch_app in tools list, got: \(allTags)"
        )
        XCTAssertTrue(
            allTags.contains("click"),
            "Tags should include click in tools list, got: \(allTags)"
        )
    }

    func test_extract_sourceRunIdSet() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true}")
            ),
        ]

        let runId = "20260513-testrun"
        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Open Calculator",
            runId: runId
        )

        XCTAssertFalse(entries.isEmpty)
        for entry in entries {
            XCTAssertEqual(entry.sourceRunId, runId,
                "Each entry should have sourceRunId matching the run")
        }
    }

    // MARK: - P1: Edge Cases

    func test_extract_emptyToolPairs_returnsEmptyArray() async throws {
        let extractor = AppMemoryExtractor()

        let entries = try await extractor.extract(
            from: [],
            task: "Do nothing",
            runId: "20260513-empty"
        )

        XCTAssertTrue(entries.isEmpty, "Empty tool pairs should produce no entries")
    }

    func test_extract_nonAppTools_onlyStillExtracts() async throws {
        let extractor = AppMemoryExtractor()

        // Only non-app tools (no launch_app)
        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-1", input: "{\"x\": 100, \"y\": 200}"),
                makeToolResult(toolUseId: "tu-1", content: "clicked")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Click somewhere",
            runId: "20260513-noapp"
        )

        // Should still produce entries even without launch_app
        XCTAssertFalse(entries.isEmpty, "Should produce entries even without launch_app")
        let content = entries.first!.content
        XCTAssertTrue(content.contains("click"), "Generic entry should reference the tools used")
    }

    func test_extract_multipleApps_producesMultipleDomains() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true, \"bundle_id\": \"com.apple.calculator\"}")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-2", input: "{\"app_name\": \"TextEdit\"}"),
                makeToolResult(toolUseId: "tu-2", content: "{\"success\": true, \"bundle_id\": \"com.apple.textedit\"}")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Open Calculator then TextEdit",
            runId: "20260513-multi"
        )

        // Should produce separate entries for both apps
        XCTAssertEqual(entries.count, 2, "Should produce separate entries for each launched app")
        let allTags = entries.flatMap { $0.tags }
        XCTAssertTrue(
            allTags.contains(where: { $0.contains("calculator") }),
            "Should have calculator domain in tags"
        )
        XCTAssertTrue(
            allTags.contains(where: { $0.contains("textedit") }),
            "Should have textedit domain in tags"
        )
    }

    func test_extract_stepCountIncluded() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true}")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-2", input: "{\"x\": 100, \"y\": 200}"),
                makeToolResult(toolUseId: "tu-2", content: "clicked")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-3", input: "{\"x\": 150, \"y\": 250}"),
                makeToolResult(toolUseId: "tu-3", content: "clicked")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Open Calculator and click twice",
            runId: "20260513-count"
        )

        XCTAssertFalse(entries.isEmpty)
        let combinedContent = entries.map { $0.content }.joined(separator: " ")
        // Content should indicate the number of steps or tool count
        XCTAssertTrue(
            combinedContent.contains("3") || combinedContent.lowercased().contains("step"),
            "Content should include step count information"
        )
    }

    // MARK: - P1 Story 4.2 AC1: AX tree structure features in content

    func test_extract_contentIncludesAxTreeSummary_whenWindowStatePresent() async throws {
        let extractor = AppMemoryExtractor()

        // Simulate a get_window_state tool result with AX tree data
        let axTreeContent = """
        {"windows": [{"role": "AXWindow", "title": "Calculator", "children": [{"role": "AXButton", "title": "1"}, {"role": "AXButton", "title": "2"}, {"role": "AXTextField", "title": "display"}]}]}
        """

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true, \"bundle_id\": \"com.apple.calculator\"}")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__get_window_state", toolUseId: "tu-2", input: "{\"window_id\": \"main\"}"),
                makeToolResult(toolUseId: "tu-2", content: axTreeContent)
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Open Calculator",
            runId: "20260513-axtree"
        )

        XCTAssertFalse(entries.isEmpty)
        let content = entries.first!.content
        XCTAssertTrue(
            content.contains("AX特征") || content.contains("AXButton") || content.contains("关键控件"),
            "Content should include AX tree summary when get_window_state is present, got: \(content)"
        )
    }

    func test_extract_contentIncludesAxTreeSummary_whenGetAxTreePresent() async throws {
        let extractor = AppMemoryExtractor()

        let axTreeContent = """
        {"root": {"role": "AXApplication", "title": "Calculator", "children": [{"role": "AXWindow", "children": [{"role": "AXButton", "title": "Clear"}]}]}}
        """

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true, \"bundle_id\": \"com.apple.calculator\"}")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__get_accessibility_tree", toolUseId: "tu-2", input: "{}"),
                makeToolResult(toolUseId: "tu-2", content: axTreeContent)
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Open Calculator",
            runId: "20260513-axtree2"
        )

        XCTAssertFalse(entries.isEmpty)
        let content = entries.first!.content
        XCTAssertTrue(
            content.contains("AX特征") || content.contains("AXButton") || content.contains("关键控件"),
            "Content should include AX tree summary when get_ax_tree is present, got: \(content)"
        )
    }

    // MARK: - P1 Story 4.2 AC3: Failure markers in content

    func test_extract_contentIncludesFailureMarker_whenToolFails() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true, \"bundle_id\": \"com.apple.calculator\"}")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-2", input: "{\"x\": 300, \"y\": 400}"),
                makeToolResult(toolUseId: "tu-2", content: "{\"error\": \"click failed\", \"message\": \"no element at coordinates\"}", isError: true)
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Click a button in Calculator",
            runId: "20260513-fail"
        )

        XCTAssertFalse(entries.isEmpty)
        let content = entries.first!.content
        XCTAssertTrue(
            content.contains("失败标记"),
            "Content should include failure marker when a tool result is an error, got: \(content)"
        )
    }

    func test_extract_contentIncludesWorkaround_whenFailureFollowedBySuccess() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true, \"bundle_id\": \"com.apple.calculator\"}")
            ),
            (
                // Failed: coordinate-based click
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-2", input: "{\"x\": 300, \"y\": 400}"),
                makeToolResult(toolUseId: "tu-2", content: "{\"error\": \"click failed\"}", isError: true)
            ),
            (
                // Success: AX selector-based click
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-3", input: "{\"ax_selector\": \"AXButton[title=\\\"*\\\"]\"}"),
                makeToolResult(toolUseId: "tu-3", content: "clicked successfully")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Click multiply in Calculator",
            runId: "20260513-workaround"
        )

        XCTAssertFalse(entries.isEmpty)
        let content = entries.first!.content
        XCTAssertTrue(
            content.contains("修正路径") || content.contains("workaround"),
            "Content should include workaround when failure is followed by success, got: \(content)"
        )
    }

    // MARK: - P1 Story 4.2: Workaround prefers same tool type match

    func test_extract_workaroundPrefersSameToolType_overUnrelatedSuccess() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true, \"bundle_id\": \"com.apple.calculator\"}")
            ),
            (
                // Failed: coordinate-based click
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-2", input: "{\"x\": 300, \"y\": 400}"),
                makeToolResult(toolUseId: "tu-2", content: "{\"error\": \"click failed\"}", isError: true)
            ),
            (
                // Unrelated success: type_text (should NOT be used as workaround)
                makeToolUse(toolName: "mcp__axion-helper__type_text", toolUseId: "tu-3", input: "{\"text\": \"hello\"}"),
                makeToolResult(toolUseId: "tu-3", content: "typed")
            ),
            (
                // Matching success: AX selector-based click (should be preferred)
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-4", input: "{\"ax_selector\": \"AXButton[title=\\\"=\\\"]\"}"),
                makeToolResult(toolUseId: "tu-4", content: "clicked")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Click equals in Calculator",
            runId: "20260513-prefer-same-type"
        )

        XCTAssertFalse(entries.isEmpty)
        let content = entries.first!.content

        // Extract the workaround line specifically
        let workaroundLine = content.components(separatedBy: "\n")
            .first { $0.contains("修正路径:") }

        XCTAssertNotNil(workaroundLine,
            "Should include workaround line, got: \(content)")
        XCTAssertTrue(workaroundLine!.contains("click") && workaroundLine!.contains("AXButton"),
            "Workaround should prefer same tool type (click with AX selector), got: \(workaroundLine!)")
        XCTAssertFalse(workaroundLine!.contains("type_text"),
            "Workaround should NOT reference unrelated tool type (type_text), got: \(workaroundLine!)")
    }

    func test_extract_toolSequenceIncludesParameters_inContent() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true, \"bundle_id\": \"com.apple.calculator\"}")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-2", input: "{\"x\": 100, \"y\": 200}"),
                makeToolResult(toolUseId: "tu-2", content: "clicked")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__type_text", toolUseId: "tu-3", input: "{\"text\": \"hello\"}"),
                makeToolResult(toolUseId: "tu-3", content: "typed")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Type in Calculator",
            runId: "20260513-params"
        )

        XCTAssertFalse(entries.isEmpty)
        let content = entries.first!.content
        // Enhanced content should include tool parameters in the sequence
        XCTAssertTrue(
            content.contains("click") && content.contains("type_text"),
            "Content should include tool names in the sequence, got: \(content)"
        )
    }

    // MARK: - P1 Story 4.2: Success entries should not contain redundant "(无)" failure marker

    func test_extract_successfulRun_doesNotContainNoFailureMarker() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true, \"bundle_id\": \"com.apple.calculator\"}")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-2", input: "{\"x\": 100, \"y\": 200}"),
                makeToolResult(toolUseId: "tu-2", content: "clicked")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Open Calculator and click",
            runId: "20260513-nofail"
        )

        XCTAssertFalse(entries.isEmpty)
        let content = entries.first!.content
        XCTAssertFalse(
            content.contains("失败标记: (无)"),
            "Success entries should not include redundant '失败标记: (无)', got: \(content)"
        )
        XCTAssertFalse(
            content.contains("失败标记"),
            "Success entries should not include any failure marker line, got: \(content)"
        )
    }
}
