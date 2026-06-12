---
title: 'Epic 39 App 卸载候选快捷发现'
type: 'feature'
created: '2026-06-13'
status: 'done'
baseline_commit: '76e47b9b5f4bb9482da1f43fc43d9d7e6398d8d0'
context:
  - '{project-root}/_bmad-output/project-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/39-3-app-uninstall-support-data-scan.md'
  - '{project-root}/_bmad-output/implementation-artifacts/39-4-multi-surface-approval-adaptation.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Epic 39 已支持 App 卸载，但用户要先用自然语言让 agent 查当前装了哪些 App，才能决定卸载目标；这个路径慢、不可发现，也会浪费一次 agent turn。用户需要一个更直接的本地入口来搜索、浏览、选择 App，并从选中项进入卸载流程。

**Approach:** 在交互模式新增 `/apps [filter]` 交互选择器：先快速枚举 `/Applications` 与 `~/Applications`，并提供显式深度搜索（如 `/apps --all` 或选择器内按 `a`）查找 Spotlight 可见的 `.app` bundle，并补充探测 Homebrew Cask 常见位置。用户用 Up/Down 选中 App 后按 Enter 进入卸载流程；选择器只生成带 display name、bundle id、bundle path 的精确卸载请求，真正的 support 扫描、审批与执行仍走既有 `scan_app_uninstall` → approval gate → `execute_app_uninstall` 安全链路。

## Boundaries & Constraints

**Always:** 默认先做快速搜索，搜索根复用 `ScanAppUninstallTool.defaultSearchRoots`；深度搜索必须由用户显式触发，走可注入的 Spotlight/metadata provider 加 Homebrew Cask provider（不是原始递归扫整个文件系统），设置超时并显示忙碌/耗时提示；Homebrew Cask provider 至少探测 `/opt/homebrew/Caskroom`、`/usr/local/Caskroom`、以及环境可得的 Homebrew prefix 下 `Caskroom`，递归深度限定在 cask/version/app bundle 层级；结果按规范化路径去重；输出包含 App 名、bundle id、版本、大小、运行状态、路径；系统保护 App 不作为可自动卸载候选，若被过滤命中则以“受保护/不可自动卸载”说明；命令进入 slash popup 和 `/help`；busy 时不可用，避免与 agent turn 并发抢占终端；非 TTY 时降级为编号列表和文字提示，不进入 Up/Down raw-mode 选择器。

**Ask First:** 如果要让选择器直接调用 `execute_app_uninstall`、在未进入既有审批 gate 前移动任何文件、扫描所有 App 的 support 数据、或新增顶层 CLI 命令（如 `axion apps list`），先停下确认。

**Never:** 不在选择器内直接调用 `execute_app_uninstall`、`execute_storage_plan` 或任何有副作用工具；不使用 sudo、pkgutil、brew、vendor uninstaller；不递归扫描 `/` 或 `~/Library`；不修改 AxionHelper；不把系统/Apple/MDM 组件标为可自动卸载；深度搜索只找 `.app` bundle 元数据，不读取用户文档内容。

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Interactive list | 用户在 TTY chat 输入 `/apps`；存在第三方 App | 打开选择器，按名称排序展示候选；Up/Down 移动选择，Esc 取消，Enter 选中并进入卸载请求流程 | 不触发直接文件操作 |
| Filter candidates | 用户输入 `/apps slack` | 选择器仅展示名称、bundle id 或路径包含 `slack` 的候选；大小写不敏感 | 无匹配时显示空结果，并提示可触发深度搜索 |
| Deep search | 用户输入 `/apps --all` 或在选择器内按 `a` | 用 Spotlight/metadata provider 与 Homebrew Cask provider 查找更多 `.app` bundle，结果去重后仍按安全规则分为可卸载候选/受保护项 | provider 不可用、权限不足或超时时回退快速结果并提示 |
| Homebrew cask app | App 由 Homebrew Cask 安装，链接到 `/Applications` 或留在 Caskroom | 链接到 `/Applications` 的 App 被快速搜索发现；仅在 Caskroom 的 App 被深度搜索发现，并显示实际 bundle path | Caskroom 不存在或不可读时跳过并提示深度搜索部分降级 |
| Select uninstall target | 用户在选择器中按 Enter 选中 Slack | REPL 生成精确任务文本（含 display name、bundle id、path），交给 agent 进入既有卸载扫描和审批流程 | 不直接执行卸载；后续审批拒绝时无文件副作用 |
| Protected app query | 用户输入 `/apps safari` 且只命中系统保护 App | 不显示为可自动卸载候选；显示受保护说明，可取消或继续搜索 | 不调用卸载扫描或执行 |
| Missing roots | `/Applications` 或 `~/Applications` 不存在/不可读 | 跳过不可读根，继续展示其他根的结果 | 全部不可读且深度搜索不可用时输出空结果说明 |

</frozen-after-approval>

## Code Map

- `Sources/AxionCLI/Services/Storage/App/AppDiscoveryService.swift` -- 当前 App 元数据读取与 query 匹配服务，可抽出/复用 bundle 元数据枚举逻辑。
- `Sources/AxionCLI/Tools/ScanAppUninstallTool.swift` -- 现有只读卸载扫描工具，提供默认搜索根常量和后续安全链路。
- `Sources/AxionCLI/Chat/SlashCommand.swift` -- slash 命令枚举、解析、help 文本、busy 可用性。
- `Sources/AxionCLI/Chat/SlashCommandHandler.swift` -- slash 命令格式化与同步处理；适合新增 `/apps` 纯格式化 helper。
- `Sources/AxionCLI/Commands/ChatCommand.swift` -- REPL 中对 `/resume`、`/compact` 等 async 特例的处理位置；`/apps` 应在这里调用只读服务，并在选中 App 后把生成的卸载请求作为本轮 agent task。
- `Sources/AxionCLI/Chat/Composer/KeyEventReader.swift`、`KeyEvent.swift`、`ComposerSlashPopupHandling.swift` -- 已有 raw-mode Up/Down/Enter/Esc 读取与测试注入模式，可复用到 App 选择器。
- `Sources/AxionCLI/Chat/Composer/SlashPopup.swift` -- slash popup 自动读取 `SlashCommand.allCases`，新增 command 后需校正测试预期。
- `Tests/AxionCLITests/Services/AppDiscoveryTests.swift` -- App 发现纯函数测试位置，可补充 list/filter 逻辑测试。
- `Tests/AxionCLITests/Chat/SlashCommandTests.swift`、`SlashCommandMetadataTests.swift`、`Composer/SlashPopupTests.swift` -- slash 命令数量、help、popup 过滤回归测试。

## Tasks & Acceptance

**Execution:**
- [x] `Sources/AxionCLI/Services/Storage/App/AppListService.swift` -- 新增 `AppListing` protocol、`AppListItem` 值类型、`AppSearchScope.fast/deep`，真实 `AppListService` 用注入的 app URL provider、running detector、size reader、metadata reader 隔离外部依赖；快速搜索复用默认 roots，深度搜索走 Spotlight/metadata provider + Homebrew Cask provider、超时、去重，并可被 mock。
- [x] `Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift` -- 新增纯格式化函数，支持 filter、排序、截断、空结果、受保护命中说明、深度搜索提示；避免直接 I/O。
- [x] `Sources/AxionCLI/Chat/AppSelectionPrompt.swift` -- 新增 Up/Down 选择器，复用 `KeyReading`/`KeyEventReader` 模式；返回结构化结果（`selected(AppListItem)` / `cancelled` / `requestDeepSearch` / `nonTTYListOnly`），支持 Enter 选中、Esc 取消、`a` 触发深度搜索、非 TTY 降级。
- [x] `Sources/AxionCLI/Chat/SlashCommand.swift` -- 新增 `.apps = "/apps"`，解析参数，help 文本为“列出可卸载 App 候选”，`acceptsArgs == true`，`availableDuringTask == false`。
- [x] `Sources/AxionCLI/Commands/ChatCommand.swift` -- 在内置 slash async 分支中处理 `/apps [filter|--all]`：调用 `AppListService` + `AppSelectionPrompt`；取消时 `continue`，选中时生成精确卸载请求并进入普通 agent stream。注意当前代码在 slash 处理前写历史/transcript；实现必须调整这一点，确保历史/transcript 至少记录选中后生成的卸载请求，而不是只记录 `/apps`。
- [x] `Sources/AxionCLI/Chat/SlashCommandHandler.swift` -- 如现有测试需要，暴露 `handleApps(items:filter:)` 纯 helper，保持 handler 本身不做文件系统 I/O。
- [x] `Tests/AxionCLITests/Services/AppListServiceTests.swift` -- 用临时目录伪造 `.app/Contents/Info.plist`，验证列表、过滤、系统保护排除/说明、不可读根跳过；不访问真实 `/Applications`。
- [x] `Tests/AxionCLITests/Chat/AppSelectionPromptTests.swift` -- 用 `MockKeyReader` 覆盖 Up/Down/Enter/Esc/深度搜索触发/非 TTY 降级，不读真实终端。
- [x] `Tests/AxionCLITests/Chat/SlashCommandAppsTests.swift` 和相关既有 slash/popup 测试 -- 覆盖 parse/help/metadata/popup，更新 `allCases.count` 和 popup 数量断言。

**Acceptance Criteria:**
- Given 用户在交互模式输入 `/apps`，when 当前搜索根有第三方 App，then 立即打开本地候选选择器且不触发 agent turn。
- Given 用户输入 `/apps <filter>`，when 候选名称、bundle id 或路径匹配 filter，then 只显示匹配候选，并保持大小写不敏感。
- Given 用户显式触发深度搜索，when 默认搜索根未覆盖目标 App，then 选择器可展示 Spotlight/metadata provider 找到的额外 `.app` bundle；provider 失败时保留快速结果并显示降级提示。
- Given App 由 Homebrew Cask 安装，when bundle 被链接到 `/Applications`，then `/apps` 快速搜索能显示该 App；when bundle 只存在于 Caskroom，then `/apps --all` 或选择器内深度搜索能显示该 App。
- Given 用户在选择器里用 Up/Down 选中 App 并按 Enter，when selection 返回，then chat 进入一轮普通 agent 请求，内容精确包含该 App 的 display name、bundle id 和 bundle path，并要求先扫描计划再请求确认。
- Given 过滤只命中系统保护 App，when 渲染结果，then 输出不可自动卸载说明，且不把该 App 放入可卸载候选列表。
- Given 用户之后决定卸载某个 App，when 继续用自然语言或已有工具发起卸载，then 仍必须走 `scan_app_uninstall`、审批 gate、`execute_app_uninstall`，`/apps` 不创建 manifest、不移动文件。

## Spec Change Log

## Design Notes

`/apps` 是“选择卸载目标”的入口，不是“执行卸载”的入口。Enter 选中后进入普通 agent turn，是为了让既有 `scan_app_uninstall` 生成 support 数据计划，并让 39.4 的审批 gate 继续保护真正的副作用工具。

“全盘搜索”在本 spec 中定义为 Spotlight/metadata 可见范围的 App bundle 搜索 + Homebrew Cask 常见目录探测，而不是 `FileManager.enumerator("/")` 递归扫盘。这样能覆盖大多数非标准安装位置和 Caskroom 内 App，同时避免性能、权限和隐私风险。

默认快速结果让常见 App 立即可见；深度搜索由用户按 `a` 或 `/apps --all` 明确触发，避免一次命令卡住终端或扫到大量系统/开发 bundle。推荐选择器输出保持紧凑，例如：

```text
可卸载 App 候选（24 个，显示前 20 个）  ↑/↓ 选择 · Enter 卸载 · a 深度搜索 · Esc 取消
▶ Slack                  com.tinyspeck.slackmacgap     4.38.125   342 MB   未运行
  Visual Studio Code     com.microsoft.VSCode          1.101.0    601 MB   运行中
```

## Verification

**Commands:**
- `swift test --filter AppListServiceTests` -- passed: 10 tests.
- `swift test --filter AppSelectionPromptTests` -- passed: 5 tests.
- `swift test --filter SlashCommandAppsTests` -- passed: 4 tests.
- `swift test --filter ReviewScheduler` -- passed: 21 tests after an unrelated full-suite parallel flaky failure.
- `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` -- passed: 3582 tests.
- `grep -rl "import XCTest" Tests/` -- passed: no output.

## Suggested Review Order

**Entry Flow**

- `/apps` bypasses raw history until a real uninstall request exists.
  [`ChatCommand.swift:304`](../../Sources/AxionCLI/Commands/ChatCommand.swift#L304)

- Selection, cancel, and deep-search loop stay local before agent handoff.
  [`ChatCommand.swift:781`](../../Sources/AxionCLI/Commands/ChatCommand.swift#L781)

- Deep search shows busy and elapsed-time feedback.
  [`ChatCommand.swift:802`](../../Sources/AxionCLI/Commands/ChatCommand.swift#L802)

**App Discovery**

- App listing is injectable and separates fast, Spotlight, and Homebrew sources.
  [`AppListService.swift:47`](../../Sources/AxionCLI/Services/Storage/App/AppListService.swift#L47)

- Candidate classification filters protected and managed components before selection.
  [`AppListService.swift:109`](../../Sources/AxionCLI/Services/Storage/App/AppListService.swift#L109)

- Spotlight output is drained concurrently to avoid pipe-buffer stalls.
  [`AppListService.swift:248`](../../Sources/AxionCLI/Services/Storage/App/AppListService.swift#L248)

**User-Facing Safety**

- Candidate rendering includes paths and non-TTY fallback messaging.
  [`AppListFormatter.swift:6`](../../Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift#L6)

- Generated uninstall requests use sanitized JSON with explicit search_roots.
  [`AppListFormatter.swift:59`](../../Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift#L59)

- Selector redraw uses physical line counts for narrow terminals.
  [`AppSelectionPrompt.swift:100`](../../Sources/AxionCLI/Chat/AppSelectionPrompt.swift#L100)

**Slash Surface**

- `/apps` is discoverable, accepts args, and is unavailable while busy.
  [`SlashCommand.swift:22`](../../Sources/AxionCLI/Chat/SlashCommand.swift#L22)

**Tests**

- Service tests cover filtering, Homebrew depth, symlink dedupe, sanitization, and managed protection.
  [`AppListServiceTests.swift:42`](../../Tests/AxionCLITests/Services/AppListServiceTests.swift#L42)

- Prompt tests cover Up/Down, Enter, cancel, deep trigger, and non-TTY fallback.
  [`AppSelectionPromptTests.swift:39`](../../Tests/AxionCLITests/Chat/AppSelectionPromptTests.swift#L39)

- Slash tests cover parsing, metadata, and popup discovery.
  [`SlashCommandAppsTests.swift:5`](../../Tests/AxionCLITests/Chat/SlashCommandAppsTests.swift#L5)
