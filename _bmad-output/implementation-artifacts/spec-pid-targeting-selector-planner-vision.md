---
title: '工具 pid/window_id 定向 + AX Selector + Planner 截图视觉'
type: 'feature'
created: '2026-05-11'
status: 'done'
context:
  - 'Sources/AxionHelper/MCP/ToolRegistrar.swift'
  - 'Sources/AxionHelper/Services/AccessibilityEngine.swift'
  - 'Sources/AxionHelper/Services/InputSimulationService.swift'
  - 'Sources/AxionCLI/Planner/LLMPlanner.swift'
  - 'Sources/AxionCLI/Planner/PromptBuilder.swift'
  - 'Prompts/planner-system.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Axion 的操作工具（click/type_text/press_key/hotkey）缺少 pid/window_id 定向参数，所有操作都是全局的——多窗口场景无法指定目标窗口，后台模式形同虚设。Planner 不传截图给 LLM，只能靠 AX tree 文本推测 UI 布局。Click 只支持 x,y 坐标，窗口位置变化就失效。

**Approach:** 三步一体：(1) 给 click/type_text/press_key/hotkey 加上可选的 pid + window_id 参数，并在 AX selector 匹配失败时用坐标回退；(2) 给 click/double_click/right_click 加 `__selector` 支持（title, title_contains, ax_id, role, ordinal），AccessibilityEngine 通过 AX tree 解析 selector 为坐标；(3) LLMPlanner 在规划前截取当前窗口截图，通过 LLMClientProtocol 传给 LLM。更新 planner-system.md 反映新参数。

## Boundaries & Constraints

**Always:**
- pid/window_id 在所有操作工具中是可选参数——当提供时走 AX 定位路径，未提供时回退到全局坐标/输入（向后兼容）
- __selector 解析失败时返回错误，不静默回退到坐标——Planner 必须明确传坐标或 selector
- 截图只在 windowId 可用时才捕获；不可用时退化为纯文本（AX tree）规划
- 不修改 InputSimulationService 的底层实现——它仍然是坐标级的 CGEvent 操作
- 测试覆盖新增的 selector 解析逻辑和 planner 截图路径

**Ask First:**
- 如果 AccessibilityEngine 的 selector 匹配找到多个候选元素，是选第一个还是返回 ambiguous 错误？（当前设计：ordinal 参数消歧，无 ordinal 时选第一个）

**Never:**
- 不实现 OpenClick 的 `multi_drag`/`click_hold`/`diff_windows`/`list_browser_tabs`/`zoom`/`set_value`——PRD 没有列出这些工具
- 不修改 OpenAgentSDK 的 API——这是应用层改动
- 不添加 address bar 自动检测——可以在后续 prompt 优化中处理

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Click with selector | `{ pid, window_id, __selector: { title: "OK", role: "AXButton" } }` | 匹配 AX tree 中 role=AXButton 且 title=OK 的元素，计算中心坐标，执行 click | 找不到元素 → `selector_no_match` 错误 |
| Click with selector + ordinal | `{ pid, window_id, __selector: { title: "Item", ordinal: 2 } }` | 匹配第 3 个 title="Item" 的元素（ordinal 0-based） | ordinal 越界 → `selector_ordinal_out_of_range` 错误 |
| Click with selector, no match | `{ pid, window_id, __selector: { title: "NotExist" } }` | 返回错误 JSON `{ error: "selector_no_match", message: "..." }` | 不静默回退 |
| Click with coordinates (backward compat) | `{ x: 100, y: 200 }` | 直接执行坐标点击，行为不变 | 坐标越界 → 现有错误 |
| TypeText with pid | `{ pid, window_id, text: "hello" }` | 现有 typeText 行为不变（pid/window_id 仅为上下文标记） | 现有错误 |
| Planner with screenshot | windowId 可用 | 截图 → base64 → 作为 image block 传给 LLM | 截图失败 → 退化为纯文本规划，不阻塞 |
| Planner no windowId | windowId 为 nil | 只传 AX tree 文本，不传截图 | 正常规划 |

</frozen-after-approval>

## Code Map

- `Sources/AxionHelper/Protocols/InputSimulating.swift` — 鼠标/键盘协议，不需要改（底层仍是坐标级）
- `Sources/AxionHelper/Services/InputSimulationService.swift` — 底层 CGEvent 实现，不需要改
- `Sources/AxionHelper/MCP/ToolRegistrar.swift` — **主要改动**：给 ClickTool/DoubleClickTool/RightClickTool/TypeTextTool/PressKeyTool/HotkeyTool 加 pid/window_id 参数，给 Click 系列加 __selector 参数和解析逻辑
- `Sources/AxionHelper/Services/AccessibilityEngine.swift` — **主要改动**：新增 `resolveSelector(windowId:selector:)` 方法，遍历 AX tree 匹配 selector 条件
- `Sources/AxionHelper/Protocols/WindowManaging.swift` — 加 `resolveSelector` 到协议
- `Sources/AxionHelper/Models/AXElement.swift` — 可能需要加 `identifier` 字段（AX identifier）
- `Sources/AxionCLI/Planner/LLMPlanner.swift` — **主要改动**：在 `captureCurrentStateSafely` 中新增截图捕获，传给 LLM
- `Sources/AxionCLI/Planner/PromptBuilder.swift` — 可能需要调整 prompt 以引用截图
- `Prompts/planner-system.md` — **更新**：反映新参数格式（pid, window_id, __selector）
- `Tests/AxionHelperTests/` — 新增 selector 解析单元测试
- `Tests/AxionHelperTests/Mocks/MockServices.swift` — 更新 mock 以支持新方法

## Tasks & Acceptance

**Execution:**
- [x] `Sources/AxionHelper/Models/AXElement.swift` — 给 AXElement 加可选 `identifier` 字段（对应 AX identifier），确保 Codable 向后兼容
- [x] `Sources/AxionHelper/Services/AccessibilityEngine.swift` — 在 buildAXTreeInternal 中提取 AXIdentifier 属性；新增 `resolveSelector(windowId:selector:)` 方法，遍历 AX tree 匹配 role/title/title_contains/identifier/ordinal 条件并返回元素 bounds 的中心坐标
- [x] `Sources/AxionHelper/Protocols/WindowManaging.swift` — 协议加 `resolveSelector(windowId:selector:)` 方法签名
- [x] `Sources/AxionHelper/MCP/ToolRegistrar.swift` — ClickTool/DoubleClickTool/RightClickTool 加可选 `pid`/`window_id`/`__selector` 参数（selector 为嵌套结构：title?, title_contains?, ax_id?, role?, ordinal?）；当 __selector 存在时调用 AccessibilityEngine.resolveSelector 解析为坐标后执行；TypeTextTool/PressKeyTool/HotkeyTool 加可选 `pid`/`window_id`（透传但不影响底层操作）
- [x] `Sources/AxionCLI/Planner/LLMPlanner.swift` — 新增 `captureScreenshotSafely()` 方法（通过 mcpClient 调用 screenshot 工具获取 base64）；在 `captureCurrentStateSafely` 中先截图（保存为临时文件），在 `callLLMWithRetry` 中将图片路径传入 imagePaths
- [x] `Prompts/planner-system.md` — 更新工具描述：click 系列支持 `{ pid, window_id, x, y }` 或 `{ pid, window_id, __selector: { title?, title_contains?, ax_id?, role?, ordinal? } }`；type_text/press_key/hotkey 支持 `{ pid, window_id?, ... }`
- [x] `Tests/AxionHelperTests/` — 新增 `SelectorResolverTests.swift`：测试精确匹配、模糊匹配（title_contains）、ordinal 消歧、无匹配、多匹配选第一个、ax_id 匹配
- [x] `Tests/AxionHelperTests/Mocks/MockServices.swift` — MockAccessibilityEngine 加 resolveSelector 方法

**Acceptance Criteria:**
- Given ClickTool 收到 `{ pid, window_id, __selector: { title: "OK" } }`，当目标窗口 AX tree 包含 title="OK" 的 AXButton，then 返回 success=true 和实际点击坐标
- Given ClickTool 收到 `{ pid, window_id, __selector: { title: "NotExist" } }`，then 返回包含 `selector_no_match` 错误的 JSON
- Given ClickTool 收到 `{ x: 100, y: 200 }`（无 __selector），then 行为与改动前完全一致
- Given LLMPlanner 规划时有可用 windowId，then 截图以 image block 传给 LLM
- Given LLMPlanner 规划时无可用 windowId，then 只传 AX tree 文本，不阻塞
- Given `swift test --filter "AxionHelperTests"` 通过

## Spec Change Log

## Design Notes

**Selector 解析策略：** AccessibilityEngine.resolveSelector 遍历 AX tree 的所有节点（递归），对每个节点检查：
1. role 匹配（如果 selector.role 指定）
2. title 精确匹配（如果 selector.title 指定）
3. title 包含匹配（如果 selector.title_contains 指定）
4. identifier 匹配（如果 selector.ax_id 指定）
5. 所有条件 AND 组合
6. 匹配结果按出现顺序编号，ordinal 消歧（默认 0 = 第一个）
7. 返回匹配元素的 bounds 中心坐标

**Planner 截图策略：** 截图保存为临时文件（/tmp/axion-planner-{uuid}.png），LLM 调用后立即删除。LLMClientProtocol 已支持 imagePaths 参数，只需在 LLMPlanner 中填充它。

**Golden example — Click with selector:**
```json
{
  "tool": "click",
  "args": {
    "pid": 12345,
    "window_id": 37,
    "__selector": { "title": "Calculate", "role": "AXButton" }
  }
}
```
AccessibilityEngine 遍历 window 37 的 AX tree，找到 role="AXButton" title="Calculate" 的节点，取 bounds={x:100, y:200, w:80, h:30}，返回 center=(140, 215)。

## Verification

**Commands:**
- `swift test --filter "AxionHelperTests"` — expected: all tests pass
- `swift test --filter "AxionCoreTests"` — expected: all tests pass
- `swift test --filter "AxionCLITests"` — expected: all tests pass
- `swift build` — expected: zero errors, zero warnings
