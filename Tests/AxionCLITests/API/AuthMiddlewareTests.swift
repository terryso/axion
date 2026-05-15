import Testing
import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
@testable import AxionCLI

@Suite("AuthMiddleware")
struct AuthMiddlewareTests {

    @Test("No auth-key: all requests pass")
    func noAuthKeyAllRequestsPass() async throws {
        let app = try await buildTestApplication(authKey: nil)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs", method: .post, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                #expect(response.status == .accepted)
            }
        }
    }

    @Test("Auth-key set, no Authorization header returns 401")
    func authKeyNoHeaderReturns401() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs", method: .post, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("Auth-key set, wrong token returns 401")
    func authKeyWrongTokenReturns401() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer wrongtoken"
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("Auth-key set, correct Bearer token passes")
    func authKeyCorrectBearerTokenPasses() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer mysecret"
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                #expect(response.status == .accepted)
            }
        }
    }

    @Test("Health endpoint bypasses auth")
    func healthEndpointNoAuthRequired() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health", method: .get) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("Authorization header wrong format (Basic) returns 401")
    func authKeyBasicAuthReturns401() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Basic dXNlcjpwYXNz"
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("Auth-key set, GET run also requires auth")
    func authKeyGetRunRequiresAuth() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/nonexistent", method: .get) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("Empty Bearer token returns 401")
    func authKeyEmptyBearerTokenReturns401() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer "
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("401 response body has correct JSON error structure")
    func authKey401ResponseHasCorrectErrorBody() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs", method: .post, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                #expect(response.status == .unauthorized)
                let body = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(body.error == "unauthorized")
                #expect(!body.message.isEmpty)
            }
        }
    }

    @Test("Health endpoint with trailing slash also bypasses auth")
    func healthEndpointTrailingSlashNoAuthRequired() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health/", method: .get) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("SSE endpoint also requires auth")
    func authKeySseEndpointRequiresAuth() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/nonexistent-id/events", method: .get) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("Bearer token with extra spaces returns 401")
    func authKeyBearerWithExtraSpacesReturns401() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer  mysecret"
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    private func buildTestApplication(
        authKey: String?,
        runTracker: RunTracker? = nil,
        eventBroadcaster: EventBroadcaster? = nil
    ) async throws -> Application<RouterResponder<BasicRequestContext>> {
        let broadcaster = eventBroadcaster ?? EventBroadcaster()
        let tracker = runTracker ?? RunTracker(eventBroadcaster: broadcaster)
        let router = Router()
        AxionAPI.registerRoutes(
            on: router,
            runTracker: tracker,
            eventBroadcaster: broadcaster,
            config: .default,
            authKey: authKey
        )
        return Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )
    }
}
