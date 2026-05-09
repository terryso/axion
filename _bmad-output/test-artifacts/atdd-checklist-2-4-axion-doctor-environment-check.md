---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04-generate-tests
  - step-04c-aggregate
  - step-05-validate-and-complete
lastStep: step-05-validate-and-complete
lastSaved: '2026-05-09'
storyId: '2.4'
storyKey: '2-4-axion-doctor-environment-check'
storyFile: '_bmad-output/implementation-artifacts/2-4-axion-doctor-environment-check.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-2-4-axion-doctor-environment-check.md'
generatedTestFiles:
  - Tests/AxionCLITests/Commands/DoctorCommandTests.swift
inputDocuments:
  - _bmad-output/implementation-artifacts/2-4-axion-doctor-environment-check.md
  - _bmad-output/project-context.md
  - Sources/AxionCore/Models/AxionConfig.swift
  - Sources/AxionCore/Errors/AxionError.swift
  - Sources/AxionCLI/Commands/DoctorCommand.swift
  - Sources/AxionCLI/Commands/SetupCommand.swift
  - Sources/AxionCLI/Config/ConfigManager.swift
  - Sources/AxionCLI/Permissions/PermissionChecker.swift
  - Sources/AxionCLI/IO/SetupIO.swift
  - Tests/AxionCLITests/Commands/SetupCommandTests.swift
  - Tests/AxionCLITests/Config/ConfigManagerTests.swift
---

# ATDD Checklist: Story 2.4 — axion doctor 环境检查命令

## TDD Red Phase (Current)

所有测试使用 `throw XCTSkip("RED: ...")` 标记为跳过状态（TDD red phase）。

- Unit Tests: **21 tests** (all skipped via XCTSkip)
  - DoctorCommandTests: 21 tests

## Acceptance Criteria Coverage

| AC | Description | Tests | Priority |
|----|-------------|-------|----------|
| AC1 | API Key 检查 | `test_doctor_reportsApiKeyOk_whenConfigured` | P0 |
| AC2 | API Key 缺失建议 | `test_doctor_reportsApiKeyMissing_whenNoConfig`, `test_doctor_reportsApiKeyMissing_whenNoKey` | P0 |
| AC3 | Accessibility 权限检查 | `test_doctor_reportsAccessibilityStatus` | P0 |
| AC4 | 屏幕录制权限检查 | `test_doctor_reportsScreenRecordingStatus` | P0 |
| AC5 | macOS 版本检查 | `test_doctor_reportsMacOSVersion`, `test_doctor_reportsUnsupportedMacOS` | P0 |
| AC6 | 所有检查通过 | `test_doctor_showsAllChecksPassed_whenEverythingOk` | P0 |
| AC7 | 明确修复建议 | `test_doctor_showsFixHints_forFailedChecks` | P0 |
| AC8 | API Key 不泄露 | `test_doctor_masksApiKey_inOutput` | P0 |
| AC9 | 配置文件完整性检查 | `test_doctor_reportsCorruptConfig` | P0 |

## Test Strategy

### Detected Stack: Backend (Swift/XCTest)

- **Unit Tests** for pure functions, business logic, and edge cases
- **Protocol-based mocking** (DoctorIO protocol) for terminal I/O isolation
- **Temporary directory isolation** for file operations (reuses SetupCommandTests pattern)
- **SystemChecker** abstracted for macOS version testing

### Test Levels

| Level | Count | Scope |
|-------|-------|-------|
| P0 — Critical Path | 13 | Type existence, config checks, API Key checks, macOS version, permission checks, output format |
| P1 — Edge Cases | 8 | Corrupt config, masked API key detail, fix hint format, failure count output |

### Key Test Patterns Used

1. **XCTSkip red-phase scaffolding** — Each test starts with `throw XCTSkip("RED: ...")`
2. **MockDoctorIO** — Implements DoctorIO protocol with captured outputs array
3. **Temporary directory isolation** — Tests use `NSTemporaryDirectory() + UUID` for file operations
4. **Test naming**: `test_doctor_{scenario}_{expectedResult}` following project conventions

### Key Design Decisions

1. **DoctorIO protocol** — Single `write(_ line: String)` method (simpler than SetupIO, no prompts needed)
2. **runDoctor(io:configDirectory:)** — Static method pattern matching SetupCommand.runSetup()
3. **SystemChecker** — Separate struct for macOS version check, testable in isolation
4. **PermissionChecker reuse** — Direct reuse from Story 2.3, no new permission logic
5. **ConfigManager reuse** — Doctor reads config via FileManager + JSONDecoder synchronously (not async loadConfig)

## Next Steps (Task-by-Task Activation)

During implementation of each task:

1. Open `Tests/AxionCLITests/Commands/DoctorCommandTests.swift`
2. Remove the `throw XCTSkip("RED: ...")` line from tests for the current task
3. Run tests: `swift test --filter "AxionCLITests.Commands.DoctorCommandTests"`
4. Verify the activated test **fails first** (red), then implement the feature until it passes (green)
5. Commit passing tests

### Activation Order (matches Story task order)

| Task | Activate Tests | Description |
|------|---------------|-------------|
| Task 1.1-1.3 | `test_checkStatus_enumExists`, `test_checkResult_structExists`, `test_doctorReport_allOkComputed`, `test_doctorReport_notAllOkComputed` | CheckResult / DoctorReport 模型 |
| Task 1.4-1.5 | `test_doctorIO_protocolExists`, `test_mockDoctorIO_capturesWrites`, `test_terminalDoctorIO_typeExists` | DoctorIO 协议和终端实现 |
| Task 1.6-1.7 | `test_doctor_reportsApiKeyMissing_whenNoConfig`, `test_doctor_reportsApiKeyOk_whenConfigured`, `test_doctor_reportsApiKeyMissing_whenNoKey`, `test_doctor_reportsCorruptConfig`, `test_doctor_reportsMacOSVersion` | 核心检查逻辑 |
| Task 2 | `test_doctor_reportsUnsupportedMacOS` | SystemChecker |
| Task 1.8-1.9 | `test_doctor_masksApiKey_inOutput`, `test_doctor_showsFixHints_forFailedChecks`, `test_doctor_showsAllChecksPassed_whenEverythingOk`, `test_doctor_showsFailureCount_whenChecksFail` | 输出格式和汇总 |

## Implementation Guidance

### Source files to create/modify

1. **Modify** `Sources/AxionCLI/Commands/DoctorCommand.swift` — Implement doctor logic
2. **Create** `Sources/AxionCLI/IO/DoctorIO.swift` — DoctorIO protocol
3. **Create** `Sources/AxionCLI/IO/TerminalDoctorIO.swift` — Terminal output implementation
4. **Create** `Sources/AxionCLI/Checks/SystemChecker.swift` — macOS version checker

### Components to reuse

- `PermissionChecker` (Sources/AxionCLI/Permissions/PermissionChecker.swift)
- `ConfigManager.defaultConfigDirectory` (Sources/AxionCLI/Config/ConfigManager.swift)
- `maskApiKey()` (Sources/AxionCLI/Commands/SetupCommand.swift)
- `AxionConfig` (Sources/AxionCore/Models/AxionConfig.swift)
