---
title: 'Apps Picker Agent Analysis Cache'
type: 'feature'
created: '2026-06-13'
status: 'done'
route: 'one-shot'
baseline_commit: '8a5b7c077da1df76b262a0eb954777426671e234'
context:
  - '{project-root}/_bmad-output/project-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-39-app-uninstall-discovery-shortcut.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-apps-picker-detail-confirmation.md'
---

# Apps Picker Agent Analysis Cache

## Intent

**Problem:** `/apps` 详情页只有 Bundle ID、路径、版本等基础字段，用户仍然需要自己判断 App 是什么、主要用途是什么，尤其在卸载前决策信息不足。

**Approach:** 详情页第一次打开时保留基础信息，同时显示 Agent 分析中状态；如果本地没有分析缓存，则用受限的一轮 Agent 根据 App 元数据和公开常识生成用途摘要，并缓存到本地。下次进入同一 App 详情时优先读取缓存，避免重复分析。

## Suggested Review Order

**Detail Analysis Service**

- 定义 App 详情补充信息、Agent 分析结果和分析状态。
  [`AppDetailAnalysisService.swift:6`](../../Sources/AxionCLI/Services/Storage/App/AppDetailAnalysisService.swift#L6)

- 读取本地最后打开时间/添加时间；缓存命中直接返回，未命中才调用 Agent 并保存结果。
  [`AppDetailAnalysisService.swift:83`](../../Sources/AxionCLI/Services/Storage/App/AppDetailAnalysisService.swift#L83)

- Agent 只运行一轮、无工具、要求严格 JSON；流式 partial/final/result 分开收集，避免重复拼接破坏 JSON。
  [`AppDetailAnalysisService.swift:154`](../../Sources/AxionCLI/Services/Storage/App/AppDetailAnalysisService.swift#L154)

- 分析缓存按 App Bundle ID 和路径落到 `~/.axion/app-analysis/`，缓存失败不阻塞选择器。
  [`AppDetailAnalysisService.swift:263`](../../Sources/AxionCLI/Services/Storage/App/AppDetailAnalysisService.swift#L263)

**Picker Flow**

- `/apps` 入口注入 `AppDetailAnalysisService`，列表逻辑仍然只负责选择 App。
  [`ChatCommand.swift:781`](../../Sources/AxionCLI/Commands/ChatCommand.swift#L781)

- 列表 Enter 先渲染基础详情和“Agent 分析中”，分析完成后原地刷新详情；详情页 Enter 才进入卸载扫描/审批流程。
  [`AppSelectionPrompt.swift:98`](../../Sources/AxionCLI/Chat/AppSelectionPrompt.swift#L98)

**Detail Rendering**

- 详情页保留基础字段，并新增最后打开、添加时间、Agent 分析结果、缓存/新生成状态和失败提示。
  [`AppListFormatter.swift:71`](../../Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift#L71)

**Tests**

- 覆盖详情页先显示分析中，再显示 Agent 分析结果。
  [`AppSelectionPromptTests.swift:72`](../../Tests/AxionCLITests/Chat/AppSelectionPromptTests.swift#L72)

- 覆盖 JSON 解析、缓存命中优先、首次生成后写入缓存。
  [`AppListServiceTests.swift:288`](../../Tests/AxionCLITests/Services/AppListServiceTests.swift#L288)

## Verification

- `swift test --filter AppSelectionPromptTests --filter AppListServiceTests --filter SlashCommandAppsTests`
- `swift test --parallel --num-workers 1 --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"`
- `grep -rl "import XCTest" Tests/ || true`
- `git diff --check`
