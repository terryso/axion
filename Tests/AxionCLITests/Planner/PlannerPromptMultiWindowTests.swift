import XCTest
@testable import AxionCLI

// [P1] Story 8.1 AC2: Planner prompt multi-window guidance
// Verifies that planner-system.md contains the required multi-window workflow instructions.

final class PlannerPromptMultiWindowTests: XCTestCase {

    private var promptContent: String!

    override func setUp() {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        do {
            promptContent = try PromptBuilder.load(name: "planner-system", variables: [:], fromDirectory: promptDir)
        } catch {
            XCTFail("Failed to load planner-system.md: \(error)")
        }
    }

    // MARK: - AC2: Multi-Window Workflow section exists

    func test_plannerPrompt_containsMultiWindowSection() {
        XCTAssertTrue(promptContent.contains("# Multi-Window Workflow"),
            "planner-system.md should contain a 'Multi-Window Workflow' section heading")
    }

    func test_plannerPrompt_containsZOrderGuidance() {
        XCTAssertTrue(promptContent.contains("z_order"),
            "planner-system.md should mention z_order for window layer ordering")
    }

    func test_plannerPrompt_containsActivateWindowGuidance() {
        XCTAssertTrue(promptContent.contains("activate_window"),
            "planner-system.md should instruct LLM to use activate_window for window switching")
    }

    func test_plannerPrompt_containsMinimizedWindowHandling() {
        XCTAssertTrue(promptContent.contains("minimized") || promptContent.contains("minimize"),
            "planner-system.md should provide guidance for handling minimized windows")
    }

    func test_plannerPrompt_containsListWindowsWithoutPid() {
        XCTAssertTrue(promptContent.contains("list_windows") && promptContent.contains("without") && promptContent.contains("pid"),
            "planner-system.md should explain that list_windows without pid returns all app windows")
    }

    // MARK: - AC2: Cross-Application Workflow Patterns

    func test_plannerPrompt_containsCrossAppWorkflowPattern() {
        XCTAssertTrue(promptContent.contains("Cross-Application") || promptContent.contains("cross-app") || promptContent.contains("multiple applications"),
            "planner-system.md should contain cross-application workflow patterns")
    }

    func test_plannerPrompt_containsClipboardGuidance() {
        XCTAssertTrue(promptContent.contains("clipboard") || promptContent.contains("command+c") || promptContent.contains("command+v"),
            "planner-system.md should explain clipboard usage for cross-app data transfer")
    }
}
