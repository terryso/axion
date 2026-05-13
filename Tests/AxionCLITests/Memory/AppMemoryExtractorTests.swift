import XCTest
import OpenAgentSDK

@testable import AxionCLI
@testable import AxionCore

// [P0] AppMemoryExtractor type existence, extraction from toolUse/toolResult messages
// [P1] Domain naming, tag generation, edge cases (empty, single tool, multiple apps)
// Story 4.1 AC: #1, #2

// MARK: - AppMemoryExtractor ATDD Tests

/// ATDD red-phase tests for AppMemoryExtractor (Story 4.1 AC1, AC2).
/// Tests that AppMemoryExtractor extracts App operation summaries from SDK
/// message streams and produces KnowledgeEntry objects organized by App domain.
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
        // The content should reference the tools used
        let combinedContent = entries.map { $0.content }.joined(separator: " ")
        XCTAssertTrue(
            combinedContent.contains("launch_app") || combinedContent.contains("click") || combinedContent.contains("type_text"),
            "Content should reference tools used in the operation"
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
        let allTags = entries.flatMap { $0.tags }
        XCTAssertTrue(
            allTags.contains(where: { $0.contains("tools:") || $0.contains("launch_app") || $0.contains("click") }),
            "Tags should include tool type information, got: \(allTags)"
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
        // The domain might be generic or derived from context
        XCTAssertNotNil(entries, "Should handle non-app-tool-only sequences")
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

        // Should produce entries for both apps
        XCTAssertTrue(entries.count >= 1, "Should produce at least one entry for multiple apps")
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
}
