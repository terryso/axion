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
storyId: '2.2'
storyKey: '2-2-config-system-keychain-storage'
storyFile: '_bmad-output/implementation-artifacts/2-2-config-system-keychain-storage.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-2-2-config-system-keychain-storage.md'
generatedTestFiles:
  - Tests/AxionCLITests/Config/KeychainStoreTests.swift
  - Tests/AxionCLITests/Config/ConfigManagerTests.swift
inputDocuments:
  - _bmad-output/implementation-artifacts/2-2-config-system-keychain-storage.md
  - _bmad-output/project-context.md
  - Sources/AxionCore/Models/AxionConfig.swift
  - Sources/AxionCore/Constants/ConfigKeys.swift
  - Sources/AxionCore/Errors/AxionError.swift
  - Sources/AxionCLI/Commands/RunCommand.swift
  - Tests/AxionCLITests/Commands/AxionCommandTests.swift
---

# ATDD Checklist: Story 2.2 — 配置系统与 Keychain 安全存储

## TDD Red Phase (Current)

所有测试使用 `throw XCTSkip("RED: 等待实现")` 标记为跳过状态。

- Unit Tests: **20 tests** (all skipped via XCTSkip)
  - KeychainStoreTests: 10 tests
  - ConfigManagerTests: 10 tests

## Acceptance Criteria Coverage

| AC | Description | Tests | Priority |
|----|-------------|-------|----------|
| AC1 | API Key 写入 Keychain | `test_keychainSave_andLoad_roundTrip`, `test_keychainSave_updateOverwrites`, `test_keychainSave_emptyKey_throwsError` | P0/P1 |
| AC2 | API Key 从 Keychain 读取 | `test_keychainLoad_notFound_returnsNil`, `test_keychainStore_hasCorrectConstants` | P0 |
| AC3 | 配置文件覆盖默认值 | `test_loadConfig_fileOverridesDefault`, `test_loadConfig_noFileNoEnv_returnsDefault` | P0 |
| AC4 | 环境变量覆盖配置文件 | `test_loadConfig_envOverridesFile`, `test_loadConfig_envMaxStepsOverridesFile`, `test_loadConfig_envBoolTraceEnabled` | P0 |
| AC5 | CLI 参数优先级最高 | `test_loadConfig_cliOverridesEnv`, `test_loadConfig_cliOverridesAllLayers`, `test_loadConfig_fullLayerStack` | P0 |
| AC6 | API Key 不泄露 | `test_keychainMask_hidesMiddlePortion`, `test_keychainMask_shortKey_returnsStars`, `test_saveConfigFile_excludesApiKey`, `test_saveConfigFile_roundTripWithoutApiKey`, `test_loadConfig_apiKeyFromEnv` | P0/P1 |

## Test Strategy

### Detected Stack: Backend (Swift/XCTest)

- **Unit Tests** for pure functions, business logic, and edge cases
- **Integration Tests** deferred (Keychain tests use real Security.framework but with isolated service/account)
- **No E2E tests** (CLI commands remain placeholder per story scope)

### Test Levels

| Level | Count | Scope |
|-------|-------|-------|
| P0 — Critical Path | 14 | Type existence, round-trip, layer precedence, API Key isolation |
| P1 — Edge Cases | 6 | Empty key, invalid JSON, delete nonexistent, short key mask |

### Key Test Patterns Used

1. **XCTSkip red-phase scaffolding** — Each test starts with `throw XCTSkip("RED: ...")`
2. **Temporary directory isolation** — ConfigManager tests use `NSTemporaryDirectory() + UUID`
3. **Dedicated Keychain service** — Tests use `"com.axion.test.keychain-store"` to avoid polluting production
4. **Environment variable cleanup** — tearDown cleans all `AXION_*` env vars
5. **Test naming**: `test_{unit}_{scenario}_{expectedResult}` following project conventions

## Next Steps (Task-by-Task Activation)

During implementation of each task:

1. Open the target test file
2. Remove the `throw XCTSkip("RED: ...")` line from tests for the current task
3. Run tests: `swift test --filter "AxionCLITests.Config"`
4. Verify the activated test **fails first** (red), then implement the feature until it passes (green)
5. Commit passing tests

### Activation Order (Recommended)

**Phase 1 — KeychainStore (Task 1):**
- Activate: `test_keychainStore_typeExists` -> `test_keychainStore_hasCorrectConstants` -> `test_keychainSave_andLoad_roundTrip` -> `test_keychainSave_updateOverwrites` -> `test_keychainLoad_notFound_returnsNil` -> `test_keychainDelete_removesKey` -> `test_keychainSave_emptyKey_throwsError` -> `test_keychainDelete_nonexistent_doesNotThrow` -> `test_keychainMask_hidesMiddlePortion` -> `test_keychainMask_shortKey_returnsStars`

**Phase 2 — ConfigManager (Task 2):**
- Activate: `test_configManager_typeExists` -> `test_cliOverrides_typeExists` -> `test_loadConfig_noFileNoEnv_returnsDefault` -> `test_loadConfig_fileOverridesDefault` -> `test_loadConfig_envOverridesFile` -> `test_loadConfig_cliOverridesEnv` -> `test_loadConfig_apiKeyFromEnv` -> `test_saveConfigFile_excludesApiKey` -> `test_saveConfigFile_roundTripWithoutApiKey` -> `test_ensureConfigDirectory_createsDirectory` -> `test_loadConfig_fullLayerStack`

## Implementation Guidance

### Types to Implement

1. **KeychainStore** (enum, static service) — `Sources/AxionCLI/Config/KeychainStore.swift`
   - `static let service: String` = "com.axion.cli"
   - `static let account: String` = "AXION_API_KEY"
   - `static func save(_ key: String, service: String, account: String) throws`
   - `static func load(service: String, account: String) throws -> String?`
   - `static func delete(service: String, account: String) throws`
   - `static func mask(_ key: String) -> String`

2. **ConfigManager** (struct, static methods) — `Sources/AxionCLI/Config/ConfigManager.swift`
   - `static func loadConfig(configDirectory: String?, cliOverrides: CLIOverrides?) async throws -> AxionConfig`
   - `static func saveConfigFile(_ config: AxionConfig, toDirectory: String) throws`
   - `static func ensureConfigDirectory(atPath: String) throws`

3. **CLIOverrides** (struct) — `Sources/AxionCLI/Config/ConfigManager.swift`
   - `var maxSteps: Int?`
   - `var maxBatches: Int?`
   - `var allowForeground: Bool?`
   - `var verbose: Bool?`

### Key Constraints

- KeychainStore uses Security.framework (`SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete`)
- ConfigManager loads in order: defaults -> config.json -> env vars -> CLI params
- API Key never written to config.json (AxionConfig.CodingKeys excludes apiKey)
- All errors use `AxionError.configError(reason:)`
- File permissions: 0o600 for config.json

## Key Risks and Assumptions

1. **Keychain CI access** — CI environments may lack Keychain access; KeychainStore tests may need conditional skip in CI
2. **Environment variable isolation** — Tests use `setenv`/`unsetenv` which is process-global; running tests in parallel could cause interference
3. **Method signature flexibility** — The test-defined `service:`/`account:` parameters on KeychainStore methods are for testability; production code may use default parameter values instead
4. **ConfigManager injectable directory** — Tests assume `loadConfig(configDirectory:cliOverrides:)` accepts an override directory for test isolation instead of hardcoding `~/.axion/`
