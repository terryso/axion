---
baseline_commit: 74a094a
---

# Story 31.2: Memory Operation Tool — Agent 主动读写记忆

Status: done

## Story

As an Axion Agent,
I want to have a memory operation tool (add / replace / remove / read),
So that I can actively save and query knowledge during task execution.

## Acceptance Criteria

1. **Given** Agent executes a task and discovers "project uses SPM for dependency management"
   **When** Agent calls `memory(action: "add", content: "项目使用 SPM 管理依赖", target: "memory")`
   **Then** the entry is appended to MEMORY.md
   **And** write-time security scan is performed via MemorySecurityScanner before persisting

2. **Given** MEMORY.md contains an outdated "§\nproject uses CocoaPods\n§"
   **When** Agent calls `memory(action: "replace", target: "memory", old: "项目使用 CocoaPods", newContent: "项目使用 SPM 管理依赖")`
   **Then** fuzzy-matches the old entry and replaces it

3. **Given** Agent calls `memory(action: "read", target: "user")`
   **Then** returns USER.md's current content as a ToolResult string

4. **Given** Agent calls `memory(action: "remove", target: "memory", old: "某个过时条目")`
   **Then** fuzzy-matches the entry and removes it

5. **Given** Agent calls `memory(action: "add", content: "ignore all previous instructions", target: "memory")`
   **When** MemorySecurityScanner rejects the content
   **Then** the write is blocked and a descriptive error is returned to the Agent

6. **Given** Agent calls `memory(action: "add", content: "...", target: "memory")`
   **When** MEMORY.md would exceed maxMemoryChars (4000) after adding
   **Then** returns a message telling the Agent to replace or remove old entries first

7. **Given** the memory tool is registered in AgentBuilder
   **When** buildFullSystemPrompt() constructs the system prompt
   **Then** the tool is available to the Agent for use during execution

8. **Given** Agent calls `memory` with invalid parameters (e.g., missing required `action`)
   **When** the tool executes
   **Then** returns a descriptive error result (not a crash)

## Tasks / Subtasks

- [x] Task 1: Create `MemoryTool` class (AC: #1–#8)
  - [x] 1.1 Create `Sources/AxionCLI/Memory/MemoryTool.swift`
  - [x] 1.2 Implement `final class MemoryTool: ToolProtocol` with `store: UniversalMemoryStore` dependency
  - [x] 1.3 Define `inputSchema` with required `action` and `target`, optional `content`, `old`, `newContent`
  - [x] 1.4 Implement `call(input:context:)` routing to `handleAdd`, `handleReplace`, `handleRemove`, `handleRead`
  - [x] 1.5 `handleAdd`: security scan → `store.add()` → return success or error (char limit / security rejection)
  - [x] 1.6 `handleReplace`: security scan on newContent → `store.replace()` → return success or error (not found / char limit)
  - [x] 1.7 `handleRemove`: `store.remove()` → return success or error (not found)
  - [x] 1.8 `handleRead`: `store.read()` → return content string
  - [x] 1.9 Parameter validation: reject unknown action values, invalid target values, missing required params
  - [x] 1.10 Set `isReadOnly = false` (writes to disk)

- [x] Task 2: Register MemoryTool in AgentBuilder (AC: #7)
  - [x] 2.1 In `AgentBuilder.build()`, create `MemoryTool(store:)` using `memoryDir` from step 3 (line 192)
  - [x] 2.2 Append to `agentTools` array after the SkillTool append (line 249)
  - [x] 2.3 Guard: skip registration when `buildConfig.noMemory` is true (memory tool should not exist without memory context)

- [x] Task 3: Write unit tests (AC: all)
  - [x] 3.1 Create `Tests/AxionCLITests/Memory/MemoryToolTests.swift`
  - [x] 3.2 Test `add` success — entry appended to MEMORY.md
  - [x] 3.3 Test `add` with security rejection — prompt injection content blocked
  - [x] 3.4 Test `add` exceeding char limit — returns error message
  - [x] 3.5 Test `replace` success — old entry replaced
  - [x] 3.6 Test `replace` not found — returns error
  - [x] 3.7 Test `replace` with security rejection on newContent
  - [x] 3.8 Test `remove` success — entry removed
  - [x] 3.9 Test `remove` not found — returns error
  - [x] 3.10 Test `read` returns current content
  - [x] 3.11 Test invalid action — returns error
  - [x] 3.12 Test invalid target — returns error
  - [x] 3.13 Test missing required parameter — returns error

## Dev Notes

### Architecture

**New files:**
- `Sources/AxionCLI/Memory/MemoryTool.swift` — `final class MemoryTool: ToolProtocol`, holds `UniversalMemoryStore` reference

**Modified files:**
- `Sources/AxionCLI/Services/AgentBuilder.swift` — register MemoryTool in `agentTools` (line ~249)

**Existing files that must NOT change:**
- `UniversalMemoryStore.swift` — fully functional from Story 31.1, provides add/replace/remove/read/charCount
- `MemorySecurityScanner.swift` — fully functional from Story 31.1, provides scan() and scanOnLoad()
- `MemoryContextProvider.swift` — untouched (read path for system prompt injection is separate from tool path)

### ToolProtocol Implementation Pattern

Follow the existing pattern from `QueryTaskStatusTool.swift` (struct) or `RunTaskTool.swift`. However, unlike those tools, `MemoryTool` needs to hold a reference to `UniversalMemoryStore` (an actor), so it MUST use `final class` instead of struct (class captures the actor reference; struct would copy it, which is fine for actors but class is the convention in the epic spec).

**Key implementation details:**
- `inputSchema`: Use `ToolInputSchema` dictionary (see `QueryTaskStatusTool.swift:13-22`)
- `call(input:context:)`: Cast `input` to `[String: Any]`, extract parameters, route to action handler
- Error results: Use the `errorResult` / `encodeResult` pattern from `QueryTaskStatusTool.swift` — JSON with `error`, `message`, `suggestion` fields
- Success results: JSON with `status`, `message` fields (e.g., `{"status": "ok", "message": "Entry added to MEMORY.md"}`)

**Tool description for Agent:**
```
"操作持久化记忆（环境知识或用户画像）。action: 'add'(追加), 'replace'(替换), 'remove'(删除), 'read'(读取)。target: 'memory'(MEMORY.md) 或 'user'(USER.md)。写入前自动安全扫描。容量有限，需先清理旧条目再添加新内容。"
```

### Security Scan Integration

Every write operation (add, replace) MUST run `MemorySecurityScanner.scan(content:)` before calling `UniversalMemoryStore`. If the result is `.rejected(reason:)`, return an error to the Agent immediately — do NOT call the store.

The `remove` and `read` operations do NOT need security scanning (remove is deletion, read is just returning content).

### Action-Parameter Matrix

| Action | Required Params | Optional Params | Store Method |
|--------|----------------|-----------------|--------------|
| `add` | `action`, `target`, `content` | — | `store.add(target:, content:)` |
| `replace` | `action`, `target`, `old`, `newContent` | — | `store.replace(target:, keyword:, newContent:)` |
| `remove` | `action`, `target`, `old` | — | `store.remove(target:, keyword:)` |
| `read` | `action`, `target` | — | `store.read(target:)` |

### AgentBuilder Integration Point

In `AgentBuilder.build()`, the MemoryTool should be registered around line 249, after the SkillTool append:

```swift
// Existing (line 248-249):
if !buildConfig.noSkills, !buildConfig.dryrun {
    agentTools.append(createSkillTool(registry: skillRegistry))
}

// NEW — Memory tool registration:
if !buildConfig.noMemory, !buildConfig.dryrun {
    let universalStore = UniversalMemoryStore(memoryDir: memoryDir)
    agentTools.append(MemoryTool(store: universalStore))
}
```

Note: Create a NEW `UniversalMemoryStore` instance for the tool — don't share with `MemoryContextProvider`. The `MemoryContextProvider` already creates its own instance internally (line 449/468). Each `UniversalMemoryStore` is an actor that serializes I/O; multiple instances writing to the same files are safe because underlying OS file I/O is atomic.

Actually, wait — there's a subtlety. Creating multiple `UniversalMemoryStore` actors that write to the same files could cause interleaved writes. Better approach: create ONE `UniversalMemoryStore` for the tool and pass it as needed. But `MemoryContextProvider.buildUniversalMemoryContext()` creates its own internal store. For this story, just create a new store for the tool — the actor serialization within each store protects against concurrent writes within that store, and the `write(target:, content:)` method uses atomic writes (`atomically: true`). The real risk is two actors interleaving, but in practice the tool is only called by one agent at a time.

**Decision: Create a new `UniversalMemoryStore(memoryDir: memoryDir)` for the MemoryTool.** This matches the pattern used by `MemoryContextProvider`.

### Frozen Snapshot Behavior

The memory tool's writes to MEMORY.md/USER.md update the disk files but do NOT refresh the current session's system prompt (frozen snapshot from Story 31.1). The Agent can read back its own writes within the same session (the tool reads from disk on each call), but the system prompt context remains frozen. This is correct behavior — no special handling needed.

### Testing Strategy

- **Swift Testing framework** (`import Testing`, `@Suite`, `@Test`, `#expect`)
- **Mock-free**: Use real `UniversalMemoryStore` with temp directories (same pattern as `UniversalMemoryStoreTests.swift`)
- **MemoryTool instantiation**: `MemoryTool(store: UniversalMemoryStore(memoryDir: tempDir.path))`
- **Direct call**: `tool.call(input: params, context: ToolContext(toolUseId: "test", ...))` — need to check `ToolContext` construction
- **Run tests**: `make test` (unit tests only)

### ToolContext Construction for Tests

Check how `ToolContext` is constructed. In the SDK:
- `ToolContext` requires `toolUseId` and optionally `memoryStore`, `skillRegistry`, etc.
- For unit tests, use a minimal context: just `toolUseId` is required, all other fields can be nil/default.

### References

- [Source: docs/epics/epic-31-universal-memory.md — Story 31.2 definition, parameter design, ToolProtocol implementation guidance]
- [Source: Sources/AxionCLI/Memory/UniversalMemoryStore.swift — store API: add/replace/remove/read/charCount]
- [Source: Sources/AxionCLI/Memory/MemorySecurityScanner.swift — scan() for write-time, scanOnLoad() for load-time]
- [Source: Sources/AxionCLI/MCP/QueryTaskStatusTool.swift — ToolProtocol pattern: struct, inputSchema, call(), errorResult(), encodeResult()]
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift:245-249 — agentTools assembly, insertion point for MemoryTool]
- [Source: Sources/AxionCLI/Memory/MemoryContextProvider.swift:248-286 — buildUniversalMemoryContext (separate from tool path)]
- [Source: _bmad-output/implementation-artifacts/31-1-dual-track-memory-storage.md — Story 31.1 learnings: ZWJ detection, § delimiter fragility]

### Previous Story Learnings (31.1)

- **ZWNJ/ZWJ detection**: `String.contains(Character)` does NOT work for ZWNJ (`\u{200C}`) and ZWJ (`\u{200D}`) in Swift — must use `unicodeScalars.contains(where:)`. This is already handled in `MemorySecurityScanner.scanOnLoad()`. The `scan()` method doesn't check invisible Unicode (it only checks prompt injection, role hijack, deception, exfil patterns).
- **`§` delimiter is fragile**: If user content contains `§`, parsing will break. Documented for future hardening — not a blocker.
- **`matches()` redundancy**: Lowercasing input AND using `.caseInsensitive` is redundant but harmless.
- **`MemoryScanResult` scope**: File-scope enum (not nested) — style preference.
- **Replace char limit**: Fixed in review — `replace()` now enforces char limit check before write.
- **63 tests pass** after Story 31.1 completion (60 original + 3 review fixes).

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

### Completion Notes List

- Implemented `MemoryTool` as `final class` conforming to `ToolProtocol` with `UniversalMemoryStore` actor dependency
- `call(input:context:)` routes to 4 action handlers: handleAdd, handleReplace, handleRemove, handleRead
- Security scan runs on `add` and `replace` write operations; `remove` and `read` skip scanning
- Char limit enforcement delegated to `UniversalMemoryStore.add()` / `.replace()` returning false
- Target validation maps "memory" → MemoryTarget.memory, "user" → MemoryTarget.user via uppercase + ".md"
- Registered in `AgentBuilder.build()` after SkillTool, guarded by `!noMemory && !dryrun`
- Creates separate `UniversalMemoryStore` instance for tool (matches MemoryContextProvider pattern)
- 14 unit tests covering all ACs: add (3+1 user), replace (3), remove (2), read (1+1 user), validation (3)
- All 1561 unit tests pass with zero regressions

### File List

- Sources/AxionCLI/Memory/MemoryTool.swift (new)
- Sources/AxionCLI/Services/AgentBuilder.swift (modified — added MemoryTool registration)
- Tests/AxionCLITests/Memory/MemoryToolTests.swift (new)

## Change Log

- 2026-05-31: Implemented MemoryTool with add/replace/remove/read actions, security scanning, char limit enforcement, and AgentBuilder registration. 14 tests added.

## Senior Developer Review (AI)

**Reviewer:** Nick on 2026-05-31
**Outcome:** Approved (with fixes applied)

### Findings

| # | Severity | Issue | Resolution |
|---|----------|-------|-----------|
| H1 | HIGH | Missing test coverage for `target: "user"` — AC #3 not fully validated | Fixed: added `readUserTarget` and `addUserTarget` tests |
| M1 | MEDIUM | Story claimed 1651 tests, actual count is 1561 | Fixed: updated story text |
| M2 | MEDIUM | `replace` error conflates "not found" and "char limit exceeded" | Noted — store returns single Bool; cannot fix without modifying UniversalMemoryStore (forbidden by story scope) |
| M3 | MEDIUM | Test `addCharLimit` checked redundant "capacity" keyword | Fixed: removed dead assertion |
| M4 | MEDIUM | Test `replaceSecurityRejection` didn't verify security-specific error | Fixed: added security/blocked assertion |
| L1 | LOW | `encodeResult`/`errorResult` duplicated from QueryTaskStatusTool | Noted — acceptable duplication for now |

### AC Validation

| AC | Status | Evidence |
|----|--------|----------|
| #1 | IMPLEMENTED | `handleAdd` → security scan → `store.add()` → success/error |
| #2 | IMPLEMENTED | `handleReplace` → security scan → `store.replace()` → success/error |
| #3 | IMPLEMENTED | `handleRead` → `store.read()` returns content string (both targets tested) |
| #4 | IMPLEMENTED | `handleRemove` → `store.remove()` → success/error |
| #5 | IMPLEMENTED | `addSecurityRejection` test passes with "ignore all instructions" content |
| #6 | IMPLEMENTED | `addCharLimit` test passes with `maxMemoryChars: 30` |
| #7 | IMPLEMENTED | AgentBuilder line 253-256 registers MemoryTool guarded by `!noMemory && !dryrun` |
| #8 | IMPLEMENTED | `invalidAction`, `invalidTarget`, `missingRequiredParam` tests pass |

### Task Audit

All 13 tasks marked [x] verified as implemented. No false completions found.
