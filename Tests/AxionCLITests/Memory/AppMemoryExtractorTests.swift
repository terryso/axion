import Testing
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
/// and workaround inference in extracted contents.
@Suite("AppMemoryExtractor")
struct AppMemoryExtractorTests {

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

    @Test("type exists")
    func typeExists() {
        let _ = AppMemoryExtractor.self
    }

    // MARK: - P0 AC1: Extract from toolUse/toolResult messages

    @Test("extract returns knowledge entries from tool messages")
    func extractReturnsKnowledgeEntries() async throws {
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

        #expect(!entries.isEmpty, "Should extract at least one KnowledgeEntry")
        for entry in entries {
            #expect(!entry.content.isEmpty, "Entry content should not be empty")
            #expect(!entry.id.isEmpty, "Entry ID should not be empty")
        }
    }

    @Test("extract content includes tool sequence")
    func extractContentIncludesToolSequence() async throws {
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

        #expect(!entries.isEmpty)
        let combinedContent = entries.map { $0.content }.joined(separator: " ")
        #expect(combinedContent.contains("launch_app"), "Content should include launch_app in tool sequence")
        #expect(combinedContent.contains("click"), "Content should include click in tool sequence")
        #expect(combinedContent.contains("type_text"), "Content should include type_text in tool sequence")
    }

    @Test("extract content includes task description")
    func extractContentIncludesTaskDescription() async throws {
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

        #expect(!entries.isEmpty)
        let combinedContent = entries.map { $0.content }.joined(separator: " ")
        #expect(
            combinedContent.contains("Open Calculator") || combinedContent.contains("Calculator"),
            "Content should reference the original task description"
        )
    }

    @Test("extract includes success or failure path")
    func extractIncludesSuccessOrFailurePath() async throws {
        let extractor = AppMemoryExtractor()

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

        #expect(!entries.isEmpty)
        let combinedContent = entries.map { $0.content }.joined(separator: " ").lowercased()
        #expect(
            combinedContent.contains("fail") || combinedContent.contains("error") || combinedContent.contains("unsuccess"),
            "Content should indicate failure when tool returns error"
        )
    }

    @Test("extract successful path indicates success")
    func extractSuccessfulPathIndicatesSuccess() async throws {
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

        #expect(!entries.isEmpty)
        let combinedContent = entries.map { $0.content }.joined(separator: " ").lowercased()
        #expect(combinedContent.contains("success"), "Content should indicate success for non-error results")
    }

    // MARK: - P0 AC2: Memory organized by App domain

    @Test("extract uses bundle identifier as domain")
    func extractUsesBundleIdentifierAsDomain() async throws {
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

        #expect(!entries.isEmpty)
        let allTags = entries.flatMap { $0.tags }
        #expect(
            allTags.contains(where: { $0.contains("calculator") || $0.contains("com.apple.calculator") }),
            "Tags should contain app identifier, got: \(allTags)"
        )
    }

    @Test("extract falls back to app name when no bundle ID")
    func extractFallsBackToAppNameWhenNoBundleId() async throws {
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

        #expect(!entries.isEmpty)
        let allTags = entries.flatMap { $0.tags }
        #expect(
            allTags.contains(where: { $0.contains("calculator") }),
            "Tags should contain app name when bundle_id unavailable"
        )
    }

    @Test("extract tags include tool types")
    func extractTagsIncludeToolTypes() async throws {
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

        #expect(!entries.isEmpty)
        let allTags = entries.flatMap { $0.tags }.joined(separator: ",")
        #expect(allTags.contains("launch_app"), "Tags should include launch_app in tools list, got: \(allTags)")
        #expect(allTags.contains("click"), "Tags should include click in tools list, got: \(allTags)")
    }

    @Test("extract source run ID set")
    func extractSourceRunIdSet() async throws {
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

        #expect(!entries.isEmpty)
        for entry in entries {
            #expect(entry.sourceRunId == runId, "Each entry should have sourceRunId matching the run")
        }
    }

    // MARK: - P1: Edge Cases

    @Test("extract empty tool pairs returns empty array")
    func extractEmptyToolPairsReturnsEmptyArray() async throws {
        let extractor = AppMemoryExtractor()

        let entries = try await extractor.extract(
            from: [],
            task: "Do nothing",
            runId: "20260513-empty"
        )

        #expect(entries.isEmpty, "Empty tool pairs should produce no entries")
    }

    @Test("extract non-app tools still extracts")
    func extractNonAppToolsStillExtracts() async throws {
        let extractor = AppMemoryExtractor()

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

        #expect(!entries.isEmpty, "Should produce entries even without launch_app")
        let content = entries.first!.content
        #expect(content.contains("click"), "Generic entry should reference the tools used")
    }

    @Test("extract multiple apps produces multiple domains")
    func extractMultipleAppsProducesMultipleDomains() async throws {
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

        #expect(entries.count == 2, "Should produce separate entries for each launched app")
        let allTags = entries.flatMap { $0.tags }
        #expect(allTags.contains(where: { $0.contains("calculator") }), "Should have calculator domain in tags")
        #expect(allTags.contains(where: { $0.contains("textedit") }), "Should have textedit domain in tags")
    }

    @Test("extract step count included")
    func extractStepCountIncluded() async throws {
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

        #expect(!entries.isEmpty)
        let combinedContent = entries.map { $0.content }.joined(separator: " ")
        #expect(
            combinedContent.contains("3") || combinedContent.lowercased().contains("step"),
            "Content should include step count information"
        )
    }

    // MARK: - P1 Story 4.2 AC1: AX tree structure features in content

    @Test("extract content includes AX tree summary when window state present")
    func extractContentIncludesAxTreeSummaryWhenWindowStatePresent() async throws {
        let extractor = AppMemoryExtractor()

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

        #expect(!entries.isEmpty)
        let content = entries.first!.content
        #expect(
            content.contains("AX特征") || content.contains("AXButton") || content.contains("关键控件"),
            "Content should include AX tree summary when get_window_state is present, got: \(content)"
        )
    }

    @Test("extract content includes AX tree summary when get AX tree present")
    func extractContentIncludesAxTreeSummaryWhenGetAxTreePresent() async throws {
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

        #expect(!entries.isEmpty)
        let content = entries.first!.content
        #expect(
            content.contains("AX特征") || content.contains("AXButton") || content.contains("关键控件"),
            "Content should include AX tree summary when get_ax_tree is present, got: \(content)"
        )
    }

    // MARK: - P1 Story 4.2 AC3: Failure markers in content

    @Test("extract content includes failure marker when tool fails")
    func extractContentIncludesFailureMarkerWhenToolFails() async throws {
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

        #expect(!entries.isEmpty)
        let content = entries.first!.content
        #expect(
            content.contains("失败标记"),
            "Content should include failure marker when a tool result is an error, got: \(content)"
        )
    }

    @Test("extract content includes workaround when failure followed by success")
    func extractContentIncludesWorkaroundWhenFailureFollowedBySuccess() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true, \"bundle_id\": \"com.apple.calculator\"}")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-2", input: "{\"x\": 300, \"y\": 400}"),
                makeToolResult(toolUseId: "tu-2", content: "{\"error\": \"click failed\"}", isError: true)
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-3", input: "{\"ax_selector\": \"AXButton[title=\\\"*\\\"]\"}"),
                makeToolResult(toolUseId: "tu-3", content: "clicked successfully")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Click multiply in Calculator",
            runId: "20260513-workaround"
        )

        #expect(!entries.isEmpty)
        let content = entries.first!.content
        #expect(
            content.contains("修正路径") || content.contains("workaround"),
            "Content should include workaround when failure is followed by success, got: \(content)"
        )
    }

    // MARK: - P1 Story 4.2: Workaround prefers same tool type match

    @Test("extract workaround prefers same tool type over unrelated success")
    func extractWorkaroundPrefersSameToolTypeOverUnrelatedSuccess() async throws {
        let extractor = AppMemoryExtractor()

        let toolPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = [
            (
                makeToolUse(toolName: "mcp__axion-helper__launch_app", toolUseId: "tu-1", input: "{\"app_name\": \"Calculator\"}"),
                makeToolResult(toolUseId: "tu-1", content: "{\"success\": true, \"bundle_id\": \"com.apple.calculator\"}")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-2", input: "{\"x\": 300, \"y\": 400}"),
                makeToolResult(toolUseId: "tu-2", content: "{\"error\": \"click failed\"}", isError: true)
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__type_text", toolUseId: "tu-3", input: "{\"text\": \"hello\"}"),
                makeToolResult(toolUseId: "tu-3", content: "typed")
            ),
            (
                makeToolUse(toolName: "mcp__axion-helper__click", toolUseId: "tu-4", input: "{\"ax_selector\": \"AXButton[title=\\\"=\\\"]\"}"),
                makeToolResult(toolUseId: "tu-4", content: "clicked")
            ),
        ]

        let entries = try await extractor.extract(
            from: toolPairs,
            task: "Click equals in Calculator",
            runId: "20260513-prefer-same-type"
        )

        #expect(!entries.isEmpty)
        let content = entries.first!.content

        let workaroundLine = content.components(separatedBy: "\n")
            .first { $0.contains("修正路径:") }

        #expect(workaroundLine != nil, "Should include workaround line, got: \(content)")
        #expect(workaroundLine!.contains("click") && workaroundLine!.contains("AXButton"),
            "Workaround should prefer same tool type (click with AX selector), got: \(workaroundLine!)")
        #expect(!workaroundLine!.contains("type_text"),
            "Workaround should NOT reference unrelated tool type (type_text), got: \(workaroundLine!)")
    }

    @Test("extract tool sequence includes parameters in content")
    func extractToolSequenceIncludesParametersInContent() async throws {
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

        #expect(!entries.isEmpty)
        let content = entries.first!.content
        #expect(content.contains("click") && content.contains("type_text"),
            "Content should include tool names in the sequence, got: \(content)")
    }

    // MARK: - P1 Story 4.2: Success entries should not contain redundant failure marker

    @Test("extract successful run does not contain no failure marker")
    func extractSuccessfulRunDoesNotContainNoFailureMarker() async throws {
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

        #expect(!entries.isEmpty)
        let content = entries.first!.content
        #expect(!content.contains("失败标记: (无)"),
            "Success entries should not include redundant '失败标记: (无)', got: \(content)")
        #expect(!content.contains("失败标记"),
            "Success entries should not include any failure marker line, got: \(content)")
    }
}
