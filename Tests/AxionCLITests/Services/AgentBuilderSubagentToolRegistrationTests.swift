import Testing
import Foundation
import OpenAgentSDK

@testable import AxionCLI
@testable import AxionCore

// MARK: - Story 40.3 ATDD
//
// 本文件覆盖 Story 40.3「Register Agent / Task / Skill Across Agent Paths」的 AC1–AC5：
// 普通 chat/run 路径（`buildToolProfile`）注册 `Agent`/`Task`；direct skill 路径
// （`buildSkillToolProfile`）注册 `Skill`/`Agent`/`Task`；`dryrunExcludedToolNames` 扩展
// 含 `Agent`/`Task`；`--no-skills` 只禁 `Skill` 不禁 `Agent`/`Task`；dry-run 排除三者。
//
// 设计依据（CLAUDE.md 强制约束）：
// - 全部使用 Swift Testing（`import Testing` / `@Suite` / `@Test` / `#expect`），禁止 `import XCTest`
// - 单元测试必须 Mock：**禁止**调用真实 `AgentBuilder.build()` / `buildSkillAgent`（会
//   resolveApiKey + 起 Helper 进程 + 真实 MCP resolve）。本测试直接调用纯函数
//   `AgentBuilder.buildToolProfile(...)` / `AgentBuilder.buildSkillToolProfile(...)`
// - 工具名 **不硬编码**（CLAUDE.md 反模式 #10）：期望的工具名一律从真实工具实例的 `.name`
//   读取（`createAgentTool().name`、`createTaskTool().name`、`createSkillTool(registry:).name`、
//   `createBashTool().name`），或从既有静态常量 `AgentBuilder.excludedToolNames` /
//   `AgentBuilder.dryrunExcludedToolNames` 读取
// - 测试位于 `Tests/AxionCLITests/Services/`，被默认单元测试命令命中
// - 命名遵循 `test_被测单元_场景_预期结果`

@Suite("AgentBuilder subagent tool registration (Story 40.3)")
struct AgentBuilderSubagentToolRegistrationTests {

    // MARK: - Helpers

    /// 临时目录工厂：隔离 `SkillUsageStore` / `StorageManifestStore` 的磁盘读写，
    /// 避免触碰真实 `~/.axion/` 目录。测试结束自动清理。
    private func makeTempBase() throws -> String {
        let base = NSTemporaryDirectory() + "axion-test-subagent-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        return base
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// 构造一个最小、无副作用的 `AxionConfig`（仅 apiKey + 默认 storage）。
    private func makeConfig() -> AxionConfig {
        AxionConfig(apiKey: "sk-test")
    }

    // MARK: - AC1 + AC5: 非 dry-run 路径注册 Agent / Task / Skill

    @Test("AC1/AC5 非 dry-run buildToolProfile 输出含 Agent / Task / Skill")
    func test_buildToolProfile_nonDryrun_includesAgentAndTaskAndSkill() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let memoryDir = base + "/memory"
        let skillsDir = base + "/skills"
        try FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let config = makeConfig()
        let registry = SkillRegistry()

        // 期望工具名从真实实例读取（反模式 #10：禁止硬编码字面量）
        let agentName = createAgentTool().name
        let taskName = createTaskTool().name
        let skillName = createSkillTool(registry: registry).name

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

        #expect(toolNames.contains(agentName), "非 dry-run 应含 Agent 工具")
        #expect(toolNames.contains(taskName), "非 dry-run 应含 Task 工具")
        #expect(toolNames.contains(skillName), "非 dry-run (!noSkills) 应含 Skill 工具")
    }

    // MARK: - AC2: --no-skills 只禁 Skill，不禁 Agent / Task

    @Test("AC2 noSkills=true 省略 Skill 但保留 Agent / Task")
    func test_buildToolProfile_noSkillsTrue_omitsSkillButKeepsAgentTask() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let memoryDir = base + "/memory"
        let skillsDir = base + "/skills"
        try FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let config = makeConfig()
        let registry = SkillRegistry()

        let agentName = createAgentTool().name
        let taskName = createTaskTool().name
        let skillName = createSkillTool(registry: registry).name

        let tools = AgentBuilder.buildToolProfile(
            noSkills: true,
            noMemory: false,
            dryrun: false,
            skillRegistry: registry,
            memoryDir: memoryDir,
            config: config,
            usageStore: nil,
            skillsDir: skillsDir
        )
        let toolNames = Set(tools.map(\.name))

        // --no-skills 只控 Skill 工具与 /skill-name routing，不控 generic subagent 能力
        #expect(!toolNames.contains(skillName), "noSkills=true 应省略 Skill 工具")
        #expect(toolNames.contains(agentName), "noSkills=true 仍应含 Agent 工具")
        #expect(toolNames.contains(taskName), "noSkills=true 仍应含 Task 工具")
    }

    // MARK: - AC3: dry-run 排除 Agent / Task / Skill / Bash 及其它副作用工具

    @Test("AC3 dry-run buildToolProfile 排除 Agent / Task / Skill / Bash 与副作用工具")
    func test_buildToolProfile_dryrun_excludesAgentTaskSkillBash() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let memoryDir = base + "/memory"
        let skillsDir = base + "/skills"
        try FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let config = makeConfig()
        let registry = SkillRegistry()

        // dry-run 排除集引用真实静态常量（含 40.3 新增的 Agent / Task）
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

        // 1. dryrunExcludedToolNames 全部被排除（Bash / Skill / Agent / Task）
        for excluded in AgentBuilder.dryrunExcludedToolNames {
            #expect(!toolNames.contains(excluded), "dry-run 不应含 \(excluded)")
        }

        // 2. Memory / save_skill 等副作用工具（!dryrun 分支注册）也缺席，名称从真实实例读取
        let memoryName = MemoryTool(store: UniversalMemoryStore(memoryDir: memoryDir)).name
        #expect(!toolNames.contains(memoryName), "dry-run 不应含 Memory 工具")

        let usageStore = SkillUsageStore(skillsDir: skillsDir)
        let saveSkillName = createSaveSkillTool(
            skillRegistry: registry,
            usageStore: usageStore,
            skillsDir: skillsDir
        ).name
        #expect(!toolNames.contains(saveSkillName), "dry-run usageStore == nil 不应含 save_skill")

        // 3. excludedToolNames（ToolSearch / AskUser）依旧排除（40.3 未改动此常量）
        for excluded in AgentBuilder.excludedToolNames {
            #expect(!toolNames.contains(excluded), "dry-run 仍应排除 \(excluded)")
        }
    }

    // MARK: - AC4: direct skill 路径（buildSkillToolProfile）注册 Skill / Agent / Task

    @Test("AC4 buildSkillToolProfile 含 Skill / Agent / Task + core 工具，排除 ToolSearch/AskUser，无 MCP")
    func test_buildSkillToolProfile_includesSkillAgentTask() throws {
        let registry = SkillRegistry()

        let agentName = createAgentTool().name
        let taskName = createTaskTool().name
        let skillName = createSkillTool(registry: registry).name

        let tools = AgentBuilder.buildSkillToolProfile(registry: registry)
        let toolNames = Set(tools.map(\.name))

        // 1. 本 story 新增的三个工具（名称从真实实例读取）
        #expect(toolNames.contains(skillName), "direct skill 路径应含 Skill 工具")
        #expect(toolNames.contains(agentName), "direct skill 路径应含 Agent 工具")
        #expect(toolNames.contains(taskName), "direct skill 路径应含 Task 工具")

        // 2. core 工具全部纳入（过滤 excludedToolNames 后）—— 名称源自 getAllBaseTools(tier: .core)
        let expectedCore = getAllBaseTools(tier: .core)
            .map(\.name)
            .filter { !AgentBuilder.excludedToolNames.contains($0) }
        for coreName in expectedCore {
            #expect(toolNames.contains(coreName), "direct skill 路径应含 core 工具 \(coreName)")
        }

        // 3. excludedToolNames（ToolSearch / AskUser）排除
        for excluded in AgentBuilder.excludedToolNames {
            #expect(!toolNames.contains(excluded), "direct skill 路径不应含 \(excluded)")
        }

        // 4. 无 MCP namespaced 工具（direct skill 路径不连 MCP）
        #expect(tools.allSatisfy { !$0.name.hasPrefix("mcp__") }, "direct skill 路径无 MCP 工具")

        // 5. 精确等价：工具池 == core(过滤 excludedToolNames) ∪ {Skill, Agent, Task}
        //    注：WebSearch / WebFetch 属 SDK `.core` tier（ToolRegistry.swift:77），本 story 不改其
        //    归属，故仍出现于 skill 路径；MCP/Web/Search 的继承 policy 归 Story 40.5。
        let expected = Set(expectedCore).union([skillName, agentName, taskName])
        #expect(toolNames == expected, "direct skill 路径工具池应精确等价 core + Skill + Agent + Task")
    }

    // MARK: - AC3 双保险：dryrunExcludedToolNames 集合含 Agent / Task

    @Test("AC3 dryrunExcludedToolNames 常量含 Agent / Task / Skill / Bash")
    func test_buildToolProfile_dryrunExcludedSet_includesAgentTask() {
        // 期望集合从 4 个真实工具实例构造（全不硬编码），与实现常量做精确等价断言
        let expectedExcluded = Set([
            createAgentTool().name,
            createTaskTool().name,
            createSkillTool(registry: SkillRegistry()).name,
            createBashTool().name,
        ])

        #expect(
            AgentBuilder.dryrunExcludedToolNames == expectedExcluded,
            "dryrunExcludedToolNames 应含 Agent / Task / Skill / Bash 四个工具名（40.3 在 40.2 基础上新增 Agent/Task）"
        )
    }
}
