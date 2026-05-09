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
storyId: '2.3'
storyKey: '2-3-axion-setup-first-time-config'
storyFile: '_bmad-output/implementation-artifacts/2-3-axion-setup-first-time-config.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-2-3-axion-setup-first-time-config.md'
generatedTestFiles:
  - Tests/AxionCLITests/Commands/SetupCommandTests.swift
inputDocuments:
  - _bmad-output/implementation-artifacts/2-3-axion-setup-first-time-config.md
  - _bmad-output/project-context.md
  - Sources/AxionCore/Models/AxionConfig.swift
  - Sources/AxionCore/Errors/AxionError.swift
  - Sources/AxionCLI/Commands/SetupCommand.swift
  - Sources/AxionCLI/Config/ConfigManager.swift
  - Tests/AxionCLITests/Commands/AxionCommandTests.swift
  - Tests/AxionCLITests/Config/ConfigManagerTests.swift
---

# ATDD Checklist: Story 2.3 — axion setup 首次配置命令

## TDD Red Phase (Current)

所有测试使用 `throw XCTSkip("RED: 等待实现")` 标记为跳过状态。

- Unit Tests: **25 tests** (all skipped via XCTSkip)
  - SetupCommandTests: 25 tests

## Acceptance Criteria Coverage

| AC | Description | Tests | Priority |
|----|-------------|-------|----------|
| AC1 | 提示输入 API Key | `test_setup_promptsForApiKey_whenNoConfig` | P0 |
| AC2 | API Key 写入 config.json | `test_setup_savesApiKey_toConfigJson`, `test_setup_createsConfigDirectory_ifMissing` | P0 |
| AC3 | Accessibility 权限检查 | `test_permissionChecker_checkAccessibility_returnsStatus`, `test_setup_showsAccessibilityGranted`, `test_setup_showsAccessibilityNotGranted` | P0/P1 |
| AC4 | 屏幕录制权限检查 | `test_permissionChecker_checkScreenRecording_returnsStatus`, `test_setup_showsScreenRecordingGranted`, `test_setup_showsScreenRecordingNotGranted` | P0/P1 |
| AC5 | 完成提示 | `test_setup_showsCompletionMessage` | P0 |
| AC6 | API Key 不泄露 | `test_maskApiKey_longKey_showsMasked`, `test_maskApiKey_shortKey_showsMasked`, `test_maskApiKey_emptyKey_returnsEmpty`, `test_setup_showsMaskedApiKey_inSummary` | P0/P1 |
| AC7 | 重复运行处理 | `test_setup_detectsExistingApiKey`, `test_setup_keepsExistingApiKey_whenUserDeclines`, `test_setup_replacesApiKey_whenUserConfirms` | P0/P1 |

## Test Strategy

### Detected Stack: Backend (Swift/XCTest)

- **Unit Tests** for pure functions, business logic, and edge cases
- **Protocol-based mocking** (SetupIO protocol) for terminal I/O isolation
- **Temporary directory isolation** for file operations

### Test Levels

| Level | Count | Scope |
|-------|-------|-------|
| P0 — Critical Path | 17 | Type existence, API Key flow, masking, setup completion, file permissions |
| P1 — Edge Cases | 8 | Short key mask, empty key, permission not granted, user declines replacement |

### Key Test Patterns Used

1. **XCTSkip red-phase scaffolding** — Each test starts with `throw XCTSkip("RED: ...")`
2. **MockSetupIO** — Implements SetupIO protocol with preset inputs and captured outputs
3. **Temporary directory isolation** — Tests use `NSTemporaryDirectory() + UUID` for file operations
4. **PermissionStatus mock** — Tests use MockPermissionChecker for deterministic permission states
5. **Test naming**: `test_{unit}_{scenario}_{expectedResult}` following project conventions

## Next Steps (Task-by-Task Activation)

During implementation of each task:

1. Open the target test file
2. Remove the `throw XCTSkip("RED: ...")` line from tests for the current task
3. Run tests: `swift test --filter "AxionCLITests.Commands.SetupCommandTests"`
4. Verify the activated test **fails first** (red), then implement the feature until it passes (green)
5. Commit passing tests

### Activation Order (Recommended)

**Phase 1 — SetupIO Protocol & MockSetupIO (Task 1.2, 1.3):**
- Activate: `test_setupIO_protocolExists` -> `test_mockSetupIO_capturesWrites` -> `test_mockSetupIO_returnsPresetInputs`

**Phase 2 — maskApiKey & Utility Functions (Task 1.5):**
- Activate: `test_maskApiKey_longKey_showsMasked` -> `test_maskApiKey_shortKey_showsMasked` -> `test_maskApiKey_emptyKey_returnsEmpty`

**Phase 3 — PermissionChecker (Task 2):**
- Activate: `test_permissionChecker_typeExists` -> `test_permissionStatus_enumExists` -> `test_permissionChecker_checkAccessibility_returnsStatus` -> `test_permissionChecker_checkScreenRecording_returnsStatus`

**Phase 4 — SetupCommand Main Flow (Task 1.1, 1.4):**
- Activate: `test_setup_promptsForApiKey_whenNoConfig` -> `test_setup_savesApiKey_toConfigJson` -> `test_setup_createsConfigDirectory_ifMissing` -> `test_setup_showsMaskedApiKey_inSummary` -> `test_setup_showsAccessibilityGranted` -> `test_setup_showsAccessibilityNotGranted` -> `test_setup_showsScreenRecordingGranted` -> `test_setup_showsScreenRecordingNotGranted` -> `test_setup_showsCompletionMessage`

**Phase 5 — Repeated Run Handling (Task 1.4 continued):**
- Activate: `test_setup_detectsExistingApiKey` -> `test_setup_keepsExistingApiKey_whenUserDeclines` -> `test_setup_replacesApiKey_whenUserConfirms` -> `test_setup_configFilePermissions_are600`

**Phase 6 — Edge Cases:**
- Activate: `test_setup_rejectsEmptyApiKey_andReprompts` -> `test_setup_trimmedApiKey_isSaved`

## Implementation Guidance

### Types to Implement

1. **SetupIO** (protocol) — `Sources/AxionCLI/IO/SetupIO.swift`
   ```swift
   protocol SetupIO {
       func write(_ line: String)
       func prompt(_ question: String) -> String
       func promptSecret(_ question: String) -> String
       func confirm(_ question: String, defaultAnswer: Bool) -> Bool
   }
   ```

2. **TerminalSetupIO** (struct) — `Sources/AxionCLI/IO/TerminalSetupIO.swift`
   - Real terminal I/O using FileHandle.stdin/stdout
   - `promptSecret()` uses `stty -echo` for hidden input

3. **PermissionChecker** (enum, static methods) — `Sources/AxionCLI/Permissions/PermissionChecker.swift`
   ```swift
   enum PermissionStatus {
       case granted
       case notGranted
       case unknown
   }
   struct PermissionChecker {
       static func checkAccessibility() -> PermissionStatus
       static func checkScreenRecording() -> PermissionStatus
   }
   ```

4. **SetupCommand.run()** — Rewrite `Sources/AxionCLI/Commands/SetupCommand.swift`
   - Inject `SetupIO` for testability
   - Full guided flow: API Key -> save -> permissions -> completion

5. **maskApiKey()** — Utility function (can be in SetupCommand or a helper)
   - `sk-ant-***...xyz` format for long keys
   - `***` for keys <= 9 chars

### Key Constraints

- API Key stored in config.json with file permission 0o600 (not Keychain)
- SetupIO protocol enables testability without real terminal I/O
- PermissionChecker is for user guidance, not functional gate
- No `print()` — use `SetupIO.write()` for all output
- All errors use `AxionError.configError(reason:)`
- Tests use temporary directories, never real `~/.axion/`

## Key Risks and Assumptions

1. **Permission API availability** — `AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()` check the calling process (CLI), not the Helper app. Setup is guidance-oriented.
2. **PermissionStatus mocking** — Tests mock PermissionChecker since real permission state is non-deterministic in test environments.
3. **ConfigManager dependency** — SetupCommand tests assume ConfigManager API (saveConfigFile, ensureConfigDirectory) from Story 2.2 is stable.
4. **File permission tests** — POSIX permission checks may behave differently on some filesystems; tests use temporary directories for isolation.
