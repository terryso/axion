# Deferred Work

## Deferred from: code review of 1-2-helper-mcp-server-foundation (2026-05-08)

- ToolNames.swift missing constants for hotkey/scroll/list_apps/get_window_state/drag — these tools are stubs in 1.2, constants will be needed when implementing in 1.3-1.5
- ToolRegistrar.swift is a single 262-line file — will need splitting when tools get real implementations in 1.3-1.5, acceptable for stub phase, restructure during real implementation
- Process smoke test has fragile timing (200ms sleep after launch) — acceptable trade-off for integration tests, can be improved with retry logic later
