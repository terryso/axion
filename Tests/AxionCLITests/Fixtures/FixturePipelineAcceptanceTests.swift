import Testing
import Foundation
import OpenAgentSDK

@testable import AxionCLI
@testable import AxionCore

// MARK: - Story 40.9 Fixture-Based Pipeline Acceptance
//
// 本套件是 Story 40.9「Fixture-Based Pipeline Acceptance」的验收测试。它**不**新增任何
// production 能力，而是用一组确定性 fixture（`PipelineFixtureSkills`）把 Story 40.3–40.8
// 已接好的各层能力（Agent/Task/Skill 注册、discovered registry、dry-run/MCP 策略、
// permission/diagnostics、slash skill guidance、child task 输出渲染）**串成一条 pipeline 链**，
// 在单元层做端到端验收。
//
// 关键约束（CLAUDE.md 强制）：
// - 全部使用 Swift Testing（`import Testing` / `@Suite` / `@Test` / `#expect`），**禁止导入 XCTest**
// - 单元测试必须 Mock：**禁止**真实 `AgentBuilder.build()` / `buildSkillAgent()`（会 resolveApiKey +
//   起 Helper + 真实 MCP resolve）。本套件只调用纯函数 helper（`buildToolProfile` /
//   `buildSkillToolProfile` / `diagnoseToolAvailability`）+ 40.8 输出格式化 helper
//   （`extractSlashSkillCommand` / `formatCompleted`）+ fixture `SkillRegistry`
// - 工具名 **不硬编码字面量做期望**（反模式 #10）：`Skill`/`Agent`/`Task` 工具名一律从真实工具实例
//   `.name` 读取（`createSkillTool(registry:).name` / `createAgentTool().name` / `createTaskTool().name`）
// - 整条链 **不调真实 LLM / MCP / Helper 进程**（AC4）：只走 registry 解析 + profile/诊断纯函数 +
//   字符串格式化。`AxionConfig(apiKey: "sk-test")` 仅作纯模型构造
// - fixture 复用 40.2–40.8 既有 helper，**不**重复实现 production 逻辑（AC5）
// - 测试命名遵循 `test_被测单元_场景_预期结果`

@Suite("Fixture-Based Pipeline Acceptance (Story 40.9)")
struct FixturePipelineAcceptanceTests {

    // MARK: - Helpers

    /// 临时目录工厂：隔离 `buildToolProfile` 的 Storage 工具分支磁盘读写（不触碰真实 `~/.axion/`）。
    private func makeTempBase() throws -> String {
        let base = NSTemporaryDirectory() + "axion-test-fixture-pipeline-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        return base
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// 构造一个最小、无副作用的 `AxionConfig`（仅 apiKey + 默认 storage），供 `buildToolProfile` 使用。
    /// `apiKey: "sk-test"` 是纯模型字段——本套件从不调用 `resolveApiKey`，故无网络调用（AC4）。
    private func makeConfig() -> AxionConfig {
        AxionConfig(apiKey: "sk-test")
    }

    // MARK: - AC1: fixture skills resolve in registry; promptTemplate orders step-one before step-two

    @Test("AC1 fixture skills（pipeline-test/step-one/step-two）可在测试 registry 中解析")
    func test_fixtureSkills_resolveInRegistry() {
        let registry = PipelineFixtureSkills.makeSuccessRegistry()

        // registry.find 能分别解析三个 fixture skill（40.4 discovered registry 的等价最小形态）
        #expect(registry.find("pipeline-test") != nil, "pipeline-test 应可解析")
        #expect(registry.find("step-one") != nil, "step-one 应可解析")
        #expect(registry.find("step-two") != nil, "step-two 应可解析")

        // 解析出的 skill 名正确（Skill.name 是公开字段，可直接断言）
        #expect(registry.find("pipeline-test")?.name == "pipeline-test")
        #expect(registry.find("step-one")?.name == "step-one")
        #expect(registry.find("step-two")?.name == "step-two")
    }

    @Test("AC1 pipeline-test 的 promptTemplate 按文本顺序先引用 step-one 再引用 step-two")
    func test_pipelineTest_promptTemplate_ordersStepOneBeforeStepTwo() {
        let registry = PipelineFixtureSkills.makeSuccessRegistry()

        // resolvePipelineSequence 用纯字符串扫描（不调 LLM）按文本顺序提取被引用 step 名
        let sequence = PipelineFixtureSkills.resolvePipelineSequence(
            registry: registry,
            pipelineSkillName: "pipeline-test"
        )

        // AC1：fixture 断言解析顺序——先 step-one 再 step-two
        #expect(sequence == ["step-one", "step-two"], "引用顺序应为 [step-one, step-two]")
        // 反向断言：step-two 不得出现在 step-one 之前
        if let oneIndex = sequence.firstIndex(of: "step-one"),
           let twoIndex = sequence.firstIndex(of: "step-two") {
            #expect(oneIndex < twoIndex, "step-one 必须在 step-two 之前")
        }
    }

    // MARK: - AC2: missing skill 失败路径——step-missing 被标记 unmatched + 失败渲染含名称 + 可重试命令

    @Test("AC2 missing skill step-missing 在 broken registry 下被标记 unmatched（registry.find 返回 nil）")
    func test_missingSkill_stepMissing_diagnosedUnmatched() {
        let registry = PipelineFixtureSkills.makeBrokenRegistry()

        // AC2 literal：broken registry 故意不注册 step-missing → registry.find 返回 nil
        #expect(registry.find("step-missing") == nil, "step-missing 未注册 → registry.find 应返回 nil")

        // 「等价 profile 诊断 helper」：unmatchedSteps 把 resolvePipelineSequence 结果逐个交给
        // registry.find，凡返回 nil 者即 unmatched step
        let unmatched = PipelineFixtureSkills.unmatchedSteps(
            registry: registry,
            pipelineSkillName: "pipeline-test-broken"
        )
        #expect(unmatched == ["step-missing"], "step-missing 应被标记为 unmatched step")

        // 复用 40.3 buildSkillToolProfile 拿可用工具名集合（复用，不重写——AC5）
        let availableToolNames = AgentBuilder.buildSkillToolProfile(registry: registry)
            .map { $0.name.lowercased() }

        // 复用 40.6 diagnoseToolAvailability（"或等价诊断 helper"）：构造一个声明 step-missing 为
        // allowed-tool 的 fixture skill，诊断应把它标记为不可用。`.parse("step-missing")` →
        // status `.unknown` → 落入 unsupportedDeclarations（tool 级「不可用」是 skill 级 unmatched
        // 的类比；二者都回答「声明了但不可用」）。
        let skillDeclaringMissing = OpenAgentSDK.Skill(
            name: "step-missing-as-declared-tool",
            toolDeclarations: [.parse("step-missing")],
            promptTemplate: ""
        )
        let diag = AgentBuilder.diagnoseToolAvailability(
            skill: skillDeclaringMissing,
            availableToolNames: availableToolNames,
            enableToolSearch: false
        )
        let unavailableDeclarations = diag.unmatchedDeclarations + diag.unsupportedDeclarations
        #expect(
            unavailableDeclarations.contains { $0.rawName == "step-missing" },
            "step-missing 应被 40.6 diagnoseToolAvailability 标记为不可用（unmatched ∪ unsupported）"
        )
        #expect(diag.affectsAvailability, "影响可用性的诊断应使 affectsAvailability 为 true")
    }

    @Test("AC2 missing skill 失败渲染保留 step-missing 名称 + 可重试命令（复用 40.8 helper）")
    func test_missingSkill_failureRenderedWithNameAndRetryableCommand() {
        // broken pipeline 第二步的子代理 prompt（引用未注册的 step-missing）
        let missingStepPrompt = "Execute /step-missing demo"

        // 复用 40.8 extractSlashSkillCommand：保留 missing-skill 名称 + 产出可重试 slash 命令
        let command = ToolCategoryFormatter.extractSlashSkillCommand(from: missingStepPrompt)
        #expect(command == "/step-missing demo", "extractSlashSkillCommand 应保留 step-missing 名称 + 参数")
        #expect(command?.contains("step-missing") ?? false, "可重试命令应保留 step-missing 名称")

        // 复用 40.8 formatCompleted：subagent（Task 工具）失败渲染应含名称 + retry 命令。
        // toolName 从真实实例读（createTaskTool().name，反模式 #10），isTTY:false 保证确定性输出。
        let taskName = createTaskTool().name
        let rendered = ToolCategoryFormatter.formatCompleted(
            toolName: taskName,
            content: #"Skill "step-missing" not found or not registered"#,
            isError: true,
            durationMs: nil,
            toolInput: #"{"prompt":"Execute /step-missing demo","description":"Run missing step"}"#,
            isTTY: false
        )
        #expect(rendered.contains("step-missing"), "失败渲染应保留 step-missing 名称")
        #expect(rendered.contains("retry:"), "失败渲染应含 retry: 前缀")
        #expect(rendered.contains("/step-missing"), "失败渲染应含可重试命令 /step-missing")
    }

    // MARK: - AC3: dry-run 过滤——dry-run profile 不含 Skill/Agent/Task；非 dry-run 含三者

    @Test("AC3 dry-run profile 排除 Skill/Agent/Task（沿用 40.3/40.5 dry-run 过滤）")
    func test_dryRunProfile_excludesSkillAgentTask() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let memoryDir = base + "/memory"
        let skillsDir = base + "/skills"
        try FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let config = makeConfig()
        let registry = PipelineFixtureSkills.makeSuccessRegistry()

        // 工具名从真实实例读（反模式 #10）
        let skillName = createSkillTool(registry: registry).name
        let agentName = createAgentTool().name
        let taskName = createTaskTool().name

        // 复用 40.2/40.3 buildToolProfile（dryrun: true）
        let tools = AgentBuilder.buildToolProfile(
            noSkills: false,
            noMemory: false,
            dryrun: true,
            skillRegistry: registry,
            memoryDir: memoryDir,
            config: config,
            usageStore: nil,
            skillsDir: skillsDir
        )
        let toolNames = Set(tools.map(\.name))

        // AC3：dry-run 集合不含 Skill/Agent/Task
        #expect(!toolNames.contains(skillName), "dry-run 不应含 \(skillName) 工具")
        #expect(!toolNames.contains(agentName), "dry-run 不应含 \(agentName) 工具")
        #expect(!toolNames.contains(taskName), "dry-run 不应含 \(taskName) 工具")
    }

    @Test("AC3 非 dry-run profile 含 Skill/Agent/Task（工具名从真实实例读）")
    func test_nonDryRunProfile_includesSkillAgentTask() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let memoryDir = base + "/memory"
        let skillsDir = base + "/skills"
        try FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let config = makeConfig()
        let registry = PipelineFixtureSkills.makeSuccessRegistry()

        // 工具名从真实实例读（反模式 #10）：确认 fixture 与 40.3 注册一致
        let skillName = createSkillTool(registry: registry).name
        let agentName = createAgentTool().name
        let taskName = createTaskTool().name

        // 复用 40.2/40.3 buildToolProfile（dryrun: false）
        let tools = AgentBuilder.buildToolProfile(
            noSkills: false,
            noMemory: false,
            dryrun: false,
            skillRegistry: registry,
            memoryDir: memoryDir,
            config: config,
            usageStore: nil,
            skillsDir: skillsDir
        )
        let toolNames = Set(tools.map(\.name))

        // AC3：非 dry-run 集合含 Skill/Agent/Task
        #expect(toolNames.contains(skillName), "非 dry-run 应含 \(skillName) 工具")
        #expect(toolNames.contains(agentName), "非 dry-run 应含 \(agentName) 工具")
        #expect(toolNames.contains(taskName), "非 dry-run 应含 \(taskName) 工具")

        // AC5 旁证：buildSkillToolProfile（40.3 直达 skill 路径）同样含三者——复用，不重写
        let skillPathTools = AgentBuilder.buildSkillToolProfile(registry: registry)
        let skillPathNames = Set(skillPathTools.map(\.name))
        #expect(skillPathNames.contains(skillName))
        #expect(skillPathNames.contains(agentName))
        #expect(skillPathNames.contains(taskName))
    }

    // MARK: - AC4 + AC5: 无网络依赖 + fixture 复用既有 helper（无重复实现）

    @Test("AC4+AC5 整条 fixture 链不发网络请求——只调纯函数/helper + 字符串断言")
    func test_noNetworkDependency_onlyPureHelpersAndStringAssertions() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let memoryDir = base + "/memory"
        let skillsDir = base + "/skills"
        try FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let config = makeConfig()  // apiKey: "sk-test" 纯模型字段，本测试从不调用 resolveApiKey
        let successRegistry = PipelineFixtureSkills.makeSuccessRegistry()
        let brokenRegistry = PipelineFixtureSkills.makeBrokenRegistry()

        // AC4：整条 fixture 链只调纯函数 helper——下列每一步都确定性、无网络、无 Helper 进程、无 MCP。
        // (1) registry 解析（SkillRegistry.find / register——内存表）
        let sequence = PipelineFixtureSkills.resolvePipelineSequence(
            registry: successRegistry,
            pipelineSkillName: "pipeline-test"
        )
        #expect(sequence == ["step-one", "step-two"])

        // (2) buildToolProfile（40.2 纯函数——无 API key 解析、无 MCP 连接、无 Helper 派生）
        let nonDryRun = AgentBuilder.buildToolProfile(
            noSkills: false,
            noMemory: false,
            dryrun: false,
            skillRegistry: successRegistry,
            memoryDir: memoryDir,
            config: config,
            usageStore: nil,
            skillsDir: skillsDir
        )
        #expect(nonDryRun.contains { $0.name == createTaskTool().name })

        // (3) diagnoseToolAvailability（40.6 纯函数——无网络）
        let availableToolNames = nonDryRun.map { $0.name.lowercased() }
        let diag = AgentBuilder.diagnoseToolAvailability(
            skill: PipelineFixtureSkills.stepOne(),
            availableToolNames: availableToolNames,
            enableToolSearch: false
        )
        // step-one 无 allowed-tools 声明 → 空 diagnostics（40.6 AC2 反向）
        #expect(diag.isEmpty)

        // (4) 输出格式化（40.8 纯函数——纯字符串处理）
        let command = ToolCategoryFormatter.extractSlashSkillCommand(from: "Execute /step-one demo")
        #expect(command == "/step-one demo")

        // 确定性：同一 registry + 同一 pipeline skill，两次解析结果一致（无网络 → 可重现）
        let sequenceAgain = PipelineFixtureSkills.resolvePipelineSequence(
            registry: successRegistry,
            pipelineSkillName: "pipeline-test"
        )
        #expect(sequence == sequenceAgain, "无网络 → 同输入应产出确定、可重现的结果")

        // broken registry 的 missing-skill 诊断同样不发网络（只 registry.find + 纯函数）
        #expect(
            PipelineFixtureSkills.unmatchedSteps(registry: brokenRegistry, pipelineSkillName: "pipeline-test-broken")
                == ["step-missing"]
        )
    }
}
