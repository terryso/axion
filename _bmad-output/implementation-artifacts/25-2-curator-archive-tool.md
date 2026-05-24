# Story 25.2: CuratorArchiveTool — 策展专用归档工具

Status: done

## Story

As a curator agent,
I want a tool that can archive skills and record merge relationships,
so that archival is traceable — every archived skill has a record explaining where its content went.

## Acceptance Criteria

1. **AC1: `CuratorArchiveTool` in `Tools/Review/`** — Create `Sources/OpenAgentSDK/Tools/Review/CuratorArchiveTool.swift` containing a factory function `createCuratorArchiveTool(skillRegistry:usageStore:)` that returns a `ToolProtocol`. Tool name: `curator_archive_skill`. Follow the exact same pattern as the other review tools (private Codable input struct, `defineTool` with `reviewJSONResponse`, factory function).

2. **AC2: Input schema** — Two parameters:
   - `skillName` (required, string): Name of the skill to archive
   - `absorbedInto` (optional, string): Name of the umbrella skill that absorbed this skill's content. Empty string means pruning with no merge target. Omitting it also means pruning (backward compat).

3. **AC3: Provenance guard** — If the skill's usage data shows `provenance != .agentCreated`, return `{"success": false, "error": "Cannot archive non-agent-created skill"}`. If no usage data exists for the skill, treat provenance as unknown and reject with the same error.

4. **AC4: Pinned guard** — If the skill's usage data shows `pinned == true`, return `{"success": false, "error": "Cannot archive pinned skill"}`.

5. **AC5: Archive action** — On successful validation:
   - Look up the skill in `SkillRegistry.find(skillName)`. If not found, return `{"success": false, "error": "Skill '<name>' not found"}`
   - Create a new `Skill` with the same fields but `lifecycleState: .retired`, then call `skillRegistry.replace()` to update it
   - Update `SkillUsageData.lastManagedAt` to `Date()` via `usageStore.setUsage()`
   - Return `{"success": true, "message": "Skill '<name>' archived", "absorbedInto": "<value or null>"}`

6. **AC6: `absorbedInto` tracking** — The tool records the `absorbedInto` value in the `SkillUsageData.metadata` field. Since `SkillUsageData` does not currently have an `absorbedInto` field, store it using the existing metadata mechanism: add an `absorbedInto: String?` field to `SkillUsageData` (new optional property, defaults to `nil`). On archive, set `absorbedInto` to the provided value (or `nil` if empty/omitted). This field survives serialization because `SkillUsageData` is `Codable`.

7. **AC7: Integration with `createReviewTools`** — Add `createCuratorArchiveTool` to the `createReviewTools()` function in `ReviewTools.swift`, making it the 5th tool in the curator toolkit. It requires `skillRegistry` and `usageStore` as dependencies. Update the function signature to accept `usageStore: SkillUsageStore`.

8. **AC8: Unit tests** — Create `Tests/OpenAgentSDKTests/Tools/Review/CuratorArchiveToolTests.swift`:
   - `testArchiveSuccess` — archives agent-created skill, verifies lifecycle becomes `.retired`
   - `testArchiveWithAbsorbedInto` — archives with merge target, verifies `absorbedInto` recorded
   - `testArchiveWithoutAbsorbedInto` — archives with empty/nil `absorbedInto`, verifies pruning
   - `testRejectsNonAgentCreated` — bundled skill returns error
   - `testRejectsPinned` — pinned skill returns error
   - `testRejectsNonExistentSkill` — non-existent skill returns "not found" error
   - `testRejectsEmptySkillName` — empty skillName returns validation error
   - All tests mock `SkillUsageStore` (actor) and `SkillRegistry` (class) — no I/O

9. **AC9: Build and test pass** — `swift build` with zero errors. Full test suite passes with zero regression (baseline: ~5,548 tests).

## Tasks / Subtasks

- [x] Task 1: Add `absorbedInto` field to `SkillUsageData` (AC: #6)
  - [x] Add `public var absorbedInto: String?` property to `SkillUsageData` in `SkillEvolutionTypes.swift`
  - [x] Default to `nil` in init, include in Codable conformance (already synthesized)

- [x] Task 2: Create `CuratorArchiveTool.swift` (AC: #1, #2, #3, #4, #5)
  - [x] Create `Sources/OpenAgentSDK/Tools/Review/CuratorArchiveTool.swift`
  - [x] Define private `CuratorArchiveInput: Codable` with `skillName` and `absorbedInto`
  - [x] Implement `createCuratorArchiveTool(skillRegistry:usageStore:)` factory function
  - [x] Validate provenance guard (agentCreated only)
  - [x] Validate pinned guard (reject pinned)
  - [x] On success: replace skill with `.retired` lifecycle, update usage data with `absorbedInto`

- [x] Task 3: Update `createReviewTools` function (AC: #7)
  - [x] Add `usageStore: SkillUsageStore` parameter to `createReviewTools()` in `ReviewTools.swift`
  - [x] Add `createCuratorArchiveTool` as 5th tool in the returned array

- [x] Task 4: Unit tests (AC: #8)
  - [x] Create `Tests/OpenAgentSDKTests/Tools/Review/CuratorArchiveToolTests.swift`
  - [x] Test success path, merge target, pruning, guards, not found, empty name

- [x] Task 5: Update callers of `createReviewTools` (AC: #7, #9)
  - [x] Find all callers of `createReviewTools()` and add `usageStore` parameter
  - [x] Verify build passes

- [x] Task 6: Verify build and full test suite (AC: #9)
  - [x] `swift build` — 0 errors
  - [x] Full test suite — 0 regressions

## Dev Notes

### Architecture Compliance

- **New file in `Tools/Review/`** — follows the same pattern as `ReviewSkillUpdateTool.swift`, `ReviewSkillCreateTool.swift`, `ReviewSkillFileTool.swift`
- **Module boundary**: `Tools/Review/` depends on `Types/` (for `SkillUsageData`, `SkillProvenance`, `SkillLifecycleState`) and `Stores/` (for `SkillUsageStore`) and `Tools/` (for `SkillRegistry`, `defineTool`). No dependency on `Core/`.
- **No Apple-proprietary frameworks**: Foundation only (cross-platform).
- **Factory function pattern**: All review tools use `public func createXxxTool(...) -> ToolProtocol` returning a `defineTool` closure. No struct/class conforming to `ToolProtocol` — just the free function + private input struct.

### Key Design Decisions

1. **`absorbedInto` as a new field on `SkillUsageData`**: Hermes stores `absorbed_into` at the point of deletion. Adding it as a field on `SkillUsageData` keeps the data model clean and queryable. It's optional (`String?`) — `nil` means never archived, non-nil with value means consolidated, non-nil with empty string means pruned.

2. **Tool does NOT delete skill files**: The hard rule from Hermes is "DO NOT delete any skill. Archiving is the maximum destructive action." The tool sets `lifecycleState` to `.retired` and records the merge relationship. The skill definition remains in the registry but is effectively inactive.

3. **`Skill` is a struct (value type)**: To update lifecycle state, we create a new `Skill` with the same fields but `lifecycleState: .retired`, then call `skillRegistry.replace()`. `Skill` doesn't have a mutable `lifecycleState` — it's set at construction time via the `Skill` struct's stored property.

4. **Provenance check uses `SkillUsageStore`, not `Skill`**: The `Skill` struct itself doesn't carry provenance info. Provenance lives in `SkillUsageData`. If no usage data exists for a skill name, the tool rejects it (unknown provenance = not safe to archive).

5. **Factory function takes `skillRegistry` + `usageStore`**: These are the two dependencies needed. `skillRegistry` for find/replace, `usageStore` for provenance check and absorbedInto recording.

### How CuratorArchiveTool Works

```
Input: skillName, absorbedInto (optional)
  |
  v
Validate: skillName not empty
  |
  v
Lookup: usageStore.getUsage(skillName)
  |
  +-- provenance != .agentCreated --> error: "Cannot archive non-agent-created skill"
  +-- pinned == true               --> error: "Cannot archive pinned skill"
  |
  v
Lookup: skillRegistry.find(skillName)
  |
  +-- nil --> error: "Skill '<name>' not found"
  |
  v
Replace: skill with lifecycleState = .retired
  |
  v
Update: usageData.absorbedInto = absorbedInto, lastManagedAt = now
  |
  v
Return: {"success": true, "message": "Skill '<name>' archived", "absorbedInto": <value|null>}
```

### Files Being Created/Modified

```
Sources/OpenAgentSDK/Types/SkillEvolutionTypes.swift           # UPDATE: add absorbedInto field to SkillUsageData
Sources/OpenAgentSDK/Tools/Review/CuratorArchiveTool.swift     # NEW: curator archive tool
Sources/OpenAgentSDK/Tools/Review/ReviewTools.swift            # UPDATE: add usageStore param, add 5th tool

Tests/OpenAgentSDKTests/Tools/Review/CuratorArchiveToolTests.swift  # NEW: unit tests
```

### Existing Patterns to Follow

- **`ReviewSkillUpdateTool.swift`** (same directory): exact same pattern — private Codable input struct, `defineTool` with `reviewJSONResponse`, factory function. The archive tool is simpler (no evolution pipeline, no LLM call).

- **`ReviewSkillCreateTool.swift`** (same directory): shows the simplest pattern — validate inputs, do the operation, return JSON response. CuratorArchiveTool follows this more closely.

- **`SkillCurator.swift`** (`Utils/`): shows how to iterate `allUsage()`, filter by `provenance`, check `pinned`, and update usage data. The archive tool reuses these same guards.

- **`SkillUsageStore`**: actor with `getUsage()`, `setUsage()`, `allUsage()`. The archive tool calls `getUsage()` for guards and `setUsage()` to persist the `absorbedInto` field.

- **`SkillRegistry`**: `final class` with `find()`, `replace()`. The archive tool calls `find()` to get the skill, creates a new copy with `.retired` lifecycle, then calls `replace()`.

### Skill Struct and lifecycleState

The `Skill` struct has an optional `lifecycleState: SkillLifecycleState?` property. To archive a skill:
```swift
let archived = Skill(
    name: skill.name,
    description: skill.description,
    aliases: skill.aliases,
    userInvocable: skill.userInvocable,
    toolRestrictions: skill.toolRestrictions,
    modelOverride: skill.modelOverride,
    promptTemplate: skill.promptTemplate,
    whenToUse: skill.whenToUse,
    argumentHint: skill.argumentHint,
    baseDir: skill.baseDir,
    supportingFiles: skill.supportingFiles,
    lifecycleState: .retired
)
skillRegistry.replace(archived)
```

### Hermes Reference Mapping

```
Hermes curator.py                           SDK Implementation
───────────────────────────────────────────────────────────────────
skill_manage action=delete (L408-412)       CuratorArchiveTool (curator_archive_skill)
absorbed_into parameter (L409-411)          SkillUsageData.absorbedInto field
"DO NOT delete any skill" rule (L350)       lifecycleState → .retired (no file deletion)
_extract_absorbed_into_declarations (L695)   CuratorArchiveTool records absorbedInto at archive time
```

### Previous Story Learnings (Story 25.1)

- **Build baseline**: 5,548 tests passing. Any regression check must match this baseline.
- **`reviewJSONResponse()` helper**: Available in `ReviewTools.swift` for building safe JSON response strings. Use it for all tool responses.
- **`nonisolated(unsafe)`** for simple test flags when actor isolation isn't needed.
- **Swift 6.1 strict concurrency**: closures need explicit capture lists. `[String: Any]` dicts need `@unchecked Sendable` wrappers.
- **`precondition()` for config validation** — not `assert()`.
- **Logger**: Use `Logger.shared` for structured logging if needed.
- **Module boundary**: `Tools/` cannot import `Core/`.
- **Review tools pattern**: All use factory functions returning `ToolProtocol`, private Codable input structs, `defineTool` + `reviewJSONResponse`.
- **`SkillUsageData` is `Codable`**: Adding a new optional field with default `nil` is backward-compatible — existing serialized data decodes fine (optional fields decode as `nil` when absent).

### Callers of `createReviewTools` to Update

Search for `createReviewTools(` to find all call sites that need the new `usageStore` parameter. Known caller: `ReviewOrchestrator.swift` in `Utils/`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 25 — Story 25.2 definition: CuratorArchiveTool]
- [Source: /Users/nick/CascadeProjects/hermes-agent/agent/curator.py#L408-412 — skill_manage action=delete with absorbed_into]
- [Source: /Users/nick/CascadeProjects/hermes-agent/agent/curator.py#L350 — "DO NOT delete any skill" hard rule]
- [Source: /Users/nick/CascadeProjects/hermes-agent/agent/curator.py#L695-746 — _extract_absorbed_into_declarations()]
- [Source: Sources/OpenAgentSDK/Tools/Review/ReviewSkillUpdateTool.swift — exact pattern to follow]
- [Source: Sources/OpenAgentSDK/Tools/Review/ReviewSkillCreateTool.swift — simplest review tool pattern]
- [Source: Sources/OpenAgentSDK/Tools/Review/ReviewTools.swift — createReviewTools() to update]
- [Source: Sources/OpenAgentSDK/Types/SkillEvolutionTypes.swift#L300-356 — SkillUsageData, SkillProvenance, SkillLifecycleState]
- [Source: Sources/OpenAgentSDK/Stores/SkillUsageStore.swift — usage store API]
- [Source: Sources/OpenAgentSDK/Tools/SkillRegistry.swift — find(), replace(), register()]

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m]

### Debug Log References

- Fixed actor isolation error: `usageStore.setUsage()` required `await` keyword since `SkillUsageStore` is an actor
- Fixed test argument order: `pinned` must precede `provenance` in `SkillUsageData` init
- Updated 7 test files that hardcoded 4-tool `allowedTools` arrays to include `curator_archive_skill`

### Completion Notes List

- Added `absorbedInto: String?` optional field to `SkillUsageData` with `nil` default — backward compatible with existing serialized data
- Created `CuratorArchiveTool.swift` following the exact `ReviewSkillCreateTool` pattern: private Codable input, `defineTool` + `reviewJSONResponse`, factory function
- Implemented provenance guard (rejects non-agentCreated), pinned guard (rejects pinned), empty name validation, and not-found guard
- Archive action creates a new `Skill` copy with `lifecycleState: .retired`, updates `absorbedInto` and `lastManagedAt` on usage data
- Updated `createReviewTools()` signature to accept `usageStore: SkillUsageStore`, added 5th tool
- Updated `ReviewOrchestrator` init to accept and store `usageStore` parameter
- Updated `ReviewAgentConfig.allowedTools` default to include `curator_archive_skill` (5 tools)
- Updated `Agent.swift` to pass `SkillUsageStore()` when constructing `ReviewOrchestrator`
- Updated all test callers: ReviewToolsTests, ReviewToolsE2ETests, ReviewOrchestratorTests, ReviewOrchestratorE2ETests, ReviewAgentTypesTests, ReviewAgentFactoryTests, ReviewAgentE2ETests
- 8 unit tests in CuratorArchiveToolTests covering all AC8 scenarios
- Build: 0 errors. Tests: 5,579 pass, 0 failures (baseline: 5,548)

### File List

- Sources/OpenAgentSDK/Types/SkillEvolutionTypes.swift (modified: added `absorbedInto` field to `SkillUsageData`)
- Sources/OpenAgentSDK/Tools/Review/CuratorArchiveTool.swift (new: archive tool implementation)
- Sources/OpenAgentSDK/Tools/Review/ReviewTools.swift (modified: added `usageStore` param, 5th tool)
- Sources/OpenAgentSDK/Types/ReviewAgentTypes.swift (modified: added `curator_archive_skill` to default `allowedTools`)
- Sources/OpenAgentSDK/Utils/ReviewOrchestrator.swift (modified: added `usageStore` property and param)
- Sources/OpenAgentSDK/Core/Agent.swift (modified: pass `SkillUsageStore()` to `ReviewOrchestrator`)
- Tests/OpenAgentSDKTests/Tools/Review/CuratorArchiveToolTests.swift (new: 8 unit tests)
- Tests/OpenAgentSDKTests/Tools/Review/ReviewToolsTests.swift (modified: updated for 5 tools + usageStore)
- Tests/OpenAgentSDKTests/Tools/Review/ReviewToolsE2ETests.swift (modified: added usageStore to makeToolSet)
- Tests/OpenAgentSDKTests/Utils/ReviewOrchestratorTests.swift (modified: added usageStore to makeOrchestrator)
- Tests/OpenAgentSDKTests/Utils/ReviewAgentTypesTests.swift (modified: updated allowedTools assertion)
- Tests/OpenAgentSDKTests/Utils/ReviewAgentFactoryTests.swift (modified: updated allowedTools assertion)
- Tests/OpenAgentSDKTests/Utils/ReviewAgentE2ETests.swift (modified: updated allowedTools assertions)
- Sources/E2ETest/ReviewOrchestratorE2ETests.swift (modified: added usageStore to 3 ReviewOrchestrator constructions)

### Change Log

- 2026-05-24: Implemented CuratorArchiveTool — 5th review tool for skill archival with merge tracking. Added `absorbedInto` field to `SkillUsageData`. Updated all callers of `createReviewTools` and `ReviewOrchestrator` for new `usageStore` dependency. 5,579 tests passing.
- 2026-05-24: **Code review fixes** (3 MEDIUM issues auto-fixed):
  - M1: Replaced `try?` on `usageStore.setUsage()` with `do/catch` returning error JSON on disk write failure (`CuratorArchiveTool.swift:79`)
  - M2: Added "archived" keyword to `summarizeActions` so archive actions appear in review summaries (`ReviewOrchestrator.swift:216`)
  - M3: Updated `createReviewTools` doc comment to document `usageStore` parameter and list all 5 tool names (`ReviewTools.swift:14`)
  - Added `testSummarizeActionsExtractsArchivedMessages` test. 5,586 tests passing.