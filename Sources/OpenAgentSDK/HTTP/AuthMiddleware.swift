import Foundation
import Hummingbird

// MARK: - AuthMiddleware

/// Hummingbird middleware that validates Bearer token authentication.
/// Health endpoint (`/v1/health`) always passes through.
/// If no `authKey` is configured, middleware is a no-op passthrough.
public struct AuthMiddleware<Context: RequestContext>: MiddlewareProtocol {
    public typealias Input = Request
    public typealias Output = Response
    public typealias Context = Context

    let authKey: String?

    public init(authKey: String?) {
        self.authKey = authKey
    }

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // No auth key configured — passthrough
        guard let authKey else {
            return try await next(request, context)
        }

        // Health endpoint always bypasses auth
        let path = request.uri.string
        if path.hasSuffix("/v1/health") || path.hasSuffix("/v1/health/") {
            return try await next(request, context)
        }

        // Validate Bearer token
        guard let authHeader = request.headers[.authorization],
              authHeader.hasPrefix("Bearer "),
              String(authHeader.dropFirst(7)) == authKey
        else {
            throw HTTPError(.unauthorized, message: "Invalid or missing authentication token.")
        }

        return try await next(request, context)
    }
}
