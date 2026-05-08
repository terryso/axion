---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04-generate-tests
  - step-04c-aggregate
  - step-05-validate-and-complete
lastStep: step-05-validate-and-complete
lastSaved: '2026-05-08'
storyId: '1.2'
storyKey: 1-2-helper-mcp-server-foundation
storyFile: _bmad-output/implementation-artifacts/1-2-helper-mcp-server-foundation.md
atddChecklistPath: _bmad-output/test-artifacts/atdd-checklist-1-2-helper-mcp-server-foundation.md
generatedTestFiles:
  - Tests/AxionHelperTests/MCP/HelperMCPServerTests.swift
  - Tests/AxionHelperTests/MCP/HelperProcessSmokeTests.swift
  - Tests/AxionHelperTests/MCP/HelperScaffoldTests.swift
inputDocuments:
  - _bmad-output/implementation-artifacts/1-2-helper-mcp-server-foundation.md
  - _bmad/tea/config.yaml
  - _bmad-output/planning-artifacts/architecture.md
  - _bmad-output/planning-artifacts/epics.md
  - .claude/skills/bmad-testarch-atdd/resources/tea-index.csv
---

# ATDD Checklist: Story 1.2 - Helper MCP Server 基础

## TDD Red Phase (Current)

Red-phase test scaffolds generated. All tests use `XCTSkip()` to indicate TDD red phase.

- **Unit Tests**: 13 test methods in HelperMCPServerTests.swift (all skipped via XCTSkip)
- **Integration Tests**: 3 test methods in HelperProcessSmokeTests.swift (all skipped via XCTSkip)
- **Scaffold Tests**: 4 test methods in HelperScaffoldTests.swift (2 active, 2 skipped)
- **Total**: 20 test methods (18 in RED phase, 2 compile-time checks active)

## Acceptance Criteria Coverage

| AC | Description | Priority | Test File | Test Count | Status |
|----|-------------|----------|-----------|------------|--------|
| AC1 | MCP initialize 响应 | P0 | HelperMCPServerTests.swift, HelperProcessSmokeTests.swift, HelperScaffoldTests.swift | 5 | RED |
| AC2 | tools/list 响应 | P0 | HelperMCPServerTests.swift | 7 | RED |
| AC3 | 未知工具调用错误 | P0 | HelperMCPServerTests.swift | 2 | RED |
| AC4 | EOF 优雅退出 | P0 | HelperMCPServerTests.swift, HelperProcessSmokeTests.swift | 3 | RED |

**All 4 acceptance criteria have corresponding test coverage.**

## Priority Distribution

| Priority | Test Count | Percentage |
|----------|------------|------------|
| P0 | 14 | 70% |
| P1 | 4 | 20% |
| Compile-time | 2 | 10% |

## Test Level Strategy

This is a **backend (Swift/SPM)** project. Test level selection:

- **Unit Tests** (primary): MCPServer creation, ToolRegistrar registration, tool name validation
  - Used for: AC1 (server creation), AC2 (tool listing), AC3 (unknown tool error)
  - Justification: MCPServer and ToolRegistrar are testable in-process using actor API
  - File: HelperMCPServerTests.swift

- **Integration Tests** (supplementary): Process-level MCP stdio communication
  - Used for: AC1 (initialize JSON-RPC), AC4 (EOF graceful exit), NFR2 (startup time)
  - Justification: Verifies actual process behavior with stdin/stdout pipes
  - File: HelperProcessSmokeTests.swift

- **Scaffold Tests** (infrastructure): Module imports and type existence
  - Used for: Build configuration verification, type existence
  - File: HelperScaffoldTests.swift

## Test Files Created

| File | Tests | ACs Covered | Lines |
|------|-------|-------------|-------|
| `Tests/AxionHelperTests/MCP/HelperMCPServerTests.swift` | 13 | AC1, AC2, AC3 | ~230 |
| `Tests/AxionHelperTests/MCP/HelperProcessSmokeTests.swift` | 3 | AC1, AC4 | ~210 |
| `Tests/AxionHelperTests/MCP/HelperScaffoldTests.swift` | 4 | AC1 | ~60 |

## Red-Green-Refactor Workflow

### RED Phase (Current - TEA Responsibility)

19 test methods are marked with `XCTSkipIf(true, "ATDD RED PHASE: ...")`. Tests assert EXPECTED behavior based on acceptance criteria. When run via `swift test`, skipped tests will be recorded as skipped (not failed), documenting the TDD red phase.

1 active compile-time check in HelperScaffoldTests verifies that the MCP module is importable (already passing from Story 1.1's Package.swift).

### GREEN Phase (DEV Team Responsibility)

During implementation of each task:

1. **Task 1: HelperMCPServer 核心服务**
   - Create `Sources/AxionHelper/MCP/HelperMCPServer.swift`
   - Create `Sources/AxionHelper/MCP/ToolRegistrar.swift` with all 15 stub tools
   - Remove `XCTSkipIf` from HelperMCPServerTests tests
   - Remove `XCTSkipIf` from HelperScaffoldTests.test_toolRegistrar_existsInAxionHelper
   - Run `swift test --filter HelperMCPServerTests` -- verify tool registration works

2. **Task 2: 更新 AxionHelper main.swift**
   - Replace placeholder main.swift with MCP Server startup
   - Remove `XCTSkipIf` from HelperProcessSmokeTests tests
   - Run `swift build` then `swift test --filter HelperProcessSmokeTests`

3. **Task 3: Package.swift 添加 MCPTool 依赖**
   - Add `.product(name: "MCPTool", package: "mcp-swift-sdk")` to AxionHelper dependencies
   - Remove `XCTSkipIf` from HelperScaffoldTests.test_mcpToolModule_importsSuccessfully
   - Run `swift test --filter HelperScaffoldTests`

### REFACTOR Phase

After GREEN:
- Verify all tests pass with `swift test`
- Ensure test naming follows `test_方法名_场景_预期结果` convention
- Verify no hardcoded test data
- Confirm tests are deterministic (no network calls, no timing dependencies except NFR2)

## Task-to-Test Mapping

| Story Task | Tests to Activate | Expected Behavior |
|------------|-------------------|-------------------|
| Task 1.1: HelperMCPServer.swift | HelperScaffoldTests.test_toolRegistrar_existsInAxionHelper, HelperMCPServerTests (AC1, AC3) | MCPServer created, tools registered, unknown tools return error |
| Task 1.2: ToolRegistrar.swift | HelperMCPServerTests (AC2: 5 tests) | All 15 tools registered with name, description, inputSchema |
| Task 2.1: main.swift MCP startup | HelperProcessSmokeTests.test_helperProcess_initializeResponds | Process responds to JSON-RPC initialize |
| Task 2.2: stdin EOF handling | HelperProcessSmokeTests.test_helperProcess_gracefulExitOnEOF | Process exits cleanly on EOF |
| Task 3: MCPTool dependency | HelperScaffoldTests.test_mcpToolModule_importsSuccessfully | MCPTool module imports |

## Execution Commands

```bash
# Build the project first (required for process-level tests)
swift build

# Run all tests (most skipped in RED phase)
swift test

# Run specific test files
swift test --filter HelperMCPServerTests
swift test --filter HelperProcessSmokeTests
swift test --filter HelperScaffoldTests

# Build without running tests
swift build

# Run a specific test by name
swift test --filter test_toolsList_returnsAllRegisteredTools
```

## Key Assumptions

1. **MCPServer API**: Tests use the MCPServer actor API from mcp-swift-sdk v0.1.x. The `toolRegistry.definitions` property returns `[Tool]` for all registered tools. The `toolRegistry.execute()` method throws `MCPError.invalidParams` for unknown tools.

2. **@Tool macro registration**: ToolRegistrar is expected to use the `@Tool` macro pattern (from MCPTool module) to define tools. Each tool struct has `static let name`, `static let description`, `@Parameter` properties, and a `perform()` method returning a stub string.

3. **Process path**: HelperProcessSmokeTests assumes the AxionHelper executable is at `.build/debug/AxionHelper` after `swift build`. This follows standard SPM conventions.

4. **15 tool minimum**: Story requires at least 15 tools registered (launch_app, list_apps, list_windows, get_window_state, click, double_click, right_click, type_text, press_key, hotkey, scroll, drag, screenshot, get_accessibility_tree, open_url).

5. **snake_case tool names**: All tool names must match the snake_case pattern and align with AxionCore/Constants/ToolNames.swift constants.

6. **stdin EOF behavior**: MCPServer's `run(transport: .stdio)` internally creates StdioTransport and blocks until stdin closes. Closing the write end of the pipe triggers EOF, causing clean exit.

## Knowledge Base References

- `test-quality.md`: Deterministic tests, explicit assertions, under 300 lines per test file
- `test-levels-framework.md`: Unit tests for MCPServer API, integration tests for process behavior
- `test-priorities-matrix.md`: P0 for core MCP protocol behavior, P1 for naming conventions and edge cases
- `component-tdd.md`: Red-green-refactor cycle with XCTSkip pattern

## Next Steps

1. **DEV team**: Implement Story 1.2 following the task list (Tasks 1-4)
2. **During implementation**: Remove `XCTSkipIf(true, ...)` from tests as each task completes
3. **After GREEN**: Run `swift test` to verify all tests pass
4. **Next story**: Create ATDD tests for Story 1.3 (应用启动与窗口管理)
