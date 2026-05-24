import Foundation
import Testing

@testable import OpenAgentSDK

struct CuratorPromptBuilderTests {

    // MARK: - curationPrompt content tests

    @Test func testCurationPromptContainsUmbrellaBuilding() {
        let prompt = CuratorPromptBuilder.curationPrompt()
        #expect(prompt.contains("UMBRELLA-BUILDING"))
        #expect(prompt.contains("class-level"))
    }

    @Test func testCurationPromptContainsThreeStrategies() {
        let prompt = CuratorPromptBuilder.curationPrompt()
        #expect(prompt.contains("MERGE INTO EXISTING UMBRELLA"))
        #expect(prompt.contains("CREATE A NEW UMBRELLA"))
        #expect(prompt.contains("DEMOTE TO REFERENCES"))
    }

    @Test func testCurationPromptContainsHardRules() {
        let prompt = CuratorPromptBuilder.curationPrompt()
        #expect(prompt.contains("bundled"))
        #expect(prompt.contains("pinned"))
        #expect(prompt.contains("Archiving is the maximum destructive action"))
        #expect(prompt.contains("archive only"))
    }

    @Test func testCurationPromptReferencesSDKToolNames() {
        let prompt = CuratorPromptBuilder.curationPrompt()
        #expect(prompt.contains("review_list_skills"))
        #expect(prompt.contains("review_view_skill"))
        #expect(prompt.contains("review_update_skill"))
        #expect(prompt.contains("review_create_skill"))
        #expect(prompt.contains("review_add_skill_file"))
        #expect(prompt.contains("curator_archive_skill"))
    }

    @Test func testCurationPromptContainsStructuredOutput() {
        let prompt = CuratorPromptBuilder.curationPrompt()
        #expect(prompt.contains("consolidations:"))
        #expect(prompt.contains("prunings:"))
    }

    // MARK: - dryRunPrompt tests

    @Test func testDryRunPromptContainsBanner() {
        let prompt = CuratorPromptBuilder.dryRunPrompt()
        #expect(prompt.contains("DRY-RUN — REPORT ONLY"))
        #expect(prompt.contains("DO NOT MUTATE THE SKILL LIBRARY"))
    }

    @Test func testDryRunPromptIncludesCurationPrompt() {
        let dryRun = CuratorPromptBuilder.dryRunPrompt()
        let curation = CuratorPromptBuilder.curationPrompt()
        #expect(dryRun.contains(curation))
    }

    @Test func testDryRunPromptReferencesSDKToolNames() {
        let prompt = CuratorPromptBuilder.dryRunPrompt()
        #expect(prompt.contains("review_update_skill"))
        #expect(prompt.contains("review_create_skill"))
        #expect(prompt.contains("review_add_skill_file"))
        #expect(prompt.contains("curator_archive_skill"))
    }

    // MARK: - buildCandidateList tests

    @Test func testBuildCandidateListFormatsSkills() {
        let usageData: [String: SkillUsageData] = [
            "beta-skill": SkillUsageData(
                skillName: "beta-skill",
                viewCount: 10,
                lastViewedAt: Date(),
                pinned: false,
                provenance: .agentCreated
            ),
            "alpha-skill": SkillUsageData(
                skillName: "alpha-skill",
                viewCount: 5,
                lastViewedAt: nil,
                pinned: true,
                provenance: .agentCreated
            ),
        ]

        let result = CuratorPromptBuilder.buildCandidateList(usageData: usageData)

        #expect(result.contains("Agent-created skills (2)"))
        // Alphabetical order: alpha-skill first
        let alphaRange = result.range(of: "alpha-skill")
        let betaRange = result.range(of: "beta-skill")
        #expect(alphaRange!.lowerBound < betaRange!.lowerBound)

        #expect(result.contains("state=active"))
        #expect(result.contains("pinned=no"))
        #expect(result.contains("views=10"))
        #expect(result.contains("pinned=yes"))
        #expect(result.contains("views=5"))
    }

    @Test func testBuildCandidateListSkipsNonAgentCreated() {
        let usageData: [String: SkillUsageData] = [
            "bundled-skill": SkillUsageData(
                skillName: "bundled-skill",
                provenance: .bundled
            ),
            "user-skill": SkillUsageData(
                skillName: "user-skill",
                provenance: .userDefined
            ),
            "hub-skill": SkillUsageData(
                skillName: "hub-skill",
                provenance: .hubInstalled
            ),
        ]

        let result = CuratorPromptBuilder.buildCandidateList(usageData: usageData)
        #expect(result == "No agent-created skills to review.")
    }

    @Test func testBuildCandidateListEmptyReturnsNoSkills() {
        let result = CuratorPromptBuilder.buildCandidateList(usageData: [:])
        #expect(result == "No agent-created skills to review.")
    }

    @Test func testBuildCandidateListMixedProvenance() {
        let usageData: [String: SkillUsageData] = [
            "agent-one": SkillUsageData(
                skillName: "agent-one",
                viewCount: 3,
                lastViewedAt: Date(),
                pinned: false,
                provenance: .agentCreated
            ),
            "bundled-one": SkillUsageData(
                skillName: "bundled-one",
                viewCount: 100,
                provenance: .bundled
            ),
            "agent-two": SkillUsageData(
                skillName: "agent-two",
                viewCount: 7,
                lastViewedAt: nil,
                pinned: false,
                provenance: .agentCreated
            ),
        ]

        let result = CuratorPromptBuilder.buildCandidateList(usageData: usageData)

        #expect(result.contains("Agent-created skills (2)"))
        #expect(result.contains("agent-one"))
        #expect(result.contains("agent-two"))
        #expect(!result.contains("bundled-one"))
    }
}
