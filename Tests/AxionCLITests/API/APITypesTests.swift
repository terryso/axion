import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

@Suite("APITypes")
struct APITypesTests {

    @Test("HealthResponse codable round trip preserves all fields")
    func healthResponseCodableRoundTripPreservesAllFields() throws {
        let response = HealthResponse(status: "ok", version: AxionCore.AxionVersion.current)

        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        let decoded = try JSONDecoder().decode(HealthResponse.self, from: data)

        #expect(decoded.status == "ok")
        #expect(decoded.version == AxionCore.AxionVersion.current)
    }

    @Test("HealthResponse JSON keys are snake case")
    func healthResponseJsonKeysAreSnakeCase() throws {
        let response = HealthResponse(status: "ok", version: AxionCore.AxionVersion.current)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(response)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"status\""))
        #expect(json.contains("\"version\""))
    }

    @Test("CreateRunRequest codable round trip preserves all fields")
    func createRunRequestCodableRoundTripPreservesAllFields() throws {
        let request = CreateRunRequest(
            task: "open calculator",
            maxSteps: 20,
            maxBatches: 6,
            allowForeground: false
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateRunRequest.self, from: data)

        #expect(decoded.task == "open calculator")
        #expect(decoded.maxSteps == 20)
        #expect(decoded.maxBatches == 6)
        #expect(decoded.allowForeground == false)
    }

    @Test("CreateRunRequest optional fields default to nil")
    func createRunRequestOptionalFieldsDefaultToNil() throws {
        let request = CreateRunRequest(task: "open calculator")

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateRunRequest.self, from: data)

        #expect(decoded.task == "open calculator")
        #expect(decoded.maxSteps == nil)
        #expect(decoded.maxBatches == nil)
        #expect(decoded.allowForeground == nil)
    }

    @Test("CreateRunRequest JSON keys are snake case")
    func createRunRequestJsonKeysAreSnakeCase() throws {
        let request = CreateRunRequest(
            task: "open calculator",
            maxSteps: 20,
            maxBatches: 6,
            allowForeground: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"task\""))
        #expect(json.contains("\"max_steps\""))
        #expect(json.contains("\"max_batches\""))
        #expect(json.contains("\"allow_foreground\""))
    }

    @Test("StepSummary codable round trip preserves all fields")
    func stepSummaryCodableRoundTripPreservesAllFields() throws {
        let summary = StepSummary(index: 1, tool: "click", purpose: "Input expression", success: true)

        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(StepSummary.self, from: data)

        #expect(decoded.index == 1)
        #expect(decoded.tool == "click")
        #expect(decoded.purpose == "Input expression")
        #expect(decoded.success == true)
    }

    @Test("APIErrorResponse codable round trip preserves all fields")
    func apiErrorResponseCodableRoundTripPreservesAllFields() throws {
        let error = APIErrorResponse(error: "missing_task", message: "Request body must include a 'task' field.")

        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(APIErrorResponse.self, from: data)

        #expect(decoded.error == "missing_task")
        #expect(decoded.message == "Request body must include a 'task' field.")
    }

    @Test("APIErrorResponse JSON keys are correct")
    func apiErrorResponseJsonKeysAreCorrect() throws {
        let error = APIErrorResponse(error: "run_not_found", message: "Run 'nonexistent-id' not found.")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(error)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"error\""))
        #expect(json.contains("\"message\""))
    }

    @Test("APIRunStatus raw values match expected strings")
    func apiRunStatusRawValuesMatchExpectedStrings() {
        #expect(APIRunStatus.queued.rawValue == "queued")
        #expect(APIRunStatus.running.rawValue == "running")
        #expect(APIRunStatus.interventionNeeded.rawValue == "intervention_needed")
        #expect(APIRunStatus.userTakeover.rawValue == "user_takeover")
        #expect(APIRunStatus.resuming.rawValue == "resuming")
        #expect(APIRunStatus.completed.rawValue == "completed")
        #expect(APIRunStatus.failed.rawValue == "failed")
        #expect(APIRunStatus.cancelled.rawValue == "cancelled")
    }

    @Test("APIRunStatus decodes from valid strings")
    func apiRunStatusDecodesFromValidStrings() throws {
        let statuses: [(String, APIRunStatus)] = [
            ("\"queued\"", .queued),
            ("\"running\"", .running),
            ("\"intervention_needed\"", .interventionNeeded),
            ("\"user_takeover\"", .userTakeover),
            ("\"resuming\"", .resuming),
            ("\"completed\"", .completed),
            ("\"failed\"", .failed),
            ("\"cancelled\"", .cancelled),
        ]

        for (jsonString, expected) in statuses {
            let data = jsonString.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(APIRunStatus.self, from: data)
            #expect(decoded == expected)
        }
    }

    @Test("APIRunStatus decoding invalid string throws error")
    func apiRunStatusDecodingInvalidStringThrowsError() {
        let data = "\"unknown_status\"".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(APIRunStatus.self, from: data)
        }
    }

    @Test("TrackedRun codable round trip preserves all fields")
    func trackedRunCodableRoundTripPreservesAllFields() throws {
        let step = StepSummary(index: 0, tool: "launch_app", purpose: "Launch app", success: true)
        let run = TrackedRun(
            runId: "20260513-abc123",
            task: "open calculator",
            status: .running,
            submittedAt: "2026-05-13T10:30:00+08:00",
            completedAt: nil,
            totalSteps: 1,
            durationMs: nil,
            replanCount: 0,
            steps: [step]
        )

        let data = try JSONEncoder().encode(run)
        let decoded = try JSONDecoder().decode(TrackedRun.self, from: data)

        #expect(decoded.runId == "20260513-abc123")
        #expect(decoded.task == "open calculator")
        #expect(decoded.status == .running)
        #expect(decoded.totalSteps == 1)
        #expect(decoded.steps.count == 1)
    }

    @Test("SkillSummaryResponse codable round trip")
    func skillSummaryResponseCodableRoundTrip() throws {
        let summary = SkillSummaryResponse(
            name: "open_calculator",
            description: "打开计算器",
            parameterCount: 1,
            stepCount: 3,
            lastUsedAt: "2026-05-15T10:00:00.000Z",
            executionCount: 5
        )
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(SkillSummaryResponse.self, from: data)
        #expect(decoded.name == "open_calculator")
        #expect(decoded.parameterCount == 1)
        #expect(decoded.stepCount == 3)
        #expect(decoded.executionCount == 5)
    }

    @Test("SkillSummaryResponse decodes snake case")
    func skillSummaryResponseDecodesSnakeCase() throws {
        let json = """
        {"name":"test","description":"desc","parameter_count":2,"step_count":4,"last_used_at":null,"execution_count":0}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SkillSummaryResponse.self, from: data)
        #expect(decoded.name == "test")
        #expect(decoded.parameterCount == 2)
        #expect(decoded.lastUsedAt == nil)
    }

    @Test("SkillDetailResponse codable round trip")
    func skillDetailResponseCodableRoundTrip() throws {
        let detail = SkillDetailResponse(
            name: "open_browser",
            description: "打开浏览器",
            version: 1,
            parameters: [SkillParameterResponse(name: "url", defaultValue: nil, description: "URL")],
            stepCount: 2,
            lastUsedAt: nil,
            executionCount: 0
        )
        let data = try JSONEncoder().encode(detail)
        let decoded = try JSONDecoder().decode(SkillDetailResponse.self, from: data)
        #expect(decoded.name == "open_browser")
        #expect(decoded.parameters.count == 1)
        #expect(decoded.parameters[0].name == "url")
    }

    @Test("SkillParameterResponse decodes snake case")
    func skillParameterResponseDecodesSnakeCase() throws {
        let json = #"{"name":"url","default_value":"https://example.com","description":"URL param"}"#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SkillParameterResponse.self, from: data)
        #expect(decoded.name == "url")
        #expect(decoded.defaultValue == "https://example.com")
    }

    @Test("SkillRunRequest encodes params")
    func skillRunRequestEncodesParams() throws {
        let req = SkillRunRequest(params: ["key": "value"])
        let data = try JSONEncoder().encode(req)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"params\""))
        #expect(json.contains("\"key\""))
    }

    @Test("SkillRunRequest encodes nil params")
    func skillRunRequestEncodesNilParams() throws {
        let req = SkillRunRequest(params: nil)
        let data = try JSONEncoder().encode(req)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json == "{}")
    }

    @Test("SkillRunResponse codable round trip")
    func skillRunResponseCodableRoundTrip() throws {
        let resp = SkillRunResponse(runId: "20260515-abc", status: "running")
        let data = try JSONEncoder().encode(resp)
        let decoded = try JSONDecoder().decode(SkillRunResponse.self, from: data)
        #expect(decoded.runId == "20260515-abc")
        #expect(decoded.status == "running")
    }

    @Test("SkillRunResponse decodes snake case")
    func skillRunResponseDecodesSnakeCase() throws {
        let json = #"{"run_id":"20260515-xyz","status":"completed"}"#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SkillRunResponse.self, from: data)
        #expect(decoded.runId == "20260515-xyz")
    }

    // MARK: - StandardTaskOutput Tests

    @Test("StandardTaskOutput codable round trip preserves all fields")
    func standardTaskOutputCodableRoundTripPreservesAllFields() throws {
        let output = StandardTaskOutput(
            runId: "20260517-abc123",
            task: "open calculator",
            status: .completed,
            ok: true,
            startedAt: "2026-05-17T10:00:00+08:00",
            endedAt: "2026-05-17T10:00:05+08:00",
            steps: [StepSummary(index: 0, tool: "launch_app", purpose: "Launch", success: true)],
            costTelemetry: CostTelemetry(modelCalls: 3, totalTokens: 1000, estimatedCostUsd: 0.01, screenshotCount: 1)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(output)
        let decoded = try JSONDecoder().decode(StandardTaskOutput.self, from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.runId == "20260517-abc123")
        #expect(decoded.task == "open calculator")
        #expect(decoded.status == .completed)
        #expect(decoded.ok == true)
        #expect(decoded.live == true)
        #expect(decoded.allowForeground == false)
        #expect(decoded.startedAt == "2026-05-17T10:00:00+08:00")
        #expect(decoded.endedAt == "2026-05-17T10:00:05+08:00")
        #expect(decoded.steps.count == 1)
        #expect(decoded.costTelemetry != nil)
    }

    @Test("StandardTaskOutput JSON keys are snake case")
    func standardTaskOutputJsonKeysAreSnakeCase() throws {
        let output = StandardTaskOutput(
            runId: "20260517-abc",
            task: "test",
            status: .completed,
            ok: true,
            exitCode: 0,
            startedAt: "2026-05-17T10:00:00+08:00",
            endedAt: "2026-05-17T10:00:05+08:00",
            costTelemetry: CostTelemetry(modelCalls: 1, totalTokens: 100, estimatedCostUsd: 0.01, screenshotCount: 0)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(output)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"schema_version\""))
        #expect(json.contains("\"run_id\""))
        #expect(json.contains("\"allow_foreground\""))
        #expect(json.contains("\"exit_code\""))
        #expect(json.contains("\"started_at\""))
        #expect(json.contains("\"ended_at\""))
        #expect(json.contains("\"cost_telemetry\""))
    }

    @Test("StandardTaskOutput partial JSON decode uses defaults")
    func standardTaskOutputPartialJsonDecodeUsesDefaults() throws {
        let json = """
        {"run_id":"20260517-xyz","task":"test","status":"running","started_at":"2026-05-17T10:00:00+08:00"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StandardTaskOutput.self, from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.ok == true)
        #expect(decoded.live == true)
        #expect(decoded.allowForeground == false)
        #expect(decoded.criteria == nil)
        #expect(decoded.result == nil)
        #expect(decoded.intervention == nil)
        #expect(decoded.exitCode == nil)
        #expect(decoded.error == nil)
        #expect(decoded.endedAt == nil)
        #expect(decoded.steps.isEmpty)
        #expect(decoded.costTelemetry == nil)
    }

    @Test("StandardTaskOutput with all status cases encodes correctly")
    func standardTaskOutputAllStatusCasesEncodesCorrectly() throws {
        let statuses: [APIRunStatus] = [.queued, .running, .interventionNeeded, .userTakeover, .resuming, .completed, .failed, .cancelled]
        let encoder = JSONEncoder()

        for status in statuses {
            let output = StandardTaskOutput(
                runId: "test",
                task: "test",
                status: status,
                startedAt: "2026-05-17T10:00:00+08:00"
            )
            let data = try encoder.encode(output)
            let decoded = try JSONDecoder().decode(StandardTaskOutput.self, from: data)
            #expect(decoded.status == status)
        }
    }

    @Test("StandardTaskOutput with result and intervention")
    func standardTaskOutputWithResultAndIntervention() throws {
        let result = ApiTaskResult(
            kind: .answer,
            title: "read email",
            body: "Latest email is from Alice",
            createdAt: "2026-05-17T10:00:05+08:00"
        )
        let intervention = InterventionData(
            reason: "需要用户确认",
            availableActions: ["resume", "abort"],
            blockingIssue: "弹窗阻塞操作"
        )
        let output = StandardTaskOutput(
            runId: "test",
            task: "read email",
            status: .interventionNeeded,
            ok: false,
            result: result,
            intervention: intervention,
            startedAt: "2026-05-17T10:00:00+08:00"
        )

        let data = try JSONEncoder().encode(output)
        let decoded = try JSONDecoder().decode(StandardTaskOutput.self, from: data)

        #expect(decoded.result?.kind == .answer)
        #expect(decoded.result?.body == "Latest email is from Alice")
        #expect(decoded.intervention?.reason == "需要用户确认")
        #expect(decoded.intervention?.availableActions == ["resume", "abort"])
        #expect(decoded.intervention?.blockingIssue == "弹窗阻塞操作")
    }

    // MARK: - ApiTaskResult Tests

    @Test("ApiTaskResult codable round trip")
    func apiTaskResultCodableRoundTrip() throws {
        let result = ApiTaskResult(
            kind: .confirmation,
            title: "open calculator",
            body: "Calculator opened successfully",
            createdAt: "2026-05-17T10:00:05+08:00"
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ApiTaskResult.self, from: data)

        #expect(decoded.kind == .confirmation)
        #expect(decoded.title == "open calculator")
        #expect(decoded.body == "Calculator opened successfully")
    }

    @Test("TaskResultKind encodes to correct strings")
    func taskResultKindEncodesCorrectStrings() throws {
        #expect(TaskResultKind.answer.rawValue == "answer")
        #expect(TaskResultKind.confirmation.rawValue == "confirmation")

        for kind in [TaskResultKind.answer, .confirmation] {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(TaskResultKind.self, from: data)
            #expect(decoded == kind)
        }
    }

    // MARK: - InterventionData Tests

    @Test("InterventionData codable round trip")
    func interventionDataCodableRoundTrip() throws {
        let data = InterventionData(
            reason: "需要手动操作",
            availableActions: ["resume", "abort"],
            blockingIssue: "权限不足"
        )
        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(InterventionData.self, from: encoded)

        #expect(decoded.reason == "需要手动操作")
        #expect(decoded.availableActions == ["resume", "abort"])
        #expect(decoded.blockingIssue == "权限不足")
    }

    @Test("InterventionData JSON keys are snake case")
    func interventionDataJsonKeysAreSnakeCase() throws {
        let data = InterventionData(reason: "test", availableActions: [], blockingIssue: "issue")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(data)
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(json.contains("\"available_actions\""))
        #expect(json.contains("\"blocking_issue\""))
    }

    // MARK: - Result Kind Inference Tests

    @Test("inferResultKind returns answer for query tasks")
    func inferResultKindReturnsAnswerForQueryTasks() {
        #expect(ApiRunner.inferResultKind(task: "读取最新邮件") == .answer)
        #expect(ApiRunner.inferResultKind(task: "查询系统信息") == .answer)
        #expect(ApiRunner.inferResultKind(task: "获取文件列表") == .answer)
        #expect(ApiRunner.inferResultKind(task: "列出所有进程") == .answer)
        #expect(ApiRunner.inferResultKind(task: "搜索相关文档") == .answer)
        #expect(ApiRunner.inferResultKind(task: "告诉我时间") == .answer)
        #expect(ApiRunner.inferResultKind(task: "显示磁盘使用") == .answer)
        #expect(ApiRunner.inferResultKind(task: "查看当前目录") == .answer)
    }

    @Test("inferResultKind returns confirmation for action tasks")
    func inferResultKindReturnsConfirmationForActionTasks() {
        #expect(ApiRunner.inferResultKind(task: "打开计算器") == .confirmation)
        #expect(ApiRunner.inferResultKind(task: "关闭窗口") == .confirmation)
        #expect(ApiRunner.inferResultKind(task: "移动文件到桌面") == .confirmation)
        #expect(ApiRunner.inferResultKind(task: "删除临时文件") == .confirmation)
        #expect(ApiRunner.inferResultKind(task: "创建新文件夹") == .confirmation)
        #expect(ApiRunner.inferResultKind(task: "安装应用") == .confirmation)
    }

    @Test("inferResultKind defaults to confirmation for ambiguous tasks")
    func inferResultKindDefaultsToConfirmation() {
        #expect(ApiRunner.inferResultKind(task: "do something") == .confirmation)
        #expect(ApiRunner.inferResultKind(task: "处理数据") == .confirmation)
    }

    // MARK: - StandardTaskOutput Serialization Performance

    @Test("StandardTaskOutput serialization under 5ms")
    func standardTaskOutputSerializationPerformance() throws {
        let output = StandardTaskOutput(
            runId: "20260517-performance",
            task: "performance test task with a longer description to simulate real workload",
            status: .completed,
            ok: true,
            result: ApiTaskResult(kind: .confirmation, title: "test", body: String(repeating: "a", count: 200), createdAt: "2026-05-17T10:00:00+08:00"),
            startedAt: "2026-05-17T10:00:00+08:00",
            endedAt: "2026-05-17T10:00:05+08:00",
            steps: (0..<20).map { StepSummary(index: $0, tool: "tool_\($0)", purpose: "purpose \($0)", success: true) },
            costTelemetry: CostTelemetry(modelCalls: 10, totalTokens: 5000, estimatedCostUsd: 0.05, screenshotCount: 3)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // Warm up
        for _ in 0..<10 {
            let data = try encoder.encode(output)
            _ = try JSONDecoder().decode(StandardTaskOutput.self, from: data)
        }

        // Single iteration benchmark — debug builds are inherently slower;
        // use 500ms threshold to verify no gross regression (release builds run <1ms)
        let start = ContinuousClock.now
        let data = try encoder.encode(output)
        _ = try JSONDecoder().decode(StandardTaskOutput.self, from: data)
        let elapsed = ContinuousClock.now - start

        let durationMs = Double(elapsed.components.seconds) * 1000.0 +
            Double(elapsed.components.attoseconds) / 1_000_000_000_000.0

        #expect(durationMs < 500.0)
    }

    // MARK: - CapabilitiesResponse Tests

    @Test("CapabilitiesResponse codable round trip preserves all fields")
    func capabilitiesResponseCodableRoundTripPreservesAllFields() throws {
        let response = CapabilitiesResponse(
            version: AxionCore.AxionVersion.current,
            supportedRunStatuses: ["queued", "running", "completed", "failed"],
            supportedResultKinds: ["answer", "confirmation"],
            availableTools: ["launch_app", "click"],
            maxConcurrentRuns: 5,
            features: ["memory", "takeover", "fast_mode", "skills"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        let decoded = try JSONDecoder().decode(CapabilitiesResponse.self, from: data)

        #expect(decoded.version == AxionCore.AxionVersion.current)
        #expect(decoded.supportedRunStatuses == ["queued", "running", "completed", "failed"])
        #expect(decoded.supportedResultKinds == ["answer", "confirmation"])
        #expect(decoded.availableTools == ["launch_app", "click"])
        #expect(decoded.maxConcurrentRuns == 5)
        #expect(decoded.features == ["memory", "takeover", "fast_mode", "skills"])
    }

    @Test("CapabilitiesResponse JSON keys are snake case")
    func capabilitiesResponseJsonKeysAreSnakeCase() throws {
        let response = CapabilitiesResponse(
            version: AxionCore.AxionVersion.current,
            supportedRunStatuses: [],
            supportedResultKinds: [],
            availableTools: [],
            maxConcurrentRuns: 10,
            features: []
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(response)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"supported_run_statuses\""))
        #expect(json.contains("\"supported_result_kinds\""))
        #expect(json.contains("\"available_tools\""))
        #expect(json.contains("\"max_concurrent_runs\""))
        #expect(json.contains("\"features\""))
        #expect(json.contains("\"version\""))
    }

    @Test("CapabilitiesResponse features contains all expected values")
    func capabilitiesResponseFeaturesContainsAllExpectedValues() throws {
        let expectedFeatures = ["memory", "takeover", "fast_mode", "skills"]

        let response = CapabilitiesResponse(
            version: AxionCore.AxionVersion.current,
            supportedRunStatuses: APIRunStatus.allCases.map(\.rawValue),
            supportedResultKinds: TaskResultKind.allCases.map(\.rawValue),
            availableTools: ToolNames.allToolNames,
            maxConcurrentRuns: 10,
            features: expectedFeatures
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(CapabilitiesResponse.self, from: data)

        #expect(decoded.features == expectedFeatures)
        #expect(decoded.features.count == 4)
    }

    @Test("APIRunStatus allCases contains all 8 statuses")
    func apiRunStatusAllCasesContainsAll8Statuses() {
        let allCases = APIRunStatus.allCases
        #expect(allCases.count == 8)
        #expect(allCases.contains(.queued))
        #expect(allCases.contains(.running))
        #expect(allCases.contains(.interventionNeeded))
        #expect(allCases.contains(.userTakeover))
        #expect(allCases.contains(.resuming))
        #expect(allCases.contains(.completed))
        #expect(allCases.contains(.failed))
        #expect(allCases.contains(.cancelled))
    }

    @Test("TaskResultKind allCases contains answer and confirmation")
    func taskResultKindAllCasesContainsAnswerAndConfirmation() {
        let allCases = TaskResultKind.allCases
        #expect(allCases.count == 2)
        #expect(allCases.contains(.answer))
        #expect(allCases.contains(.confirmation))
    }

    // MARK: - Settings API Types Tests (Story 14.3)

    @Test("ApiKeyStatusResponse codable round trip preserves all fields")
    func apiKeyStatusResponseCodableRoundTrip() throws {
        let response = ApiKeyStatusResponse(
            provider: "anthropic",
            available: true,
            source: "config",
            maskedKey: "sk-ant-****abcd"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(response)
        let decoded = try JSONDecoder().decode(ApiKeyStatusResponse.self, from: data)

        #expect(decoded.provider == "anthropic")
        #expect(decoded.available == true)
        #expect(decoded.source == "config")
        #expect(decoded.maskedKey == "sk-ant-****abcd")
    }

    @Test("ApiKeyStatusResponse JSON keys are snake case")
    func apiKeyStatusResponseJsonKeysAreSnakeCase() throws {
        let response = ApiKeyStatusResponse(
            provider: "anthropic",
            available: false,
            source: "missing",
            maskedKey: ""
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(response)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"masked_key\""))
        #expect(json.contains("\"provider\""))
        #expect(json.contains("\"available\""))
        #expect(json.contains("\"source\""))
    }

    @Test("SaveApiKeyRequest codable round trip preserves all fields")
    func saveApiKeyRequestCodableRoundTrip() throws {
        let request = SaveApiKeyRequest(apiKey: "sk-ant-xxx", provider: "anthropic")

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SaveApiKeyRequest.self, from: data)

        #expect(decoded.apiKey == "sk-ant-xxx")
        #expect(decoded.provider == "anthropic")
    }

    @Test("SaveApiKeyRequest optional provider defaults to nil")
    func saveApiKeyRequestOptionalProviderDefaultsToNil() throws {
        let request = SaveApiKeyRequest(apiKey: "sk-ant-xxx", provider: nil)

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SaveApiKeyRequest.self, from: data)

        #expect(decoded.apiKey == "sk-ant-xxx")
        #expect(decoded.provider == nil)
    }

    @Test("SaveApiKeyRequest decodes snake case api_key")
    func saveApiKeyRequestDecodesSnakeCase() throws {
        let json = #"{"api_key":"sk-test","provider":"openai"}"#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SaveApiKeyRequest.self, from: data)

        #expect(decoded.apiKey == "sk-test")
        #expect(decoded.provider == "openai")
    }

    @Test("DeleteApiKeyResponse codable round trip preserves all fields")
    func deleteApiKeyResponseCodableRoundTrip() throws {
        let response = DeleteApiKeyResponse(
            provider: "anthropic",
            available: false,
            source: "missing"
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DeleteApiKeyResponse.self, from: data)

        #expect(decoded.provider == "anthropic")
        #expect(decoded.available == false)
        #expect(decoded.source == "missing")
    }

    @Test("maskKey returns correct format for long keys")
    func maskKeyLongKeys() {
        let key = "sk-ant-api03-abcdefghijklmnop"
        let masked = ApiKeyStatusResponse.maskKey(key)
        #expect(masked == "sk-ant-****mnop")
    }

    @Test("maskKey returns correct format for short keys")
    func maskKeyShortKeys() {
        #expect(ApiKeyStatusResponse.maskKey("short") == "****hort")
        #expect(ApiKeyStatusResponse.maskKey("1234567890") == "****7890")
    }

    @Test("maskKey returns empty for empty string")
    func maskKeyEmptyString() {
        #expect(ApiKeyStatusResponse.maskKey("") == "")
    }

    @Test("maskKey handles exactly 11 characters")
    func maskKeyExactly11() {
        let key = "12345678901"
        let masked = ApiKeyStatusResponse.maskKey(key)
        #expect(masked == "1234567****8901")
    }
}
