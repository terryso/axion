---
stepsCompleted:
  - step-01-load-context
  - step-02-discover-tests
  - step-03-map-criteria
  - step-04-analyze-gaps
  - step-05-gate-decision
lastStep: 'step-05-gate-decision'
lastSaved: '2026-05-09'
coverageBasis: 'acceptance_criteria'
oracleConfidence: 'high'
oracleResolutionMode: 'formal_requirements'
oracleSources:
  - '_bmad-output/planning-artifacts/epics.md'
  - '_bmad-output/planning-artifacts/prd.md'
  - '_bmad-output/planning-artifacts/architecture.md'
externalPointerStatus: 'not_used'
tempCoverageMatrixPath: '/tmp/tea-trace-coverage-matrix-2026-05-08T23-58-50.json'
---

# Axion 追溯报告 -- Epic 1 Stories 1.1-1.6

## Gate Decision: FAIL

**Rationale:** P0 coverage is 92% (required: 100%). 1 critical requirement uncovered.

---

## 覆盖率概要

| 指标 | 值 |
|------|-----|
| 总需求数 | 43 |
| 完全覆盖 (FULL) | 41 (95%) |
| 部分覆盖 (PARTIAL) | 1 |
| 未覆盖 (NONE) | 1 |
| 测试文件 | 16 |
| 测试用例 | 131 |

## 优先级覆盖

| 优先级 | 覆盖/总数 | 百分比 | 状态 |
|--------|-----------|--------|------|
| P0 | 23/25 | 92% | NOT_MET (需要 100%) |
| P1 | 15/15 | 100% | MET |
| P2 | 3/3 | 100% | MET |
| P3 | 0/0 | N/A | MET |

---

## 追溯矩阵

### Story 1.1: SPM 项目脚手架与 AxionCore 共享模型

| AC ID | 接受标准 | 优先级 | 覆盖 | 测试数 |
|-------|---------|--------|------|--------|
| S1.1-AC1 | swift build 编译成功，三目标结构 | P0 | FULL | 2 |
| S1.1-AC2 | Plan Codable round-trip，Value placeholder 保留 | P0 | FULL | 7 |
| S1.1-AC3 | RunState 包含全部 9 个 case | P0 | FULL | 5 |
| S1.1-AC4 | AxionConfig Codable 输出 camelCase | P1 | FULL | 3 |
| S1.1-AC5 | AxionError MCP ToolResult 格式 (error/message/suggestion) | P0 | FULL | 8 |
| S1.1-AC6 | 所有 Protocol 位于 AxionCore/Protocols/ | P0 | FULL | 5 |
| S1.1-AC7 | API Key 不出现在 Codable 编码中 | P1 | FULL | 1 |

### Story 1.2: Helper MCP Server 基础

| AC ID | 接受标准 | 优先级 | 覆盖 | 测试数 |
|-------|---------|--------|------|--------|
| S1.2-AC1 | MCP initialize 返回正确响应 | P0 | FULL | 2 |
| S1.2-AC2 | tools/list 返回全部已注册工具 | P0 | FULL | 4 |
| S1.2-AC3 | 未知工具调用返回 isError=true | P0 | FULL | 2 |
| S1.2-AC4 | stdin EOF 时 Helper 优雅退出 | P0 | FULL | 3 |

### Story 1.3: 应用启动与窗口管理

| AC ID | 接受标准 | 优先级 | 覆盖 | 测试数 |
|-------|---------|--------|------|--------|
| S1.3-AC1 | launch_app 启动成功返回 pid | P0 | FULL | 1 |
| S1.3-AC2 | list_apps 返回应用列表 | P0 | FULL | 2 |
| S1.3-AC3 | list_windows 返回窗口列表 | P0 | FULL | 3 |
| S1.3-AC4 | get_window_state 返回完整窗口状态 | P0 | FULL | 2 |
| S1.3-AC5 | 应用未安装返回 app_not_found 错误 | P1 | FULL | 1 |
| S1.3-AC6 | 应用已运行返回已有 pid | P2 | FULL | 1 |
| S1.3-AC7 | 无效 window_id 返回错误 | P1 | FULL | 1 |

### Story 1.4: 鼠标与键盘操作

| AC ID | 接受标准 | 优先级 | 覆盖 | 测试数 |
|-------|---------|--------|------|--------|
| S1.4-AC1 | click 单击操作 | P0 | FULL | 2 |
| S1.4-AC2 | type_text 文本输入 | P0 | FULL | 3 |
| S1.4-AC3 | press_key 按键 | P0 | FULL | 1 |
| S1.4-AC4 | hotkey 组合键 | P0 | FULL | 1 |
| S1.4-AC5 | scroll 滚动 | P1 | FULL | 1 |
| S1.4-AC6 | drag 拖拽 | P1 | FULL | 1 |
| S1.4-AC7 | double_click 双击 | P2 | FULL | 1 |
| S1.4-AC8 | right_click 右键 | P2 | FULL | 1 |
| S1.4-AC9 | 无效坐标返回错误 | P1 | FULL | 5 |
| S1.4-AC10 | 无效按键名/组合键格式返回错误 | P1 | FULL | 3 |
| S1.4-AC11 | 键名映射 (key code / hotkey 解析) | P1 | FULL | 21 |

### Story 1.5: 截图、AX Tree 与 URL 打开

| AC ID | 接受标准 | 优先级 | 覆盖 | 测试数 |
|-------|---------|--------|------|--------|
| S1.5-AC1 | screenshot 返回 base64 不超过 5MB | P0 | FULL | 5 |
| S1.5-AC2 | screenshot 全屏截图 | P0 | FULL | 2 |
| S1.5-AC3 | get_ax_tree 返回完整 AX tree | P0 | FULL | 3 |
| S1.5-AC4 | AX tree maxNodes=500 截断 | P1 | FULL | 2 |
| S1.5-AC5 | open_url 在默认浏览器打开 | P1 | FULL | 5 |
| S1.5-AC6 | screenshot 无效 window_id 返回错误 | P1 | FULL | 2 |
| S1.5-AC7 | get_ax_tree 无效 window_id 返回错误 | P1 | FULL | 1 |
| S1.5-AC8 | open_url 无效/不支持 URL 返回错误 | P1 | FULL | 9 |

### Story 1.6: Helper 完整集成与 App 打包

| AC ID | 接受标准 | 优先级 | 覆盖 | 测试数 |
|-------|---------|--------|------|--------|
| S1.6-AC1 | tools/list 返回全部 15 个工具 | P0 | FULL | 4 |
| S1.6-AC2 | Info.plist LSUIElement + LSMinimumSystemVersion | P0 | FULL | 2 |
| S1.6-AC3 | Helper 启动 < 500ms (NFR2) | P0 | FULL | 1 |
| S1.6-AC4 | 单个 AX 操作 < 200ms (NFR3) | **P0** | **NONE** | **0** |
| S1.6-AC5 | Helper App 打包结构正确 | P1 | FULL | 3 |
| S1.6-AC6 | CLI 退出时 Helper 随之退出 | P0 | PARTIAL | 2 |

---

## 缺口分析

### 严重缺口 (P0 NONE) -- 1 项

| AC ID | 标题 | 说明 |
|-------|------|------|
| **S1.6-AC4** | 单个 AX 操作耗时 < 200ms (NFR3) | 缺少 NFR3 性能测试。现有的 `SingleOperationPerformanceTests` 在 Integration 目录中，需要真实 macOS 应用和 AX 权限，不属于单元测试覆盖范围。需要添加可在 CI 运行的 Mock 性能测试。 |

### 部分覆盖 (PARTIAL) -- 1 项

| AC ID | 标题 | 说明 |
|-------|------|------|
| **S1.6-AC6** | CLI 退出时 Helper 随之退出 | 现有测试覆盖了 EOF 场景下的 Helper 退出，但缺少 CLI 进程退出场景的端到端测试（需 HelperProcessManager 层面的集成测试）。 |

---

## 建议

1. **[URGENT]** 为 S1.6-AC4 添加 NFR3 性能测试。建议使用 Mock MCPClient 测量从请求到响应的耗时，确保 < 200ms 的性能约束在 CI 中可验证。
2. **[MEDIUM]** 为 S1.6-AC6 添加 HelperProcessManager 集成测试，验证 CLI 进程退出时 Helper 被正确清理（SIGTERM/SIGKILL）。

---

## 测试级别分布

| 级别 | 测试数 | 覆盖的需求数 |
|------|--------|-------------|
| Unit | 128 | 41 |
| Integration | 3 | 3 |
| E2E | 0 | 0 |
| API | 0 | 0 |
| Component | 0 | 0 |

---

## Gate Decision: FAIL

| 条件 | 要求 | 实际 | 状态 |
|------|------|------|------|
| P0 覆盖率 | 100% | 92% | NOT_MET |
| P1 覆盖率 | >=90% / >=80% | 100% | MET |
| 整体覆盖率 | >=80% | 95% | MET |

**结论:** P0 覆盖率未达到 100% 阈值（缺 NFR3 性能测试），Gate FAIL。
