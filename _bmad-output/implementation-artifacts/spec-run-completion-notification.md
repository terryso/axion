---
title: 'Run Completion macOS Desktop Notification'
type: 'feature'
created: '2026-05-23'
status: 'done'
route: 'one-shot'
---

# Run Completion macOS Desktop Notification

## Intent

**Problem:** When `axion run` operates a fullscreen or maximized app, the user cannot see the terminal and doesn't know when the AI finishes. Users are afraid to touch the computer, not knowing if it's safe.

**Approach:** Send a macOS system notification via `osascript display notification` when a run completes. The notification includes the task description, status (success/failure/cancelled), and elapsed time. Skipped in JSON mode since programmatic callers don't need desktop notifications.

## Suggested Review Order

1. [`sendDesktopNotification()`](../Sources/AxionCLI/Services/RunOrchestrator.swift:435) — New helper: osascript notification with proper AppleScript escaping
2. [Notification in `execute()`](../Sources/AxionCLI/Services/RunOrchestrator.swift:247) — Placed after lock release and all cleanup, guarded by `!runConfig.json`
3. [Notification in `executeSkillDirectly()`](../Sources/AxionCLI/Services/RunOrchestrator.swift:305) — Placed after `agent.close()` to avoid delaying cleanup
