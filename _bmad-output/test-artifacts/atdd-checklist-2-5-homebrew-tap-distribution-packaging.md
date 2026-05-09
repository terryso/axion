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
storyId: '2.5'
storyKey: '2-5-homebrew-tap-distribution-packaging'
storyFile: '_bmad-output/implementation-artifacts/2-5-homebrew-tap-distribution-packaging.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-2-5-homebrew-tap-distribution-packaging.md'
generatedTestFiles:
  - Tests/AxionCLITests/Helper/HelperPathResolverTests.swift
inputDocuments:
  - _bmad-output/implementation-artifacts/2-5-homebrew-tap-distribution-packaging.md
  - _bmad-output/project-context.md
  - Distribution/homebrew/build-helper-app.sh
  - Distribution/homebrew/build-release.sh
  - Distribution/homebrew/axion.rb.template
  - Distribution/homebrew/Info.plist
  - Distribution/homebrew/AxionHelper.entitlements
  - Tests/AxionCLITests/Config/ConfigManagerTests.swift
  - Tests/AxionCLITests/Commands/DoctorCommandTests.swift
---

# ATDD Checklist: Story 2.5 -- Homebrew 私有 Tap 分发与打包

## TDD Red Phase (Current)

所有测试使用 `try XCTSkipIf(true, "RED: ...")` 标记为跳过状态（TDD red phase）。

- Unit Tests: **16 tests** (all skipped via XCTSkip)
  - HelperPathResolverTests: 16 tests

## Acceptance Criteria Coverage

| AC | Description | Tests | Priority |
|----|-------------|-------|----------|
| AC1 | Homebrew formula 推送与安装 | (Shell 脚本验证，不生成单元测试) | P0 |
| AC2 | 安装后版本验证 | (Shell 脚本验证，不生成单元测试) | P0 |
| AC3 | Helper 路径发现 | `test_resolve_noHelperFound_returnsNil`, `test_resolve_relativePath_buildsHomebrewStylePath` | P0 |
| AC4 | Code Signing | (Shell 脚本验证，不生成单元测试) | P1 |
| AC5 | build-release.sh 完整流程 | (Shell 脚本验证，不生成单元测试) | P0 |
| AC6 | HelperApp 路径解析（关键） | `test_helperPathResolver_typeExists`, `test_helperPathResolver_resolveMethodExists`, `test_resolve_envVariable_returnsEnvPath`, `test_resolve_envVariable_returnsEvenIfNotExists`, `test_resolve_relativePath_buildsHomebrewStylePath`, `test_resolve_homebrewPath_containsLibexecAxion`, `test_resolve_developmentMode_detectsBuildDirectory`, `test_resolve_developmentMode_buildPathFormat`, `test_resolve_noHelperFound_returnsNil`, `test_resolve_envVariableTakesPriorityOverRelativePath`, `test_resolve_emptyEnvVariable_fallsThrough`, `test_resolve_resultPath_pointsToExecutable`, `test_resolve_resultPath_isAbsolute`, `test_resolve_supportsOptHomebrewPath`, `test_resolve_supportsUsrLocalPath`, `test_resolver_noHardcodedPaths` | P0 |
| AC7 | GitHub Release 自动化 | (Shell 脚本验证，不生成单元测试) | P1 |

## Test Strategy Notes

### 测试层级选择

Story 2.5 的可测试代码分两类：

1. **Swift 代码（HelperPathResolver）** -- 单元测试（本文件生成）
   - 纯逻辑：路径解析策略（环境变量 > 相对路径 > 开发模式回退）
   - 无系统依赖：不启动 Helper 进程，不调用 AX API
   - 通过环境变量和 `Bundle.main.executableURL` 隔离测试

2. **Shell 脚本（build-helper-app.sh, build-release.sh, axion.rb.template）** -- 集成测试（Task 5 手动验证）
   - 需要真实构建环境（swift build, codesign, tar）
   - 需要文件系统操作（创建 .app Bundle, tar.gz 打包）
   - 不适合 XCTestCase 自动化 -- 建议通过 Task 5 的集成测试验证

### 未生成单元测试的 AC

以下 AC 涉及 Shell 脚本和 GitHub Actions，不适合 Swift 单元测试：

- **AC1** (Homebrew formula 安装): build-release.sh + axion.rb.template 验证
- **AC2** (版本验证): `axion --version` 输出验证
- **AC4** (Code Signing): `codesign --verify` 验证
- **AC5** (build-release.sh 流程): 完整构建流程测试
- **AC7** (GitHub Release): publish-release.sh 验证

## Acceptance Tests (Red Phase)

### File: Tests/AxionCLITests/Helper/HelperPathResolverTests.swift

#### P0 -- 基础设施验证 (2 tests)

| # | Test Method | AC | Validates |
|---|-------------|----|-----------|
| 1 | `test_helperPathResolver_typeExists` | AC6 | HelperPathResolver struct 存在 |
| 2 | `test_helperPathResolver_resolveMethodExists` | AC6 | `resolveHelperPath() -> String?` 方法签名 |

#### P0 -- 环境变量覆盖策略 (2 tests)

| # | Test Method | AC | Validates |
|---|-------------|----|-----------|
| 3 | `test_resolve_envVariable_returnsEnvPath` | AC6 | AXION_HELPER_PATH 环境变量直接返回 |
| 4 | `test_resolve_envVariable_returnsEvenIfNotExists` | AC6 | 环境变量路径无需验证文件存在 |

#### P0 -- 相对路径解析策略 (2 tests)

| # | Test Method | AC | Validates |
|---|-------------|----|-----------|
| 5 | `test_resolve_relativePath_buildsHomebrewStylePath` | AC3, AC6 | 构建 ../libexec/axion/AxionHelper.app 路径 |
| 6 | `test_resolve_homebrewPath_containsLibexecAxion` | AC3 | 路径包含 libexec/axion 组件 |

#### P0 -- 开发模式回退策略 (2 tests)

| # | Test Method | AC | Validates |
|---|-------------|----|-----------|
| 7 | `test_resolve_developmentMode_detectsBuildDirectory` | AC6 | 检测 .build 目录使用开发模式 |
| 8 | `test_resolve_developmentMode_buildPathFormat` | AC6 | 开发模式路径包含 AxionHelper.app |

#### P0 -- 容错 (1 test)

| # | Test Method | AC | Validates |
|---|-------------|----|-----------|
| 9 | `test_resolve_noHelperFound_returnsNil` | AC3 | 路径未找到返回 nil（不抛异常） |

#### P1 -- 优先级验证 (2 tests)

| # | Test Method | AC | Validates |
|---|-------------|----|-----------|
| 10 | `test_resolve_envVariableTakesPriorityOverRelativePath` | AC6 | 环境变量优先级最高 |
| 11 | `test_resolve_emptyEnvVariable_fallsThrough` | AC6 | 空环境变量不视为有效覆盖 |

#### P1 -- 路径格式验证 (2 tests)

| # | Test Method | AC | Validates |
|---|-------------|----|-----------|
| 12 | `test_resolve_resultPath_pointsToExecutable` | AC6 | 路径指向可执行文件而非 .app 目录 |
| 13 | `test_resolve_resultPath_isAbsolute` | AC6 | 返回绝对路径 |

#### P1 -- 跨架构兼容性 (2 tests)

| # | Test Method | AC | Validates |
|---|-------------|----|-----------|
| 14 | `test_resolve_supportsOptHomebrewPath` | AC3 | 支持 /opt/homebrew（Apple Silicon） |
| 15 | `test_resolve_supportsUsrLocalPath` | AC3 | 支持 /usr/local（Intel Mac） |

#### P1 -- 设计约束 (1 test)

| # | Test Method | AC | Validates |
|---|-------------|----|-----------|
| 16 | `test_resolver_noHardcodedPaths` | AC6 | 不包含硬编码绝对路径 |

## Next Steps (Task-by-Task Activation)

During implementation of each task:

1. Remove `try XCTSkipIf(true, ...)` from the test methods for the current task
2. Run tests: `swift test --filter "AxionCLITests.Helper"`
3. Verify the activated test **fails first** (red), then passes after implementation (green)
4. If any activated tests still fail unexpectedly:
   - Either fix implementation (feature bug)
   - Or fix test (test bug)
5. Commit passing tests

### Recommended Activation Order

1. **Task 1 (HelperPathResolver)**: Activate all 16 tests
   - Implement `Sources/AxionCLI/Helper/HelperPathResolver.swift`
   - Remove all XCTSkip calls
   - Run tests, verify they pass
2. **Task 2-4 (Build scripts, Formula, Release)**: Manual integration testing (Task 5)
3. **Task 5 (Integration testing)**: Run `swift test --filter "AxionCLITests"` for regression

## Implementation Guidance

### Source Files to Implement

- `Sources/AxionCLI/Helper/HelperPathResolver.swift` -- Helper App 路径解析器

### Key Design Constraints

- `HelperPathResolver` 必须是 `struct`（值类型，无状态）
- `resolveHelperPath()` 返回 `String?`（不抛异常）
- 三策略优先级：环境变量 > 相对路径 > 开发模式回退
- 空字符串环境变量不视为有效覆盖
- 返回路径必须是绝对路径，指向可执行文件而非 .app 目录
- 不得硬编码 `/usr/local` 或 `/opt/homebrew`

## Summary Statistics

| Metric | Value |
|--------|-------|
| TDD Phase | RED |
| Total Tests | 16 |
| Unit Tests | 16 |
| Integration Tests | 0 (manual shell script verification) |
| All Tests Skipped | Yes (XCTSkip) |
| Expected to Fail | Yes (after activation) |
| Fixtures Created | 0 |
| AC Coverage | AC3, AC6 (code-testable); AC1,2,4,5,7 (manual verification) |
