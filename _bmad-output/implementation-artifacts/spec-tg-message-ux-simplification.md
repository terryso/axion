---
title: 'TG Message UX Simplification'
type: 'feature'
created: '2026-06-01'
status: 'done'
baseline_commit: '9dc5266'
context:
  - '{project-root}/_bmad-output/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Telegram replies are still too noisy. A simple user request currently produces a standalone start message, visible tool chatter in the progress bubble, and in some cases a final answer that still contains raw MCP `Input` / `Output` transcript content.

**Approach:** Simplify Telegram UX to the quiet path the user wants: no redundant start banner, one lightweight progress surface, and a final answer that only contains user-meaningful content. Hermes is the product reference for “quiet chat, verbose logs”.

## Boundaries & Constraints

**Always:**
- Remove the normal Telegram execution-start push (`"任务开始执行: ..."`) when the task will already show progress through the streaming/status bubble.
- Keep queue notices, timeout/failure messages, `/new`, and session-resume behavior working as they do today unless this cleanup explicitly changes user-facing copy.
- Ensure tool progress text stays concise and never shows raw tool input, raw tool output, `Built-in Tool`, `Input:`, `Output:`, `*_result_summary`, or `*Executing on server...*`.
- Harden final-result cleaning for mixed transcript shapes, including prose before and after MCP blocks.
- Keep the change Telegram-specific; do not alter CLI / notification / HTTP output surfaces.
- Cover the UX contract with Swift Testing unit tests only.

**Ask First:** None.

**Never:**
- Do not remove meaningful failure delivery or approval/clarify interactions.
- Do not add a second execution-progress channel that duplicates the edited bubble.
- Do not expose raw MCP transcript content to Telegram as a fallback.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Normal TG task | User sends a text task; streaming is enabled | No standalone start message; user sees one progress bubble and one clean final answer | N/A |
| MCP-heavy final text | `resultText` contains prose mixed with MCP transcript blocks | Final Telegram reply strips the transcript blocks and keeps only the useful answer | If cleanup cannot trust a block, prefer the safest cleaned prose instead of echoing raw transcript |
| Edit fallback | Progress bubble can no longer be edited | Fallback delivery still uses quiet wording and keeps raw MCP transcript hidden | Reuse existing append/fallback path without crashing |

</frozen-after-approval>

## Code Map

- `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` -- emits the current standalone start message before streaming begins.
- `Sources/AxionCLI/Services/Telegram/TGStreamingController.swift` -- owns visible progress wording, tool summaries, and final wrapper copy.
- `Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift` -- owns Telegram-specific result cleaning helpers; this is where raw MCP transcript leakage must be fixed.
- `Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift` -- verifies start-message / queue UX.
- `Tests/AxionCLITests/Services/Telegram/TGStreamingControllerTests.swift` -- verifies progress bubble and final formatting behavior.
- `Tests/AxionCLITests/Services/Telegram/TGEventHandlerTests.swift` -- verifies transcript stripping and result extraction edge cases.

## Tasks & Acceptance

**Execution:**
- [x] `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` -- stop sending the normal TG execution-start banner before streaming begins -- removes the first low-value message the user called out.
- [x] `Sources/AxionCLI/Services/Telegram/TGStreamingController.swift` -- simplify progress/final copy so Telegram shows one lightweight status bubble with concise tool wording and a cleaner final answer wrapper -- makes the chat read more like Hermes.
- [x] `Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift` -- strengthen Telegram result cleaning so raw MCP transcript blocks are stripped even when mixed with model prose -- fixes the weather-example leak.
- [x] `Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift` -- update expectations for the removed start banner while preserving queue-notice coverage.
- [x] `Tests/AxionCLITests/Services/Telegram/TGStreamingControllerTests.swift` -- add coverage for the quieter progress/final wording and fallback behavior.
- [x] `Tests/AxionCLITests/Services/Telegram/TGEventHandlerTests.swift` -- add the reported weather-style transcript and similar interleaved fixtures to lock in transcript stripping.

**Acceptance Criteria:**
- Given a user sends a normal Telegram text request, when Axion starts processing it, then the user does not receive a separate `"任务开始执行: ..."` message before the progress bubble appears.
- Given the agent uses tools during a Telegram task, when progress text is shown, then the visible progress stays concise and does not reveal raw tool input, raw tool output, or internal tool-transport phrasing.
- Given `AgentCompletedEvent.resultText` contains interleaved MCP transcript sections such as `Built-in Tool`, `Input:`, `Output:`, `*_result_summary`, or `*Executing on server...*`, when Axion sends the final Telegram answer, then those sections are removed and only the user-meaningful answer remains.
- Given progress delivery falls back from edit mode to append mode, when later progress or final text is sent, then the appended message still follows the quiet Telegram wording and does not expose raw MCP transcript content.

## Spec Change Log

## Design Notes

The split version of this spec keeps one goal only: **quiet Telegram task messaging**. Broader Hermes-parity ideas such as reactions or notification-mode tuning are deferred. The implementation should treat the edited progress bubble as the primary execution surface and keep logs as the place for verbose diagnostics.

## Verification

**Commands:**
- `swift test --filter "AxionCLITests.Services.Gateway.TaskSerialQueueTests"` -- expected: TG queue/start-message tests pass with the new quiet lifecycle behavior
- `swift test --filter "AxionCLITests.Services.Telegram.TGStreamingControllerTests"` -- expected: TG progress/final-formatting tests pass with the simplified wording
- `swift test --filter "AxionCLITests.Services.Telegram.TGEventHandlerTests"` -- expected: mixed MCP transcript fixtures are stripped correctly
- `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` -- expected: unit-test suite stays green without running integration tests

## Suggested Review Order

**Execution lifecycle**

- Start with the removed standalone TG start banner and preserved queue notice path.
  [`TaskSerialQueue.swift:83`](../../Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift#L83)

- See where tool-first runs now create the same quiet preview bubble.
  [`TGStreamingController.swift:199`](../../Sources/AxionCLI/Services/Telegram/TGStreamingController.swift#L199)

**Progress and fallback behavior**

- Review the quieter preview/final transport and append fallback on edit failure.
  [`TGStreamingController.swift:331`](../../Sources/AxionCLI/Services/Telegram/TGStreamingController.swift#L331)

- Review the final-answer cleanup pipeline before text reaches Telegram.
  [`TGEventHandler.swift:176`](../../Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift#L176)

- Confirm the latest-result extraction prefers user-meaningful answer text.
  [`TGEventHandler.swift:368`](../../Sources/AxionCLI/Runtime/Handlers/TGEventHandler.swift#L368)

**Supporting tests**

- Verify queue behavior keeps silence for first tasks but still notifies queued work.
  [`TaskSerialQueueTests.swift:358`](../../Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift#L358)

- Verify tool-start preview creation and append fallback after edit failures.
  [`TGStreamingControllerTests.swift:136`](../../Tests/AxionCLITests/Services/Telegram/TGStreamingControllerTests.swift#L136)

- Verify transcript stripping guards, multiline results, and short terminal answers.
  [`TGEventHandlerTests.swift:374`](../../Tests/AxionCLITests/Services/Telegram/TGEventHandlerTests.swift#L374)

- Review the deferred follow-up noted for group-chat session isolation.
  [`deferred-work.md:46`](deferred-work.md#L46)
