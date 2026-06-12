---
title: 'Support Data Full Path Table'
type: 'bugfix'
created: '2026-06-13'
status: 'done'
route: 'one-shot'
baseline_commit: '3ea0e120a6e4'
context:
  - '{project-root}/_bmad-output/project-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-39-app-uninstall-discovery-shortcut.md'
---

# Support Data Full Path Table

## Intent

**Problem:** App 卸载流程展示 Support 数据候选时，Markdown 多列表格会被终端宽度压缩，关键的 `路径` 列只显示 `~/Library/...`，用户无法判断该 support 数据是否应该删除。

**Approach:** 在流式表格 renderer 中识别 `路径`/`Path` 列；当路径列被截断时，在对应数据行下方追加一条跨表格宽度的完整路径补充行，并按目录分隔符换行。同步增强 `/apps` 卸载请求和 `scan_app_uninstall` 工具说明，要求 agent 展示完整 support path。

## Suggested Review Order

**Table Rendering**

- 识别路径列，只有路径单元格被终端宽度压缩时才追加完整路径补充行。
  [`StreamingTableRenderer.swift:314`](../../Sources/AxionCLI/Chat/StreamingTableRenderer.swift#L314)

- 完整路径补充行跨表格宽度渲染，并按 `/` 或 `\` 优先换行，避免从路径段中间硬断开。
  [`StreamingTableRenderer.swift:351`](../../Sources/AxionCLI/Chat/StreamingTableRenderer.swift#L351)

**Agent Guidance**

- `/apps` 生成的卸载请求要求逐项显示完整路径，不只依赖多列表格中的截断路径。
  [`AppListFormatter.swift:109`](../../Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift#L109)

- `scan_app_uninstall` 工具描述也要求展示完整 support path，覆盖非 `/apps` 入口。
  [`ScanAppUninstallTool.swift:18`](../../Sources/AxionCLI/Tools/ScanAppUninstallTool.swift#L18)

**Tests**

- 覆盖 7 列 support 数据表格在 80 列终端下追加完整路径补充行，并保持每行不超宽。
  [`StreamingTableRendererTests.swift:46`](../../Tests/AxionCLITests/Chat/StreamingTableRendererTests.swift#L46)

- 覆盖极窄终端下路径列被压出可显示列范围时不会越界崩溃。
  [`StreamingTableRendererTests.swift:65`](../../Tests/AxionCLITests/Chat/StreamingTableRendererTests.swift#L65)

- 覆盖 `/apps` 卸载请求和工具描述都包含完整路径展示要求。
  [`AppListServiceTests.swift:426`](../../Tests/AxionCLITests/Services/AppListServiceTests.swift#L426)
  [`ScanAppUninstallToolTests.swift:128`](../../Tests/AxionCLITests/Storage/ScanAppUninstallToolTests.swift#L128)

## Verification

- `swift test --filter StreamingTableRendererTests --filter AppListServiceTests --filter ScanAppUninstallToolTests`
- `swift test --parallel --num-workers 1 --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"`
- `grep -rl "import XCTest" Tests/ || true`
- `git diff --check`
