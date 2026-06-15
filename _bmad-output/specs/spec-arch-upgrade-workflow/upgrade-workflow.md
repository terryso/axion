# Arch 升级与卸载工作流设计

## Brownfield Surface

当前功能的关键入口：

- `Sources/AxionCLI/Commands/ArchitectureCommand.swift`: `axion arch` 非交互命令，保持只读表格输出。
- `Sources/AxionCLI/Commands/ChatCommand.swift`: `/arch` slash 分支，扫描后进入交互 prompt。
- `Sources/AxionCLI/Chat/AppArchitectureSelectionPrompt.swift`: `/arch` 分页列表和只读详情页。
- `Sources/AxionCLI/Services/AppArchitecture/AppArchitectureScanService.swift`: 只读扫描 App、Homebrew、MacPorts 可执行文件架构。
- `Sources/AxionCLI/Services/AppArchitecture/AppArchitectureFormatter.swift`: 非交互表格、交互列表、详情页文本渲染。
- `Sources/AxionCLI/Services/Storage/App/AppUninstallPlanBuilder.swift`: 现有 App 卸载计划构建，负责候选 App、support 数据和风险标记。
- `Sources/AxionCLI/Services/Storage/App/AppUninstallExecutor.swift`: 现有 App 卸载执行器，负责 typed 确认后的退出 App、移入废纸篓、manifest 和 undo 语义。
- `Sources/AxionCLI/Services/Storage/Approval/StorageApprovalInput.swift`: `execute_app_uninstall` 审批归一化，bundle 卸载强制 high risk + typed confirmation。

设计原则：扫描事实、处置计划、处置执行三者分离。扫描服务不产生副作用；详情页只展示 planner 的结果；升级执行器只在用户确认后运行命令；卸载不新建第二套删除逻辑，必须桥接到现有 `/apps` 可恢复卸载链路。

## Proposed Types

```swift
enum AppArchitectureUpgradeStatus: Equatable, Sendable {
    case notChecked
    case upgradeAvailable
    case alreadyNative
    case latestButStillIntel
    case manualOnly
    case unsupported
    case unknown
    case failed(String)
}

struct AppArchitectureUpgradePlan: Equatable, Sendable {
    let status: AppArchitectureUpgradeStatus
    let source: AppArchitectureSource
    let packageIdentity: String?
    let displayCommands: [String]
    let executableCommands: [[String]]
    let requiresSudo: Bool
    let confidence: AppArchitectureUpgradeConfidence
    let postCheckPath: String?
    let notes: [String]
}

enum AppArchitectureUninstallAvailability: Equatable, Sendable {
    case unavailable(String)
    case available
}

struct AppArchitectureUninstallOption: Equatable, Sendable {
    let availability: AppArchitectureUninstallAvailability
    let appQuery: String?
    let displayName: String?
    let bundleIdentifier: String?
    let bundlePath: String?
    let searchRoots: [String]
    let notes: [String]
}

protocol AppArchitectureUpgradePlanning: Sendable {
    func plan(for item: AppArchitectureItem) async -> AppArchitectureUpgradePlan
}

protocol AppArchitectureUpgradeExecuting: Sendable {
    func execute(plan: AppArchitectureUpgradePlan) async -> AppArchitectureUpgradeResult
}

protocol AppArchitectureUninstallOptionPlanning: Sendable {
    func option(for item: AppArchitectureItem) async -> AppArchitectureUninstallOption
}

protocol ProcessLaunching: Sendable {
    func run(executable: String, arguments: [String]) async -> ProcessResult
}
```

`displayCommands` 用于渲染给用户；`executableCommands` 用数组表达可执行文件和参数，避免 shell 字符串拼接。测试中注入 `ProcessLaunching` mock。

`AppArchitectureUninstallOption` 不是执行计划本身，只是 `/arch` 详情到现有 App 卸载流程的桥接信息。真正的 support 数据发现、风险分类、typed confirmation、trash 和 undo manifest 仍由 `scan_app_uninstall` / `execute_app_uninstall` 对应服务负责。

## Detail Page UX

详情页展示：

- 名称
- 当前架构
- 类型
- 来源
- 可执行文件
- 包管理器身份
- 版本或 token（如果可得）
- 升级状态
- 将执行的命令
- 卸载状态
- 是否需要 sudo
- 置信度
- 复扫路径
- 风险说明

详情态按键：

- `u`: 对可执行计划进入确认并升级。
- `x`: 对可安全映射的 `.app` bundle 进入卸载审批流程。
- `r`: 重新扫描当前项，刷新详情。
- `o`: Finder 打开路径或 reveal 当前 bundle/bin。
- `b` 或 Left: 返回列表。
- `q`、Esc、Ctrl-C: 退出。

确认文本必须包含完整命令或完整卸载计划。单项升级可以使用 yes/no；App bundle 卸载必须使用现有 typed confirmation；未来批量升级必须使用 typed confirmation。

## Source Handling

| 来源 | 升级行为 | 卸载行为 | 说明 |
| --- | --- | --- | --- |
| Homebrew formula | 生成 `brew upgrade <formula>` 计划 | 不提供执行卸载 | formula 从 Cellar real path 提取。执行后复扫同一 real path 或重新解析 symlink。 |
| Homebrew cask | 生成 `brew upgrade --cask <token>` 计划，前提是 token 高置信 | 如果同时能映射为非系统 `.app`，可进入 `/apps` 可恢复卸载流程；不执行 `brew uninstall --cask` | token 识别失败则升级降级为 manualOnly。 |
| MacPorts | 显示 `sudo port selfupdate && sudo port upgrade <port>` 指导 | 不提供执行卸载 | MVP 不自动 sudo，也不执行 `port uninstall`。 |
| App Store | 提示使用 App Store 更新 | 不提供执行卸载 | `mas` 集成作为后续能力。 |
| Direct `.app` | 提示厂商更新；可显示 Sparkle `SUFeedURL` | 如果位于 `/Applications` 或 `~/Applications` 且非系统保护，可进入 `/apps` 可恢复卸载流程 | 不自动下载或安装。 |
| System app | 提示通过 macOS 更新处理 | 不提供执行卸载 | 不对 `/System/Applications` 执行修改。 |
| Unknown | 显示无法可靠生成升级方案 | 仅当能高置信映射为安全 App bundle 时提供，否则不提供执行卸载 | 保持只读诊断优先。 |

## Homebrew Formula Detection

输入示例：

```text
/opt/homebrew/Cellar/foo/1.2.3/bin/foo
/usr/local/Cellar/bar/4.5.6/bin/bar
```

规划逻辑：

1. 从 real path 匹配 `<prefix>/Cellar/<formula>/...`。
2. `packageIdentity = formula`。
3. `displayCommands = ["brew upgrade \(formula)"]`。
4. `postCheckPath = item.executablePath ?? item.displayPath`。
5. 执行成功后重新扫描同一项；如果 symlink 指向新版本路径，需要通过 package identity 重新定位可执行文件。

## Homebrew Cask Detection

候选来源：

- `.app` 路径位于 `/Applications`，bundle 可能由 Homebrew cask 安装。
- `/opt/homebrew/Caskroom/<token>/...`
- `/usr/local/Caskroom/<token>/...`
- `brew list --cask --versions` 输出。

MVP 只对高置信 token 生成可执行计划。低置信时显示候选和手动命令，不执行。

## Uninstall Option Planning

`/arch` 详情中的卸载入口只处理 App bundle，不处理 CLI 包或包管理器实体：

1. 读取 `AppArchitectureItem` 的 bundle 路径、bundle id、display name 或 executable 所属 `.app`。
2. 路径必须位于 `/Applications` 或 `~/Applications` 等现有 `ScanAppUninstallTool.defaultSearchRoots` 覆盖范围。
3. 系统路径、受保护路径、非 `.app`、路径不存在或无法反查 bundle id 时，返回 `unavailable(reason)`。
4. 可用时生成 `AppArchitectureUninstallOption`，携带 query、bundle path、bundle id、search roots 和用户可读说明。
5. 按 `x` 后不要直接移动文件；先调用现有 App 卸载计划构建，让用户 review support 数据候选。

显示文案必须区分“卸载/移入废纸篓”和“永久删除”。详情页可以写 `x 卸载（移入废纸篓）`，确认页必须说明可通过现有 undo manifest 恢复。

## Upgrade Execution Flow

1. 用户在详情页按 `u`。
2. Prompt 校验 plan 是否可执行。
3. 渲染确认页：
   - item 名称
   - 当前架构
   - 命令列表
   - 风险说明
   - `y` 确认，其他键取消
4. 用户确认后执行命令。
5. 显示执行中状态。
6. 命令结束后捕获 exit code、stdout 摘要、stderr 摘要。
7. 重新扫描当前 item 或同一 package identity。
8. 渲染结果：
   - before 架构
   - after 架构
   - 是否从 Intel-only 变为 universal/arm64
   - 如果仍是 Intel-only，说明包上游可能未提供 Apple Silicon 版本。

## Uninstall Execution Flow

1. 用户在详情页按 `x`。
2. Prompt 校验 uninstall option 是否可用。
3. 进入现有 App 卸载计划流程，等价于对同一 App 发起 `/apps` 卸载：
   - query / bundle id
   - search roots
   - selected app 元数据
   - mode = `uninstall_with_support_review`
4. 渲染 App 卸载计划和 support 数据候选，逐项显示完整路径和风险。
5. 用户确认要卸载 bundle 时，沿用 `execute_app_uninstall` 审批：high risk、typed confirmation 候选为 App 名称或 bundle id。
6. 执行器只做可恢复操作：
   - 如 App 正在运行，先 graceful terminate；失败则不移动 bundle。
   - bundle 和用户批准的 support 数据移入废纸篓。
   - 写入 manifest，展示 succeeded / skipped / failed 和 undo 提示。
7. 卸载后返回 `/arch` 列表或提示用户重新运行 `/arch`；不把卸载结果伪装成架构升级成功。

## Error Handling

- `brew` 不存在：plan 状态为 unsupported，显示安装或路径问题。
- command exit code 非 0：显示失败，保留 stderr 摘要，不复写为成功。
- 复扫无法找到文件：显示升级执行完成但复扫目标丢失，建议重新运行 `/arch`。
- uninstall option 不可用：详情页隐藏 `x` 或显示不可卸载原因，不进入执行。
- App 卸载计划为空：提示未找到可自动卸载候选，返回详情页。
- typed confirmation 不匹配：不执行卸载，返回详情页或卸载计划页。
- App 正在运行且无法退出：bundle 项 failed，不移动文件。
- trash 失败：显示失败原因和 manifest 摘要，不报告卸载成功。
- 用户取消：不执行命令，返回详情页。
- Ctrl-C/Esc：取消当前 prompt；如果子进程已启动，后续实现必须决定是否转发中断信号并记录结果。

## Implementation Phases

### Phase 1: Upgrade Plan in Detail

- 新增 planner protocol 和 Homebrew formula planner。
- 详情页显示 upgrade plan。
- 不执行升级，只展示计划。

### Phase 2: Homebrew Formula Execution

- 详情态支持 `u`。
- 确认后执行 `brew upgrade <formula>`。
- 执行后复扫并展示 before/after。

### Phase 3: Homebrew Cask Execution

- 增加 cask token resolver。
- 高置信 cask 支持 `brew upgrade --cask <token>`。
- 低置信 cask 降级为 manualOnly。

### Phase 4: Manual Sources and Convenience Actions

- MacPorts、App Store、direct app、system app、unknown 详情指导。
- `r` 复扫当前项。
- `o` reveal path。

### Phase 5: App Bundle Uninstall Entry

- 详情态支持 `x`。
- 新增 `/arch` 到现有 App 卸载 planner 的桥接层。
- 可卸载 App 进入 support 数据 review、typed confirmation、trash 和 undo manifest 流程。
- 不对 CLI 包、系统 App 或无法高置信映射的路径提供执行卸载。

### Phase 6: Bulk and History Follow-up

- 可选升级历史记录。
- 可选批量 Homebrew upgrade。
- 可选 `axion arch upgrade` 显式子命令。

## Test Plan

全部使用 Swift Testing。

必测：

- planner 为 Homebrew formula 生成正确 package identity、命令和 post-check path。
- planner 对 MacPorts、direct app、system app、unknown 返回 manualOnly/unsupported。
- cask resolver 对高置信 token 生成 cask plan，低置信不执行。
- prompt 在详情态按 `u` 进入确认，取消不执行。
- uninstall option planner 只对非系统 `.app` bundle 返回 available。
- prompt 在详情态按 `x` 进入 App 卸载计划，取消不执行。
- App bundle 卸载强制 typed confirmation，typed 不匹配时不调用 executor。
- App 卸载 executor 使用 mock trash performer，不调用真实废纸篓。
- executor 使用 mock process launcher，不调用真实 `brew`。
- executor 命令成功后调用 mock scanner 复扫并显示 before/after。
- executor 命令失败时保留错误并不报告修复成功。
- 非 TTY `/arch` 不进入确认、不执行升级或卸载。

默认验证命令沿用项目规则：

```bash
swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"
```
