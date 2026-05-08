---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04-generate-tests
  - step-04c-aggregate
  - step-05-validate-and-complete
lastStep: 'step-05-validate-and-complete'
lastSaved: '2026-05-08'
storyId: '1.6'
storyKey: '1-6-helper-integration-app-packaging'
storyFile: '_bmad-output/implementation-artifacts/1-6-helper-integration-app-packaging.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-1-6-helper-integration-app-packaging.md'
generatedTestFiles:
  - Tests/AxionHelperTests/Integration/FullToolRegistrationTests.swift
  - Tests/AxionHelperTests/Integration/HelperStartupPerformanceTests.swift
  - Tests/AxionHelperTests/Integration/SingleOperationPerformanceTests.swift
  - Tests/AxionHelperTests/Tools/AppBundleTests.swift
inputDocuments:
  - _bmad-output/implementation-artifacts/1-6-helper-integration-app-packaging.md
  - _bmad-output/project-context.md
  - _bmad-output/planning-artifacts/epics.md
  - _bmad-output/planning-artifacts/architecture.md
---

# ATDD Checklist: Story 1.6 — Helper 完整集成与 App 打包

## Story Summary

**Story 1.6** 是 Epic 1 的收官之作。所有 15 个 MCP 工具已在 Stories 1.1-1.5 中实现。本 Story 的核心目标：

1. 将 SPM 编译产物包装为标准 macOS App Bundle
2. 创建构建发布脚本和 Homebrew formula
3. 通过集成测试验证完整工具注册和性能指标

**技术栈:** Swift (backend), SPM, macOS App Bundle, Homebrew

## TDD Red Phase (Current)

### Test Strategy

- **Unit Tests** — App Bundle 内容验证（Info.plist 字段检查）
- **Integration Tests** — 进程级测试：全部工具注册验证、NFR2 启动性能、NFR3 单操作性能
- **Smoke Tests** — Helper 进程生命周期增强

### Acceptance Criteria Coverage

| AC | Description | Test Level | Priority | Test File |
|----|-------------|------------|----------|-----------|
| AC1 | 全部 15 个工具注册可用 | Integration | P0 | FullToolRegistrationTests.swift |
| AC2 | AxionHelper.app 打包配置正确 | Unit | P0 | AppBundleTests.swift |
| AC3 | Helper MCP 启动就绪 < 500ms (NFR2) | Integration | P0 | HelperStartupPerformanceTests.swift |
| AC4 | 单操作 < 200ms (NFR3) | Integration | P1 | SingleOperationPerformanceTests.swift |
| AC5 | Helper 随 CLI 退出 | Integration | P0 | HelperProcessSmokeTests.swift (enhanced) |

## Test Scaffolds Created

### Integration Tests (red-phase, require AX permissions)

| File | Tests | AC Covered |
|------|-------|------------|
| `Tests/AxionHelperTests/Integration/FullToolRegistrationTests.swift` | 3 tests | AC1 |
| `Tests/AxionHelperTests/Integration/HelperStartupPerformanceTests.swift` | 2 tests | AC3 |
| `Tests/AxionHelperTests/Integration/SingleOperationPerformanceTests.swift` | 2 tests | AC4 |

### Unit Tests (red-phase, no AX permissions needed)

| File | Tests | AC Covered |
|------|-------|------------|
| `Tests/AxionHelperTests/Tools/AppBundleTests.swift` | 5 tests | AC2 |

## Test Details

### FullToolRegistrationTests (Integration)

- [P0] `test_toolsList_all15ToolsRegistered_viaRealMCP` — 通过真实 Helper 进程验证 tools/list 返回全部 15 个工具
- [P0] `test_toolsList_eachToolHasNameDescriptionSchema` — 每个工具包含 name/description/inputSchema
- [P0] `test_toolsList_toolNamesMatchToolNamesConstants` — 工具名与 ToolNames.swift 常量一致

### HelperStartupPerformanceTests (Integration)

- [P0] `test_helperStartup_initializeResponseTime_under500ms` — NFR2: 启动到 MCP 就绪 < 500ms
- [P1] `test_helperStartup_consecutiveRestarts_meetNFR2` — 连续重启均满足 NFR2

### SingleOperationPerformanceTests (Integration)

- [P1] `test_listApps_responseTime_under200ms` — NFR3: list_apps 响应 < 200ms
- [P1] `test_getWindowState_responseTime_under200ms` — NFR3: get_window_state 响应 < 200ms

### AppBundleTests (Unit)

- [P0] `test_infoPlist_containsLSUIElement` — Info.plist 包含 LSUIElement=true
- [P0] `test_infoPlist_containsMinimumSystemVersion` — Info.plist 包含 LSMinimumSystemVersion=13.0
- [P0] `test_infoPlist_containsBundleIdentifier` — Info.plist 包含 CFBundleIdentifier=com.axion.helper
- [P1] `test_appBundleStructure_hasExpectedDirectories` — App Bundle 目录结构正确
- [P1] `test_infoPlist_versionMatchesProjectVersion` — 版本号与 VERSION 文件一致

## Implementation Checklist

### Task-by-Task Activation (Red-Green-Refactor)

1. **App Bundle 构建脚本** (AC2)
   - [ ] 创建 `Distribution/homebrew/build-helper-app.sh`
   - [ ] 创建 `Distribution/homebrew/Info.plist` 模板
   - [ ] 创建 `Distribution/homebrew/AxionHelper.entitlements`
   - [ ] Remove `test.skip` from AppBundleTests, verify RED, then implement
   - Run: `swift test --filter "AxionHelperTests.Tools.AppBundleTests"`

2. **发布脚本** (AC2, AC5)
   - [ ] 创建 `Distribution/homebrew/build-release.sh`
   - [ ] 创建 `Distribution/homebrew/axion.rb.template`
   - [ ] 创建 `VERSION` 文件

3. **集成验证** (AC1, AC3, AC4)
   - [ ] Remove `test.skip` from FullToolRegistrationTests, verify RED
   - [ ] Remove `test.skip` from HelperStartupPerformanceTests, verify RED
   - [ ] Remove `test.skip` from SingleOperationPerformanceTests, verify RED
   - Run: `swift test --filter "AxionHelperIntegrationTests"`

4. **Helper 进程生命周期增强** (AC5)
   - [ ] 添加 HelperProcessSmokeTests 退出验证测试
   - Run: `swift test --filter "AxionHelperTests.MCP.HelperProcessSmokeTests"`

## Execution Commands

```bash
# Unit tests only (no AX permissions needed)
swift test --filter "AxionHelperTests.Tools.AppBundleTests"

# Integration tests (require AX permissions + macOS GUI session)
swift test --filter "AxionHelperIntegrationTests"

# All unit tests (confirm no regression)
swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionCoreTests"
```

## Next Steps

1. Implement Task 1 (App Bundle build script + Info.plist)
2. Activate AppBundleTests, confirm RED, then implement to GREEN
3. Implement Task 2 (release scripts + Homebrew formula)
4. Implement Task 3 (integration tests)
5. Run full regression suite
6. Next workflow: `dev-story` for Story 1.6 implementation
