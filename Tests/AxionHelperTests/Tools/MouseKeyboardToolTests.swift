import Foundation
import MCP
import MCPTool
import Testing
@testable import AxionHelper
@testable import AxionCore

@MainActor
extension ToolsTests {
@Suite("MouseKeyboardTool")
struct MouseKeyboardToolTests {

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

    @Test("click valid coordinates returns success JSON")
    func clickValidCoordinatesReturnsSuccessJson() async throws {
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

        #expect(json?["success"] as? Bool == true)
        #expect(json?["action"] as? String == "click")
        #expect(json?["x"] as? Int == 100)
        #expect(json?["y"] as? Int == 200)
    }

    @Test("click out of bounds returns error JSON")
    func clickOutOfBoundsReturnsErrorJson() async throws {
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

        #expect(json?["error"] as? String == "coordinates_out_of_bounds")
        #expect(json?["message"] != nil)
        #expect(json?["suggestion"] != nil)
    }

    @Test("double click valid coordinates returns success JSON")
    func doubleClickValidCoordinatesReturnsSuccessJson() async throws {
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

        #expect(json?["success"] as? Bool == true)
        #expect(json?["action"] as? String == "double_click")
    }

    @Test("right click valid coordinates returns success JSON")
    func rightClickValidCoordinatesReturnsSuccessJson() async throws {
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

        #expect(json?["success"] as? Bool == true)
        #expect(json?["action"] as? String == "right_click")
    }

    @Test("type text valid text returns success JSON")
    func typeTextValidTextReturnsSuccessJson() async throws {
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

        #expect(json?["success"] as? Bool == true)
        #expect(json?["action"] as? String == "type_text")
        #expect(json?["text"] as? String == "Hello World")
    }

    @Test("type text unicode characters returns success JSON")
    func typeTextUnicodeCharactersReturnsSuccessJson() async throws {
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

        #expect(json?["success"] as? Bool == true)
    }

    @Test("press key valid key returns success JSON")
    func pressKeyValidKeyReturnsSuccessJson() async throws {
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

        #expect(json?["success"] as? Bool == true)
        #expect(json?["action"] as? String == "press_key")
        #expect(json?["key"] as? String == "return")
    }

    @Test("press key invalid key name returns error JSON")
    func pressKeyInvalidKeyNameReturnsErrorJson() async throws {
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

        #expect(json?["error"] as? String == "invalid_key_name")
        #expect(json?["message"] != nil)
        #expect(json?["suggestion"] != nil)
    }

    @Test("hotkey valid combination returns success JSON")
    func hotkeyValidCombinationReturnsSuccessJson() async throws {
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

        #expect(json?["success"] as? Bool == true)
        #expect(json?["action"] as? String == "hotkey")
        #expect(json?["keys"] as? String == "cmd+c")
    }

    @Test("hotkey invalid format returns error JSON")
    func hotkeyInvalidFormatReturnsErrorJson() async throws {
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

        #expect(json?["error"] as? String == "invalid_hotkey_format")
        #expect(json?["message"] != nil)
        #expect(json?["suggestion"] != nil)
    }

    @Test("scroll valid direction returns success JSON")
    func scrollValidDirectionReturnsSuccessJson() async throws {
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

        #expect(json?["success"] as? Bool == true)
        #expect(json?["action"] as? String == "scroll")
        #expect(json?["direction"] as? String == "down")
        #expect(json?["amount"] as? Int == 3)
    }

    @Test("scroll invalid direction returns error JSON")
    func scrollInvalidDirectionReturnsErrorJson() async throws {
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

        #expect(json?["error"] as? String == "invalid_direction")
        #expect(json?["message"] != nil)
        #expect(json?["suggestion"] != nil)
    }

    @Test("drag valid coordinates returns success JSON")
    func dragValidCoordinatesReturnsSuccessJson() async throws {
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

        #expect(json?["success"] as? Bool == true)
        #expect(json?["action"] as? String == "drag")
    }

    @Test("drag out of bounds returns error JSON")
    func dragOutOfBoundsReturnsErrorJson() async throws {
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

        #expect(json?["error"] as? String == "coordinates_out_of_bounds")
        #expect(json?["message"] != nil)
        #expect(json?["suggestion"] != nil)
    }

    @Test("click does not return stub text")
    func clickDoesNotReturnStubText() async throws {
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
        #expect(!text.hasPrefix("Not yet implemented"))
    }

    @Test("type text does not return stub text")
    func typeTextDoesNotReturnStubText() async throws {
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
        #expect(!text.hasPrefix("Not yet implemented"))
    }
}
}
