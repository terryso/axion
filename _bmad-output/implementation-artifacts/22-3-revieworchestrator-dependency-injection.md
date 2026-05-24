# Story 22.3: ReviewOrchestrator 依赖注入

Status: done

## Story

As a 开发者,
I want ReviewOrchestrator 的依赖通过 AgentBuilder 正确注入,
So that review pipeline 在 Axion 的完整上下文中运行.

## Acceptance Criteria

1. **Given** AgentBuilder 构建 agent
   **When** 检查 ReviewOrchestrator 初始化
   **Then** orchestrator 的 factStore 指向 SDK `FactStore` 实例
   **And** orchestrator 的 skillRegistry 指向 SDK `SkillRegistry` 实例
   **And** orchestrator 的 skillEvolver 指向 `LLMSkillEvolver` 实例
   **And** orchestrator 的 usageStore 指向 `SkillUsageStore` 实例

2. **Given** ReviewOrchestrator 执行 review
   **When** createReviewTools() 创建工具
   **Then** 5 个 review 工具的依赖正确注入（factStore、skillRegistry、skillEvolver、usageStore）
   **And** review agent 可以成功调用这些工具

3. **Given** config.json 包含 review 配置
   **When** AgentBuilder 读取配置
   **Then** ReviewScheduleConfig 使用配置值（memoryReviewInterval、skillReviewInterval、minMessagesForReview、reviewModel）

## Tasks / Subtasks

- [x] Task 1: Verify and test dependency injection wiring (AC: #1, #2, #3)
  - [x] 1.1 Add test: `AgentBuilder.build()` creates non-nil `reviewOrchestrator` when memory enabled (verify via `AgentBuildResult`)
  - [x] 1.2 Add test: `ReviewScheduleConfig` uses `AxionConfig.reviewModel` when set, falls back to `"claude-haiku-4-5-20251001"` when nil
  - [x] 1.3 Add test: `FactStore(memoryDir:)` receives correct memory directory from AgentBuilder
  - [x] 1.4 Add test: `SkillUsageStore(skillsDir:)` receives correct skills directory from AgentBuilder
  - [x] 1.5 Add test: `ReviewOrchestrator` with all dependencies passes through to `createReviewTools()` — verify tool injection by checking tools are non-empty after construction

- [x] Task 2: Verify config.json integration end-to-end (AC: #3)
  - [x] 2.1 Add test: `AxionConfig` with custom review intervals produces matching `ReviewScheduleConfig` values
  - [x] 2.2 Add test: Default `ReviewScheduleConfig()` values match when `AxionConfig` review fields are nil

## Dev Notes

### CRITICAL: Most Wiring Already Complete

Stories 22.1 and 22.2 together wired ALL ReviewOrchestrator dependencies in `AgentBuilder.build()` (lines 262-291). The existing code:

```swift
// AgentBuilder.swift:262-291 — ALREADY IN PLACE
let reviewOrchestrator: ReviewOrchestrator?
if !buildConfig.noMemory, !buildConfig.dryrun {
    let scheduleConfig = ReviewScheduleConfig(
        memoryReviewInterval: config.reviewMemoryInterval ?? ReviewScheduleConfig().memoryReviewInterval,
        skillReviewInterval: config.reviewSkillInterval ?? ReviewScheduleConfig().skillReviewInterval,
        minMessagesForReview: config.reviewMinMessages ?? ReviewScheduleConfig().minMessagesForReview,
        reviewModel: config.reviewModel
    )
    let reviewFactStore = FactStore(memoryDir: memoryDir)
    let skillsDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("skills")
    let usageStore = SkillUsageStore(skillsDir: skillsDir)
    let evolverClient = AnthropicClient(apiKey: apiKey, baseURL: config.baseURL)
    let skillEvolver = LLMSkillEvolver(
        client: evolverClient,
        evolutionModel: config.reviewModel ?? "claude-haiku-4-5-20251001"
    )
    reviewOrchestrator = ReviewOrchestrator(
        scheduleConfig: scheduleConfig,
        factStore: reviewFactStore,
        skillRegistry: skillRegistry,
        skillEvolver: skillEvolver,
        usageStore: usageStore
    )
} else {
    reviewOrchestrator = nil
}
```

This story is primarily a **verification and test-hardening** story — confirm the wiring is correct and add any missing test coverage for the dependency injection specifics.

### Dependency Map

| Dependency | Type | Source | Init Location |
|------------|------|--------|---------------|
| `scheduleConfig` | `ReviewScheduleConfig` | SDK struct | Created from `AxionConfig` review fields |
| `factStore` | `FactStore` (SDK actor) | `OpenAgentSDK` | `FactStore(memoryDir: memoryDir)` |
| `skillRegistry` | `SkillRegistry` | SDK struct | Created earlier in `build()` for agent |
| `skillEvolver` | `LLMSkillEvolver` | SDK struct | `LLMSkillEvolver(client:evolutionModel:)` |
| `usageStore` | `SkillUsageStore` | SDK actor | `SkillUsageStore(skillsDir:)` |

### FactStore Architecture Decision

Review agent uses SDK's `FactStore` (not Axion's `AxionFactStore`). Both coexist:
- **`AxionFactStore`** — Axion 专有 Memory 层（scope/cause/evidence 字段，用于 RunMemoryProcessor）
- **SDK `FactStore`** — Review agent 标准 MemoryFact 存储（用于 `review_save_memory` 工具）

两者共享同一 `memoryDir`，但各自管理自己的文件。SDK `FactStore` 的 `review_save_memory` 写入的 MemoryFact 会被后续 `AxionFactStore` 读取时自动识别（两者都持久化为 JSON）。

### ReviewOrchestrator → createReviewTools() Flow

```
ReviewOrchestrator.executeReview(parentAgent:messages:config:)
  → parentAgent.createReviewAgent(config:)     // SDK: forks agent, shares LLMClient
  → createReviewTools(factStore:skillRegistry:skillEvolver:usageStore:)
     → review_save_memory (uses factStore)
     → review_update_skill (uses skillEvolver + skillRegistry)
     → review_read_facts (uses factStore)
     → review_save_experience (uses factStore)
     → review_list_skills (uses skillRegistry)
  → agent.prompt(reviewPrompt)
```

The 5 tools are created inside `ReviewOrchestrator.executeReview()`, using the dependencies we inject. No Axion code needed for tool creation — SDK handles everything.

### Existing Test Coverage

`RunOrchestratorReviewTests.swift` (301 lines) already covers:
- `shouldReview` gating logic (5 tests)
- dryrun/noMemory mode → `reviewOrchestrator == nil` (2 tests)
- Trace recording for review_completed/review_failed (2 tests)
- AxionConfig review fields Codable round-trip (3 tests)
- LLMSkillEvolver initialization (3 tests)
- MockSkillEvolver behavior (2 tests)

**Missing test coverage** to add:
- Verify `ReviewScheduleConfig` construction uses config values with fallback to defaults
- Verify `FactStore` and `SkillUsageStore` receive correct directory paths
- Verify the complete ReviewOrchestrator can be constructed with real SDK types (integration-level)

### Files to Verify / Update

| File | Action | Details |
|------|--------|---------|
| `Sources/AxionCLI/Services/AgentBuilder.swift` | **VERIFY** | Lines 262-291: confirm all 5 deps correctly injected |
| `Sources/AxionCLI/Services/RunOrchestrator.swift` | **VERIFY** | Lines 243-283: confirm review trigger uses orchestrator correctly |
| `Sources/AxionCore/Models/AxionConfig.swift` | **VERIFY** | Review config fields (reviewMemoryInterval, reviewSkillInterval, reviewMinMessages, reviewModel) |
| `Tests/AxionCLITests/Services/RunOrchestratorReviewTests.swift` | **UPDATE** | Add dependency injection verification tests |

### References

- [Source: AgentBuilder.swift:262-291] — ReviewOrchestrator dependency injection block
- [Source: RunOrchestrator.swift:243-283] — review trigger in post-run flow
- [Source: AxionConfig.swift:20-23] — review config fields with Codable support
- [Source: SDK ReviewOrchestrator.swift:57-72] — init signature and createReviewTools() call
- [Source: SDK FactStore.swift] — `actor FactStore`, `init(memoryDir:)`
- [Source: SDK SkillUsageStore.swift] — `actor SkillUsageStore`, `init(skillsDir:)`
- [Source: SDK LLMSkillEvolver.swift] — `init(client:evolutionModel:)`
- [Source: Story 22.2 dev notes] — LLMSkillEvolver wiring rationale (separate AnthropicClient)
- [Source: Architecture.md — Epic 22] — original story requirements

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

- Verified AgentBuilder.build() creates non-nil ReviewOrchestrator when memory enabled and dryrun disabled (test uses AXION_HELPER_PATH env override)
- Verified ReviewScheduleConfig uses AxionConfig.reviewModel when set, falls back to nil (LLMSkillEvolver falls back to "claude-haiku-4-5-20251001")
- Verified FactStore receives correct memoryDir and is functional (save/query round-trip)
- Verified SkillUsageStore receives correct skillsDir from AgentBuilder
- Verified ReviewOrchestrator exposes all 5 dependencies as public properties and createReviewTools() returns >= 5 tools
- Verified AxionConfig custom review intervals produce matching ReviewScheduleConfig values
- Verified default ReviewScheduleConfig values (4/6/4/nil) when AxionConfig review fields are nil
- All 1152 unit tests pass with 0 regressions

### File List

- `Tests/AxionCLITests/Services/RunOrchestratorReviewTests.swift` — Added 9 dependency injection verification tests

## Senior Developer Review (AI)

**Reviewer:** Nick (AI) on 2026-05-24
**Outcome:** Approved — 0 CRITICAL, 3 MEDIUM (all fixed), 2 LOW (all fixed)

### Findings & Fixes Applied

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| 1 | MEDIUM | `factStoreReceivesCorrectMemoryDir` wrote to real `~/.config/axion/memory` — test pollution risk | Switched to temp directory for FactStore writes; kept path assertion against real dir |
| 2 | MEDIUM | `reviewOrchestratorPassesThroughDependencies` used real directories for FactStore/SkillUsageStore | Switched to temp directories |
| 3 | MEDIUM | Completion Notes claimed 8 tests added but diff shows 9 | Corrected to 9 |
| 4 | LOW | `skillUsageStoreReceivesCorrectSkillsDir` had trivial `hasSuffix("skills")` assertion, used real dir | Replaced with exact path equality check + temp dir construction |
| 5 | LOW | `skillEvolverFallsBackToHaikuModel` hardcoded fallback string instead of testing nil-coalescing | Now replicates exact `config.reviewModel ?? "claude-haiku-4-5-20251001"` pattern from AgentBuilder |

### AC Validation

- AC #1 (dependency injection wiring): IMPLEMENTED — verified at AgentBuilder.swift:262-291
- AC #2 (5 review tools with correct deps): IMPLEMENTED — `createReviewTools()` returns >= 5 tools
- AC #3 (config.json integration): IMPLEMENTED — ReviewScheduleConfig uses AxionConfig fields with fallbacks

### Task Audit

All tasks marked [x] verified as complete. No false claims found.

### Change Log

- 2026-05-24: Story created
- 2026-05-24: Implementation completed (9 tests added)
- 2026-05-24: Review passed — 5 issues found and auto-fixed
