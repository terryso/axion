---
title: 'Apple Photos Search Tagging'
type: 'feature'
created: '2026-06-13T04:43:41+0800'
status: 'draft'
context:
  - '{project-root}/_bmad-output/project-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/39-1-safe-file-scan-plan-model.md'
  - '{project-root}/_bmad-output/implementation-artifacts/39-2-organize-folder-execute-undo.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 用户在 iPhone Photos 里经常搜不到想找的照片；把照片导出到 Mac、改图片文件元数据、再复制回 iPhone 的路径太麻烦，也容易产生重复导入和 iCloud/Live Photo/HEIC 边界问题。Axion 需要直接面向 Apple Photos 工作流，让 agent 分析照片内容并写入 Photos 可搜索元数据，使这些照片通过 iCloud Photos 同步后在 iPhone 上更容易被搜索到。

**Approach:** 新增 `/photos` 交互式向导作为主入口，支持“当前 Photos 选中照片、最近导入、指定相册、指定时间范围”等来源。工具通过 Photos.app 脚本接口只读枚举候选、临时导出/读取分析图像，agent 生成中英文关键词与简短 caption，用户确认后写回 Photos `keywords` / `description` / 可选 `name`。文件夹 IPTC/XMP 写入保留为高级备选模式，不作为 MVP 主路径。MVP 不直接修改 `.photoslibrary` 内部数据库；iPhone 搜索命中依赖 iCloud Photos 同步和系统索引，属于 best-effort。

## Boundaries & Constraints

**Always:** 只处理用户明确选择或授权范围内的 Apple Photos media item。读取像素前必须有用户请求；分析用导出文件放在 Axion 私有临时目录，单图限字节并下采样，流程结束后清理。写入只合并新增关键词/说明，保留已有 Photos 元数据；所有写入必须生成 draft manifest，逐项审批后执行，并记录 media item id、原 keywords/description 摘要和新增值。非 TTY、`--json`、Telegram 默认拒绝 Photos 元数据写入。

**Ask First:** 处理超过默认批量上限的照片、覆盖/删除已有 keywords/description/title、修改文件夹中的原始图片文件、导出完整原图、发送图片给外部视觉模型、或启用文件夹 IPTC/XMP 高级模式。

**Never:** 不递归展开 `.photoslibrary`、不直接写 Photos SQLite/内部数据库、不删除/移动照片、不修改 Live Photo 配对资源、不把图片发给当前 configured model 以外的服务、不把生成标签写入源码仓库或通用 memory。

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Interactive guide | `/photos` | 显示交互式来源选择：当前选中、最近导入、相册、时间范围、文件夹高级模式；选择后生成稳定 agent task | Photos 未运行或无权限时给出可恢复提示，不读取照片 |
| Selected photos | 用户在 Photos.app 选中若干照片后输入自然语言或 `/photos selected` | Agent 获取 selected media items，导出分析副本，生成 keywords/caption；审批后写回 Photos `keywords`/`description` | 未选中时回到向导，不默认处理全库 |
| Last import | `/photos recent` 或向导选择“最近导入” | 使用 Photos `last import album` 作为候选来源，默认限制 N 张并展示摘要 | 最近导入为空时返回只读错误 |
| Album | `/photos album 旅行` 或向导选择相册 | 按相册名查找，唯一匹配后处理；多匹配时要求用户选择更精确名称 | 不对多匹配自动写入 |
| Date range | `/photos range 2026-06-01..2026-06-13` 或自然语言等价请求 | 按日期过滤 Photos media items，展示数量和上限；超过上限要求确认 | 日期解析失败或数量过大时不导出像素 |
| Existing metadata | 照片已有 `family`、`travel` 等关键词/description | 写入时保留原 metadata，只追加去重后的新关键词，并可追加简短 description 片段 | 若全部关键词已存在且 description 不变，记录 skipped/noop |
| Folder advanced mode | `/photos folder ~/Pictures/iPhoneExport --limit 20` | 扫描普通图片文件，写 IPTC/XMP keywords/caption；用于非 Photos 库图片 | 目录不存在、`.photoslibrary`、symlink 或不可写时拒绝 |
| Unsafe write surface | API/Telegram/非交互终端触发 `apply_photos_metadata` | 审批门拒绝写入，返回 approval_required，附待确认摘要 | 不写 metadata，不写 completed manifest |

</frozen-after-approval>

## Code Map

- `Sources/AxionCLI/Tools/StorageScanTool.swift` -- CLI Agent tool 写法范本，含 `ToolProtocol`、schema、`ToolResultHelper`。
- `Sources/AxionCLI/Services/Storage/StorageScanService.swift` -- 文件扫描、UTType、bundle 折叠和 symlink 安全规则。
- `Sources/AxionCLI/Services/AgentBuilder.swift` -- Agent tools 注册位置；新工具必须在 `!dryrun` 下注册。
- `Sources/AxionCLI/Services/Storage/Approval/StorageApprovalGate.swift` -- storage 副作用工具审批门；需要纳入 `apply_photos_metadata`，复用其 per-item 子集审批。
- `Sources/AxionCore/Models/Storage/StorageConfig.swift` + `AxionConfig.swift` -- `PhotosConfig` partial-decode 模式的范本（39.1 已落地）。
- `Sources/AxionCLI/Chat/SlashCommand.swift` and `Sources/AxionCLI/Chat/SlashCommandHandler+Storage.swift` -- slash 入口和生成任务文本的模式。
- `Sources/AxionCLI/Commands/ChatCommand.swift` -- `/apps`、`/storage` 将 slash 命令转换为 agent task 的入口；`/photos` 沿用该模式。
- `/System/Applications/Photos.app` scripting definition -- 当前 macOS Photos 暴露 `selection`、`last import album`、`search`、media item `keywords` / `description` / `name` 等脚本属性；实现用 `PhotosScripting` Protocol 包装 `osascript -l JavaScript`（JXA）返回 JSON。
- `Sources/AxionHelper/Services/ScreenshotService.swift` -- ImageIO import/CGImage 使用范例（HEIC→JPEG 转码参考）；文件夹 IPTC/XMP 写入随 folder 模式 defer，不在本 Story。

## Tasks & Acceptance

**关键参数（已 pin）：**

| 参数 | 值 | 说明 |
|---|---|---|
| 批量上限 `batchLimit` | 20 | 单次来源候选上限；超过即 Ask-First 要求缩小范围 |
| 下采样长边 `downsampleLongEdgePx` | 1568 | 主流 vision 模型成本/质量甜点 |
| 单图最大字节 `maxImageBytes` | 1_572_864 (~1.5MB) | JPEG q85 压缩后上限 |
| HEIC 处理 | → JPEG | 经 ImageIO/CGImage 转码（参考 `ScreenshotService.swift`） |
| 视频像素分析 | 跳过 | MVP 仅读元数据打标签，不取代表帧 |
| Live Photo | 只分析配对静态图 | 永不读取/修改 `.mov` paired resource |
| `writeName` | 默认 false | 由 config `photos.writeName` 控制，可选 slash `--with-name` 临时开启；写 name 恒 Ask-First |
| `bilingualTags` | 默认 true | 中英文双语关键词 |

**Execution:**
- [ ] `Sources/AxionCore/Models/Photos/PhotoTagModels.swift` -- 新增 candidate/proposal/manifest 模型，snake_case Codable + `decodeIfPresent` 缺省回退（对齐 `StoragePlan` 模式）。
- [ ] `Sources/AxionCore/Models/Photos/PhotosConfig.swift` + `AxionConfig.swift` -- 新增 `photos: PhotosConfig?`（partial decode，缺省回退）；字段见上表。
- [ ] `Sources/AxionCLI/Services/Photos/PhotosScripting.swift` -- `PhotosScripting` Protocol + 实现，用 `osascript -l JavaScript`（JXA）返回 JSON，列出 selection / last import / album / date range；读取 id/name/filename/date/keywords/description/size。
- [ ] `Sources/AxionCLI/Services/Photos/PhotosExportService.swift` -- 将待分析 media items 导出到 Axion 私有临时目录，按上表下采样（HEIC→JPEG）、单图限字节；视频项跳过像素导出；流程结束清理。
- [ ] `Sources/AxionCLI/Tools/PhotosListTool.swift` and `PhotosImageLoadTool.swift` -- 只读 `photos_list` / `photos_image_load`；load 工具校验 manifest/source id 并返回 `.text(JSON) + .image(data:mimeType)`；执行前检测配置 model 是否支持 vision，不支持返回可读错误。
- [ ] `Sources/AxionCLI/Services/Photos/PhotosMetadataWriter.swift` and `Sources/AxionCLI/Tools/ApplyPhotosMetadataTool.swift` -- 唯一写入工具 `apply_photos_metadata`（统一命名，不再有 `apply_photo_tags`）：工具内先 build draft manifest；合并写回 Photos `keywords` / `description`，`writeName` 开启时可选 `name`，保留已有 metadata、追加去重。
- [ ] `Sources/AxionCLI/Services/Storage/Approval/StorageApprovalGate.swift`, `StorageApprovalInput.swift`, `AgentBuilder.swift` -- 将 `apply_photos_metadata` 纳入审批门 `decide()` 白名单，复用 per-item 子集审批 / `denySubset` 召回（对齐 `execute_storage_plan`）；非交互 / `--json` / Telegram surface 拒绝并附可读摘要；dryrun 不注册写入工具。
- [ ] `Sources/AxionCLI/Chat/SlashCommand.swift`, new `SlashCommandHandler+Photos.swift`, `Commands/ChatCommand.swift` -- 新增 `case photos = "/photos"`；无参显示向导文案；支持 `selected` / `recent` / `album <name>` / `range <date..date>`，可选 `--with-name`，生成稳定任务文本（沿袭 `SlashCommandHandler+Storage.swift` 与 `ChatCommand.swift` slash→task 入口）。
- [ ] `Tests/AxionCoreTests/Models/Photos/PhotoTagModelTests.swift` and `Tests/AxionCLITests/Photos/Photos*Tests.swift` -- 覆盖模型 Codable round-trip、`PhotosScripting` mock（不调真实 osascript）、来源解析、typed image、metadata merge/noop、审批门 per-item 子集、slash task、错误矩阵。

**Deferred（本 Story 不实现，记为后续 story）:**
- 文件夹 IPTC/XMP 高级模式（`/photos folder <path>`、`PhotoTagScanService`、`PhotoTagMetadataWriter`，及原 `apply_photo_tags` 的 folder 用途）——I/O 矩阵中保留为未来范围的行为描述，MVP 不交付。

**Acceptance Criteria:**
- Given 用户输入 `/photos`, when 未提供参数, then 显示交互式来源选择或生成“请先选择来源”的 agent task，不要求用户记住长参数。
- Given 用户在 Photos.app 选中照片, when 执行 `/photos selected` 或自然语言等价请求, then 写入前展示每张照片待新增 tags、caption 片段、理由和数量摘要。
- Given 用户批准部分照片, when `apply_photos_metadata` 执行, then 只修改批准项的 Photos keywords/description，保留原 metadata，并写入 manifest。
- Given 最近导入、相册或日期范围来源, when 候选数量超过默认上限, then 在导出/读取像素前要求用户缩小范围或确认上限。
- Given 图片不可读、越界、非 photo/video media item、`.photoslibrary` 内部路径或导出失败, when 工具处理, then 该项被拒绝或跳过且不会写 tag。
- Given 非交互、`--json` 或 Telegram surface, when 写入工具被调用, then 审批门拒绝副作用并返回可读原因。

## Design Notes

主路径不再要求“导出文件 -> 改文件 metadata -> 再复制回 iPhone”。MVP 面向 Photos Library 写 Photos 自身 metadata，然后由 iCloud Photos 同步到 iPhone。AppleScript/Photos.app 是当前最低侵入方案：不直接改数据库，且本机脚本字典暴露 `selection`、`last import album`、media item `keywords`/`description`。`photos_image_load` 一张图一调用；Agent 看图生成标签，Swift 工具只做来源解析、边界校验、图片导出/加载和写入。文件夹 IPTC/XMP 模式仍有价值，但作为高级模式 defer 到后续 story，不解决普通用户 iPhone 回传麻烦。

### 关键决策

- **审批机制（复刻 storage，不新增 propose 工具）**：`apply_photos_metadata` 单工具入参带全部候选项 → 工具内 build draft manifest → `StorageApprovalGate.decide()` 走现有 per-item 子集审批（用户批准部分照片）→ `denySubset` 召回 → agent 用批准子集重调执行。与 `execute_storage_plan` 同构，最小化新审批机制。
- **统一命名**：全项目只保留 `apply_photos_metadata`（写入 Photos 库）；原 `apply_photo_tags` 不再使用，其 folder 模式用途随 folder 模式 defer。
- **视觉模型**：复用 session 配置的 model，不引入第二模型配置；`photos_image_load` 前检测配置 model 是否支持 vision，不支持返回可读错误；cost 走既有 `/cost`。
- **MVP 成功标准 = 写入 Photos library metadata**，**不**保证「iPhone 立刻能搜到」——后者依赖 iCloud Photos 同步与系统索引，best-effort、本机不可验证。
- **JXA runner**：`PhotosScripting` 用 `osascript -l JavaScript` 返回 JSON（比 AppleScript record 易解析）；单测注入 mock，不调真实 osascript（CLAUDE.md 强制）。
- **HEIC / 视频 / Live Photo**：HEIC 经 ImageIO 转 JPEG；视频 MVP 跳过像素分析（仅元数据打标签，不取代表帧）；Live Photo 只分析配对静态图，永不读 `.mov` paired resource。

## Verification

**Commands:**
- `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` -- expected: unit tests pass; no Integration/E2E targets.
- `grep -rl "import XCTest" Tests/` -- expected: empty output.
