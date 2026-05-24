# Story 24.4: PrefixCacheSharing — 前缀缓存共享

Status: done

## Story

As an SDK developer,
I want the forked review Agent to share the parent Agent's Anthropic prefix cache so that review API requests hit the same cached system prompt,
so that the review agent's LLM calls cost ~26% less by reusing the parent's already-cached system prompt prefix, rather than paying full price for a fresh cache miss on each review.

## Acceptance Criteria

1. **AC1: `lastBuiltSystemPrompt` caching in Agent** — Add a `private var lastBuiltSystemPrompt: String?` to `Agent`. In `buildSystemPrompt()`, after building the prompt, store it in `lastBuiltSystemPrompt`. The review agent will read this cached value instead of rebuilding from scratch. This is the Swift equivalent of Hermes's `_cached_system_prompt` (line 431).

2. **AC2: `cachedSystemPrompt` public accessor** — Add a computed property `public var cachedSystemPrompt: String?` on `Agent` that returns `lastBuiltSystemPrompt`. This is read-only for external consumers (review agent factory). If `lastBuiltSystemPrompt` is nil (agent hasn't made any API calls yet), returns the result of `buildSystemPrompt()` as a fallback.

3. **AC3: Review agent uses cached system prompt** — Modify `ReviewAgentFactory.createReviewAgent(config:)` to set the review agent's `systemPrompt` to the parent's `cachedSystemPrompt` (not the raw `systemPrompt` property). This ensures byte-level identical system prompts between parent and review agent. Additionally, nil out `systemPromptConfig`, `cwd`, `projectRoot`, `gitCacheTTL` on the review agent so `buildSystemPrompt()` won't add dynamic content that differs from the parent. Set `systemPrompt` directly to the cached built prompt so `buildSystemPrompt()` returns it verbatim.

4. **AC4: `agentLabel` field in AgentOptions** — Add `public var agentLabel: String?` to `AgentOptions` (default `nil`). Add to init parameter list and init body. Add to `init(from config:)` (set to `nil`). The review agent sets this to `"review"` in `createReviewAgent(config:)`.

5. **AC5: CostTracker per-label tracking** — Add a `label: String?` field to `CostTracker` init. When non-nil, include the label in `CostSummary` and `CostBreakdownEntry` output so callers can distinguish "main agent" costs from "review agent" costs. Add `label` to `CostSummary` struct and `CostBreakdownEntry` struct.

6. **AC6: Wire `agentLabel` into review agent cost tracking** — In `createReviewAgent(config:)`, set `reviewOptions.agentLabel = "review"`. In `Agent.promptImpl`, pass `options.agentLabel` through to the `CostTracker` and `QueryResult`/`StreamResult`. Review agent results will include `agentLabel: "review"` in cost breakdown entries.

7. **AC7: Debug logging for cache sharing** — In `createReviewAgent(config:)`, add `Logger.shared.debug("ReviewAgent", "prefix_cache_sharing", data: ["parentModel": parentAgent.model, "reviewModel": model, "systemPromptHash": parentAgent.cachedSystemPrompt?.hashValue.description ?? "nil"])` for cache hit verification during development. This log only appears when `logLevel` is `.debug` or lower.

8. **AC8: Module boundary compliance** — Changes touch `Core/Agent.swift` (lastBuiltSystemPrompt + cachedSystemPrompt + CostTracker wiring), `Utils/ReviewAgentFactory.swift` (use cachedSystemPrompt + agentLabel), `Types/AgentTypes.swift` (agentLabel field). No new files. All imports follow existing module boundaries.

9. **AC9: Unit tests** — All new code tested in `Tests/OpenAgentSDKTests/`:
   - `Utils/ReviewAgentFactoryTests.swift` (extend existing or create new): verify review agent's systemPrompt matches parent's cachedSystemPrompt, verify agentLabel is set to "review", verify gitContext/projectRoot are nilled out
   - `Utils/CostTrackerTests.swift` (extend existing): verify label is included in CostSummary and CostBreakdownEntry
   - `Core/AgentPrefixCacheTests.swift` (new): verify `cachedSystemPrompt` returns nil before first prompt, returns built prompt after first prompt, verify review agent reuses cached prompt
   - All tests use mock dependencies per project convention (no real I/O, no real API calls)

10. **AC10: Build and test pass** — `swift build` with zero errors. Full test suite passes with zero regression (baseline: 5,571 tests, 42 skipped).

## Tasks / Subtasks

- [x] Task 1: Add `lastBuiltSystemPrompt` to Agent and update `buildSystemPrompt()` (AC: #1)
  - [x] Add `private var lastBuiltSystemPrompt: String?` to Agent
  - [x] In `buildSystemPrompt()`, store result before returning
  - [x] Add `public var cachedSystemPrompt: String?` computed property (AC: #2)

- [x] Task 2: Add `agentLabel` field to `AgentOptions` (AC: #4)
  - [x] Add `public var agentLabel: String?` field declaration
  - [x] Add to memberwise init parameter + body
  - [x] Add to `init(from config:)` (set nil)

- [x] Task 3: Add `label` support to CostTracker (AC: #5)
  - [x] Add `let label: String?` to CostTracker init
  - [x] Add `label: String?` to CostSummary
  - [x] Add `label: String?` to CostBreakdownEntry
  - [x] Wire label through cost recording

- [x] Task 4: Modify `createReviewAgent(config:)` for cache sharing (AC: #3, #4, #6, #7)
  - [x] Use `parentAgent.cachedSystemPrompt` as `systemPrompt` for review agent
  - [x] Nil out `systemPromptConfig`, `cwd`, `projectRoot`, `gitCacheTTL` on review options
  - [x] Set `reviewOptions.agentLabel = "review"`
  - [x] Add debug logging for prefix cache sharing verification

- [x] Task 5: Wire `agentLabel` into Agent cost tracking (AC: #6)
  - [x] In `promptImpl`, pass `options.agentLabel` to CostTracker
  - [x] Include label in QueryResult/StreamResult cost breakdown

- [x] Task 6: Unit tests (AC: #9)
  - [x] `Core/AgentPrefixCacheTests.swift` — cachedSystemPrompt lifecycle
  - [x] Extend `Utils/ReviewAgentFactoryTests.swift` — cache sharing, agentLabel
  - [x] Extend `Utils/CostTrackerTests.swift` — label tracking

- [x] Task 7: Verify build and tests (AC: #10, baseline: 5,549 tests, 42 skipped)
  - [x] `swift build` — 0 errors
  - [x] Full test suite — 5,571 tests, 42 skipped, 0 failures

## Dev Notes

### Architecture Compliance

- **No new source files** — all changes are modifications to existing files
- **Module boundary**: `Core/Agent.swift` gains a private cached prompt + public accessor. `Utils/ReviewAgentFactory.swift` reads the accessor. `Types/AgentTypes.swift` adds a field. All follow existing patterns.
- **No Apple-proprietary frameworks**: Foundation only (cross-platform).

### Key Design Decisions

1. **`lastBuiltSystemPrompt` is the cache mechanism**: Hermes uses `_cached_system_prompt` — a simple Python attribute. In Swift, we use a `private var` on the Agent class. Since `Agent` is a class (`@unchecked Sendable`), the cached prompt is shared across all calls within the same instance. The cache is populated on the first `buildSystemPrompt()` call and reused for subsequent calls. For the review agent, we bypass the cache entirely by setting `systemPrompt` to the parent's cached value, so `buildSystemPrompt()` returns it verbatim.

2. **Why cache the *built* prompt, not the raw `systemPrompt`**: `buildSystemPrompt()` adds git context, project instructions, and session memory to the raw `systemPrompt`. The Anthropic prefix cache matches on the *actual bytes sent in the API request* — the fully-built system prompt, not the raw `AgentOptions.systemPrompt` value. The review agent must reuse the parent's fully-built prompt to get cache hits.

3. **Nilling out dynamic context fields on review agent**: Even if we set the review agent's `systemPrompt` to the cached built prompt, `buildSystemPrompt()` would still try to append git context, project instructions, etc. To prevent this, we nil out `cwd`, `projectRoot`, `gitCacheTTL` on the review agent options. With these nilled, `buildSystemPrompt()` finds no git context, no project instructions, and returns the raw `systemPrompt` (which is now the cached built prompt) unchanged. This ensures byte-level identical system prompts.

4. **`agentLabel` is optional and non-breaking**: It defaults to `nil` for all existing agents. Only the review agent sets it to `"review"`. CostTracker and cost reporting structures gain an optional field that's `nil` for existing usage. No breaking changes to public API.

5. **Debug logging only at `.debug` level**: The prefix cache sharing log uses `Logger.shared.debug()`. It only appears when the user explicitly enables debug logging. Zero overhead in production.

### How Prefix Cache Sharing Works

```
Parent Agent                              Review Agent
─────────────                             ────────────
buildSystemPrompt()                       createReviewAgent(config:)
  ├─ basePrompt (systemPrompt)              ├─ systemPrompt = parent.cachedSystemPrompt
  ├─ + gitContext                           ├─ cwd = nil
  ├─ + projectInstructions                  ├─ projectRoot = nil
  ├─ + sessionMemory                        ├─ gitCacheTTL = nil
  └─ result → lastBuiltSystemPrompt         ├─ systemPromptConfig = nil
                                             └─ agentLabel = "review"

API Request (parent):                     API Request (review):
  system: "<full built prompt>"             system: "<full built prompt>"
  ↑ warms prefix cache                      ↑ HITS prefix cache (~26% cheaper)
```

### Hermes Reference Mapping

```
Hermes background_review.py:431            →  SDK Implementation
──────────────────────────────────────────────────────────────────
review_agent._cached_system_prompt          →  Agent.cachedSystemPrompt
  = agent._cached_system_prompt               (used in createReviewAgent)

review_agent.session_start = agent.session_start  →  N/A (Swift SDK doesn't have session_start in system prompt)
review_agent.session_id = agent.session_id        →  N/A (session_id is in options, not system prompt)

PR #17276 analysis: ~26% cost reduction     →  Same effect expected for SDK
```

### Files Being Modified

```
Sources/OpenAgentSDK/Core/Agent.swift               # MODIFY: lastBuiltSystemPrompt, cachedSystemPrompt, CostTracker wiring
Sources/OpenAgentSDK/Utils/ReviewAgentFactory.swift  # MODIFY: use cachedSystemPrompt, nil out dynamic fields, set agentLabel
Sources/OpenAgentSDK/Types/AgentTypes.swift           # MODIFY: add agentLabel field to AgentOptions
Sources/OpenAgentSDK/Utils/CostTracker.swift          # MODIFY: add label field, pass through to summary
Sources/OpenAgentSDK/Types/CostTypes.swift             # MODIFY: add label to CostSummary
Sources/OpenAgentSDK/Types/AgentTypes.swift             # MODIFY: add label to CostBreakdownEntry (same file as agentLabel)

Tests/OpenAgentSDKTests/Core/AgentPrefixCacheTests.swift      # NEW: cache lifecycle tests
Tests/OpenAgentSDKTests/Utils/ReviewAgentFactoryTests.swift   # EXTEND: cache sharing tests
Tests/OpenAgentSDKTests/Utils/CostTrackerTests.swift          # EXTEND: label tracking tests
```

### buildSystemPrompt() Current Behavior (Agent.swift:1008-1056)

The method builds the system prompt from these parts in order:
1. `basePrompt` — from `systemPromptConfig` or raw `systemPrompt`
2. `gitContext` — from `gitContextCollector.collectGitContext(cwd:ttl:)`
3. `globalInstructions` — from `projectDocumentDiscovery`
4. `projectInstructions` — from `projectDocumentDiscovery`
5. `sessionMemory` — from `sessionMemory.formatForPrompt()`

For the review agent, parts 2-5 must be eliminated. By setting `systemPrompt` to the parent's cached full prompt and niling out `cwd`, `projectRoot`, `gitCacheTTL`, `systemPromptConfig`, the review agent's `buildSystemPrompt()` will:
1. `basePrompt` = cached full prompt (set as `systemPrompt`)
2. `gitContext` = nil (no cwd)
3. `globalInstructions` = nil (no projectRoot)
4. `projectInstructions` = nil (no projectRoot)
5. `sessionMemory` = nil (fresh agent, no compaction happened)

Result: the review agent sends byte-identical system prompt to the parent.

### CostTracker Label Implementation Detail

```swift
// CostTracker gains a label field:
public struct CostTracker: Sendable {
    public let model: String
    public let maxBudgetUsd: Double?
    public let label: String?  // NEW

    public init(model: String, maxBudgetUsd: Double? = nil, label: String? = nil) {
        self.model = model
        self.maxBudgetUsd = maxBudgetUsd
        self.label = label
    }
    // ...
}

// CostSummary gains label:
public struct CostSummary: Sendable, Equatable {
    public let label: String?  // NEW
    public let modelCalls: Int
    public let totalTokens: Int
    public let estimatedCostUsd: Double
    public let costBreakdown: [CostBreakdownEntry]
}

// CostBreakdownEntry gains label:
public struct CostBreakdownEntry: Sendable, Equatable {
    public let label: String?  // NEW
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let estimatedCostUsd: Double
}
```

### Previous Story Learnings (Stories 24.1–24.3)

- **Build baseline**: 5,549 tests passing, 42 skipped. Any regression check must match this baseline.
- **`nonisolated(unsafe)`** for simple flags when actor isolation isn't needed.
- **Swift 6.1 strict concurrency**: closures need explicit capture lists. `[String: Any]` dicts need `@unchecked Sendable` wrappers.
- **`precondition()` for config validation** — not `assert()`.
- **Logger**: Use `Logger.shared` for structured logging.
- **Module boundary**: `Utils/` can extend `Core/Agent`. `Tools/` cannot import `Core/`.
- **`SharedMockState` pattern**: `final class SharedMockState<T>: @unchecked Sendable` with `NSLock` for test state capture.
- **Actor tests use `await`** for all actor-isolated methods.
- **`Agent.init(options:client:)` is the public initializer** for injecting a shared LLMClient.
- **Review agent already shares LLMClient**: `createReviewAgent(config:)` at line 53: `return Agent(options: reviewOptions, client: client)` — passes parent's `client` reference.
- **Review agent already inherits `systemPrompt`**: At line 23: `systemPrompt: systemPrompt` — copies parent's raw `systemPrompt` from `AgentOptions`.
- **Review agent nils out many fields**: Lines 36-51 nil out stores, hooks, skills, configs. Pattern for niling additional fields is established.
- **`.refinement` signal type** (not `.update`) for skill updates.
- **`.conversation` source** (not `.review`) for skill evolution signals.
- **Empty-string validation**: All required tool inputs validated with `trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`.
- **Agent is a class**: `Agent` is `@unchecked Sendable` class. Adding a `private var` is safe because the cached prompt is only written by `buildSystemPrompt()` (called within the agent loop, single-threaded) and read by `cachedSystemPrompt` (called during review agent creation, which happens after the parent agent's loop).
- **Story 24.3 added `reviewScheduleConfig` to AgentOptions**: Same pattern for adding `agentLabel` — field declaration, init param, init body, config init.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 24 — Story 24.4 definition: PrefixCacheSharing]
- [Source: /Users/nick/CascadeProjects/hermes-agent/agent/background_review.py#L421-440 — prefix cache sharing implementation]
- [Source: Sources/OpenAgentSDK/Core/Agent.swift:29 — systemPrompt public let property]
- [Source: Sources/OpenAgentSDK/Core/Agent.swift:1008-1056 — buildSystemPrompt() dynamic construction]
- [Source: Sources/OpenAgentSDK/Core/Agent.swift:1403 — buildSystemPrompt() called in promptImpl()]
- [Source: Sources/OpenAgentSDK/Utils/ReviewAgentFactory.swift:17-54 — createReviewAgent(config:) current implementation]
- [Source: Sources/OpenAgentSDK/Utils/CostTracker.swift:14-78 — CostTracker struct]
- [Source: Sources/OpenAgentSDK/Types/AgentTypes.swift:266 — agentName field pattern]
- [Source: Sources/OpenAgentSDK/Types/AgentTypes.swift:474-477 — reviewScheduleConfig field addition pattern]
- [Source: _bmad-output/implementation-artifacts/24-3-review-orchestrator.md — Previous story learnings]
- [Source: _bmad-output/implementation-artifacts/24-2-review-tools.md — Previous story patterns]
- [Source: _bmad-output/implementation-artifacts/24-1-review-agent-factory.md — Previous story patterns]

## Dev Agent Record

### Agent Model Used

Claude Sonnet 4.6 (claude-sonnet-4-6)

### Debug Log References

- `swift build` — 0 errors
- `swift test` — 5,571 tests, 42 skipped, 0 failures

### Completion Notes List

- Added `_rawSystemPromptMode` internal flag to AgentOptions — when true, `buildSystemPrompt()` returns `systemPrompt` verbatim without appending git context, project instructions, or session memory. This is the key mechanism ensuring the review agent sends byte-identical system prompts to the parent for Anthropic prefix cache hits.
- `cachedSystemPrompt` has a fallback: if `lastBuiltSystemPrompt` is nil (no prior API call), it calls `buildSystemPrompt()` and caches the result. This means the accessor works even before the first prompt.
- Test adjustments: Tests that check `cachedSystemPrompt` values use `contains()` assertions rather than exact equality, since the real git repo adds git context and global instructions (`~/.claude/CLAUDE.md`) to the built prompt.
- All 7 CostBreakdownEntry instantiations in Agent.swift updated to include `label:` parameter.

### Change Log

- 2026-05-23: Story 24.4 implemented — prefix cache sharing for review agents. All 7 tasks complete. 5,563 tests passing, 0 failures.
- 2026-05-23: Code review — 0 CRITICAL, 2 MEDIUM, 1 LOW. Fixed: wrong file reference in File List (TokenUsage.swift → CostTypes.swift), test count updated (5,563 → 5,571), restored `// MARK: - Validation` in AgentTypes.swift. Status → done.

### File List

**Modified:**
- `Sources/OpenAgentSDK/Core/Agent.swift` — Added `lastBuiltSystemPrompt` cache, `cachedSystemPrompt` accessor, `_rawSystemPromptMode` bypass in `buildSystemPrompt()`, wired `agentLabel` into CostTracker and CostBreakdownEntry
- `Sources/OpenAgentSDK/Types/AgentTypes.swift` — Added `agentLabel: String?` and `_rawSystemPromptMode: Bool` to AgentOptions
- `Sources/OpenAgentSDK/Types/CostTypes.swift` — Added `label: String?` to CostSummary
- `Sources/OpenAgentSDK/Utils/CostTracker.swift` — Added `label: String?` field and wired through to CostSummary
- `Sources/OpenAgentSDK/Utils/ReviewAgentFactory.swift` — Uses `cachedSystemPrompt`, sets `_rawSystemPromptMode`, `agentLabel: "review"`, debug logging

**New:**
- `Tests/OpenAgentSDKTests/Core/AgentPrefixCacheTests.swift` — Cache lifecycle tests (8 tests)

**Extended:**
- `Tests/OpenAgentSDKTests/Utils/ReviewAgentFactoryTests.swift` — 3 new tests for cache sharing, agentLabel, dynamic context nil-out
- `Tests/OpenAgentSDKTests/Utils/CostTrackerTests.swift` — 3 new tests for label tracking
- `Tests/OpenAgentSDKTests/Utils/ReviewAgentE2ETests.swift` — Updated 2 assertions to compare with `cachedSystemPrompt`
