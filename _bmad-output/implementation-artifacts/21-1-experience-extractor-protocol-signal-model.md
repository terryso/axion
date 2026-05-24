# Story 21.1: ExperienceExtractor Protocol & Signal Model

Status: ready-for-dev

## Story

As an SDK developer,
I want to define the abstract interface and data model for extracting experience signals from agent conversations,
so that subsequent stories (21.2-21.4) can build concrete LLM-driven extraction and hook integration on a solid, testable foundation.

## Acceptance Criteria

1. **AC1: `ExperienceSignal` struct** — Given `ExperienceSignal`, when defined in `Types/`, it is a `public struct` that is `Sendable`, `Codable`, and `Equatable`. Fields: `id` (djb2 deterministic hash of domain + content), `domain` (string, non-empty), `content` (string, human-readable experience description), `kind` (`MemoryKind` — affordance/avoid/observation), `confidence` (Double, 0-1, default 0.5), `source` (`ExperienceSource` enum — conversation/observation/imported), `createdAt` (Date), `metadata` (`[String: String]?`, optional key-value pairs for source context like runId, sessionId, turnIndex).

2. **AC2: `ExperienceSource` enum** — Given `ExperienceSource`, when defined, it is a `public enum: String, Codable, Sendable, Equatable` with cases: `conversation` (extracted from a dialogue by an extractor), `observation` (directly observed by the agent), `imported` (from an external bundle).

3. **AC3: `ExperienceExtractor` protocol** — Given `ExperienceExtractor`, when defined in `Types/`, it is a `public protocol: Sendable` with method `func extract(from messages: [SDKMessage], config: ExtractionConfig) async throws -> [ExperienceSignal]`. The protocol has no dependencies on `Core/` or `Tools/` — only `Types/` (for `SDKMessage`).

4. **AC4: `ExtractionConfig` struct** — Given `ExtractionConfig`, when defined in `Types/`, it is a `public struct` that is `Sendable`, `Codable`, `Equatable`. Fields: `antiPatternKeywords` (`[String]`, default: environment-dependent failures, transient errors, one-off task narratives), `minSignalConfidence` (Double, default 0.4 — signals below this are discarded), `maxSignalsPerExtraction` (Int, default 10), `domain` (String? — restrict extraction to a specific domain, nil means auto-detect).

5. **AC5: `ExtractionResult` struct** — Given `ExtractionResult`, when defined in `Types/`, it is a `public struct` that is `Sendable`, `Equatable`. Fields: `signals` ([ExperienceSignal]), `skippedCount` (Int — how many candidate signals were below threshold or matched anti-patterns), `extractionDate` (Date), `sourceMessageCount` (Int — how many messages were analyzed). This wraps the raw extraction output with metadata for auditability.

6. **AC6: Signal-to-Fact conversion** — Given `ExperienceSignal`, when `toFact()` is called, it produces a `MemoryFact` with `status: .candidate`, `evidenceCount: 1`, `confidence` from the signal, and appropriate `MemoryFactSource` mapping (`conversation` -> `.observation`, `imported` -> `.imported`). This bridges the extraction pipeline to the existing `FactStore`.

7. **AC7: `ExtractionConfig` default anti-pattern list** — Given the default `ExtractionConfig`, when initialized without custom anti-patterns, it includes keywords derived from Hermes research: ["command not found", "not installed", "permission denied" (when transient), "timeout", "temporary failure", "summarize today's", "summarize this week's"]. These match the anti-patterns in `agent/background_review.py` lines 121-144: environment-dependent failures, negative assertions, one-off task narratives.

8. **AC8: Unit tests** — All new types tested: `ExperienceSignal` creation and id determinism, `ExperienceSource` enum cases, `ExtractionConfig` defaults and custom init, `ExtractionResult` construction, `ExperienceSignal.toFact()` conversion (correct status/confidence/source mapping), `ExtractionConfig` anti-pattern filtering logic. A mock `ExperienceExtractor` conforming to the protocol proves the interface is implementable.

9. **AC9: Build and test pass** — `swift build` with zero errors and zero warnings. All existing 4975 tests pass with zero regression.

## Tasks / Subtasks

- [ ] Task 1: Define `ExperienceSource` enum (AC: #2)
  - [ ] Create `Sources/OpenAgentSDK/Types/ExperienceTypes.swift`
  - [ ] Define `public enum ExperienceSource: String, Codable, Sendable, Equatable` with cases: conversation, observation, imported

- [ ] Task 2: Define `ExperienceSignal` struct (AC: #1, #6)
  - [ ] In `ExperienceTypes.swift`, define `public struct ExperienceSignal: Codable, Sendable, Equatable`
  - [ ] Fields: id, domain, content, kind (MemoryKind), confidence, source (ExperienceSource), createdAt, metadata
  - [ ] `create(domain:kind:content:confidence:source:metadata:)` static factory using djb2 hash
  - [ ] `toFact() -> MemoryFact` conversion method

- [ ] Task 3: Define `ExtractionConfig` struct (AC: #4, #7)
  - [ ] In `ExperienceTypes.swift`, define `public struct ExtractionConfig: Sendable, Codable, Equatable`
  - [ ] Fields: antiPatternKeywords, minSignalConfidence, maxSignalsPerExtraction, domain
  - [ ] Static `let defaultAntiPatternKeywords` with Hermes-derived list
  - [ ] Default init using the static anti-pattern list

- [ ] Task 4: Define `ExtractionResult` struct (AC: #5)
  - [ ] In `ExperienceTypes.swift`, define `public struct ExtractionResult: Sendable, Equatable`
  - [ ] Fields: signals, skippedCount, extractionDate, sourceMessageCount

- [ ] Task 5: Define `ExperienceExtractor` protocol (AC: #3)
  - [ ] In `ExperienceTypes.swift`, define `public protocol ExperienceExtractor: Sendable`
  - [ ] Single method: `func extract(from messages: [SDKMessage], config: ExtractionConfig) async throws -> ExtractionResult`

- [ ] Task 6: Unit tests (AC: #8)
  - [ ] Create `Tests/OpenAgentSDKTests/Types/ExperienceTypesTests.swift`
  - [ ] Test ExperienceSignal.create() determinism (same input = same id)
  - [ ] Test ExperienceSignal confidence clamping (negative, >1.0)
  - [ ] Test ExperienceSignal.toFact() conversion (status, source mapping, confidence, evidenceCount)
  - [ ] Test ExtractionConfig defaults (anti-pattern list non-empty, threshold 0.4, max 10)
  - [ ] Test ExtractionConfig custom init overrides defaults
  - [ ] Test ExtractionResult construction
  - [ ] Test ExperienceSource enum raw values
  - [ ] Test mock ExperienceExtractor conformance (protocol is implementable)

- [ ] Task 7: Verify build and tests (AC: #9)
  - [ ] `swift build` — 0 errors, 0 warnings
  - [ ] Run full test suite — 0 failures

## Dev Notes

### Architecture Compliance

- **All new types go in `Types/`**: This story defines only data types and protocols — leaf-node types with no outbound dependencies. The `ExperienceExtractor` protocol references `SDKMessage` (also in `Types/`), which is valid.
- **Protocol in `Types/`**: `ExperienceExtractor` is a public protocol with no I/O or actor dependencies. Follows the pattern of `MemoryStoreProtocol` in `Types/MemoryTypes.swift`.
- **No dependency on `Core/` or `Tools/`**: Strict module boundary. The protocol's `messages` parameter is `[SDKMessage]`, which is a `Types/` type.
- **No actor needed**: All types are value types (struct/enum). `ExperienceExtractor` is a protocol — concrete implementations in Story 21.2 may use actors, but the protocol itself is Sendable.
- **No Apple-proprietary frameworks**: Foundation only.
- **Reuse existing `MemoryKind` enum**: `ExperienceSignal.kind` reuses `MemoryKind` (affordance/avoid/observation) from `MemoryFact.swift`. Do NOT create a duplicate enum.

### Key Design Decisions

1. **`ExperienceSignal` is separate from `MemoryFact`**: Signals are the raw output of extraction. They become `MemoryFact` objects only after passing through validation, deduplication, and lifecycle management. This separation matches the Hermes pattern where extraction and storage are distinct phases.

2. **`ExtractionResult` wraps the output**: Rather than returning `[ExperienceSignal]` directly, the protocol returns `ExtractionResult` which includes metadata (skippedCount, sourceMessageCount) for observability and debugging. This is essential for the ReviewHook in Story 21.3 to report what happened.

3. **`ExtractionConfig` carries the anti-pattern list**: Hermes hardcodes anti-patterns in the review prompt. We externalize them as config so developers can customize. The default list comes from `agent/background_review.py` lines 121-144.

4. **`ExperienceSignal.id` uses djb2 like `MemoryFact.factId`**: Same hash algorithm, different input. Signal id = djb2(domain + content). This ensures deterministic deduplication — the same experience extracted twice produces the same signal id, which maps to the same fact id.

5. **`metadata` field is `[String: String]?`**: Optional flat dictionary for attaching extraction context (runId, sessionId, turnIndex) without over-specifying the schema. Codable for future serialization.

### Integration Points with Existing SDK

- **`MemoryFact.swift`** (`Types/MemoryFact.swift`): `ExperienceSignal.toFact()` creates a `MemoryFact`. Uses `MemoryFact.create()` factory method. Signal's `MemoryKind` maps directly to Fact's `kind`.
- **`MemoryTypes.swift`** (`Types/MemoryTypes.swift`): `MemoryStoreProtocol` is the storage abstraction. Signals become Facts before being stored via `FactStore`.
- **`FactStore.swift`** (`Stores/FactStore.swift`): Signals convert to Facts, then FactStore persists them. This story does NOT modify FactStore.
- **`MemoryLifecycleService.swift`** (`Utils/MemoryLifecycleService.swift`): Facts created from signals go through lifecycle (candidate -> active -> retired). This story does NOT modify MemoryLifecycleService.
- **`SDKMessage.swift`** (`Types/SDKMessage.swift`): The 20-case enum consumed by `ExperienceExtractor.extract()`. This story does NOT modify SDKMessage.

### File Structure

```
Sources/OpenAgentSDK/Types/
  ExperienceTypes.swift     # All new types: ExperienceSource, ExperienceSignal,
                             # ExtractionConfig, ExtractionResult, ExperienceExtractor (NEW)

Tests/OpenAgentSDKTests/Types/
  ExperienceTypesTests.swift  # Unit tests for all new types (NEW)
```

### Modified Files

None — this story is purely additive. All existing files remain unchanged.

### Anti-Pattern List (from Hermes `background_review.py`)

The default `ExtractionConfig.antiPatternKeywords` includes patterns that indicate transient or environment-dependent issues, NOT genuine agent experience:

- **Environment-dependent failures**: "command not found", "not installed", "no such file", "binary not found" — these reflect setup state, not learning
- **Transient errors**: "timeout", "temporary failure", "connection reset", "rate limit" — retry fixes these
- **One-off task narratives**: "summarize today's", "summarize this week's", "what happened" — these are one-shot queries, not reusable knowledge
- **Negative standalone assertions**: "tool does not work", "cannot access" (without a FIX) — Hermes explicitly says "If a tool failed because of setup state, capture the FIX — never 'this tool does not work' as a standalone constraint"

The dev should NOT hardcode these as English-only strings in a way that prevents localization. Instead, use them as default values that developers can override.

### Previous Story Learnings (Epic 20, especially 20.3 & 20.4)

- Build baseline: 4975 tests passing. Any regression check must match this baseline.
- `nonisolated(unsafe)` for simple flags when actor isolation isn't needed
- Swift 6.1 strict concurrency: closures need explicit capture lists
- `NSLock` for protecting mutable state in non-actor contexts
- `ISO8601DateFormatter` should be instance property on actors (not allocated per call)
- Test counts in completion notes must match actual test count — use `swift test 2>&1 | grep -c "Test case"` before writing completion notes
- `Codable` for SDK-internal structured data, raw `[String: Any]` only for LLM API communication boundary
- Pure computation structs (like MemoryLifecycleService) are preferred when no I/O is needed
- Purely additive stories (zero modified files) are lower risk — aim for this pattern

### Testing Strategy

- **Unit tests only**: All types are data structures and a protocol — no I/O, no network, no LLM calls.
- **Protocol conformance test**: Create a mock `ExperienceExtractor` that returns fixed signals. This proves the protocol is implementable and usable.
- **Determinism tests**: Verify `ExperienceSignal.create()` produces the same id for the same input across calls.
- **Boundary tests**: Confidence clamping (negative, zero, >1.0), empty content, empty domain.
- **Conversion tests**: `toFact()` maps fields correctly, especially `ExperienceSource.conversation` -> `MemoryFactSource.observation`.
- **Anti-pattern tests**: Verify default config includes expected patterns and custom config can override.

### References

- [Source: docs/epics.md#Epic 21 Story 21.1 — ExperienceExtractor protocol and signal model]
- [Source: _bmad-output/project-context.md — Architecture rules, naming conventions, module boundaries]
- [Source: _bmad-output/implementation-artifacts/20-4-sdkmessage-output-formatting.md — Previous story learnings]
- [Source: _bmad-output/implementation-artifacts/epic-20-retro-2026-05-20.md — Epic 20 retrospective and lessons]
- [Reference: Hermes agent/background_review.py lines 34-37, 121-144 — Anti-pattern list and review prompt structure]
- [Source: Sources/OpenAgentSDK/Types/MemoryFact.swift — MemoryFact struct, djb2 hash, lifecycle status]
- [Source: Sources/OpenAgentSDK/Types/MemoryTypes.swift — MemoryStoreProtocol, KnowledgeEntry]
- [Source: Sources/OpenAgentSDK/Stores/FactStore.swift — FactStore actor for persistence]
- [Source: Sources/OpenAgentSDK/Types/HookTypes.swift — HookEvent.sessionEnd (target for Story 21.3)]
- [Source: Sources/OpenAgentSDK/Utils/MemoryLifecycleService.swift — Lifecycle transitions (candidate->active->retired)]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List

## Change Log

- 2026-05-22: Story 21.1 created — ExperienceExtractor protocol and signal model definition. Purely additive story with zero existing file modifications.
