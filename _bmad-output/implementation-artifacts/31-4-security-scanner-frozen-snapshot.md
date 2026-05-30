---
baseline_commit: 56adbc6...
---

# Story 31.4: Security Scanner Enhancement and Frozen Snapshot Integration

Status: done

## Story

As an Axion user,
I want the memory system to filter suspicious entries at load time and confirm frozen snapshot behavior,
So that prompt injection or corrupted entries never reach the LLM, and mid-session memory writes don't invalidate prefix caching.

## Acceptance Criteria

1. **Given** MEMORY.md contains an entry with "ignore all previous instructions"
   **When** `buildUniversalMemoryContext()` loads the file
   **Then** the suspicious entry is **filtered out** from the injected prompt
   **And** a warning is logged (not just appended to the prompt)

2. **Given** MEMORY.md contains an entry with zero-width spaces (U+200B)
   **When** `buildUniversalMemoryContext()` loads the file
   **Then** the entry containing invisible Unicode is filtered out
   **And** other clean entries are still included

3. **Given** MEMORY.md has 3 entries where 1 is suspicious and 2 are safe
   **When** `buildUniversalMemoryContext()` builds the context
   **Then** only the 2 safe entries appear in the injected prompt
   **And** a warning mentions 1 entry was filtered

4. **Given** the system prompt is built at session start with current MEMORY.md content
   **When** Agent calls `memory(action: "add")` mid-session
   **Then** the new content is written to disk
   **And** the running session's system prompt remains unchanged (frozen snapshot)

5. **Given** the review agent writes new memory via `review_save_universal_memory`
   **When** the main conversation continues
   **Then** the main agent's system prompt is unaffected

6. **Given** a clean entry (e.g., "project uses Swift 6.1")
   **When** `MemorySecurityScanner.scanEntry()` checks it
   **Then** the entry is marked safe and included in the prompt

## Tasks / Subtasks

- [x] Task 1: Add entry-level scanning to `MemorySecurityScanner` (AC: #1, #2, #6)
  - [x] 1.1 Add `scanEntry(content: String) -> MemoryScanResult` method to `MemorySecurityScanner`
  - [x] 1.2 Check all write-time threat patterns (prompt injection, role hijack, deception, exfil)
  - [x] 1.3 Check invisible Unicode characters
  - [x] 1.4 Return `.rejected(reason:)` for dangerous entries, `.warning(message:)` for suspicious entries, `.safe` for clean entries

- [x] Task 2: Enhance `buildUniversalMemoryContext()` to filter entries (AC: #1–#3)
  - [x] 2.1 Parse MEMORY.md / USER.md into §-delimited entries
  - [x] 2.2 Run `scanEntry()` on each entry individually
  - [x] 2.3 Filter out entries that return `.rejected` or `.warning`
  - [x] 2.4 Log warnings for filtered entries (using `fputs` to stderr)
  - [x] 2.5 Return only safe entries in the formatted context block

- [x] Task 3: Write unit tests for `scanEntry()` (AC: #1, #2, #6)
  - [x] 3.1 Test `scanEntry()` rejects prompt injection entry
  - [x] 3.2 Test `scanEntry()` rejects invisible Unicode entry
  - [x] 3.3 Test `scanEntry()` passes clean entry
  - [x] 3.4 Test `scanEntry()` rejects role hijack entry
  - [x] 3.5 Test `scanEntry()` rejects deception entry
  - [x] 3.6 Test `scanEntry()` rejects credential exfiltration entry

- [x] Task 4: Write integration tests for filtering in `buildUniversalMemoryContext()` (AC: #3)
  - [x] 4.1 Test mixed entries: 2 safe + 1 suspicious → only 2 safe entries in output
  - [x] 4.2 Test all entries suspicious → returns nil (all filtered)
  - [x] 4.3 Test all entries safe → full content included
  - [x] 4.4 Test entries with invisible Unicode are filtered
  - [x] 4.5 Update existing `suspiciousContentWarning` test to verify filtering

- [x] Task 5: Write frozen snapshot verification tests (AC: #4, #5)
  - [x] 5.1 Test that `buildFullSystemPrompt` result doesn't change when file is modified after call
  - [x] 5.2 Test that `MemoryTool` writes to disk but the previously built prompt string is unaffected
  - [x] 5.3 Test that `ReviewSaveUniversalMemoryTool` writes don't affect a cached prompt

## Dev Notes

### What Already Exists

The core security infrastructure was built in Stories 31.1–31.3:

| Component | Status | File |
|-----------|--------|------|
| `MemorySecurityScanner.scan()` | Done — write-time rejection | `Sources/AxionCLI/Memory/MemorySecurityScanner.swift` |
| `MemorySecurityScanner.scanOnLoad()` | Done — load-time warnings (but NO filtering) | Same file |
| `UniversalMemoryStore` | Done — full CRUD + char limits | `Sources/AxionCLI/Memory/UniversalMemoryStore.swift` |
| `MemoryContextProvider.buildUniversalMemoryContext()` | Done — but only warns, doesn't filter | `Sources/AxionCLI/Memory/MemoryContextProvider.swift` |
| `buildFullSystemPrompt()` | Done — accepts `universalMemoryContext` param | `Sources/AxionCLI/Services/AgentBuilder.swift:521` |
| Frozen snapshot | Done — prompt computed once at session start | `AgentBuilder.swift:477` |
| `MemoryTool` | Done — agent-facing add/replace/remove/read | `Sources/AxionCLI/Memory/MemoryTool.swift` |
| `ReviewSaveUniversalMemoryTool` | Done — review agent writes | `Sources/AxionCLI/Memory/ReviewSaveUniversalMemoryTool.swift` |

**The gap:** `buildUniversalMemoryContext()` currently adds a `⚠️ Security warnings` line to the prompt but **still includes the suspicious content**. It needs to parse entries and filter out dangerous ones before injecting into the system prompt.

### Architecture

**Modified files:**
- `Sources/AxionCLI/Memory/MemorySecurityScanner.swift` — add `scanEntry(content:) -> MemoryScanResult`
- `Sources/AxionCLI/Memory/MemoryContextProvider.swift` — enhance `buildUniversalMemoryContext()` to parse and filter entries

**Files that must NOT change:**
- `UniversalMemoryStore.swift` — fully functional
- `MemoryTool.swift` — agent-facing tool, already uses `scan()` before writes
- `ReviewSaveUniversalMemoryTool.swift` — review tool, already uses `scan()` before writes
- `AgentBuilder.swift` — frozen snapshot already implemented
- `RunOrchestrator.swift` — no changes needed

### scanEntry Design

Add a single method to `MemorySecurityScanner` that combines write-time and load-time checks for individual entries:

```swift
/// Scan a single §-delimited entry. Used at load time to decide whether
/// to include the entry in the injected prompt.
/// Returns `.rejected` for dangerous content, `.warning` for suspicious content
/// (invisible Unicode), `.safe` for clean entries.
func scanEntry(content: String) -> MemoryScanResult {
    // Reuse existing scan() for write-time threat patterns
    let writeResult = scan(content: content)
    if case .rejected = writeResult { return writeResult }

    // Check invisible Unicode
    let invisibleScalarValues: [UInt32] = [0x200B, 0x200C, 0x200D, 0xFEFF]
    for scalarValue in invisibleScalarValues {
        if content.unicodeScalars.contains(where: { $0.value == scalarValue }) {
            return .warning(message: "Invisible Unicode character detected")
        }
    }

    return .safe
}
```

### buildUniversalMemoryContext Enhancement

The current implementation reads raw file content and injects it wholesale. It needs to:

1. Read each file via `store.read(target:)`
2. Parse into §-delimited entries using the same logic as `UniversalMemoryStore.parseEntries()`
3. Run `scanner.scanEntry()` on each entry
4. Keep only `.safe` entries
5. Reconstruct the output with only safe entries
6. Log filtered count to stderr

```swift
// Pseudocode for the enhanced filtering:
func buildUniversalMemoryContext(memoryDir: String) async -> String? {
    let store = UniversalMemoryStore(memoryDir: memoryDir)
    let scanner = MemorySecurityScanner()

    let memoryContent = await store.read(target: .memory)
    let userContent = await store.read(target: .user)

    // Parse and filter entries
    let memoryEntries = parseEntries(from: memoryContent)
    let (safeMemory, filteredMemory) = filterEntries(memoryEntries, using: scanner)
    let userEntries = parseEntries(from: userContent)
    let (safeUser, filteredUser) = filterEntries(userEntries, using: scanner)

    // Log filtered entries
    if filteredMemory > 0 || filteredUser > 0 {
        fputs("UniversalMemory: filtered \(filteredMemory + filteredUser) suspicious entries\n", stderr)
    }

    guard !safeMemory.isEmpty || !safeUser.isEmpty else { return nil }

    // Build output with safe entries only
    ...
}
```

Note: `parseEntries()` is currently private to `UniversalMemoryStore`. Either:
- (A) Add a `static` method to `UniversalMemoryStore` for parsing, or
- (B) Duplicate the simple parsing logic in `MemoryContextProvider` (it's 3 lines: split by "§", trim, filter empty)

Option B is simpler and avoids modifying `UniversalMemoryStore`.

### Frozen Snapshot Verification

The frozen snapshot already works because:
1. `AgentBuilder.buildSystemPrompt()` is called once at agent construction time (line 205)
2. The result is passed to `AgentOptions.systemPrompt` which the SDK caches
3. Neither `MemoryTool` nor `ReviewSaveUniversalMemoryTool` modify the system prompt — they only write to disk
4. SDK's agent loop uses the cached system prompt for the entire session

Tests should verify this by:
1. Building a system prompt with specific MEMORY.md content
2. Writing new content via `UniversalMemoryStore`
3. Asserting the previously built prompt string hasn't changed

### Testing Strategy

- **Swift Testing framework** (`import Testing`, `@Suite`, `@Test`, `#expect`)
- **Mock-free**: Use real `UniversalMemoryStore` with temp directories
- **Existing tests to EXTEND** (not replace):
  - `MemorySecurityScannerTests.swift` — add `scanEntry` tests
  - `UniversalMemoryContextProviderTests.swift` — update `suspiciousContentWarning` test and add filtering tests
- **Run tests**: `swift test --filter "AxionCLITests.Memory"`

### References

- [Source: docs/epics/epic-31-universal-memory.md — Story 31.4 definition, security scanner patterns, frozen snapshot spec]
- [Source: Sources/AxionCLI/Memory/MemorySecurityScanner.swift — existing scan/scanOnLoad implementation]
- [Source: Sources/AxionCLI/Memory/MemoryContextProvider.swift:241-286 — buildUniversalMemoryContext, current warning-only approach]
- [Source: Sources/AxionCLI/Memory/UniversalMemoryStore.swift:132-137 — parseEntries private method (logic to replicate)]
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift:456-498 — frozen snapshot: universalMemoryContext computed once at line 477]
- [Source: Tests/AxionCLITests/Memory/MemorySecurityScannerTests.swift — existing 19 tests, extend with scanEntry tests]
- [Source: Tests/AxionCLITests/Memory/UniversalMemoryContextProviderTests.swift — existing 5 tests, extend with filtering tests]

### Previous Story Learnings (31.3)

- **Security scan integration**: Use `scanner.scan(content:)` before every write — returns `.rejected(reason:)` or `.safe`. The new `scanEntry()` should reuse this existing `scan()` method.
- **Multiple UniversalMemoryStore instances are safe**: Each actor serializes I/O; atomic writes prevent interleaving
- **ToolContext construction**: For tests, use `ToolContext(toolUseId: "test")` — minimal context is sufficient
- **SDK `summarizeActions`**: Success responses need `success: true` + "Saved" verb for SDK action summarization compatibility
- **CRITICAL: SDK change in local checkout**: The `additionalReviewTools` SDK change is committed locally in `.build/checkouts/open-agent-sdk-swift/` but needs upstreaming. If `swift package resolve` runs, the change is lost.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (GLM-5.1)

### Debug Log References

### Completion Notes List

- ✅ Added `scanEntry(content:) -> MemoryScanResult` to `MemorySecurityScanner` — reuses `scan()` for write-time patterns + checks invisible Unicode
- ✅ Enhanced `buildUniversalMemoryContext()` to parse §-delimited entries, scan each, filter out `.rejected`/`.warning` entries, log filtered count to stderr
- ✅ Added 6 unit tests for `scanEntry()` (prompt injection, invisible Unicode, clean, role hijack, deception, exfil)
- ✅ Added 4 integration tests for entry filtering (mixed entries, all suspicious, all safe, invisible Unicode)
- ✅ Updated existing `suspiciousContentWarning` test to verify filtering (suspicious entries now produce nil)
- ✅ Added 3 frozen snapshot verification tests (buildFullSystemPrompt immutability, MemoryTool writes, ReviewSaveUniversalMemoryTool writes)
- ✅ All 83 Memory tests pass, zero regressions

### File List

- `Sources/AxionCLI/Memory/MemorySecurityScanner.swift` — added `scanEntry(content:)` method
- `Sources/AxionCLI/Memory/MemoryContextProvider.swift` — rewrote `buildUniversalMemoryContext()` to parse/filter entries; added `filterEntries()` and `parseEntries()` helpers
- `Tests/AxionCLITests/Memory/MemorySecurityScannerTests.swift` — added 6 scanEntry tests
- `Tests/AxionCLITests/Memory/UniversalMemoryContextProviderTests.swift` — added 4 filtering tests + 3 frozen snapshot tests; updated suspiciousContentWarning test

### Change Log

- 2026-05-31: Story 31.4 complete — entry-level security scanning + filtering in buildUniversalMemoryContext + frozen snapshot verification tests
- 2026-05-31: Senior Developer Review (AI) — Approved with fixes
  - **Issues Found:** 0 CRITICAL, 0 HIGH, 2 MEDIUM, 1 LOW
  - **M1 Fixed:** Extracted duplicated invisible Unicode scalar values to `static let invisibleScalarValues` in `MemorySecurityScanner`
  - **M2 Fixed:** Renamed misleading test `suspiciousContentWarning` → `suspiciousContentFilteredOut` with corrected display name
  - **L1 Noted:** No test for stderr warning message (hard to test in Swift Testing)
  - All 6 ACs verified. All 83 Memory tests pass. No regressions.
