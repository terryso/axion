import Foundation
import OpenAgentSDK

enum ToolResultHelper {

    static func encodeResult(toolUseId: String, isError: Bool, _ encode: (JSONEncoder) throws -> Data) -> ToolResult {
        let data = (try? encode(axionSortedEncoder)) ?? Data()
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

    /// Validates a required non-empty string parameter from a JSON params dict.
    /// Returns an error ToolResult if missing/empty, or nil if valid (caller unwraps via `guard`).
    static func requireStringParam(
        params: [String: Any], key: String, toolUseId: String,
        error: String, message: String, suggestion: String
    ) -> ToolResult? {
        guard let value = params[key] as? String, !value.isEmpty else {
            return errorResult(toolUseId: toolUseId, error: error, message: message, suggestion: suggestion)
        }
        return nil
    }

    /// Validates the common JSON-object → action → target → MemoryTarget chain
    /// shared by MemoryTool and ReviewSaveUniversalMemoryTool.
    /// Returns the validated (params, action, target) on success, or an error ToolResult.
    static func validateMemoryInput(
        input: Any, toolUseId: String, validActions: String
    ) -> MemoryInputValidation {
        guard let params = input as? [String: Any] else {
            return .error(errorResult(toolUseId: toolUseId, error: "invalid_input", message: "Input must be a JSON object", suggestion: "Pass a valid JSON object with 'action' and 'target'"))
        }

        guard let action = params["action"] as? String, !action.isEmpty else {
            return .error(errorResult(toolUseId: toolUseId, error: "missing_action", message: "Missing required 'action' parameter", suggestion: "Provide 'action' as one of: \(validActions)"))
        }

        guard let targetRaw = params["target"] as? String, !targetRaw.isEmpty else {
            return .error(errorResult(toolUseId: toolUseId, error: "missing_target", message: "Missing required 'target' parameter", suggestion: "Provide 'target' as 'memory' or 'user'"))
        }

        guard let target = MemoryTarget.fromCLIString(targetRaw) else {
            return .error(errorResult(toolUseId: toolUseId, error: "invalid_target", message: "Invalid target '\(targetRaw)'", suggestion: "Use 'memory' or 'user'"))
        }

        return .valid(params, action, target)
    }

    /// Scan content with the security scanner and return a rejection ToolResult if unsafe, or nil if safe.
    static func rejectIfUnsafe(content: String, scanner: MemorySecurityScanner, toolUseId: String) -> ToolResult? {
        if case .rejected(let reason) = scanner.scan(content: content) {
            return errorResult(toolUseId: toolUseId, error: "security_rejection", message: "Content blocked by security scanner: \(reason)", suggestion: "Modify the content to remove the problematic pattern")
        }
        return nil
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

/// Result of validating memory tool input parameters.
enum MemoryInputValidation {
    case valid([String: Any], String, MemoryTarget)
    case error(ToolResult)
}
