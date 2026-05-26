# Story 25.6: ReviewHandler + NotificationHandler

**Status:** backlog
**Epic:** 25 (EventHandler 体系)
**Priority:** P1
**Data Source:** Review: SessionStore + Agent reference; Notification: RunCompleteContext

## Goal
Trigger code review and desktop notification after agent completion.

## Implementation

1. Create `Sources/AxionCLI/Runtime/Handlers/ReviewHandler.swift`
   - Subscribe to AgentCompletedEvent
   - Conditions: !dryrun && !noMemory && !noReview
   - Load messages from sessionStore.load()
   - Call ReviewOrchestrator.executeReview()

2. Create `Sources/AxionCLI/Runtime/Handlers/NotificationHandler.swift`
   - Subscribe to terminal events
   - Get cost from runCompleteContext
   - Send desktop notification with status/cost/duration

3. Create `Sources/AxionCore/Utils/MessageConverter.swift`
   - Convert [[String: Any]] to [SDKMessage] via JSONSerialization bridge

## Acceptance Criteria

- Given ReviewHandler with conditions met, When agent completes, Then review triggered with messages from sessionStore
- Given NotificationHandler registered, When agent completes, Then desktop notification sent
- Given SessionStore not yet persisted, When ReviewHandler loads, Then graceful error handling
