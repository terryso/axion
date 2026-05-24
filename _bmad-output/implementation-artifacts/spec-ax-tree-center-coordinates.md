---
title: 'Fix calculator click regression + click_element tool'
type: 'bugfix'
created: '2026-05-22'
status: 'done'
route: 'one-shot'
---

## Intent

**Problem:** When running `axion run '帮我打开计算器计算 (10+30*20)*2'`, the LLM agent keeps clicking the same position (1101, 326) repeatedly instead of clicking different calculator buttons. The model generates all click calls in a single response with identical coordinates because it cannot correctly map button names to positions from the AX tree.

**Approach:** Two-part fix:
1. Add pre-computed `center: {x, y}` to each AX element in the tree output (reduces math burden)
2. Add a dedicated `click_element` tool that takes `window_id` + `title` and resolves coordinates automatically — the model no longer needs to do any coordinate lookup

## Code Map

- `Sources/AxionHelper/MCP/MouseTools.swift` — new `ClickElementTool` that resolves by title/role
- `Sources/AxionHelper/Models/AXElement.swift` — `ElementCenter` struct + `center` field on AXElement
- `Sources/AxionHelper/Services/AccessibilityEngine.swift` — center computation in `buildAXTreeInternal`
- `Sources/AxionCore/Constants/ToolNames.swift` — added `click_element` to tool names
- `Sources/AxionHelper/MCP/ScreenshotTools.swift` — get_accessibility_tree description mentions center
- `Prompts/planner-system.md` — recommends `click_element` as preferred approach
- `Tests/AxionHelperTests/Tools/MouseKeyboardToolTests.swift` — 2 tests for click_element
- `Tests/AxionHelperTests/Models/AXElementTests.swift` — center field assertions

## Suggested Review Order

1. [MouseTools.swift](../../Sources/AxionHelper/MCP/MouseTools.swift) — new `ClickElementTool` (lines ~52-80)
2. [AXElement.swift](../../Sources/AxionHelper/Models/AXElement.swift) — `ElementCenter` struct + `center` field
3. [AccessibilityEngine.swift](../../Sources/AxionHelper/Services/AccessibilityEngine.swift) — center computation
4. [ToolNames.swift](../../Sources/AxionCore/Constants/ToolNames.swift) — `click_element` registration
5. [planner-system.md](../../Prompts/planner-system.md) — updated element discovery guidance
6. [MouseKeyboardToolTests.swift](../../Tests/AxionHelperTests/Tools/MouseKeyboardToolTests.swift) — click_element tests
