import XCTest
@testable import AxionCLI
@testable import AxionCore

// [P0] 基础设施验证
// [P1] 行为验证

// MARK: - PlaceholderResolver ATDD Tests

/// ATDD 红色阶段测试 — 覆盖 Story 3-3 AC2 ($pid 占位符解析) 和 AC3 ($window_id 占位符解析)
/// 这些测试将在 PlaceholderResolver 实现后通过 (TDD red-green-refactor)
final class PlaceholderResolverTests: XCTestCase {

    // MARK: - P0 类型存在性

    func test_placeholderResolver_typeExists() {
        let _ = PlaceholderResolver.self
    }

    func test_executionContext_typeExists() {
        let _ = ExecutionContext.self
    }

    // MARK: - P0 $pid 占位符解析 (AC2)

    func test_resolve_pidPlaceholder_replacesWithPid() {
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

        XCTAssertEqual(resolved.parameters["pid"], .int(1234))
        XCTAssertEqual(resolved.parameters["x"], .int(100))
        XCTAssertEqual(resolved.parameters["y"], .int(200))
    }

    func test_resolve_pidPlaceholder_notSet_preservesPlaceholder() {
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
        XCTAssertEqual(resolved.parameters["pid"], .placeholder("$pid"))
    }

    // MARK: - P0 $window_id 占位符解析 (AC3)

    func test_resolve_windowIdPlaceholder_replacesWithWindowId() {
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

        XCTAssertEqual(resolved.parameters["pid"], .int(1234))
        XCTAssertEqual(resolved.parameters["window_id"], .int(42))
        XCTAssertEqual(resolved.parameters["text"], .string("17*23="))
    }

    func test_resolve_windowIdPlaceholder_notSet_preservesPlaceholder() {
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

        XCTAssertEqual(resolved.parameters["window_id"], .placeholder("$window_id"))
    }

    // MARK: - P0 多占位符混合

    func test_resolve_multiplePlaceholders_allResolved() {
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

        XCTAssertEqual(resolved.parameters["pid"], .int(5678))
        XCTAssertEqual(resolved.parameters["window_id"], .int(99))
        XCTAssertEqual(resolved.parameters["x"], .int(300))
        XCTAssertEqual(resolved.parameters["y"], .int(400))
    }

    func test_resolve_noPlaceholders_preservesAllParams() {
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

        XCTAssertEqual(resolved.parameters["app_name"], .string("Calculator"))
        XCTAssertEqual(resolved, step)
    }

    // MARK: - P0 未知占位符保留

    func test_resolve_unknownPlaceholder_preservesOriginal() {
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

        XCTAssertEqual(resolved.parameters["ref"], .placeholder("$unknown_ref"))
    }

    func test_resolve_mixedResolvedAndUnresolved() {
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

        XCTAssertEqual(resolved.parameters["pid"], .int(100))
        XCTAssertEqual(resolved.parameters["window_id"], .placeholder("$window_id"))
        XCTAssertEqual(resolved.parameters["x"], .int(10))
    }

    // MARK: - P0 步骤元数据保留

    func test_resolve_preservesStepMetadata() {
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

        XCTAssertEqual(resolved.index, 5)
        XCTAssertEqual(resolved.tool, "type_text")
        XCTAssertEqual(resolved.purpose, "Type hello")
        XCTAssertEqual(resolved.expectedChange, "Text entered")
    }

    // MARK: - P1 absorbResult — 从 launch_app 结果提取 pid

    func test_absorbResult_launchApp_extractsPid() {
        let resolver = PlaceholderResolver()
        var context = ExecutionContext(pid: nil, windowId: nil)
        let result = """
        {"pid": 9876, "app_name": "Calculator", "status": "launched"}
        """

        resolver.absorbResult(tool: "launch_app", result: result, context: &context)

        XCTAssertEqual(context.pid, 9876)
        XCTAssertNil(context.windowId)
    }

    // MARK: - P1 absorbResult — 从 list_windows 结果提取 window_id

    func test_absorbResult_listWindows_extractsWindowId() {
        let resolver = PlaceholderResolver()
        var context = ExecutionContext(pid: nil, windowId: nil)
        let result = """
        {"windows": [{"window_id": 42, "pid": 1234, "title": "Calculator", "bounds": {"x": 0, "y": 0, "width": 300, "height": 500}}]}
        """

        resolver.absorbResult(tool: "list_windows", result: result, context: &context)

        XCTAssertEqual(context.windowId, 42)
        XCTAssertEqual(context.pid, 1234)
    }

    // MARK: - P1 absorbResult — 从 get_window_state 结果提取 window_id

    func test_absorbResult_getWindowState_extractsWindowId() {
        let resolver = PlaceholderResolver()
        var context = ExecutionContext(pid: nil, windowId: nil)
        let result = """
        {"window_id": 77, "title": "Notes", "pid": 5555, "elements": []}
        """

        resolver.absorbResult(tool: "get_window_state", result: result, context: &context)

        XCTAssertEqual(context.windowId, 77)
        XCTAssertEqual(context.pid, 5555)
    }

    // MARK: - P1 absorbResult — 非 pid/window_id 产出工具不改变 context

    func test_absorbResult_nonContextTool_doesNothing() {
        let resolver = PlaceholderResolver()
        var context = ExecutionContext(pid: nil, windowId: nil)
        let result = """
        {"x": 100, "y": 200, "success": true}
        """

        resolver.absorbResult(tool: "click", result: result, context: &context)

        XCTAssertNil(context.pid)
        XCTAssertNil(context.windowId)
    }

    func test_absorbResult_invalidJSON_doesNotCrash() {
        let resolver = PlaceholderResolver()
        var context = ExecutionContext(pid: 111, windowId: 22)
        let result = "not valid json {{{"

        resolver.absorbResult(tool: "launch_app", result: result, context: &context)

        // Context should remain unchanged on invalid JSON
        XCTAssertEqual(context.pid, 111)
        XCTAssertEqual(context.windowId, 22)
    }

    func test_absorbResult_launchAppWithoutPid_doesNotOverwrite() {
        let resolver = PlaceholderResolver()
        var context = ExecutionContext(pid: 100, windowId: nil)
        let result = """
        {"app_name": "Calculator", "status": "already_running"}
        """

        resolver.absorbResult(tool: "launch_app", result: result, context: &context)

        // Existing pid should not be cleared
        XCTAssertEqual(context.pid, 100)
    }

    func test_absorbResult_listWindowsEmptyArray_doesNotOverwrite() {
        let resolver = PlaceholderResolver()
        var context = ExecutionContext(pid: 100, windowId: 50)
        let result = """
        {"windows": []}
        """

        resolver.absorbResult(tool: "list_windows", result: result, context: &context)

        // Existing context should not be cleared
        XCTAssertEqual(context.pid, 100)
        XCTAssertEqual(context.windowId, 50)
    }
}
