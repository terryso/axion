import Foundation
import Hummingbird

import AxionCore

/// AxionAPI — Hummingbird route definitions for the Axion HTTP API.
/// Provides REST endpoints for task submission, status queries, and health checks.
enum AxionAPI {

    // MARK: - Route Registration

    /// Register all API routes on the given router.
    /// - Parameters:
    ///   - router: The Hummingbird router to register routes on.
    ///   - runTracker: The shared RunTracker instance for task state management.
    static func registerRoutes(on router: Router<BasicRequestContext>, runTracker: RunTracker, config: AxionConfig) {
        let v1 = router.group("v1")

        // GET /v1/health
        v1.get("health") { _, _ in
            EditedResponse(
                headers: [.contentType: "application/json"],
                response: HealthResponse(
                    status: "ok",
                    version: AxionVersion.current
                )
            )
        }

        // POST /v1/runs
        v1.post("runs") { request, context in
            // Read raw body first (can only be consumed once)
            let buffer: ByteBuffer
            do {
                buffer = try await request.body.collect(upTo: context.maxUploadSize)
            } catch {
                throw AxionAPIError(
                    status: .badRequest,
                    error: APIErrorResponse(
                        error: "invalid_request",
                        message: "Failed to read request body."
                    )
                )
            }

            let data = Data(buffer: buffer)

            // Decode request body
            let createRequest: CreateRunRequest
            do {
                createRequest = try JSONDecoder().decode(CreateRunRequest.self, from: data)
            } catch {
                // Check if task field is missing specifically
                // Decode as a generic JSON object to check for task key presence
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
                   let dict = jsonObject as? [String: Any],
                   dict["task"] == nil {
                    throw AxionAPIError(
                        status: .badRequest,
                        error: APIErrorResponse(
                            error: "missing_task",
                            message: "Request body must include a 'task' field."
                        )
                    )
                }
                throw AxionAPIError(
                    status: .badRequest,
                    error: APIErrorResponse(
                        error: "invalid_request",
                        message: "Failed to parse request body."
                    )
                )
            }

            // Validate task field is not empty
            guard !createRequest.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AxionAPIError(
                    status: .badRequest,
                    error: APIErrorResponse(
                        error: "missing_task",
                        message: "Request body must include a 'task' field."
                    )
                )
            }

            // Submit run to tracker
            let runId = await runTracker.submitRun(
                task: createRequest.task,
                options: RunOptions(
                    task: createRequest.task,
                    maxSteps: createRequest.maxSteps,
                    maxBatches: createRequest.maxBatches,
                    allowForeground: createRequest.allowForeground
                )
            )

            // Launch agent execution in background
            let capturedConfig = config
            _ = Task.detached {
                let result = await AgentRunner.runAgent(
                    config: capturedConfig,
                    task: createRequest.task,
                    options: RunOptions(
                        task: createRequest.task,
                        maxSteps: createRequest.maxSteps,
                        maxBatches: createRequest.maxBatches,
                        allowForeground: createRequest.allowForeground
                    ),
                    completion: { _, _, _, _, _ in }
                )
                await runTracker.updateRun(
                    runId: runId,
                    status: result.finalStatus,
                    steps: result.stepSummaries,
                    durationMs: result.durationMs,
                    replanCount: result.replanCount
                )
            }

            return EditedResponse(
                status: .accepted,
                headers: [.contentType: "application/json"],
                response: CreateRunResponse(runId: runId, status: "running")
            )
        }

        // GET /v1/runs/:runId
        v1.get("runs/:runId") { request, context in
            guard let runId = context.parameters.get("runId") else {
                throw AxionAPIError(
                    status: .badRequest,
                    error: APIErrorResponse(
                        error: "missing_run_id",
                        message: "Run ID is required."
                    )
                )
            }

            guard let run = await runTracker.getRun(runId: runId) else {
                throw AxionAPIError(
                    status: .notFound,
                    error: APIErrorResponse(
                        error: "run_not_found",
                        message: "Run '\(runId)' not found."
                    )
                )
            }

            let response = RunStatusResponse(
                runId: run.runId,
                status: run.status.rawValue,
                task: run.task,
                totalSteps: run.totalSteps,
                durationMs: run.durationMs,
                replanCount: run.replanCount,
                submittedAt: run.submittedAt,
                completedAt: run.completedAt,
                steps: run.steps
            )

            return EditedResponse(
                headers: [.contentType: "application/json"],
                response: response
            )
        }
    }
}

// MARK: - AxionAPIError

/// Custom error type that encodes APIErrorResponse as JSON in the response body.
struct AxionAPIError: Error, HTTPResponseError, Sendable {
    let status: HTTPResponse.Status
    let error: APIErrorResponse

    func response(from request: Request, context: some RequestContext) throws -> Response {
        var response = try context.responseEncoder.encode(error, from: request, context: context)
        response.status = self.status
        return response
    }
}
