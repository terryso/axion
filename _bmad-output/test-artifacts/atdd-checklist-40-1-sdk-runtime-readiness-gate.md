---
stepsCompleted: ['step-01-preflight-and-context', 'step-04-generate-tests', 'step-05-validate-and-complete']
lastStep: 'step-05-validate-and-complete'
lastSaved: '2026-06-15'
storyId: '40.1'
storyKey: '40-1-sdk-runtime-readiness-gate'
storyFile: '_bmad-output/implementation-artifacts/40-1-sdk-runtime-readiness-gate.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-40-1-sdk-runtime-readiness-gate.md'
generatedTestFiles:
  - 'Tests/AxionCLITests/Services/SDKRuntimeReadinessGateTests.swift'
inputDocuments:
  - '_bmad-output/implementation-artifacts/40-1-sdk-runtime-readiness-gate.md'
  - 'CLAUDE.md'
  - 'Package.swift'
  - 'Package.resolved'
  - '/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/Advanced/AgentTool.swift'
  - '/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/Advanced/SkillTool.swift'
  - '/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/ToolTypes.swift'
framework: 'Swift Testing (import Testing / @Suite / @Test / #expect)'
tddPhase: 'GREEN'
executionMode: 'yolo (非交互 Create)'
---

# ATDD Checklist — Story 40.1 SDK Runtime Readiness Gate

## 1. 测试套件概览

- **测试文件**：`Tests/AxionCLITests/Services/SDKRuntimeReadinessGateTests.swift`
- **框架**：Swift Testing（`@Suite("SDK Runtime Readiness Gate (Story 40.1)")`）
- **testTarget**：`AxionCLITests`（被默认单元测试命令 `--filter "AxionCLITests"` 命中）
- **TDD 阶段**：GREEN（dev 升 SDK 后已转绿）
- **依赖**：`AxionCLITests` 已直接依赖 `OpenAgentSDK` product，`import OpenAgentSDK` 合法

## 2. AC 覆盖映射

| AC | 描述 | 覆盖方式 | @Test | 当前 red/green |
|----|------|----------|-------|----------------|
| AC1 | Package.swift/resolved 升到 0.10.0 (revision 4285aac) | **构建/文档级验证**（非单测） | — | dev 执行 `swift package update` 后由 Package.resolved 体现 |
| AC2 | createAgentTool/createTaskTool/createSkillTool 可 import 且实例化 | 单测（编译级 gate） | `test_createAgentTool_resolvesAndReturnsAgentName`、`test_createTaskTool_resolvesAndReturnsTaskName`、`test_createSkillTool_resolvesWithRegistry` | GREEN |
| AC3 | Task/Agent name 与 schema 兼容（仅 name 不同） | 单测（schema 反射） | `test_createAgentTool_*`、`test_createTaskTool_*`、`test_taskAndAgent_shareEquivalentSchema` | GREEN |
| AC4 | schema 含 skills 与 mcpServers/mcp_servers 字段 | 单测（schema 反射 properties 键集合） | `test_taskAndAgent_schemaIncludesSkillsAndMcpServers` | GREEN |
| AC5 | executeSkillStream 注入 Skill package context | **降级处理**（SDK 行为验证） | `test_filesystemSkill_promptIncludesPackageContext`（`.disabled`） | DISABLED（需真实 Agent 运行时/API key） |
| AC6 | gate 失败不得关闭 Epic | **文档级验证**（流程守护） | — | dev 在 Completion Notes 记录 blocked/deferred 策略 |

## 3. @Test 清单（共 6 个）

1. `test_createAgentTool_resolvesAndReturnsAgentName` — AC2/AC3
2. `test_createTaskTool_resolvesAndReturnsTaskName` — AC2/AC3
3. `test_createSkillTool_resolvesWithRegistry` — AC2（兼回归：升级未破坏既有签名）
4. `test_taskAndAgent_shareEquivalentSchema` — AC3（完整 `inputSchema` 规范化 JSON 等价）
5. `test_taskAndAgent_schemaIncludesSkillsAndMcpServers` — AC4
6. `test_filesystemSkill_promptIncludesPackageContext` — AC5（`.disabled`，降级）

## 4. Red-to-Green Gate 行为

**历史 RED 状态（SDK 0.8.3，未升 SDK）**：`Tests/AxionCLITests/Services/SDKRuntimeReadinessGateTests.swift` **编译失败**。

实测编译错误（`swift build --target AxionCLITests`）：

```
error: cannot find 'createTaskTool' in scope   (第 73 / 109 / 136 行)
```

- `createTaskTool()` 在 SDK 0.8.3 未公开（SDK 0.10.0 commit `4285aac` 才导出，见
  `open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/Advanced/AgentTool.swift:312`）。
- 该符号缺失阻断 AC2/AC3/AC4 全部断言式测试 → 这是预期的确定性 gate。
- AC5 测试以 `.disabled(...)` 标记，不计入编译/运行失败。

**当前 GREEN 条件**（Task 1 升 SDK 后已满足）：

1. `Package.swift:18` `from: "0.8.0"` → `from: "0.10.0"`。
2. `swift package update` → `Package.resolved` resolve 到
   `version: "0.10.0"`, revision `4285aac6535236dae014e945eed694ed7fe6bd4b`。
3. `swift build --target AxionCLITests` 编译通过（createTaskTool 符号出现）。
4. `swift test --filter "AxionCLITests"` 运行通过：
   - `test_createAgentTool_*` → name == "Agent"
   - `test_createTaskTool_*` → name == "Task"
   - `test_createSkillTool_*` → name == "Skill"
   - `test_taskAndAgent_shareEquivalentSchema` → 两工具完整 inputSchema 规范化 JSON 相等
   - `test_taskAndAgent_schemaIncludesSkillsAndMcpServers` → 含 skills / mcpServers
   - `test_filesystemSkill_promptIncludesPackageContext` → 仍 disabled（降级）

## 5. 关键决策与降级处理

### 5.1 AC1 / AC6 标注为「构建/文档级验证」
AC1（版本约束 + Package.resolved pin）由 `swift package update` 产生的
`Package.resolved` 体现，非运行时单测对象；AC6（Epic gate 守护）是流程/文档约定。
两者在 checklist 标注为构建/文档级验证，不产出 @Test。

### 5.2 AC4 用 schema 反射而非 JSON decode
SDK `AgentToolInput` 是 `private struct`（`AgentTool.swift:35`），无法从 Axion 侧
直接 decode。但 `ToolProtocol.inputSchema: ToolInputSchema`（`ToolTypes.swift:127-130`）
公开可读，且 `ToolInputSchema = [String: Any]`（`ToolTypes.swift:4`），其
`properties` 子字典键集合即工具接受的输入字段名。故 AC4 用
`tool.inputSchema["properties"]` 的键集合断言 `skills` / `mcpServers` 存在，
符合 story Task 2.2.5「优先 schema 反射」路径。

### 5.3 AC3 schema 等价性用完整 schema 比对
SDK 的 Task/Agent 共享同一 `subAgentLauncherSchema` 字面量（`AgentTool.swift:170`），
仅工具 name 字符串不同。单测比对两工具完整 `inputSchema` 的规范化 JSON 相等 +
name 不同，覆盖 story Task 2.2.4 的 schema 反射路径（优于降级路径）。

### 5.4 AC5 降级为 `.disabled`
SDK `resolveSkillForExecution` / package-context 注入（`Core/Agent.swift:3293-3319`，
commit `4285aac`）需真实 `Agent` 运行时触发，内部可能校验 API key。单元测试规则
（CLAUDE.md）禁止真实外部依赖/网络副作用。故按 story Dev Notes 降级策略：
- 测试以 `.disabled(...)` 标记，附详细降级说明。
- 该行为由 SDK 侧 `SkillExecutionPromptContextTests` 单测覆盖。
- dev 在 Completion Notes 记录 SDK commit `4285aac` 与代码路径作为集成点冒烟证据。
- 若后续 SDK 暴露无副作用的纯函数 prompt builder，dev 可激活本测试为断言式单测。

### 5.5 createSkillTool 兼作回归断言
`createSkillTool(registry:)` 在 0.8.x 即存在（Axion 已在用），保留其 @Test
作为「SDK 0.10.0 升级未破坏既有签名」的回归点。

## 6. 约束遵循确认

- [x] 仅 Swift Testing，无 `import XCTest`
- [x] 不调真实 `AgentBuilder.build()`
- [x] 不连 MCP、不起 Helper、不发 API key
- [x] 不调真实 `executeSkillStream`（AC5 已降级 disabled）
- [x] `createAgentTool()` / `createTaskTool()` / `createSkillTool(registry:)` 为纯工厂
      函数，调用本身无副作用，作单测对象合规
- [x] 测试文件位于 `Tests/AxionCLITests/Services/`，被默认单元测试命令命中
- [x] 命名遵循 `test_被测单元_场景_预期结果`
- [x] 不运行 `Tests/**/Integration/`、`Tests/**/AxionE2ETests/`

## 7. 阻塞点 / 风险

- 无阻塞点。AC5 的降级是 story 明确允许的策略，非缺陷。
- 风险（低）：若 SDK 0.10.0 的 `createAgentTool`/`createTaskTool` 在升级后
  schema properties 键集合与预期不符（如 `mcpServers` 改名），AC4 会转红——
  这是 gate 的正确行为，届时 dev 需核实 SDK 实际 schema 并据实调整断言或上报 SDK。
