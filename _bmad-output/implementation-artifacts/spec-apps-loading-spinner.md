---
title: '/apps 扫描加载提示'
type: 'feature'
created: '2026-06-13'
status: 'done'
baseline_commit: '7ce1844d7d9ea00ea2cd9c7f4a1c0fac6aa93a94'
context:
  - '{project-root}/_bmad-output/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 交互模式输入 `/apps` 后，扫描本地 App（读每个 `.app` 的 bundle 元数据 + 递归算体积）通常要 1–3 秒；默认快速搜索期间终端无任何反馈，用户以为卡住。只有 `--all` 深度搜索有一行静态文本，也没有动画。

**Approach:** 在 `listAppsForSlash` 调用 `service.list(...)` 期间，复用既有 `SpinnerRenderer`（与"思考中"同一组件）显示带实时耗时的 spinner；扫描结束立即 `stop()` 清行，再交由 `AppSelectionPrompt` 渲染列表。

## Boundaries & Constraints

**Always:**
- 复用 `SpinnerRenderer`，不得自建 spinner / 动画实现。
- `service.list(...)` 返回后必须**先** `spinner.stop()`、再写任何后续输出（含 deep 完成摘要），避免动画帧与摘要串行写同一 `\r` 行导致错位。
- 非 TTY 静默跳过（SpinnerRenderer 既有行为）；pipe / list-only 模式行为不变。

**Ask First:** （无）

**Never:**
- 不改 `AppListService.list()` 本身（性能优化、异步化另开 spec）。
- 不在非 TTY 强制输出 spinner 控制字符。
- 不动 `/apps` 参数解析与 `AppSelectionPrompt` 交互逻辑；不改 deep 完成摘要文案（候选数 + 用时 + warnings 保持现状）。

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|---------------|----------------------------|----------------|
| 默认 `/apps`（TTY） | fast 扫描 ~1–3s | spinner `⏳ 正在扫描 App 1.2s ⠙` 实时刷新；完成后清行，列表出现 | N/A |
| `/apps --all`（TTY） | deep 扫描 | spinner `正在深度搜索 App`；stop 后打印既有完成摘要（候选数 + 用时 + warnings） | warnings 计入提示 |
| 秒级完成（TTY） | fast 扫描 <200ms | 因 delayMs=200 不显示 spinner，无闪烁 | N/A |
| 非 TTY / pipe | list-only | 不显示 spinner；deep 仍打印完成摘要 | N/A |

</frozen-after-approval>

## Code Map

- `Sources/AxionCLI/Commands/ChatCommand.swift` -- `listAppsForSlash(service:filter:scope:)`（私有，注入 `AppListing`）是 spinner 包裹点；含 deep 的起始 fputs 与完成摘要 fputs。
- `Sources/AxionCLI/Chat/SpinnerRenderer.swift` -- 既有 spinner：`start(message:delayMs:)` / `stop()`，非 TTY 自跳过，`stop()` 可安全重复调用。
- `Sources/AxionCLI/Chat/ChatOutputFormatter.swift:68` -- `startLLMWaiting()` 参考用法（message + delayMs 模式）。
- `Sources/AxionCLI/Services/Storage/App/AppListService.swift` -- `list()` 即耗时扫描源（**不修改**）。

## Tasks & Acceptance

**Execution:**
- [x] `Sources/AxionCLI/Commands/ChatCommand.swift` -- 删除 deep 的起始 fputs（`正在执行 App 深度搜索...`），改为在 `listAppsForSlash` 开头创建 `SpinnerRenderer` 并 `start(message:delayMs:)`：fast 用 `正在扫描 App` / `delayMs: 200`，deep 用 `正在深度搜索 App` / `delayMs: 0`。
- [x] `Sources/AxionCLI/Commands/ChatCommand.swift` -- `service.list(...)` 返回后**立即** `spinner.stop()`（清行），再保留既有 deep 完成摘要 fputs 不变；可叠加 `defer { spinner.stop() }` 作安全网（`stop()` 幂等）。
- [x] 确认 `Tests/AxionCLITests/Chat/SlashCommandAppsTests.swift` 与 `Tests/AxionCLITests/Services/AppListServiceTests.swift` 仍通过（无对起始消息的断言，预期不受影响）。

**Acceptance Criteria:**
- Given 交互 TTY 模式，when 输入 `/apps`，then 扫描期间显示带实时耗时的 spinner，扫描结束后 spinner 清行、列表正常出现、无光标错位。
- Given `/apps --all`，when 扫描完成，then 打印既有完成摘要（候选数 + 用时 + warnings），且无残留 spinner 字符。
- Given 非 TTY / 管道，when `/apps`，then 不输出任何 spinner 控制字符（list-only 行为不变）。

## Design Notes

**stop 顺序为何关键：** spinner 动画每帧用 `\r` 回到行首覆写。若 `service.list()` 返回后不先 `stop()` 就 `fputs` 完成摘要，摘要会写在当前行（光标停在最后一帧之后），与下一帧 `\r` 覆写交错，产生错位/残影。故必须 `list()` 返回后先 `stop()` 清行，再写摘要或交还控制权给 `AppSelectionPrompt`（其用 ANSI 上移/清屏码管理行，spinner 已清故不冲突）。

**delayMs 取值：** fast=200（秒级扫描不闪烁、真·慢扫描 200ms 内出反馈）；deep=0（深度搜索恒慢，立即显示）。

## Verification

**Commands:**
- `make test` -- 单元测试通过（含 `SlashCommandAppsTests` / `AppListServiceTests`）。
- `swift build` -- 编译通过。

**Manual checks:**
- 终端运行 `axion` → `/apps`：扫描期间见 spinner，列表出现后无光标错乱。
- `/apps --all`：见 spinner + 完成摘要。
- `echo "/apps" | axion`（非 TTY）：无 spinner 控制字符泄漏，仅列表/摘要。

## Suggested Review Order

- 扫描期间复用 SpinnerRenderer 显示带实时耗时的加载提示，fast 200ms 延迟避免闪烁、deep 立即显示。
  [`ChatCommand.swift:818`](../../Sources/AxionCLI/Commands/ChatCommand.swift#L818)

- `service.list()` 返回后立即 `stop()` 清行，再写 deep 完成摘要——避免动画 `\r` 帧与摘要交错。
  [`ChatCommand.swift:829`](../../Sources/AxionCLI/Commands/ChatCommand.swift#L829)

- deep 完成摘要（候选数 + 用时 + warnings）文案与行为保持不变，仅删掉了旧的起始静态行。
  [`ChatCommand.swift:834`](../../Sources/AxionCLI/Commands/ChatCommand.swift#L834)

- 复用的既有 spinner 组件：`start(message:delayMs:)` 非 TTY 静默、`stop()` 幂等清行。
  [`SpinnerRenderer.swift:39`](../../Sources/AxionCLI/Chat/SpinnerRenderer.swift#L39)
