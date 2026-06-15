import Testing
import Foundation
import OpenAgentSDK

@testable import AxionCLI
@testable import AxionCore

// MARK: - Story 40.4 ATDD
//
// 本文件覆盖 Story 40.4「Direct Skill Uses Discovered Skill Registry」的 AC1–AC5：
// `AgentBuilder.makeDiscoveredSkillRegistry(ensuring:discoveryDirectories:)` 把 direct skill 路径
// （`buildSkillAgent`）的 single-skill registry 换成完整 discovered registry（built-in +
// filesystem discovery + ensure 当前 skill），使 pipeline 父 skill 的 Task 子代理能解析
// /bmad-create-story 等同级 skill（CAP-3）。
//
// 设计依据（CLAUDE.md 强制约束）：
// - 全部使用 Swift Testing（`import Testing` / `@Suite` / `@Test` / `#expect`），禁止 `import XCTest`
// - 单元测试必须 Mock：**禁止**调用真实 `AgentBuilder.build()`（会 resolveApiKey + 起 Helper 进程
//   + 真实 MCP resolve）。本测试直接调用纯函数 `AgentBuilder.makeDiscoveredSkillRegistry(...)`
//   （FS discovery 限于注入的临时 fixture 目录，受控、无副作用）
// - 仅 AC2 接线断言（4.2.6）调用真实 `buildSkillAgent`，用 `AxionConfig(apiKey: "sk-test")` 绕过
//   `resolveApiKey`、`mcpServers: nil` 不连 MCP（Story Dev Notes 明确授权该构造）
// - skill 名 **不硬编码**（CLAUDE.md 反模式 #10）：fixture skill 名是测试输入（写 SKILL.md），
//   断言时从 `registry.find(name)?.name` 读回；built-in skill 名从 `AxionBuiltInSkills` 真实
//   读取（注册到参考 registry 取 `allSkills.map(\.name)`），不写字面量 "screenshot-analyze"
// - 测试位于 `Tests/AxionCLITests/Services/`，被 `make test` 命中
// - 命名遵循 `test_被测单元_场景_预期结果`

@Suite("AgentBuilder discovered skill registry (Story 40.4)")
struct AgentBuilderDiscoveredSkillRegistryTests {

    // MARK: - Fixture Helpers

    /// 临时目录工厂：隔离 filesystem discovery，避免触碰真实 `~/.axion/`、`~/.claude/skills` 等目录。
    private func makeTempBase() throws -> String {
        let base = NSTemporaryDirectory() + "axion-test-registry404-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        return base
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// 在 `base` 下写入一个最小 SKILL.md（`SkillLoader` 可解析的 frontmatter + body）。
    /// - Parameters:
    ///   - base: 临时 fixture 根目录。
    ///   - name: skill 目录名（兼作 frontmatter `name`）。
    ///   - description: frontmatter description（默认占位）。
    ///   - aliases: frontmatter aliases（空格/逗号分隔，`SkillLoader.extractAliases` 格式）。`nil` 表示不写该字段。
    ///   - body: SKILL.md 正文（promptTemplate）。
    private func writeFixtureSkill(
        base: String,
        name: String,
        description: String = "fixture skill",
        aliases: String? = nil,
        body: String = "fixture body"
    ) throws {
        let skillDir = base + "/" + name
        try FileManager.default.createDirectory(atPath: skillDir, withIntermediateDirectories: true)
        var content = "---\nname: \(name)\ndescription: \(description)\n"
        if let aliases { content += "aliases: \(aliases)\n" }
        content += "---\n\(body)\n"
        try content.write(toFile: skillDir + "/SKILL.md", atomically: true, encoding: .utf8)
    }

    // MARK: - AC1: discovered registry 含同级 skill（pipeline-test / step-one / step-two）

    @Test("AC1 makeDiscoveredSkillRegistry 发现 fixture 目录中的同级 skill")
    func test_makeDiscoveredSkillRegistry_discoversSiblingSkills() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }

        // fixture 输入：三个同级 skill（pipeline-test / step-one / step-two）
        try writeFixtureSkill(base: base, name: "pipeline-test")
        try writeFixtureSkill(base: base, name: "step-one")
        try writeFixtureSkill(base: base, name: "step-two")

        // ensure 的 pipeline-test 用 programmatic 实例（同名，验证幂等替换语义）
        let ensuredPipeline = Skill(
            name: "pipeline-test",
            description: "orchestrator programmatic instance",
            promptTemplate: "orchestrate"
        )

        let registry = AgentBuilder.makeDiscoveredSkillRegistry(
            ensuring: ensuredPipeline,
            discoveryDirectories: [base]
        )

        // 三个同级 skill 全部命中（名从 registry.find(name)?.name 读回）
        let stepOne = registry.find("step-one")
        let stepTwo = registry.find("step-two")
        let pipeline = registry.find("pipeline-test")
        #expect(stepOne != nil, "应发现同级 skill step-one")
        #expect(stepTwo != nil, "应发现同级 skill step-two")
        #expect(pipeline != nil, "应发现/ensure pipeline-test")
        #expect(stepOne?.name == "step-one", "registry 应原样保留 step-one 名")
        #expect(stepTwo?.name == "step-two", "registry 应原样保留 step-two 名")
        #expect(pipeline?.name == "pipeline-test", "registry 应原样保留 pipeline-test 名")
    }

    // MARK: - AC2 ensure 语义：programmatic skill 不在 discovery 目录仍命中

    @Test("AC2 makeDiscoveredSkillRegistry ensure 当前 skill 即便不在 discovery 目录")
    func test_makeDiscoveredSkillRegistry_ensuresCurrentSkillEvenIfNotOnDisk() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        // fixture 目录仅含无关 skill —— orchestrator-only 不在磁盘
        try writeFixtureSkill(base: base, name: "unrelated-on-disk")

        let orchestrator = Skill(
            name: "orchestrator-only",
            description: "programmatic, not on disk",
            promptTemplate: "orchestrate"
        )

        let registry = AgentBuilder.makeDiscoveredSkillRegistry(
            ensuring: orchestrator,
            discoveryDirectories: [base]
        )

        #expect(
            registry.find("orchestrator-only") != nil,
            "ensure 的 programmatic skill 即便不在 discovery 目录也应命中（register(skill) 幂等注册）"
        )
    }

    // MARK: - AC3: alias 解析（frontmatter aliases）

    @Test("AC3 makeDiscoveredSkillRegistry 解析 frontmatter alias")
    func test_makeDiscoveredSkillRegistry_resolvesAliases() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }

        // fixture skill 声明 alias "sa"（SkillLoader.extractAliases 格式：空格/逗号分隔）
        try writeFixtureSkill(base: base, name: "aliased-skill", aliases: "sa")

        let registry = AgentBuilder.makeDiscoveredSkillRegistry(
            ensuring: Skill(name: "pipeline-test", promptTemplate: "p"),
            discoveryDirectories: [base]
        )

        // find(alias) 与 find(name) 命中同一 skill（SkillRegistry.find name+alias 双路查找）
        let viaAlias = registry.find("sa")
        let viaName = registry.find("aliased-skill")
        #expect(viaAlias != nil, "find(alias) 应命中")
        #expect(viaName != nil, "find(name) 应命中")
        #expect(viaAlias?.name == "aliased-skill", "alias 应解析到同一 skill")
    }

    // MARK: - AC4: 缺失 skill 返回 nil（registry 层确定性）

    @Test("AC4 makeDiscoveredSkillRegistry 缺失 skill 返回 nil")
    func test_makeDiscoveredSkillRegistry_missingSkillReturnsNil() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        try writeFixtureSkill(base: base, name: "step-one")

        let registry = AgentBuilder.makeDiscoveredSkillRegistry(
            ensuring: Skill(name: "pipeline-test", promptTemplate: "p"),
            discoveryDirectories: [base]
        )

        #expect(
            registry.find("missing-skill") == nil,
            "registry 应确定性返回 nil —— SDK SkillTool 据此返回 Error: Skill \"missing-skill\" not found or not registered（保留 skill 名）；args 回显属 SDK follow-up，见 Dev Notes"
        )
    }

    // MARK: - AC1 built-in 一致性：registry 含 AxionBuiltInSkills built-in（名从真实实例读取）

    @Test("AC1 makeDiscoveredSkillRegistry 含 AxionBuiltInSkills built-in（名从真实实例读取）")
    func test_makeDiscoveredSkillRegistry_includesBuiltInSkills() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        // 空目录即可 —— built-in 与 discovery 目录无关

        // built-in 名单一来源：注册到独立参考 registry 取 allSkills.map(\.name)（不硬编码）
        let referenceBuiltIns = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: referenceBuiltIns)
        let builtInNames = referenceBuiltIns.allSkills.map(\.name)
        #expect(!builtInNames.isEmpty, "AxionBuiltInSkills 应注册至少一个 built-in")

        let registry = AgentBuilder.makeDiscoveredSkillRegistry(
            ensuring: Skill(name: "pipeline-test", promptTemplate: "p"),
            discoveryDirectories: [base]
        )

        // discovered registry 至少含一个 built-in（名从真实实例读取，不硬编码 "screenshot-analyze"）
        let hitBuiltIn = builtInNames.contains { registry.find($0) != nil }
        #expect(hitBuiltIn, "discovered registry 应含至少一个 AxionBuiltInSkills built-in（与 build() 对齐）")
    }

    // MARK: - AC2 接线：buildSkillAgent 构造的 agent 使用 discovered registry

    @Test("AC2 buildSkillAgent 接线：discovered registry 非空且 ensure 当前 skill")
    func test_buildSkillAgent_skillRegistryUsesDiscoveredRegistry() async throws {
        // `buildSkillAgent` 返回 (agent, runCompleteBox)，SDK Agent 不公开 agentOptions.skillRegistry，
        // 故无法直接读取 agent 的 registry。其内部唯一构造 registry 的路径是
        // `makeDiscoveredSkillRegistry(ensuring: skill)`（默认 discoveryDirectories = 全局配置，Task 2.1）。
        // 本测试：(1) 真实 buildSkillAgent 全路径可成功构造 agent（apiKey stub 绕过 resolveApiKey、
        //   mcpServers: nil 不连 MCP——Story Dev Notes 授权），证明替换 registry 来源后接线无异常；
        // (2) 复现其内部构造，断言 registry 非空（built-in 恒存在，确定性）+ ensure 的 skill 命中（确定性）。
        let ensured = Skill(name: "wiring-probe", description: "probe", promptTemplate: "probe")

        // (1) 真实 buildSkillAgent 全路径构造（不抛错 = 走通 makeDiscoveredSkillRegistry）
        let (agent, _) = try await AgentBuilder.buildSkillAgent(
            config: AxionConfig(apiKey: "sk-test"),
            skill: ensured,
            maxSteps: nil,
            verbose: false,
            eventBus: nil
        )
        try? await agent.close()

        // (2) buildSkillAgent 内部构造 registry 的等价调用（默认目录）—— 非空 + ensure skill
        let registry = AgentBuilder.makeDiscoveredSkillRegistry(ensuring: ensured)
        #expect(
            registry.allSkills.isEmpty == false,
            "buildSkillAgent 的 registry 应非空（AxionBuiltInSkills 恒注册，确定性）"
        )
        #expect(
            registry.find(ensured.name) != nil,
            "buildSkillAgent 的 registry 应 ensure 当前 skill（确定性）"
        )
    }
}
