---
id: SPEC-arch-upgrade-workflow
companions:
  - upgrade-workflow.md
  - ../../project-context.md
sources: []
---

> **规范合约。** 本 SPEC 及 `companions:` 中列出的文件构成完整的、经保真验证的构建、测试、验收合约。frontmatter 中列出的源文件仅用于溯源；本 spec 的代码事实和实现细节已经沉淀到 companion。

# Arch 详情升级与卸载工作流

## Why

macOS 后续版本可能移除 Rosetta 2 支持，Intel-only App 和命令行包会从“可运行但有风险”变成“无法运行”。Axion 已有 `axion arch` 和 `/arch` 能扫描风险项，但用户需要的不只是查询结果，还需要在详情页判断能否升级、看到安全的升级方案，并对不再需要的 App 执行可恢复卸载。这个工作把 `arch` 从静态审计扩展为“审计 -> 详情 -> 升级/卸载/指导 -> 复扫或可恢复处置确认”的本地、安全、可测试流程。

## Capabilities

- id: CAP-1
  intent: 用户可以在 `/arch` 交互列表中选择软件并进入架构详情，而不是按回车后退出或只看到一次性表格。
  success: 在 TTY 中输入 `/arch` 后出现分页列表；按 `Enter` 进入选中项详情；按 `b` 返回列表；按 `q`、Esc 或 Ctrl-C 退出。

- id: CAP-2
  intent: 用户可以在架构详情页看到该软件的升级可行性、卸载可行性、来源识别、推荐动作和精确命令。
  success: 详情页显示当前架构、可执行文件路径、来源、包管理器身份、升级状态、升级命令、卸载状态、是否需要 sudo、风险说明和复扫路径；无法可靠升级或卸载的来源显示手动指导而不是可执行动作。

- id: CAP-3
  intent: 用户可以从详情页对 Homebrew formula 或 Homebrew cask 执行单项升级，并在执行前明确确认。
  success: 对可识别的 Homebrew 项按 `u` 后，Axion 展示完整命令并要求确认；确认后执行升级命令；结束后重新扫描同一项并展示 before/after 架构结果。

- id: CAP-4
  intent: 用户可以对非 Homebrew 来源获得明确的处理指导，而不会触发不可靠或高风险的自动升级。
  success: MacPorts、App Store、直接下载的 `.app`、系统应用和 Unknown 项在详情页展示来源对应的建议；MVP 不自动执行 `sudo port`、App Store 更新、厂商下载或系统更新。

- id: CAP-5
  intent: 用户可以从架构详情页对可安全识别的 `.app` bundle 发起卸载，而不需要重新去 `/apps` 搜索同一个 App。
  success: 对 `/Applications` 或 `~/Applications` 下的非系统 App，详情页显示 `x 卸载`；按 `x` 后进入现有 App 卸载计划、support 数据 review、typed 二次确认、移入废纸篓和 undo manifest 流程；命令行包、系统应用、路径不可信或无法映射为 App bundle 的项目不显示可执行卸载动作。

- id: CAP-6
  intent: 脚本和非交互场景继续获得稳定的只读查询输出。
  success: `axion arch` 保持当前表格输出；非 TTY `/arch` 只输出编号列表或只读结果，不进入选择器，不执行升级或卸载，不阻塞等待按键。

- id: CAP-7
  intent: 升级和卸载执行过程可取消、可诊断，并且不会隐藏副作用。
  success: 扫描和详情选择支持 Esc/Ctrl-C 取消；升级命令失败时显示退出码和 stderr 摘要；卸载失败时显示被拒绝或失败的具体原因；任何 sudo、重装、批量升级、永久删除或 support 数据静默清理行为都不会发生。

- id: CAP-8
  intent: 升级计划、卸载入口和执行分支可以用单元测试验证，不依赖真实 Homebrew、MacPorts、App Store、网络、废纸篓或系统权限。
  success: Swift Testing 单元测试通过 mock process launcher、mock app uninstall planner/executor、mock trash performer、临时路径和扫描 fixtures 覆盖计划生成、确认流程、命令执行、错误处理、复扫结果和卸载拒绝路径。

## Constraints

- 必须保持 `axion arch` 默认只读、脚本友好；升级和卸载能力只从交互详情页或未来显式子命令进入。
- 必须复用现有 `/apps`、`/mcp` 风格的分页列表、详情页、Esc/Ctrl-C 取消、非 TTY fallback 模式。
- 扫描器必须保持只读；升级规划和执行必须拆到独立 protocol，不能把副作用放进 `AppArchitectureScanService`。
- 自动升级 MVP 只覆盖可高置信识别的 Homebrew formula 和 Homebrew cask。
- 卸载必须复用现有 `/apps` App 卸载计划、审批、typed confirmation、trash 和 undo manifest 链路；不得在 `/arch` 内实现第二套永久删除或无审批卸载器。
- 可执行卸载只覆盖可映射为非系统 `.app` bundle 的项目；Homebrew formula、MacPorts port、CLI 可执行文件、系统应用、路径不可信项目只展示指导，不提供卸载执行键。
- 执行前必须展示完整命令或完整卸载计划并要求确认；批量升级、sudo、重装、永久删除、厂商下载安装和 support 数据静默清理不在 MVP 自动执行范围内。
- 执行后必须重新扫描同一目标；不能只以包管理器命令成功作为“已修复”结论。
- 卸载后必须展示可恢复结果和 undo 提示；不能把“移入废纸篓”描述成不可逆删除。
- 单元测试必须使用 Swift Testing；禁止测试调用真实 `brew`、`port`、`mas`、网络、桌面通知、系统废纸篓或系统权限流程。
- 开发完成后的默认验证只运行项目定义的单元测试范围，不运行 `Tests/**/Integration/` 或 `Tests/**/AxionE2ETests/`。

## Non-goals

- 不实现通用软件更新中心或系统级包管理器。
- 不在 MVP 中实现“一键升级所有 Intel-only 项”。
- 不自动升级 MacPorts、App Store、直接下载 `.app`、系统应用或 Unknown 来源。
- 不自动下载厂商安装包、不解析网页、不执行重装或永久删除。
- 不在 `/arch` 中实现命令行包卸载、`brew uninstall`、`port uninstall`、`mas uninstall` 或系统 App 移除。
- 不绕过现有 `/apps` 卸载审批、support 数据 review、typed confirmation 和 undo manifest。
- 不把 LLM 决策作为升级命令生成来源；升级计划必须来自本地确定性规则。
- 不改变 `arch` 现有扫描范围、默认 Intel-only 过滤和 `--all`、`--system`、`--apps-only`、`--packages-only`、`--limit` 语义。

## Success signal

用户在 Axion 交互模式中输入 `/arch`，列表中选择一个 Intel-only Homebrew 项，进入详情后看到 `u 升级`、完整 `brew` 命令和复扫说明。用户确认后升级执行，Axion 重新扫描同一可执行文件并显示架构变化；如果升级后仍是 Intel-only，详情明确报告“升级完成但仍未提供 arm64/universal”。选择直接下载的非系统 `.app` 时，详情给出手动升级指导，同时显示 `x 卸载`；用户按 `x` 后进入现有 `/apps` 卸载审批流程，typed 确认后只把 bundle 和用户批准的 support 数据移入废纸篓，并显示 undo 提示。选择 CLI 包、系统应用或 Unknown 路径时，不显示可执行卸载按钮。

## Assumptions

- Homebrew formula 可以从 `/opt/homebrew/Cellar` 或 `/usr/local/Cellar` 真实路径稳定提取 formula 名称。
- Homebrew cask 需要额外元数据解析，可能通过 Caskroom 路径、bundle 路径或 `brew list --cask` 输出建立映射。
- `brew upgrade <formula>` 和 `brew upgrade --cask <token>` 是 MVP 的首选升级命令；`brew update` 是否前置执行由实现阶段评估。
- 现有 `AppArchitectureItem` 需要补充或关联包管理器身份、版本、upgrade plan、uninstall option 和 post-check 路径。
- `/arch` 的 `.app` 项需要能映射到现有 `AppCandidate` 或等价查询参数，才能复用 `scan_app_uninstall` / `execute_app_uninstall` 链路。
- 当前 `/arch` 详情页已是只读承接点，后续可以在详情态新增 `u`、`x` 和 `r` 操作。

## Open Questions

- Homebrew 升级前是否总是执行 `brew update`，还是先检测 last update 时间或提供用户选择？
- 是否需要记录升级历史到本地文件，便于用户回看执行过的命令和结果？
- Homebrew cask token 识别失败时，是否允许用户手动选择候选 token？
- 后续是否接入 `mas` 支持 App Store 项，还是继续只给手动指导？
- 批量升级是否作为后续能力进入详情页，还是单独设计 `axion arch upgrade` 子命令？
- Homebrew cask App 的卸载是否长期继续走可恢复 `/apps` 流程，还是后续增加显式 `brew uninstall --cask` 手动指导或独立动作？
