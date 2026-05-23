# Story 25.3: IntelligentCurator — LLM 驱动的策展执行器

Status: done

## Story

As a SDK developer,
I want the SDK to provide an LLM-driven intelligent curation executor,
so that application developers can invoke a single method to execute the full curation pipeline (mechanical state transitions + LLM intelligent curation).

## Acceptance Criteria

1. **AC1: `IntelligentCurator` struct in `Utils/`** — Create `Sources/OpenAgentSDK/Utils/IntelligentCurator.swift` containing a public `IntelligentCurator` struct. Dependencies (all injected via init):
   - `skillCurator: SkillCurator` — mechanical curation (Epic 22)
   - `factStore: FactStore` — review tool dependency
   - `skillRegistry: SkillRegistry` — skill library operations
   - `skillEvolver: any SkillEvolver` — review tool dependency
   - `usageStore: SkillUsageStore` — usage data + archive tool dependency
   - `curatorStore: SkillCuratorStore` — curator state persistence

2. **AC2: Two-phase `execute()` method** — `IntelligentCurator.execute(parentAgent: Agent, dryRun: Bool = false) async throws -> IntelligentCuratorResult`
   - **Phase 1 (mechanical):** Call `skillCurator.run()` for automatic lifecycle state transitions. In dry-run mode, `skillCurator` must already be configured with `dryRun: true` — the caller is responsible for creating a `SkillCurator` with appropriate config.
   - **Phase 2 (intelligent):** If the candidate list from `CuratorPromptBuilder.buildCandidateList()` contains candidates (i.e., returns something other than `"No agent-created skills to review."`), fork a curator agent and execute LLM curation. If no candidates exist, skip Phase 2 and return mechanical-only results.

3. **AC3: Curator agent fork configuration** — Fork the curator agent using `parentAgent.createReviewAgent(config:)` with a `ReviewAgentConfig` configured as:
   - `maxTurns: 200` (curation may require many rounds)
   - `reviewMemory: false` (curator reviews skills, not memories)
   - `reviewSkills: true`
   - `allowedTools`: the 5 review tools returned by `createReviewTools(factStore:skillRegistry:skillEvolver:usageStore:)`
   - The forked agent inherits the parent's model, LLM client (for prefix cache sharing), and runs in `bypassPermissions` mode (already enforced by `createReviewAgent`)

4. **AC4: Review schedule isolation** — The curator agent's `AgentOptions` must have `memoryReviewConfig: nil` and `reviewScheduleConfig: nil` to prevent recursive review triggers. This is already handled by `createReviewAgent()` (it nils out all stores, hooks, review configs). No additional action needed — verify this is the case.

5. **AC5: `IntelligentCuratorResult` type** — Define in the same file:
   ```swift
   public struct IntelligentCuratorResult: Sendable {
       public let mechanicalResult: CuratorRunResult
       public let llmResult: ReviewAgentResult?
       public let consolidations: [CuratorConsolidation]
       public let prunings: [CuratorPruning]
       public let durationMs: Int
       public let dryRun: Bool
       public let error: String?
   }

   public struct CuratorConsolidation: Sendable, Codable, Equatable {
       public let from: String
       public let into: String
       public let reason: String
   }

   public struct CuratorPruning: Sendable, Codable, Equatable {
       public let name: String
       public let reason: String
   }
   ```

6. **AC6: Structured output parsing** — After the LLM curation completes, parse the curator agent's output messages for the YAML structured summary block. Extract `consolidations` and `prunings` from the YAML block in the assistant's final text. Use simple string matching (find ```` ```yaml ```` block, parse `consolidations:` and `prunings:` sections). Do NOT add a YAML parsing library — use regex/string parsing.

7. **AC7: Dry-run support** — When `dryRun` is `true`:
   - Phase 1: The mechanical `SkillCurator` should already be configured with `dryRun: true` by the caller. The `IntelligentCurator` does NOT override the `SkillCurator`'s config.
   - Phase 2: Use `CuratorPromptBuilder.dryRunPrompt()` instead of `curationPrompt()`. The curator agent will read-only (no mutating tool calls per the dry-run prompt instructions).
   - Result: `IntelligentCuratorResult.dryRun = true`

8. **AC8: Error resilience** — If the LLM curation (Phase 2) fails (agent throws, API error, etc.):
   - The mechanical result from Phase 1 is still returned
   - `llmResult` is `nil`
   - `error` contains the failure description
   - `consolidations` and `prunings` are empty arrays

9. **AC9: No-candidate fast path** — When `buildCandidateList()` returns the "No agent-created skills to review." message, skip Phase 2 entirely. Return mechanical-only result with `llmResult = nil`, empty consolidations/prunings, and no error.

10. **AC10: Unit tests** — Create `Tests/OpenAgentSDKTests/Utils/IntelligentCuratorTests.swift`:
    - `testTwoPhaseExecution` — verify Phase 1 runs then Phase 2 runs
    - `testNoCandidateSkipsLLM` — no agent-created skills → only mechanical result
    - `testDryRunMode` — uses dryRunPrompt, result marked dryRun
    - `testPhase2ErrorResilience` — LLM phase fails, mechanical result preserved
    - `testCuratorAgentConfig` — verify maxTurns=200, reviewSkills=true, reviewMemory=false
    - `testParseConsolidationsFromYAML` — parse YAML block from text
    - `testParsePruningsFromYAML` — parse YAML block from text
    - `testParseEmptyYAML` — empty consolidations/prunings lists
    - All tests mock dependencies (SkillCurator, SkillUsageStore, SkillCuratorStore) — no I/O

11. **AC11: Build and test pass** — `swift build` with zero errors. Full test suite passes with zero regression (baseline: ~5,586 tests).

## Tasks / Subtasks

- [x] Task 1: Define `IntelligentCuratorResult`, `CuratorConsolidation`, `CuratorPruning` types (AC: #5)
  - [x] Add `IntelligentCuratorResult` struct with all fields
  - [x] Add `CuratorConsolidation` struct (from, into, reason)
  - [x] Add `CuratorPruning` struct (name, reason)

- [x] Task 2: Create `IntelligentCurator` struct (AC: #1, #2, #3, #4)
  - [x] Define init with all 6 dependencies
  - [x] Implement `execute(parentAgent:dryRun:) async throws -> IntelligentCuratorResult`
  - [x] Phase 1: call `skillCurator.run()`
  - [x] Phase 2: build candidate list, check for candidates, fork agent, execute
  - [x] Fork config: `ReviewAgentConfig(maxTurns: 200, reviewMemory: false, reviewSkills: true)`

- [x] Task 3: Implement YAML structured output parser (AC: #6)
  - [x] Private helper to extract YAML block from assistant text
  - [x] Parse `consolidations:` entries (from/into/reason)
  - [x] Parse `prunings:` entries (name/reason)
  - [x] Graceful fallback on parse failure (empty arrays, no crash)

- [x] Task 4: Implement dry-run support (AC: #7)
  - [x] Select prompt based on `dryRun` flag
  - [x] Pass dry-run through to result

- [x] Task 5: Implement error resilience (AC: #8, #9)
  - [x] Wrap Phase 2 in do/catch
  - [x] Return mechanical result on Phase 2 failure
  - [x] Fast-path when no candidates

- [x] Task 6: Unit tests (AC: #10)
  - [x] Create `Tests/OpenAgentSDKTests/Utils/IntelligentCuratorTests.swift`
  - [x] Test all scenarios (two-phase, no-candidate, dry-run, error, config, YAML parsing)

- [x] Task 7: Verify build and full test suite (AC: #11)
  - [x] `swift build` — 0 errors
  - [x] Full test suite — 0 regressions

## Dev Notes

### Architecture Compliance

- **New file in `Utils/`** — follows the same location as `ReviewAgentFactory.swift`, `SkillCurator.swift`, `CuratorPromptBuilder.swift`
- **Module boundary**: `Utils/` can depend on `Types/`, `API/`, `Stores/`, `Tools/`, and `Core/Agent` (via extensions like `ReviewAgentFactory`). `IntelligentCurator` depends on `Core/Agent` through `parentAgent.createReviewAgent()`.
- **`IntelligentCurator` is a `struct`** — it has no mutable state. All dependencies are injected via init. The `execute()` method is a pure function of its inputs. Follows the same pattern as `SkillCurator` (struct) and `ReviewOrchestrator` (struct).
- **No Apple-proprietary frameworks**: Foundation only (cross-platform).

### How IntelligentCurator.execute() Works

```
Input: parentAgent: Agent, dryRun: Bool
  |
  v
Phase 1: skillCurator.run() → CuratorRunResult (mechanical transitions)
  |
  v
Build candidate list: CuratorPromptBuilder.buildCandidateList(usageStore.allUsage())
  |
  +-- "No agent-created skills to review." → skip Phase 2, return mechanical-only
  |
  v
Phase 2: LLM Curation
  |
  +-- Select prompt: dryRun ? dryRunPrompt() : curationPrompt()
  +-- Build full prompt: curationPrompt + "\n\n---\n\n" + candidateList
  +-- Fork curator agent: parentAgent.createReviewAgent(config: ReviewAgentConfig(
  |      maxTurns: 200, reviewMemory: false, reviewSkills: true))
  +-- Inject review tools: createReviewTools(factStore, skillRegistry, skillEvolver, usageStore)
  +-- Execute: await curatorAgent.prompt(fullPrompt)
  +-- Parse YAML from assistant output → consolidations + prunings
  |
  v
Return: IntelligentCuratorResult(
    mechanicalResult, llmResult, consolidations, prunings, durationMs, dryRun, error)
```

### Key Design Decisions

1. **`execute()` takes `parentAgent: Agent`, not `AgentOptions`**: The curator agent must share the parent's `LLMClient` for prefix cache sharing. `createReviewAgent()` is an extension on `Agent` that handles all the configuration. We cannot create a review agent from options alone — we need the `Agent` instance to access its `client` and `cachedSystemPrompt`.

2. **`SkillCurator` is injected, not created internally**: The caller creates the `SkillCurator` with the desired `SkillCuratorConfig` (including `dryRun`). This follows dependency injection and lets the caller control the mechanical phase configuration independently. `IntelligentCurator` does NOT override the `SkillCurator`'s config.

3. **YAML parsing without a library**: Hermes outputs structured YAML in the curator's text response. We parse it with string matching (regex). This avoids adding a YAML dependency. The format is simple and predictable: `consolidations:` / `prunings:` with `- from: / into: / reason:` entries. Use `NSRegularExpression` or simple `split`/`contains` parsing.

4. **Review agent config reuses `createReviewAgent()`**: This already nils out stores, hooks, MCP, skills, memory review config, and review schedule config. We don't need to set these manually — just call `createReviewAgent()` with the right `ReviewAgentConfig`. This ensures isolation.

5. **`IntelligentCuratorResult` is separate from `CuratorRunReport`** (Story 25.4): The result type holds raw data. `CuratorRunReport` (next story) wraps this into a formatted report with `renderMarkdown()` and `renderYAML()`. Keep the result type simple and data-focused.

6. **Phase 2 prompt construction**: The full prompt to the curator agent is the curation prompt + candidate list. This matches how `ReviewOrchestrator.executeReview()` builds its prompt: review prompt + conversation context. The curator agent receives the curation prompt as its user message with the candidate list appended.

### Existing Patterns to Follow

- **`ReviewOrchestrator.executeReview()`** (`Utils/ReviewOrchestrator.swift:113-170`): Exact same pattern — fork agent, inject tools, execute, collect results. `IntelligentCurator.execute()` follows this same flow but with curator-specific config (200 turns, no memory review).

- **`SkillCurator.run()`** (`Utils/SkillCurator.swift:47-123`): Phase 1 of `IntelligentCurator` calls this directly. Understand its return type `CuratorRunResult` and how it iterates `allUsage()`.

- **`ReviewAgentFactory.createReviewAgent()`** (`Utils/ReviewAgentFactory.swift`): Extension on `Agent` that creates the forked agent. It already handles: sharing LLM client, nil-ing stores/hooks/review configs, bypassing permissions, using cached system prompt.

- **`CuratorPromptBuilder`** (`Utils/CuratorPromptBuilder.swift`): Provides `curationPrompt()`, `dryRunPrompt()`, and `buildCandidateList(usageData:)`. Call these to build the curator agent's prompt.

- **`createReviewTools()`** (`Tools/Review/ReviewTools.swift`): Creates the 5 review tools. Inject into the forked agent via `reviewAgent.options.tools = reviewTools`.

### Previous Story Learnings (Stories 25.1 & 25.2)

- **Build baseline**: 5,586 tests passing. Any regression check must match this baseline.
- **`reviewJSONResponse()` helper**: Available in `ReviewTools.swift` for building safe JSON response strings.
- **Swift 6.1 strict concurrency**: closures need explicit capture lists. `[String: Any]` dicts need `@unchecked Sendable` wrappers.
- **`precondition()` for config validation** — not `assert()`.
- **Logger**: Use `Logger.shared` for structured logging if needed.
- **Module boundary**: `Utils/` can depend on `Core/Agent` (via extensions) but must not replace Core's orchestration role.
- **`SkillUsageData` now has `absorbedInto: String?`**: Added in Story 25.2. Available on all usage data records.
- **`createReviewTools()` now takes `usageStore: SkillUsageStore`**: Updated in Story 25.2 to support CuratorArchiveTool. Signature: `createReviewTools(factStore:skillRegistry:skillEvolver:usageStore:)`.
- **Review agent already has `curator_archive_skill` in default `allowedTools`**: 5 tools total. No need to add it manually if using default `ReviewAgentConfig`.
- **Do not create mock-based E2E tests**: Per CLAUDE.md, E2E tests should use the real environment. For this story, unit tests with mocked dependencies are sufficient since the LLM curation path requires a real API key.

### Files Being Created/Modified

```
Sources/OpenAgentSDK/Utils/IntelligentCurator.swift       # NEW: IntelligentCurator + result types
Sources/OpenAgentSDK/Types/SkillEvolutionTypes.swift       # UPDATE: add CuratorConsolidation, CuratorPruning (or put them in IntelligentCurator.swift)

Tests/OpenAgentSDKTests/Utils/IntelligentCuratorTests.swift  # NEW: unit tests
```

**Note on type placement**: `CuratorConsolidation` and `CuratorPruning` are only used by `IntelligentCurator` and the future `CuratorRunReport` (Story 25.4). They can live in `IntelligentCurator.swift` for now. If Story 25.4 needs them in `Types/`, they can be moved then.

### Hermes Reference Mapping

```
Hermes curator.py                            SDK Implementation
───────────────────────────────────────────────────────────────────
run_curator_review() (L1369-1535)            IntelligentCurator.execute()
apply_automatic_transitions() (Phase 1)       skillCurator.run()
_run_llm_review() (L1623-1756)               Phase 2: fork agent + execute
max_iterations=9999 (L1702)                  maxTurns: 200 (lower — SDK tools are more focused)
quiet_mode=True (L1703)                      bypassPermissions + nil stores (handled by createReviewAgent)
skip_context_files=True (L1706)              systemPromptConfig = nil (handled by createReviewAgent)
skip_memory=True (L1707)                     memoryStore = nil (handled by createReviewAgent)
_memory_nudge_interval=0 (L1709)             memoryReviewConfig: nil (handled by createReviewAgent)
_skill_nudge_interval=0 (L1710)              reviewScheduleConfig: nil (handled by createReviewAgent)
_resolve_review_runtime() (L1671)            Inherits parent's model via createReviewAgent
curator_backup.snapshot_skills() (L1412)     Not implemented — archival is recoverable (retired state)
```

### Mocking Strategy for Tests

- **`SkillCurator`**: It's a struct. Create a test helper that builds one with mock stores (`SkillUsageStore` and `SkillCuratorStore` with in-memory data). For `testPhase2ErrorResilience`, the mock `SkillCurator` should return successfully but the `parentAgent` should fail on `prompt()`.
- **`SkillUsageStore`**: Actor. Use real `SkillUsageStore(skillsDir: nil)` which defaults to in-memory if no dir is provided, or create with a temp directory.
- **`SkillCuratorStore`**: Actor. Same approach — real store with temp dir.
- **`parentAgent`**: For unit tests that don't need LLM calls, mock the agent's `prompt()` by subclassing or using a test helper. For YAML parsing tests, no agent needed — test the parser directly.
- **`FactStore`**: Use real `FactStore` with temp dir.
- **`SkillRegistry`**: Use real `SkillRegistry` (it's a `final class` with in-memory storage).

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 25 — Story 25.3 definition: IntelligentCurator]
- [Source: /Users/nick/CascadeProjects/hermes-agent/agent/curator.py#L1369-1535 — run_curator_review() two-phase execution]
- [Source: /Users/nick/CascadeProjects/hermes-agent/agent/curator.py#L1623-1756 — _run_llm_review() fork AIAgent]
- [Source: /Users/nick/CascadeProjects/hermes-agent/agent/curator.py#L1691-1720 — fork agent configuration]
- [Source: Sources/OpenAgentSDK/Utils/ReviewAgentFactory.swift — createReviewAgent() pattern]
- [Source: Sources/OpenAgentSDK/Utils/ReviewOrchestrator.swift — executeReview() pattern to follow]
- [Source: Sources/OpenAgentSDK/Utils/SkillCurator.swift — SkillCurator.run() mechanical phase]
- [Source: Sources/OpenAgentSDK/Utils/CuratorPromptBuilder.swift — prompt building]
- [Source: Sources/OpenAgentSDK/Tools/Review/ReviewTools.swift — createReviewTools() 5 tools]
- [Source: Sources/OpenAgentSDK/Types/ReviewAgentTypes.swift — ReviewAgentConfig, ReviewAgentResult]
- [Source: Sources/OpenAgentSDK/Types/SkillEvolutionTypes.swift — CuratorRunResult, CuratorState]

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m]

### Debug Log References

### Completion Notes List

- Implemented `IntelligentCurator` struct with two-phase execute() method (mechanical + LLM curation)
- YAML structured output parser uses string matching (no YAML library dependency)
- Used `promptResult.text` as primary text source (fallback to message extraction) because `getMessages()` may not include assistant text in mock scenarios
- All 6 dependencies injected via init; `SkillCurator` is not overridden internally
- Fork config: `ReviewAgentConfig(maxTurns: 200, reviewMemory: false, reviewSkills: true)`
- Error resilience: Phase 2 failure returns mechanical-only result with error description
- No-candidate fast path skips Phase 2 when no agent-created skills exist
- 26 unit tests: YAML parsing (8), two-phase execution, no-candidate skip, dry-run, error resilience, agent config, result types, review isolation, codable round-trip, duration tracking, provenance filtering, edge cases

### File List

- `Sources/OpenAgentSDK/Utils/IntelligentCurator.swift` — NEW: IntelligentCurator + CuratorConsolidation + CuratorPruning + IntelligentCuratorResult
- `Tests/OpenAgentSDKTests/Utils/IntelligentCuratorTests.swift` — NEW: 15 unit tests

## Change Log

- 2026-05-24: Story 25.3 implementation complete — IntelligentCurator two-phase curation executor with YAML output parsing, dry-run support, error resilience, and 26 unit tests. 5,601 tests passing (0 regressions).
- 2026-05-24: Code review — 3 MEDIUM, 3 LOW findings. Fixed: added structured logging to execute(), set error on errorMaxTurns path, corrected test count in completion notes. 6,120 tests passing (0 regressions).

## Senior Developer Review (AI)

**Reviewer:** terryso (AI automated)
**Date:** 2026-05-24
**Outcome:** Approve (0 CRITICAL, 0 HIGH remaining)

### Findings Fixed

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| 1 | MEDIUM | No structured logging in execute() | Added Logger.shared.debug for phase1_start, no_candidates_fast_path, phase2_start, phase2_agent_failed, phase2_complete, phase2_error |
| 2 | MEDIUM | errorMaxTurns produces no error indicator — caller can't distinguish complete from truncated output | Set `error` field to descriptive warning when status is `.errorMaxTurns` |
| 3 | MEDIUM | Completion notes claim "15 unit tests" but file contains 26 | Updated to "26 unit tests" |

### Findings Deferred (LOW)

| # | Severity | Issue | Rationale |
|---|----------|-------|-----------|
| 4 | LOW | `parseYAMLSummary` is `static` (internal) not `private` | Required for direct testability; acceptable trade-off |
| 5 | LOW | `curatorStore` property stored but never directly accessed | Required by AC1 spec; may be needed by future stories |
| 6 | LOW | `do/catch` wraps non-throwing operations | Defensive; may catch future changes |
