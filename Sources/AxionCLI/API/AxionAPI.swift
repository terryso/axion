import Foundation
import Hummingbird
import NIOCore

import AxionCore
import OpenAgentSDK

// Disambiguate: AxionCore.Skill = recorded skill model, OpenAgentSDK.Skill = prompt skill model
typealias RecordedSkill = AxionCore.Skill

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
        runTracker: AxionRunTracker,
        eventBroadcaster: OpenAgentSDK.EventBroadcaster,
        config: AxionConfig,
        authKey: String? = nil,
        concurrencyLimiter: OpenAgentSDK.ConcurrencyLimiter? = nil,
        runLockService: RunLockService? = nil,
        maxConcurrent: Int = 10,
        configDirectory: String = ConfigManager.defaultConfigDirectory,
        skillRegistry: SkillRegistry? = nil,
        skillsDirectory: String? = nil
    ) {
        let resolvedSkillsDir = skillsDirectory ?? SkillCompileCommand.skillsDirectory()
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

        // Authenticated route group — SDK's AuthMiddleware handles nil authKey as passthrough
        let v1Authed = v1.group().addMiddleware {
            OpenAgentSDK.AuthMiddleware(authKey: authKey)
        }

        // GET /v1/capabilities — discover Axion capabilities (Story 14.2)
        v1Authed.get("capabilities") { _, _ in
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
                    maxConcurrentRuns: maxConcurrent,
                    features: ["memory", "takeover", "fast_mode", "skills"]
                )
            )
        }

        // MARK: - Settings API Routes (Story 14.3)

        // GET /v1/settings/api-key — get API key status
        v1Authed.get("settings/api-key") { _, _ in
            let (source, effectiveKey, available) = Self.resolveApiKeySource(config: config)

            return EditedResponse(
                headers: [
                    .contentType: "application/json",
                    .cacheControl: "private, max-age=300",
                ],
                response: ApiKeyStatusResponse(
                    provider: config.provider.rawValue,
                    available: available,
                    source: source,
                    maskedKey: ApiKeyStatusResponse.maskKey(effectiveKey)
                )
            )
        }

        // POST /v1/settings/api-key — save API key
        v1Authed.post("settings/api-key") { request, context in
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
            let saveRequest: SaveApiKeyRequest
            do {
                saveRequest = try JSONDecoder().decode(SaveApiKeyRequest.self, from: data)
            } catch {
                throw AxionAPIError(
                    status: .badRequest,
                    error: APIErrorResponse(
                        error: "invalid_request",
                        message: "Failed to parse request body. Expected {\"api_key\": \"...\"}."
                    )
                )
            }

            guard !saveRequest.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AxionAPIError(
                    status: .badRequest,
                    error: APIErrorResponse(
                        error: "missing_api_key",
                        message: "Request body must include a non-empty 'api_key' field."
                    )
                )
            }

            // Load current config from file, update apiKey, save back
            var fileConfig: AxionConfig
            let configPath = (configDirectory as NSString).appendingPathComponent("config.json")
            if let fileData = FileManager.default.contents(atPath: configPath),
               let decoded = try? JSONDecoder().decode(AxionConfig.self, from: fileData) {
                fileConfig = decoded
            } else {
                fileConfig = config
            }
            fileConfig.apiKey = saveRequest.apiKey
            try ConfigManager.saveConfigFile(fileConfig, toDirectory: configDirectory)

            // Return status based on effective key (env may override)
            let env = ProcessInfo.processInfo.environment
            let source: String
            let maskedKey: String
            let available = true
            if let envKey = env["AXION_API_KEY"], !envKey.isEmpty {
                source = "env"
                maskedKey = ApiKeyStatusResponse.maskKey(envKey)
            } else {
                source = "config"
                maskedKey = ApiKeyStatusResponse.maskKey(saveRequest.apiKey)
            }

            return EditedResponse(
                headers: [.contentType: "application/json"],
                response: ApiKeyStatusResponse(
                    provider: config.provider.rawValue,
                    available: available,
                    source: source,
                    maskedKey: maskedKey
                )
            )
        }

        // DELETE /v1/settings/api-key — clear API key
        v1Authed.delete("settings/api-key") { _, _ in
            // Load current config from file, clear apiKey, save back
            var fileConfig: AxionConfig
            let configPath = (configDirectory as NSString).appendingPathComponent("config.json")
            if let fileData = FileManager.default.contents(atPath: configPath),
               let decoded = try? JSONDecoder().decode(AxionConfig.self, from: fileData) {
                fileConfig = decoded
            } else {
                fileConfig = config
            }
            fileConfig.apiKey = nil
            try ConfigManager.saveConfigFile(fileConfig, toDirectory: configDirectory)

            let (source, _, available) = Self.resolveApiKeySource(config: fileConfig)

            return EditedResponse(
                headers: [.contentType: "application/json"],
                response: DeleteApiKeyResponse(
                    provider: config.provider.rawValue,
                    available: available,
                    source: source
                )
            )
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
                run.toStandardOutput()
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

            let activeRunLockService = runLockService ?? RunLockService()

            // Synchronous lock check: reject immediately if desktop lock is held
            let currentHolder = await activeRunLockService.readExistingLock()
            if let holder = currentHolder, await activeRunLockService.isProcessAlive(holder.pid) {
                await runTracker.updateRun(runId: runId, status: .failed, steps: [], durationMs: 0, replanCount: 0)
                throw AxionAPIError(
                    status: .conflict,
                    error: APIErrorResponse(
                        error: "run_locked",
                        message: "Another live run (\(holder.runId)) is currently executing (pid \(holder.pid))."
                    )
                )
            }

            // Check concurrency limiter — determines running vs queued response
            if let limiter = concurrencyLimiter {
                let acquired = await limiter.tryAcquire()
                if acquired {
                    // Slot available immediately — launch agent in background (waits for desktop lock internally)
                    let capturedConfig = config
                    _ = _Concurrency.Task.detached {
                        let locked = await activeRunLockService.waitForLock(runId: runId)
                        guard locked else {
                            await runTracker.updateRun(runId: runId, status: .failed, steps: [], durationMs: 0, replanCount: 0)
                            await limiter.release()
                            return
                        }
                        let result = await ApiRunner.runAgent(
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
                            runTracker: runTracker,
                            completion: { _, _, _, _, _, _, _ in }
                        )
                        await runTracker.updateRun(
                            runId: runId,
                            status: result.finalStatus,
                            steps: result.stepSummaries,
                            durationMs: result.durationMs,
                            replanCount: result.replanCount,
                            costTelemetry: result.costTelemetry
                        )
                        await limiter.release()
                        await activeRunLockService.release()
                    }

                    var resp = try context.responseEncoder.encode(
                        StandardTaskOutput(
                            runId: runId,
                            task: createRequest.task,
                            status: .running,
                            startedAt: ISO8601DateFormatter().string(from: Date())
                        ),
                        from: request,
                        context: context
                    )
                    resp.status = .accepted
                    return resp
                }

                // Queue full — return queued response immediately, background task will execute when slot available
                let position = await limiter.queueDepth + 1
                let capturedConfig = config
                _ = _Concurrency.Task.detached {
                    await limiter.acquire()
                    let locked = await activeRunLockService.waitForLock(runId: runId)
                    guard locked else {
                        await runTracker.updateRun(runId: runId, status: .failed, steps: [], durationMs: 0, replanCount: 0)
                        await limiter.release()
                        return
                    }
                    let result = await ApiRunner.runAgent(
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
                        runTracker: runTracker,
                        completion: { _, _, _, _, _, _, _ in }
                    )
                    await runTracker.updateRun(
                        runId: runId,
                        status: result.finalStatus,
                        steps: result.stepSummaries,
                        durationMs: result.durationMs,
                        replanCount: result.replanCount,
                        costTelemetry: result.costTelemetry
                    )
                    await limiter.release()
                    await activeRunLockService.release()
                }

                let queuedResp = QueuedRunResponse(runId: runId, status: "queued", position: position)
                var response = try context.responseEncoder.encode(queuedResp, from: request, context: context)
                response.status = .accepted
                return response
            }

            // No concurrency limiter — wait for desktop lock in background
            let capturedConfig = config
            _ = _Concurrency.Task.detached {
                let locked = await activeRunLockService.waitForLock(runId: runId)
                guard locked else {
                    await runTracker.updateRun(runId: runId, status: .failed, steps: [], durationMs: 0, replanCount: 0)
                    return
                }
                let result = await ApiRunner.runAgent(
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
                    runTracker: runTracker,
                    completion: { _, _, _, _, _, _, _ in }
                )
                await runTracker.updateRun(
                    runId: runId,
                    status: result.finalStatus,
                    steps: result.stepSummaries,
                    durationMs: result.durationMs,
                    replanCount: result.replanCount,
                    costTelemetry: result.costTelemetry
                )
                await activeRunLockService.release()
            }

            var resp = try context.responseEncoder.encode(
                StandardTaskOutput(
                    runId: runId,
                    task: createRequest.task,
                    status: .running,
                    startedAt: ISO8601DateFormatter().string(from: Date())
                ),
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

            let response = run.toStandardOutput()

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

                // Convert AsyncStream<AgentSSEEvent> to AsyncSequence<ByteBuffer>
                // Use an iterator to generate sequential SSE event IDs
                var sequenceCounter = 0
                let bufferStream = eventStream.map { (event: AgentSSEEvent) -> ByteBuffer in
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

        // MARK: - Skill API Routes (Story 10.3, Story 18.3)

        // GET /v1/skills — list all skills (merged dual sources)
        v1Authed.get("skills") { _, _ in
            let summaries = Self.loadAllSkillSummaries(registry: skillRegistry, skillsDir: resolvedSkillsDir)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(summaries)
            let body = ByteBuffer(data: data)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: body)
            )
        }

        // GET /v1/skills/:name — skill detail (dual source lookup)
        v1Authed.get("skills/:name") { _, context in
            guard let name = context.parameters.get("name") else {
                throw AxionAPIError(
                    status: .badRequest,
                    error: APIErrorResponse(
                        error: "missing_skill_name",
                        message: "Skill name is required."
                    )
                )
            }

            // Track 1: prompt skill via SkillRegistry
            if let promptSkill = skillRegistry?.find(name) {
                return EditedResponse(
                    headers: [.contentType: "application/json"],
                    response: SkillDetailResponse(
                        name: promptSkill.name,
                        description: promptSkill.whenToUse ?? promptSkill.description,
                        type: "prompt",
                        version: 1,
                        parameters: [],
                        stepCount: 0,
                        lastUsedAt: nil,
                        executionCount: 0
                    )
                )
            }

            // Track 2: recorded skill from JSON file
            if let detail = Self.loadSkillDetail(name: name, skillsDir: resolvedSkillsDir) {
                return EditedResponse(
                    headers: [.contentType: "application/json"],
                    response: detail
                )
            }

            throw AxionAPIError(
                status: .notFound,
                error: APIErrorResponse(
                    error: "skill_not_found",
                    message: "Skill '\(name)' not found."
                )
            )
        }

        // POST /v1/skills/:name/run — execute a skill (dual path: prompt vs recorded)
        v1Authed.post("skills/:name/run") { request, context in
            guard let name = context.parameters.get("name") else {
                throw AxionAPIError(
                    status: .badRequest,
                    error: APIErrorResponse(
                        error: "missing_skill_name",
                        message: "Skill name is required."
                    )
                )
            }

            // Track 1: prompt skill via SkillRegistry
            if let promptSkill = skillRegistry?.find(name) {
                // Parse request body for task description
                let buffer = try await request.body.collect(upTo: context.maxUploadSize)
                let bodyData = Data(buffer: buffer)
                var task: String
                if !bodyData.isEmpty, let runRequest = try? JSONDecoder().decode(PromptSkillRunRequest.self, from: bodyData) {
                    task = runRequest.task
                } else {
                    task = "Execute skill \(promptSkill.name)"
                }
                if task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    task = "Execute skill \(promptSkill.name)"
                }

                // Submit run via RunTracker
                let taskDescription = "技能(prompt): \(promptSkill.name) — \(task)"
                let runId = await runTracker.submitRun(
                    task: taskDescription,
                    options: RunOptions(task: taskDescription)
                )

                let activeRunLockService = runLockService ?? RunLockService()

                // Check concurrency limiter — determines running vs queued response
                if let limiter = concurrencyLimiter {
                    let acquired = await limiter.tryAcquire()
                    if acquired {
                        let capturedConfig = config
                        let capturedSkill = promptSkill
                        _ = _Concurrency.Task.detached {
                            let locked = await activeRunLockService.waitForLock(runId: runId)
                            guard locked else {
                                await runTracker.updateRun(runId: runId, status: .failed, steps: [], durationMs: 0, replanCount: 0)
                                await limiter.release()
                                return
                            }
                            let result = await ApiRunner.runSkillAgent(
                                skill: capturedSkill,
                                task: task,
                                config: capturedConfig,
                                runId: runId,
                                eventBroadcaster: eventBroadcaster,
                                runTracker: runTracker,
                                verbose: false,
                                completion: { _, _, _, _, _, _, _ in }
                            )
                            await runTracker.updateRun(
                                runId: runId,
                                status: result.finalStatus,
                                steps: result.stepSummaries,
                                durationMs: result.durationMs,
                                replanCount: result.replanCount,
                                costTelemetry: result.costTelemetry
                            )
                            await limiter.release()
                            await activeRunLockService.release()
                        }
                    } else {
                        // Queue full — queue in background
                        let position = await limiter.queueDepth + 1
                        let capturedConfig = config
                        let capturedSkill = promptSkill
                        _ = _Concurrency.Task.detached {
                            await limiter.acquire()
                            let locked = await activeRunLockService.waitForLock(runId: runId)
                            guard locked else {
                                await runTracker.updateRun(runId: runId, status: .failed, steps: [], durationMs: 0, replanCount: 0)
                                await limiter.release()
                                return
                            }
                            let result = await ApiRunner.runSkillAgent(
                                skill: capturedSkill,
                                task: task,
                                config: capturedConfig,
                                runId: runId,
                                eventBroadcaster: eventBroadcaster,
                                runTracker: runTracker,
                                verbose: false,
                                completion: { _, _, _, _, _, _, _ in }
                            )
                            await runTracker.updateRun(
                                runId: runId,
                                status: result.finalStatus,
                                steps: result.stepSummaries,
                                durationMs: result.durationMs,
                                replanCount: result.replanCount,
                                costTelemetry: result.costTelemetry
                            )
                            await limiter.release()
                            await activeRunLockService.release()
                        }
                        let queuedResp = QueuedRunResponse(runId: runId, status: "queued", position: position)
                        var response = try context.responseEncoder.encode(queuedResp, from: request, context: context)
                        response.status = .accepted
                        return response
                    }
                } else {
                    // No concurrency limiter — wait for desktop lock in background
                    let capturedConfig = config
                    let capturedSkill = promptSkill
                    _ = _Concurrency.Task.detached {
                        let locked = await activeRunLockService.waitForLock(runId: runId)
                        guard locked else {
                            await runTracker.updateRun(runId: runId, status: .failed, steps: [], durationMs: 0, replanCount: 0)
                            return
                        }
                        let result = await ApiRunner.runSkillAgent(
                            skill: capturedSkill,
                            task: task,
                            config: capturedConfig,
                            runId: runId,
                            eventBroadcaster: eventBroadcaster,
                            runTracker: runTracker,
                            verbose: false,
                            completion: { _, _, _, _, _, _, _ in }
                        )
                        await runTracker.updateRun(
                            runId: runId,
                            status: result.finalStatus,
                            steps: result.stepSummaries,
                            durationMs: result.durationMs,
                            replanCount: result.replanCount,
                            costTelemetry: result.costTelemetry
                        )
                        await activeRunLockService.release()
                    }
                }

                let response = SkillRunResponse(runId: runId, status: "running")
                var resp = try context.responseEncoder.encode(response, from: request, context: context)
                resp.status = .accepted
                return resp
            }

            // Track 2: recorded skill from JSON file
            let safeName = RecordCommand.sanitizeFileName(name)
            let skillsDir = resolvedSkillsDir
            let skillPath = (skillsDir as NSString).appendingPathComponent("\(safeName).json")

            guard FileManager.default.fileExists(atPath: skillPath) else {
                throw AxionAPIError(
                    status: .notFound,
                    error: APIErrorResponse(
                        error: "skill_not_found",
                        message: "Skill '\(name)' not found."
                    )
                )
            }

            // Load skill
            let skillData = try Data(contentsOf: URL(fileURLWithPath: skillPath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let skill: RecordedSkill
            do {
                skill = try decoder.decode(RecordedSkill.self, from: skillData)
            } catch {
                throw AxionAPIError(
                    status: .badRequest,
                    error: APIErrorResponse(
                        error: "invalid_skill",
                        message: "Failed to parse skill file."
                    )
                )
            }

            // Parse optional params from request body
            var paramValues: [String: String] = [:]
            let buffer = try await request.body.collect(upTo: context.maxUploadSize)
            let bodyData = Data(buffer: buffer)
            if !bodyData.isEmpty {
                if let runRequest = try? JSONDecoder().decode(SkillRunRequest.self, from: bodyData) {
                    paramValues = runRequest.params ?? [:]
                }
            }

            // Validate required parameters
            for param in skill.parameters where param.defaultValue == nil {
                guard paramValues[param.name] != nil else {
                    throw AxionAPIError(
                        status: .badRequest,
                        error: APIErrorResponse(
                            error: "missing_parameter",
                            message: "Missing required parameter: \(param.name)"
                        )
                    )
                }
            }

            // Submit run via RunTracker — skill execution in background
            let taskDescription = "技能: \(skill.name)"
            let runId = await runTracker.submitRun(
                task: taskDescription,
                options: RunOptions(task: taskDescription)
            )

            let capturedConfig = config
            let capturedSkill = skill
            _ = _Concurrency.Task.detached {
                let result = await SkillAPIRunner.runSkill(
                    config: capturedConfig,
                    skill: capturedSkill,
                    paramValues: paramValues,
                    runId: runId,
                    eventBroadcaster: eventBroadcaster
                )
                await runTracker.updateRun(
                    runId: runId,
                    status: result.finalStatus,
                    steps: result.stepSummaries,
                    durationMs: result.durationMs,
                    replanCount: result.replanCount
                )

                // Update skill metadata on success
                if result.finalStatus == .completed {
                    Self.updateSkillMetadata(skillPath: skillPath, skill: capturedSkill)
                }
            }

            let response = SkillRunResponse(runId: runId, status: "running")
            var resp = try context.responseEncoder.encode(response, from: request, context: context)
            resp.status = .accepted
            return resp
        }
    }

    // MARK: - Settings Helpers

    /// Determine the effective API key source.
    /// Returns (source, effectiveKey, available).
    private static func resolveApiKeySource(config: AxionConfig) -> (String, String, Bool) {
        let env = ProcessInfo.processInfo.environment
        if let envKey = env["AXION_API_KEY"], !envKey.isEmpty {
            return ("env", envKey, true)
        }
        if let configKey = config.apiKey, !configKey.isEmpty {
            return ("config", configKey, true)
        }
        return ("missing", "", false)
    }

    // MARK: - Skill Helpers

    /// Load skill summaries from both prompt skills (SkillRegistry) and recorded skills (JSON files).
    /// Prompt skills take priority on name collision (consistent with CLI dual-track lookup).
    private static func loadAllSkillSummaries(registry: SkillRegistry?, skillsDir: String) -> [SkillSummaryResponse] {
        var summariesByName: [String: SkillSummaryResponse] = [:]

        // Load recorded skills from skillsDir/*.json
        let recordedSummaries = loadRecordedSkillSummaries(skillsDir: skillsDir)
        for summary in recordedSummaries {
            summariesByName[summary.name] = summary
        }

        // Load prompt skills from SkillRegistry (overrides recorded on collision)
        if let registry {
            for skill in registry.allSkills where skill.userInvocable {
                summariesByName[skill.name] = SkillSummaryResponse(
                    name: skill.name,
                    description: skill.whenToUse ?? skill.description,
                    type: "prompt",
                    parameterCount: 0,
                    stepCount: 0,
                    lastUsedAt: nil,
                    executionCount: 0
                )
            }
        }

        return summariesByName.values.sorted { $0.name < $1.name }
    }

    private static func loadRecordedSkillSummaries(skillsDir: String) -> [SkillSummaryResponse] {
        let fm = FileManager.default

        guard let fileNames = try? fm.contentsOfDirectory(atPath: skillsDir) else {
            return []
        }

        let jsonFiles = fileNames.filter { $0.hasSuffix(".json") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var summaries: [SkillSummaryResponse] = []
        for fileName in jsonFiles {
            let filePath = (skillsDir as NSString).appendingPathComponent(fileName)
            guard let data = fm.contents(atPath: filePath),
                  let skill = try? decoder.decode(RecordedSkill.self, from: data) else { continue }
            summaries.append(SkillSummaryResponse(
                name: skill.name,
                description: skill.description,
                type: "recorded",
                parameterCount: skill.parameters.count,
                stepCount: skill.steps.count,
                lastUsedAt: skill.lastUsedAt.map { dateFormatter.string(from: $0) },
                executionCount: skill.executionCount
            ))
        }

        return summaries.sorted { $0.name < $1.name }
    }

    private static func loadSkillDetail(name: String, skillsDir: String) -> SkillDetailResponse? {
        let safeName = RecordCommand.sanitizeFileName(name)
        let skillPath = (skillsDir as NSString).appendingPathComponent("\(safeName).json")

        guard let data = FileManager.default.contents(atPath: skillPath) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let skill = try? decoder.decode(RecordedSkill.self, from: data) else { return nil }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return SkillDetailResponse(
            name: skill.name,
            description: skill.description,
            type: "recorded",
            version: skill.version,
            parameters: skill.parameters.map { p in
                SkillParameterResponse(name: p.name, defaultValue: p.defaultValue, description: p.description)
            },
            stepCount: skill.steps.count,
            lastUsedAt: skill.lastUsedAt.map { dateFormatter.string(from: $0) },
            executionCount: skill.executionCount
        )
    }

    private static func updateSkillMetadata(skillPath: String, skill: RecordedSkill) {
        var updated = skill
        updated.lastUsedAt = Date()
        updated.executionCount += 1
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(updated) else { return }
        try? data.write(to: URL(fileURLWithPath: skillPath))
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
