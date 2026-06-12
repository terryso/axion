---
title: 'Apps List Hide Path'
type: 'bugfix'
created: '2026-06-13'
status: 'done'
route: 'one-shot'
baseline_commit: '6244165997798fbe09782110b464cbeeb459e29c'
context:
  - '{project-root}/_bmad-output/project-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-apps-list-size-column.md'
---

# Apps List Hide Path

## Intent

**Problem:** `/apps` 列表每个候选都显示 `path:` 行，占用空间并把应在详情页判断的信息提前铺在列表里。

**Approach:** 列表只保留名称、Bundle ID、版本、大小、状态、来源；路径继续保留在 App 详情页，进入详情后再查看。

## Suggested Review Order

**Rendering**

- 候选列表只渲染一行概要，不再追加 path 行。
  [`AppListFormatter.swift:35`](../../Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift#L35)

- 受保护匹配项同样去掉路径，保持列表语义一致。
  [`AppListFormatter.swift:49`](../../Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift#L49)

- 详情页继续显示路径，保留卸载前判断入口。
  [`AppListFormatter.swift:71`](../../Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift#L71)

**Tests**

- Protected 匹配列表断言不再泄漏 app 路径。
  [`AppListServiceTests.swift:174`](../../Tests/AxionCLITests/Services/AppListServiceTests.swift#L174)

- Candidate 列表断言保留大小列但不显示路径。
  [`AppListServiceTests.swift:199`](../../Tests/AxionCLITests/Services/AppListServiceTests.swift#L199)
