---
stepsCompleted: ['step-01-load-context', 'step-02-discover-tests', 'step-03-build-matrix', 'step-04-gate-decision']
lastStep: 'step-04-gate-decision'
lastSaved: '2026-06-15'
storyId: '40.1'
storyKey: '40-1-sdk-runtime-readiness-gate'
storyFile: '_bmad-output/implementation-artifacts/40-1-sdk-runtime-readiness-gate.md'
gateTestFile: 'Tests/AxionCLITests/Services/SDKRuntimeReadinessGateTests.swift'
atddChecklist: '_bmad-output/test-artifacts/atdd-checklist-40-1-sdk-runtime-readiness-gate.md'
coverageBasis: 'acceptance_criteria'
oracleResolutionMode: 'formal_requirements'
oracleConfidence: 'high'
oracleSources:
  - '_bmad-output/implementation-artifacts/40-1-sdk-runtime-readiness-gate.md'
  - 'Tests/AxionCLITests/Services/SDKRuntimeReadinessGateTests.swift'
  - '_bmad-output/test-artifacts/atdd-checklist-40-1-sdk-runtime-readiness-gate.md'
  - 'Package.swift'
  - 'Package.resolved'
externalPointerStatus: 'not_used'
gateDecision: 'PASS'
executionMode: 'yolo (非交互 Create)'
framework: 'Swift Testing (import Testing / @Suite / @Test / #expect)'
---

# 可追溯性矩阵与质量门决策 — Story 40.1 SDK Runtime Readiness Gate

**生成时间：** 2026-06-15
**Story：** 40.1（`40-1-sdk-runtime-readiness-gate`）
**覆盖基准（Oracle）：** 正式验收标准（formal requirements），置信度 high
**质量门决策：** **PASS**

---

## 1. 可追溯性矩阵（AC → 验证方式 → 证据 → 覆盖状态）

| AC | 描述 | 验证层级 | 具体测试 / 证据 | 覆盖状态 |
|----|------|----------|----------------|----------|
| **AC1** | `Package.swift`/`.resolved` 升到 0.10.0（revision `4285aac`） | **构建级**（非单测） | `Package.swift:18` = `from: "0.10.0"`；`Package.resolved` = `version: "0.10.0"` / `revision: "4285aac6535236dae014e945eed694ed7fe6bd4b"`（实测核实，精确匹配 AC 要求） | ✅ 已覆盖（构建级） |
| **AC2** | `createAgentTool`/`createTaskTool`/`createSkillTool` 可 import 且实例化，返回 `ToolProtocol` | **单测**（编译级 gate） | `test_createAgentTool_resolvesAndReturnsAgentName`、`test_createTaskTool_resolvesAndReturnsTaskName`、`test_createSkillTool_resolvesWithRegistry` | ✅ PASS（3/3 绿） |
| **AC3** | Task/Agent `name` 与 schema 兼容（仅 name 不同，schema 等价） | **单测**（schema 反射） | `test_createAgentTool_*`、`test_createTaskTool_*`、`test_taskAndAgent_shareEquivalentSchema`（完整 `inputSchema` 规范化 JSON 比对） | ✅ PASS（绿） |
| **AC4** | Task/Agent schema 含 `skills` 与 `mcpServers`（或 `mcp_servers`）字段 | **单测**（schema 反射） | `test_taskAndAgent_schemaIncludesSkillsAndMcpServers` | ✅ PASS（绿） |
| **AC5** | `executeSkillStream` 注入 `Skill package context:` 块 | **合规降级**（`.disabled`） | `test_filesystemSkill_promptIncludesPackageContext`（disabled，运行时 skipped）；行为由 SDK 侧 `SkillExecutionPromptContextTests` 覆盖；集成点冒烟证据：SDK commit `4285aac`、代码路径 `Core/Agent.swift:3293-3319` | ✅ 合规降级（非缺口） |
| **AC6** | gate 失败时不得关闭 Epic 40 | **文档级**（流程守护） | Completion Notes 记录守护策略：SDK 未 resolve 到 0.10.0+ 时，Story 40.5/40.6 与 Epic 40 整体标记 blocked/deferred；`SDKRuntimeReadinessGateTests`（AC2/3/4）作为编译/单测级 gate 天然守护 | ✅ 已覆盖（文档级 + gate 机制） |

---

## 2. 覆盖率分析

### 2.1 单测可覆盖的 AC 通过率

单测可覆盖的 AC：**AC2 / AC3 / AC4**（3 个，均为编译/运行级 gate）。

- 通过：3/3 = **100%**
- 运行证据：`swift test --filter "SDKRuntimeReadinessGateTests"` →
  - Suite「SDK Runtime Readiness Gate (Story 40.1)」**passed** after 0.007s
  - **6 tests in 1 suite passed**（含 5 个激活 + 1 个 AC5 skipped，套件整体 passed）
  - 5 个激活 @Test：`createAgentTool` / `createTaskTool` / `createSkillTool` / `taskAndAgent_shareEquivalentSchema` / `taskAndAgent_schemaIncludesSkillsAndMcpServers` 全绿

### 2.2 整体 AC 覆盖（含构建/文档级）

全部 6 个 AC 覆盖情况：

- **单测覆盖（绿）：** AC2、AC3、AC4 — 3 个
- **构建级覆盖：** AC1（`Package.resolved` 实测匹配） — 1 个
- **文档级 + 机制覆盖：** AC6（守护策略 + gate 套件天然阻断） — 1 个
- **合规降级（非缺口）：** AC5（`.disabled`，由 SDK 单测覆盖） — 1 个

**整体 AC 覆盖率：6/6 = 100%**（无未解释缺口 / 无 unresolved gap）。

> 说明：AC1 与 AC6 在性质上不是单测对象（构建/流程级验证）。按 BMAD trace 工作流与 risk-governance，未解释的覆盖缺口（unresolved gap）才会触发 FAIL；此处所有非单测 AC 均有明确证据与解释，不计为缺口。

---

## 3. 质量门决策：**PASS**

### 决策依据（基于 risk-governance gate 规则）

按 gate 决策引擎逻辑：

1. **CRITICAL 阻塞（score=9, OPEN）：0** — 无。
2. **未解释覆盖缺口（unresolved gaps）：0** — AC1/AC6 有构建/文档证据，AC5 有合规降级说明，均非 unresolved。
3. **FAIL 条件（critical > 0 或 unresolved gap > 0）：** 不满足。
4. **单测层 gate 套件：** 编译通过 + 5 激活测试全绿 + AC5 合规 skipped。

→ 决策为 **PASS**。

### 关键证据

- `swift build` → Build complete（0.8.3→0.10.0 非破坏性升级，Axion 源码零改动）
- gate 套件实测：`Test run with 6 tests in 1 suite passed`
- `Package.resolved` 精确 pin 到 AC1 要求的 revision `4285aac...`
- code-review 报告：**PASS，无 blocking**
- 全量单元测试（CLAUDE.md 命令）：3813 tests passed（见 story Debug Log）

---

## 4. 缺口与风险

### 4.1 真实缺口

**无。** 单测可覆盖的 AC（2/3/4）通过率 100%，无任何未解释缺口。

### 4.2 合规降级（非缺口）

- **AC5（skill package context 注入）：** `.disabled`，运行时 skipped。
  - **降级原因：** SDK `Core/Agent.swift:3293-3319` 的 package-context 注入需真实 `Agent` 运行时（API key 校验 / 网络），违反 CLAUDE.md「单元测试禁止真实运行时副作用」规则。
  - **替代覆盖：** SDK 侧 `SkillExecutionPromptContextTests`（SDK test-plan）已覆盖该行为。
  - **集成点冒烟证据：** Completion Notes 已记录 SDK commit `4285aac6535236dae014e945eed694ed7fe6bd4b` 与代码路径。
  - **激活条件：** 若后续 SDK 暴露无副作用的纯函数 prompt builder，dev 可激活为断言式单测。
  - **性质：** 这是 story 明确允许的策略，**非缺陷、非阻塞**。

### 4.3 已知预存在 flaky 测试（与本 story 无关）

code-review 记录：6 个 ReviewScheduler/CuratorScheduler flaky 测试为**预存在、与本 story 无关**的问题，不构成 quality gate 阻塞。风险评分低（probability 受控、impact 局限于调度子系统），归属至各自 owner 跟踪，不计入本 story 决策。

---

## 5. 建议下一步

1. **更新 sprint-status 与 story 状态：** 将 Story 40.1 状态由 `review` 推进到 `done`，sprint-status.yaml 同步标记 40.1 完成并解锁依赖链首节点（40.2–40.10 可启动）。
2. **进入 Epic 40 线性链下一节点：** Story 40.2（tool profile helper）或 40.3（注册 Agent/Task 工具）。gate 已证明 SDK 0.10.0 API 可达且行为符合预期，后续 story 可安全依赖。
3. **AC5 跟踪项（可选）：** 在 Epic 40 backlog 记录一条「待 SDK 暴露纯函数 prompt builder 时激活 AC5 断言式单测」的后续 ticket，避免降级被遗忘。
4. **文档卫生（可选，非本 story 范围）：** `project-context.md` 第 29/38/890 行「path-based 依赖」描述与实际远程 URL 依赖不符（readiness report 已列为 minor concern），可单独提交修正。

---

## 附：gate 测试套件运行实测（2026-06-15）

```
Suite "SDK Runtime Readiness Gate (Story 40.1)" started.
  Test "createSkillTool resolves with an (empty) SkillRegistry and is named 'Skill'" — passed
  Test "filesystem skill prompt includes 'Skill package context' block" — skipped (AC5 合规降级)
  Test "Task and Agent input schema include 'skills' and 'mcpServers' fields" — passed
  Test "createAgentTool resolves and returns a tool named 'Agent'" — passed
  Test "createTaskTool resolves and returns a tool named 'Task'" — passed
  Test "Task and Agent share equivalent input schema (differ only by name)" — passed
Suite "SDK Runtime Readiness Gate (Story 40.1)" passed after 0.007 seconds.
Test run with 6 tests in 1 suite passed after 0.007 seconds.
```
