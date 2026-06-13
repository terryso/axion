import OpenAgentSDK

public enum AxionMcpServerConfig: Equatable, Sendable {
    case stdio(command: String, args: [String]?, env: [String: String]?)
    case sse(url: String, headers: [String: String]? = nil)
    case http(url: String, headers: [String: String]? = nil)

    public func toSdkConfig() -> McpServerConfig {
        switch self {
        case let .stdio(command, args, env):
            return .stdio(McpStdioConfig(command: command, args: args, env: env))
        case let .sse(url, headers):
            return .sse(McpSseConfig(url: url, headers: headers))
        case let .http(url, headers):
            return .http(McpHttpConfig(url: url, headers: headers))
        }
    }
}

extension AxionMcpServerConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case command
        case args
        case env
        case url
        case headers
    }

    private enum ServerType: String, Codable {
        case stdio
        case sse
        case http
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ServerType.self, forKey: .type)

        switch type {
        case .stdio:
            let command = try container.decode(String.self, forKey: .command)
            let args = try container.decodeIfPresent([String].self, forKey: .args)
            let env = try container.decodeIfPresent([String: String].self, forKey: .env)
            self = .stdio(command: command, args: args, env: env)
        case .sse:
            let url = try container.decode(String.self, forKey: .url)
            let headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
            self = .sse(url: url, headers: headers)
        case .http:
            let url = try container.decode(String.self, forKey: .url)
            let headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
            self = .http(url: url, headers: headers)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .stdio(command, args, env):
            try container.encode(ServerType.stdio, forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encodeIfPresent(args, forKey: .args)
            try container.encodeIfPresent(env, forKey: .env)
        case let .sse(url, headers):
            try container.encode(ServerType.sse, forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encodeIfPresent(headers, forKey: .headers)
        case let .http(url, headers):
            try container.encode(ServerType.http, forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encodeIfPresent(headers, forKey: .headers)
        }
    }
}
