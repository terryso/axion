import Testing
import Foundation
import OpenAgentSDK

@testable import AxionCLI
@testable import AxionCore

// MARK: - Story 40.7 ATDD
//
// 本文件覆盖 Story 40.7「Slash-Skill Guidance for Child Agents」的 AC1–AC5：
// (1) `slashSkillAndTaskGuidance(noSkills:dryrun:)` 纯函数 helper 在「Skill 与 Task 同时可用」
//     （⟺ `!noSkills && !dryrun`，投影自 `buildToolProfile` 注册门）时返回非空提示块，否则 nil；
// (2) 提示块措辞同时覆盖「slash-skill 执行」（CAP-3）与「Task 工具调用」（CAP-1/CAP-2）两条指引；
// (3) `buildSystemPrompt`（Path A / run）在 `!noSkills && !dryrun` 时注入该块，dry-run / --no-skills 时不注入；
// (4) `buildSkillAgent`（Path B）恒注入（skill 路径恒注册 Skill+Agent+Task）；
// (5) 40.2–40.6 零回归。
//
// 设计依据（CLAUDE.md 强制约束）：
// - 全部使用 Swift Testing（`import Testing` / `@Suite` / `@Test` / `#expect`），禁止导入 XCTest
// - 单元测试必须 Mock：**禁止**调用真实 `AgentBuilder.build()` / `buildSkillAgent()`（会 resolveApiKey +
//   Helper + MCP）。4.2.1–4.2.7 只调纯函数 `slashSkillAndTaskGuidance`（零外部依赖）；4.2.8 调
//   `buildSystemPrompt`（注入空 `SkillRegistry()` + `noMemory:true` + 临时 memoryDir，无网络 / 无 Helper / 无 MCP）
// - **反模式 #10 边界**：AC2 的措辞断言（`"invoke the Skill tool"` 等）是 SPEC/Risk 表钦定的 canonical
//   短语——属产品契约守护，不是「硬编码工具名做期望」。详见 story Dev Notes「反模式 #10 边界」
// - 测试位于 `Tests/AxionCLITests/Services/`，被默认单元测试命令 `make test` 命中
// - 命名遵循 `test_被测单元_场景_预期结果`

@Suite("AgentBuilder slash-skill guidance (Story 40.7)")
struct AgentBuilderSlashSkillGuidanceTests {

    // MARK: - Helpers

    /// 构造一个最小、无副作用的 `AxionConfig`（仅 apiKey）。沿用 40.5/40.6 测试工厂。
    private func makeConfig() -> AxionConfig {
        AxionConfig(apiKey: "sk-test")
    }

    /// 创建一个临时 memory 目录（供 4.2.8 `buildSystemPrompt` smoke 用），测试结束清理。
    private func createTempMemoryDir() throws -> String {
        let tempDir = "/tmp/axion-test-slash-skill-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return tempDir
    }

    // MARK: - AC1: 四象限条件真值表（slashSkillAndTaskGuidance 是纯函数）

    @Test("AC1 正向：Skill 与 Task 同时可用 (!noSkills && !dryrun) 时返回非空提示块")
    func test_slashSkillAndTaskGuidance_returnsBlockWhenBothAvailable() {
        let guidance = AgentBuilder.slashSkillAndTaskGuidance(noSkills: false, dryrun: false)
        #expect(guidance != nil, "!noSkills && !dryrun 时应返回非空提示块")
        #expect(!guidance!.isEmpty, "提示块应为非空字符串")
    }

    @Test("AC1：noSkills=true 时返回 nil（Task 可能注册但 Skill 不注册 → 不注入 slash 指引）")
    func test_slashSkillAndTaskGuidance_nilWhenNoSkills() {
        let guidance = AgentBuilder.slashSkillAndTaskGuidance(noSkills: true, dryrun: false)
        #expect(guidance == nil, "noSkills=true 时 Skill 工具不注册 → 应返回 nil 不注入")
    }

    @Test("AC1：dryrun=true 时返回 nil（dry-run 不注册 side-effect Skill/Agent/Task 工具）")
    func test_slashSkillAndTaskGuidance_nilWhenDryRun() {
        let guidance = AgentBuilder.slashSkillAndTaskGuidance(noSkills: false, dryrun: true)
        #expect(guidance == nil, "dryrun=true 时 side-effect 工具不注册 → 应返回 nil 不注入")
    }

    @Test("AC1 四象限补全：noSkills=true 且 dryrun=true 时返回 nil")
    func test_slashSkillAndTaskGuidance_nilWhenBothOff() {
        let guidance = AgentBuilder.slashSkillAndTaskGuidance(noSkills: true, dryrun: true)
        #expect(guidance == nil, "noSkills=true && dryrun=true 时应返回 nil")
    }

    // MARK: - AC2: 措辞锚点（canonical 短语子串匹配——产品契约守护，非反模式 #10）

    @Test("AC2 slash-skill 执行指引：含 'invoke the Skill tool' 与 'Do not treat the slash command as plain'")
    func test_slashSkillAndTaskGuidance_containsSlashSkillExecutionPhrase() {
        let guidance = AgentBuilder.slashSkillAndTaskGuidance(noSkills: false, dryrun: false)
        guard let guidance else {
            Issue.record("期望非 nil 提示块以断言措辞")
            return
        }
        // CAP-3 / 架构 §4 钦定措辞：告诉模型把 /<skill-name> 当 Skill 工具调用，不要当聊天
        #expect(
            guidance.contains("invoke the Skill tool"),
            "提示块应含 'invoke the Skill tool'（CAP-3 slash-skill 执行锚点）"
        )
        #expect(
            guidance.contains("Do not treat the slash command as plain"),
            "提示块应含 'Do not treat the slash command as plain'（否定式锚点，防把 slash 当聊天）"
        )
    }

    @Test("AC2 Task 工具调用指引：含 'Task(subagent_type' / 'invoke the `Task` tool' / 'Do not print the' 三锚点")
    func test_slashSkillAndTaskGuidance_containsTaskInvocationPhrase() {
        let guidance = AgentBuilder.slashSkillAndTaskGuidance(noSkills: false, dryrun: false)
        guard let guidance else {
            Issue.record("期望非 nil 提示块以断言措辞")
            return
        }
        // CAP-1/CAP-2 / implementation-plan Risk 表第 198 行钦定措辞：Task(...) 片段映射到 Task 工具
        #expect(
            guidance.contains("Task(subagent_type"),
            "提示块应含 'Task(subagent_type'（Risk 表 Task 片段锚点）"
        )
        #expect(
            guidance.contains("invoke the `Task` tool"),
            "提示块应含 'invoke the `Task` tool'（Task 工具调用正向锚点）"
        )
        #expect(
            guidance.contains("Do not print the"),
            "提示块应含 'Do not print the'（否定式锚点，防把 Task(...) 当文本打印）"
        )
    }

    // MARK: - 范围守护（可选）：正向指引，非降级提示

    @Test("范围守护：(false,false) 下提示块不含降级措辞 'disabled' / 'not available'")
    func test_slashSkillAndTaskGuidance_doesNotMentionDisabledState() {
        let guidance = AgentBuilder.slashSkillAndTaskGuidance(noSkills: false, dryrun: false)
        guard let guidance else {
            Issue.record("期望非 nil 提示块以断言范围")
            return
        }
        // 选了「降级 nil」策略：可用时只给正向指引，不提「工具不可用」
        #expect(
            !guidance.lowercased().contains("disabled"),
            "正向提示块不应含 'disabled'（非降级提示）"
        )
        #expect(
            !guidance.lowercased().contains("not available"),
            "正向提示块不应含 'not available'（非降级提示）"
        )
    }

    // MARK: - AC3: buildSystemPrompt wiring smoke（Path A / run）

    @Test("AC3 wiring smoke：buildSystemPrompt 在 !noSkills && !dryrun 时含 AC2 指引；dryrun:true 时不含")
    func test_buildSystemPrompt_includesGuidanceWhenBothAvailable() async throws {
        let config = makeConfig()
        let memoryDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: memoryDir) }
        let memoryStore = FileBasedMemoryStore(memoryDir: memoryDir)
        let skillRegistry = SkillRegistry()  // 空 registry，不触发发现

        // (a) !noSkills && !dryrun → 提示含 AC2 关键短语
        let promptAvailable = await AgentBuilder.buildSystemPrompt(
            config: config,
            task: "",
            memoryStore: memoryStore,
            memoryDir: memoryDir,
            skillRegistry: skillRegistry,
            noMemory: true,  // 避免真实 memory 副作用
            noSkills: false,
            fast: false,
            dryrun: false,
            includeSaveSkillGuidance: false
        )
        #expect(
            promptAvailable.contains("invoke the Skill tool"),
            "buildSystemPrompt 在 !noSkills && !dryrun 时应注入 slash-skill 指引"
        )
        #expect(
            promptAvailable.contains("invoke the `Task` tool"),
            "buildSystemPrompt 在 !noSkills && !dryrun 时应注入 Task 工具调用指引"
        )

        // (b) dryrun:true → 提示不含 AC2 关键短语（helper 返回 nil → 不追加）
        let promptDryrun = await AgentBuilder.buildSystemPrompt(
            config: config,
            task: "",
            memoryStore: memoryStore,
            memoryDir: memoryDir,
            skillRegistry: skillRegistry,
            noMemory: true,
            noSkills: false,
            fast: false,
            dryrun: true,
            includeSaveSkillGuidance: false
        )
        #expect(
            !promptDryrun.contains("Skill & Subagent Execution (Claude Code Compatibility)"),
            "dryrun=true 时 buildSystemPrompt 不应注入 slash-skill guidance 段落"
        )
    }
}
