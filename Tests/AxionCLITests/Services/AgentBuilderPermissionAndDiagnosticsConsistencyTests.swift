import Testing
import Foundation
import OpenAgentSDK

@testable import AxionCLI
@testable import AxionCore

// MARK: - Story 40.6 ATDD
//
// 本文件覆盖 Story 40.6「Permission, Allowlist, and Diagnostics Consistency」的 AC1–AC5：
// (1) `diagnoseToolAvailability(...)` 纯函数 helper 在 Axion build/route 时刻复算 SDK 运行时丢弃的
//     tool-availability diagnostics（unmatched / unsupported / pattern / config-disabled），让「skill 声明
//     了不可用工具」这一信号可观察（CAP-8）；(2) 全部未知 → 不静默退化为「无限制」（AC2）；(3) config
//     policy 冲突（ToolSearch 被 `enableToolSearch:false` 关）产生可见诊断（AC3）；(4) permission mode +
//     session allowlist 在 chat skill 执行（Path A）与 child agent 上非扩张继承——`forChat` 透传、
//     `forSkillExecution` 有意 `.bypassPermissions`（AC4）；(5) 过滤顺序：allowed-tools 先收窄 → 交集
//     （AC5）。
//
// 设计依据（CLAUDE.md 强制约束）：
// - 全部使用 Swift Testing（`import Testing` / `@Suite` / `@Test` / `#expect`），禁止导入 XCTest
// - 单元测试必须 Mock：**禁止**调用真实 `AgentBuilder.build()` / `buildSkillAgent()`（会 resolveApiKey +
//   起 Helper 进程 + 真实 MCP resolve）。本测试只调用纯函数 helper（`diagnoseToolAvailability` /
//   `effectiveSkillToolPool`）+ 纯 struct 构造（`BuildConfig.forChat` / `forSkillExecution`）+ 直接构造
//   `Skill` / `ToolDeclaration`
// - 工具名 **不硬编码字面量做期望**（反模式 #10）：期望工具名一律从真实工具实例的 `.name` 读取
//   （`createReadTool().name`、`createGrepTool().name`、`createBashTool().name`、`createWriteTool().name`）；
//   `ToolDeclaration` 用 `.parse(...)` 构造（declaration 名属测试输入，可写字面量）；`normalizedName`
//   比对从枚举读取 `ToolRestriction.toolSearch.rawValue.lowercased()`，不手写字面量 `"toolsearch"`
// - `Skill.init` 的 `promptTemplate: String` 必填无默认——fixture skill 一律传 `promptTemplate: ""`；
//   程序化构造的 `Skill` 其 `toolDeclarationDiagnostics` 为 nil，`diagnoseToolAvailability` 内已用
//   `?? declarations.filter { ... }` 回退，故无需手动填 diagnostics
// - 测试位于 `Tests/AxionCLITests/Services/`，被默认单元测试命令 `make test` 命中
// - 命名遵循 `test_被测单元_场景_预期结果`

@Suite("AgentBuilder permission & diagnostics consistency (Story 40.6)")
struct AgentBuilderPermissionAndDiagnosticsConsistencyTests {

    // MARK: - Helpers

    /// 构造一个最小、无副作用的 `AxionConfig`（仅 apiKey + 默认 storage）。`enableToolSearch` 默认 nil →
    /// `toolSearchEnabled == false`（保持 GLM 稳定，Story 40.5 默认）。
    private func makeConfig() -> AxionConfig {
        AxionConfig(apiKey: "sk-test")
    }

    /// 构造一个无 `allowed-tools` 的 fixture skill（`toolDeclarations == nil`），用于 AC2/AC5 反向断言。
    private func unrestrictedSkill() -> OpenAgentSDK.Skill {
        OpenAgentSDK.Skill(name: "s", promptTemplate: "")
    }

    // MARK: - AC1 + AC2: unknown / unresolvable allowed-tools 显式诊断，不静默退化

    @Test("AC1+AC2 未知工具与未匹配 MCP 工具被显式诊断，绝不静默退化为无限制")
    func test_diagnoseToolAvailability_unmatchedAndUnknownSurface() {
        // 声明：Read/Grep（可用池中有）、UnknownTool（parse 期无法分类 → .unknown）、
        // mcp__github__list_prs（当前未连接的 MCP 工具）
        let skill = OpenAgentSDK.Skill(
            name: "s",
            toolDeclarations: [
                .parse("Read"),
                .parse("Grep"),
                .parse("UnknownTool"),
                .parse("mcp__github__list_prs")
            ],
            promptTemplate: ""
        )

        // 可用池名从真实工具实例读取（反模式 #10：禁止硬编码 "read"/"grep"/"bash"）
        let availableToolNames = [
            createReadTool().name.lowercased(),
            createGrepTool().name.lowercased(),
            createBashTool().name.lowercased()
        ]

        let diag = AgentBuilder.diagnoseToolAvailability(
            skill: skill,
            availableToolNames: availableToolNames,
            enableToolSearch: false
        )

        // unsupportedDeclarations 含 UnknownTool（rawName 是测试输入的 echo，可断言字面量）
        #expect(
            diag.unsupportedDeclarations.contains { $0.rawName == "UnknownTool" },
            "UnknownTool（.unknown）应进入 unsupportedDeclarations"
        )
        // unmatchedDeclarations 含未连接的 MCP 工具（rawName 是测试输入的 echo）
        #expect(
            diag.unmatchedDeclarations.contains { $0.rawName == "mcp__github__list_prs" },
            "未连接的 MCP 工具 mcp__github__list_prs 应进入 unmatchedDeclarations"
        )
        // 影响可用性的诊断应使 affectsAvailability 为真（闭合「不静默退化」红线）
        #expect(diag.affectsAvailability, "存在 unmatched/unsupported 诊断 → affectsAvailability 应为 true")
    }

    @Test("AC2 反向：未声明 allowed-tools 的 skill 返回空 diagnostics（区分「无声明」与「声明但不可用」）")
    func test_diagnoseToolAvailability_noDeclarationsYieldsEmpty() {
        let skill = unrestrictedSkill()  // toolDeclarations == nil

        let diag = AgentBuilder.diagnoseToolAvailability(
            skill: skill,
            availableToolNames: [createReadTool().name.lowercased()],
            enableToolSearch: false
        )

        #expect(diag.isEmpty, "未声明 allowed-tools 的 skill 应产生空 diagnostics（与「声明但不可用」区分）")
        #expect(!diag.affectsAvailability)
    }

    // MARK: - AC3: config policy 冲突产生可观察诊断（接 40.5 的 ToolSearch config 天花板）

    @Test("AC3 skill 请求 ToolSearch 在 enableToolSearch=false 时产生 config-disabled 诊断；true 时不产生")
    func test_diagnoseToolAvailability_toolSearchConfigConflict() {
        let skill = OpenAgentSDK.Skill(
            name: "s",
            toolDeclarations: [.parse("Read"), .parse("ToolSearch")],
            promptTemplate: ""
        )

        // 可用池不含 ToolSearch（典型组装池）
        let availableToolNames = [
            createReadTool().name.lowercased(),
            createGrepTool().name.lowercased(),
            createBashTool().name.lowercased()
        ]

        // normalizedName 比对从枚举读取（反模式 #10：不手写字面量 "toolsearch"）
        let toolSearchNorm = OpenAgentSDK.ToolRestriction.toolSearch.rawValue.lowercased()

        // (a) enableToolSearch=false → configDisabledDeclarations 含 ToolSearch
        let diagDisabled = AgentBuilder.diagnoseToolAvailability(
            skill: skill,
            availableToolNames: availableToolNames,
            enableToolSearch: false
        )
        #expect(
            diagDisabled.configDisabledDeclarations.contains { $0.normalizedName == toolSearchNorm },
            "enableToolSearch=false 时，请求 ToolSearch 应产生 config-disabled 诊断"
        )
        // Regression (Story 40.6 review): a config-disabled declaration must NOT also appear under
        // `unmatchedDeclarations` — the four availability categories are mutually exclusive, so each
        // unavailable tool is reported exactly once (config-disabled gives the precise policy reason,
        // not the misleading "未匹配"). Before this fix ToolSearch was double-reported under both.
        #expect(
            !diagDisabled.unmatchedDeclarations.contains { $0.normalizedName == toolSearchNorm },
            "config-disabled ToolSearch 不应同时进入 unmatchedDeclarations（四类互斥，避免双重报告）"
        )

        // (b) enableToolSearch=true → configDisabledDeclarations 不含 ToolSearch（config 已放行）
        let diagEnabled = AgentBuilder.diagnoseToolAvailability(
            skill: skill,
            availableToolNames: availableToolNames,
            enableToolSearch: true
        )
        #expect(
            !diagEnabled.configDisabledDeclarations.contains { $0.normalizedName == toolSearchNorm },
            "enableToolSearch=true 时，ToolSearch 已被 config 放行，不应产生 config-disabled 诊断"
        )
    }

    @Test("AC1 pattern Bash(git diff:*) 被解析但不强制，进入 patternDeclarations")
    func test_diagnoseToolAvailability_patternDeclarationsParsedNotEnforced() {
        let skill = OpenAgentSDK.Skill(
            name: "s",
            toolDeclarations: [.parse("Bash(git diff:*)")],
            promptTemplate: ""
        )

        let diag = AgentBuilder.diagnoseToolAvailability(
            skill: skill,
            availableToolNames: [createBashTool().name.lowercased()],
            enableToolSearch: false
        )

        // pattern 值 "git diff:*" 是测试输入的 echo（.parse("Bash(git diff:*)")）
        #expect(
            diag.patternDeclarations.contains { $0.pattern == "git diff:*" },
            "Bash(git diff:*) 的 pattern 应被解析并进入 patternDeclarations（parsed but not enforced）"
        )
        // pattern-only 诊断不单独移除工具 → 不应触发 affectsAvailability
        #expect(!diag.affectsAvailability, "仅 pattern 诊断不应使 affectsAvailability 为 true")
    }

    // MARK: - AC4: permission mode + canUseTool 继承（forChat 透传 / forSkillExecution 有意 bypass）

    @Test("AC4 forChat 透传 permissionMode+canUseTool；forSkillExecution 有意 .bypassPermissions + canUseTool:nil")
    func test_forChat_preservesPermission_forSkillExecutionBypasses() {
        let config = makeConfig()

        // Path A（chat）：forChat 应透传传入的 permissionMode 与 canUseTool（非扩张继承的构造保证）
        let chatConfig = AgentBuilder.BuildConfig.forChat(
            config: config,
            permissionMode: .acceptEdits,
            canUseTool: { _, _, _ in CanUseToolResult.allow() }
        )
        #expect(chatConfig.permissionMode == .acceptEdits, "forChat 应透传 permissionMode")
        #expect(chatConfig.canUseTool != nil, "forChat 应透传 canUseTool 闭包")

        // Path B（非交互 skill 执行）：forSkillExecution 有意 .bypassPermissions + canUseTool:nil
        // （无 TTY 无法逐项审批；bypass 是既定策略，本测试锁定该决策，防未来误改）
        let skillExecConfig = AgentBuilder.BuildConfig.forSkillExecution(
            config: config,
            skill: unrestrictedSkill()
        )
        #expect(
            skillExecConfig.permissionMode == .bypassPermissions,
            "forSkillExecution 应为 .bypassPermissions（非交互路径有意 bypass）"
        )
        #expect(skillExecConfig.canUseTool == nil, "forSkillExecution 的 canUseTool 应为 nil")
    }

    // MARK: - AC5: 过滤顺序——allowed-tools 先收窄 → 交集

    @Test("AC5 effectiveSkillToolPool 收窄为交集：allowed [Read,Grep] 仅留 Read/Grep")
    func test_effectiveSkillToolPool_restrictionsNarrowToIntersection() {
        let skill = OpenAgentSDK.Skill(
            name: "s",
            toolDeclarations: [.parse("Read"), .parse("Grep")],
            promptTemplate: ""
        )

        // 组装池含 Read/Grep/Bash/Write（工具名从真实实例构造）
        let available: [OpenAgentSDK.ToolProtocol] = [
            createReadTool(),
            createGrepTool(),
            createBashTool(),
            createWriteTool()
        ]

        let pool = AgentBuilder.effectiveSkillToolPool(skill: skill, available: available)
        let poolNames = Set(pool.map { $0.name })

        // 期望名从真实实例读取（反模式 #10）
        let expected = Set([
            createReadTool().name,
            createGrepTool().name
        ])
        #expect(poolNames == expected, "effectiveSkillToolPool 应收窄为 allowed ∩ available（仅 Read/Grep）")
        #expect(!poolNames.contains(createBashTool().name), "Bash 不在 allowed 声明中 → 应被移除（即便运行时 mayUseTool 放行）")
        #expect(!poolNames.contains(createWriteTool().name), "Write 不在 allowed 声明中 → 应被移除")
    }

    @Test("AC5 反向：未声明 restriction 的 skill 返回全部 available")
    func test_effectiveSkillToolPool_noRestrictionsReturnsAll() {
        let skill = unrestrictedSkill()  // toolDeclarations == nil, toolRestrictions == nil

        let available: [OpenAgentSDK.ToolProtocol] = [
            createReadTool(),
            createBashTool()
        ]

        let pool = AgentBuilder.effectiveSkillToolPool(skill: skill, available: available)
        let poolNames = Set(pool.map { $0.name })
        let expected = Set([
            createReadTool().name,
            createBashTool().name
        ])

        #expect(poolNames == expected, "未声明 restriction 的 skill 应返回全部 available（无收窄）")
    }
}
