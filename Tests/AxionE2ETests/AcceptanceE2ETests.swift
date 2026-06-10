import Foundation
import Testing

import AxionCore
import OpenAgentSDK
@testable import AxionCLI

/// Acceptance E2E tests — mirrors the 5 manual tests from docs/ACCEPTANCE.md.
///
/// Tests call real LLM APIs and execute real operations (no mocks).
/// Run via: `swift test --filter "AxionE2ETests.AcceptanceE2E"`
///
/// Prerequisites:
/// - `~/.axion/config.json` with valid API key (via `axion setup`)
/// - AxionHelper.app built + AX permissions (for Test 2)
/// - polyv-live-cli installed (for Test 4)
/// - ffmpeg installed (for Test 5)
@Suite("Acceptance E2E")
struct AcceptanceE2ETests {

    // MARK: - Test 1: Pure Calculation

    @Test("acceptance: pure calculation — no tool calls")
    func testPureCalculation() async throws {
        let task = "30+40*30="

        guard let result = try await runAgentNoMCP(task: task, maxTurns: 2) else { return }

        #expect(result.toolCalls.isEmpty, "Pure calculation should not call any tools, got: \(result.toolCalls)")

        let passed = try await judgeResult(task: task, toolCalls: result.toolCalls, resultText: result.resultText)
        #expect(passed, "LLM judge: result does not satisfy task '\(task)'. Result: \(result.resultText.prefix(200))")
    }

    // MARK: - Test 2: GUI Automation (Calculator)

    @Test("acceptance: GUI automation — calculator")
    func testGUIAutomation() async throws {
        let task = "帮我打开计算器计算 10 * 67"

        guard let result = try await runAgentWithMCP(task: task, maxTurns: 12) else { return }

        let hasMCP = result.toolCalls.contains { $0.contains("mcp__") }
        #expect(hasMCP, "GUI task should use MCP tools, got: \(result.toolCalls)")

        let passed = try await judgeResult(task: task, toolCalls: result.toolCalls, resultText: result.resultText)
        print("[debug] Judge response for GUI test: \(result.resultText)")

        #expect(passed, "LLM judge: result does not satisfy task '\(task)'. Result: \(result.resultText.prefix(200))")
    }

    // MARK: - Test 3: Web Search

    @Test("acceptance: web search — weather")
    func testWebSearch() async throws {
        let task = "今天广州天气如何"

        guard let result = try await runAgentNoMCP(task: task, maxTurns: 5) else { return }

        let hasWebTool = result.toolCalls.contains { $0 == "WebSearch" || $0 == "WebFetch" }
        #expect(hasWebTool, "Weather task should use WebSearch or WebFetch, got: \(result.toolCalls)")

        let passed = try await judgeResult(task: task, toolCalls: result.toolCalls, resultText: result.resultText)
        #expect(passed, "LLM judge: result does not satisfy task '\(task)'. Result: \(result.resultText.prefix(200))")
    }

    // MARK: - Test 4: Skill Call

    @Test("acceptance: skill call — polyv-live-cli")
    func testSkillCall() async throws {
        guard FileManager.default.fileExists(atPath: "/Users/nick/.nvm/versions/node/v23.5.0/bin/polyv-live-cli") else {
            print("[skip] polyv-live-cli not found — skipping skill test")
            return
        }

        let task = "/polyv-live-cli 获取最新5个频道信息"
        let maxRetries = 2

        for attempt in 1...maxRetries {
            guard let result = try await runAgentNoMCP(task: task, maxTurns: 5) else { return }

            let hasSkill = result.toolCalls.contains("Skill")
            if !hasSkill {
                #expect(hasSkill, "Skill task should call Skill tool, got: \(result.toolCalls)")
                return
            }

            let passed = try await judgeResult(task: task, toolCalls: result.toolCalls, resultText: result.resultText)
            if passed {
                return  // Test passed
            }

            if attempt < maxRetries {
                print("[retry] testSkillCall attempt \(attempt)/\(maxRetries) judge failed. subtype=\(String(describing: result.resultSubtype)), resultText=\(result.resultText.prefix(200))")
                try? await _Concurrency.Task.sleep(for: .seconds(2))
                continue
            }

            // Final attempt — fail with diagnostic info
            #expect(passed, "LLM judge: result does not satisfy task '\(task)' after \(maxRetries) attempts. subtype=\(String(describing: result.resultSubtype)), resultText=\(result.resultText.prefix(500))")
        }
    }

    // MARK: - Test 5: Bash Execution

    @Test("acceptance: bash execution — ffmpeg")
    func testBashExecution() async throws {
        let downloads = "/Users/nick/Downloads"
        let contents = try FileManager.default.contentsOfDirectory(atPath: downloads)
        guard let mp4 = contents.first(where: { $0.hasSuffix(".mp4") }) else {
            print("[skip] No .mp4 file in Downloads — skipping bash test")
            return
        }

        let task = "帮我压缩一下~/Downloads/\(mp4)"

        guard let result = try await runAgentNoMCP(task: task, maxTurns: 8) else { return }

        let hasBash = result.toolCalls.contains("Bash")
        #expect(hasBash, "FFmpeg task should use Bash tool, got: \(result.toolCalls)")

        let passed = try await judgeResult(task: task, toolCalls: result.toolCalls, resultText: result.resultText)
        #expect(passed, "LLM judge: result does not satisfy task '\(task)'. Result: \(result.resultText.prefix(200))")
    }

    // MARK: - Helpers

    private struct AgentResult {
        let toolCalls: [String]
        let resultText: String
        let resultSubtype: SDKMessage.ResultData.Subtype?
    }

    /// Build agent WITHOUT MCP servers (for tests 1, 3, 4, 5).
    /// Uses the same system prompt and tools as production but skips helper path requirement.
    private func runAgentNoMCP(task: String, maxTurns: Int = 5) async throws -> AgentResult? {
        let config = try await ConfigManager.loadConfig()
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            print("[skip] No API key configured")
            return nil
        }

        let promptDir = PromptBuilder.resolvePromptDirectory()
        let mcpPrefixedToolNames = ToolNames.allToolNames.map { "mcp__axion-helper__\($0)" }

        let systemPrompt = (try? PromptBuilder.load(
            name: "planner-system",
            variables: [
                "tools": PromptBuilder.buildToolListDescription(from: mcpPrefixedToolNames),
                "max_steps": String(maxTurns),
            ],
            fromDirectory: promptDir
        )) ?? ""

        let skillRegistry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: skillRegistry)
        _ = skillRegistry.registerDiscoveredSkills()

        let skillsPrompt = skillRegistry.formatSkillsForPrompt()
        let fullPrompt = AgentBuilder.buildFullSystemPrompt(
            basePrompt: systemPrompt,
            skillsPrompt: skillsPrompt
        )

        let excludedToolNames: Set<String> = ["ToolSearch", "AskUser"]
        var agentTools: [ToolProtocol] = (getAllBaseTools(tier: .core) + getAllBaseTools(tier: .specialist))
            .filter { !excludedToolNames.contains($0.name) }
        agentTools.append(createSkillTool(registry: skillRegistry))

        let options = AgentOptions(
            apiKey: apiKey,
            model: config.model,
            baseURL: config.baseURL,
            systemPrompt: fullPrompt,
            maxTurns: maxTurns,
            maxTokens: 4096,
            permissionMode: .bypassPermissions,
            tools: agentTools,
            mcpServers: nil,
            skillRegistry: skillRegistry,
            logLevel: .info
        )

        let agent = createAgent(options: options)
        return await collectResult(agent: agent, task: task)
    }

    /// Build agent WITH MCP servers (for test 2 — GUI automation).
    private func runAgentWithMCP(task: String, maxTurns: Int = 12) async throws -> AgentResult? {
        let config = try await ConfigManager.loadConfig()
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            print("[skip] No API key configured")
            return nil
        }
        guard let helperPath = HelperPathResolver.resolveHelperPath() else {
            print("[skip] Helper path not found")
            return nil
        }

        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath))
        ]

        let promptDir = PromptBuilder.resolvePromptDirectory()
        let mcpPrefixedToolNames = ToolNames.allToolNames.map { "mcp__axion-helper__\($0)" }

        let systemPrompt = (try? PromptBuilder.load(
            name: "planner-system",
            variables: [
                "tools": PromptBuilder.buildToolListDescription(from: mcpPrefixedToolNames),
                "max_steps": String(maxTurns),
            ],
            fromDirectory: promptDir
        )) ?? ""

        let excludedToolNames: Set<String> = ["ToolSearch", "AskUser"]
        var agentTools: [ToolProtocol] = (getAllBaseTools(tier: .core) + getAllBaseTools(tier: .specialist))
            .filter { !excludedToolNames.contains($0.name) }

        let skillRegistry = SkillRegistry()
        agentTools.append(createSkillTool(registry: skillRegistry))

        let options = AgentOptions(
            apiKey: apiKey,
            model: config.model,
            baseURL: config.baseURL,
            systemPrompt: systemPrompt,
            maxTurns: maxTurns,
            maxTokens: 4096,
            permissionMode: .bypassPermissions,
            tools: agentTools,
            mcpServers: mcpServers,
            skillRegistry: skillRegistry,
            logLevel: .info
        )

        let agent = createAgent(options: options)
        return await collectResult(agent: agent, task: task)
    }

    /// Stream agent messages and collect toolCalls + full text output.
    /// Captures tool result content so the LLM judge has context even when
    /// the agent's final summary is empty (e.g. errorDuringExecution).
    private func collectResult(agent: Agent, task: String) async -> AgentResult? {
        var toolCalls: [String] = []
        var assistantTexts: [String] = []
        var toolResults: [String] = []
        var resultText = ""
        var resultSubtype: SDKMessage.ResultData.Subtype?

        let stream = agent.stream(task)
        for await message in stream {
            switch message {
            case .toolUse(let data):
                toolCalls.append(data.toolName)
            case .assistant(let data):
                assistantTexts.append(data.text)
            case .toolResult(let data):
                toolResults.append(data.content)
            case .result(let data):
                resultText = data.text
                resultSubtype = data.subtype
            default:
                break
            }
        }

        try? await agent.close()

        // Combine all text for judge: assistant messages → tool results → final result
        var fullText = assistantTexts.joined(separator: "\n")
        if !toolResults.isEmpty {
            if !fullText.isEmpty { fullText += "\n" }
            fullText += "[Tool Results]\n" + toolResults.joined(separator: "\n---\n")
        }
        if !resultText.isEmpty {
            if !fullText.isEmpty { fullText += "\n" }
            fullText += resultText
        }

        return AgentResult(toolCalls: toolCalls, resultText: fullText, resultSubtype: resultSubtype)
    }

    /// LLM-as-judge: ask the LLM to verify the result is correct.
    private func judgeResult(task: String, toolCalls: [String] = [], resultText: String) async throws -> Bool {
        let config = try await ConfigManager.loadConfig()
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            return false
        }

        let judgeOptions = AgentOptions(
            apiKey: apiKey,
            model: config.model,
            baseURL: config.baseURL,
            systemPrompt: "你是一个测试验收助手。判断 Agent 是否正确完成了用户任务。只要结果中包含正确答案、成功操作的证据、或合理地进行了尝试（如 GUI 操作已执行、工具调用成功）即可判定通过。第一行输出 PASS 或 FAIL，第二行起简要说明原因。",
            maxTurns: 1,
            maxTokens: 256,
            permissionMode: .bypassPermissions,
            tools: [],
            mcpServers: nil,
            logLevel: .error
        )

        let judgeAgent = createAgent(options: judgeOptions)

        let toolCallsDesc = toolCalls.isEmpty ? "（无工具调用）" : toolCalls.joined(separator: ", ")
        let prompt = """
        任务：\(task)
        Agent 调用的工具：\(toolCallsDesc)
        Agent 的执行结果：
        \(resultText.prefix(3000))

        请判断以上结果是否正确完成了任务。
        """

        var judgeResponse = ""
        let stream = judgeAgent.stream(prompt)
        for await message in stream {
            switch message {
            case .result(let data):
                judgeResponse = data.text
            default:
                break
            }
        }
        try? await judgeAgent.close()

        let firstLine = judgeResponse.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return firstLine.uppercased().hasPrefix("PASS")
    }
}
