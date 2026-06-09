import Foundation
import Hummingbird
import NIOCore

import AxionCore
import OpenAgentSDK

// Disambiguate: AxionCore.Skill = recorded skill model, OpenAgentSDK.Skill = prompt skill model
// (declared in AxionAPI.swift)

extension AxionAPI {

    // MARK: - Skills Route Registration

    /// Register skills API routes (GET /v1/skills, GET /v1/skills/:name, POST /v1/skills/:name/run).
    static func registerSkillsRoutes(
        on router: RouterGroup<BasicRequestContext>,
        config: AxionConfig,
        runCoordinator: RunCoordinator,
        eventBroadcaster: OpenAgentSDK.EventBroadcaster,
        skillRegistry: SkillRegistry?,
        resolvedSkillsDir: String
    ) {
        // GET /v1/skills — list all skills (merged dual sources)
        router.get("skills") { _, _ in
            let summaries = Self.loadAllSkillSummaries(registry: skillRegistry, skillsDir: resolvedSkillsDir)
            let data = try axionSortedEncoder.encode(summaries)
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
                throw AxionAPIError.apiError(status: .badRequest, error: "missing_skill_name", message: "Skill name is required.")
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

            throw AxionAPIError.apiError(status: .notFound, error: "skill_not_found", message: "Skill '\(name)' not found.")
        }

        // POST /v1/skills/:name/run — execute a skill (dual path: prompt vs recorded)
        router.post("skills/:name/run") { request, context in
            guard let name = context.parameters.get("name") else {
                throw AxionAPIError.apiError(status: .badRequest, error: "missing_skill_name", message: "Skill name is required.")
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
            let skillPath = resolveFilePath(name: name, in: resolvedSkillsDir)

            guard FileManager.default.fileExists(atPath: skillPath) else {
                throw AxionAPIError.apiError(status: .notFound, error: "skill_not_found", message: "Skill '\(name)' not found.")
            }
            guard let skill = loadDecodableFile(skillPath, as: RecordedSkill.self, decoder: axionPersistentDecoder) else {
                throw AxionAPIError.apiError(status: .badRequest, error: "invalid_skill", message: "Failed to parse skill file.")
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
                    throw AxionAPIError.apiError(status: .badRequest, error: "missing_parameter", message: "Missing required parameter: \(param.name)")
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

    // MARK: - Skill Helpers

    /// Load skill summaries from both prompt skills (SkillRegistry) and recorded skills (JSON files).
    /// Prompt skills take priority on name collision (consistent with CLI dual-track lookup).
    static func loadAllSkillSummaries(registry: SkillRegistry?, skillsDir: String) -> [SkillSummaryResponse] {
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

    static func loadRecordedSkillSummaries(skillsDir: String) -> [SkillSummaryResponse] {
        loadAllRecordedSkills(in: skillsDir).map { name, skill in
            SkillSummaryResponse(
                name: skill.name,
                description: skill.description,
                type: "recorded",
                parameterCount: skill.parameters.count,
                stepCount: skill.steps.count,
                lastUsedAt: skill.lastUsedAt.map { axionISO8601Formatter.string(from: $0) },
                executionCount: skill.executionCount
            )
        }
    }

    static func loadSkillDetail(name: String, skillsDir: String) -> SkillDetailResponse? {
        let skillPath = resolveFilePath(name: name, in: skillsDir)

        guard let skill = loadDecodableFile(skillPath, as: RecordedSkill.self, decoder: axionPersistentDecoder) else { return nil }

        return SkillDetailResponse(
            name: skill.name,
            description: skill.description,
            type: "recorded",
            version: skill.version,
            parameters: skill.parameters.map { p in
                SkillParameterResponse(name: p.name, defaultValue: p.defaultValue, description: p.description)
            },
            stepCount: skill.steps.count,
            lastUsedAt: skill.lastUsedAt.map { axionISO8601Formatter.string(from: $0) },
            executionCount: skill.executionCount
        )
    }

    static func updateSkillMetadata(skillPath: String, skill: RecordedSkill) {
        var updated = skill
        updated.lastUsedAt = Date()
        updated.executionCount += 1
        guard let data = try? axionPersistentEncoder.encode(updated) else { return }
        try? data.write(to: URL(fileURLWithPath: skillPath))
    }
}
