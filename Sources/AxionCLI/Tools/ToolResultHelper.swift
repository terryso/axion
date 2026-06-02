import Foundation
import OpenAgentSDK

enum ToolResultHelper {

    static func encodeResult(toolUseId: String, isError: Bool, _ encode: (JSONEncoder) throws -> Data) -> ToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encode(encoder)) ?? Data()
        let content = String(data: data, encoding: .utf8) ?? "{}"
        return ToolResult(toolUseId: toolUseId, content: content, isError: isError)
    }

    static func errorResult(toolUseId: String, error: String, message: String, suggestion: String) -> ToolResult {
        encodeResult(toolUseId: toolUseId, isError: true) { encoder in
            try encoder.encode(ErrorResponse(error: error, message: message, suggestion: suggestion))
        }
    }

    static func successResult(toolUseId: String, message: String) -> ToolResult {
        encodeResult(toolUseId: toolUseId, isError: false) { encoder in
            try encoder.encode(StatusSuccessResponse(status: "ok", message: message))
        }
    }

    static func savedResult(toolUseId: String, message: String) -> ToolResult {
        encodeResult(toolUseId: toolUseId, isError: false) { encoder in
            try encoder.encode(BoolSuccessResponse(success: true, message: message))
        }
    }
}

private struct ErrorResponse: Encodable {
    let error: String
    let message: String
    let suggestion: String
}

private struct StatusSuccessResponse: Encodable {
    let status: String
    let message: String
}

private struct BoolSuccessResponse: Encodable {
    let success: Bool
    let message: String
}
