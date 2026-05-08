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
storyId: '2.1'
storyKey: 2-1-cli-entry-argumentparser-skeleton
storyFile: _bmad-output/implementation-artifacts/2-1-cli-entry-argumentparser-skeleton.md
atddChecklistPath: _bmad-output/test-artifacts/atdd-checklist-2-1-cli-entry-argumentparser-skeleton.md
generatedTestFiles:
  - Tests/AxionCLITests/Commands/AxionCommandTests.swift
inputDocuments:
  - _bmad-output/implementation-artifacts/2-1-cli-entry-argumentparser-skeleton.md
  - _bmad/tea/config.yaml
  - _bmad-output/project-context.md
  - .claude/skills/bmad-testarch-atdd/resources/tea-index.csv
---

# ATDD Checklist: Story 2.1 - CLI 入口与 ArgumentParser 骨架

## TDD Red Phase (Current)

Red-phase test scaffolds generated. All tests are in compile-fail RED phase -- the implementation types (`RunCommand`, `SetupCommand`, `DoctorCommand`, `AxionVersion`) do not exist yet.

- **Unit Tests**: 21 test methods in AxionCommandTests.swift
- **Total**: 21 test methods (all in RED phase -- compile failure)

## Compile Errors (RED Phase Verification)

| Missing Type | Error Count | Tests Affected |
|-------------|-------------|----------------|
| `RunCommand` | 13 | All RunCommand parameter parsing tests |
| `SetupCommand` | 1 | test_setupCommandExists |
| `DoctorCommand` | 1 | test_doctorCommandExists |
| `AxionVersion` | 2 | test_axionVersion_currentIsNotEmpty, test_axionVersion_matchesVersionFile |

No API misuse errors. All failures are expected "cannot find in scope" for types yet to be implemented.

## Acceptance Criteria Coverage

| AC | Description | Priority | Test File | Test Count | Status |
|----|-------------|----------|-----------|------------|--------|
| AC1 | `axion --help` 显示根命令帮助 | P0 | AxionCommandTests.swift | 3 | RED |
| AC2 | `axion --version` 显示版本号 | P0 | AxionCommandTests.swift | 1 | RED |
| AC3 | 未知子命令显示错误提示 | P0 | AxionCommandTests.swift | 1 | RED |

**All 3 acceptance criteria have corresponding test coverage.**

Additional test coverage beyond AC (P1):

| Category | Description | Test Count | Status |
|----------|-------------|------------|--------|
| RunCommand 参数解析 | task, --live, --max-steps, --max-batches, --allow-foreground, --verbose, --json | 13 | RED |
| SetupCommand 骨架 | 存在性验证 | 1 | RED |
| DoctorCommand 骨架 | 存在性验证 | 1 | RED |
| AxionVersion | 版本号常量验证 | 2 | RED |

## Priority Distribution

| Priority | Test Count | Percentage |
|----------|------------|------------|
| P0 | 5 | 24% |
| P1 | 16 | 76% |

## Test Level Strategy

This is a **backend (Swift/SPM)** project. Test level selection:

- **Unit Tests** (primary): ArgumentParser command parsing, parameter extraction, version constant validation
  - Used for: AC1 (help output), AC2 (version output), AC3 (unknown subcommand error), RunCommand args
  - Justification: ArgumentParser provides `parse()` and `helpMessage(for:)` API for direct in-process testing without CLI execution
  - File: AxionCommandTests.swift

## Test Files Created

| File | Tests | ACs Covered | Lines |
|------|-------|-------------|-------|
| `Tests/AxionCLITests/Commands/AxionCommandTests.swift` | 21 | AC1, AC2, AC3 + extras | ~187 |

## Test-Method to Acceptance Criteria Mapping

### AC1: `axion --help` 显示根命令帮助 (P0)

| # | Test Method | Approach | Validates |
|---|-------------|----------|-----------|
| 1 | `test_axionHelp_showsRunSubcommand()` | `AxionCLI.helpMessage(for:)` | 帮助文本包含 "run" |
| 2 | `test_axionHelp_showsSetupSubcommand()` | `AxionCLI.helpMessage(for:)` | 帮助文本包含 "setup" |
| 3 | `test_axionHelp_showsDoctorSubcommand()` | `AxionCLI.helpMessage(for:)` | 帮助文本包含 "doctor" |

### AC2: `axion --version` 显示版本号 (P0)

| # | Test Method | Approach | Validates |
|---|-------------|----------|-----------|
| 4 | `test_axionVersion_configurationHasVersion()` | `AxionCLI.configuration.version` | 版本包含 "0.1.0" |

### AC3: 未知子命令显示错误提示 (P0)

| # | Test Method | Approach | Validates |
|---|-------------|----------|-----------|
| 5 | `test_unknownSubcommand_throwsParseError()` | `AxionCLI.parse(["unknown"])` | 非 CleanExit 错误 |

### RunCommand 参数解析 (P1)

| # | Test Method | Validates |
|---|-------------|-----------|
| 6 | `test_runCommandParsesTaskArgument()` | task 位置参数解析 |
| 7 | `test_runCommandParsesLiveFlag()` | --live flag 解析为 true |
| 8 | `test_runCommandLiveDefaultIsFalse()` | live 默认 false |
| 9 | `test_runCommandParsesMaxSteps()` | --max-steps 5 解析为 5 |
| 10 | `test_runCommandMaxStepsDefaultIsNil()` | maxSteps 默认 nil |
| 11 | `test_runCommandParsesMaxBatches()` | --max-batches 3 解析为 3 |
| 12 | `test_runCommandMaxBatchesDefaultIsNil()` | maxBatches 默认 nil |
| 13 | `test_runCommandParsesAllowForeground()` | --allow-foreground 解析为 true |
| 14 | `test_runCommandParsesVerbose()` | --verbose 解析为 true |
| 15 | `test_runCommandParsesJson()` | --json 解析为 true |
| 16 | `test_runCommandRequiresTaskArgument()` | 缺少 task 参数抛错 |
| 17 | `test_runCommandParsesAllArgumentsCombined()` | 所有参数组合正确解析 |

### 其他骨架验证 (P1)

| # | Test Method | Validates |
|---|-------------|-----------|
| 18 | `test_setupCommandExists()` | SetupCommand 可解析 |
| 19 | `test_doctorCommandExists()` | DoctorCommand 可解析 |
| 20 | `test_axionVersion_currentIsNotEmpty()` | AxionVersion.current 非空 |
| 21 | `test_axionVersion_matchesVersionFile()` | AxionVersion.current == "0.1.0" |

## Implementation Guidance

### Feature Components to Implement

1. **AxionCLI root command** (main.swift):
   - Update `AxionCLI` struct with `CommandConfiguration` including `subcommands`, `version`
   - Register: RunCommand, SetupCommand, DoctorCommand

2. **RunCommand** (`Sources/AxionCLI/Commands/RunCommand.swift`):
   - `@Argument var task: String`
   - `@Flag var live: Bool = false`
   - `@Option var maxSteps: Int?`
   - `@Option var maxBatches: Int?`
   - `@Flag var allowForeground: Bool = false`
   - `@Flag var verbose: Bool = false`
   - `@Flag var json: Bool = false`
   - `run()` throws -> `CleanExit.message("Run command not yet implemented (Epic 3)")`

3. **SetupCommand** (`Sources/AxionCLI/Commands/SetupCommand.swift`):
   - `run()` throws -> `CleanExit.message("Setup command not yet implemented")`

4. **DoctorCommand** (`Sources/AxionCLI/Commands/DoctorCommand.swift`):
   - `run()` throws -> `CleanExit.message("Doctor command not yet implemented")`

5. **AxionVersion** (`Sources/AxionCLI/Constants/Version.swift`):
   - `enum AxionVersion { static let current = "0.1.0" }`

### Red-Green-Refactor Workflow

1. **RED** (current): All 21 tests fail to compile because RunCommand, SetupCommand, DoctorCommand, and AxionVersion types don't exist
2. **GREEN**: Implement the 5 components above, then run tests to verify they pass
3. **REFACTOR**: Clean up code while keeping tests green

### Execution Commands

```bash
# Run all AxionCLI tests
swift test --filter "AxionCLITests"

# Run specific test file
swift test --filter "AxionCommandTests"

# Run all unit tests (excluding integration)
swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionCoreTests" --filter "AxionCLITests"
```

## Next Steps (Task-by-Task Activation)

During implementation of each task:

1. Implement the source files listed in "Feature Components to Implement"
2. Run tests: `swift test --filter "AxionCommandTests"`
3. Verify tests pass after each component is implemented
4. Commit passing tests

## Key Risks and Assumptions

1. **ArgumentParser `helpMessage(for:)` API**: Tests use the public `AxionCLI.helpMessage(for: AxionCLI.self)` API to verify help output content -- this API is stable in swift-argument-parser 1.5+
2. **ArgumentParser `configuration.version`**: The `--version` test verifies `AxionCLI.configuration.version` contains "0.1.0" -- the version string is set via `CommandConfiguration(version:)`
3. **RunCommand property names**: Tests access `cmd.task`, `cmd.live`, `cmd.maxSteps`, `cmd.maxBatches`, `cmd.allowForeground`, `cmd.verbose`, `cmd.json` -- the implementation must use these exact property names
4. **Compile-fail RED phase**: Unlike previous stories that used `XCTSkip()`, these tests are designed to compile-fail until implementation exists -- this is the strongest form of TDD red phase

## Knowledge Base References Applied

- `component-tdd.md` -- Red-Green-Refactor cycle adapted for Swift/XCTest
- `test-quality.md` -- Test naming convention: `test_方法名_场景_预期结果`
- `test-levels-framework.md` -- Unit test level for ArgumentParser command parsing
