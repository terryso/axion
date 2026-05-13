import Foundation
import Hummingbird

import AxionCore

struct AuthMiddleware<Context: RequestContext>: MiddlewareProtocol {
    typealias Input = Request
    typealias Output = Response
    typealias Context = Context

    let authKey: String

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        // Skip auth for health endpoint
        if request.uri.string.hasSuffix("/v1/health") || request.uri.string.hasSuffix("/v1/health/") {
            return try await next(request, context)
        }

        guard let authHeader = request.headers[.authorization],
              authHeader.hasPrefix("Bearer "),
              String(authHeader.dropFirst(7)) == authKey else {
            throw AxionAPIError(
                status: .unauthorized,
                error: APIErrorResponse(
                    error: "unauthorized",
                    message: "Invalid or missing authentication token."
                )
            )
        }

        return try await next(request, context)
    }
}
