import Foundation
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
        let resolvedSkillsDir = skillsDirectory ?? SkillCompileCommand.skillsDirectory()

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

        // MARK: - Settings API Routes (Story 14.3)

        // GET /v1/settings/api-key — get API key status
        router.get("settings/api-key") { _, _ in
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
        router.post("settings/api-key") { request, context in
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
            let configPath = (resolvedConfigDir as NSString).appendingPathComponent("config.json")
            if let fileData = FileManager.default.contents(atPath: configPath),
               let decoded = try? JSONDecoder().decode(AxionConfig.self, from: fileData) {
                fileConfig = decoded
            } else {
                fileConfig = config
            }
            fileConfig.apiKey = saveRequest.apiKey
            try ConfigManager.saveConfigFile(fileConfig, toDirectory: resolvedConfigDir)

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
        router.delete("settings/api-key") { _, _ in
            // Load current config from file, clear apiKey, save back
            var fileConfig: AxionConfig
            let configPath = (resolvedConfigDir as NSString).appendingPathComponent("config.json")
            if let fileData = FileManager.default.contents(atPath: configPath),
               let decoded = try? JSONDecoder().decode(AxionConfig.self, from: fileData) {
                fileConfig = decoded
            } else {
                fileConfig = config
            }
            fileConfig.apiKey = nil
            try ConfigManager.saveConfigFile(fileConfig, toDirectory: resolvedConfigDir)

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

        // MARK: - Skill API Routes (Story 10.3, Story 18.3)

        // GET /v1/skills — list all skills (merged dual sources)
        router.get("skills") { _, _ in
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
        router.get("skills/:name") { _, context in
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
        router.post("skills/:name/run") { request, context in
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

                // Submit run via RunCoordinator
                let taskDescription = "技能(prompt): \(promptSkill.name) — \(task)"
                let runId = await runCoordinator.submitRun(
                    task: taskDescription,
                    request: OpenAgentSDK.CreateRunRequest(task: taskDescription)
                )

                // Execute skill agent in background
                let capturedConfig = config
                let capturedSkill = promptSkill
                _ = _Concurrency.Task.detached {
                    let result = await ApiRunner.runSkillAgent(
                        skill: capturedSkill,
                        task: task,
                        config: capturedConfig,
                        runId: runId,
                        eventBroadcaster: eventBroadcaster,
                        runTracker: runCoordinator,
                        verbose: false,
                        completion: { _, _, _, _, _, _, _ in }
                    )
                    await runCoordinator.updateRun(
                        runId: runId,
                        status: result.finalStatus,
                        steps: result.stepSummaries,
                        durationMs: result.durationMs,
                        replanCount: result.replanCount,
                        costTelemetry: result.costTelemetry
                    )
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

            // Submit run via RunCoordinator — skill execution in background
            let taskDescription = "技能: \(skill.name)"
            let runId = await runCoordinator.submitRun(
                task: taskDescription,
                request: OpenAgentSDK.CreateRunRequest(task: taskDescription)
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
                await runCoordinator.updateRun(
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
