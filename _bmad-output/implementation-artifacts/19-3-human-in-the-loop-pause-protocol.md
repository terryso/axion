# Story 19.3: Human-in-the-loop Pause Protocol

Status: review

## Story

As an SDK developer,
I want the SDK to provide a structured Agent pause/resume protocol,
so that an Agent can pause when it cannot complete autonomously, wait for human intervention, and resume execution after the human finishes.

## Acceptance Criteria

1. **AC1: `Agent.pause(reason:)` method** -- When `pause(reason:)` is called during Agent execution, the Agent enters a `paused` state, stops tool execution, and emits `SDKMessage.system(.paused(PausedData))` to notify the consumer.

2. **AC2: `Agent.resume(context:)` method** -- When the consumer calls `resume(context:)` while the Agent is paused, the Agent resumes execution. The `context` string is injected into the next conversation turn as a human-completion message (e.g., "Human has completed the following: {context}").

3. **AC3: `Agent.abort()` from paused state** -- When the consumer calls `abort()` while the Agent is paused, the Agent enters `cancelled` state and returns a summary of executed steps via a `.result(.cancelled)` message.

4. **AC4: Pause timeout** -- When the Agent has been paused for longer than `pauseTimeoutMs` (default 300000ms = 5 minutes), the Agent automatically enters `cancelled` state and emits `SDKMessage.system(.pausedTimeout)` to notify the consumer.

5. **AC5: `SDKMessage` new cases** -- `SDKMessage.SystemData.Subtype` gains `paused` and `pausedTimeout` cases. `PausedData` struct contains `reason` (String), `pausedAt` (Date), and `canResume` (Bool).

6. **AC6: Built-in `pause_for_human` tool** -- An LLM can invoke the built-in tool `pause_for_human` with parameter `{ "reason": "..." }`. This is equivalent to calling `Agent.pause(reason:)` and triggers the full pause protocol.

7. **AC7: Unit tests** -- All pause/resume/abort/timeout operations covered by unit tests.

8. **AC8: Build and test pass** -- `swift build` zero errors zero warnings. All existing tests pass with zero regression.

## Tasks / Subtasks

- [x] Task 1: Define PausedData and extend SDKMessage types (AC: #5)
  - [x] Add `PausedData` struct to `Sources/OpenAgentSDK/Types/SDKMessage.swift` with fields: `reason: String`, `pausedAt: Date`, `canResume: Bool`
  - [x] Add `paused` and `pausedTimeout` cases to `SDKMessage.SystemData.Subtype` enum
  - [x] Add `pausedData: PausedData?` field to `SDKMessage.SystemData` (optional, nil for non-pause events)
  - [x] Update `SystemData.init()` and `SystemData.==()` to include new field

- [x] Task 2: Add pause state infrastructure to Agent (AC: #1, #2, #3, #4)
  - [x] Add internal pause state enum or flags to Agent: `_paused: Bool`, `_pauseReason: String?`, `_pauseContinuation: CheckedContinuation<String, Never>?`, `_pauseTimeoutTask: Task<Void, Never>?`
  - [x] Add `_pauseLock: NSLock` for thread-safe access to pause state
  - [x] Add `pauseTimeoutMs: Int` field to `AgentOptions` (default 300000)
  - [x] Update `AgentOptions` memberwise init and `init(from config:)` to include `pauseTimeoutMs`

- [x] Task 3: Implement `Agent.pause(reason:)` (AC: #1)
  - [x] Add public method `pause(reason: String)` to Agent
  - [x] Set `_paused = true`, store reason, capture current time
  - [x] Emit `SDKMessage.system(SystemData(subtype: .paused, message: reason, pausedData: PausedData(...)))` via a stored continuation/yield mechanism
  - [x] Suspend execution by awaiting on a `CheckedContinuation<String, Never>` that `resume(context:)` will resume

- [x] Task 4: Implement `Agent.resume(context:)` (AC: #2)
  - [x] Add public method `resume(context: String)` to Agent
  - [x] Guard that Agent is in paused state; if not, log warning and return
  - [x] Resume the stored `CheckedContinuation` with the provided context string
  - [x] The context string is then injected into the conversation as a user message: "Human has completed the following operations: {context}. Please continue the task."
  - [x] Set `_paused = false`, cancel timeout task

- [x] Task 5: Implement `Agent.abort()` for paused state (AC: #3)
  - [x] Extend existing `interrupt()` behavior: if paused, resume continuation with a special sentinel that triggers cancellation
  - [x] Alternatively: `abort()` calls `interrupt()` which cancels the pause continuation, leading to cancelled state
  - [x] Return `.result(.cancelled)` with summary of steps completed so far

- [x] Task 6: Implement pause timeout (AC: #4)
  - [x] When `pause()` is called, start a `Task.sleep` for `pauseTimeoutMs`
  - [x] If timeout fires before resume, emit `SDKMessage.system(.pausedTimeout)` and transition to cancelled state
  - [x] Cancel timeout task when `resume()` is called

- [x] Task 7: Implement `pause_for_human` built-in tool (AC: #6)
  - [x] Create `Sources/OpenAgentSDK/Tools/Core/PauseForHumanTool.swift`
  - [x] Tool name: `pause_for_human`, description: "Pause agent execution and request human intervention. Use when you cannot complete the task autonomously."
  - [x] Input schema: `{ "type": "object", "properties": { "reason": { "type": "string", "description": "Why human help is needed" } }, "required": ["reason"] }`
  - [x] The tool's `call()` method signals pause via a shared handler mechanism (similar to `AskUser` tool's `_questionHandler` pattern)
  - [x] When paused, the tool suspends (awaits) until resume/abort/timeout
  - [x] On resume: return `ToolResult` with the human's context message
  - [x] On abort/timeout: return `ToolResult(isError: true)` with cancellation message
  - [x] Register in `ToolRegistry.getAllBaseTools(tier: .core)`

- [x] Task 8: Wire pause mechanism into Agent stream loop (AC: #1, #2, #3, #4)
  - [x] The `pause_for_human` tool needs access to the stream's continuation to emit pause/timeout events
  - [x] Use a module-level handler pattern (like `_questionHandler` for AskUser): `_pauseHandler: (@Sendable (String, AsyncStream<SDKMessage>.Continuation) async -> String)?`
  - [x] Set the pause handler at the start of `stream()`, clear at the end
  - [x] Inside the handler: emit paused event, suspend via continuation, emit resumed/timeout event

- [x] Task 9: Write unit tests (AC: #7)
  - [x] Create `Tests/OpenAgentSDKTests/Core/PauseProtocolTests.swift`
  - [x] Test pause emits `.system(.paused)` message with correct PausedData
  - [x] Test resume injects context message and continues execution
  - [x] Test abort from paused state returns `.result(.cancelled)`
  - [x] Test pause timeout transitions to cancelled with `.system(.pausedTimeout)` message
  - [x] Test pause_for_human tool triggers pause when called by LLM
  - [x] Test pause_for_human tool returns human context on resume
  - [x] Test that pause/resume works in both `prompt()` and `stream()` flows

- [x] Task 10: Update module entry point doc comments (AC: #8)
  - [x] Add `PausedData`, `pause_for_human` tool references to `OpenAgentSDK.swift` DocC sections

- [x] Task 11: Build and verify (AC: #8)
  - [x] `swift build` zero errors zero warnings
  - [x] Run full test suite, report total count

## Dev Notes

### Position in Epic and Project

- **Epic 19** (Axion Phase 2 SDK Capabilities), third and final story
- **Prerequisites:** Epic 1 (Agent basics), Epic 7 (session persistence) -- all done
- **Depends on Story 19-1** (cross-run Memory Store) -- done
- **Depends on Story 19-2** (Agent-as-MCP-Server) -- done
- **Source:** Axion Phase 2 requirement, generalized to all SDK consumers
- **New FR70:** Developer can pause/resume/abort Agent execution for human-in-the-loop workflows

### CRITICAL: Understand the Execution Model

The Agent has two execution paths: `prompt()` (blocking) and `stream()` (AsyncStream). The pause protocol must work in BOTH paths.

**For `stream()`:** The `AsyncStream<SDKMessage>.Continuation` is used to yield messages to the consumer. When paused, we emit `.system(.paused)` and suspend. The consumer receives the paused message and calls `resume()`.

**For `prompt()`:** The `prompt()` method returns a `QueryResult` after completion. Pause/resume in `prompt()` means the method blocks until resume/abort/timeout. The `QueryResult` will contain the final result after resumption.

### CRITICAL: How to Suspend Execution from Within a Tool

The `pause_for_human` tool's `call()` method runs inside the agent loop's tool execution phase. To "pause" the entire agent, the tool must suspend (not return) until resume/abort/timeout. This is the core challenge.

**Design approach -- Module-level pause handler (follow AskUser pattern):**

1. A module-level `_pauseHandler` variable (like `_questionHandler` for AskUser):
   ```swift
   nonisolated(unsafe) private var _pauseHandler: (@Sendable (String) async -> PauseResult)?
   ```

2. `PauseResult` enum:
   ```swift
   enum PauseResult: Sendable {
       case resumed(context: String)
       case aborted
       case timedOut
   }
   ```

3. In `stream()`, before the agent loop starts, set the handler:
   ```swift
   _pauseHandler = { [weak self] reason in
       // Emit .paused message via continuation
       // Suspend on a CheckedContinuation<String, Never>
       // Return .resumed(context) when resumed, .aborted/.timedOut otherwise
   }
   ```

4. The `pause_for_human` tool calls `_pauseHandler?(reason)` and awaits the result.

5. `Agent.resume(context:)` resumes the continuation with the context string.

6. `Agent.interrupt()` / `abort()` cancels the continuation (or resumes with abort sentinel).

### CRITICAL: Where Tool Execution Happens in stream()

In `Agent.stream()` (around line 1976), tool execution occurs via:
```swift
let toolResults = await ToolExecutor.executeTools(
    toolUseBlocks: toolUseBlocks,
    tools: allToolProtocols,
    context: ToolContext(...)
)
```

The `pause_for_human` tool's `call()` will be invoked as part of this batch. Since `ToolExecutor.executeTools` uses `TaskGroup` for concurrent tool execution, the `pause_for_human` tool must:
- **Return `isError: true` with a cancellation message** when aborted or timed out (so the agent loop sees a tool error and can decide to stop)
- **Return `isError: false` with the human context** when resumed (so the agent loop continues with the context as a tool result)

After the tool returns, the normal agent loop continues -- the tool result is fed back to the LLM as part of the conversation.

### Architecture Compliance

- **Tools/ depends on Types/ only, never Core/** -- `pause_for_human` tool goes in `Sources/OpenAgentSDK/Tools/Core/` and uses the module-level handler pattern (same as AskUser) to avoid Core/ dependency
- **Actor for shared mutable state** -- Agent uses `NSLock` for pause state (consistent with existing `_closedLock`, `_permissionLock` pattern)
- **No force-unwrap** -- Use `guard let` / `if let` everywhere
- **No Apple-proprietary frameworks** -- `Date`, `NSLock`, `Task.sleep` are cross-platform
- **Error model** -- Tool execution errors captured in `ToolResult(isError: true)`, never throw from tool handler

### Pause/Resume Flow Diagram

```
Agent stream() running
    |
    LLM calls pause_for_human(reason: "Can't find target window")
    |
    pause_for_human.call() invokes _pauseHandler(reason)
    |
    _pauseHandler:
      1. Emits SDKMessage.system(.paused(PausedData)) to stream
      2. Starts timeout task (pauseTimeoutMs)
      3. Suspends on CheckedContinuation<String, Never>
    |
    Consumer receives .paused message
    |
    Consumer either:
    A) Calls agent.resume(context: "I clicked the OK button")
       -> Continuation resumes with context
       -> Timeout task cancelled
       -> _pauseHandler returns .resumed(context)
       -> pause_for_human tool returns ToolResult(isError: false, content: context)
       -> Agent loop continues with context in conversation
    |
    B) Calls agent.interrupt() / agent.abort()
       -> Continuation resumes with abort sentinel
       -> Timeout task cancelled
       -> _pauseHandler returns .aborted
       -> pause_for_human tool returns ToolResult(isError: true, content: "Agent aborted")
       -> Agent loop sees cancelled state, exits with .result(.cancelled)
    |
    C) Timeout fires (5 minutes)
       -> Continuation resumes with timeout sentinel
       -> Emits SDKMessage.system(.pausedTimeout) to stream
       -> _pauseHandler returns .timedOut
       -> pause_for_human tool returns ToolResult(isError: true, content: "Pause timed out")
       -> Agent loop sees cancelled state, exits with .result(.cancelled)
```

### PausedData Struct Design

```swift
/// Data for a pause event, emitted when the agent pauses for human intervention.
public struct PausedData: Sendable, Equatable {
    /// The reason the agent paused (provided by the LLM or developer).
    public let reason: String
    /// The timestamp when the pause started.
    public let pausedAt: Date
    /// Whether the agent can be resumed (true unless already timed out or aborted).
    public let canResume: Bool

    public init(reason: String, pausedAt: Date = Date(), canResume: Bool = true) {
        self.reason = reason
        self.pausedAt = pausedAt
        self.canResume = canResume
    }
}
```

### AgentOptions Extension

Add `pauseTimeoutMs` to `AgentOptions`:

```swift
/// Maximum time in milliseconds the agent will wait in a paused state before
/// automatically cancelling. Defaults to 300000 (5 minutes).
/// Set to `0` to disable timeout (agent waits indefinitely).
public var pauseTimeoutMs: Int
```

Update memberwise init with parameter `pauseTimeoutMs: Int = 300000`.
Update `init(from config:)` to read from config if present.

### pause_for_human Tool Design

Follow the AskUser tool pattern exactly:

```swift
// Module-level handler (like _questionHandler)
nonisolated(unsafe) private var _pauseHandler: (@Sendable (String) async -> PauseResult)?

public func setPauseHandler(_ handler: @Sendable @escaping (String) async -> PauseResult) {
    _pauseHandler = handler
}

public func clearPauseHandler() {
    _pauseHandler = nil
}
```

Tool implementation:
```swift
public func createPauseForHumanTool() -> ToolProtocol {
    return defineTool(
        name: "pause_for_human",
        description: "Pause execution and request human intervention...",
        inputSchema: [...],
        isReadOnly: true
    ) { (input: PauseForHumanInput, context: ToolContext) async throws -> ToolExecuteResult in
        guard let handler = _pauseHandler else {
            return ToolExecuteResult(
                content: "[Non-interactive mode] Pause requested: \(input.reason). No handler available, continuing autonomously.",
                isError: false
            )
        }
        let result = await handler(input.reason)
        switch result {
        case .resumed(let context):
            return ToolExecuteResult(content: "Human completed: \(context)", isError: false)
        case .aborted:
            return ToolExecuteResult(content: "Agent was aborted while paused.", isError: true)
        case .timedOut:
            return ToolExecuteResult(content: "Pause timed out after configured duration.", isError: true)
        }
    }
}
```

### How Other Tool Calls in Same Batch Are Affected

When the LLM calls `pause_for_human` alongside other tools in the same turn, `ToolExecutor.executeTools` runs them concurrently via `TaskGroup`. The `pause_for_human` tool will suspend, but other tools will complete normally. The agent loop waits for ALL tool results before proceeding.

This means:
- Other tools execute and return results normally
- `pause_for_human` suspends until resume/abort/timeout
- Once resumed, all tool results (including the pause result) are sent back to the LLM
- The LLM then continues with the full context

This is acceptable behavior. If needed, a future optimization could cancel other in-flight tools when pause is triggered, but this is NOT required for this story.

### Concurrency Safety Notes

- `_pauseHandler` uses `nonisolated(unsafe)` -- same pattern as `_questionHandler` for AskUser. Safe because: handler is set before agent loop starts, cleared after it ends, and tool execution is serialized within the handler.
- `CheckedContinuation` is `Sendable` and can be safely resumed from any isolation domain.
- `_pauseLock: NSLock` protects pause state (`_paused`, `_pauseReason`, `_pauseContinuation`) from concurrent access by `pause()`, `resume()`, `interrupt()`, and timeout handler.

### File Locations

```
Sources/OpenAgentSDK/Types/SDKMessage.swift                     # MODIFY -- add PausedData, SystemData.Subtype.paused, .pausedTimeout, SystemData.pausedData field
Sources/OpenAgentSDK/Types/AgentTypes.swift                     # MODIFY -- add pauseTimeoutMs to AgentOptions
Sources/OpenAgentSDK/Tools/Core/PauseForHumanTool.swift         # NEW -- pause_for_human tool + PauseResult enum + setPauseHandler/clearPauseHandler
Sources/OpenAgentSDK/Tools/ToolRegistry.swift                   # MODIFY -- add createPauseForHumanTool() to core tier
Sources/OpenAgentSDK/Core/Agent.swift                           # MODIFY -- add pause/resume state, setPauseHandler in stream()/prompt(), wire resume/abort/timeout
Sources/OpenAgentSDK/OpenAgentSDK.swift                          # MODIFY -- add DocC symbol references
Tests/OpenAgentSDKTests/Core/PauseProtocolTests.swift           # NEW -- unit tests for pause/resume/abort/timeout
_bmad-output/implementation-artifacts/sprint-status.yaml        # MODIFY -- status update
```

### Anti-Patterns to Avoid

- Do NOT make pause_for_human throw from the tool handler -- capture errors in `ToolResult(isError: true)`
- Do NOT use force-unwrap (!) -- use guard let / if let
- Do NOT import Core/ from Tools/ -- use module-level handler pattern (same as AskUser)
- Do NOT use Apple-proprietary APIs -- must work on macOS and Linux
- Do NOT use a class or struct for shared pause state in Agent -- use NSLock-protected properties (consistent with existing pattern)
- Do NOT block the stream continuation -- use `CheckedContinuation` for clean suspension
- Do NOT use `AsyncStream` for pause signaling -- `CheckedContinuation` is the correct primitive for one-shot resume
- Do NOT forget to clear `_pauseHandler` when stream/prompt ends (use defer)
- Do NOT forget to cancel timeout task when resume or abort is called
- Do NOT register pause_for_human in specialist or advanced tiers -- it belongs in core tier

### Testing Requirements

- **New test file:** `Tests/OpenAgentSDKTests/Core/PauseProtocolTests.swift`
- **Test categories:**
  - Pause emits `.system(.paused)` with correct PausedData fields
  - Resume injects context and continues agent execution
  - Abort from paused state returns `.result(.cancelled)`
  - Timeout fires after pauseTimeoutMs and returns `.system(.pausedTimeout)`
  - pause_for_human tool triggers pause protocol when called
  - pause_for_human tool in non-interactive mode returns informational message
  - Pause/resume works in `stream()` flow
  - Pause/resume works in `prompt()` flow
- **Key testing challenge:** pause/resume requires async coordination. Use `Task` to simulate:
  1. Start stream in a Task
  2. Collect messages until `.paused` received
  3. In another Task, call `agent.resume(context: "...")`
  4. Verify resumed execution continues
- **After implementation, run full test suite and report total count**

### Previous Story Intelligence

**From Story 19-2 (Agent-as-MCP-Server):**
- Test count at completion: 4640 tests passing, 14 skipped, 0 failures
- `swift build` zero errors zero warnings
- Pattern for adding to OpenAgentSDK.swift DocC section: add bullet points to the appropriate section
- Adding fields to AgentOptions requires updating BOTH memberwise init AND any config-based init
- MCPServer.register() API takes Codable Input types, not `[String: Value]`
- Logger API: `Logger.shared.error("QueryEngine", "event_name", data: [...])`

**From Story 19-1 (Cross-run Memory Store):**
- Adding fields to AgentOptions/ToolContext requires updating BOTH memberwise init AND `init(from config:)`
- Module-level handler pattern (set/clear) works well for tool-to-core communication
- Test files in `Tests/OpenAgentSDKTests/Core/` for core agent features

**From AskUser Tool Pattern (Epic 3):**
- `_questionHandler` uses `nonisolated(unsafe)` -- acceptable for tool lifecycle
- `setQuestionHandler` / `clearQuestionHandler` pattern is clean and proven
- Non-interactive fallback returns `isError: false` with informational message
- Handler set before agent loop, cleared after completion (use defer)

### Project Structure Notes

- New file `PauseForHumanTool.swift` goes in `Sources/OpenAgentSDK/Tools/Core/` (same directory as AskUserTool.swift)
- No Package.swift changes needed (all files are in the existing OpenAgentSDK target)
- No new dependencies needed
- Test file goes in `Tests/OpenAgentSDKTests/Core/` (create if needed, or reuse existing)

### Claude Code Integration Example

After implementation, a user would use pause/resume like this:

```swift
let agent = createAgent(options: AgentOptions(
    model: "claude-sonnet-4-6",
    tools: getAllBaseTools(tier: .core),
    systemPrompt: "You are a desktop automation agent."
))

for await message in agent.stream("Open Calculator and click the OK button") {
    switch message {
    case .system(let data):
        if data.subtype == .paused, let pausedData = data.pausedData {
            print("Agent paused: \(pausedData.reason)")
            // Show UI to user, let them take action
            // When done:
            agent.resume(context: "I manually clicked the OK button")
        } else if data.subtype == .pausedTimeout {
            print("Pause timed out!")
        }
    case .result(let data):
        print("Done: \(data.status)")
    default:
        break
    }
}
```

### References

- [Source: Sources/OpenAgentSDK/Tools/Core/AskUserTool.swift] -- Module-level handler pattern (set/clear), nonisolated(unsafe) variable, non-interactive fallback
- [Source: Sources/OpenAgentSDK/Types/SDKMessage.swift:339] -- SystemData struct, Subtype enum, init pattern
- [Source: Sources/OpenAgentSDK/Types/AgentTypes.swift:229] -- AgentOptions struct, memberwise init pattern
- [Source: Sources/OpenAgentSDK/Core/Agent.swift:43] -- nonisolated(unsafe) _interrupted flag pattern
- [Source: Sources/OpenAgentSDK/Core/Agent.swift:279] -- interrupt() method pattern
- [Source: Sources/OpenAgentSDK/Core/Agent.swift:1976] -- ToolExecutor.executeTools() in stream() where pause_for_human.call() executes
- [Source: Sources/OpenAgentSDK/Core/Agent.swift:1394] -- AsyncStream continuation used for emitting messages
- [Source: Sources/OpenAgentSDK/Core/Agent.swift:2270] -- yieldStreamCancelled() pattern for cancellation result
- [Source: Sources/OpenAgentSDK/Tools/ToolRegistry.swift:64] -- getAllBaseTools(tier: .core) where pause_for_human is registered
- [Source: Sources/OpenAgentSDK/Types/HookTypes.swift:7] -- HookEvent enum (may want to add .paused/.resumed hooks in future)
- [Source: _bmad-output/implementation-artifacts/19-2-agent-as-mcp-server.md] -- Previous story learnings and patterns
- [Source: _bmad-output/project-context.md] -- Project rules (actor for shared state, module boundaries, no force-unwrap, cross-platform)

## Dev Agent Record

### Agent Model Used

Claude (GLM-5.1[1m])

### Debug Log References

### Completion Notes List

- Implemented PausedData struct as SDKMessage.PausedData with reason, pausedAt, canResume fields (AC5)
- Added SystemData.Subtype.paused and .pausedTimeout cases (AC5)
- Added pausedData optional field to SystemData with updated init and == (AC5)
- Added pauseTimeoutMs field to AgentOptions with default 300000 (AC4)
- Added pause/resume/abort state to Agent with _pauseLock, _paused, _pauseContinuation, _pauseTimeoutTask
- Implemented Agent.pause(reason:) to set paused state (AC1)
- Implemented Agent.resume(context:) to resume continuation with context string (AC2)
- Extended Agent.interrupt() to resume pause continuation with abort sentinel (AC3)
- Implemented pause timeout via Task.sleep in pause handler (AC4)
- Created PauseForHumanTool.swift with PauseResult enum, setPauseHandler/clearPauseHandler, and createPauseForHumanTool() (AC6)
- Registered pause_for_human in ToolRegistry.getAllBaseTools(tier: .core) (AC6)
- Wired setupPauseHandler into stream() with defer cleanup (AC1, AC2, AC3, AC4)
- Wired setupPromptPauseHandler into promptImpl() with defer cleanup
- Updated OpenAgentSDK.swift DocC section with Pause/Resume Protocol references
- Fixed 3 existing tests that expected core tool count = 10 (now 11)
- Updated test file to use SDKMessage.PausedData instead of bare PausedData
- All 4673 tests pass, 14 skipped, 0 failures

### File List

- Sources/OpenAgentSDK/Types/SDKMessage.swift (MODIFIED -- added PausedData struct, SystemData.Subtype.paused/.pausedTimeout, SystemData.pausedData field)
- Sources/OpenAgentSDK/Types/AgentTypes.swift (MODIFIED -- added pauseTimeoutMs to AgentOptions)
- Sources/OpenAgentSDK/Tools/Core/PauseForHumanTool.swift (NEW -- PauseResult enum, setPauseHandler/clearPauseHandler, createPauseForHumanTool())
- Sources/OpenAgentSDK/Tools/ToolRegistry.swift (MODIFIED -- added createPauseForHumanTool() to core tier)
- Sources/OpenAgentSDK/Core/Agent.swift (MODIFIED -- added pause state, pause/resume methods, setupPauseHandler/setupPromptPauseHandler, wired into stream/prompt)
- Sources/OpenAgentSDK/OpenAgentSDK.swift (MODIFIED -- added DocC Pause/Resume Protocol section)
- Tests/OpenAgentSDKTests/Core/PauseProtocolTests.swift (MODIFIED -- fixed PausedData references)
- Tests/OpenAgentSDKTests/Compat/CompatToolSystemTests.swift (MODIFIED -- updated core tool count 10->11)
- Tests/OpenAgentSDKTests/Tools/Core/FileToolsRegistryTests.swift (MODIFIED -- updated core tool count 10->11)

### Change Log

- 2026-05-12: Implemented human-in-the-loop pause protocol (Story 19-3). All 8 ACs satisfied. 4673 tests passing, 14 skipped, 0 failures.
