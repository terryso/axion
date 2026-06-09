import Hummingbird
import OpenAgentSDK

typealias APIErrorResponse = OpenAgentSDK.APIErrorResponse

/// Response body for `GET /v1/capabilities`.
struct CapabilitiesResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let version: String
    let supportedRunStatuses: [String]
    let supportedResultKinds: [String]
    let availableTools: [String]
    let maxConcurrentRuns: Int
    let features: [String]

    enum CodingKeys: String, CodingKey {
        case version
        case supportedRunStatuses = "supported_run_statuses"
        case supportedResultKinds = "supported_result_kinds"
        case availableTools = "available_tools"
        case maxConcurrentRuns = "max_concurrent_runs"
        case features
    }
}

/// Response body for `GET /v1/settings/api-key`.
struct ApiKeyStatusResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let provider: String
    let available: Bool
    let source: String
    let maskedKey: String

    enum CodingKeys: String, CodingKey {
        case provider
        case available
        case source
        case maskedKey = "masked_key"
    }

    /// Mask an API key for safe display.
    /// Format: first 7 + "****" + last 4 (e.g. "sk-ant-****xxxx").
    /// Keys shorter than 11 chars: "****" + last 4. Empty keys: "".
    static func maskKey(_ key: String) -> String {
        if key.isEmpty { return "" }
        if key.count < 11 {
            let suffix = String(key.suffix(4))
            return "****\(suffix)"
        }
        let prefix = String(key.prefix(7))
        let suffix = String(key.suffix(4))
        return "\(prefix)****\(suffix)"
    }
}

/// Request body for `POST /v1/settings/api-key`.
struct SaveApiKeyRequest: Codable, Equatable, Sendable {
    let apiKey: String
    let provider: String?

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case provider
    }
}

/// Response body for `DELETE /v1/settings/api-key`.
struct DeleteApiKeyResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let provider: String
    let available: Bool
    let source: String
}
