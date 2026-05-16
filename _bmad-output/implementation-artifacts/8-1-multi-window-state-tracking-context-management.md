# Story 8.1: 多窗口状态追踪与上下文管理

Status: done

## Story

As a Planner,
I want 同时追踪多个应用窗口的状态,
So that 我可以在规划时了解所有相关窗口的布局和内容.

## Acceptance Criteria

1. **AC1: 增强版 list_windows 返回所有应用窗口**
   Given 多个应用正在运行（如 Chrome 和 TextEdit）
   When 调用 list_windows（不指定 pid）
   Then 返回所有应用的窗口列表，每项包含 app_name、pid、window_id、title、bounds 和 z-order（窗口层级）

2. **AC2: Planner prompt 支持命名窗口占位符**
   Given 任务涉及两个应用的交互
   When Planner 生成计划
   Then 计划中的步骤可以引用不同的 window_id，Planner system prompt 中包含多窗口规划指导

3. **AC3: 窗口切换前自动刷新**
   Given 执行过程中窗口焦点切换
   When Executor 在窗口间切换操作（通过 activate_window）
   Then SDK Agent Loop 自然处理切换（调用 activate_window → 后续操作在目标窗口），无需特殊 executor 逻辑

4. **AC4: 最小化窗口自动恢复**
   Given 某个目标窗口被用户最小化
   When Executor 尝试操作该窗口（validate_window 返回 actionable: false）
   Then 检测到窗口不可见，通过 activate_window(pid:) 恢复窗口后再执行操作；如恢复失败则触发 takeover

5. **AC5: Trace 记录多窗口上下文**
   Given 多窗口上下文
   When TraceRecorder 记录事件
   Then 每个步骤事件包含 window_id 和 app_name 字段（如可用），trace 文件可回溯完整的多窗口操作序列

## Tasks / Subtasks

- [x] Task 1: 扩展 WindowInfo 模型添加 z-order 字段 (AC: #1)
  - [x] 1.1 在 `Sources/AxionHelper/Models/WindowInfo.swift` 中添加 `zOrder: Int` 字段（CodingKeys: `z_order`）
  - [x] 1.2 更新 `AccessibilityEngineService.listWindows()` 利用 CGWindowList 的层序信息填充 zOrder（窗口在数组中的索引即为层序）

- [x] Task 2: 扩展 WindowState 模型添加 appName 字段 (AC: #5)
  - [x] 2.1 在 `Sources/AxionHelper/Models/WindowState.swift` 中添加 `appName: String?` 字段（CodingKeys: `app_name`）
  - [x] 2.2 更新 `AccessibilityEngineService.getWindowState()` 通过 NSWorkspace 查找 app name 并填充

- [x] Task 3: 更新 Planner system prompt 添加多窗口规划指导 (AC: #2)
  - [x] 3.1 在 `Prompts/planner-system.md` 添加「Multi-Window Workflow」章节
  - [x] 3.2 指导 LLM 在跨应用任务中使用 activate_window 切换窗口
  - [x] 3.3 说明 list_windows 不带 pid 返回所有应用窗口
  - [x] 3.4 说明剪贴板（hotkey cmd+c / cmd+v）作为跨应用数据传递方式

- [x] Task 4: 更新 TraceRecorder 记录窗口上下文 (AC: #5)
  - [x] 4.1 在 `recordToTrace` 的 tool_use 和 tool_result 事件中提取并记录 window_id / app_name（从工具调用参数和返回值中提取）

- [x] Task 5: 单元测试 (AC: #1-#5)
  - [x] 5.1 测试 WindowInfo 包含 zOrder 字段的 Codable round-trip
  - [x] 5.2 测试 WindowState 包含 appName 字段的 Codable round-trip
  - [x] 5.3 测试 planner prompt 包含多窗口指导内容
  - [x] 5.4 测试 trace 事件在 tool_use 记录中包含窗口信息字段

## Dev Notes

### 核心设计：在现有架构上增量扩展

Story 8.1 不改变 Axion 的核心架构（双进程 + MCP stdio + SDK Agent Loop）。所有多窗口能力通过以下方式实现：

1. **Helper 端**：扩展 `WindowInfo` 和 `WindowState` 模型，增加 z-order 和 app_name 字段
2. **Prompt 端**：在 `planner-system.md` 添加多窗口规划指导，让 LLM 知道如何编排跨窗口操作
3. **Trace 端**：在记录中增加窗口上下文字段

### SDK Agent Loop 不需要修改

当前架构使用 SDK 的 `createAgent()` + `agent.stream(task)` 模式。Agent Loop 已经是 tool-use 循环 — LLM 在每轮决定调用哪个工具。多窗口编排通过 prompt 指导 LLM 在正确的时机调用 `activate_window`、`list_windows` 等工具，不需要修改 executor 或 engine。

### 现有窗口管理能力（已实现，可直接复用）

| 工具 | 当前能力 | Story 8.1 变更 |
|------|----------|---------------|
| `list_windows` | 返回 WindowInfo[]（window_id, pid, title, app_name, bounds） | 添加 z_order 字段 |
| `get_window_state` | 返回 WindowState（bounds, is_minimized, is_focused, ax_tree） | 添加 app_name 字段 |
| `activate_window` | 激活指定应用/窗口 | 无变更，已满足多窗口切换需求 |
| `validate_window` | 检查窗口是否存在且可操作 | 无变更，已满足窗口状态检测 |

### 最小化窗口恢复策略

当 LLM 尝试操作一个最小化窗口时：
1. `validate_window` 返回 `actionable: false`（已实现）
2. LLM 根据指导调用 `activate_window(pid:)` 恢复窗口
3. 如 `activate_window` 失败，LLM 可触发 `pause_for_human`（takeover 机制，Story 7.1 已实现）

这完全在 prompt 引导层面实现，不需要新的自动恢复逻辑。

### z-order 实现方式

`CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)` 返回的窗口列表天然按 z-order 排列（最前面的窗口在前面）。用窗口在列表中的索引作为 zOrder 值即可 — 值越小表示越靠前（z-order 越高）。

### 需要修改的现有文件

1. **`Sources/AxionHelper/Models/WindowInfo.swift`** [UPDATE]
   - 添加 `zOrder: Int` 字段
   - 添加 CodingKey `z_order`
   - Codable round-trip 兼容（新字段用 decodeIfPresent + 默认值 0）

2. **`Sources/AxionHelper/Models/WindowState.swift`** [UPDATE]
   - 添加 `appName: String?` 字段
   - 添加 CodingKey `app_name`
   - getWindowState 中通过 NSWorkspace 查找

3. **`Sources/AxionHelper/Services/AccessibilityEngine.swift`** [UPDATE]
   - `listWindows()`: 填充 zOrder（数组索引）
   - `getWindowState()`: 通过 NSWorkspace 查找 appName 并填充

4. **`Prompts/planner-system.md`** [UPDATE]
   - 添加 Multi-Window Workflow 章节

5. **`Sources/AxionCLI/Commands/RunCommand.swift`** [UPDATE]
   - `recordToTrace()` 方法中 tool_use / tool_result 事件增加 window_id / app_name 字段提取

### 不需要创建新文件

本 Story 是对现有模型和 prompt 的增量扩展。不需要新的模块、工具或命令。

### 前一 Story 的关键学习（Story 7.2）

- **939 测试全部通过**，零回归 — 变更时保持测试通过
- **stdout 纯净原则**：不直接 print，使用 outputHandler
- **buildFullSystemPrompt 已有 dryrun + fast 分支** — 多窗口 prompt 指导直接追加在 planner-system.md 中，不需要在 buildFullSystemPrompt 中添加新分支
- **Codable 模型扩展规范**：新字段使用 `decodeIfPresent + ?? 默认值` 模式，保持向后兼容
- **测试必须调用真实方法**，不允许测试纯字面量（bogus test）

### Import 顺序

无变化 — 修改的文件已有所有需要的 import。

### 项目结构注意事项

- 模型变更在 `Sources/AxionHelper/Models/`（Helper 专有模型）
- Prompt 变更在 `Prompts/planner-system.md`
- Trace 变更在 `Sources/AxionCLI/Commands/RunCommand.swift` 的 `recordToTrace` 方法
- 测试文件：`Tests/AxionHelperTests/Models/` 下新增或扩展模型测试

### References

- Epic 8 定义: `_bmad-output/planning-artifacts/epics.md` (Story 8.1)
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Project Context: `_bmad-output/project-context.md`
- Previous Story 7.2: `_bmad-output/implementation-artifacts/7-2-fast-mode.md`
- WindowInfo model: `Sources/AxionHelper/Models/WindowInfo.swift`
- WindowState model: `Sources/AxionHelper/Models/WindowState.swift`
- AccessibilityEngine: `Sources/AxionHelper/Services/AccessibilityEngine.swift`
- Planner system prompt: `Prompts/planner-system.md`
- RunCommand + trace: `Sources/AxionCLI/Commands/RunCommand.swift`
- ToolNames: `Sources/AxionCore/Constants/ToolNames.swift`

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7

### Debug Log References

### Completion Notes List

- WindowInfo: 添加 zOrder 字段，使用 enumerate + index 填充 z-order，decodeIfPresent 向后兼容
- WindowState: 添加 appName 字段，通过 NSWorkspace.runningApplications 查找，decodeIfPresent 向后兼容
- Planner prompt: 添加 Multi-Window Workflow 章节，覆盖窗口发现、切换、最小化恢复、剪贴板传递
- Trace: tool_use 事件从 input JSON 提取 window_id/pid，tool_result 事件从 content JSON 提取 app_name/window_id
- 全部 1189 个测试通过，零回归

### File List

- Sources/AxionHelper/Models/WindowInfo.swift [MODIFIED] — 添加 zOrder 字段和自定义 init(from:)
- Sources/AxionHelper/Models/WindowState.swift [MODIFIED] — 添加 appName 字段和自定义 init(from:)
- Sources/AxionHelper/Services/AccessibilityEngine.swift [MODIFIED] — listWindows 填充 zOrder，getWindowState 填充 appName
- Prompts/planner-system.md [MODIFIED] — 添加 Multi-Window Workflow 章节
- Sources/AxionCLI/Commands/RunCommand.swift [MODIFIED] — recordToTrace 提取窗口上下文
- Tests/AxionHelperTests/Models/WindowInfoTests.swift [MODIFIED] — 添加 zOrder 测试
- Tests/AxionHelperTests/Models/WindowStateTests.swift [MODIFIED] — 添加 appName 测试

### Change Log

- 2026-05-14: Story 8.1 实现完成 — 多窗口状态追踪与上下文管理
