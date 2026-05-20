import Foundation
import MCP
import MCPTool

enum KeyboardTools {
    static func register(to server: MCPServer) async throws {
        try await server.register {
            TypeTextTool.self
            PressKeyTool.self
            HotkeyTool.self
        }
    }
}

// MARK: - Keyboard Tools (Story 1.4)

@Tool
struct TypeTextTool {
    static let name = "type_text"
    static let description = "Type text at the current cursor position"

    @Parameter(description: "Text to type")
    var text: String

    @Parameter(description: "Process ID of the target application (optional, for context)")
    var pid: Int?

    @Parameter(key: "window_id", description: "Window identifier (optional, for context)")
    var windowId: Int?

    func perform() async throws -> String {
        do {
            try ServiceContainer.shared.inputSimulation.typeText(text)
            let result = TextActionResult(success: true, action: "type_text", text: text)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as InputSimulationError {
            let payload = ToolErrorPayload(
                error: error.errorCode,
                message: error.localizedDescription,
                suggestion: error.suggestion
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}

@Tool
struct PressKeyTool {
    static let name = "press_key"
    static let description = "Press a keyboard key"

    @Parameter(description: "Key to press (e.g. 'return', 'tab', 'escape')")
    var key: String

    @Parameter(description: "Process ID of the target application (optional, for context)")
    var pid: Int?

    @Parameter(key: "window_id", description: "Window identifier (optional, for context)")
    var windowId: Int?

    func perform() async throws -> String {
        do {
            try ServiceContainer.shared.inputSimulation.pressKey(key)
            let result = KeyActionResult(success: true, action: "press_key", key: key)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as InputSimulationError {
            let payload = ToolErrorPayload(
                error: error.errorCode,
                message: error.localizedDescription,
                suggestion: error.suggestion
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}

@Tool
struct HotkeyTool {
    static let name = "hotkey"
    static let description = "Press a keyboard shortcut / hotkey combination"

    @Parameter(description: "Key combination (e.g. 'cmd+c', 'cmd+shift+s')")
    var keys: String

    @Parameter(description: "Process ID of the target application (optional, for context)")
    var pid: Int?

    @Parameter(key: "window_id", description: "Window identifier (optional, for context)")
    var windowId: Int?

    func perform() async throws -> String {
        do {
            try ServiceContainer.shared.inputSimulation.hotkey(keys)
            let result = HotkeyActionResult(success: true, action: "hotkey", keys: keys)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as InputSimulationError {
            let payload = ToolErrorPayload(
                error: error.errorCode,
                message: error.localizedDescription,
                suggestion: error.suggestion
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}
