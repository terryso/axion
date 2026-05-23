# Story 24.3: ReviewOrchestrator — 审查调度与间隔控制

Status: done

## Story

As an SDK developer,
I want a `ReviewOrchestrator` that triggers background review agents at configurable intervals after each session,
so that conversations are automatically reviewed for memory and skill extraction without manual invocation, controlling cost and frequency through interval-based scheduling.

## Acceptance Criteria

1. **AC1: `ReviewScheduleConfig` struct** — Defined in `Utils/ReviewOrchestrator.swift`. `public struct`, `Sendable`, `Codable`, `Equatable`. Fields: `memoryReviewInterval` (Int, default `4`), `skillReviewInterval` (Int, default `6`), `minMessagesForReview` (Int, default `4`), `reviewModel` (String?, default `nil` = inherit parent). Validation: all intervals > 0, `minMessagesForReview` > 0. Invalid values `preconditionFailure`.

2. **AC2: `ReviewOrchestrator` struct** — Defined in `Utils/ReviewOrchestrator.swift`. `public struct`, `Sendable`. Dependencies injected via init: `scheduleConfig: ReviewScheduleConfig`, `factStore: FactStore`, `skillRegistry: SkillRegistry`, `skillEvolver: any SkillEvolver`. Methods:
   - `shouldReview(sessionId: messageCount: config:) -> (memory: Bool, skill: Bool)` — interval-based check: triggers memory review when `messageCount % memoryReviewInterval == 0` AND `messageCount >= minMessagesForReview`; triggers skill review when `messageCount % skillReviewInterval == 0` AND `messageCount >= minMessagesForReview`. Per-session tracking via a `final class` state holder (interval tracker keyed by sessionId + domain, matching `MemoryReviewHook` pattern).
   - `executeReview(parentAgent: Agent, messages: [SDKMessage], config: ReviewAgentConfig) async -> ReviewAgentResult?` — full review pipeline:
     1. Build review prompt via `ReviewPromptBuilder.selectPrompt(config:)`
     2. Fork review agent via `parentAgent.createReviewAgent(config:)`
     3. Create review tools via `createReviewTools(factStore:skillRegistry:skillEvolver:)` and inject into the forked agent by setting its `options.tools` (review agent was created with empty `tools: []`)
     4. Execute in `Task.detached` — call `reviewAgent.prompt(reviewPrompt + conversationHistory)` — non-blocking
     5. Extract results from review agent's message history
     6. Summarize actions via `summarizeActions(_:priorSnapshot:)`
     7. Return `ReviewAgentResult` or `nil` on failure

3. **AC3: `summarizeActions` static method** — `static func summarizeActions(_ messages: [SDKMessage], priorSnapshot: [SDKMessage]) -> [String]`. Translated from Hermes `summarize_background_review_actions()`:
   - Walk review messages, find tool-result messages with `"success": true` JSON
   - Skip messages already present in `priorSnapshot` (match by tool call ID or content equality) to avoid re-surfacing stale actions (Hermes issue #14944)
   - Extract action descriptions from `"message"` field: "created" → append message, "updated" → append message, "saved" → append message
   - Deduplicate while preserving order
   - Returns `[String]` action descriptions

4. **AC4: sessionEnd hook registration** — In `Agent.init`, when `AgentOptions.reviewScheduleConfig` is present AND `hookRegistry` is present AND `provider == .anthropic`:
   - Create a `ReviewOrchestrator` with injected dependencies
   - Register a `.sessionEnd` hook that:
     a. Gets messages via `agent.getMessages()`
     b. Calls `shouldReview(sessionId:messageCount:config:)` with default `ReviewAgentConfig`
     c. If neither memory nor skill review needed, returns `nil`
     d. Constructs `ReviewAgentConfig` based on `shouldReview` result (sets `reviewMemory`/`reviewSkills` flags)
     e. Calls `orchestrator.executeReview(parentAgent:messages:config:)` in `Task.detached` (non-blocking — fire-and-forget)
     f. Returns `HookOutput(additionalContext: summary)` if review completed synchronously, or `nil` if detached (review runs in background)
   - Registration pattern matches `MemoryReviewHook` registration at `Agent.swift:214-237` — use detached `Task` for actor-isolated `hookRegistry.register()` call

5. **AC5: `AgentOptions.reviewScheduleConfig` field** — Add `public var reviewScheduleConfig: ReviewScheduleConfig?` to `AgentOptions` (default `nil`). Add to `AgentOptions.init()` and `AgentOptions.empty()`. Wire into `Agent.init` merged options.

6. **AC6: Review agent tools injection** — After calling `parentAgent.createReviewAgent(config:)` (which creates agent with `tools: []`), the orchestrator must inject the review tools. Since `Agent.options.tools` is a `var`, call `reviewAgent.options.tools = createReviewTools(factStore:skillRegistry:skillEvolver:)`. This follows the pipeline described in Story 24.2's wiring diagram.

7. **AC7: Module boundary compliance** — `ReviewOrchestrator.swift` lives in `Utils/`. Dependencies: `Types/` (ReviewAgentTypes, AgentTypes, HookTypes, SDKMessage), `Utils/` (ReviewPromptBuilder, ReviewAgentFactory), `Tools/Review/` (ReviewTools), `Stores/` (FactStore), `Tools/` (SkillRegistry), `Core/` (Agent — for extension and `options` access). This extends the pattern where `Utils/ReviewAgentFactory.swift` already depends on `Core/Agent`.

8. **AC8: Unit tests** — All new code tested in `Tests/OpenAgentSDKTests/Utils/`:
   - `ReviewScheduleConfigTests`: valid construction, defaults, Codable round-trip, Equatable, precondition failure for invalid values
   - `ReviewOrchestratorTests`:
     - `shouldReview`: triggers at correct intervals, respects `minMessagesForReview`, handles zero/low message counts, tracks per-session state
     - `executeReview`: mocks LLMClient to return tool-use responses, verifies ReviewAgentResult contains correct memoryChanges/skillChanges/summary
     - `summarizeActions`: extracts "created"/"updated"/"saved" actions, skips prior snapshot messages, deduplicates, handles malformed JSON
   - All tests use mock dependencies per project convention (no real I/O, no real API calls)

9. **AC9: Build and test pass** — `swift build` with zero errors. Full test suite passes with zero regression.

## Tasks / Subtasks

- [x] Task 1: Define `ReviewScheduleConfig` (AC: #1)
  - [x] Add struct to `Utils/ReviewOrchestrator.swift`
  - [x] Validation with `precondition()` for intervals and minMessages

- [x] Task 2: Define `ReviewOrchestrator` core struct (AC: #2)
  - [x] Add init with dependency injection
  - [x] Implement `shouldReview(sessionId:messageCount:config:)` with interval tracking
  - [x] Implement `executeReview(parentAgent:messages:config:)` async method

- [x] Task 3: Implement `summarizeActions` (AC: #3)
  - [x] Static method that parses tool-result JSON from review messages
  - [x] Deduplication against prior snapshot

- [x] Task 4: Add `reviewScheduleConfig` to `AgentOptions` (AC: #5)
  - [x] Add field to `AgentOptions` struct
  - [x] Add to init and empty() defaults

- [x] Task 5: Register sessionEnd hook in `Agent.init` (AC: #4)
  - [x] Add hook registration block similar to MemoryReviewHook pattern
  - [x] Wire orchestrator with injected dependencies

- [x] Task 6: Wire review tools injection (AC: #6)
  - [x] In `executeReview`, create tools via `createReviewTools()` and inject into forked agent

- [x] Task 7: Unit tests (AC: #8)
  - [x] `ReviewScheduleConfigTests.swift`
  - [x] `ReviewOrchestratorTests.swift` (shouldReview, executeReview, summarizeActions)

- [x] Task 8: Verify build and tests (AC: #9)
  - [x] `swift build` — 0 errors
  - [x] Full test suite — 0 failures

## Dev Notes

### Architecture Compliance

- **Directory**: `Sources/OpenAgentSDK/Utils/ReviewOrchestrator.swift` — follows the existing `ReviewAgentFactory.swift` and `ReviewPromptBuilder.swift` in `Utils/`.
- **Module boundary**: `Utils/` can depend on `Core/Agent` (same pattern as `ReviewAgentFactory.swift`). Can also depend on `Tools/Review/` for `createReviewTools()`.
- **No Apple-proprietary frameworks**: Foundation only (cross-platform).

### Key Design Decisions

1. **`ReviewOrchestrator` is a struct, not a class**: It holds injected dependencies (FactStore, SkillRegistry, SkillEvolver) and a reference-type interval tracker. The struct itself is `Sendable` because its stored properties are either Sendable value types or reference-type dependencies. The interval tracker is a `final class: @unchecked Sendable` with `NSLock` — same pattern as `IntervalTracker` in `MemoryReviewHook.swift`.

2. **Per-session interval tracking**: The orchestrator needs to track when the last review occurred per session. Use a `final class IntervalTracker: @unchecked Sendable` with `[String: Date]` keyed by `"{sessionId}:memory"` and `"{sessionId}:skill"`. This mirrors the `IntervalTracker` in `MemoryReviewHook.swift` but tracks per-session instead of per-domain.

3. **`Task.detached` for background execution**: The review runs in `Task.detached` so it doesn't block the parent agent's `prompt()`/`stream()` return. This is the Swift equivalent of Hermes's `threading.Thread(daemon=True)`. The parent agent's hook handler returns `nil` immediately (fire-and-forget), and the detached task logs the summary via `Logger.shared`.

4. **Review agent tools injection after creation**: `createReviewAgent(config:)` creates the agent with `tools: []` (Story 24.1). The orchestrator creates the tools via `createReviewTools(factStore:skillRegistry:skillEvolver:)` (Story 24.2) and injects them by setting `reviewAgent.options.tools`. `Agent.options` is a `var` (internal access), and `AgentOptions.tools` is a `var`, so this works within the same module.

5. **Conversation history injection**: The review agent needs the parent's conversation messages as context. Pass them as part of the user prompt (concatenated with the review prompt) to `reviewAgent.prompt()`. Swift Arrays are value types — creating a snapshot is automatic when passing to the detached task.

6. **Fire-and-forget hook pattern**: Unlike `MemoryReviewHook` which runs synchronously in the hook handler, the review orchestrator's `executeReview` is async and runs in a detached task. The hook handler returns `nil` immediately. The review result is logged via `Logger.shared` rather than returned as `HookOutput`. This is intentional — the sessionEnd hook should not block while a full agent loop runs.

### How ReviewOrchestrator Wires Into the Pipeline

```
Story 24.1 (DONE)     Story 24.2 (DONE)         Story 24.3 (THIS)
─────────────────     ──────────────────         ──────────────────
ReviewAgentConfig     ReviewMemoryTool            ReviewScheduleConfig
ReviewAgentResult     ReviewSkillUpdateTool       ReviewOrchestrator
ReviewPromptBuilder   ReviewSkillCreateTool         ├─ shouldReview()
Agent.createReview()  ReviewSkillFileTool           ├─ executeReview()
                      createReviewTools()            │   ├─ selectPrompt()
                                                     │   ├─ createReviewAgent()
                                                     │   ├─ createReviewTools() → inject
                                                     │   ├─ Task.detached { prompt() }
                                                     │   ├─ summarizeActions()
                                                     │   └─ return ReviewAgentResult
                                                     └─ sessionEnd hook registration
```

### shouldReview Logic

```swift
func shouldReview(sessionId: String, messageCount: Int, config: ReviewAgentConfig) -> (memory: Bool, skill: Bool) {
    guard messageCount >= scheduleConfig.minMessagesForReview else {
        return (false, false)
    }
    let doMemory = config.reviewMemory && messageCount % scheduleConfig.memoryReviewInterval == 0
    let doSkill = config.reviewSkills && messageCount % skillReviewInterval == 0
    return (doMemory, doSkill)
}
```

Hermes uses `_memory_nudge_interval` / `_skill_nudge_interval` (line 347-370 of `background_review.py`). The SDK version simplifies this: modulo of message count against the interval. When the count is exactly divisible by the interval, a review triggers.

### summarizeActions Logic (Translated from Hermes)

```swift
static func summarizeActions(_ messages: [SDKMessage], priorSnapshot: [SDKMessage]) -> [String] {
    // 1. Build set of existing tool call IDs and content from priorSnapshot
    // 2. Walk review messages, find tool-result messages
    // 3. Parse JSON, check "success": true
    // 4. Skip messages already in priorSnapshot (by toolCallId or content)
    // 5. Extract "message" field, look for "created"/"updated"/"saved" keywords
    // 6. Deduplicate preserving order
    // 7. Return action descriptions
}
```

### sessionEnd Hook Registration Pattern

Follow the exact same pattern as `MemoryReviewHook` registration in `Agent.swift:214-237`:

```swift
// In Agent.init, after MemoryReviewHook registration:
if let scheduleConfig = mergedOptions.reviewScheduleConfig,
   let hookRegistry = mergedOptions.hookRegistry,
   mergedOptions.provider == .anthropic {
    let orchestrator = ReviewOrchestrator(
        scheduleConfig: scheduleConfig,
        factStore: FactStore(),
        skillRegistry: skillRegistry ?? SkillRegistry(),
        skillEvolver: mergedOptions.skillEvolver ?? LLMSkillEvolver(client: self.client)
    )
    let agent = self
    let handler: @Sendable (HookInput) async -> HookOutput? = { _ in
        let messages = agent.getMessages()
        let defaultConfig = ReviewAgentConfig()
        let (doMemory, doSkill) = orchestrator.shouldReview(
            sessionId: agent.getSessionId() ?? "",
            messageCount: messages.count,
            config: defaultConfig
        )
        guard doMemory || doSkill else { return nil }

        let reviewConfig = ReviewAgentConfig(
            reviewMemory: doMemory,
            reviewSkills: doSkill
        )
        // Fire-and-forget in detached task
        _Concurrency.Task.detached {
            do {
                let result = await orchestrator.executeReview(
                    parentAgent: agent,
                    messages: messages,
                    config: reviewConfig
                )
                if let result {
                    Logger.shared.info("ReviewOrchestrator", "review_completed", data: [
                        "summary": result.summary,
                    ])
                }
            } catch {
                Logger.shared.warn("ReviewOrchestrator", "review_failed", data: [
                    "error": error.localizedDescription,
                ])
            }
        }
        return nil // Non-blocking — review runs in background
    }
    _Concurrency.Task { [hookRegistry] in
        await hookRegistry.register(.sessionEnd, definition: HookDefinition(handler: handler))
    }
}
```

**Important**: Check if `AgentOptions` already has a `skillEvolver` field. If not, the orchestrator will need to create its own `LLMSkillEvolver(client:)`. Check `AgentOptions` for this field first.

### Hermes Reference Mapping

```
Hermes background_review.py              →  SDK Component
──────────────────────────────────────────────────────────────────
_memory_nudge_interval (L347-370)        →  ReviewScheduleConfig.memoryReviewInterval
_skill_nudge_interval (L347-370)         →  ReviewScheduleConfig.skillReviewInterval
spawn_background_review_thread() (L547)  →  ReviewOrchestrator.executeReview()
_run_review_in_thread() (L321)           →  Task.detached { ... } block
threading.Thread(daemon=True)            →  Task.detached
messages_snapshot = list(messages)       →  let snapshot = messages (value type)
suppress_status_output = True            →  permissionMode = .bypassPermissions + no hookRegistry
review_agent.run_conversation(...) (L462) →  reviewAgent.prompt(reviewPrompt)
summarize_background_review_actions()    →  ReviewOrchestrator.summarizeActions()
agent._safe_print(summary) (L503)        →  Logger.shared.info("ReviewOrchestrator", ...)
```

### Previous Story Learnings (Stories 24.1 & 24.2)

- **Build baseline**: 5,523 tests passing, 42 skipped. Any regression check must match this baseline.
- **`nonisolated(unsafe)`** for simple flags when actor isolation isn't needed.
- **Swift 6.1 strict concurrency**: closures need explicit capture lists. `[String: Any]` dicts need `@unchecked Sendable` wrappers.
- **`precondition()` for config validation** — not `assert()`.
- **Logger**: Use `Logger.shared` for structured logging.
- **Module boundary**: `Utils/` can extend `Core/Agent`. `Tools/` cannot import `Core/`.
- **`SharedMockState` pattern**: `final class SharedMockState<T>: @unchecked Sendable` with `NSLock` for test state capture.
- **Actor tests use `await`** for all actor-isolated methods.
- **`Agent.init(options:client:)` is the public initializer** for injecting a shared LLMClient.
- **Tool names already defined**: `["review_save_memory", "review_update_skill", "review_create_skill", "review_add_skill_file"]`
- **Error handling**: Review tools return error JSON `{"success": false, ...}` — do NOT throw from execute closures.
- **`FactStore.save` can throw**: Catch and return error JSON.
- **`.refinement` signal type** (not `.update`) for skill updates.
- **`.conversation` source** (not `.review`) for skill evolution signals.
- **Empty-string validation**: All required tool inputs validated with `trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`.
- **ReviewSkillFileTool validates path prefix**: Only `references/`, `templates/`, `scripts/` allowed.

### File Structure

```
Sources/OpenAgentSDK/Utils/
  ReviewOrchestrator.swift              # NEW: ReviewScheduleConfig + ReviewOrchestrator

Sources/OpenAgentSDK/Types/
  AgentTypes.swift                       # MODIFY: add reviewScheduleConfig field

Sources/OpenAgentSDK/Core/
  Agent.swift                            # MODIFY: add sessionEnd hook registration for orchestrator

Tests/OpenAgentSDKTests/Utils/
  ReviewScheduleConfigTests.swift        # NEW: Config validation tests
  ReviewOrchestratorTests.swift          # NEW: shouldReview, executeReview, summarizeActions tests
```

### AgentOptions.reviewScheduleConfig Field Addition

In `AgentTypes.swift`, add the field alongside `memoryReviewConfig`, `securityConfig`, `evolutionPlugins`:

```swift
/// Optional configuration for automatic background review scheduling.
/// When set with `hookRegistry` and Anthropic provider, a sessionEnd hook
/// is registered to trigger review agents at configurable intervals.
public var reviewScheduleConfig: ReviewScheduleConfig?
```

Add to init parameter list (default `nil`) and to `empty()` (set to `nil`).

### Review Agent Tools Injection Detail

The review agent created by `createReviewAgent(config:)` has `tools: []`. The orchestrator must:

```swift
let reviewTools = createReviewTools(
    factStore: factStore,
    skillRegistry: skillRegistry,
    skillEvolver: skillEvolver
)
reviewAgent.options.tools = reviewTools
```

This works because `Agent.options` is `internal var options: AgentOptions` and `AgentOptions.tools` is `public var tools: [ToolProtocol]`. Both are mutable within the same module.

### Conversation History for Review Prompt

The review agent needs the parent's messages as context. Pass the messages to `reviewAgent.prompt()`:

```swift
let reviewPrompt = ReviewPromptBuilder.selectPrompt(config: config)
let conversationContext = formatMessagesForReview(messages)
let fullPrompt = reviewPrompt + "\n\n---\n\n## Conversation to Review\n\n" + conversationContext

// Run in detached task
let result = await reviewAgent.prompt(fullPrompt)
```

Format the conversation as a readable transcript that the review agent can analyze. Use a simple format: `User: ...` / `Assistant: ...` for each message's text content.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 24 — Story 24.3 definition: ReviewOrchestrator]
- [Source: /Users/nick/CascadeProjects/hermes-agent/agent/background_review.py#L231-291 — summarize_background_review_actions()]
- [Source: /Users/nick/CascadeProjects/hermes-agent/agent/background_review.py#L321-540 — _run_review_in_thread()]
- [Source: /Users/nick/CascadeProjects/hermes-agent/agent/background_review.py#L547-572 — spawn_background_review_thread()]
- [Source: Sources/OpenAgentSDK/Utils/ReviewAgentFactory.swift — createReviewAgent(config:)]
- [Source: Sources/OpenAgentSDK/Tools/Review/ReviewTools.swift — createReviewTools(factStore:skillRegistry:skillEvolver:)]
- [Source: Sources/OpenAgentSDK/Utils/ReviewPromptBuilder.swift — selectPrompt(config:)]
- [Source: Sources/OpenAgentSDK/Types/ReviewAgentTypes.swift — ReviewAgentConfig, ReviewAgentResult]
- [Source: Sources/OpenAgentSDK/Utils/MemoryReviewHook.swift — sessionEnd hook registration pattern]
- [Source: Sources/OpenAgentSDK/Core/Agent.swift:214-237 — MemoryReviewHook registration in Agent.init]
- [Source: Sources/OpenAgentSDK/Core/Agent.swift:1479-1487 — sessionEnd hook execution in prompt()]
- [Source: Sources/OpenAgentSDK/Core/Agent.swift:1751-1758 — sessionEnd hook execution in stream()]
- [Source: Sources/OpenAgentSDK/Types/AgentTypes.swift:462 — memoryReviewConfig field pattern]
- [Source: Sources/OpenAgentSDK/Hooks/HookRegistry.swift — register() and execute()]
- [Source: _bmad-output/implementation-artifacts/24-1-review-agent-factory.md — Previous story patterns]
- [Source: _bmad-output/implementation-artifacts/24-2-review-tools.md — Previous story patterns]

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m]

### Debug Log References

### Completion Notes List

- Implemented `ReviewScheduleConfig`: public struct, Sendable, Codable, Equatable with precondition validation for all intervals
- Implemented `ReviewOrchestrator`: struct with dependency injection, `shouldReview()` interval-based scheduling, `executeReview()` full pipeline with Task.detached, `summarizeActions()` static method with dedup against prior snapshot
- Added `reviewScheduleConfig` field to `AgentOptions` (init param + body assignment)
- Registered sessionEnd hook in `Agent.init` following MemoryReviewHook pattern — fire-and-forget via Task.detached
- Wired review tools injection: `createReviewTools()` → `reviewAgent.options.tools`
- Updated `ReviewAgentFactory` to nil out `reviewScheduleConfig` to prevent nested review
- 26 new unit tests: 5 config tests + 21 orchestrator tests (shouldReview, summarizeActions, AgentOptions integration)
- Build: 0 errors. Full suite: 5,549 tests passing, 42 skipped, 0 failures (baseline was 5,523).

### Change Log

- 2026-05-23: Story 24.3 complete — ReviewOrchestrator with interval-based scheduling, sessionEnd hook, tools injection, summarizeActions, and 26 unit tests.
- 2026-05-23: Senior Developer Review (AI) — 6 issues found and auto-fixed:
  - [HIGH] Removed dead `IntervalTracker` class and unused `tracker` property
  - [HIGH] Fixed `executeReview` to call `prompt()` directly instead of wrapping in pointless `Task.detached` + `.value` await
  - [HIGH] Added failure detection in `executeReview`: returns `nil` when prompt result status is error
  - [MEDIUM] Added `reviewScheduleConfig = nil` to `init(from config:)` initializer
  - [MEDIUM] Fixed memory/skill classification to use `.lowercased().contains()` consistently
  - [MEDIUM] Updated doc comments to accurately reflect fire-and-forget behavior (hook handler fires `executeReview` in detached task, not `executeReview` itself)
  - All 5,549 tests passing, 42 skipped, 0 failures.

### File List

- `Sources/OpenAgentSDK/Utils/ReviewOrchestrator.swift` — NEW: ReviewScheduleConfig + ReviewOrchestrator
- `Sources/OpenAgentSDK/Types/AgentTypes.swift` — MODIFIED: added reviewScheduleConfig field, init param, init body
- `Sources/OpenAgentSDK/Core/Agent.swift` — MODIFIED: added sessionEnd hook registration for ReviewOrchestrator
- `Sources/OpenAgentSDK/Utils/ReviewAgentFactory.swift` — MODIFIED: nil out reviewScheduleConfig on review agent
- `Tests/OpenAgentSDKTests/Utils/ReviewScheduleConfigTests.swift` — NEW: 5 tests
- `Tests/OpenAgentSDKTests/Utils/ReviewOrchestratorTests.swift` — NEW: 21 tests
