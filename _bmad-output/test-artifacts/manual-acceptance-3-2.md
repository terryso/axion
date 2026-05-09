# Story 3-2: Prompt 管理与规划引擎 — 手工验收文档

日期: 2026-05-10
验收人: Claude Code (automated)

## 验收范围

Story 3-2 实现了 Axion 规划引擎的三大核心组件：
1. **PromptBuilder** — Prompt 文件加载与模板变量注入
2. **PlanParser** — LLM 原始输出 -> 强类型 Plan 解析
3. **LLMPlanner** — 通过 LLM 生成结构化执行计划

## 验收检查项

### AC1: Prompt 文件加载与模板变量注入

| # | 检查项 | 验证方式 | 预期结果 | 状态 |
|---|--------|----------|----------|------|
| 1.1 | `Prompts/planner-system.md` 文件存在 | `ls Prompts/planner-system.md` | 文件存在 | PASS |
| 1.2 | prompt 内容包含 `{{tools}}` 占位符 | `grep '{{tools}}' Prompts/planner-system.md` | 匹配到内容 | PASS |
| 1.3 | prompt 内容包含 `{{max_steps}}` 占位符 | `grep '{{max_steps}}' Prompts/planner-system.md` | 匹配到内容 | PASS |
| 1.4 | prompt 包含工具描述和规划原则 | 检查文件内容 | 包含工具列表、shifted key 映射、输出格式规范 | PASS |
| 1.5 | PromptBuilder 单元测试通过 | `swift test --filter PromptBuilderTests` | 12 tests, 0 failures | PASS |

### AC2: LLM 规划生成结构化 Plan

| # | 检查项 | 验证方式 | 预期结果 | 状态 |
|---|--------|----------|----------|------|
| 2.1 | LLMPlanner 遵循 PlannerProtocol | 检查 `LLMPlanner: PlannerProtocol` | 遵循协议 | PASS |
| 2.2 | createPlan 方法存在且签名正确 | 检查源码 | `func createPlan(for task: String, context: RunContext) async throws -> Plan` | PASS |
| 2.3 | replan 方法存在且签名正确 | 检查源码 | `func replan(from:executedSteps:failureReason:context:) async throws -> Plan` | PASS |
| 2.4 | LLMPlanner 单元测试通过 | `swift test --filter LLMPlannerTests` | 15 tests, 0 failures | PASS |

### AC3: Plan 步骤结构完整性

| # | 检查项 | 验证方式 | 预期结果 | 状态 |
|---|--------|----------|----------|------|
| 3.1 | Step 包含 tool 字段 | 检查 Step 结构体 | `tool: String` | PASS |
| 3.2 | Step 包含 parameters 字段 | 检查 Step 结构体 | `parameters: [String: Value]` | PASS |
| 3.3 | Step 包含 purpose 字段 | 检查 Step 结构体 | `purpose: String` | PASS |
| 3.4 | Step 包含 expectedChange 字段 | 检查 Step 结构体 | `expectedChange: String` | PASS |
| 3.5 | PlanParser 验证所有字段非空 | 检查 PlanParser.validatePlan | 空 tool/purpose 抛出 invalidPlan | PASS |

### AC4: Markdown 围栏解析

| # | 检查项 | 验证方式 | 预期结果 | 状态 |
|---|--------|----------|----------|------|
| 4.1 | stripFences 提取 ```json...``` 内容 | PlanParserTests.test_stripFences_jsonInBackticks | 测试通过 | PASS |
| 4.2 | stripFences 提取 ```...``` 内容 | PlanParserTests.test_stripFences_jsonInPlainBackticks | 测试通过 | PASS |

### AC5: 前导文本解析

| # | 检查项 | 验证方式 | 预期结果 | 状态 |
|---|--------|----------|----------|------|
| 5.1 | 跳过前导自然语言文本 | PlanParserTests.test_stripFences_proseBeforeJSON | 测试通过 | PASS |
| 5.2 | 跳过 JSON 后的尾部文本 | PlanParserTests.test_stripFences_jsonWithTrailingText | 测试通过 | PASS |
| 5.3 | 处理字符串内嵌套花括号 | PlanParserTests.test_stripFences_nestedBracesInStrings | 测试通过 | PASS |

### AC6: LLM API 重试（NFR6）

| # | 检查项 | 验证方式 | 预期结果 | 状态 |
|---|--------|----------|----------|------|
| 6.1 | 网络错误最多重试 3 次 | LLMPlannerTests.test_createPlan_retriesOnNetworkError | 1 + 3 = 4 次调用 | PASS |
| 6.2 | 重试成功后返回结果 | LLMPlannerTests.test_createPlan_succeedsOnRetry | 第 2 次成功 | PASS |
| 6.3 | 解析错误不触发重试 | LLMPlannerTests.test_createPlan_doesNotRetryOnParseError | 仅 1 次调用 | PASS |
| 6.4 | 退避时间 1s -> 2s -> 4s | 检查源码 baseDelays | `[1_000_000_000, 2_000_000_000, 4_000_000_000]` | PASS |

### AC7: Plan 解析失败不静默丢弃（NFR7）

| # | 检查项 | 验证方式 | 预期结果 | 状态 |
|---|--------|----------|----------|------|
| 7.1 | 解析失败抛出 AxionError.invalidPlan | PlanParserTests.test_parsePlan_invalidJSON | 包含原始响应内容 | PASS |
| 7.2 | 错误中保留原始响应 | PlanParserTests.test_parsePlan_failurePreservesRawResponse | 错误 reason 含原始文本 | PASS |

### 构建与测试

| # | 检查项 | 验证方式 | 预期结果 | 状态 |
|---|--------|----------|----------|------|
| B.1 | 项目编译通过 | `swift build` | Build complete | PASS |
| B.2 | 全部单元测试通过 | `swift test` (全部 filter) | 293 tests, 0 failures | PASS |
| B.3 | 无编译警告 | 检查 build 输出 | 0 warnings | PASS |

### 文件结构

| # | 检查项 | 验证方式 | 预期结果 | 状态 |
|---|--------|----------|----------|------|
| F.1 | PromptBuilder.swift 存在 | `ls Sources/AxionCLI/Planner/PromptBuilder.swift` | 文件存在 | PASS |
| F.2 | PlanParser.swift 存在 | `ls Sources/AxionCLI/Planner/PlanParser.swift` | 文件存在 | PASS |
| F.3 | LLMPlanner.swift 存在 | `ls Sources/AxionCLI/Planner/LLMPlanner.swift` | 文件存在 | PASS |
| F.4 | planner-system.md 存在 | `ls Prompts/planner-system.md` | 文件存在 | PASS |
| F.5 | 测试文件存在 | `ls Tests/AxionCLITests/Planner/` | 3 个测试文件 | PASS |

### 代码质量

| # | 检查项 | 验证方式 | 预期结果 | 状态 |
|---|--------|----------|----------|------|
| Q.1 | 模块依赖正确（无循环） | 检查 import 语句 | PlanParser/PromptBuilder 仅 import Foundation + AxionCore | PASS |
| Q.2 | 无硬编码 prompt 文本 | 检查 Planner 文件 | prompt 从外部 .md 文件加载 | PASS |
| Q.3 | 无 print() 输出 | `grep 'print(' Sources/AxionCLI/Planner/*.swift` | 无结果 | PASS |
| Q.4 | AxionCLI 未 import AxionHelper | `grep 'import AxionHelper' Sources/AxionCLI/Planner/*.swift` | 无结果 | PASS |

## 验收结论

- [x] PASS — 全部 33 项检查通过
- [ ] FAIL — 存在未通过项（列出）
