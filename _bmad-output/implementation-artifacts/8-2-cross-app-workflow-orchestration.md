# Story 8.2: 跨应用工作流编排

Status: done

## Story

As a 用户,
I want 用一句话描述跨多个应用的工作流,
So that Axion 可以自动协调多个应用完成端到端任务.

## Acceptance Criteria

1. **AC1: Planner 生成跨应用计划**
   Given 运行 `axion run "从 Safari 复制网页标题，粘贴到 TextEdit 文档"`
   When Planner 规划
   Then 生成包含跨应用操作的计划：激活 Safari → 获取标题 → 复制到剪贴板 → 切换到 TextEdit → 粘贴

2. **AC2: Executor 窗口切换确保焦点**
   Given 跨应用计划执行中
   When 步骤需要切换目标应用
   Then Executor 通过 `list_windows` + 窗口激活确保目标应用获得焦点，再执行后续操作

3. **AC3: 剪贴板跨应用数据传递**
   Given 跨应用数据传递涉及剪贴板
   When Planner 规划剪贴板操作
   Then 使用 cmd+c / cmd+v 的 hotkey 操作，Executor 在复制后验证剪贴板内容再执行粘贴

4. **AC4: 跨应用失败重规划**
   Given 跨应用计划中某一步失败（如目标应用未安装）
   When 执行失败
   Then 携带失败上下文触发重规划，Planner 可以选择跳过失败步骤或寻找替代路径

5. **AC5: 端到端跨应用操作**
   Given 运行 `axion run "打开浏览器搜索 'Swift Agent'，把第一个结果复制到备忘录"`
   When 完整流程执行
   Then 成功协调 Safari/Chrome 和 Notes/TextEdit 两个应用完成端到端操作

## Tasks / Subtasks

- [x] Task 1: 增强 Planner prompt 的跨应用工作流指导 (AC: #1, #2, #3, #4)
  - [x] 1.1 在 `Prompts/planner-system.md` 的 `# Multi-Window Workflow` 章节添加「Cross-Application Workflow Patterns」子章节
  - [x] 1.2 添加标准跨应用工作流模板：source_app → 获取内容 → 剪贴板 → activate target → 粘贴/操作
  - [x] 1.3 添加剪贴板验证指导：复制后通过 `get_window_state` 确认焦点元素包含预期内容，再执行粘贴
  - [x] 1.4 添加失败恢复指导：跨应用步骤失败时，利用失败上下文（工具返回的错误信息）规划替代路径

- [x] Task 2: 增强 Planner prompt 的重规划上下文指导 (AC: #4)
  - [x] 2.1 在 `Prompts/planner-system.md` 的 `# Failure Recovery` 章节添加跨应用场景指导
  - [x] 2.2 说明当应用不存在时，Planner 可建议用户安装或选择替代应用
  - [x] 2.3 说明当剪贴板操作失败时，可尝试 AX tree 直接读取内容作为 fallback

- [x] Task 3: 单元测试 (AC: #1-#5)
  - [x] 3.1 测试 planner prompt 包含跨应用工作流模式指导
  - [x] 3.2 测试 planner prompt 包含剪贴板验证指导
  - [x] 3.3 测试 planner prompt 包含跨应用失败恢复指导

## Dev Notes

### 核心设计：Prompt 工程而非代码变更

Story 8.2 不需要修改 Swift 源代码。当前架构（双进程 + MCP stdio + SDK Agent Loop）已经完整支持跨应用工作流：

- **SDK Agent Loop** 已是 tool-use 循环，LLM 在每轮决定调用哪个工具
- **Helper 工具** 已经支持所有需要的操作：`launch_app`, `activate_window`, `list_windows`, `get_window_state`, `hotkey`, `click`, `type_text`
- **Story 8.1** 已添加 `z_order`, `app_name` 字段和 Multi-Window Workflow 基础指导

Story 8.2 的所有 AC 通过增强 `planner-system.md` prompt 来实现，让 LLM 在规划跨应用任务时有更精确的指导。

### 为什么不需要代码变更

| AC | 实现方式 | 理由 |
|----|---------|------|
| AC1 | Prompt 指导 | LLM 已能调用 activate_window + hotkey，只需更明确的模式指导 |
| AC2 | 已实现（Story 8.1） | list_windows + activate_window 已在 prompt 中有指导 |
| AC3 | Prompt 指导 | 剪贴板 cmd+c/v 已可用，需要添加验证步骤指导 |
| AC4 | Prompt 指导 + 已有架构 | 重规划机制已存在于 RunEngine 状态机 |
| AC5 | 以上组合验证 | 端到端需要真实 macOS 环境（集成测试/手动验证） |

### 需要修改的现有文件

1. **`Prompts/planner-system.md`** [UPDATE]
   - 扩展 `# Multi-Window Workflow` 章节
   - 增强 `# Failure Recovery` 章节

### 不需要创建新文件

本 Story 是对 planner prompt 的增量增强。不需要新的 Swift 文件、工具或模型。

### 前一 Story 的关键学习（Story 8.1）

- **1189 测试全部通过**，零回归 — 变更时保持测试通过
- **Planner prompt 修改不需要编译** — 纯文本变更，通过单元测试验证内容存在性
- **stdout 纯净原则**：不直接 print，使用 outputHandler
- **Codable 模型扩展规范**：新字段使用 `decodeIfPresent + ?? 默认值` 模式
- **测试必须调用真实方法**，不允许测试纯字面量（bogus test）
- **Story 8.1 添加的 Multi-Window Workflow 基础**：窗口发现、切换、最小化恢复、剪贴板传递、上下文追踪

### 跨应用工作流的核心模式

```
1. Discovery:  list_windows → 选择 source app window
2. Source Op:  activate_window → 操作 source app → hotkey cmd+c (复制)
3. Transfer:   (剪贴板已持有数据)
4. Target Op:  activate_window → 操作 target app → hotkey cmd+v (粘贴)
5. Verify:     get_window_state / screenshot 确认结果
```

### 失败场景与恢复策略

| 失败场景 | 恢复策略 |
|---------|---------|
| 目标应用未安装 | replan → 建议替代应用或提示用户安装 |
| 窗口激活失败 | retry activate_window → 若仍失败则 pause_for_human |
| 剪贴板为空 | 尝试重新复制 → 检查 AX tree 直接读取内容作为 fallback |
| 粘贴后内容不正确 | 截图验证 → undo (cmd+z) → 重新规划输入方式 |

### References

- Epic 8 定义: `_bmad-output/planning-artifacts/epics.md` (Story 8.2)
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Project Context: `_bmad-output/project-context.md`
- Previous Story 8.1: `_bmad-output/implementation-artifacts/8-1-multi-window-state-tracking-context-management.md`
- Planner system prompt: `Prompts/planner-system.md`
- RunEngine state machine: `Sources/AxionCore/Models/RunState.swift`

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7

### Debug Log References

### Completion Notes List

- 添加 Cross-Application Workflow Patterns 子章节到 planner-system.md
- 包含 6 步跨应用工作流模板：discover → source → verify → switch → target → verify
- 添加剪贴板验证指导和应用不存在时的替代建议
- 在 Failure Recovery 添加跨应用失败恢复：替代应用建议 + AX tree fallback
- 3 个新测试验证 prompt 内容，全部 1192 测试通过

### File List

- Prompts/planner-system.md [MODIFIED] — 添加 Cross-Application Workflow Patterns 章节，增强 Failure Recovery
- Tests/AxionCLITests/Planner/PromptBuilderTests.swift [MODIFIED] — 添加 3 个跨应用 prompt 内容测试

### Change Log

- 2026-05-14: Story 8.2 实现完成 — 跨应用工作流编排 prompt 增强
