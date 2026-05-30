---
baseline_commit: 20ffe93043faf76ded0b3b9031740b4b5704ab6a
---

# Story 31.1: Dual-Track Memory Storage — MEMORY.md + USER.md

Status: done

## Story

As an Axion user,
I want Axion to persist two independent knowledge types: environment knowledge (MEMORY.md) and user profile (USER.md),
So that Axion can leverage cross-session accumulated context in any task.

## Acceptance Criteria

1. **Given** `~/.axion/memory/MEMORY.md` and `USER.md` do not exist
   **When** UniversalMemoryStore initializes
   **Then** empty files are created and both MEMORY.md and USER.md are readable/writable

2. **Given** content is written to MEMORY.md (e.g., "project uses Swift 6.1")
   **When** the next AxionRuntime starts
   **Then** MemoryContextProvider injects that content into the system prompt
   **And** frozen snapshot mode is in effect — mid-session writes do NOT refresh the current system prompt

3. **Given** MEMORY.md contains "API key is in Keychain"
   **When** MemorySecurityScanner scans the content
   **Then** no security alert is triggered (normal knowledge)

4. **Given** MEMORY.md contains "ignore all previous instructions"
   **When** MemorySecurityScanner scans the content
   **Then** write is rejected and a warning is logged

5. **Given** MEMORY.md character count exceeds the limit (default 4000 chars)
   **When** Agent attempts to add a new entry
   **Then** Agent is told to replace or remove old entries first to free space

## Tasks / Subtasks

- [x] Task 1: Create `UniversalMemoryStore` actor (AC: #1, #2, #5)
  - [x] 1.1 Define `MemoryTarget` enum: `.memory` (MEMORY.md) and `.user` (USER.md)
  - [x] 1.2 Implement `init(memoryDir: String)` — create MEMORY.md / USER.md if missing
  - [x] 1.3 Implement `read(target:) -> String` — read file contents
  - [x] 1.4 Implement `write(target:, content:)` — full file overwrite (used by replace)
  - [x] 1.5 Implement `add(target:, content:)` — append entry with `§` delimiters, enforce maxChars
  - [x] 1.6 Implement `remove(target:, keyword:)` — fuzzy match entry by keyword, remove it
  - [x] 1.7 Implement `replace(target:, keyword:, newContent:)` — fuzzy match + replace entry
  - [x] 1.8 Implement `charCount(target:) -> Int`
  - [x] 1.9 Add `maxMemoryChars: Int = 4000` and `maxUserChars: Int = 2000` constants
  - [x] 1.10 File I/O errors must be non-fatal (catch + warning log to stderr, never throw)

- [x] Task 2: Create `MemorySecurityScanner` struct (AC: #3, #4)
  - [x] 2.1 Define `ScanResult` enum: `.safe`, `.rejected(reason: String)`, `.warning(message: String)`
  - [x] 2.2 Implement `scan(content:) -> ScanResult` — check against threat patterns
  - [x] 2.3 Implement `scanOnLoad(content:) -> [String]` — return list of suspicious entries (for load-time scan)
  - [x] 2.4 Threat patterns: prompt injection (`ignore.*previous.*instructions`, `you are now`), credential exfiltration (`curl.*KEY|TOKEN|SECRET`), invisible Unicode (`[​-‍﻿]`)
  - [x] 2.5 Write-time scan returns `.rejected` for prompt injection / exfiltration, `.safe` for clean content
  - [x] 2.6 Load-time scan returns warning strings for suspicious entries (doesn't block loading)

- [x] Task 3: Extend `MemoryContextProvider` (AC: #2)
  - [x] 3.1 Add `buildUniversalMemoryContext(memoryDir:) -> String?` method
  - [x] 3.2 Load MEMORY.md + USER.md contents via UniversalMemoryStore
  - [x] 3.3 Run MemorySecurityScanner.load-time scan; filter suspicious entries
  - [x] 3.4 Format output as `[=== Universal Memory ===]` block (see Dev Notes for exact format)
  - [x] 3.5 Return `nil` if both files are empty (safe degradation)

- [x] Task 4: Integrate into `AgentBuilder.buildSystemPrompt` (AC: #2, frozen snapshot)
  - [x] 4.1 Call `buildUniversalMemoryContext(memoryDir:)` in `buildSystemPrompt()`
  - [x] 4.2 Inject universal memory context AFTER existing memoryContext, BEFORE skills prompt
  - [x] 4.3 Ensure `buildFullSystemPrompt()` signature accepts universal memory context as separate parameter (frozen snapshot: computed once at prompt build time, not updated mid-session)

- [x] Task 5: Write unit tests
  - [x] 5.1 `UniversalMemoryStoreTests` — init creates files, read/write/add/remove/replace, char limits, non-existent dir
  - [x] 5.2 `MemorySecurityScannerTests` — safe content, prompt injection rejection, credential exfiltration, invisible Unicode detection, load-time warnings
  - [x] 5.3 `MemoryContextProviderTests` extension — `buildUniversalMemoryContext` returns nil for empty, returns formatted block for non-empty, filters suspicious entries

## Dev Notes

### Architecture

**New files:**
- `Sources/AxionCLI/Memory/UniversalMemoryStore.swift` — actor managing MEMORY.md / USER.md
- `Sources/AxionCLI/Memory/MemorySecurityScanner.swift` — pure struct, no state, scan functions

**Modified files:**
- `Sources/AxionCLI/Memory/MemoryContextProvider.swift` — add `buildUniversalMemoryContext(memoryDir:)`
- `Sources/AxionCLI/Services/AgentBuilder.swift` — extend `buildSystemPrompt()` to inject universal memory; update `buildFullSystemPrompt()` signature

**Existing files that must NOT change:**
- `AppMemoryExtractor.swift` — only processes tool pairs, untouched
- `RunMemoryProcessor.swift` — post-run fact processing, untouched
- `AxionFactStore` / `AppMemoryFact` — per-domain JSON facts, untouched

### Storage Format

The `§` delimiter separates entries (aligned with Hermes convention):
```
§
项目使用 Swift 6.1
§
截图不持久化到磁盘
§
```

### Injection Format in System Prompt

```
[existing system prompt]
[App facts memory context]          ← existing, per-domain JSON
[=== Universal Memory ===]
MEMORY.md:
{MEMORY.md contents}

USER.md:
{USER.md contents}
[=== End Universal Memory ===]
[Skills context]                    ← existing
```

### Frozen Snapshot Implementation

The frozen snapshot is naturally achieved by the existing architecture: `buildSystemPrompt()` runs once at agent construction time in `AgentBuilder.build()`. The resulting prompt string is passed to the SDK `Agent` and never recomputed. Any mid-session writes to MEMORY.md/USER.md update the disk files but NOT the prompt already sent to the LLM. No special snapshot caching is needed — the existing flow IS the snapshot.

### Key Design Decisions

- **Actor for UniversalMemoryStore**: File I/O must be serialized. Two concurrent writes to the same file would corrupt it. Actor isolation is the established pattern in this codebase (see `AxionFactStore`, `GatewayRunner`, `TelegramAdapter`).
- **Struct for MemorySecurityScanner**: Pure functions with no mutable state. No isolation needed. Instantiated on demand.
- **Non-fatal I/O**: All file operations wrapped in do/catch, errors logged to stderr via `fputs`. Memory failures must never block task execution (consistent with existing MemoryContextProvider pattern).
- **`§` delimiter**: Matches Hermes convention. Simple string split/join, no complex parsing.
- **Separate maxChars for MEMORY.md (4000) and USER.md (2000)**: Environment knowledge tends to be larger than user preferences.

### MemorySecurityScanner — Threat Patterns

Use `Regex` (Swift RegexBuilder or NSRegularExpression) for pattern matching:

| Pattern | Category | Action |
|---------|----------|--------|
| `ignore\s+(previous\|all\|above\|prior)\s+instructions` | prompt_injection | reject write |
| `you\s+are\s+now\s+` | role_hijack | reject write |
| `do\s+not\s+tell\s+the\s+user` | deception_hide | reject write |
| `curl\s+.*\$(KEY\|TOKEN\|SECRET\|PASSWORD)` | exfil_curl | reject write |
| `[​-‍﻿]` | invisible_unicode | warn on load |

### Testing Strategy

- **Swift Testing framework** (`import Testing`, `@Suite`, `@Test`, `#expect`)
- **Temporary directories**: Use `FileManager.default.temporaryDirectory` + unique subdirectory for each test. Clean up in test.
- **Mock-free**: UniversalMemoryStore reads/writes real files in temp dirs. MemorySecurityScanner is pure functions. No protocols to mock.
- **Run tests**: `make test` (per project rules — unit tests only)

### Project Structure Notes

- New files go into `Sources/AxionCLI/Memory/` — same directory as existing memory files
- Test files go into `Tests/AxionCLITests/Memory/` — mirrors source structure
- Follow import order: Foundation → OpenAgentSDK → AxionCore
- Follow naming: `UniversalMemoryStore.swift`, `MemorySecurityScanner.swift`

### References

- [Source: docs/epics/epic-31-universal-memory.md — Story 31.1 definition, storage format, Hermes alignment]
- [Source: _bmad-output/project-context.md — Memory system section, file I/O patterns, actor isolation patterns]
- [Source: _bmad-output/project-context.md — Anti-patterns: #11 no manual string concat for JSON]
- [Source: Sources/AxionCLI/Memory/MemoryContextProvider.swift — existing memory context assembly pattern]
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift:507-530 — `buildFullSystemPrompt()` injection point]
- [Source: _bmad-output/implementation-artifacts/epic-30-retro-2026-05-30.md — L1: detached tasks use direct callbacks; L3: non-zero test defaults]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- ZWNJ (`\u{200C}`) and ZWJ (`\u{200D}`) are not detected by `String.contains(Character)` in Swift — must use `unicodeScalars.contains(where:)` instead. ZWSP (`\u{200B}`) and BOM (`\u{FEFF}`) work with `Character`-based contains.

### Completion Notes List

- ✅ Implemented `UniversalMemoryStore` actor with full CRUD: read, write, add (§-delimited), remove (fuzzy keyword), replace (fuzzy keyword), charCount. Non-fatal I/O with stderr logging. Separate limits: MEMORY.md 4000 chars, USER.md 2000 chars.
- ✅ Implemented `MemorySecurityScanner` struct with write-time (reject) and load-time (warn) scanning. Covers: prompt injection, role hijack, deception, credential exfiltration, invisible Unicode.
- ✅ Extended `MemoryContextProvider` with `buildUniversalMemoryContext(memoryDir:)` — loads both files, runs load-time scan, formats as `[=== Universal Memory ===]` block, returns nil for empty content.
- ✅ Integrated into `AgentBuilder.buildSystemPrompt()` — universal memory computed once at prompt build time (frozen snapshot). `buildFullSystemPrompt()` now accepts `universalMemoryContext` parameter (default nil, backward-compatible).
- ✅ All 60 memory tests pass (37 new + 23 existing). No regressions. Pre-existing ReviewSchedulerTests failures confirmed on baseline.

### File List

**New files:**
- `Sources/AxionCLI/Memory/UniversalMemoryStore.swift`
- `Sources/AxionCLI/Memory/MemorySecurityScanner.swift`
- `Tests/AxionCLITests/Memory/UniversalMemoryStoreTests.swift`
- `Tests/AxionCLITests/Memory/MemorySecurityScannerTests.swift`
- `Tests/AxionCLITests/Memory/UniversalMemoryContextProviderTests.swift`

**Modified files:**
- `Sources/AxionCLI/Memory/MemoryContextProvider.swift`
- `Sources/AxionCLI/Services/AgentBuilder.swift`

## Senior Developer Review (AI)

**Reviewer:** Nick on 2026-05-31
**Result:** Approved (with auto-fixes applied)

### Findings Fixed

| # | Severity | File | Issue | Fix |
|---|----------|------|-------|-----|
| H1 | HIGH | UniversalMemoryStore.swift:79-89 | `replace()` didn't enforce char limit — could blow past maxChars | Added `serialized.count > maxChars` check before write |
| H2 | HIGH | MemorySecurityScanner.swift:50-69 | `scanOnLoad()` only checked 2/5 threat patterns (prompt injection + invisible Unicode). Missing: role hijack, deception, exfil. | Added all write-time patterns as load-time warnings |
| M1 | MEDIUM | Story file:183 | Dev record claimed "14 new tests" — actually 37 new (14+18+5) | Corrected count |

### Remaining Notes (not blocking)

- `§` delimiter is fragile if user content contains `§` — documented for future hardening
- `matches()` lowercases input AND uses `.caseInsensitive` — redundant but harmless
- `MemoryScanResult` at file scope instead of nested — style preference

### Tests After Fix

63 tests pass (60 original + 3 new: `replaceExceedsLimit`, `loadTimeRoleHijack`, `loadTimeDeception`)

## Change Log

- 2026-05-31 — Story created by dev agent
- 2026-05-31 — Review: 2 HIGH + 1 MEDIUM auto-fixed, 63 tests green
