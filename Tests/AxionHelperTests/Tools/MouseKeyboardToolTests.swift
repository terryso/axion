import Foundation
import MCP
import MCPTool
import XCTest
@testable import AxionHelper
@testable import AxionCore

// Unit tests for mouse and keyboard MCP tools (Story 1.4) using mock services.
// These tests do NOT perform real mouse/keyboard input — all CGEvent calls are mocked.
// Priority: P0 (core tool wiring for click, double_click, right_click, type_text, press_key, hotkey, scroll, drag)

@MainActor
final class MouseKeyboardToolTests: XCTestCase {

    // MARK: - Helpers

    private func makeRegisteredServer() async throws -> MCPServer {
        let server = MCPServer(name: "AxionHelper", version: "0.1.0")
        try await ToolRegistrar.registerAll(to: server)
        return server
    }

    private func makeTestContext() -> HandlerContext {
        let requestContext = RequestHandlerContext(
            sessionId: nil,
            requestId: .number(1),
            _meta: nil,
            taskId: nil,
            authInfo: nil,
            requestInfo: nil,
            closeResponseStream: nil,
            closeNotificationStream: nil,
            sendNotification: { _ in },
            sendRequest: { _ in Data() }
        )
        return HandlerContext(handlerContext: requestContext, progressToken: nil)
    }

    private func textContent(_ result: CallTool.Result) -> String {
        result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()
    }

    /// Creates a MockInputSimulation that succeeds for all operations.
    private func makeSuccessMock() -> MockInputSimulation {
        MockInputSimulation(
            clickHandler: { _, _ in },
            doubleClickHandler: { _, _ in },
            rightClickHandler: { _, _ in },
            scrollHandler: { _, _ in },
            dragHandler: { _, _, _, _ in },
            typeTextHandler: { _ in },
            pressKeyHandler: { _ in },
            hotkeyHandler: { _ in }
        )
    }

    // MARK: - AC1: click

    func test_click_validCoordinates_returnsSuccessJson() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: makeSuccessMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "click",
            arguments: ["x": .int(100), "y": .int(200)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertEqual(json?["action"] as? String, "click")
        XCTAssertEqual(json?["x"] as? Int, 100)
        XCTAssertEqual(json?["y"] as? Int, 200)
    }

    func test_click_outOfBounds_returnsErrorJson() async throws {
        let mock = MockInputSimulation(
            clickHandler: { x, y in throw InputSimulationError.coordinatesOutOfBounds(x: x, y: y) },
            doubleClickHandler: { _, _ in },
            rightClickHandler: { _, _ in },
            scrollHandler: { _, _ in },
            dragHandler: { _, _, _, _ in },
            typeTextHandler: { _ in },
            pressKeyHandler: { _ in },
            hotkeyHandler: { _ in }
        )
        let restore = ServiceContainerFixture.apply(inputSimulation: mock)
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "click",
            arguments: ["x": .int(-1), "y": .int(-1)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["error"] as? String, "coordinates_out_of_bounds")
        XCTAssertNotNil(json?["message"])
        XCTAssertNotNil(json?["suggestion"])
    }

    // MARK: - AC2: double_click

    func test_doubleClick_validCoordinates_returnsSuccessJson() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: makeSuccessMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "double_click",
            arguments: ["x": .int(150), "y": .int(250)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertEqual(json?["action"] as? String, "double_click")
    }

    // MARK: - AC3: right_click

    func test_rightClick_validCoordinates_returnsSuccessJson() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: makeSuccessMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "right_click",
            arguments: ["x": .int(300), "y": .int(400)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertEqual(json?["action"] as? String, "right_click")
    }

    // MARK: - AC4: type_text

    func test_typeText_validText_returnsSuccessJson() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: makeSuccessMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "type_text",
            arguments: ["text": .string("Hello World")],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertEqual(json?["action"] as? String, "type_text")
        XCTAssertEqual(json?["text"] as? String, "Hello World")
    }

    func test_typeText_unicodeCharacters_returnsSuccessJson() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: makeSuccessMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "type_text",
            arguments: ["text": .string("Hello\u{3000}World")],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["success"] as? Bool, true, "Unicode text should be handled")
    }

    // MARK: - AC5: press_key

    func test_pressKey_validKey_returnsSuccessJson() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: makeSuccessMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "press_key",
            arguments: ["key": .string("return")],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertEqual(json?["action"] as? String, "press_key")
        XCTAssertEqual(json?["key"] as? String, "return")
    }

    func test_pressKey_invalidKeyName_returnsErrorJson() async throws {
        let mock = MockInputSimulation(
            clickHandler: { _, _ in },
            doubleClickHandler: { _, _ in },
            rightClickHandler: { _, _ in },
            scrollHandler: { _, _ in },
            dragHandler: { _, _, _, _ in },
            typeTextHandler: { _ in },
            pressKeyHandler: { key in throw InputSimulationError.invalidKeyName(key) },
            hotkeyHandler: { _ in }
        )
        let restore = ServiceContainerFixture.apply(inputSimulation: mock)
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "press_key",
            arguments: ["key": .string("nonexistent_key")],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["error"] as? String, "invalid_key_name")
        XCTAssertNotNil(json?["message"])
        XCTAssertNotNil(json?["suggestion"])
    }

    // MARK: - AC6: hotkey

    func test_hotkey_validCombination_returnsSuccessJson() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: makeSuccessMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "hotkey",
            arguments: ["keys": .string("cmd+c")],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertEqual(json?["action"] as? String, "hotkey")
        XCTAssertEqual(json?["keys"] as? String, "cmd+c")
    }

    func test_hotkey_invalidFormat_returnsErrorJson() async throws {
        let mock = MockInputSimulation(
            clickHandler: { _, _ in },
            doubleClickHandler: { _, _ in },
            rightClickHandler: { _, _ in },
            scrollHandler: { _, _ in },
            dragHandler: { _, _, _, _ in },
            typeTextHandler: { _ in },
            pressKeyHandler: { _ in },
            hotkeyHandler: { keys in throw InputSimulationError.invalidHotkeyFormat(keys) }
        )
        let restore = ServiceContainerFixture.apply(inputSimulation: mock)
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "hotkey",
            arguments: ["keys": .string("c")],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["error"] as? String, "invalid_hotkey_format")
        XCTAssertNotNil(json?["message"])
        XCTAssertNotNil(json?["suggestion"])
    }

    // MARK: - AC7: scroll

    func test_scroll_validDirection_returnsSuccessJson() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: makeSuccessMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "scroll",
            arguments: ["direction": .string("down"), "amount": .int(3)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertEqual(json?["action"] as? String, "scroll")
        XCTAssertEqual(json?["direction"] as? String, "down")
        XCTAssertEqual(json?["amount"] as? Int, 3)
    }

    func test_scroll_invalidDirection_returnsErrorJson() async throws {
        let mock = MockInputSimulation(
            clickHandler: { _, _ in },
            doubleClickHandler: { _, _ in },
            rightClickHandler: { _, _ in },
            scrollHandler: { dir, _ in throw InputSimulationError.invalidDirection(dir) },
            dragHandler: { _, _, _, _ in },
            typeTextHandler: { _ in },
            pressKeyHandler: { _ in },
            hotkeyHandler: { _ in }
        )
        let restore = ServiceContainerFixture.apply(inputSimulation: mock)
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "scroll",
            arguments: ["direction": .string("diagonal"), "amount": .int(1)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["error"] as? String, "invalid_direction")
        XCTAssertNotNil(json?["message"])
        XCTAssertNotNil(json?["suggestion"])
    }

    // MARK: - AC8: drag

    func test_drag_validCoordinates_returnsSuccessJson() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: makeSuccessMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "drag",
            arguments: [
                "from_x": .int(100), "from_y": .int(100),
                "to_x": .int(200), "to_y": .int(200),
            ],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertEqual(json?["action"] as? String, "drag")
    }

    func test_drag_outOfBounds_returnsErrorJson() async throws {
        let mock = MockInputSimulation(
            clickHandler: { _, _ in },
            doubleClickHandler: { _, _ in },
            rightClickHandler: { _, _ in },
            scrollHandler: { _, _ in },
            dragHandler: { fx, fy, _, _ in throw InputSimulationError.coordinatesOutOfBounds(x: fx, y: fy) },
            typeTextHandler: { _ in },
            pressKeyHandler: { _ in },
            hotkeyHandler: { _ in }
        )
        let restore = ServiceContainerFixture.apply(inputSimulation: mock)
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "drag",
            arguments: [
                "from_x": .int(-1), "from_y": .int(-1),
                "to_x": .int(200), "to_y": .int(200),
            ],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["error"] as? String, "coordinates_out_of_bounds")
        XCTAssertNotNil(json?["message"])
        XCTAssertNotNil(json?["suggestion"])
    }

    // MARK: - No stub responses

    func test_click_doesNotReturnStubText() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: makeSuccessMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "click",
            arguments: ["x": .int(100), "y": .int(200)],
            context: makeTestContext()
        )

        let text = textContent(result)
        XCTAssertFalse(text.hasPrefix("Not yet implemented"), "Tool should not return stub text")
    }

    func test_typeText_doesNotReturnStubText() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: makeSuccessMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "type_text",
            arguments: ["text": .string("test")],
            context: makeTestContext()
        )

        let text = textContent(result)
        XCTAssertFalse(text.hasPrefix("Not yet implemented"), "Tool should not return stub text")
    }
}
