import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

@Suite("SkillExecutor")
struct SkillExecutorTests {

    // MARK: - Mock MCPClient

    final class MockMCPClient: MCPClientProtocol {
        var callResults: [Result<String, Error>]
        var callLog: [(name: String, arguments: [String: Value])] = []
        private var callIndex = 0

        init(callResults: [Result<String, Error>]) {
            self.callResults = callResults
        }

        func callTool(name: String, arguments: [String: Value]) async throws -> String {
            let index = callIndex
            callIndex += 1
            callLog.append((name: name, arguments: arguments))
            guard index < callResults.count else {
                return ""
            }
            switch callResults[index] {
            case .success(let value): return value
            case .failure(let error): throw error
            }
        }

        func listTools() async throws -> [String] {
            return []
        }
    }

    private func makeSkill(
        parameters: [SkillParameter] = [],
        steps: [SkillStep]
    ) -> Skill {
        Skill(
            name: "test_skill",
            description: "test",
            createdAt: Date(),
            sourceRecording: "test",
            parameters: parameters,
            steps: steps
        )
    }

    // MARK: - Parameter Replacement (7.2)

    @Test("{{url}} replaced with user-provided value")
    func test_paramReplacement_userProvided() async throws {
        let client = MockMCPClient(callResults: [.success("ok")])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(
            parameters: [SkillParameter(name: "url", description: "URL")],
            steps: [SkillStep(tool: "open_url", arguments: ["url": "{{url}}"])]
        )

        let result = try await executor.execute(skill: skill, paramValues: ["url": "https://example.com"])
        #expect(result.success)
        #expect(client.callLog[0].arguments["url"] == .string("https://example.com"))
    }

    // MARK: - Parameter Default Values (7.3)

    @Test("parameter uses default value when not provided")
    func test_paramReplacement_defaultValue() async throws {
        let client = MockMCPClient(callResults: [.success("ok")])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(
            parameters: [SkillParameter(name: "search_term", defaultValue: "hello", description: "search")],
            steps: [SkillStep(tool: "type_text", arguments: ["text": "{{search_term}}"])]
        )

        let result = try await executor.execute(skill: skill, paramValues: [:])
        #expect(result.success)
        #expect(client.callLog[0].arguments["text"] == .string("hello"))
    }

    // MARK: - Required Parameter Missing (7.4)

    @Test("missing required parameter throws error")
    func test_requiredParamMissing_throwsError() async {
        let client = MockMCPClient(callResults: [.success("ok")])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(
            parameters: [SkillParameter(name: "url", description: "URL")],
            steps: [SkillStep(tool: "open_url", arguments: ["url": "{{url}}"])]
        )

        do {
            _ = try await executor.execute(skill: skill, paramValues: [:])
            #expect(Bool(false), "Should have thrown")
        } catch let error as AxionError {
            if case .configError(let reason) = error {
                #expect(reason.contains("url"))
            } else {
                Issue.record("Expected configError, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - String→Value Type Conversion (7.5)

    @Test("numeric string converts to .int()")
    func test_stringToIntConversion() async throws {
        let client = MockMCPClient(callResults: [.success("ok")])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(steps: [
            SkillStep(tool: "click", arguments: ["x": "500", "y": "300"]),
        ])

        let result = try await executor.execute(skill: skill, paramValues: [:])
        #expect(result.success)
        #expect(client.callLog[0].arguments["x"] == .int(500))
        #expect(client.callLog[0].arguments["y"] == .int(300))
    }

    @Test("non-numeric string converts to .string()")
    func test_stringToStringConversion() async throws {
        let client = MockMCPClient(callResults: [.success("ok")])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(steps: [
            SkillStep(tool: "launch_app", arguments: ["app_name": "Calculator"]),
        ])

        let result = try await executor.execute(skill: skill, paramValues: [:])
        #expect(result.success)
        #expect(client.callLog[0].arguments["app_name"] == .string("Calculator"))
    }

    // MARK: - Failure Retry (7.7)

    @Test("first failure retries once and succeeds")
    func test_retryOnce_success() async throws {
        let client = MockMCPClient(callResults: [
            .failure(AxionError.mcpError(tool: "click", reason: "element not found")),
            .success("ok"),
        ])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(steps: [
            SkillStep(tool: "click", arguments: ["x": "100"]),
        ])

        let result = try await executor.execute(skill: skill, paramValues: [:])
        #expect(result.success)
        #expect(result.stepsExecuted == 1)
        #expect(client.callLog.count == 2)
    }

    // MARK: - Retry Still Fails (7.8)

    @Test("two failures returns failure result with failedStepIndex")
    func test_retryStillFails_returnsFailure() async throws {
        let client = MockMCPClient(callResults: [
            .failure(AxionError.mcpError(tool: "click", reason: "fail1")),
            .failure(AxionError.mcpError(tool: "click", reason: "fail2")),
        ])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(steps: [
            SkillStep(tool: "click", arguments: ["x": "100"]),
        ])

        let result = try await executor.execute(skill: skill, paramValues: [:])
        #expect(!result.success)
        #expect(result.failedStepIndex == 0)
        #expect(result.errorMessage?.contains("步骤 1 失败") == true)
    }

    // MARK: - Multi-step Execution

    @Test("multiple steps execute in order")
    func test_multiStepExecution() async throws {
        let client = MockMCPClient(callResults: [
            .success("ok1"),
            .success("ok2"),
            .success("ok3"),
        ])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(steps: [
            SkillStep(tool: "launch_app", arguments: ["app_name": "Calculator"]),
            SkillStep(tool: "click", arguments: ["x": "100"]),
            SkillStep(tool: "type_text", arguments: ["text": "hello"]),
        ])

        let result = try await executor.execute(skill: skill, paramValues: [:])
        #expect(result.success)
        #expect(result.stepsExecuted == 3)
        #expect(client.callLog.count == 3)
        #expect(client.callLog[0].name == "launch_app")
        #expect(client.callLog[1].name == "click")
        #expect(client.callLog[2].name == "type_text")
    }

    // MARK: - waitAfterSeconds (7.6)

    @Test("step with waitAfterSeconds completes successfully")
    func test_waitAfterSeconds_completes() async throws {
        let client = MockMCPClient(callResults: [
            .success("ok1"),
            .success("ok2"),
        ])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(steps: [
            SkillStep(tool: "launch_app", arguments: ["app_name": "Calc"], waitAfterSeconds: 0.01),
            SkillStep(tool: "click", arguments: ["x": "100"]),
        ])

        let result = try await executor.execute(skill: skill, paramValues: [:])
        #expect(result.success)
        #expect(result.stepsExecuted == 2)
        #expect(result.durationSeconds >= 0.01)
    }

    @Test("step with zero waitAfterSeconds executes normally")
    func test_waitAfterSeconds_zero() async throws {
        let client = MockMCPClient(callResults: [.success("ok")])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(steps: [
            SkillStep(tool: "click", arguments: ["x": "100"], waitAfterSeconds: 0),
        ])

        let result = try await executor.execute(skill: skill, paramValues: [:])
        #expect(result.success)
    }

    // MARK: - toStringValueDict (unit test for conversion)

    @Test("toStringValueDict converts strings correctly")
    func test_toStringValueDict() {
        let client = MockMCPClient(callResults: [])
        let executor = SkillExecutor(client: client)
        let result = executor.toStringValueDict(["x": "500", "name": "hello", "count": "0"])

        #expect(result["x"] == .int(500))
        #expect(result["name"] == .string("hello"))
        #expect(result["count"] == .int(0))
    }

    // MARK: - stringValueToValue

    @Test("stringValueToValue converts pure int to .int")
    func test_stringValueToValue_int() {
        let client = MockMCPClient(callResults: [])
        let executor = SkillExecutor(client: client)
        #expect(executor.stringValueToValue("42") == .int(42))
        #expect(executor.stringValueToValue("0") == .int(0))
        #expect(executor.stringValueToValue("-5") == .int(-5))
    }

    @Test("stringValueToValue converts non-numeric to .string")
    func test_stringValueToValue_string() {
        let client = MockMCPClient(callResults: [])
        let executor = SkillExecutor(client: client)
        #expect(executor.stringValueToValue("hello") == .string("hello"))
        #expect(executor.stringValueToValue("12.5") == .string("12.5"))
        #expect(executor.stringValueToValue("") == .string(""))
    }

    // MARK: - Duration Tracking

    @Test("successful execution tracks duration")
    func test_durationTracking() async throws {
        let client = MockMCPClient(callResults: [.success("ok")])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(steps: [
            SkillStep(tool: "click", arguments: ["x": "100"]),
        ])

        let result = try await executor.execute(skill: skill, paramValues: [:])
        #expect(result.success)
        #expect(result.durationSeconds >= 0)
    }

    // MARK: - Empty Steps (AC1 edge case)

    @Test("empty steps skill succeeds with 0 steps")
    func test_emptySteps_success() async throws {
        let client = MockMCPClient(callResults: [])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(steps: [])

        let result = try await executor.execute(skill: skill, paramValues: [:])
        #expect(result.success)
        #expect(result.stepsExecuted == 0)
        #expect(result.failedStepIndex == nil)
        #expect(result.errorMessage == nil)
        #expect(result.durationSeconds >= 0)
        #expect(client.callLog.isEmpty)
    }

    // MARK: - Multiple Params in Template (AC2)

    @Test("multiple {{param}} in single argument value")
    func test_multipleParamsInTemplate() async throws {
        let client = MockMCPClient(callResults: [.success("ok")])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(
            parameters: [
                SkillParameter(name: "host", description: "host"),
                SkillParameter(name: "path", description: "path"),
            ],
            steps: [SkillStep(tool: "open_url", arguments: ["url": "https://{{host}}/{{path}}"])]
        )

        let result = try await executor.execute(
            skill: skill,
            paramValues: ["host": "example.com", "path": "api/v1"]
        )
        #expect(result.success)
        #expect(client.callLog[0].arguments["url"] == .string("https://example.com/api/v1"))
    }

    @Test("parameter in middle of string")
    func test_paramInMiddleOfString() async throws {
        let client = MockMCPClient(callResults: [.success("ok")])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(
            parameters: [SkillParameter(name: "domain", description: "domain")],
            steps: [SkillStep(tool: "open_url", arguments: ["url": "https://{{domain}}/api/users"])]
        )

        let result = try await executor.execute(
            skill: skill,
            paramValues: ["domain": "mysite.com"]
        )
        #expect(result.success)
        #expect(client.callLog[0].arguments["url"] == .string("https://mysite.com/api/users"))
    }

    // MARK: - Failure at Non-First Step (AC5)

    @Test("failure at step 3 of 4 returns correct failedStepIndex")
    func test_failureAtMiddleStep() async throws {
        let client = MockMCPClient(callResults: [
            .success("ok1"),
            .success("ok2"),
            .failure(AxionError.mcpError(tool: "click", reason: "not found")),
            .failure(AxionError.mcpError(tool: "click", reason: "still not found")),
        ])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(steps: [
            SkillStep(tool: "launch_app", arguments: ["app_name": "Calc"]),
            SkillStep(tool: "click", arguments: ["x": "100"]),
            SkillStep(tool: "click", arguments: ["x": "200"]),
            SkillStep(tool: "type_text", arguments: ["text": "hello"]),
        ])

        let result = try await executor.execute(skill: skill, paramValues: [:])
        #expect(!result.success)
        #expect(result.failedStepIndex == 2)
        #expect(result.stepsExecuted == 2)
        #expect(result.errorMessage?.contains("步骤 3 失败") == true)
    }

    // MARK: - Mixed Arguments (int + string in same step)

    @Test("mixed int and string arguments in same step")
    func test_mixedArguments() async throws {
        let client = MockMCPClient(callResults: [.success("ok")])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(steps: [
            SkillStep(tool: "click_text", arguments: ["x": "250", "y": "100", "text": "Submit"]),
        ])

        let result = try await executor.execute(skill: skill, paramValues: [:])
        #expect(result.success)
        #expect(client.callLog[0].arguments["x"] == .int(250))
        #expect(client.callLog[0].arguments["y"] == .int(100))
        #expect(client.callLog[0].arguments["text"] == .string("Submit"))
    }

    // MARK: - Negative Int Conversion (7.5 edge case)

    @Test("negative int string converts to .int()")
    func test_negativeIntConversion() async throws {
        let client = MockMCPClient(callResults: [.success("ok")])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(steps: [
            SkillStep(tool: "scroll", arguments: ["delta": "-50"]),
        ])

        let result = try await executor.execute(skill: skill, paramValues: [:])
        #expect(result.success)
        #expect(client.callLog[0].arguments["delta"] == .int(-50))
    }

    // MARK: - Unused Parameter

    @Test("unused parameter does not cause error")
    func test_unusedParameter() async throws {
        let client = MockMCPClient(callResults: [.success("ok")])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(
            parameters: [
                SkillParameter(name: "url", description: "URL"),
                SkillParameter(name: "unused", defaultValue: "x", description: "not used"),
            ],
            steps: [SkillStep(tool: "open_url", arguments: ["url": "{{url}}"])]
        )

        let result = try await executor.execute(
            skill: skill,
            paramValues: ["url": "https://example.com"]
        )
        #expect(result.success)
        #expect(client.callLog[0].arguments["url"] == .string("https://example.com"))
    }

    // MARK: - Step Retry at Step 2 (AC5 extended)

    @Test("retry at step 2 succeeds and execution continues")
    func test_retryAtMiddleStep_succeeds() async throws {
        let client = MockMCPClient(callResults: [
            .success("ok1"),
            .failure(AxionError.mcpError(tool: "click", reason: "transient")),
            .success("ok2_retried"),
            .success("ok3"),
        ])
        let executor = SkillExecutor(client: client)

        let skill = makeSkill(steps: [
            SkillStep(tool: "launch_app", arguments: ["app_name": "Calc"]),
            SkillStep(tool: "click", arguments: ["x": "100"]),
            SkillStep(tool: "type_text", arguments: ["text": "hi"]),
        ])

        let result = try await executor.execute(skill: skill, paramValues: [:])
        #expect(result.success)
        #expect(result.stepsExecuted == 3)
        #expect(client.callLog.count == 4) // 1 + 2 (retry) + 1
    }
}
