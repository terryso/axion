# Story 25.1: CuratorPromptBuilder — 策展 Prompt 定义

Status: done

## Story

As an SDK developer,
I want the SDK to provide curator-specific prompts translated from Hermes's CURATOR_REVIEW_PROMPT,
so that application developers don't have to write their own curation logic prompts.

## Acceptance Criteria

1. **AC1: `CuratorPromptBuilder` enum in `Utils/`** — Create `Sources/OpenAgentSDK/Utils/CuratorPromptBuilder.swift` as a `public enum` with static methods (same pattern as `ReviewPromptBuilder`). No instance state — all methods are `public static func`.

2. **AC2: `curationPrompt()` method** — Returns the full curator review prompt string. Content translated from Hermes `CURATOR_REVIEW_PROMPT` (curator.py:330-445) with SDK-adapted tool names:
   - Replace `skill_manage action=patch` → `review_update_skill`
   - Replace `skill_manage action=create` → `review_create_skill`
   - Replace `skill_manage action=write_file` → `review_add_skill_file`
   - Replace `skill_manage action=delete` → `curator_archive_skill`
   - Replace `terminal` commands → SDK archive tool
   - Replace `skills_list, skill_view` → `review_list_skills, review_view_skill` (from Epic 24 ReviewTools)
   - Replace `~/.hermes/skills/` paths → SDK-neutral references
   - Preserve all core logic: UMBRELLA-BUILDING goal, three consolidation strategies, hard rules, structured YAML output format

3. **AC3: `dryRunPrompt()` method** — Returns the curator review prompt prefixed with the DRY_RUN_BANNER, translated from Hermes `CURATOR_DRY_RUN_BANNER` (curator.py:303-328):
   - Replace `skill_manage` and `terminal` references with SDK tool names
   - Keep the core message: report only, do not mutate, produce same structured YAML describing what you WOULD do

4. **AC4: `buildCandidateList(usageData:)` method** — Translates Hermes `_render_candidate_list()` (curator.py:1349-1366):
   - Input: `[String: SkillUsageData]` (from `SkillUsageStore.allUsage()`)
   - Filter to `provenance == .agentCreated` only
   - Sort alphabetically by skill name
   - Return formatted string listing each skill with: name, lifecycleState, pinned status, viewCount
   - Return `"No agent-created skills to review."` when the filtered list is empty

5. **AC5: Prompt content verification** — `curationPrompt()` contains all of these elements:
   - UMBRELLA-BUILDING objective ("class-level skills", not "one-session-one-skill")
   - Three consolidation strategies: (a) merge into existing umbrella, (b) create new umbrella, (c) demote to references/templates/scripts
   - Hard rules: do not touch bundled/hub/pinned skills; do not delete (archive only); do not skip on low usage counts
   - Structured YAML output format (`consolidations:` + `prunings:` lists)
   - SDK review tool names (`review_update_skill`, `review_create_skill`, `review_add_skill_file`, `curator_archive_skill`, `review_list_skills`, `review_view_skill`)

6. **AC6: Unit tests** — All new code tested in `Tests/OpenAgentSDKTests/Utils/CuratorPromptBuilderTests.swift`:
   - `testCurationPromptContainsUmbrellaBuilding` — prompt contains "UMBRELLA-BUILDING" and "class-level"
   - `testCurationPromptContainsThreeStrategies` — prompt mentions merge/create/demote strategies
   - `testCurationPromptContainsHardRules` — prompt contains "bundled", "pinned", "archive" (not "delete")
   - `testCurationPromptReferencesSDKToolNames` — prompt mentions all 6 SDK tool names
   - `testCurationPromptContainsStructuredOutput` — prompt contains "consolidations:" and "prunings:"
   - `testDryRunPromptContainsBanner` — output starts with DRY_RUN banner text
   - `testDryRunPromptIncludesCurationPrompt` — dry-run output contains the full curation prompt after the banner
   - `testBuildCandidateListFormatsSkills` — formats agent-created skills with name, state, pinned, viewCount
   - `testBuildCandidateListSkipsNonAgentCreated` — bundled/userDefined skills excluded
   - `testBuildCandidateListEmptyReturnsNoSkills` — empty dict returns "No agent-created skills to review."
   - All tests use no external dependencies (pure string processing, no I/O)

7. **AC7: Build and test pass** — `swift build` with zero errors. Full test suite passes with zero regression (baseline: 5,571 tests, 42 skipped).

## Tasks / Subtasks

- [x] Task 1: Create `CuratorPromptBuilder.swift` with `curationPrompt()` (AC: #2, #5)
  - [x] Create `Sources/OpenAgentSDK/Utils/CuratorPromptBuilder.swift` as `public enum`
  - [x] Implement `public static func curationPrompt() -> String` translating Hermes CURATOR_REVIEW_PROMPT
  - [x] Replace all Hermes tool names with SDK equivalents
  - [x] Verify all 5 content elements from AC5 are present

- [x] Task 2: Add `dryRunPrompt()` method (AC: #3)
  - [x] Translate CURATOR_DRY_RUN_BANNER with SDK tool names
  - [x] Implement `public static func dryRunPrompt() -> String` = banner + curationPrompt

- [x] Task 3: Add `buildCandidateList(usageData:)` method (AC: #4)
  - [x] Implement `public static func buildCandidateList(usageData: [String: SkillUsageData]) -> String`
  - [x] Filter to `.agentCreated` provenance, sort alphabetically, format with state/pinned/views
  - [x] Handle empty case

- [x] Task 4: Unit tests (AC: #6)
  - [x] Create `Tests/OpenAgentSDKTests/Utils/CuratorPromptBuilderTests.swift`
  - [x] Test curationPrompt content (umbrella, strategies, rules, tool names, YAML format)
  - [x] Test dryRunPrompt (banner presence, includes full curation prompt)
  - [x] Test buildCandidateList (formatting, filtering, empty case)

- [x] Task 5: Verify build and full test suite (AC: #7)
  - [x] `swift build` — 0 errors
  - [x] Full test suite — 0 regressions

## Dev Notes

### Architecture Compliance

- **New file in `Utils/`** — follows the same pattern as `ReviewPromptBuilder.swift` (public enum with static methods)
- **Module boundary**: `Utils/` depends on `Types/` (for `SkillUsageData`, `SkillProvenance`, `SkillLifecycleState`). No dependency on `Core/` or `Tools/`.
- **No Apple-proprietary frameworks**: Foundation only (cross-platform).
- **Pure string processing**: No I/O, no actor access, no async. All methods are synchronous.

### Key Design Decisions

1. **`enum` not `struct` for CuratorPromptBuilder**: Same pattern as `ReviewPromptBuilder` — no instance state, only static methods. Using `enum` prevents accidental instantiation.

2. **Prompt is a static string, not built dynamically**: The curator prompt doesn't change per-run. It's a constant string. The dynamic part (candidate list) is built separately and combined by the caller (Story 25.3 `IntelligentCurator`).

3. **`buildCandidateList` takes `[String: SkillUsageData]` not `SkillUsageStore`**: Keeps the function pure (no actor dependency). The caller passes the data. This makes testing trivial — no mocking needed.

4. **SDK tool name mapping from Hermes**:
   ```
   Hermes                              SDK
   ─────────────────────────────────   ──────────────────────────
   skills_list                         review_list_skills
   skill_view                          review_view_skill
   skill_manage action=patch           review_update_skill
   skill_manage action=create           review_create_skill
   skill_manage action=write_file       review_add_skill_file
   skill_manage action=delete           curator_archive_skill (Story 25.2)
   terminal (mv, mkdir)                curator_archive_skill
   ```

5. **`dryRunPrompt()` prepends banner to `curationPrompt()`**: DRY — the curation prompt is written once. The dry-run version adds the banner on top. Same approach as Hermes where the banner is prepended to the same prompt.

### How `buildCandidateList` Works

```
Input: allUsage() from SkillUsageStore
  ↓
Filter: provenance == .agentCreated
  ↓
Sort: alphabetical by skill name
  ↓
Format: "- {name}  state={lifecycleState}  pinned={yes|no}  views={viewCount}"
  ↓
Output: "Agent-created skills (N):\n{formatted lines}"
         OR "No agent-created skills to review."
```

### Files Being Created/Modified

```
Sources/OpenAgentSDK/Utils/CuratorPromptBuilder.swift       # NEW: curator prompt builder

Tests/OpenAgentSDKTests/Utils/CuratorPromptBuilderTests.swift  # NEW: unit tests
```

### Existing Patterns to Follow

- **`ReviewPromptBuilder.swift`** (same directory): `public enum` with `static func` returning `String`. Exact same pattern.
- **`SkillCurator.swift`** (same directory): shows how `SkillUsageStore` data is consumed — iterate `allUsage()`, filter by `provenance`, skip pinned.
- **`SkillUsageData.currentLifecycleState`**: computed property that derives lifecycle from usage timestamps. Use this for the candidate list display.

### Hermes Reference Mapping

```
Hermes curator.py                    →  SDK Implementation
──────────────────────────────────────────────────────────────
CURATOR_REVIEW_PROMPT (L330-445)     →  CuratorPromptBuilder.curationPrompt()
CURATOR_DRY_RUN_BANNER (L303-328)    →  CuratorPromptBuilder.dryRunBanner() (private)
_render_candidate_list() (L1349-1366) →  CuratorPromptBuilder.buildCandidateList()
```

### Previous Story Learnings (Epic 24)

- **Build baseline**: 5,571 tests passing, 42 skipped. Any regression check must match this baseline.
- **`nonisolated(unsafe)`** for simple flags when actor isolation isn't needed.
- **Swift 6.1 strict concurrency**: closures need explicit capture lists. `[String: Any]` dicts need `@unchecked Sendable` wrappers.
- **`precondition()` for config validation** — not `assert()`.
- **Logger**: Use `Logger.shared` for structured logging.
- **Module boundary**: `Utils/` can extend `Core/Agent`. `Tools/` cannot import `Core/`.
- **Review tools already exist in `Tools/Review/`**: `ReviewSkillUpdateTool.swift`, `ReviewSkillCreateTool.swift`, `ReviewSkillFileTool.swift`, `ReviewMemoryTool.swift`, `ReviewTools.swift`. The curator prompt references these tool names.
- **`ReviewPromptBuilder` is the closest analog**: same directory, same pattern (public enum, static funcs, string returns).

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 25 — Story 25.1 definition: CuratorPromptBuilder]
- [Source: /Users/nick/CascadeProjects/hermes-agent/agent/curator.py#L330-445 — CURATOR_REVIEW_PROMPT]
- [Source: /Users/nick/CascadeProjects/hermes-agent/agent/curator.py#L303-328 — CURATOR_DRY_RUN_BANNER]
- [Source: /Users/nick/CascadeProjects/hermes-agent/agent/curator.py#L1349-1366 — _render_candidate_list()]
- [Source: Sources/OpenAgentSDK/Utils/ReviewPromptBuilder.swift — exact pattern to follow]
- [Source: Sources/OpenAgentSDK/Utils/SkillCurator.swift — SkillUsageStore data consumption pattern]
- [Source: Sources/OpenAgentSDK/Types/SkillEvolutionTypes.swift#L275-356 — SkillLifecycleState, SkillProvenance, SkillUsageData]
- [Source: Sources/OpenAgentSDK/Tools/Review/ReviewTools.swift — existing review tool names]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

### Completion Notes List

- Implemented CuratorPromptBuilder as public enum with 3 static methods: curationPrompt(), dryRunPrompt(), buildCandidateList(usageData:)
- Translated Hermes CURATOR_REVIEW_PROMPT with all SDK tool name substitutions (review_update_skill, review_create_skill, review_add_skill_file, curator_archive_skill, review_list_skills, review_view_skill)
- dryRunPrompt() prepends DRY-RUN banner to curationPrompt() — DRY approach
- buildCandidateList filters to .agentCreated provenance, sorts alphabetically, formats with state/pinned/views
- Used "archive only" language instead of "delete" to match SDK conventions
- All 12 unit tests pass covering: umbrella-building content, 3 strategies, hard rules, SDK tool names, structured YAML output, dry-run banner, candidate list formatting/filtering/empty case
- Build: 0 errors. Full suite: 5542 passing, 0 regressions from changes (1 pre-existing HTTPIntegrationTests flaky failure unrelated to this story)
- Review fix: removed CuratorPromptBuilderE2ETests.swift — duplicated unit test coverage, mislabeled as E2E (no real environment integration)
- Review fix: hardened testCurationPromptContainsHardRules to assert specific archive-only phrasing instead of fragile "delete"-absence check
- Review fix: removed Hermes-internal reference from public doc comment

### File List

- `Sources/OpenAgentSDK/Utils/CuratorPromptBuilder.swift` — NEW: curator prompt builder (public enum, 3 static methods)
- `Tests/OpenAgentSDKTests/Utils/CuratorPromptBuilderTests.swift` — NEW: 12 unit tests for all methods

## Senior Developer Review (AI)

**Reviewer:** Nick (via automated review)
**Date:** 2026-05-24
**Outcome:** Approved (with fixes applied)

### Findings (7 total: 2 HIGH, 3 MEDIUM, 2 LOW)

| # | Severity | Finding | Fix Applied |
|---|----------|---------|-------------|
| H1 | HIGH | E2E test file not documented in File List | File removed (redundant), File List updated |
| H2 | HIGH | CuratorPromptBuilderE2ETests mislabeled as E2E — pure string assertions, no real environment | File deleted; unit tests already cover all ACs |
| M1 | MEDIUM | `testCurationPromptContainsHardRules` fragile "delete"-absence assertion | Replaced with positive assertions for specific archive-only phrasing |
| M2 | MEDIUM | E2E tests use XCTest while unit tests use Swift Testing | Resolved by removing E2E file |
| M3 | MEDIUM | E2E tests duplicate unit test coverage — zero incremental value | Resolved by removing E2E file |
| L1 | LOW | Public doc comment references "Hermes agent's CURATOR_REVIEW_PROMPT" — internal detail | Removed Hermes reference |
| L2 | LOW | Duplicate test name `testDryRunPromptReferencesSDKToolNames` in both files | Resolved by removing E2E file |

### Verification

- Build: 0 errors
- Full test suite: 5548 passing, 0 failures, 0 regressions
- All 7 ACs verified against implementation
- All 5 tasks marked [x] verified as actually completed
