import Testing
import Foundation
@testable import AxionCLI

@Suite("PlannerPromptMultiWindow")
struct PlannerPromptMultiWindowTests {

    private let promptContent: String

    init() {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        do {
            promptContent = try PromptBuilder.load(name: "planner-system", variables: [:], fromDirectory: promptDir)
        } catch {
            promptContent = ""  // Will cause tests to fail via #expect
            Issue.record("Failed to load planner-system.md: \(error)")
        }
    }

    @Test("AC2: planner prompt contains multi-window section")
    func plannerPromptContainsMultiWindowSection() {
        #expect(promptContent.contains("# Multi-Window Workflow"))
    }

    @Test("AC2: planner prompt contains z_order guidance")
    func plannerPromptContainsZOrderGuidance() {
        #expect(promptContent.contains("z_order"))
    }

    @Test("AC2: planner prompt contains activate_window guidance")
    func plannerPromptContainsActivateWindowGuidance() {
        #expect(promptContent.contains("activate_window"))
    }

    @Test("AC2: planner prompt contains minimized window handling")
    func plannerPromptContainsMinimizedWindowHandling() {
        #expect(promptContent.contains("minimized") || promptContent.contains("minimize"))
    }

    @Test("AC2: planner prompt contains list_windows without pid")
    func plannerPromptContainsListWindowsWithoutPid() {
        #expect(promptContent.contains("list_windows") && promptContent.contains("without") && promptContent.contains("pid"))
    }

    @Test("AC2: planner prompt contains cross-app workflow pattern")
    func plannerPromptContainsCrossAppWorkflowPattern() {
        #expect(promptContent.contains("Cross-Application") || promptContent.contains("cross-app") || promptContent.contains("multiple applications"))
    }

    @Test("AC2: planner prompt contains clipboard guidance")
    func plannerPromptContainsClipboardGuidance() {
        #expect(promptContent.contains("clipboard") || promptContent.contains("command+c") || promptContent.contains("command+v"))
    }
}
