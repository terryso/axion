import Foundation
import OpenAgentSDK
import Testing
@testable import AxionCLI

@Suite("AxionMcpServerConfig")
struct AxionMcpServerConfigTests {

    // MARK: - Codable

    @Test("stdio encodes flat JSON and round trips")
    func test_stdio_encodesFlatJsonAndRoundTrips() throws {
        let config = AxionMcpServerConfig.stdio(
            command: "node",
            args: ["server.js"],
            env: ["FOO": "bar"]
        )

        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let decoded = try JSONDecoder().decode(AxionMcpServerConfig.self, from: data)

        #expect(json["type"] as? String == "stdio")
        #expect(json["command"] as? String == "node")
        #expect(json["stdio"] == nil)
        #expect(decoded == config)
    }

    @Test("stdio args and env are optional")
    func test_stdio_argsAndEnvOptional() throws {
        let json = #"{"type":"stdio","command":"npx"}"#
        let decoded = try JSONDecoder().decode(AxionMcpServerConfig.self, from: Data(json.utf8))

        #expect(decoded == .stdio(command: "npx", args: nil, env: nil))
    }

    @Test("sse encodes flat JSON and round trips")
    func test_sse_encodesFlatJsonAndRoundTrips() throws {
        let config = AxionMcpServerConfig.sse(url: "http://localhost:8080/sse")
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let decoded = try JSONDecoder().decode(AxionMcpServerConfig.self, from: data)

        #expect(json["type"] as? String == "sse")
        #expect(json["url"] as? String == "http://localhost:8080/sse")
        #expect(decoded == config)
    }

    @Test("http encodes flat JSON and round trips")
    func test_http_encodesFlatJsonAndRoundTrips() throws {
        let config = AxionMcpServerConfig.http(
            url: "http://localhost:8080/mcp",
            headers: ["Authorization": "Bearer token"]
        )
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let decoded = try JSONDecoder().decode(AxionMcpServerConfig.self, from: data)

        #expect(json["type"] as? String == "http")
        #expect(json["url"] as? String == "http://localhost:8080/mcp")
        #expect((json["headers"] as? [String: String])?["Authorization"] == "Bearer token")
        #expect(decoded == config)
    }

    @Test("sse headers are optional")
    func test_sse_headersAreOptional() throws {
        let json = #"{"type":"sse","url":"http://localhost:8080/sse"}"#
        let decoded = try JSONDecoder().decode(AxionMcpServerConfig.self, from: Data(json.utf8))

        #expect(decoded == .sse(url: "http://localhost:8080/sse", headers: nil))
    }

    @Test("unknown type throws")
    func test_unknownType_throws() {
        let json = #"{"type":"websocket","url":"ws://localhost"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AxionMcpServerConfig.self, from: Data(json.utf8))
        }
    }

    // MARK: - SDK Mapping

    @Test("stdio maps to SDK stdio config")
    func test_stdio_mapsToSdkStdioConfig() throws {
        let sdkConfig = AxionMcpServerConfig
            .stdio(command: "node", args: ["server.js"], env: ["FOO": "bar"])
            .toSdkConfig()

        guard case let .stdio(stdio) = sdkConfig else {
            Issue.record("Expected stdio SDK config")
            return
        }

        #expect(stdio.command == "node")
        #expect(stdio.args == ["server.js"])
        #expect(stdio.env == ["FOO": "bar"])
    }

    @Test("http maps headers to SDK config")
    func test_http_mapsHeadersToSdkConfig() throws {
        let sdkConfig = AxionMcpServerConfig
            .http(url: "https://example.com/mcp", headers: ["Authorization": "Bearer token"])
            .toSdkConfig()

        guard case let .http(http) = sdkConfig else {
            Issue.record("Expected http SDK config")
            return
        }

        #expect(http.url == "https://example.com/mcp")
        #expect(http.headers == ["Authorization": "Bearer token"])
    }
}
