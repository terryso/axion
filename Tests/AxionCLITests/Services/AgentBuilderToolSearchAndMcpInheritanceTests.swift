import Testing
import Foundation
import OpenAgentSDK

@testable import AxionCLI
@testable import AxionCore

// MARK: - Story 40.5 ATDD
//
// 本文件覆盖 Story 40.5「MCP / Web / Search Tool Inheritance Policy」的 AC1–AC6：
// (1) ToolSearch 由硬编码全局排除改为 `AxionConfig.enableToolSearch` 驱动的 config 策略
//     （默认关闭保持 GLM 稳定，零回归）；(2) `enableToolSearch=true` 在普通 chat 与 direct skill
// 两条路径都纳入 ToolSearch（单一策略来源 `effectiveExcludedToolNames(allowingToolSearch:)`）；
// (3) direct skill 路径（`buildSkillAgent`）继承 config 的 MCP servers（was `nil`）；(4) Web 工具
// 在 skill 路径可见性锁定；(5) ToolSearch policy 与 dry-run 正交（read-only，不受 side-effect 过滤）。
//
// 设计依据（CLAUDE.md 强制约束）：
// - 全部使用 Swift Testing（`import Testing` / `@Suite` / `@Test` / `#expect`），禁止导入 XCTest
// - 单元测试必须 Mock：**禁止**调用真实 `AgentBuilder.build()`（会 resolveApiKey + 起 Helper 进程
//   + 真实 MCP resolve）。本测试直接调用纯函数 helper（`buildToolProfile` / `buildSkillToolProfile`
//   / `resolveSkillMcpServers` / `effectiveExcludedToolNames`）—— 不连真实 MCP、不起 Helper、不
//   resolveApiKey
// - 工具名 **不硬编码**（CLAUDE.md 反模式 #10）：期望工具名一律从真实工具实例的 `.name` 读取
//   （`createToolSearchTool().name`、`createAskUserTool().name`、`createWebSearchTool().name`、
//   `createWebFetchTool().name`、`createBashTool().name`），或从既有静态常量 / helper 读取
// - MCP server key：`"my-server"` 是测试**注入**的 user server 名（测试输入，可硬编码在注入值）；
//   `"axion-helper"` 是 `MCPConfigResolver` 的 baseline key（`MCPConfigResolver.swift:23`，断言 key
//   存在时引用该 baseline 字面量来源——非工具名，不触发反模式 #10）
// - 测试位于 `Tests/AxionCLITests/Services/`，被默认单元测试命令 `make test` 命中
// - 命名遵循 `test_被测单元_场景_预期结果`

@Suite("AgentBuilder ToolSearch & MCP inheritance (Story 40.5)")
struct AgentBuilderToolSearchAndMcpInheritanceTests {

    // MARK: - Helpers

    /// 临时目录工厂：隔离 `SkillUsageStore` / `StorageManifestStore` 的磁盘读写，
    /// 避免触碰真实 `~/.axion/` 目录。测试结束自动清理。
    private func makeTempBase() throws -> String {
        let base = NSTemporaryDirectory() + "axion-test-ts405-\(UUID().uuidString)"
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

    /// 在 `base` 下创建 memory + skills 子目录，返回二元组供 `buildToolProfile` 使用。
    @discardableResult
    private func makeMemoryAndSkillsDirs(base: String) throws -> (memoryDir: String, skillsDir: String) {
        let memoryDir = base + "/memory"
        let skillsDir = base + "/skills"
        try FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)
        return (memoryDir, skillsDir)
    }

    // MARK: - AC1: ToolSearch 默认关闭（零回归基准）

    @Test("AC1 默认 config 调 buildToolProfile 排除 ToolSearch（零回归基准）")
    func test_buildToolProfile_defaultConfig_excludesToolSearch() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let (memoryDir, skillsDir) = try makeMemoryAndSkillsDirs(base: base)

        // 默认 config：enableToolSearch nil → toolSearchEnabled == false（保持 GLM 稳定）
        let config = makeConfig()
        #expect(config.toolSearchEnabled == false, "默认 config 的 toolSearchEnabled 应为 false")

        let registry = SkillRegistry()

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

        // ToolSearch 名从真实实例读取（反模式 #10：禁止硬编码字面量）
        let toolSearchName = createToolSearchTool().name
        #expect(!toolNames.contains(toolSearchName), "默认 config 应排除 ToolSearch（与 40.5 前行为一致）")
    }

    // MARK: - AC2: enableToolSearch=true 双路径纳入 ToolSearch（单一策略来源）

    @Test("AC2 chat 路径 enableToolSearch=true 纳入 ToolSearch，仍排除 AskUser")
    func test_buildToolProfile_enableToolSearchTrue_includesToolSearch() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let (memoryDir, skillsDir) = try makeMemoryAndSkillsDirs(base: base)

        let config = AxionConfig(apiKey: "sk-test", enableToolSearch: true)
        #expect(config.toolSearchEnabled == true, "enableToolSearch=true → toolSearchEnabled 应为 true")

        let registry = SkillRegistry()

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

        let toolSearchName = createToolSearchTool().name
        let askUserName = createAskUserTool().name
        #expect(toolNames.contains(toolSearchName), "enableToolSearch=true 时 chat 路径应含 ToolSearch")
        #expect(!toolNames.contains(askUserName), "AskUser 恒排除（不受 enableToolSearch 影响）")
    }

    @Test("AC1+AC2 skill 路径：默认排除 ToolSearch；enableToolSearch=true 纳入；单参默认等价 false")
    func test_buildSkillToolProfile_defaultExcludesToolSearch_enableTrueIncludes() {
        let registry = SkillRegistry()
        let toolSearchName = createToolSearchTool().name
        let askUserName = createAskUserTool().name

        // (a) 默认（enableToolSearch=false）排除 ToolSearch
        let toolsOff = AgentBuilder.buildSkillToolProfile(registry: registry, enableToolSearch: false)
        let namesOff = Set(toolsOff.map(\.name))
        #expect(!namesOff.contains(toolSearchName), "skill 路径默认应排除 ToolSearch")

        // (b) enableToolSearch=true 纳入 ToolSearch，仍排除 AskUser
        let toolsOn = AgentBuilder.buildSkillToolProfile(registry: registry, enableToolSearch: true)
        let namesOn = Set(toolsOn.map(\.name))
        #expect(namesOn.contains(toolSearchName), "skill 路径 enableToolSearch=true 应含 ToolSearch")
        #expect(!namesOn.contains(askUserName), "skill 路径 AskUser 恒排除")

        // (c) 默认参数：buildSkillToolProfile(registry:)（单参）等价于 enableToolSearch:false（零回归）
        let toolsDefault = AgentBuilder.buildSkillToolProfile(registry: registry)
        let namesDefault = Set(toolsDefault.map(\.name))
        #expect(
            namesDefault == namesOff,
            "单参 buildSkillToolProfile(registry:) 应等价于 enableToolSearch:false（默认参数零回归）"
        )
    }

    @Test("AC2 单一策略：effectiveExcludedToolNames 是两路径共享的真相源")
    func test_effectiveExcludedToolNames_singlePolicySource() {
        // AskUser 名从真实实例读取构造期望集（反模式 #10）
        let askUserName = createAskUserTool().name

        // allowingToolSearch=true → 只排除 AskUser（ToolSearch 保留）
        #expect(
            AgentBuilder.effectiveExcludedToolNames(allowingToolSearch: true) == Set([askUserName]),
            "allowingToolSearch=true 应仅排除 AskUser（ToolSearch 不在排除集）"
        )

        // allowingToolSearch=false → 等于既有 excludedToolNames 常量（ToolSearch-off 默认集）
        #expect(
            AgentBuilder.effectiveExcludedToolNames(allowingToolSearch: false) == AgentBuilder.excludedToolNames,
            "allowingToolSearch=false 应等于 excludedToolNames 常量（恒等：两路径默认行为同源）"
        )
    }

    // MARK: - AC4: Web 工具在 skill 路径可见性锁定（不受 ToolSearch 策略影响）

    @Test("AC4 buildSkillToolProfile 含 WebSearch/WebFetch，不受 ToolSearch 策略影响")
    func test_buildSkillToolProfile_includesWebTools_regardlessOfToolSearchPolicy() {
        let registry = SkillRegistry()
        let webSearchName = createWebSearchTool().name
        let webFetchName = createWebFetchTool().name

        // enableToolSearch=false：Web 工具应在池
        let namesOff = Set(AgentBuilder.buildSkillToolProfile(registry: registry, enableToolSearch: false).map(\.name))
        #expect(namesOff.contains(webSearchName), "skill 路径应含 WebSearch（.core tier）")
        #expect(namesOff.contains(webFetchName), "skill 路径应含 WebFetch（.core tier）")

        // enableToolSearch=true：Web 工具仍应在池（ToolSearch 策略不波及 Web 工具）
        let namesOn = Set(AgentBuilder.buildSkillToolProfile(registry: registry, enableToolSearch: true).map(\.name))
        #expect(namesOn.contains(webSearchName), "ToolSearch 策略不影响 WebSearch 可见性")
        #expect(namesOn.contains(webFetchName), "ToolSearch 策略不影响 WebFetch 可见性")
    }

    // MARK: - AC3: direct skill 路径继承 config 的 MCP servers（不再 nil）

    @Test("AC3 resolveSkillMcpServers 继承 user servers + axion-helper baseline")
    func test_resolveSkillMcpServers_inheritsUserServersAndAxionHelperBaseline() {
        // 注入 user server：my-server（stdio /usr/bin/true）—— 名为测试输入
        let config = AxionConfig(
            apiKey: "sk-test",
            mcpServers: ["my-server": .stdio(command: "/usr/bin/true", args: nil, env: nil)]
        )

        // 注入 helperPath 做全确定性断言（沿用 40.4 makeDiscoveredSkillRegistry 的可注入 seam 模式）
        let servers = AgentBuilder.resolveSkillMcpServers(from: config, helperPath: "/usr/bin/true")

        // user server key 存在（注入名）
        #expect(servers["my-server"] != nil, "resolveSkillMcpServers 应继承 config 的 user server my-server")

        // axion-helper baseline key 存在（MCPConfigResolver.swift:23 baseline；不断言 command 字面量路径——非确定性）
        #expect(
            servers["axion-helper"] != nil,
            "resolveSkillMcpServers 应恒含 axion-helper baseline key（与 build() 同源）"
        )
    }

    // MARK: - AC5: ToolSearch policy 与 dry-run 解耦

    @Test("AC5 dry-run + enableToolSearch=true 保留 ToolSearch（read-only），排除 Bash（side-effect）")
    func test_buildToolProfile_dryrunWithToolSearchEnabled_keepsToolSearch_dropsBash() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let (memoryDir, skillsDir) = try makeMemoryAndSkillsDirs(base: base)

        let config = AxionConfig(apiKey: "sk-test", enableToolSearch: true)

        let tools = AgentBuilder.buildToolProfile(
            noSkills: false,
            noMemory: false,
            dryrun: true,
            skillRegistry: SkillRegistry(),
            memoryDir: memoryDir,
            config: config,
            usageStore: nil,
            skillsDir: skillsDir
        )
        let toolNames = Set(tools.map(\.name))

        let toolSearchName = createToolSearchTool().name
        let bashName = createBashTool().name

        // ToolSearch 是 read-only 发现工具，不在 dryrunExcludedToolNames → dry-run 仍保留（受 config 策略支配）
        #expect(toolNames.contains(toolSearchName), "dry-run + enableToolSearch=true 应保留 ToolSearch（read-only，与 side-effect 过滤正交）")
        // Bash 是 side-effect 工具，在 dryrunExcludedToolNames → dry-run 排除
        #expect(!toolNames.contains(bashName), "dry-run 应排除 Bash（dryrunExcludedToolNames 生效）")
    }
}
