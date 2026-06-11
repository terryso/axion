# Axion Epic 39: Mac 文件、存储与 App 管理

> **状态：提议中**
> **优先级：P1**
> **前置依赖：** Epic 37（交互聊天模式）建议已完成；Epic 38（终端体验增强）非硬依赖
> **目标入口：** `axion run`、交互模式 `axion` 首发支持；Telegram 网关预留审批适配

## 背景与动机

Axion 已经具备自然语言任务执行、文件读写、Shell、Finder 桌面自动化和交互模式。下一阶段需要把这些能力从 demo 场景推进到普通 Mac 用户的高频刚需：整理混乱目录、释放磁盘空间、卸载 App、处理安装包和大文件。

典型用户不是想学习 Shell、Automator 或复杂清理软件，而是想直接说：

```bash
axion run "帮我整理下载目录，找出大文件和不用的安装包，先给我确认清单"
```

或在交互模式中说：

```text
帮我看看 Downloads 里哪些文件可以清理，先不要删
```

这个 Epic 的目标是把 Axion 做成一个安全、可解释、可回滚的 Mac 文件与存储管家，而不是给 LLM 一个无限制删除权限。

## 产品目标

1. **解决真实刚需**：整理目录、找大文件、清理安装包、辅助卸载 App。
2. **同时支持单次和多轮**：`run` 适合一次性任务；交互模式适合多轮筛选、追问、局部确认和撤销。
3. **为远程入口预留**：未来 Telegram 可复用同一套计划、审批、执行、回滚模型。
4. **安全优先**：所有破坏性操作先生成计划，默认移到废纸篓，不永久删除。
5. **隐私优先**：默认只扫描元数据；读取文件内容或生成内容摘要必须明确说明并获得确认。

## 非目标

- 不做杀毒、防恶意软件、系统加速或内核级清理。
- 不自动清理 `/System`、`/Library`、`/usr` 等系统路径。
- 不默认读取用户文件内容，不把文件内容发送给模型。
- 不绕过 macOS 权限，不请求 Full Disk Access 作为 MVP 前置条件。
- 不在第一阶段实现 Telegram 端完整交互 UI，只保留协议和审批模型兼容性。

## 入口与体验要求

### `axion run`

`run` 模式适合用户给出明确任务后快速得到计划和结果。

**示例：**

```bash
axion run "整理 ~/Downloads，把截图、PDF、安装包分类，执行前给我确认"
axion run "找出超过 1GB 的文件，先列清单不要删除"
axion run "卸载 Xcode beta，包含相关缓存，但每一步都要确认"
```

**要求：**

- 默认先输出操作计划，不直接执行移动、删除、卸载。
- 用户可在终端审批整个计划，也可逐项批准/拒绝。
- 非 TTY 或 `--json` 模式下输出结构化计划，调用方可显式传入确认。
- 执行后输出摘要：移动了什么、跳过了什么、失败了什么、如何撤销。

### 交互模式

交互模式适合探索式清理和连续决策。

**示例流程：**

```text
用户：帮我看看 Downloads 里哪些东西占空间
Axion：列出大文件、安装包、重复候选、最近未使用文件
用户：先处理 dmg 和 zip，PDF 不动
Axion：生成更新后的计划
用户：把这些移到废纸篓
```

**要求：**

- 支持多轮细化扫描范围、分类规则和操作策略。
- 支持“只看不动”“只处理某类文件”“排除某个目录”。
- 审批请求应复用现有权限确认体验，并支持详情查看。
- 交互模式中应能查询上一次清理记录，并发起撤销。

### Telegram 预留

Telegram 不是第一阶段必须交付，但本 Epic 的内部模型必须支持远程入口。

**设计约束：**

- 扫描计划、审批请求、执行结果都必须是结构化模型，不绑定终端文本。
- 审批动作抽象为 `approvePlan`、`approveItem`、`rejectItem`、`cancel`。
- 计划摘要必须能压缩成远程消息格式，详情可分页。
- 高风险操作在远程入口中必须更保守：默认只允许扫描和移到废纸篓，不允许永久删除。

## 核心能力范围

### 1. 按内容整理文件或目录

用户选择一个或多个目录后，Axion 不应只按扩展名硬编码分类，而应采用“代码提取安全信号 + Agent 语义分析”的混合模式生成整理计划。

**分类策略：**

| 层 | 责任 | 示例 |
|----|------|------|
| 本地扫描层 | 提取安全、低成本、可审计的文件信号 | 路径、文件名、扩展名、UTType、大小、创建/修改时间、是否 bundle、是否隐藏、是否来自下载目录 |
| 可选内容摘要层 | 在用户授权后读取有限内容或元数据摘要 | PDF 标题/前几页文本、图片 EXIF、文本文件前 N KB、归档包文件清单 |
| Agent 语义层 | 结合目录上下文和用户意图生成动态分类 | “发票与报销”、“项目资料”、“安装包可清理”、“会议录音”、“截图临时文件” |
| 安全执行层 | 将 Agent 建议转成可确认、可撤销的操作计划 | move / trash / createDirectory / scanOnly |

扩展名、UTType 和文件名模式只作为底层信号，不是最终分类逻辑。Agent 应根据目录里实际出现的文件簇、命名模式、时间分布和用户目标动态决定分类名称与目标目录。例如同样是 PDF，在一个目录里可能分成“合同 / 发票 / 白皮书”，在另一个目录里可能分成“课程资料 / 论文 / 说明书”。

**默认输出分类示例，不是硬编码规则：**

| 场景 | Agent 可能生成的分类 | 默认动作 |
|------|----------------------|----------|
| Downloads 中有大量 `.dmg`、`.pkg`、旧 `.zip` | 安装包与压缩包 | 建议移到废纸篓或 `Installers/`，需确认 |
| 混合 PDF、表格、图片，文件名含 invoice/receipt | 报销与票据 | 建议归档到用户确认的目录 |
| 大量截图，时间集中且命名相似 | 临时截图 | 建议移动到 `Screenshots/` |
| 大视频、录屏、音频 | 大媒体文件 | 只列出，不默认移动 |
| 无法判断业务语义的文件 | 未分类 / 需要用户判断 | 默认不处理 |

**Acceptance Criteria:**

**Given** 用户请求整理 `~/Downloads`
**When** Axion 扫描目录
**Then** 返回由 Agent 基于文件信号和目录上下文生成的分类整理计划
**And** 计划包含源路径、目标路径、文件大小、原因和风险等级
**And** 每个分类说明使用了哪些信号或上下文依据
**And** 未经确认不移动任何文件

**Given** 用户授权读取部分文件内容用于分类
**When** Axion 读取 PDF、文本或归档包摘要
**Then** 只读取完成分类所需的最小内容
**And** 在计划中标注哪些分类使用了内容摘要
**And** 未经授权不读取文件正文

**Given** 用户批准整理计划
**When** Axion 执行移动
**Then** 文件被移动到计划目标位置
**And** 生成可撤销 manifest
**And** 执行摘要列出成功、跳过和失败项

### 2. 查找和处理大文件

Axion 帮用户找到占用空间的文件，并解释为什么值得处理。

**默认扫描范围：**

| 范围 | 默认行为 | 说明 |
|------|----------|------|
| `~/Downloads` | 扫描 | 最常见清理入口 |
| `~/Desktop` | 扫描 | 只列候选，近期文件默认不处理 |
| `~/Documents` | 扫描元数据 | 不读取内容，重要文档默认不处理 |
| `~/Movies` / `~/Pictures` / `~/Music` | 只列大文件 | 媒体文件可能是用户资产，默认不移动 |
| 当前工作目录 | 默认排除 | 避免误处理项目文件 |
| `node_modules` / `.build` / `DerivedData` 等开发缓存 | 可单独列为“开发缓存候选” | 只在用户明确要求清理开发缓存时处理 |

默认阈值建议为 1GB；用户可通过自然语言覆盖，例如“找出超过 500MB 的文件”。扫描必须跳过 symlink 目标，不跟随符号链接跨出扫描根。App bundle、package bundle、Photos/Music 等库文件应按单个 bundle/library 展示，不递归展开给 Agent 做移动建议。

重复文件检测不属于默认 MVP。若用户明确要求“找重复文件”，第一阶段只做只读候选提示，不自动删除重复项。

**Acceptance Criteria:**

**Given** 用户请求“找出超过 1GB 的文件”
**When** Axion 扫描用户目录
**Then** 输出按大小排序的大文件列表
**And** 默认排除系统目录、隐藏目录、开发依赖目录和当前项目目录
**And** 列表包含大小、最后修改时间、文件类型和建议动作
**And** symlink 只作为路径项展示，不跟随扫描目标

**Given** 用户批准处理若干大文件
**When** Axion 执行动作
**Then** 默认移动到废纸篓
**And** 不执行永久删除

### 3. 卸载 App 与 Support 数据清理

Axion 支持卸载用户选择的 App，并应把 App 的 support 数据纳入卸载计划：包括缓存、偏好设置、Saved State、Application Support、Containers、Group Containers、LaunchAgents 等。App bundle 只是卸载的一部分，完整计划必须同时展示“应用本体”和“关联 support 数据”。

卸载 App 是本 Epic 中误删风险最高的能力，必须拆成“识别 App → 生成卸载计划 → 扫描 support 数据 → 移动 App bundle 到废纸篓 → support 数据逐项确认”的多阶段流程。默认计划必须包含 support 数据候选，但高风险用户数据默认不选中。

**参考项目与设计来源：**

| 来源 | 类型 | 可借鉴点 | Axion 取舍 |
|------|------|----------|------------|
| [Pearcleaner](https://github.com/alienator88/Pearcleaner) | Swift Mac app cleaner；source-available/fair-code | App uninstall、orphaned file search、CLI/deep link、Finder Extension、Sentinel 监控 App 入废纸篓、include/exclude directories、search sensitivity、导出 app bundles/file lists | 借鉴扫描路径、容器发现、搜索敏感度、撤销/历史和 UX；不直接复用代码或受其 Commons Clause 许可证影响 |
| [Homebrew Cask `uninstall` / `zap`](https://docs.brew.sh/Cask-Cookbook#stanza-zap) | 开源规则与大量 cask 语料 | `zap` 明确把偏好、缓存、共享资源作为“更完整卸载”的范围；`zap` 不默认执行；`trash:` 优先于 `delete:`；不应删除用户直接创建的文件；常查路径包含 `~/Library/Application Support`、`Caches`、`Containers`、`LaunchAgents`、`Logs`、`Preferences`、`Saved Application State` | 作为 support 数据分类和安全策略的主参考；Axion 应比 `brew --zap` 更交互化，逐项解释和确认 |

Pearcleaner README 显示它需要 Full Disk Access 和 privileged helper 才能搜索/处理更广范围文件。Axion MVP 不应把 Full Disk Access 作为前置要求，而应先覆盖当前用户可读写范围；无法访问的 support 数据只做提示，不阻塞 App bundle 卸载。

**支持范围：**

- `/Applications/*.app`
- `~/Applications/*.app`
- 常见 support 数据候选：
  - `~/Library/Application Support/<app or bundle id>`
  - `~/Library/Caches/<bundle id>`
  - `~/Library/HTTPStorages/<bundle id>`
  - `~/Library/WebKit/<bundle id>`
  - `~/Library/Logs/<app or bundle id>`
  - `~/Library/Preferences/<bundle id>.plist`
  - `~/Library/Preferences/ByHost/<bundle id>.*.plist`
  - `~/Library/Saved Application State/<bundle id>.savedState`
  - `~/Library/Application Scripts/<bundle id>`
  - `~/Library/Containers/<bundle id>`
  - `~/Library/Group Containers/<team id or bundle id>`
  - `~/Library/LaunchAgents/<bundle id>.plist`

**卸载模式：**

| 模式 | 默认入口 | 行为 | 风险策略 |
|------|----------|------|----------|
| `scanOnly` | 用户要求“看看能不能卸载” | 只识别 App 和 support 数据候选，不执行操作 | 无副作用 |
| `uninstallAppOnly` | 用户要求“只卸载应用本体” | 仅移动 `.app` bundle 到废纸篓 | 需确认 |
| `uninstallWithSupportReview` | 用户要求“卸载 App” | 移动 `.app` bundle，并展示 support 数据候选供确认 | 默认模式 |
| `reviewSupportData` | 用户要求“看看 support 数据” | 扫描 support 数据候选并分类展示 | 只读 |
| `cleanApprovedSupportData` | 用户明确批准 support 数据清理 | 只移动已批准 support 数据到废纸篓 | 逐项或按风险组确认 |

永久删除不属于 MVP。任何模式都不使用 `sudo`，也不处理需要管理员权限的系统级卸载。

**App 识别要求：**

| 字段 | 说明 |
|------|------|
| `displayName` | App 显示名 |
| `bundleIdentifier` | 从 `Info.plist` 读取的 bundle id |
| `bundlePath` | App bundle 绝对路径 |
| `version` | `CFBundleShortVersionString` / `CFBundleVersion` |
| `teamIdentifier` | 可选，签名 team id；读取失败不阻塞 |
| `sizeBytes` | App bundle 体积 |
| `isRunning` | 是否有运行中进程 |
| `isSystemProtected` | 是否位于系统路径或疑似 Apple/system 组件 |
| `matchConfidence` | 用户输入到候选 App 的匹配置信度 |

多候选匹配时必须让用户选择，不能按模糊匹配自动卸载。路径不在 `/Applications` 或 `~/Applications` 时必须额外确认。系统 App、Apple 预装 App、MDM/企业管理 App、正在运行且未能正常退出的 App 默认不可卸载，只能提示用户手动处理或显式升级确认。

**Support 数据分类：**

| 类别 | 示例路径 | 数据风险 | 默认动作 |
|------|----------|----------|----------|
| 可重建缓存 | `~/Library/Caches/<bundle id>` | 低 | 可建议清理，需确认 |
| 日志 / 崩溃报告 | `~/Library/Logs/...`、`~/Library/DiagnosticReports/...` | 低 | 可建议清理，需确认 |
| HTTP / WebKit 存储 | `~/Library/HTTPStorages/<bundle id>`、`~/Library/WebKit/<bundle id>` | 中 | 单独列出，默认不勾选 |
| 偏好设置 | `~/Library/Preferences/<bundle id>.plist` | 中 | 单独列出，默认不勾选 |
| Saved State | `~/Library/Saved Application State/<bundle id>.savedState` | 中 | 单独列出，默认不勾选 |
| Application Scripts | `~/Library/Application Scripts/<bundle id>` | 中 | 单独列出，默认不勾选 |
| Application Support | `~/Library/Application Support/<app or bundle id>` | 高 | 可能包含用户数据，默认不清理 |
| App Sandbox Container | `~/Library/Containers/<bundle id>` | 高 | 可能包含用户数据，默认不清理 |
| Group Container | `~/Library/Group Containers/<team/app group>` | 高 | 可能被多个 App 共享，默认不清理 |
| LaunchAgents / Login Items | `~/Library/LaunchAgents/<bundle id>.plist` | 高 | 仅扫描提示，不自动移除 |
| Keychain / 浏览器扩展 / 云同步数据 | Keychain、iCloud、Dropbox、OneDrive 等 | 禁止 | MVP 不处理 |

Application Support 是一等支持数据来源，不能只作为“残留”附带扫描。计划中必须单独展示 Application Support 目录大小、最近修改时间、匹配证据和数据风险。它可能包含用户创建的数据、数据库、下载内容、插件和项目缓存，所以默认不选中；如果用户明确要求“连配置和数据一起卸载”，仍需要逐项确认。

**Support 数据匹配证据：**

| 证据强度 | 例子 | 是否可默认进入清理计划 |
|----------|------|--------------------------|
| 高 | 路径精确包含 bundle id；plist 文件名等于 bundle id；Container 名等于 bundle id | 可以列入候选，但仍需确认 |
| 中 | 路径包含 App 显示名或 vendor 名，并且目录内 metadata 指向 bundle id | 可以列出为“需要用户判断” |
| 低 | 仅靠名称相似、模糊匹配、同 vendor 父目录 | 只提示，不进入可执行计划 |

禁止因为 vendor 名称匹配而删除共享目录。例如卸载某个 Google App 时，不能删除整个 `~/Library/Application Support/Google`；只能处理证据精确指向目标 bundle id 的子项。对 `Group Containers` 只要无法证明只归属于目标 App，就必须保持 scan-only。

**卸载计划字段补充：**

| 字段 | 说明 |
|------|------|
| `app` | 已选 App 候选信息 |
| `uninstallMode` | `scanOnly` / `uninstallAppOnly` / `uninstallWithSupportReview` / `reviewSupportData` / `cleanApprovedSupportData` |
| `supportDataItems` | support 数据候选列表 |
| `dataLossRisk` | `none` / `low` / `medium` / `high` |
| `requiresTypedConfirmation` | 高风险项是否要求输入 App 名或 bundle id 确认 |
| `blockedReasons` | 因系统保护、运行中、权限不足或证据不足而阻止执行的原因 |
| `externalUninstallHints` | pkg receipt、Homebrew cask、vendor uninstaller 等只读提示 |

**Support 数据项字段补充：**

| 字段 | 说明 |
|------|------|
| `category` | cache / logs / preferences / savedState / applicationSupport / container / groupContainer / launchAgent / forbidden |
| `path` | 候选路径 |
| `sizeBytes` | 体积 |
| `matchEvidence` | 匹配依据 |
| `matchConfidence` | high / medium / low |
| `dataRisk` | low / medium / high / forbidden |
| `defaultSelected` | 默认是否勾选；高风险必须为 false |
| `requiresExplicitApproval` | 是否必须逐项确认 |

**安装来源与外部卸载提示：**

| 来源 | 处理策略 |
|------|----------|
| 普通 `.app` bundle | 可移动 App bundle 到废纸篓 |
| Mac App Store App | 可移动 App bundle 到废纸篓；support 数据仍按风险分级确认 |
| Homebrew Cask | 可读取本机 cask 元数据和 `zap` 路径作为候选提示；不直接执行 `brew uninstall --zap` |
| `.pkg` / installer 安装 | 只识别 pkg receipts、launchd jobs、login items 等为外部卸载提示；MVP 不执行 `pkgutil --forget`、不删除系统 payload、不运行 sudo uninstaller |
| Vendor uninstaller | 只提示存在，不自动运行；运行外部 uninstaller 属于后续能力 |

Homebrew Cask `zap` 数据只能作为候选来源，仍要经过 Axion 的风险分级、证据说明和用户确认。任何外部元数据都不能绕过 Axion 的安全策略。

**Acceptance Criteria:**

**Given** 用户请求卸载某个 App
**When** Axion 找到匹配 App
**Then** 展示 App 名称、路径、bundle id、大小和最近修改时间
**And** 同时扫描并展示 support 数据候选摘要
**And** 请求用户确认后才移动 App bundle 到废纸篓

**Given** 用户输入匹配到多个 App
**When** Axion 无法确定唯一目标
**Then** 展示候选列表并停止
**And** 不自动选择第一个候选执行卸载

**Given** 目标 App 正在运行
**When** 用户请求卸载
**Then** Axion 先请求确认是否正常退出 App
**And** 退出失败时不移动 App bundle

**Given** 目标 App 位于系统路径或疑似系统组件
**When** 用户请求卸载
**Then** Axion 阻止自动卸载
**And** 给出安全原因和手动处理建议

**Given** 用户请求清理 support 数据
**When** Axion 扫描常见 support 数据目录
**Then** 输出候选 support 数据列表和匹配依据
**And** 每个 support 数据项需要单独确认或批量确认
**And** 默认仍移动到废纸篓，不永久删除

**Given** support 数据候选是 `Application Support`、`Containers` 或 `Group Containers`
**When** Axion 生成计划
**Then** 标记为高风险用户数据候选
**And** 默认不选中
**And** 必须逐项确认后才可移到废纸篓
**And** 若 `requiresTypedConfirmation` 为 true，用户必须输入 App 名或 bundle id 才能批准

**Given** support 数据候选只有低置信度名称相似证据
**When** Axion 生成计划
**Then** 该项只能作为提示展示
**And** 不进入可执行清理计划

**Given** 卸载或 support 数据清理已执行
**When** 生成 manifest
**Then** manifest 记录 App 信息、每个移动项的原路径、废纸篓目标、大小、时间戳、审批决策和匹配证据
**And** 撤销只恢复 manifest 中记录且仍存在于废纸篓的项目

**Given** App 来自 `.pkg` 或 Homebrew Cask
**When** Axion 生成卸载计划
**Then** 展示 pkg receipt 或 cask zap 路径作为只读提示
**And** 不执行 sudo、pkgutil forget、vendor uninstaller 或 `brew uninstall --zap`

### 4. 安全确认与回滚

所有有副作用操作必须经过统一计划模型。

**计划字段：**

| 字段 | 说明 |
|------|------|
| `operationId` | 本次计划 ID |
| `surface` | `run` / `chat` / future `telegram` |
| `items` | 操作项列表 |
| `riskLevel` | `low` / `medium` / `high` |
| `requiresConfirmation` | 是否需要确认 |
| `reversible` | 是否可撤销 |
| `summary` | 面向用户的摘要 |

**操作项字段：**

| 字段 | 说明 |
|------|------|
| `action` | `move` / `trash` / `createDirectory` / `uninstallApp` / `scanOnly` |
| `sourcePath` | 源路径 |
| `targetPath` | 目标路径，可选 |
| `sizeBytes` | 文件大小，可选 |
| `reason` | 为什么建议这么做 |
| `riskLevel` | 单项风险 |
| `approved` | 是否已批准 |
| `evidence` | 操作依据，包含匹配规则、来源和置信度 |
| `dataRisk` | 数据风险 |

**Manifest 存储：**

每次有副作用的操作必须写入 manifest，建议路径为 `~/.axion/storage-ops/<operationId>.json`。manifest 必须在执行前创建草稿，执行后补全结果，避免执行中断后丢失审计信息。

**Manifest 字段：**

| 字段 | 说明 |
|------|------|
| `operationId` | 操作 ID |
| `createdAt` / `completedAt` | 时间戳 |
| `surface` | run / chat / future telegram |
| `userRequest` | 用户原始请求 |
| `approvedByUser` | 审批摘要 |
| `items` | 每个执行项 |
| `trashResultPath` | 实际进入废纸篓后的路径 |
| `status` | planned / executing / completed / partiallyFailed / cancelled |
| `errors` | 非致命失败 |

**Acceptance Criteria:**

**Given** 计划包含移动、废纸篓或卸载动作
**When** 用户尚未确认
**Then** Axion 不执行任何副作用操作

**Given** 操作已执行并生成 manifest
**When** 用户请求撤销上一次整理
**Then** Axion 根据 manifest 尝试恢复文件位置
**And** 对无法恢复的项目给出明确原因

## 安全边界

默认禁止自动处理以下路径：

- `/System`
- `/Library`
- `/bin`
- `/sbin`
- `/usr`
- `/private`
- `.git`
- 当前工作目录下的源码项目，除非用户明确指定
- `~/Library` 全目录级清理，除非是 App support 数据扫描并逐项确认

默认不处理以下文件：

- 未提交 Git 工作区中的文件
- dotfile 和隐藏目录
- 近期修改的重要文档，除非用户明确选择
- iCloud/Dropbox/OneDrive 同步目录中的文件，除非用户确认同步风险
- symlink 指向的外部目标，除非用户明确要求并再次确认

高风险操作确认策略：

| 风险 | 示例 | 确认策略 |
|------|------|----------|
| 低 | 清理精确匹配的缓存/日志 | 普通确认即可 |
| 中 | Preferences、Saved State、HTTPStorages | 逐项或风险组确认 |
| 高 | Application Support、Containers、Group Containers、同步目录 | 逐项确认；可要求输入 App 名或 bundle id |
| 禁止 | Keychain、系统目录、pkg 系统 payload、用户直接创建的数据 | MVP 不执行 |

## 建议实现分层

| 层 | 责任 |
|----|------|
| AxionCLI 服务层 | 文件扫描、分类、计划生成、执行、manifest、回滚 |
| Agent 工具层 | 暴露 `storage_scan`、`organize_folder`、`trash_items`、`uninstall_app` 等工具 |
| 交互审批层 | run/chat/TG 共享确认模型，各入口只负责展示和收集决策 |
| AxionHelper | 仅在需要 Finder/App UI 操作时使用，不承担核心文件系统逻辑 |

## Story 拆分建议

### Story 39.1: 安全文件扫描与计划模型

As a Mac 用户,
I want Axion 先扫描目录并生成可解释计划,
So that 我能在不冒删除风险的情况下理解磁盘占用和整理建议.

**范围：**

- 目录扫描服务
- 排除规则
- 大文件排序
- 文件信号提取
- Agent 语义分类提示与结果解析
- `StoragePlan` / `StoragePlanItem` 模型
- `run` 和交互模式均可展示计划

### Story 39.2: 整理目录执行与撤销

As a Mac 用户,
I want 批准计划后让 Axion 整理文件,
So that Downloads/Desktop 等目录能安全变干净.

**范围：**

- 创建目标目录
- 移动文件
- 移到废纸篓
- manifest 记录
- 撤销上一次操作

### Story 39.3: App 卸载与 Support 数据候选扫描

As a Mac 用户,
I want Axion 卸载 App 并提示相关 support 数据,
So that 我能释放空间但不会误删重要数据.

**范围：**

- App bundle 发现：仅扫描 `/Applications`、`~/Applications`，系统路径默认阻止
- App 元数据解析：display name、bundle id、version、team id、bundle path、大小、运行状态
- 多候选 disambiguation：模糊匹配不自动执行，必须用户选择唯一 App
- 卸载模式：`scanOnly`、`uninstallAppOnly`、`uninstallWithSupportReview`、`reviewSupportData`、`cleanApprovedSupportData`
- support 数据候选扫描：Caches、Logs、Preferences、Saved State、Application Support、Containers、Group Containers、LaunchAgents
- support 数据风险分级：低风险缓存/日志、中风险偏好、高风险用户数据、禁止处理项
- 证据强度模型：high / medium / low，低置信度候选不得进入可执行计划
- 共享目录保护：vendor 父目录、Group Containers、云同步目录默认 scan-only
- Homebrew Cask / pkg receipt / vendor uninstaller 只读提示，不直接执行外部卸载器
- 分级确认：App bundle、低风险 support 数据、高风险 support 数据分别确认；高风险项默认不选中
- manifest 与撤销：记录原路径、废纸篓目标、审批决策、匹配证据和不可恢复原因
- 单元测试覆盖：多候选、系统 App、运行中 App、共享目录误删防护、低置信度 support 数据阻止、pkg/Homebrew 只读提示、manifest 回滚

### Story 39.4: 多入口审批适配

As a Axion 用户,
I want run、交互模式和未来远程入口都使用一致的审批语义,
So that 同一个高风险任务在不同入口中行为一致、安全可控.

**范围：**

- 共享审批决策模型
- `run` 终端确认
- 交互模式逐项确认
- Telegram 预留字段和摘要格式
- JSON 输出兼容

## 验收示例

### 示例 1：run 模式整理 Downloads

**Given** `~/Downloads` 包含 PDF、截图、`.dmg`、`.zip` 和视频文件
**When** 用户运行：

```bash
axion run "帮我整理 Downloads，先给我确认清单"
```

**Then** Axion 输出整理计划
**And** 不移动任何文件
**When** 用户批准计划
**Then** Axion 执行已批准项并生成撤销 manifest

### 示例 2：交互模式筛选大文件

**Given** 用户在 `axion` 交互模式中说“找出占空间的大文件”
**When** Axion 扫描完成
**Then** 返回按大小排序的候选列表
**When** 用户说“只处理 dmg 和 zip”
**Then** Axion 更新计划，只保留安装包类候选

### 示例 3：卸载 App

**Given** 用户请求“卸载 Foo.app 并看看 support 数据”
**When** Axion 找到 App 和 support 数据候选
**Then** 先确认移动 App 到废纸篓
**And** support 数据项单独列出，等待二次确认

## 成功指标

- 用户能在 2 分钟内完成一次 Downloads 清理计划预览。
- 默认无确认时，破坏性操作执行次数为 0。
- 100% 的移动、废纸篓、卸载动作都有 manifest。
- `run` 和交互模式共享同一套计划模型。
- 用户可理解每个建议动作的原因，而不是只看到文件列表。

## 待确认产品决策

1. **MVP 优先顺序**：先做 App 卸载，还是先做 Downloads 整理和大文件扫描？如果 App 卸载是最常用刚需，建议把 Story 39.3 提前为首个实现切片。
2. **默认勾选策略**：低风险缓存/日志是否可以默认选中但仍需确认？保守建议：MVP 所有 support 数据默认不选中，只让用户主动选择。
3. **内容读取策略**：整理目录时是否允许在 MVP 中读取 PDF/text 摘要？保守建议：MVP 只做元数据 + 文件名语义分析，内容摘要作为后续增强。
4. **重复文件检测**：是否进入 MVP？保守建议：不进入第一阶段，避免误删和复杂确认。
5. **Homebrew Cask 集成深度**：MVP 是否只读取 cask zap 元数据作为提示？保守建议：只读提示，不调用 `brew uninstall --zap`。
