---
title: '/apps 扫描可中断（Esc/Ctrl+C）'
type: 'bugfix'
created: '2026-06-13'
status: 'done'
route: 'plan-code-review'
baseline_commit: '7ce1844d7d9ea00ea2cd9c7f4a1c0fac6aa93a94'
context:
  - '{project-root}/_bmad-output/project-context.md'
---

# /apps 扫描可中断（Esc / Ctrl+C）

## Intent

**Problem:** 交互模式输入 `/apps` 后扫描本地 App 期间（fast ~1–3s、deep 更久），spinner 在转却无法用 Esc 或 Ctrl+C 中断——只能干等扫描自然结束。

**根因（两路独立失效）：**
- **Esc**：`EscapeInterruptListener` 只在 agent streaming 段（`ChatCommand.swift:568` 建、665 销）存活；`/apps` 走 slash 分发段（331），扫描期间无任何 stdin reader，Esc 字节进缓冲区被吞。
- **Ctrl+C**：被 `SignalHandler`（164）的 DispatchSource 捕获并 `currentAgent.interrupt()`，但扫描期间 agent 空闲、interrupt 空转；而 `AppListService.list()`（`AppListService.swift:84`）从头到尾不检查 `Task.isCancelled`，阻塞到自然结束，回到循环顶部 `reset()`（223）把这次 fireCount 清零 → Ctrl+C 被吃掉。

**Approach:**
1. `AppListService.list()` 加协作式取消检查点（spotlight/homebrew await 前 + for 循环每轮），取消时返回已收集的 partial 结果。
2. `listAppsForSlash` 把扫描包进 `_Concurrency.Task`（注：`OpenAgentSDK` 导出的 `Task` struct 遮蔽了 `_Concurrency.Task`，须全限定），并启动 `EscapeInterruptListener`，任一中断字节即 `scanTask.cancel()`。
3. raw mode 关闭 ISIG 后 Ctrl+C 不再产生 SIGINT、而作为 `0x03` 字节进入 stdin → 与 Esc(`0x1B`) 由同一监听器统一捕获，不经 SignalHandler 故不污染 REPL 的中断计数/双击退出状态机。

## Code Map

- `Sources/AxionCLI/Services/Storage/App/AppListService.swift` — `list()` 加取消检查点（95/99/119 行）；新增 private `finish(...)`（158 行）复用结果构造。
- `Sources/AxionCLI/Chat/EscapeInterruptListener.swift` — `init` 增加可配置 `interruptBytes`（默认 `[0x1B]`，agent 路径行为不变）；扫描场景传 `[0x1B, 0x03]`。
- `Sources/AxionCLI/Commands/ChatCommand.swift` — `listAppsForSlash` 返回 `AppListResult?`（nil=被取消），包 `_Concurrency.Task` + 监听器（835 行）；`handleAppsSlash` 两处调用点 `guard let … else { return nil }`。

## Tasks & Acceptance

**Execution:**
- [x] `EscapeInterruptListener`：加 `interruptBytes: Set<UInt8> = [0x1B]` 参数 + 属性，`startPollingTask` capture 并把 `byte == 0x1B` 改为 `interruptBytes.contains(byte)`。
- [x] `AppListService.list()`：spotlight await 前、homebrew await 前各加 `if Task.isCancelled { return Self.finish(…) }`；for 循环每轮开头 `if Task.isCancelled { break }`。
- [x] `listAppsForSlash`：改返回 `AppListResult?`；`_Concurrency.Task { await service.list(…) }` + `EscapeInterruptListener(onEscape: { scanTask.cancel() }, interruptBytes: [0x1B, 0x03])`；`defer` 先 `listener.cancel()`（恢复 termios+tcflush）后 `spinner.stop()`；`scanTask.isCancelled` 时 return nil。
- [x] `handleAppsSlash`：首次扫描 + deep 二次扫描两处 `guard let … else { return nil }`。

**Acceptance Criteria:**
- Given TTY 扫描中，when 按 Esc 或 Ctrl+C，then spinner 立即消失、回到输入提示符、不进入选择列表。
- Given `/apps --all` 深度搜索中断，then 不残留 spinner 字符、termios 恢复、下一次输入正常。
- Given 非 TTY / 管道，then 无 spinner 控制字符、行为不变（监听器 raw mode 仅在 TTY 生效）。
- Given 中断后，then REPL 的中断计数/双击退出状态机不受影响（中断不经 SignalHandler）。

## Design Notes

**为什么 raw mode 下 Ctrl+C 变 0x03：** `EscapeInterruptListener.applyRawMode` 关闭 `ISIG`（`c_lflag &= ~ISIG`）后，内核不再把 Ctrl+C 翻译成 SIGINT，而是把 `0x03` 作为普通字节投递到 stdin。因此扫描期间 Ctrl+C 不触发 `SignalHandler`，而是被监听器轮询读到——与 Esc 走同一条中断路径。监听器 `cancel()` 时 `tcsetattr(TCSAFLUSH)` 恢复 termios 并冲掉残留字节，ISIG 随之恢复，下一次 Ctrl+C 回到正常 SIGINT 语义。

**defer 顺序：** `defer { spinner.stop() }` 先注册（后执行）、`defer { listener.cancel() }` 后注册（先执行）。退出时先恢复 termios+tcflush（清掉用户按下的中断字节残留），再 stop spinner 清行。两者输出均走 stderr、OPOST 始终保留，顺序对正确性无影响，仅为语义清晰。

**partial 结果被丢弃：** `list()` 取消时返回已收集的 partial 候选，但 `listAppsForSlash` 检测 `scanTask.isCancelled` 后直接 return nil 丢弃——调用方语义是"取消=放弃本次扫描回提示符"，partial 仅供 list() 自身能快速 break 返回（而非阻塞到自然结束）。

**OpenAgentSDK.Task 遮蔽：** `import OpenAgentSDK` 引入 `public struct Task: Codable`（非泛型），遮蔽 `_Concurrency.Task`。裸 `Task { }` 会被解析为该 struct 的 `init(from decoder:)` → 报 "trailing closure passed to parameter of type 'any Decoder'"。必须用 `_Concurrency.Task` 全限定（linter 会自动补此前缀）。

## Verification

**Commands:**
- `swift build` — 编译通过。
- `swift test --filter "AppListServiceTests"` — 17/17 通过，含新增 `list cooperatively cancels mid-scan, returning a partial result`。

**Manual checks:**
- TTY `axion` → `/apps`：扫描中按 Esc → spinner 消失、回提示符。
- TTY `axion` → `/apps --all`：深度搜索中按 Ctrl+C → 同上，且后续 Ctrl+C 行为正常。
- 中断后再 `/apps`：能正常重新扫描。

## Suggested Review Order

- 扫描包进可取消 Task + 接入监听器（Esc/Ctrl+C 统一捕获）。
  [`ChatCommand.swift:835`](../../Sources/AxionCLI/Commands/ChatCommand.swift#L835)

- `list()` 协作式取消检查点（spotlight/homebrew/for 每轮）。
  [`AppListService.swift:95`](../../Sources/AxionCLI/Services/Storage/App/AppListService.swift#L95)

- 监听器可配置中断字节（默认 `[0x1B]` 不改 agent 路径）。
  [`EscapeInterruptListener.swift:43`](../../Sources/AxionCLI/Chat/EscapeInterruptListener.swift#L43)
