import Hummingbird
import NIOCore

import AxionCore
import OpenAgentSDK

// Disambiguate: AxionCore.Skill = recorded skill model, OpenAgentSDK.Skill = prompt skill model
typealias RecordedSkill = AxionCore.Skill

/// AxionAPI — Hummingbird route definitions for Axion-specific HTTP API routes.
/// SDK handles health, runs, and SSE endpoints. Axion registers only:
/// - GET /v1/capabilities
/// - Settings routes (GET/POST/DELETE /v1/settings/api-key)
/// - Skills routes (GET /v1/skills, GET /v1/skills/:name, POST /v1/skills/:name/run)
enum AxionAPI {

    // MARK: - Route Registration

    /// Register Axion-specific custom routes on the given router.
    /// Called via SDK's `customRouteBuilder` hook after SDK registers its standard routes.
    /// - Parameters:
    ///   - router: The Hummingbird v1 router group to register routes on.
    ///   - runCoordinator: Axion's RunCoordinator for task state management.
    ///   - eventBroadcaster: The shared EventBroadcaster for SSE streaming.
    ///   - config: The loaded AxionConfig.
    ///   - skillRegistry: Optional SkillRegistry for prompt skill support.
    static func registerCustomRoutes(
        on router: RouterGroup<BasicRequestContext>,
        runCoordinator: RunCoordinator,
        eventBroadcaster: OpenAgentSDK.EventBroadcaster,
        config: AxionConfig,
        maxConcurrentRuns: Int = 10,
        skillRegistry: SkillRegistry? = nil,
        configDirectory: String? = nil,
        skillsDirectory: String? = nil
    ) {
        let resolvedConfigDir = configDirectory ?? ConfigManager.defaultConfigDirectory
        let resolvedSkillsDir = skillsDirectory ?? ConfigManager.skillsDirectory

        // No need to add AuthMiddleware here — SDK's AgentHTTPServer already applies it
        // to the root router when authKey is set. Custom routes inherit that protection.

        // GET /v1/capabilities — discover Axion capabilities (Story 14.2)
        router.get("capabilities") { _, _ in
            EditedResponse(
                headers: [
                    .contentType: "application/json",
                    .cacheControl: "private, max-age=300",
                ],
                response: CapabilitiesResponse(
                    version: AxionVersion.current,
                    supportedRunStatuses: APIRunStatus.allCases.map(\.rawValue),
                    supportedResultKinds: TaskResultKind.allCases.map(\.rawValue),
                    availableTools: ToolNames.allToolNames,
                    maxConcurrentRuns: maxConcurrentRuns,
                    features: ["memory", "takeover", "fast_mode", "skills"]
                )
            )
        }

        // Settings and Skills routes are registered via extension files
        Self.registerSettingsRoutes(
            on: router,
            config: config,
            resolvedConfigDir: resolvedConfigDir
        )
        Self.registerSkillsRoutes(
            on: router,
            config: config,
            runCoordinator: runCoordinator,
            eventBroadcaster: eventBroadcaster,
            skillRegistry: skillRegistry,
            resolvedSkillsDir: resolvedSkillsDir
        )
    }
}

// MARK: - AxionAPIError

/// Custom error type that encodes APIErrorResponse as JSON in the response body.
struct AxionAPIError: Error, HTTPResponseError, Sendable {
    let status: HTTPResponse.Status
    let error: APIErrorResponse

    /// Convenience factory — collapses the repeated status+APIErrorResponse construction
    /// into a single call site line instead of 5 lines.
    static func apiError(status: HTTPResponse.Status, error: String, message: String) -> AxionAPIError {
        AxionAPIError(status: status, error: APIErrorResponse(error: error, message: message))
    }

    func response(from request: Request, context: some RequestContext) throws -> Response {
        var response = try context.responseEncoder.encode(error, from: request, context: context)
        response.status = self.status
        return response
    }
}
