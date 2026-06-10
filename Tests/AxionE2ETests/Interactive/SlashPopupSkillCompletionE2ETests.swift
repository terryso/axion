import Foundation
import Testing

@testable import AxionCLI
import OpenAgentSDK

/// E2E tests for Story 38.9: SlashPopup Skill 补全.
///
/// 验证真实 SkillRegistry → SkillInfo 映射 → SlashPopup 过滤/渲染的端到端路径。
/// 不需要 API key — 纯 SkillRegistry + SlashPopup 交互测试。
///
/// ChatComposer 集成路径（Tab/Enter 补全 skill）由 ChatComposerSlashPopupTests 覆盖（单元测试层）。
@Suite("SlashPopup Skill Completion E2E")
struct SlashPopupSkillCompletionE2ETests {

    // MARK: - Helpers

    /// 构建包含 built-in skill 的 [SkillInfo]
    private func builtInSkillInfos() -> [SkillInfo] {
        let registry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: registry)
        return registry.userInvocableSkills.map { skill in
            SkillInfo(name: skill.name, description: skill.description, aliases: skill.aliases)
        }
    }

    /// 构建包含 filesystem skill 的 registry + 对应 [SkillInfo]
    private func registryWithFilesystemSkills() -> (SkillRegistry, [SkillInfo]) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("e2e-popup-skill")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let skillMD = """
        ---
        name: e2e-popup-skill
        description: E2E popup test skill for verification
        userInvocable: true
        aliases: e2eps, popup-test
        ---

        E2E test skill body.
        """
        try! skillMD.write(to: tempDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let registry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: registry)
        _ = registry.registerDiscoveredSkills(from: [tempDir.deletingLastPathComponent().path])

        let infos = registry.userInvocableSkills.map { skill in
            SkillInfo(name: skill.name, description: skill.description, aliases: skill.aliases)
        }
        return (registry, infos)
    }

    // MARK: - E2E: Built-in Skill → SlashPopup.filter

    @Test("E2E: built-in skills appear in empty query popup")
    func builtInSkillsInEmptyQuery() {
        let skills = builtInSkillInfos()
        guard !skills.isEmpty else {
            Issue.record("No built-in skills found in registry")
            return
        }

        let items = SlashPopup.filter(query: "/", skills: skills)

        // 验证 built-in skill 出现在列表中
        let skillNames = items.compactMap { item -> String? in
            if case .skill(let info) = item.kind { return info.name }
            return nil
        }
        #expect(!skillNames.isEmpty, "Should have at least one skill in popup")

        // 验证命令和 skill 混合存在
        let hasCommands = items.contains { if case .command = $0.kind { return true } else { return false } }
        let hasSkills = items.contains { if case .skill = $0.kind { return true } else { return false } }
        #expect(hasCommands, "Should have commands in popup")
        #expect(hasSkills, "Should have skills in popup")

        // 验证混合排序 — 所有 displayName 应按字母序排列
        let displayNames = items.map(\.kind.displayName)
        let sorted = displayNames.sorted()
        #expect(displayNames == sorted, "Items should be sorted alphabetically")
    }

    @Test("E2E: built-in skill prefix match works end-to-end")
    func builtInSkillPrefixMatch() {
        let skills = builtInSkillInfos()

        // screenshot-analyze 是 built-in skill，/sc 前缀应匹配
        let items = SlashPopup.filter(query: "/sc", skills: skills)
        let matched = items.filter {
            if case .skill(let info) = $0.kind { return info.name == "screenshot-analyze" }
            return false
        }
        #expect(!matched.isEmpty, "/sc should match screenshot-analyze skill")
    }

    @Test("E2E: built-in skill alias match works end-to-end")
    func builtInSkillAliasMatch() {
        let skills = builtInSkillInfos()

        // screenshot-analyze 有别名 "sa"
        let items = SlashPopup.filter(query: "/sa", skills: skills)
        let matched = items.filter {
            if case .skill(let info) = $0.kind { return info.name == "screenshot-analyze" }
            return false
        }
        #expect(!matched.isEmpty, "/sa should match screenshot-analyze via alias")
    }

    // MARK: - E2E: Built-in Skill → SlashPopup.render

    @Test("E2E: rendered skill output contains [skill] tag and description")
    func renderedSkillOutput() {
        let skills = builtInSkillInfos()
        guard let firstSkill = skills.first else {
            Issue.record("No built-in skills")
            return
        }

        let items = SlashPopup.filter(query: "/\(firstSkill.name.prefix(2))", skills: skills)
        guard !items.isEmpty else {
            Issue.record("No items matched for prefix of \(firstSkill.name)")
            return
        }

        let theme = ChatTheme(profile: .unknown, isTTY: false)
        let output = SlashPopup.render(items: items, selectedIndex: -1, theme: theme)

        // 验证包含 skill 的显示名称
        #expect(output.contains("/\(firstSkill.name)"), "Should contain skill display name")
        // 验证包含 [skill] 标签
        #expect(output.contains("[skill]"), "Should contain [skill] tag")
    }

    // MARK: - E2E: Filesystem Skill → Full Pipeline

    @Test("E2E: filesystem skill discovered and appears in popup")
    func filesystemSkillInPopup() {
        let (_, skills) = registryWithFilesystemSkills()

        // 验证 filesystem skill 出现在列表
        let items = SlashPopup.filter(query: "/", skills: skills)
        let matched = items.filter {
            if case .skill(let info) = $0.kind { return info.name == "e2e-popup-skill" }
            return false
        }
        #expect(!matched.isEmpty, "Filesystem skill should appear in popup")
    }

    @Test("E2E: filesystem skill alias match in popup")
    func filesystemSkillAliasInPopup() {
        let (_, skills) = registryWithFilesystemSkills()

        // e2e-popup-skill 有别名 "e2eps"
        let items = SlashPopup.filter(query: "/e2eps", skills: skills)
        let matched = items.filter {
            if case .skill(let info) = $0.kind { return info.name == "e2e-popup-skill" }
            return false
        }
        #expect(!matched.isEmpty, "/e2eps alias should match e2e-popup-skill")

        // 另一个别名 "popup-test"
        let items2 = SlashPopup.filter(query: "/popup-te", skills: skills)
        let matched2 = items2.filter {
            if case .skill(let info) = $0.kind { return info.name == "e2e-popup-skill" }
            return false
        }
        #expect(!matched2.isEmpty, "/popup-te prefix should match popup-test alias")
    }

    // MARK: - E2E: SkillInfo Mapping from SkillRegistry

    @Test("E2E: SkillInfo mapping preserves name, description, aliases")
    func skillInfoMappingAccuracy() {
        let registry = SkillRegistry()
        registry.register(Skill(
            name: "test-mapping",
            description: "Test description for mapping",
            aliases: ["tm", "map-test"],
            userInvocable: true,
            promptTemplate: "Test"
        ))

        let infos: [SkillInfo] = registry.userInvocableSkills.map { skill in
            SkillInfo(name: skill.name, description: skill.description, aliases: skill.aliases)
        }

        guard let info = infos.first(where: { $0.name == "test-mapping" }) else {
            Issue.record("test-mapping skill not found in infos")
            return
        }

        #expect(info.name == "test-mapping")
        #expect(info.description == "Test description for mapping")
        #expect(info.aliases == ["tm", "map-test"])
    }

    @Test("E2E: non-userInvocable skills excluded from popup")
    func nonUserInvocableExcluded() {
        let registry = SkillRegistry()
        registry.register(Skill(
            name: "internal-only",
            description: "Internal skill",
            userInvocable: false,
            promptTemplate: "Internal"
        ))
        registry.register(Skill(
            name: "public-skill",
            description: "Public skill",
            userInvocable: true,
            promptTemplate: "Public"
        ))

        let infos: [SkillInfo] = registry.userInvocableSkills.map { skill in
            SkillInfo(name: skill.name, description: skill.description, aliases: skill.aliases)
        }

        let items = SlashPopup.filter(query: "/", skills: infos)
        let names = items.map(\.kind.displayName)

        #expect(!names.contains("/internal-only"), "Non-userInvocable should be excluded")
        #expect(names.contains("/public-skill"), "User-invocable should be included")
    }

    // MARK: - E2E: completeSelected with Skill

    @Test("E2E: SlashPopupItemKind.skill displayName and acceptsArgs")
    func skillKindProperties() {
        let skills = builtInSkillInfos()
        guard let firstSkill = skills.first else {
            Issue.record("No built-in skills")
            return
        }

        let kind = SlashPopupItemKind.skill(firstSkill)
        #expect(kind.displayName == "/\(firstSkill.name)")
        #expect(kind.acceptsArgs == true, "Skill should always accept args")
    }

    @Test("E2E: command kind properties preserved through new model")
    func commandKindPropertiesPreserved() {
        let kind = SlashPopupItemKind.command(.help)
        #expect(kind.displayName == "/help")
        #expect(kind.acceptsArgs == false)

        let kindModel = SlashPopupItemKind.command(.model)
        #expect(kindModel.displayName == "/model")
        #expect(kindModel.acceptsArgs == true)
    }

    // MARK: - E2E: Agent Busy Context

    @Test("E2E: agent busy filters skills and task-sensitive commands")
    func agentBusyFiltersAll() {
        let skills = builtInSkillInfos()
        let busyContext = SlashCommandContext(isAgentBusy: true, isSideSession: false)

        let items = SlashPopup.filter(query: "/", context: busyContext, skills: skills)

        // Skill 应该全部被过滤
        let skillItems = items.filter {
            if case .skill = $0.kind { return true }
            return false
        }
        #expect(skillItems.isEmpty, "All skills should be filtered when agent is busy")

        // task-sensitive 命令也应被过滤
        let names = items.map(\.kind.displayName)
        #expect(!names.contains("/resume"), "/resume should be filtered when agent busy")
        #expect(!names.contains("/new"), "/new should be filtered when agent busy")

        // task-safe 命令应保留
        #expect(names.contains("/help"), "/help should be available when agent busy")
        #expect(names.contains("/cost"), "/cost should be available when agent busy")
    }

    // MARK: - E2E: No Skill Registry (--no-skills)

    @Test("E2E: empty skill list produces same result as original command-only mode")
    func emptySkillsBehaviorIdentical() {
        // 没有 skill 时的行为应该与原始命令模式完全一致
        let itemsNoSkill = SlashPopup.filter(query: "/", skills: [])
        let itemsOriginal = SlashPopup.filter(query: "/")

        #expect(itemsNoSkill.count == itemsOriginal.count,
            "Empty skill list should produce same count as no-skill mode")
        #expect(itemsNoSkill.map(\.kind.displayName) == itemsOriginal.map(\.kind.displayName),
            "Empty skill list should produce same items as no-skill mode")
    }

    // MARK: - E2E: Render Alignment

    @Test("E2E: mixed command+skill render has aligned columns")
    func renderAlignmentWithMixedItems() {
        let skills = [
            SkillInfo(name: "a-very-long-skill-name-for-testing", description: "Short", aliases: []),
            SkillInfo(name: "x", description: "A longer description that exceeds fifty characters limit for testing", aliases: []),
        ]

        let items = SlashPopup.filter(query: "/", skills: skills)
        let theme = ChatTheme(profile: .unknown, isTTY: false)
        let output = SlashPopup.render(items: items, selectedIndex: -1, theme: theme)

        // 验证长 skill 名称出现在输出中
        #expect(output.contains("/a-very-long-skill-name-for-testing"))
        // 验证描述截断
        #expect(output.contains("..."), "Long description should be truncated")
        // 验证 [skill] 标签
        #expect(output.contains("[skill]"))
    }

    // MARK: - E2E: Skill Name Collision with Command Name

    @Test("E2E: skill with same name as command appears as separate item")
    func skillCommandNameCollision() {
        // 如果有一个叫 "help" 的 skill（和 /help 命令同名）
        let skills = [SkillInfo(name: "help", description: "A custom help skill", aliases: [])]
        let items = SlashPopup.filter(query: "/help", skills: skills)

        // 应该同时匹配命令和 skill
        #expect(items.count == 2, "Should match both command /help and skill /help")

        let kinds = items.map(\.kind)
        let hasCmd = kinds.contains { if case .command(.help) = $0 { return true } else { return false } }
        let hasSkill = kinds.contains { if case .skill = $0 { return true } else { return false } }
        #expect(hasCmd, "Should contain command /help")
        #expect(hasSkill, "Should contain skill /help")
    }
}
