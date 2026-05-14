import Foundation
import Hummingbird
import NIOCore

import AxionCore

/// AxionAPI — Hummingbird route definitions for the Axion HTTP API.
/// Provides REST endpoints for task submission, status queries, health checks,
/// and SSE event streaming (Story 5.2).
enum AxionAPI {

    // MARK: - Route Registration

    /// Register all API routes on the given router.
    /// - Parameters:
    ///   - router: The Hummingbird router to register routes on.
    ///   - runTracker: The shared RunTracker instance for task state management.
    ///   - eventBroadcaster: The shared EventBroadcaster for SSE streaming.
    ///   - config: The loaded AxionConfig.
    ///   - authKey: Optional Bearer token for authentication (nil = no auth).
    ///   - concurrencyLimiter: Optional concurrency limiter for task execution.
    static func registerRoutes(
        on router: Router<BasicRequestContext>,
        runTracker: RunTracker,
        eventBroadcaster: EventBroadcaster,
        config: AxionConfig,
        authKey: String? = nil,
        concurrencyLimiter: ConcurrencyLimiter? = nil
    ) {
        let v1 = router.group("v1")

        // GET /v1/health — no auth required
        v1.get("health") { _, _ in
            EditedResponse(
                headers: [.contentType: "application/json"],
                response: HealthResponse(
                    status: "ok",
                    version: AxionVersion.current
                )
            )
        }

        // Authenticated route group
        let v1Authed: RouterGroup<BasicRequestContext>
        if let authKey {
            v1Authed = v1.group().addMiddleware {
                AuthMiddleware(authKey: authKey)
            }
        } else {
            v1Authed = v1.group()
        }

        // GET /v1/runs — list runs (Story 10.2)
        v1Authed.get("runs") { request, context in
            let limitParam = request.uri.queryParameters["limit"].map { String($0) } ?? "20"
            let limit = Int(limitParam) ?? 20

            let allRuns = await runTracker.listRuns()
            let sortedRuns = allRuns
                .sorted { $0.submittedAt > $1.submittedAt }
                .prefix(limit)

            let responses = sortedRuns.map { run in
                RunStatusResponse(
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
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(responses)
            let body = ByteBuffer(data: data)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: body)
            )
        }

        // POST /v1/runs
        v1Authed.post("runs") { request, context in
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

            // Check concurrency limiter
            if let limiter = concurrencyLimiter {
                let acquired = await limiter.tryAcquire()
                if acquired {
                    // Slot available immediately — launch agent in background
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
                            runId: runId,
                            eventBroadcaster: eventBroadcaster,
                            completion: { _, _, _, _, _ in }
                        )
                        await runTracker.updateRun(
                            runId: runId,
                            status: result.finalStatus,
                            steps: result.stepSummaries,
                            durationMs: result.durationMs,
                            replanCount: result.replanCount
                        )
                        await limiter.release()
                    }

                    var resp = try context.responseEncoder.encode(
                        CreateRunResponse(runId: runId, status: "running"),
                        from: request,
                        context: context
                    )
                    resp.status = .accepted
                    return resp
                }

                // Queue full — return queued response immediately, background task will execute when slot available
                let position = await limiter.queueDepth + 1
                let capturedConfig = config
                _ = Task.detached {
                    let slotResult = await limiter.acquire()
                    guard slotResult >= 0 else { return }
                    let result = await AgentRunner.runAgent(
                        config: capturedConfig,
                        task: createRequest.task,
                        options: RunOptions(
                            task: createRequest.task,
                            maxSteps: createRequest.maxSteps,
                            maxBatches: createRequest.maxBatches,
                            allowForeground: createRequest.allowForeground
                        ),
                        runId: runId,
                        eventBroadcaster: eventBroadcaster,
                        completion: { _, _, _, _, _ in }
                    )
                    await runTracker.updateRun(
                        runId: runId,
                        status: result.finalStatus,
                        steps: result.stepSummaries,
                        durationMs: result.durationMs,
                        replanCount: result.replanCount
                    )
                    await limiter.release()
                }

                let queuedResp = QueuedRunResponse(runId: runId, status: "queued", position: position)
                var response = try context.responseEncoder.encode(queuedResp, from: request, context: context)
                response.status = .accepted
                return response
            }

            // No concurrency limiter — original behavior
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
                    runId: runId,
                    eventBroadcaster: eventBroadcaster,
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

            var resp = try context.responseEncoder.encode(
                CreateRunResponse(runId: runId, status: "running"),
                from: request,
                context: context
            )
            resp.status = .accepted
            return resp
        }

        // GET /v1/runs/:runId
        v1Authed.get("runs/:runId") { request, context in
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

        // GET /v1/runs/:runId/events — SSE endpoint (Story 5.2)
        v1Authed.get("runs/:runId/events") { request, context in
            guard let runId = context.parameters.get("runId") else {
                throw AxionAPIError(
                    status: .badRequest,
                    error: APIErrorResponse(
                        error: "missing_run_id",
                        message: "Run ID is required."
                    )
                )
            }

            let run = await runTracker.getRun(runId: runId)
            guard run != nil else {
                throw AxionAPIError(
                    status: .notFound,
                    error: APIErrorResponse(
                        error: "run_not_found",
                        message: "Run '\(runId)' not found."
                    )
                )
            }

            // Check if the run is already completed — if so, replay from buffer and close
            let isCompleted = run?.status != .running

            if isCompleted {
                // Replay buffered events and close immediately (AC4)
                let replayEvents = await eventBroadcaster.getReplayBuffer(runId: runId)
                var sseOutput = ""
                for (index, event) in replayEvents.enumerated() {
                    do {
                        let sseString = try event.encodeToSSE(sequenceId: index + 1)
                        sseOutput += sseString
                    } catch {
                        // If a single event fails to encode, emit an error placeholder
                        sseOutput += "event: error\ndata: {\"message\":\"Replay event encoding failed at index \(index)\"}\nid: \(index + 1)\n\n"
                    }
                }
                let body = ByteBuffer(string: sseOutput)
                return Response(
                    status: .ok,
                    headers: [
                        .contentType: "text/event-stream",
                        .cacheControl: "no-cache",
                        .connection: "keep-alive",
                    ],
                    body: .init(byteBuffer: body)
                )
            } else {
                // Live streaming: subscribe and stream events via AsyncStream
                let eventStream = await eventBroadcaster.subscribe(runId: runId)

                // Convert AsyncStream<SSEEvent> to AsyncSequence<ByteBuffer>
                // Use an iterator to generate sequential SSE event IDs
                var sequenceCounter = 0
                let bufferStream = eventStream.map { (event: SSEEvent) -> ByteBuffer in
                    sequenceCounter += 1
                    do {
                        let sseString = try event.encodeToSSE(sequenceId: sequenceCounter)
                        return ByteBuffer(string: sseString)
                    } catch {
                        // Emit a minimal error event so the client is aware of encoding failure
                        let fallback = "event: error\ndata: {\"message\":\"SSE encoding failed\"}\nid: \(sequenceCounter)\n\n"
                        return ByteBuffer(string: fallback)
                    }
                }

                let body = ResponseBody(asyncSequence: bufferStream)
                return Response(
                    status: .ok,
                    headers: [
                        .contentType: "text/event-stream",
                        .cacheControl: "no-cache",
                        .connection: "keep-alive",
                    ],
                    body: body
                )
            }
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
