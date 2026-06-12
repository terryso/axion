---
title: 'Apps Picker Detail Confirmation'
type: 'bugfix'
created: '2026-06-13'
status: 'done'
route: 'one-shot'
baseline_commit: 'e9407403638ea498ce706cb3ec75f85f6a485ad7'
context:
  - '{project-root}/_bmad-output/project-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-39-app-uninstall-discovery-shortcut.md'
---

# Apps Picker Detail Confirmation

## Intent

**Problem:** `/apps` 列表中按 Enter 会立即进入卸载流程，用户没有机会先查看 App 元数据并判断这个 App 大概是什么。

**Approach:** 将列表 Enter 改为打开 App 详情页，展示名称、Bundle ID、版本、大小、运行状态、来源、路径和本地用途线索；详情页里再次 Enter 才继续进入既有扫描/审批卸载流程，`b` 或左方向键返回列表。

## Suggested Review Order

**Interaction State**

- 列表 Enter 只进入详情状态，不再直接选择 App。
  [`AppSelectionPrompt.swift:91`](../../Sources/AxionCLI/Chat/AppSelectionPrompt.swift#L91)

- 详情页 Enter 才返回 selected 给后续 agent 流程。
  [`AppSelectionPrompt.swift:95`](../../Sources/AxionCLI/Chat/AppSelectionPrompt.swift#L95)

- 详情页支持返回列表，保留原选择和分页窗口。
  [`AppSelectionPrompt.swift:102`](../../Sources/AxionCLI/Chat/AppSelectionPrompt.swift#L102)

**Detail Rendering**

- 列表主操作文案改成 Enter 详情。
  [`AppListFormatter.swift:26`](../../Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift#L26)

- 详情页展示本地元数据和安全提示。
  [`AppListFormatter.swift:71`](../../Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift#L71)

- 用 Bundle ID 提供有限的厂商/产品线索。
  [`AppListFormatter.swift:155`](../../Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift#L155)

**Tests**

- 覆盖列表 Enter 只打开详情、不选择。
  [`AppSelectionPromptTests.swift:39`](../../Tests/AxionCLITests/Chat/AppSelectionPromptTests.swift#L39)

- 覆盖详情页确认、分页选择和返回列表。
  [`AppSelectionPromptTests.swift:60`](../../Tests/AxionCLITests/Chat/AppSelectionPromptTests.swift#L60)

- 覆盖详情页字段、用途线索和安全提示。
  [`AppListServiceTests.swift:243`](../../Tests/AxionCLITests/Services/AppListServiceTests.swift#L243)
