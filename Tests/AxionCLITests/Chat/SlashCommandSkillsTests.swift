import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

@Suite("SlashCommand /skills")
struct SlashCommandSkillsTests {

    // MARK: - /skills parse

    @Test("parse /skills → .skills")
    func parseSkills() {
        #expect(SlashCommand.parse("/skills") == .skills)
    }

    @Test("parse /Skills → .skills (大小写不敏感)")
    func parseSkillsCaseInsensitive() {
        #expect(SlashCommand.parse("/Skills") == .skills)
    }

    @Test("/skills helpText 非空")
    func skillsHelpText() {
        #expect(!SlashCommand.skills.helpText.isEmpty)
        #expect(SlashCommand.skills.helpText == "列出可用技能")
    }

    @Test("/skills acceptsArgs == false")
    func skillsAcceptsNoArgs() {
        #expect(SlashCommand.skills.acceptsArgs == false)
    }

    @Test("/skills availableDuringTask == false")
    func skillsNotAvailableDuringTask() {
        #expect(SlashCommand.skills.availableDuringTask == false)
    }

    // MARK: - allCases 包含 .skills

    @Test("allCases 包含 .skills")
    func allCasesContainsSkills() {
        #expect(SlashCommand.allCases.contains(.skills))
    }

    // MARK: - handleSkills 无 registry

    @Test("handleSkills 无 registry 时提示技能系统未启用")
    func handleSkillsNoRegistry() {
        let output = SlashCommandHandler.handleSkills(registry: nil)
        #expect(output.contains("技能系统未启用"))
    }

    // MARK: - handleSkills 空 registry

    @Test("handleSkills 无技能时显示暂无可用技能")
    func handleSkillsEmpty() {
        let registry = SkillRegistry()
        let output = SlashCommandHandler.handleSkills(registry: registry)
        #expect(output.contains("暂无可用技能"))
    }

    // MARK: - handleSkills 有技能

    @Test("handleSkills 显示技能列表")
    func handleSkillsWithSkills() {
        let registry = SkillRegistry()
        registry.register(Skill(
            name: "test-skill",
            description: "A test skill for verification",
            userInvocable: true,
            promptTemplate: "Do something useful"
        ))
        let output = SlashCommandHandler.handleSkills(registry: registry)
        #expect(output.contains("可用技能"))
        #expect(output.contains("test-skill"))
        #expect(output.contains("A test skill for verification"))
    }

    @Test("handleSkills 显示多个技能并按字母排序")
    func handleSkillsMultipleSorted() {
        let registry = SkillRegistry()
        registry.register(Skill(
            name: "zebra",
            description: "Z skill",
            userInvocable: true,
            promptTemplate: "Z"
        ))
        registry.register(Skill(
            name: "alpha",
            description: "A skill",
            userInvocable: true,
            promptTemplate: "A"
        ))
        let output = SlashCommandHandler.handleSkills(registry: registry)
        #expect(output.contains("alpha"))
        #expect(output.contains("zebra"))
        // alpha 应该出现在 zebra 之前（字母排序）
        let alphaRange = output.range(of: "alpha")
        let zebraRange = output.range(of: "zebra")
        if let a = alphaRange, let z = zebraRange {
            #expect(a.lowerBound < z.lowerBound)
        }
    }

    @Test("handleSkills 不显示 userInvocable=false 的技能")
    func handleSkillsFiltersNonUserInvocable() {
        let registry = SkillRegistry()
        registry.register(Skill(
            name: "public-skill",
            description: "Public",
            userInvocable: true,
            promptTemplate: "Public"
        ))
        registry.register(Skill(
            name: "internal-skill",
            description: "Internal",
            userInvocable: false,
            promptTemplate: "Internal"
        ))
        let output = SlashCommandHandler.handleSkills(registry: registry)
        #expect(output.contains("public-skill"))
        #expect(!output.contains("internal-skill"))
    }

    @Test("handleSkills 显示别名")
    func handleSkillsShowsAliases() {
        let registry = SkillRegistry()
        registry.register(Skill(
            name: "commit",
            description: "Create commit",
            aliases: ["ci"],
            userInvocable: true,
            promptTemplate: "Commit"
        ))
        let output = SlashCommandHandler.handleSkills(registry: registry)
        #expect(output.contains("commit"))
        #expect(output.contains("别名"))
        #expect(output.contains("ci"))
    }

    @Test("handleSkills 文件系统技能标记 [fs]")
    func handleSkillsFilesystemTag() {
        let registry = SkillRegistry()
        registry.register(Skill(
            name: "my-skill",
            description: "FS skill",
            userInvocable: true,
            promptTemplate: "Do it",
            baseDir: "/some/path"
        ))
        let output = SlashCommandHandler.handleSkills(registry: registry)
        #expect(output.contains("[fs]"))
    }

    @Test("handleSkills 提示直接执行技能")
    func handleSkillsShowsUsageHint() {
        let registry = SkillRegistry()
        registry.register(Skill(
            name: "example",
            description: "Example skill",
            userInvocable: true,
            promptTemplate: "Example"
        ))
        let output = SlashCommandHandler.handleSkills(registry: registry)
        #expect(output.contains("/example"))
    }

    // MARK: - handleSkills 截断长描述

    @Test("handleSkills 截断超长描述")
    func handleSkillsTruncatesLongDescription() {
        let longDesc = String(repeating: "A", count: 100)
        let registry = SkillRegistry()
        registry.register(Skill(
            name: "verbose-skill",
            description: longDesc,
            userInvocable: true,
            promptTemplate: "Verbose"
        ))
        let output = SlashCommandHandler.handleSkills(registry: registry)
        #expect(output.contains("verbose-skill"))
        // 描述被截断，不应包含完整的 100 个字符
        #expect(!output.contains(longDesc))
    }

    // MARK: - Skill 名称匹配（用于 /skill-name 直接执行）

    @Suite("Skill name matching")
    struct SkillNameMatchingTests {

        @Test("SkillRegistry.find() 精确匹配")
        func findExact() {
            let registry = SkillRegistry()
            registry.register(Skill(
                name: "commit",
                description: "Create commit",
                userInvocable: true,
                promptTemplate: "Commit"
            ))
            #expect(registry.find("commit") != nil)
            #expect(registry.find("nonexistent") == nil)
        }

        @Test("SkillRegistry.find() 别名匹配")
        func findAlias() {
            let registry = SkillRegistry()
            registry.register(Skill(
                name: "commit",
                description: "Create commit",
                aliases: ["ci"],
                userInvocable: true,
                promptTemplate: "Commit"
            ))
            #expect(registry.find("ci") != nil)
        }

        @Test("SkillRegistry.find() 返回的 skill 有 promptTemplate")
        func foundSkillHasPromptTemplate() {
            let registry = SkillRegistry()
            registry.register(Skill(
                name: "test",
                description: "Test skill",
                userInvocable: true,
                promptTemplate: "Execute the test"
            ))
            let skill = registry.find("test")
            #expect(skill != nil)
            #expect(skill!.promptTemplate == "Execute the test")
        }

        @Test("userInvocableSkills 过滤不可用技能")
        func userInvocableFilters() {
            let registry = SkillRegistry()
            registry.register(Skill(
                name: "public",
                description: "Public",
                userInvocable: true,
                promptTemplate: "P"
            ))
            registry.register(Skill(
                name: "private",
                description: "Private",
                userInvocable: false,
                promptTemplate: "P"
            ))
            let invocable = registry.userInvocableSkills
            #expect(invocable.count == 1)
            #expect(invocable[0].name == "public")
        }

        @Test("promptTemplate 支持 {args} 占位符")
        func promptTemplateArgsSubstitution() {
            let template = "Search for {args} in the codebase"
            let result = template.replacingOccurrences(of: "{args}", with: "authentication")
            #expect(result == "Search for authentication in the codebase")
        }

        @Test("promptTemplate 无 {args} 时不替换")
        func promptTemplateNoArgs() {
            let template = "Analyze and commit changes"
            let result = template.replacingOccurrences(of: "{args}", with: "something")
            #expect(result == "Analyze and commit changes")
        }
    }
}
