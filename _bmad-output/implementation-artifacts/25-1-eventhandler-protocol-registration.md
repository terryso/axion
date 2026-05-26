# Story 25.1: EventHandler Protocol 与注册机制

**Status:** done
**Epic:** 25 (EventHandler 体系)
**Priority:** P0

## Implementation Summary

Code already implemented in Epic 24:
- `Sources/AxionCLI/Services/EventHandler.swift` — Protocol definition (Actor-based, subscribe/dispatch)
- `Sources/AxionCLI/Services/EventHandlerContext.swift` — Context struct with sessionId, config, runCompleteContext, sessionStore
- `Sources/AxionCLI/Services/AxionRuntime.swift` — Handler registration (`registerHandler`), event loop (`startEventLoop/stopEventLoop`), dispatch mechanism (`dispatchToHandlers`)
- `Tests/AxionCLITests/Services/EventHandlerTests.swift` — 7 tests (dispatch, filtering, wildcard, multi-handler)
- `Tests/AxionCLITests/Services/EventHandlerContextTests.swift` — Context construction tests

## Acceptance Criteria

All AC met via existing implementation:
- ✅ Handler subscribed to ToolCompletedEvent receives matching event
- ✅ Handler subscribed to ToolCompletedEvent ignores AgentStartedEvent
- ✅ Multiple handlers all receive matching events
- ✅ Handler error isolation (do/catch in dispatchToHandlers)
