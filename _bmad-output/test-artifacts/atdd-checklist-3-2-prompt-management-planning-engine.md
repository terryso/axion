---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04c-aggregate
  - step-05-validate-and-complete
lastStep: step-05-validate-and-complete
lastSaved: '2026-05-10'
storyId: '3.2'
storyKey: '3-2-prompt-management-planning-engine'
storyFile: '_bmad-output/implementation-artifacts/3-2-prompt-management-planning-engine.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-3-2-prompt-management-planning-engine.md'
generatedTestFiles:
  - 'Tests/AxionCLITests/Planner/PromptBuilderTests.swift'
  - 'Tests/AxionCLITests/Planner/PlanParserTests.swift'
  - 'Tests/AxionCLITests/Planner/LLMPlannerTests.swift'
---

# ATDD Checklist: Story 3.2 -- Prompt 管理与规划引擎

## TDD Red Phase（当前阶段）

**所有测试已使用 XCTSkipIf(true) 标记为红色阶段脚手架。**

- PromptBuilderTests: 11 个测试
- PlanParserTests: 20 个测试
- LLMPlannerTests: 16 个测试
- **总计: 47 个红色阶段测试**

## Acceptance Criteria 覆盖

| AC | 描述 | 测试覆盖 | 优先级 |
|----|------|---------|--------|
| AC1 | Prompt 文件加载与模板变量注入 | test_load_existingFile_returnsContent, test_load_missingFile_throwsError, test_load_noVariables_returnsRawContent, test_load_multipleOccurrences_replacesAll, test_templateVariable_injectedCorrectly, test_buildToolListDescription_formatsToolNames, test_buildToolListDescription_emptyList_returnsEmpty, test_buildPlannerPrompt_includesTask, test_buildPlannerPrompt_withReplanContext_includesFailureInfo, test_resolvePromptDirectory_returnsValidPath, test_load_unresolvedVariables_remainAsPlaceholders | P0 |
| AC2 | LLM 规划生成结构化 Plan | test_createPlan_callsLLMWithCorrectPrompt, test_createPlan_returnsPlanWithSteps, test_createPlan_systemPromptContainsToolList | P0 |
| AC3 | Plan 步骤结构完整性 | test_parsePlan_stepStructure_hasAllRequiredFields, test_validatePlan_validPlan_returnsPlan, test_parsePlan_argsField_mapsToParameters, test_parsePlan_expectedChangeField_snakeCaseMapped | P0 |
| AC4 | Markdown 围栏解析 | test_stripFences_jsonInBackticks_extractsJSON, test_stripFences_jsonInPlainBackticks_extractsJSON | P0 |
| AC5 | 前导文本解析 | test_stripFences_proseBeforeJSON_extractsJSON, test_stripFences_jsonWithTrailingText_extractsJSON | P0 |
| AC6 | LLM API 重试（NFR6） | test_createPlan_retriesOnNetworkError_upToMaxRetries, test_createPlan_succeedsOnRetry_afterInitialFailure, test_createPlan_doesNotRetryOnParseError | P0 |
| AC7 | Plan 解析失败不静默丢弃（NFR7） | test_parsePlan_failurePreservesRawResponse_NFR7, test_parsePlan_invalidJSON_throwsInvalidPlan | P0 |

## Test Strategy

### Stack: Backend (Swift/XCTest)

本 Story 为纯后端 Swift 项目，使用 XCTest 框架。无浏览器/E2E 测试。

### Test Levels

- **Unit Tests** (47 tests): PromptBuilder 模板加载、PlanParser JSON 提取/解析/验证、LLMPlanner 规划/重规划/重试
- **Integration Tests** (not included here): 真实 LLM API 调用测试，属于 `Tests/**/Integration/` 目录

### Mock Strategy

| 组件 | Mock 方式 | 说明 |
|------|----------|------|
| LLMClient | MockLLMClient（手动 mock） | 模拟 LLM 响应、错误、重试行为 |
| MCPClient | MockPlannerMCPClient（手动 mock） | 模拟 screenshot/AX tree/工具列表 |
| Prompt 文件系统 | 临时目录 + FileManager | XCTSkip 跳过的测试不需要真实文件 |

### Priority Matrix

| Priority | Tests | Description |
|----------|-------|-------------|
| P0 | 34 tests | 类型存在性、核心路径（加载/解析/规划）、围栏剥离、前导文本、错误处理、重试 |
| P1 | 13 tests | stopWhen 映射、参数映射、截图降级、replan 上下文、Prompt 目录查找 |

## 生成的测试文件

### 1. Tests/AxionCLITests/Planner/PromptBuilderTests.swift

- 11 个测试方法
- 覆盖 AC1
- 按 MARK 分组：类型存在性、Prompt 文件加载、模板变量注入、工具列表格式化、Planner Prompt 组装、Prompt 目录查找、未使用变量保留

### 2. Tests/AxionCLITests/Planner/PlanParserTests.swift

- 20 个测试方法
- 覆盖 AC3, AC4, AC5, AC7
- 按 MARK 分组：类型存在性、Markdown 围栏解析、前导文本解析、嵌套花括号、纯 JSON、完整 Plan 解析、步骤结构、解析失败处理（NFR7）、步骤数超限、stopWhen 映射、参数映射、validatePlan、status 字段处理

### 3. Tests/AxionCLITests/Planner/LLMPlannerTests.swift

- 16 个测试方法（含 MockLLMClient 和 MockPlannerMCPClient）
- 覆盖 AC2, AC6
- 按 MARK 分组：类型存在性、createPlan 核心流程、createPlan 错误处理、重试逻辑、重规划、当前状态获取、ReplanContext 传递、初始化、system prompt 验证

## Red-Green-Refactor 工作流

### RED Phase（当前 -- 由 TEA 完成）

1. 所有 47 个测试已生成为红色阶段脚手架（XCTSkipIf）
2. 测试断言了预期行为（非占位断言）
3. 实现前所有测试被跳过

### GREEN Phase（由 DEV 团队执行）

实现每个 Task 时：

1. 打开对应的测试文件
2. 找到对应当前 Task 的测试方法
3. 移除 `try XCTSkipIf(true, "...")` 行
4. 运行 `swift test --filter "AxionCLITests.Planner"`
5. 确认测试失败（RED）
6. 实现功能代码
7. 确认测试通过（GREEN）
8. 提交通过的测试

### Task -> Test 映射

| Task | 测试文件 | 测试方法 |
|------|---------|---------|
| Task 1: PromptBuilder | PromptBuilderTests.swift | 11 个测试 |
| Task 2: planner-system.md | （集成验证，无独立测试） | -- |
| Task 3: PlanParser | PlanParserTests.swift | 20 个测试 |
| Task 4: LLMPlanner | LLMPlannerTests.swift | 16 个测试 |
| Task 5: ReplanContext | LLMPlannerTests.swift (replan tests) | 2 个测试 |

## 关键测试覆盖

### NFR 覆盖

| NFR | 测试 | 状态 |
|-----|------|------|
| NFR6 (LLM API 重试) | test_createPlan_retriesOnNetworkError_upToMaxRetries, test_createPlan_doesNotRetryOnParseError | RED |
| NFR7 (解析失败不静默丢弃) | test_parsePlan_failurePreservesRawResponse_NFR7 | RED |

### 边界条件覆盖

- 空工具列表
- 空变量注入
- 未匹配变量保留
- 空步骤数组
- 空 stopWhen
- 步骤数超限
- 缺失 tool/purpose 字段
- status: done / needs_clarification
- 截图失败降级
- 网络错误重试
- 解析错误不重试
