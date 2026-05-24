// SelfEvolutionExample 示例
//
// 演示 SDK 的自进化能力，包括：
//   1. LLMExperienceExtractor — 从对话中提取经验信号
//   2. LLMSkillEvolver — 根据使用信号进化技能
//   3. ReviewOrchestrator — 后台审查调度
//   4. IntelligentCurator — 两阶段智能策展
//   5. CuratorRunReport — Markdown/YAML 报告生成
//
// Demonstrates the SDK's self-evolution capabilities:
//   1. LLMExperienceExtractor — extract experience signals from conversations
//   2. LLMSkillEvolver — evolve skills based on usage signals
//   3. ReviewOrchestrator — background review scheduling
//   4. IntelligentCurator — two-phase intelligent curation
//   5. CuratorRunReport — Markdown/YAML report generation
//
// 运行方式：swift run SelfEvolutionExample
// 说明：Part 1-3 为纯 API 调用（使用 mock LLM），无需 API Key

import Foundation
import OpenAgentSDK

print("=== SelfEvolutionExample ===")
print()

// MARK: - Part 1: CuratorRunReport — 报告生成（纯本地）

print("--- Part 1: CuratorRunReport ---")
print()

let report = CuratorRunReport(
    startedAt: Date(),
    durationMs: 3500,
    autoTransitions: [
        SkillLifecycleTransition(
            skillName: "old-helper",
            from: .active,
            to: .deprecated,
            reason: "Not used in 30 days",
            evaluatedAt: Date()
        ),
    ],
    consolidations: [
        CuratorConsolidation(
            from: "debug-login-issue",
            into: "debugging-workflow",
            reason: "login debugging is a subset of general debugging"
        ),
    ],
    prunings: [
        CuratorPruning(
            name: "temp-analysis-2026",
            reason: "one-off analysis, no reusable pattern"
        ),
    ],
    toolCalls: [
        CuratorToolCall(
            toolName: "curator_archive_skill",
            input: "{\"name\": \"temp-analysis-2026\"}",
            result: "Archived successfully",
            isError: false
        ),
    ],
    dryRun: false,
    skillsBefore: 15,
    skillsAfter: 13
)

print("Markdown 报告:")
print(report.renderMarkdown())
print()

print("YAML 报告:")
print(report.renderYAML())
print()

// Dry-run 报告
let dryRunReport = CuratorRunReport(
    startedAt: Date(),
    durationMs: 1200,
    consolidations: [
        CuratorConsolidation(from: "old-skill", into: "umbrella-skill", reason: "subset"),
    ],
    prunings: [],
    dryRun: true,
    skillsBefore: 10,
    skillsAfter: 9
)
print("Dry-run 报告:")
print(dryRunReport.renderMarkdown())
print()

// 空结果报告
let emptyReport = CuratorRunReport(
    startedAt: Date(),
    durationMs: 200
)
print("空结果报告:")
print(emptyReport.renderMarkdown())

// MARK: - Part 2: ExperienceExtractor API（展示类型签名）

print("--- Part 2: ExperienceExtractor Types ---")
print()

// 展示 ExtractionConfig 配置选项
let config = ExtractionConfig(
    minSignalConfidence: 0.7,
    maxSignalsPerExtraction: 10,
    domain: "project-knowledge"
)
print("ExtractionConfig:")
print("  minSignalConfidence: \(config.minSignalConfidence)")
print("  maxSignalsPerExtraction: \(config.maxSignalsPerExtraction)")
print("  domain: \(config.domain ?? "all")")
print()

// 展示 MemoryReviewConfig
let reviewConfig = MemoryReviewConfig(
    enabled: true,
    extractionConfig: config,
    minMessagesForReview: 10
)
print("MemoryReviewConfig:")
print("  enabled: \(reviewConfig.enabled)")
print("  minMessagesForReview: \(reviewConfig.minMessagesForReview)")
print()

// MARK: - Part 3: SkillEvolution Types

print("--- Part 3: SkillEvolution Types ---")
print()

// 展示 SkillEvolutionConfig
let evolveConfig = SkillEvolutionConfig(
    minConfidence: 0.6,
    allowedSignalTypes: [.refinement, .deprecation, .merge]
)
print("SkillEvolutionConfig:")
print("  minConfidence: \(evolveConfig.minConfidence)")
print("  allowedSignalTypes: \(evolveConfig.allowedSignalTypes?.map { $0.rawValue } ?? [])")
print()

// 展示 SkillLifecycleState 枚举
print("SkillLifecycleState 枚举:")
for state in SkillLifecycleState.allCases {
    print("  \(state.rawValue)")
}
print()

// 展示 SkillSignalType 枚举
print("SkillSignalType 枚举:")
for signalType in SkillSignalType.allCases {
    print("  \(signalType.rawValue)")
}
print()

// MARK: - Part 4: CuratorRunReport 从结果构建

print("--- Part 4: CuratorRunReport from IntelligentCuratorResult ---")
print()

// 模拟一个 IntelligentCuratorResult
let ranAt = Date(timeIntervalSince1970: 1_700_000_000)
let mechanicalResult = CuratorRunResult(
    transitionsApplied: [
        SkillLifecycleTransition(
            skillName: "stale-skill",
            from: .active,
            to: .deprecated,
            reason: "Not used in 30 days",
            evaluatedAt: ranAt
        ),
    ],
    skillsEvaluated: 8,
    skillsSkipped: 2,
    errors: [],
    durationMs: 500,
    dryRun: false,
    ranAt: ranAt
)

let curatorResult = IntelligentCuratorResult(
    mechanicalResult: mechanicalResult,
    llmResult: nil,  // 无 LLM 阶段（例如纯机械式策展）
    consolidations: [],
    prunings: [],
    durationMs: 1500,
    dryRun: false,
    error: nil
)

let reportFromResult = CuratorRunReport(from: curatorResult)
print("从 IntelligentCuratorResult 构建报告:")
print("  skillsBefore: \(reportFromResult.skillsBefore)")
print("  skillsAfter: \(reportFromResult.skillsAfter)")
print("  toolCalls: \(reportFromResult.toolCalls.count)")
print("  autoTransitions: \(reportFromResult.autoTransitions.count)")
print()

// MARK: - Part 5: 完整组件组装（展示 API 集成方式）

print("--- Part 5: 完整组件组装 ---")
print()

// 展示如何组装所有自进化组件
let factStore = FactStore()
let usageStore = SkillUsageStore(skillsDir: NSTemporaryDirectory())
let curatorStore = SkillCuratorStore(skillsDir: NSTemporaryDirectory())
let skillRegistry = SkillRegistry()

print("自进化组件组装:")
print("  ✓ FactStore — 记忆存储")
print("  ✓ SkillUsageStore — 技能使用数据")
print("  ✓ SkillCuratorStore — 策展状态持久化")
print("  ✓ SkillRegistry — 技能注册表")
print()

// 展示 SkillCurator 配置
let curatorConfig = SkillCuratorConfig(
    staleAfterDays: 30,
    archiveAfterDays: 90
)
print("SkillCuratorConfig:")
print("  staleAfterDays: \(curatorConfig.staleAfterDays)")
print("  archiveAfterDays: \(curatorConfig.archiveAfterDays)")
print()

// 展示 ReviewScheduleConfig
let scheduleConfig = ReviewScheduleConfig(
    memoryReviewInterval: 20,
    skillReviewInterval: 30,
    minMessagesForReview: 10
)
print("ReviewScheduleConfig:")
print("  minMessagesForReview: \(scheduleConfig.minMessagesForReview)")
print("  memoryReviewInterval: \(scheduleConfig.memoryReviewInterval)")
print("  skillReviewInterval: \(scheduleConfig.skillReviewInterval)")
print()

// 展示 ReviewAgentConfig
let reviewAgentConfig = ReviewAgentConfig(
    reviewMemory: true,
    reviewSkills: true,
    maxTurns: 16
)
print("ReviewAgentConfig:")
print("  reviewMemory: \(reviewAgentConfig.reviewMemory)")
print("  reviewSkills: \(reviewAgentConfig.reviewSkills)")
print("  maxTurns: \(reviewAgentConfig.maxTurns)")
print("  allowedTools: \(reviewAgentConfig.allowedTools)")
print()

print("=== SelfEvolutionExample 完成 ===")
print()
print("提示：要运行完整的 LLM 驱动体验，需要配置 API Key 并使用")
print("  LLMExperienceExtractor(client: myLLMClient)")
print("  LLMSkillEvolver(client: myLLMClient)")
print("  IntelligentCurator + agent.execute(parentAgent:)")
