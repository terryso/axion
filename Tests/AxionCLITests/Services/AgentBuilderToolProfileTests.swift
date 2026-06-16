import Testing
import Foundation
import OpenAgentSDK

@testable import AxionCLI
@testable import AxionCore

// MARK: - Story 40.2 ATDD (RED phase)
//
// 本文件是 Story 40.2「Shared Tool Profile Helper With Behavior Parity」的 RED 阶段
// ATDD 脚手架。被测对象是尚不存在的 `AgentBuilder.buildToolProfile(...)` 纯函数 ——
// 因此本文件在 Story 40.2 dev 实现该 helper 之前 **无法编译**（确定性 RED gate）。
// 当 Step 3（dev-story）把 `AgentBuilder.swift` 第 140–189 / 206–212 行的工具组装
// 逻辑提取为 `buildToolProfile(...)` 后，本套件转 GREEN。
//
// 设计依据（CLAUDE.md 强制约束）：
// - 全部使用 Swift Testing（`import Testing` / `@Suite` / `@Test` / `#expect`），禁止导入 XCTest
// - 单元测试必须 Mock：**禁止**调用真实 `AgentBuilder.build()`（会 resolveApiKey + 起 Helper
//   进程 + 真实 MCP resolve）。本测试直接调用纯函数 `AgentBuilder.buildToolProfile(...)`
// - 工具名 **不硬编码**（CLAUDE.md 反模式 #10）：期望的工具名一律从真实工具实例的 `.name`
//   读取（如 `MemoryTool(store: ...).name`、`StorageScanTool(...).name`、
//   `createSkillTool(registry:).name`、`createSaveSkillTool(...).name`），或从既有
//   静态常量 `AgentBuilder.excludedToolNames` / 字面量 `dryrunExcludedToolNames` 读取
// - 测试位于 `Tests/AxionCLITests/Services/`，被默认单元测试命令 `--filter "AxionCLITests"` 命中
// - 命名遵循 `test_被测单元_场景_预期结果`

@Suite("AgentBuilder.buildToolProfile (Story 40.2)")
struct AgentBuilderToolProfileTests {

    // MARK: - Helpers

    /// 临时目录工厂：隔离 `SkillUsageStore` / `StorageManifestStore` 的磁盘读写，
    /// 避免触碰真实 `~/.axion/` 目录。测试结束自动清理。
    private func makeTempBase() throws -> String {
        let base = NSTemporaryDirectory() + "axion-test-toolprofile-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        return base
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// 构造一个最小、无副作用的 `AxionConfig`（仅 apiKey + 默认 storage），
    /// 供 helper 的 Storage 工具分支使用。
    private func makeConfig() -> AxionConfig {
        AxionConfig(apiKey: "sk-test")
    }

    /// 从真实工具实例读取工具名，供断言「期望工具名」用（避免硬编码字符串）。
    /// 这些构造本身无副作用（工具的副作用只在 `perform()` 时发生）。
    /// 注意：`createSaveSkillTool` 的入参 `usageStore` 是**非可选** `SkillUsageStore`
    /// （SDK SaveSkillTool.swift:27），且 `save_skill` 工具只在 `usageStore != nil`
    /// 且非 dry-run 时注册。故 saveSkill 名单独按需读取，其它工具名在此统一构造。
    private func expectedNames(
        memoryDir: String,
        skillRegistry: SkillRegistry,
        config: AxionConfig
    ) -> (
        skill: String,
        memory: String,
        storageScan: String,
        proposeStoragePlan: String,
        executeStoragePlan: String,
        undoStorageOp: String,
        scanAppUninstall: String,
        executeAppUninstall: String
    ) {
        let universalStore = UniversalMemoryStore(memoryDir: memoryDir)
        let manifestStore = StorageManifestStore(storageOpsDir: config.storage.storageOpsDir)
        let appPlanBuilder = AppUninstallPlanBuilder(
            supportDataScanner: SupportDataScanService(),
            appDiscoverer: AppDiscoveryService(),
            hintReader: ExternalHintReader()
        )
        return (
            skill: createSkillTool(registry: skillRegistry).name,
            memory: MemoryTool(store: universalStore).name,
            storageScan: StorageScanTool(scanner: StorageScanService(), config: config.storage).name,
            proposeStoragePlan: ProposeStoragePlanTool(config: config.storage).name,
            executeStoragePlan: ExecuteStoragePlanTool(
                executor: StorageExecutor(manifestStore: manifestStore),
                config: config.storage
            ).name,
            undoStorageOp: UndoStorageOpTool(
                undoer: StorageUndoService(manifestStore: manifestStore),
                config: config.storage
            ).name,
            scanAppUninstall: ScanAppUninstallTool(planBuilder: appPlanBuilder).name,
            executeAppUninstall: ExecuteAppUninstallTool(
                executor: AppUninstallExecutor(
                    manifestStore: manifestStore,
                    appQuitter: AppQuitter()
                ),
                config: config.storage
            ).name
        )
    }

    /// 单独读取 `save_skill` 工具名（只在 `usageStore != nil` 时有意义）。
    /// 入参为非可选 `SkillUsageStore`，对齐 SDK 签名。
    private func saveSkillName(
        skillRegistry: SkillRegistry,
        usageStore: SkillUsageStore,
        skillsDir: String
    ) -> String {
        createSaveSkillTool(
            skillRegistry: skillRegistry,
            usageStore: usageStore,
            skillsDir: skillsDir
        ).name
    }

    // MARK: - AC1 + AC5: 非 dry-run 路径工具名 parity

    @Test("AC1/AC5 非 dry-run helper 输出含 Skill/Memory/Storage 6 工具（usageStore != nil 时含 save_skill）")
    func test_buildToolProfile_nonDryrun_includesSkillMemoryStorageAndSaveSkill() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let memoryDir = base + "/memory"
        let skillsDir = base + "/skills"
        try FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let config = makeConfig()
        let registry = SkillRegistry()
        let usageStore = SkillUsageStore(skillsDir: skillsDir)

        let names = expectedNames(memoryDir: memoryDir, skillRegistry: registry, config: config)
        let saveSkill = saveSkillName(skillRegistry: registry, usageStore: usageStore, skillsDir: skillsDir)

        let tools = AgentBuilder.buildToolProfile(
            noSkills: false,
            noMemory: false,
            dryrun: false,
            skillRegistry: registry,
            memoryDir: memoryDir,
            config: config,
            usageStore: usageStore,
            skillsDir: skillsDir
        )
        let toolNames = Set(tools.map(\.name))

        // Skill / Memory / 6 个 Storage 工具 / save_skill 全部应在列（usageStore 非 nil）
        #expect(toolNames.contains(names.skill), "非 dry-run 应含 Skill 工具")
        #expect(toolNames.contains(names.memory), "非 dry-run 应含 Memory 工具")
        #expect(toolNames.contains(names.storageScan))
        #expect(toolNames.contains(names.proposeStoragePlan))
        #expect(toolNames.contains(names.executeStoragePlan))
        #expect(toolNames.contains(names.undoStorageOp))
        #expect(toolNames.contains(names.scanAppUninstall))
        #expect(toolNames.contains(names.executeAppUninstall))
        #expect(toolNames.contains(saveSkill), "usageStore != nil 时应含 save_skill")
    }

    @Test("AC1/AC5 非 dry-run helper 输出排除 ToolSearch / AskUser（沿用 excludedToolNames）")
    func test_buildToolProfile_nonDryrun_excludesToolSearchAndAskUser() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let memoryDir = base + "/memory"
        let skillsDir = base + "/skills"
        try FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let config = makeConfig()
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

        // excludedToolNames 是 AgentBuilder 既有静态常量，测试引用真实常量而非硬编码
        for excluded in AgentBuilder.excludedToolNames {
            #expect(!toolNames.contains(excluded), "helper 应排除 \(excluded)")
        }
    }

    @Test("AC1 非 dry-run helper 输出含 core + specialist 基础工具（过滤 excludedToolNames）")
    func test_buildToolProfile_nonDryrun_includesCoreAndSpecialistBaseTools() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let memoryDir = base + "/memory"
        let skillsDir = base + "/skills"
        try FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let config = makeConfig()
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

        // 验证基础工具层完整纳入：core + specialist（过滤 excludedToolNames 后）
        let expectedBase = (getAllBaseTools(tier: .core) + getAllBaseTools(tier: .specialist))
            .map(\.name)
            .filter { !AgentBuilder.excludedToolNames.contains($0) }
        for baseName in expectedBase {
            #expect(toolNames.contains(baseName), "helper 应含基础工具 \(baseName)")
        }
    }

    // MARK: - AC4 + AC5: dry-run 路径工具过滤 parity

    @Test("AC4/AC5 dry-run helper 输出排除 Bash / Skill（dryrunExcludedToolNames）")
    func test_buildToolProfile_dryrun_excludesBashAndSkill() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let memoryDir = base + "/memory"
        let skillsDir = base + "/skills"
        try FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let config = makeConfig()
        let registry = SkillRegistry()

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

        // dry-run 排除集引用 `AgentBuilder.dryrunExcludedToolNames` 真实静态常量（Story 40.3
        // 把它从局部字面量提升为 static let，并扩展含 Agent / Task）。此处不再硬编码字面量，
        // 与 40.3 的 `test_buildToolProfile_dryrunExcludedSet_includesAgentTask` 共用同一来源。
        for excluded in AgentBuilder.dryrunExcludedToolNames {
            #expect(!toolNames.contains(excluded), "dry-run 不应含 \(excluded)")
        }
    }

    @Test("AC4/AC5 dry-run helper 输出排除 Memory / Storage 副作用工具 / save_skill")
    func test_buildToolProfile_dryrun_excludesSideEffectTools() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let memoryDir = base + "/memory"
        let skillsDir = base + "/skills"
        try FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let config = makeConfig()
        let registry = SkillRegistry()
        let usageStore = SkillUsageStore(skillsDir: skillsDir)
        // 防御性覆盖：即使直接调用 helper 时误传了非 nil usageStore，dry-run 仍不得注册 save_skill。
        let names = expectedNames(memoryDir: memoryDir, skillRegistry: registry, config: config)
        let saveSkill = saveSkillName(skillRegistry: registry, usageStore: usageStore, skillsDir: skillsDir)

        let tools = AgentBuilder.buildToolProfile(
            noSkills: false,
            noMemory: false,
            dryrun: true,
            skillRegistry: registry,
            memoryDir: memoryDir,
            config: config,
            usageStore: usageStore,
            skillsDir: skillsDir
        )
        let toolNames = Set(tools.map(\.name))

        #expect(!toolNames.contains(names.memory), "dry-run 不应含 Memory 工具")
        #expect(!toolNames.contains(names.storageScan), "dry-run 不应含 storage_scan")
        #expect(!toolNames.contains(names.proposeStoragePlan))
        #expect(!toolNames.contains(names.executeStoragePlan))
        #expect(!toolNames.contains(names.undoStorageOp))
        #expect(!toolNames.contains(names.scanAppUninstall))
        #expect(!toolNames.contains(names.executeAppUninstall))
        #expect(!toolNames.contains(saveSkill), "dry-run 即使 usageStore 非 nil 也不应含 save_skill")
    }

    // MARK: - AC1: noSkills 开关仅控 Skill 工具

    @Test("AC1 noSkills=true 时仅省略 Skill 工具，Memory/Storage 保留")
    func test_buildToolProfile_noSkillsTrue_omitsSkillToolOnly() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let memoryDir = base + "/memory"
        let skillsDir = base + "/skills"
        try FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let config = makeConfig()
        let registry = SkillRegistry()
        let usageStore = SkillUsageStore(skillsDir: skillsDir)
        let names = expectedNames(memoryDir: memoryDir, skillRegistry: registry, config: config)
        let saveSkill = saveSkillName(skillRegistry: registry, usageStore: usageStore, skillsDir: skillsDir)

        let tools = AgentBuilder.buildToolProfile(
            noSkills: true,
            noMemory: false,
            dryrun: false,
            skillRegistry: registry,
            memoryDir: memoryDir,
            config: config,
            usageStore: usageStore,
            skillsDir: skillsDir
        )
        let toolNames = Set(tools.map(\.name))

        #expect(!toolNames.contains(names.skill), "noSkills=true 应省略 Skill 工具")
        // noSkills 只控 Skill，不控 Memory/Storage
        #expect(toolNames.contains(names.memory))
        #expect(toolNames.contains(names.storageScan))
        #expect(toolNames.contains(names.executeAppUninstall))
        #expect(toolNames.contains(saveSkill))
    }

    // MARK: - AC2: helper 返回可读取 .name 的 [ToolProtocol]（纯函数可测性）

    @Test("AC2 buildToolProfile 返回 [ToolProtocol]，每个元素 .name 可读取")
    func test_buildToolProfile_returnsToolProtocolsWithNameAccessible() throws {
        let base = try makeTempBase()
        defer { cleanup(base) }
        let memoryDir = base + "/memory"
        let skillsDir = base + "/skills"
        try FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let config = makeConfig()
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

        // AC2：返回值为 [ToolProtocol]，调用方可读取 .name 做工具名断言
        #expect(!tools.isEmpty, "非 dry-run 工具池非空")
        #expect(tools.allSatisfy { !$0.name.isEmpty }, "每个工具 .name 非空可读")
        // 工具名唯一性（除 excludedToolNames 外的基础工具 + Skill/Memory/Storage）
        let names = tools.map(\.name)
        #expect(Set(names).count == names.count, "工具名集合应无重复（SDK assembleToolPool 去重前的等价集）")
    }
}
