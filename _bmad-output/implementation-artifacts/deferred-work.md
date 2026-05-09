# Deferred Work

## Deferred from: code review of 1-2-helper-mcp-server-foundation (2026-05-08)

- ToolNames.swift missing constants for hotkey/scroll/list_apps/get_window_state/drag — these tools are stubs in 1.2, constants will be needed when implementing in 1.3-1.5
- ToolRegistrar.swift is a single 262-line file — will need splitting when tools get real implementations in 1.3-1.5, acceptable for stub phase, restructure during real implementation
- Process smoke test has fragile timing (200ms sleep after launch) — acceptable trade-off for integration tests, can be improved with retry logic later

## Deferred from: code review of 2-3-axion-setup-first-time-config (2026-05-09)

- `CGPreflightScreenCaptureAccess()` triggers system dialog on macOS — no pure "check-only" API exists for screen recording permission. This is an Apple API limitation. Acceptable for now; may need documentation in user-facing help text.
- `maskApiKey` reveals 9/10 characters for keys of exactly length 10 — spec design gap. Real Anthropic API keys are 100+ chars so practical risk is negligible. Spec masking policy could be tightened in a future iteration.
- `PermissionChecker` uses static methods with no protocol abstraction — not mockable for testing. Story 2.4 (axion doctor) will reuse this and may need to introduce a protocol at that point.

## Deferred from: code review of 3-2-prompt-management-planning-engine (2026-05-10)

- `resolvePromptDirectory()` fallback returns a path that may not exist, leading to unclear error messages when prompts directory is missing — not introduced by this story, pre-existing design choice that can be improved in a future iteration
