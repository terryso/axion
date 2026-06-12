---
title: 'Apps Picker Pagination'
type: 'bugfix'
created: '2026-06-13'
status: 'done'
route: 'one-shot'
baseline_commit: '9acfefa92a6ed36b76eca66f4ffd4a1aa54f99ae'
context:
  - '{project-root}/_bmad-output/project-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-39-app-uninstall-discovery-shortcut.md'
---

# Apps Picker Pagination

## Intent

**Problem:** `/apps` 选择器只把前 20 个候选纳入交互状态，候选更多时用户无法继续向下选择目标 App。

**Approach:** 保持每屏最多 20 条的紧凑渲染，但把选择状态改为全量候选索引，并让可视窗口随 Up/Down 自动滚动；formatter 同步显示当前区间和绝对编号。

## Suggested Review Order

**Selection Flow**

- 选择状态改为全量候选，Enter 不再受第一页限制。
  [`AppSelectionPrompt.swift:64`](../../Sources/AxionCLI/Chat/AppSelectionPrompt.swift#L64)

- Down 越过窗口底部时推进可视窗口。
  [`AppSelectionPrompt.swift:82`](../../Sources/AxionCLI/Chat/AppSelectionPrompt.swift#L82)

- Redraw 传入窗口起点，保持物理行清理逻辑不变。
  [`AppSelectionPrompt.swift:108`](../../Sources/AxionCLI/Chat/AppSelectionPrompt.swift#L108)

**Rendering**

- Formatter 接受窗口起点并只渲染当前页。
  [`AppListFormatter.swift:6`](../../Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift#L6)

- 显示绝对编号和当前区间，解释如何继续浏览。
  [`AppListFormatter.swift:34`](../../Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift#L34)

- 标题从“前 N 个”改为当前区间。
  [`AppListFormatter.swift:90`](../../Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift#L90)

**Tests**

- 选择器覆盖下移到第 21 个候选并选中。
  [`AppSelectionPromptTests.swift:59`](../../Tests/AxionCLITests/Chat/AppSelectionPromptTests.swift#L59)

- Formatter 覆盖区间显示和绝对编号。
  [`AppListServiceTests.swift:206`](../../Tests/AxionCLITests/Services/AppListServiceTests.swift#L206)
