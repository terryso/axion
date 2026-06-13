---
title: 'storage 扫描可中断 + spinner 实时耗时（storage_scan + scan_app_uninstall）'
type: 'bugfix'
created: '2026-06-13'
status: 'done'
route: 'plan-code-review'
baseline_commit: 'c911b67'
context:
  - '{project-root}/_bmad-output/project-context.md'
---

# storage 扫描可中断 + spinner 实时耗时

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 交互模式触发 `storage_scan`（如 `/storage large` 扫 `~/Downloads` 等，数十万文件 + `.totalFileSizeKey` 递归算体积 + UTI 探测）或 `scan_app_uninstall`（`AppDiscoveryService.discover()` 遍历 `/Applications` 逐 `.app` `totalFileSizeKey`）时，工具 spinner 的实时耗时永远卡在 `0.0s`，且 Esc/Ctrl+C 无法中断，只能干等。

**根因（同一种 Swift 并发反模式，两处）：** 两个扫描器的 `async` 入口内部都是**纯同步紧密循环、无 suspension point、无 `Task.isCancelled` 检查**。
- **spinner 卡 0.0s**：scan 占满一个 cooperative worker 不释放 → 持续饱和核心饿死 spinner 的 GCD 定时器线程（`SpinnerRenderer` 已把 QoS 提到 `.userInitiated` 但只是缓解；是否还需硬化待实测）。
- **不可中断**：Esc/Ctrl+C 经 agent streaming 段已存活的 `EscapeInterruptListener` → `currentAgent.interrupt()` → SDK `_streamTask.cancel()`（`Agent.swift:485`）→ `Task.isCancelled` 在 tool `call()`/scan 内为真（已验证 `tool.call()` 内联 `await` 于 `_streamTask`，`ToolExecutor.swift:197`）。但 scan 从不观察取消，跑完才结束。

**Approach:** 把两个扫描器的同步枚举提升为真正 cooperative 的 `async`：每 N 项 `try Task.checkCancellation()`（抛 `CancellationError`）+ `await Task.yield()`（释放 worker，给 spinner 调度窗口）。两个工具的 `call()` 用 `do/catch` 区分 `is CancellationError`（返回最小结果，turn 以 `.cancelled` 结束）与其他错误。`SupportDataScanService` 是快速键控探测，**不改**。

## Boundaries & Constraints

**Always:**
- 复用 agent streaming 段已存活的 `EscapeInterruptListener` 与 `agent.interrupt()` → `_streamTask.cancel()` 路径；不新增监听器、不包额外 `Task`。
- 取消走「抛 `CancellationError`」语义；`call()` 专门 catch 它（不混入 scan_failed / discover_failed）。
- 扫描/发现/卸载计划语义不变（排除规则、bundle 折叠、大文件降序、多候选阻断、证据分级、风险映射）。
- 只读、无副作用；仅读取元数据。

**Ask First:**
- **先实测**：动手前先在 baseline (`c911b67`) 构建上跑 `/storage large`，确认 spinner 是否真还卡 `0.0s`（`.userInitiated` 修复已在仓库，可能已生效或仍失效）。若 yield 落地后实测 spinner 仍卡顿，**HALT 并提议**是否硬化 `SpinnerRenderer`（GCD 定时器 → 独立 `Thread`，触及 thinking+tool 共享组件）。

**Never:**
- 不改 `ScanResult` / `AppUninstallPlan` / `AppCandidate` 等返回契约字段。
- 不改 `SupportDataScanService`（快速键控探测，非问题源）。
- 不放宽 `~/Library` 通用排除规则（Epic 39 红线）；`SupportDataScanService` 仍用 bundle-id 精确探测。
- 不引入真实删除/移动/sudo。

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|---------------|----------------------------|----------------|
| storage_scan 中按 Esc | 执行中、TTY | 立即停、spinner 消失、turn `.cancelled`（警告抑制）、回提示符 | N/A |
| storage_scan 中按 Ctrl+C | 同上（ISIG 关→`0x03` 同监听器） | 同上，REPL 中断计数/双击退出状态机不受影响 | N/A |
| scan_app_uninstall 中按 Esc/Ctrl+C | discover 遍历中 | 同上立即停 | N/A |
| 观察实时耗时 | 多目录大扫描、TTY | 耗时按 ~100ms 持续递增，不再冻结 | N/A |
| 非 TTY / pipe | 非 TTY | 无 spinner 控制字符；结果与 checkpoint 开销可忽略 | N/A |
| 取消后重试 | 一次取消后再触发 | 正常完整扫描，结果正确 | N/A |

</frozen-after-approval>

## Code Map

- `Sources/AxionCLI/Services/Storage/StorageScanService.swift` — `scan(_:)` 协作化：逐根枚举循环迁入 `async`，每 N（约 512）文件 `try Task.checkCancellation()` + `await Task.yield()`，每 root 起始再 `try Task.checkCancellation()`；`makeSignal`/`makeGroups`/`directoryContentSize` 等纯 helper 不变（`directoryContentSize` 起始加一处 `Task.isCancelled` 早退）。
- `Sources/AxionCLI/Tools/StorageScanTool.swift` — `call()` 的 `do/catch` 区分 `catch is CancellationError`（返回最小 ok 结果）与 `catch`（scan_failed）。
- `Sources/AxionCLI/Services/Storage/App/AppDiscovering.swift` — 协议 `discover(query:searchRoots:)` 改 `async throws -> [AppCandidate]`。
- `Sources/AxionCLI/Services/Storage/App/AppDiscoveryService.swift` — `discover()` 改 `async throws`：每 app `try Task.checkCancellation()` + 每 N app `await Task.yield()`。
- `Sources/AxionCLI/Services/Storage/App/AppUninstallPlanBuilder.swift` — `build()` 改 `async throws`，`try await appDiscoverer.discover(...)` 传播 `CancellationError`；其余非抛路径不动。
- `Sources/AxionCLI/Tools/ScanAppUninstallTool.swift` — `call()` 用 `do/try await planBuilder.build(...)` 包裹，`catch is CancellationError` 返回最小结果，`catch` 返回 error 结果。
- `Sources/AxionCLI/Chat/SpinnerRenderer.swift` — （Ask First 已触发落地）动画驱动由 GCD `DispatchSourceTimer` 改为**专用 `Thread`**（`.userInteractive`，per-start `SpinnerStopFlag`），免疫 cooperative 池阻塞膨胀导致的定时器饿死。详见 Spec Change Log #1。

## Tasks & Acceptance

**Execution:**
- [x] **实测 baseline**：用户在修复（cooperative `yield`）构建上跑 `/storage large`，spinner **仍卡 `0.0s`** —— 确认 `yield` 不足以救 spinner，触发下方 Ask-First 硬化。根因修正见 Spec Change Log #1。
- [x] `StorageScanService.swift` — 枚举循环迁入 `async scanSync()`，加 `checkCancellation`（每 root + 每文件）+ 每 512 文件 `yield`；取消抛 `CancellationError`。`for ... in` 改 `while let nextObject()` 以规避 `makeIterator` 在 async 上下文不可用。
- [x] `StorageScanTool.swift` — `call()` catch `is CancellationError` → 最小 `status:"cancelled"` 结果。
- [x] `AppDiscovering.swift` + `AppDiscoveryService.swift` — `discover()` 改 `async throws` + 协作化（`checkCancellation` 每 app、每 16 候选 `yield`）。
- [x] `AppUninstallPlanBuilder.swift` — `build()` 改 `async throws` 传播取消；`MockAppDiscoverer` + `AppUninstallPlanBuilderTests`(11 函数 `async throws` + `try await`) + `AppDiscoveryTests` 同步更新。
- [x] `ScanAppUninstallTool.swift` — `call()` catch `is CancellationError` → 最小 `{"status":"cancelled"}` 结果。
- [x] 测试：新增 `scan() throws CancellationError when cancelled mid-scan`（2000 文件 + `_Concurrency.Task` + cancel 断言）与 `discover() ... CancellationError`（2000 fake `.app` 目录）。`swift build` 通过；聚焦单测 39/39 通过（含 2 新取消用例 + 全量回归）。
- [x] （条件，Ask First — 已触发并落地）spinner 实测仍卡顿 → `SpinnerRenderer` 由 `DispatchSourceTimer`（GCD `.userInitiated` 队列）改为**专用 `Thread`**（`.userInteractive`，每 start 一个 `SpinnerStopFlag`），免疫 GCD 线程池/cooperative 池阻塞膨胀。`swift build` 通过。详见 Spec Change Log #1。

**Acceptance Criteria:**
- Given TTY 扫描中（两工具），when 按 Esc 或 Ctrl+C，then spinner 立即消失、turn 以 `.cancelled` 结束、回提示符、中断计数状态机不受影响。
- Given TTY 大扫描，then spinner 耗时持续递增、不再卡 `0.0s`（实测确认）。
- Given 取消后重跑，then 排除/折叠/排序/证据分级语义不变；非 TTY 行为不变。
- Given 单测，then 两扫描器取消即抛 `CancellationError`（不阻塞到完整枚举）、未取消路径结果与改造前一致。

## Design Notes

**listener 已够用，无需包 Task：** `/apps` 走 slash 分发段（listener 未存活）故需 `_Concurrency.Task` + 临时 listener；这两个工具走 agent streaming 段，listener 在 `ChatCommand.swift:603` 已存活，ESC/Ctrl+C 已触发 `simulateFire()` + `interrupt()`，`interrupt()` 内 `_streamTask.cancel()`（`Agent.swift:485`）→ `Task.isCancelled` 在 `call()`/scan 内为真（已验证 `tool.call()` 内联 `await` 于 `_streamTask`，非 detached）。只需 scan 协作观察。

**抛 `CancellationError` 而非返回 partial：** scan 抛取消、`call()` 专门 catch 返回最小结果 → agent 拿不到半截数据、不会在被取消前先吐文本，UX 干净（优于 partial 让 agent 基于半截数据行动）。

**`scan_app_uninstall` 的慢路径是 `AppDiscoveryService`：** `SupportDataScanService` 是快速 bundle-id 键控探测（AC #13，禁止 `~/Library` 全量递归），非问题源；慢的是 `AppDiscoveryService.discover()` 遍历 `/Applications` 逐 app `totalFileSizeKey`，有界（~150 app）但同反模式。其协议 `AppDiscovering.discover` 当前非 `throws`，故需协议→实现→builder→tool 涟漪传播取消。

**yield 救 spinner 的机制（待实测确认）：** scan 紧密同步循环占满 cooperative worker 不释放，饿死 spinner 的 `.userInitiated` GCD 定时器；每 N 项 `await Task.yield()` 制造 suspension 窗口释放 worker，OS 调度器得以在 spinner 100ms 定时器触发时调度其线程。`.userInitiated` 提升优先级只是缓解；yield 才是根治——但既然 `.userInitiated` 已在仓库却仍报告卡住，必须实测确认 yield 是否足够，不够才上独立 `Thread`。

## Verification

**Commands:**
- `swift build` — 编译通过。
- `swift test --filter "AxionCLITests.Storage"` — 含两扫描器新增取消用例与回归。

**Manual checks:**
- baseline 构建 `/storage large`：先记录 spinner 现状（Ask First 输入）。
- 修复后 TTY `/storage large`：扫描中 spinner 耗时持续递增；Esc → 立即停；Ctrl+C → 立即停。
- 修复后 `scan_app_uninstall`（如 `/uninstall <app>` 或 agent 调用）：扫描中可 Esc/Ctrl+C 中断。
- 中断后重试：能正常完整扫描。

## Spec Change Log

### #1 — spinner 修复方式由「cooperative yield」改为「SpinnerRenderer 专用 Thread」

- **触发发现**：用户在 cooperative `yield` 落地后的构建上实测 `/storage large`，spinner **仍卡 `0.0s`**。`Task.yield()` 只在文件之间让步，无法在单次漫长的阻塞 `resourceValues(forKeys:[.totalFileSizeKey,...])`（目录递归求和，可达数百 ms）调用期间释放压力。
- **修正根因**：扫描里漫长的阻塞 `resourceValues` 调用在 cooperative 池上触发 Swift 阻塞检测 → cooperative 池膨胀 → GCD 无可用线程调度 spinner 的 `DispatchSourceTimer`，故仅首帧（`0.0s`）能渲染。`.userInitiated` QoS 提升与 `yield` 都治不了「GCD 线程池被耗尽」这一层。
- **改了什么**：`Sources/AxionCLI/Chat/SpinnerRenderer.swift` 把动画驱动从 GCD `DispatchSourceTimer`（serial `.userInitiated` 队列）改为**专用 `Thread`**（`.userInteractive`）。raw OS 线程由内核抢占式直接调度，不受 GCD 线程池上限 / cooperative 池阻塞检测影响。每次 `start()` 新建一个 `SpinnerStopFlag`（线程安全），旧线程持有旧 flag、stop()/下一次 start() 置位旧 flag → 旧线程自行退出，避免双线程竞态。公共 API（`start(message:delayMs:)` / `stop()`）不变；`ChatOutputFormatter` 与 `ChatCommand` 无需改。
- **避免的 known-bad 状态**：仅靠 yield/`.userInitiated` → spinner 在阻塞型工具期间冻结（用户已实测复现）。
- **KEEP**：协作式取消（`checkCancellation` + `CancellationError` + 两工具 `catch is CancellationError`）保留不变，已单测覆盖；scan 语义/排除/折叠/排序不变。**待用户在真实终端复测** spinner 是否持续递增、Esc/Ctrl+C 是否可中断。

### #2 — spinner 真正根因：`handle(.assistant)` 提前 stop（非资源饿死）

- **触发发现**：用户在 round-1/2 修复（cooperative yield + SpinnerRenderer 专用 Thread）后的 debug 构建实测，spinner 仍卡 `0.0s`。加临时诊断日志（每帧写 `/tmp/axion-spinner-debug.log`）后，真实 REPL 日志显示：`storage_scan` spinner **START 后约 1ms 即被 STOP**，随后扫描空跑 3.4s 无任何 spinner 帧。即 spinner 线程本身正常（诊断日志里 `思考中`/`Bash` 的 spinner 都持续 tick），是被**提前 stop** 了。
- **修正根因（推翻 #1 的「资源饿死」假设）**：SDK 在 yield `.toolUse`（`Agent.swift:2367`）之后，会紧接着 yield `.assistant`（`Agent.swift:2478`）——后者是 finalize「含 tool_use 的 assistant 消息」，**发生在工具真正执行之前**。而 `ChatOutputFormatter.handle(.assistant)` 无条件 `spinner.stop()`，于是工具执行 spinner 在工具还没跑时就被关掉，漫长工具调用期间无 spinner（`storage_scan` 卡首帧 `0.0s` 的真因）。专用 Thread / yield / QoS 都治不了这个——因为根本不是调度问题，是 stop 时机错误。
- **改了什么**：`Sources/AxionCLI/Chat/ChatOutputFormatter.swift` 的 `handle(.assistant)`：仅当 `toolStartTimes.isEmpty`（无正在执行的工具）时才 `spinner.stop()`。工具 spinner 的停止交回 `.toolResult` 负责。`.partialMessage` 不变（它在工具执行前到达，`toolStartTimes` 为空，停 `思考中` 正确）。
- **避免的 known-bad 状态**：任何「agent 文本 + tool_use」回合里，工具执行期间 spinner 被提前关闭（用户实测复现；`Bash` 等快速工具因执行极短未暴露，慢工具 `storage_scan`/`scan_app_uninstall` 暴露）。
- **KEEP**：`SpinnerRenderer` 专用 Thread（#1）保留——它让 spinner 在阻塞负载下稳健 tick，是正确加固；协作式取消（`checkCancellation` + `CancellationError` + 两工具 catch + ESC/Ctrl+C `[0x1B,0x03]`）全部保留。`Ctrl+C` 修复（`EscapeInterruptListener` 加 `0x03`）经用户实测已生效。
- **诊断移除**：临时 `AXION_SPINNER_DIAG` 日志已从 `SpinnerRenderer` 移除。

## Suggested Review Order

**协作式取消（核心修复 — 先看这里）**

- 扫描循环改 `while let nextObject()` + 每文件 `checkCancellation` + 每 512 文件 `yield`；规避 async 下不可用的 `makeIterator`。
  [`StorageScanService.swift:112`](../../Sources/AxionCLI/Services/Storage/StorageScanService.swift#L112)

- App 发现同样协作化：每 root + 每 app `checkCancellation`，每 16 候选 `yield`。
  [`AppDiscoveryService.swift:26`](../../Sources/AxionCLI/Services/Storage/App/AppDiscoveryService.swift#L26)

**取消传播（throws 涟漪）**

- `AppDiscovering.discover` 协议改 `async throws`，取消沿协议→实现→builder→tool 传播。
  [`AppDiscovering.swift:14`](../../Sources/AxionCLI/Services/Storage/App/AppDiscovering.swift#L14)

- `build()` 改 `async throws`，`try await discover` 透传 `CancellationError`。
  [`AppUninstallPlanBuilder.swift:29`](../../Sources/AxionCLI/Services/Storage/App/AppUninstallPlanBuilder.swift#L29)

**工具结果（取消时返回最小非 error 结果）**

- `storage_scan` 的 `call()` 专门 catch `CancellationError` → `status:"cancelled"`；turn 以 `.cancelled` 结束。
  [`StorageScanTool.swift:105`](../../Sources/AxionCLI/Tools/StorageScanTool.swift#L105)

- `scan_app_uninstall` 的 `call()` 同样 catch → `{"status":"cancelled"}`。
  [`ScanAppUninstallTool.swift:94`](../../Sources/AxionCLI/Tools/ScanAppUninstallTool.swift#L94)

**spinner 实时耗时（真正根因：`.assistant` 提前 stop，见 Spec Change Log #2）**

- `handle(.assistant)` 仅在无工具执行时停 spinner——SDK 在 `.toolUse` 后紧接 yield `.assistant`（工具尚未执行），无条件 stop 会提前关掉工具 spinner。
  [`ChatOutputFormatter.swift:134`](../../Sources/AxionCLI/Chat/ChatOutputFormatter.swift#L134)

- 动画从 GCD `DispatchSourceTimer` 换成专用 `Thread`（`.userInteractive`），免疫 cooperative 池阻塞膨胀；每 start 一个 `SpinnerStopFlag` 避免双线程竞态。
  [`SpinnerRenderer.swift:54`](../../Sources/AxionCLI/Chat/SpinnerRenderer.swift#L54)

**测试**

- `scan()` 取消即抛 `CancellationError`（2000 文件 + `_Concurrency.Task` + cancel 断言）。
  [`StorageFeatureTests.swift:91`](../../Tests/AxionCLITests/Storage/StorageFeatureTests.swift#L91)

- `discover()` 同类取消用例（2000 fake `.app` 目录）。
  [`AppDiscoveryTests.swift:98`](../../Tests/AxionCLITests/Services/AppDiscoveryTests.swift#L98)
