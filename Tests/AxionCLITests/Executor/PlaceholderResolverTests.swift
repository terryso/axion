import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

/// ATDD 红色阶段测试 — 覆盖 Story 3-3 AC2 ($pid 占位符解析) 和 AC3 ($window_id 占位符解析)
/// 这些测试将在 PlaceholderResolver 实现后通过 (TDD red-green-refactor)
@Suite("PlaceholderResolver")
struct PlaceholderResolverTests {

    @Test("placeholderResolver type exists")
    func placeholderResolverTypeExists() {
        let _ = PlaceholderResolver.self
    }

    @Test("executionContext type exists")
    func executionContextTypeExists() {
        let _ = ExecutionContext.self
    }

    @Test("$pid placeholder is replaced with actual pid")
    func resolvePidPlaceholderReplacesWithPid() {
        let resolver = PlaceholderResolver()
        let context = ExecutionContext(pid: 1234, windowId: nil)
        let step = Step(
            index: 1,
            tool: "click",
            parameters: [
                "pid": .placeholder("$pid"),
                "x": .int(100),
                "y": .int(200)
            ],
            purpose: "Click button",
            expectedChange: "Button clicked"
        )

        let resolved = resolver.resolve(step: step, context: context)

        #expect(resolved.parameters["pid"] == .int(1234))
        #expect(resolved.parameters["x"] == .int(100))
        #expect(resolved.parameters["y"] == .int(200))
    }

    @Test("$pid placeholder preserved when pid not set")
    func resolvePidPlaceholderNotSetPreservesPlaceholder() {
        let resolver = PlaceholderResolver()
        let context = ExecutionContext(pid: nil, windowId: nil)
        let step = Step(
            index: 1,
            tool: "click",
            parameters: [
                "pid": .placeholder("$pid"),
                "x": .int(100),
                "y": .int(200)
            ],
            purpose: "Click button",
            expectedChange: "Button clicked"
        )

        let resolved = resolver.resolve(step: step, context: context)

        // When pid is not yet set, placeholder should remain unchanged
        #expect(resolved.parameters["pid"] == .placeholder("$pid"))
    }

    @Test("$window_id placeholder is replaced with actual windowId")
    func resolveWindowIdPlaceholderReplacesWithWindowId() {
        let resolver = PlaceholderResolver()
        let context = ExecutionContext(pid: 1234, windowId: 42)
        let step = Step(
            index: 2,
            tool: "type_text",
            parameters: [
                "pid": .placeholder("$pid"),
                "window_id": .placeholder("$window_id"),
                "text": .string("17*23=")
            ],
            purpose: "Type expression",
            expectedChange: "Expression entered"
        )

        let resolved = resolver.resolve(step: step, context: context)

        #expect(resolved.parameters["pid"] == .int(1234))
        #expect(resolved.parameters["window_id"] == .int(42))
        #expect(resolved.parameters["text"] == .string("17*23="))
    }

    @Test("$window_id placeholder preserved when windowId not set")
    func resolveWindowIdPlaceholderNotSetPreservesPlaceholder() {
        let resolver = PlaceholderResolver()
        let context = ExecutionContext(pid: 1234, windowId: nil)
        let step = Step(
            index: 2,
            tool: "click",
            parameters: [
                "window_id": .placeholder("$window_id"),
                "x": .int(50),
                "y": .int(75)
            ],
            purpose: "Click element",
            expectedChange: "Element clicked"
        )

        let resolved = resolver.resolve(step: step, context: context)

        #expect(resolved.parameters["window_id"] == .placeholder("$window_id"))
    }

    @Test("multiple placeholders all resolved")
    func resolveMultiplePlaceholdersAllResolved() {
        let resolver = PlaceholderResolver()
        let context = ExecutionContext(pid: 5678, windowId: 99)
        let step = Step(
            index: 3,
            tool: "click",
            parameters: [
                "pid": .placeholder("$pid"),
                "window_id": .placeholder("$window_id"),
                "x": .int(300),
                "y": .int(400)
            ],
            purpose: "Click result",
            expectedChange: "Result clicked"
        )

        let resolved = resolver.resolve(step: step, context: context)

        #expect(resolved.parameters["pid"] == .int(5678))
        #expect(resolved.parameters["window_id"] == .int(99))
        #expect(resolved.parameters["x"] == .int(300))
        #expect(resolved.parameters["y"] == .int(400))
    }

    @Test("no placeholders preserves all params")
    func resolveNoPlaceholdersPreservesAllParams() {
        let resolver = PlaceholderResolver()
        let context = ExecutionContext(pid: 1234, windowId: 42)
        let step = Step(
            index: 0,
            tool: "launch_app",
            parameters: ["app_name": .string("Calculator")],
            purpose: "Open Calculator",
            expectedChange: "Calculator opens"
        )

        let resolved = resolver.resolve(step: step, context: context)

        #expect(resolved.parameters["app_name"] == .string("Calculator"))
        #expect(resolved == step)
    }

    @Test("unknown placeholder preserved")
    func resolveUnknownPlaceholderPreservesOriginal() {
        let resolver = PlaceholderResolver()
        let context = ExecutionContext(pid: 1234, windowId: 42)
        let step = Step(
            index: 1,
            tool: "custom_tool",
            parameters: ["ref": .placeholder("$unknown_ref")],
            purpose: "Custom op",
            expectedChange: "Something happens"
        )

        let resolved = resolver.resolve(step: step, context: context)

        #expect(resolved.parameters["ref"] == .placeholder("$unknown_ref"))
    }

    @Test("mixed resolved and unresolved placeholders")
    func resolveMixedResolvedAndUnresolved() {
        let resolver = PlaceholderResolver()
        let context = ExecutionContext(pid: 100, windowId: nil)
        let step = Step(
            index: 1,
            tool: "click",
            parameters: [
                "pid": .placeholder("$pid"),
                "window_id": .placeholder("$window_id"),
                "x": .int(10)
            ],
            purpose: "Click",
            expectedChange: "Clicked"
        )

        let resolved = resolver.resolve(step: step, context: context)

        #expect(resolved.parameters["pid"] == .int(100))
        #expect(resolved.parameters["window_id"] == .placeholder("$window_id"))
        #expect(resolved.parameters["x"] == .int(10))
    }

    @Test("step metadata preserved after resolve")
    func resolvePreservesStepMetadata() {
        let resolver = PlaceholderResolver()
        let context = ExecutionContext(pid: 1234, windowId: 42)
        let step = Step(
            index: 5,
            tool: "type_text",
            parameters: ["pid": .placeholder("$pid")],
            purpose: "Type hello",
            expectedChange: "Text entered"
        )

        let resolved = resolver.resolve(step: step, context: context)

        #expect(resolved.index == 5)
        #expect(resolved.tool == "type_text")
        #expect(resolved.purpose == "Type hello")
        #expect(resolved.expectedChange == "Text entered")
    }

    @Test("absorbResult from launch_app extracts pid")
    func absorbResultLaunchAppExtractsPid() {
        let resolver = PlaceholderResolver()
        var context = ExecutionContext(pid: nil, windowId: nil)
        let result = """
        {"pid": 9876, "app_name": "Calculator", "status": "launched"}
        """

        resolver.absorbResult(tool: "launch_app", result: result, context: &context)

        #expect(context.pid == 9876)
        #expect(context.windowId == nil)
    }

    @Test("absorbResult from list_windows extracts window_id")
    func absorbResultListWindowsExtractsWindowId() {
        let resolver = PlaceholderResolver()
        var context = ExecutionContext(pid: nil, windowId: nil)
        let result = """
        {"windows": [{"window_id": 42, "pid": 1234, "title": "Calculator", "bounds": {"x": 0, "y": 0, "width": 300, "height": 500}}]}
        """

        resolver.absorbResult(tool: "list_windows", result: result, context: &context)

        #expect(context.windowId == 42)
        #expect(context.pid == 1234)
    }

    @Test("absorbResult from get_window_state extracts window_id")
    func absorbResultGetWindowStateExtractsWindowId() {
        let resolver = PlaceholderResolver()
        var context = ExecutionContext(pid: nil, windowId: nil)
        let result = """
        {"window_id": 77, "title": "Notes", "pid": 5555, "elements": []}
        """

        resolver.absorbResult(tool: "get_window_state", result: result, context: &context)

        #expect(context.windowId == 77)
        #expect(context.pid == 5555)
    }

    @Test("absorbResult for non-context tool does nothing")
    func absorbResultNonContextToolDoesNothing() {
        let resolver = PlaceholderResolver()
        var context = ExecutionContext(pid: nil, windowId: nil)
        let result = """
        {"x": 100, "y": 200, "success": true}
        """

        resolver.absorbResult(tool: "click", result: result, context: &context)

        #expect(context.pid == nil)
        #expect(context.windowId == nil)
    }

    @Test("absorbResult with invalid JSON does not crash")
    func absorbResultInvalidJSONDoesNotCrash() {
        let resolver = PlaceholderResolver()
        var context = ExecutionContext(pid: 111, windowId: 22)
        let result = "not valid json {{{"

        resolver.absorbResult(tool: "launch_app", result: result, context: &context)

        // Context should remain unchanged on invalid JSON
        #expect(context.pid == 111)
        #expect(context.windowId == 22)
    }

    @Test("absorbResult from launch_app without pid does not overwrite")
    func absorbResultLaunchAppWithoutPidDoesNotOverwrite() {
        let resolver = PlaceholderResolver()
        var context = ExecutionContext(pid: 100, windowId: nil)
        let result = """
        {"app_name": "Calculator", "status": "already_running"}
        """

        resolver.absorbResult(tool: "launch_app", result: result, context: &context)

        // Existing pid should not be cleared
        #expect(context.pid == 100)
    }

    @Test("absorbResult from list_windows with empty array does not overwrite")
    func absorbResultListWindowsEmptyArrayDoesNotOverwrite() {
        let resolver = PlaceholderResolver()
        var context = ExecutionContext(pid: 100, windowId: 50)
        let result = """
        {"windows": []}
        """

        resolver.absorbResult(tool: "list_windows", result: result, context: &context)

        // Existing context should not be cleared
        #expect(context.pid == 100)
        #expect(context.windowId == 50)
    }
}
