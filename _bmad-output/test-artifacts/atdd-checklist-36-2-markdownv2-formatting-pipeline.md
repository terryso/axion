---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04-generate-tests
  - step-04c-aggregate
  - step-05-validate-and-complete
lastStep: step-05-validate-and-complete
lastSaved: '2026-06-03'
storyId: '36.2'
storyKey: 36-2-markdownv2-formatting-pipeline-hermes-parity
storyFile: _bmad-output/implementation-artifacts/36-2-markdownv2-formatting-pipeline-hermes-parity.md
atddChecklistPath: _bmad-output/test-artifacts/atdd-checklist-36-2-markdownv2-formatting-pipeline.md
generatedTestFiles:
  - Tests/AxionCLITests/Services/Telegram/TGMessageFormatterTableTests.swift
inputDocuments:
  - _bmad-output/implementation-artifacts/36-2-markdownv2-formatting-pipeline-hermes-parity.md
  - _bmad/tea/config.yaml
  - _bmad-output/project-context.md
---

# ATDD Checklist: Story 36.2 - MarkdownV2 Table Block Rendering

## TDD Red Phase (Current)

Red-phase acceptance test scaffolds generated. All new tests target the **block-level table rendering** capabilities that do not yet exist in `TGMessageFormatter`. Tests will compile but fail until the implementation is complete.

- **New Test File**: 22 test methods in `TGMessageFormatterTableTests.swift` (all RED)
- **Existing Test Updates Required**: 1 test in `TGMessageFormatterTests.swift` (update expected output)
- **Total New Tests**: 22 test methods covering all 7 ACs

## Acceptance Criteria Coverage

| AC | Description | Priority | Test File | Test Count | Status |
|----|-------------|----------|-----------|------------|--------|
| AC1 | Multi-row table rendered as monospace aligned `<pre>` block in MarkdownV2 | P0 | TGMessageFormatterTableTests.swift | 5 | RED |
| AC2 | Entire table as single `<pre>` block; no escaping inside | P0 | TGMessageFormatterTableTests.swift | 3 | RED |
| AC3 | Mixed content: table block detected among paragraphs | P0 | TGMessageFormatterTableTests.swift | 4 | RED |
| AC4 | HTML mode: table renders as `<pre><code>` block | P1 | TGMessageFormatterTableTests.swift | 3 | RED |
| AC5 | Plain mode: table renders as indented monospace | P1 | TGMessageFormatterTableTests.swift | 3 | RED |
| AC6 | Split preserves table block integrity | P0 | TGMessageFormatterTableTests.swift | 2 | RED |
| AC7 | Old key/value fallback replaced by block rendering | P0 | TGMessageFormatterTableTests.swift | 2 | RED |

**All 7 acceptance criteria have corresponding test coverage.**

## Priority Distribution

| Priority | Test Count | Percentage |
|----------|------------|------------|
| P0 | 13 | 59% |
| P1 | 6 | 27% |
| P2 (edge cases) | 3 | 14% |

## Test Level Strategy

This is a **pure function enum** (`TGMessageFormatter`) with no external dependencies. Test level selection:

- **Unit Tests** (primary — 100%): All tests are unit tests calling `TGMessageFormatter.format()`, `formatAsHTML()`, `formatAsPlain()`, and `split()` directly.
  - No mocks needed — `TGMessageFormatter` is a stateless enum with pure static methods.
  - No integration tests required — no external process, network, or filesystem interactions.
  - File: `TGMessageFormatterTableTests.swift`

- **Existing Test Updates**: The `formatTableDegrades` test in `TGMessageFormatterTests.swift` currently validates key/value output. After implementation, it should be updated to expect block-level aligned output. This is noted in the story's Task 5.1 but the ATDD scaffold does not modify existing tests — that happens during implementation.

## Test Files Created

| File | Tests | ACs Covered | Lines |
|------|-------|-------------|-------|
| `Tests/AxionCLITests/Services/Telegram/TGMessageFormatterTableTests.swift` | 22 | AC1-AC7 | ~380 |

## Test Design Rationale

### Why a Separate Test File?

Story 36.2 adds 22 new test methods for block-level table rendering. Placing these in a separate `TGMessageFormatterTableTests.swift` alongside the existing `TGMessageFormatterTests.swift` follows the project's test organization pattern (one test file per feature area) and keeps the diff manageable.

### Why No New Source Files?

The story explicitly states: "All changes in existing `TGMessageFormatter.swift`." The ATDD tests target new internal behavior (`detectTableBlock`, `renderTableBlock`) through the existing public API (`format()`, `formatAsHTML()`, `formatAsPlain()`, `split()`).

### Test Input Strategy

All test inputs use realistic GFM table syntax that an LLM agent would produce. Edge cases include:
- Tables with 3+ columns (not just 2-column key/value)
- Tables with varying cell widths (tests column alignment)
- Single-row tables (should fall back to key/value per story design)
- Tables mixed with headings, lists, and paragraphs
- Tables containing special MarkdownV2 characters (`.` `-` `|`)
- Tables that exceed the 4096-byte split threshold

### Anti-Pattern Prevention

- **No XCTest** — all tests use `import Testing`, `@Suite`, `@Test`, `#expect`
- **No mocks needed** — `TGMessageFormatter` is a pure function enum
- **No `print()` debugging** — all assertions use `#expect`
- **Tests call real public API** — no testing literal strings (anti-pattern #10 from project-context)
- **No new source files** — story explicitly forbids this
