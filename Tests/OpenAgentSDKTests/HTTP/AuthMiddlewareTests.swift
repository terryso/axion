import XCTest
import Hummingbird
@testable import OpenAgentSDK

final class AuthMiddlewareTests: XCTestCase {

    // MARK: - Middleware Protocol Tests via Hummingbird Application

    /// Create a minimal Hummingbird app with AuthMiddleware and test against it.
    private func createTestApp(authKey: String?) async throws -> (
        application: Application<RouterResponder<BasicRequestContext>>,
        port: Int
    ) {
        let router = Router<BasicRequestContext>()

        if let authKey {
            router.add(middleware: AuthMiddleware<BasicRequestContext>(authKey: authKey))
        }

        router.get("v1/health") { _, _ -> String in "ok" }
        router.get("v1/runs") { _, _ -> String in "runs-list" }
        router.post("v1/runs") { _, _ -> String in "created" }

        let testPort = 54300 + Int(arc4random_uniform(1000))
        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: testPort))
        )
        return (app, testPort)
    }

    private func startApp(_ app: Application<RouterResponder<BasicRequestContext>>) {
        _Concurrency.Task { try? await app.runService() }
    }

    private func waitForServer() async throws {
        try await _Concurrency.Task.sleep(for: .milliseconds(300))
    }

    // MARK: - Token Validation

    func testValidTokenPassesThrough() async throws {
        let (app, port) = try await createTestApp(authKey: "secret-key")
        startApp(app)
        try await waitForServer()

        let url = URL(string: "http://127.0.0.1:\(port)/v1/runs")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer secret-key", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        XCTAssertEqual(statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "runs-list")
    }

    func testNoAuthKeyIsPassthrough() async throws {
        let (app, port) = try await createTestApp(authKey: nil)
        startApp(app)
        try await waitForServer()

        let url = URL(string: "http://127.0.0.1:\(port)/v1/runs")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // No Authorization header

        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        XCTAssertEqual(statusCode, 200)
    }

    // MARK: - Health Endpoint Bypass

    func testHealthEndpointBypassesAuth() async throws {
        let (app, port) = try await createTestApp(authKey: "secret-key")
        startApp(app)
        try await waitForServer()

        let url = URL(string: "http://127.0.0.1:\(port)/v1/health")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // No Authorization header

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        XCTAssertEqual(statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")
    }

    // MARK: - Rejection Cases

    func testMissingTokenReturns401() async throws {
        let (app, port) = try await createTestApp(authKey: "secret-key")
        startApp(app)
        try await waitForServer()

        let url = URL(string: "http://127.0.0.1:\(port)/v1/runs")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // No Authorization header

        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        XCTAssertEqual(statusCode, 401)
    }

    func testWrongTokenReturns401() async throws {
        let (app, port) = try await createTestApp(authKey: "secret-key")
        startApp(app)
        try await waitForServer()

        let url = URL(string: "http://127.0.0.1:\(port)/v1/runs")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer wrong-key", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        XCTAssertEqual(statusCode, 401)
    }

    func testMissingBearerPrefixReturns401() async throws {
        let (app, port) = try await createTestApp(authKey: "secret-key")
        startApp(app)
        try await waitForServer()

        let url = URL(string: "http://127.0.0.1:\(port)/v1/runs")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Basic secret-key", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        XCTAssertEqual(statusCode, 401)
    }
}
