# Story 38.9: SlashPopup Skill 补全

Status: done

## Story

As a Axion 交互式 Chat 用户,
I want 输入 `/` 时 SlashPopup 列表中同时显示可用的 skill 名称（而不仅是内置 slash 命令）,
so that 我能通过补全面板发现和执行 skill，不需要记住 skill 名称或先执行 `/skills` 查看。

## 背景

Epic 38 实现了 SlashPopup 补全面板（输入 `/` 弹出命令列表），但当前 `SlashPopupItem` 强绑定 `SlashCommand` 枚举，只显示 15 个内置命令。`/skills` 命令可以列出 skill，但 `/` 补全不包含任何 skill。用户必须先执行 `/skills` 看名称、记住后再手动输入 `/skill-name`，发现性差。

本 Story 重构 `SlashPopupItem` 数据模型，使其同时承载内置命令和 skill，让补全面板成为统一的命令+skill 发现入口。

## Acceptance Criteria

1. **AC1: Skill 出现在空查询列表**
   - **Given** 用户输入 `/`（空查询）
   - **When** SlashPopup 渲染列表
   - **Then** 列表同时显示所有可用内置命令和所有 `userInvocable` skill
   - **And** 命令和 skill 混合排序（按名称字母序）

2. **AC2: Skill 前缀过滤**
   - **Given** 用户输入 `/sc`
   - **When** SlashPopup 过滤列表
   - **Then** 同时匹配命令（如 `/config`）和 skill（如 `screenshot-analyze`、`data-extract`）的名称前缀
   - **And** 匹配逻辑大小写不敏感

3. **AC3: Skill 渲染样式**
   - **Given** 列表中包含 skill 项
   - **When** 渲染 popup
   - **Then** skill 项显示格式：`/skill-name  [skill]  技能描述`
   - **And** `[skill]` 标签区分 skill 和内置命令（命令无标签）
   - **And** skill 描述截断超过 50 字符的部分，追加 `...`

4. **AC4: Skill 别名匹配**
   - **Given** skill 有别名（如 `screenshot-analyze` 别名 `sa`、`analyze`、`screen`）
   - **When** 用户输入 `/an` 或 `/sc`
   - **Then** 通过别名前缀匹配到对应 skill
   - **And** skill 只在列表中出现一次（不因多别名重复）

5. **AC5: Skill 选中并执行**
   - **Given** 用户通过 Tab/Enter 选中列表中的 skill 项
   - **When** 选中一个 skill（如 `screenshot-analyze`）
   - **Then** 补全 buffer 为 `/screenshot-analyze`
   - **And** 按 Enter 时提交输入，由 ChatCommand 的现有 skill 匹配逻辑执行
   - **And** Tab 补全后留在编辑模式（skill 接受参数，行为与命令相同）

6. **AC6: Skill 列表为空时无影响**
   - **Given** `--no-skills` 启动或无可用 skill
   - **When** 用户输入 `/`
   - **Then** popup 仅显示内置命令，行为与现有完全一致

7. **AC7: agent 忙碌时 skill 不可用**
   - **Given** agent 正在执行任务
   - **When** 用户输入 `/`
   - **Then** skill 项不出现在列表中（与 `/resume`、`/new` 等命令的过滤逻辑一致）

8. **AC8: 匹配高亮**
   - **Given** 用户输入 `/sc` 匹配到 skill `screenshot-analyze`
   - **When** TTY 模式渲染
   - **Then** skill 名称中的 `sc` 部分高亮显示（ANSI cyan + bold）

## Tasks / Subtasks

- [x] Task 1: 重构 `SlashPopupItem` 数据模型 (AC: 1-8)
  - [x] 引入 `SkillInfo` 轻量 struct + `SlashPopupItemKind` 枚举：`.command(SlashCommand)` | `.skill(SkillInfo)`
  - [x] 修改 `SlashPopupItem` 使用 `kind: SlashPopupItemKind` 替代 `command: SlashCommand`
  - [x] 更新 `matchRange` 计算逻辑适配两种 kind

- [x] Task 2: 扩展 `SlashPopup.filter()` 支持 skill (AC: 1, 2, 4, 7)
  - [x] 新增 `skills` 参数：`[SkillInfo]`（轻量 struct，只含 name/description/aliases）
  - [x] 空查询时合并命令和 skill 列表
  - [x] 前缀匹配同时搜索 skill 的 name 和 aliases
  - [x] `SlashCommandContext` 过滤：agent 忙碌时排除 skill

- [x] Task 3: 扩展 `SlashPopup.render()` 支持 skill 项 (AC: 3, 8)
  - [x] skill 项渲染：`/skill-name  [skill]  描述`
  - [x] skill 描述截断逻辑（>50 字符）
  - [x] skill 名称匹配高亮（ANSI cyan + bold）

- [x] Task 4: `ChatComposer` 注入 skill 列表 (AC: 1, 6, 7)
  - [x] `ChatComposer` 新增 `availableSkills: [SkillInfo]` 属性
  - [x] `enterSlashPopup()` 和 `refreshSlashPopup()` 调用 `SlashPopup.filter()` 时传入 skill 列表
  - [x] agent 忙碌过滤通过 filter() 内部 context.isAgentBusy 判断

- [x] Task 5: `ChatCommand` 传入 skill 数据 (AC: 1, 6)
  - [x] 从 `skillRegistry?.userInvocableSkills` 转换为 `[SkillInfo]` 并赋给 `composer.availableSkills`

- [x] Task 6: 适配 `ComposerSlashPopupHandling` (AC: 5)
  - [x] `completeSelectedCommand()` 改为 `completeSelected()`，返回 `SlashPopupItemKind?`
  - [x] skill 补全时 buffer 设为 `/skillName`（加空格，因为 skill 接受参数）
  - [x] Enter 提交逻辑：skill 走 acceptsArgs=true 路径留在编辑模式

- [x] Task 7: 更新测试 (AC: 全部)
  - [x] `SlashPopupTests` 适配新数据模型（27 个原有测试全部通过）
  - [x] 新增 14 个 skill 相关测试（过滤、渲染、混合排序、别名匹配、agent 忙碌等）
  - [x] `ChatComposerSlashPopupTests` 无需修改（通过 readInput 间接测试，接口兼容）

## Dev Notes

### 核心设计决策

**为什么引入 `SkillInfo` 而不直接用 `Skill`：**
- `SlashPopup` 是纯函数 + 零外部依赖的设计（见 `SlashPopup.swift` 注释）
- `Skill` 来自 SDK，包含闭包（`isAvailable`）、promptTemplate 等重字段
- popup 只需 name/description/aliases 三个字段做过滤和渲染
- 定义轻量 struct 保持 SlashPopup 的纯度：

```swift
/// Skill 摘要 — 仅供 SlashPopup 过滤/渲染使用。
struct SkillInfo: Equatable, Sendable {
    let name: String
    let description: String
    let aliases: [String]
}
```

**`SlashPopupItemKind` 设计：**

```swift
enum SlashPopupItemKind: Equatable {
    case command(SlashCommand)
    case skill(SkillInfo)
}
```

item 的显示名称（用于匹配和渲染）：
- `.command` → `command.rawValue`（如 `/help`）
- `.skill` → `"/\(skill.name)"`（如 `/screenshot-analyze`）

### 需要修改的文件

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `Sources/AxionCLI/Chat/Composer/SlashPopup.swift` | **UPDATE** | 新增 `SkillInfo`、`SlashPopupItemKind`；`SlashPopupItem` 用 `kind` 替代 `command`；`filter()` 和 `render()` 支持 skill |
| `Sources/AxionCLI/Chat/Composer/ChatComposer.swift` | **UPDATE** | 新增 `availableSkills: [SkillInfo]` 属性 |
| `Sources/AxionCLI/Chat/Composer/ComposerSlashPopupHandling.swift` | **UPDATE** | `completeSelectedCommand()` → `completeSelected()`；Enter 提交路径适配 skill |
| `Sources/AxionCLI/Commands/ChatCommand.swift` | **UPDATE** | 初始化 `composer.availableSkills` 从 `skillRegistry` 转换 |
| `Sources/AxionCLI/Chat/Composer/SlashCommandContext.swift` | **UPDATE** | `filter()` 方法签名不变，skill 过滤在 `SlashPopup.filter()` 层通过 context 判断 |
| `Tests/AxionCLITests/Chat/Composer/SlashPopupTests.swift` | **UPDATE** | 适配新模型 + 新增 skill 测试 |
| `Tests/AxionCLITests/Chat/Composer/ChatComposerSlashPopupTests.swift` | **UPDATE** | 适配新接口 |

### 关键约束

1. **保持 SlashPopup 纯函数** — 所有方法返回 String，零 I/O，不 import SDK
2. **保持向后兼容** — `filter()` 无 skill 参数时行为与现有完全一致（默认空数组）
3. **性能** — skill 数量通常 < 20，遍历开销可忽略。维持现有 < 0.1ms/次 的性能
4. **排序规则** — 混合排序：先精确匹配优先，然后按显示名称（`/command` 和 `/skill-name`）统一字母序
5. **agent 忙碌时** — skill 和 `/resume`、`/new` 一样不可用（`availableDuringTask: false`）

### `SlashPopupItem` 变更对照

```swift
// BEFORE:
struct SlashPopupItem: Equatable {
    let command: SlashCommand
    let matchRange: Range<String.Index>?
}

// AFTER:
struct SlashPopupItem: Equatable {
    let kind: SlashPopupItemKind
    let matchRange: Range<String.Index>?
}
```

### `completeSelectedCommand()` → `completeSelected()` 变更

```swift
// BEFORE:
mutating func completeSelectedCommand() -> SlashCommand?

// AFTER:
mutating func completeSelected() -> SlashPopupItemKind?
```

所有调用 `completeSelectedCommand()` 的地方（`ComposerSlashPopupHandling.swift` 中 Tab 和 Enter 分支）改为：
- Tab：补全名称，留在编辑模式
- Enter：
  - `.command` 且不接受参数 → 直接提交
  - `.command` 且接受参数 → 留在编辑模式
  - `.skill` → 留在编辑模式（skill 接受参数，用户可能要输入 args）

注意：当前 Enter 对无匹配内置命令的 `/xxx` 已有 fallback 提交逻辑（`ComposerSlashPopupHandling.swift:178-185`），skill 的 Enter 行为可复用此路径——选中 skill 后 buffer 为 `/skillName `，Enter 提交即走现有 ChatCommand 的 skill 匹配。

### `filter()` 新签名

```swift
static func filter(
    query: String,
    context: SlashCommandContext = SlashCommandContext(isAgentBusy: false, isSideSession: false),
    skills: [SkillInfo] = []   // NEW — 默认空，向后兼容
) -> [SlashPopupItem]
```

### `render()` skill 项样式

```
 ▶ 1.  /help                显示帮助信息
   2.  /screenshot-analyze  [skill]  捕获并分析当前屏幕，结合视觉截图...
   3.  /data-extract        [skill]  从当前应用窗口的 UI 元素中提取结构...
```

- 内置命令：`  /{rawValue}{padding}{helpText}`（现有格式不变）
- skill：`  /{name}{padding}[skill]  {description}`

### `ChatCommand` 传入 skill 数据

在 `ChatCommand.swift` 的 REPL 循环初始化后（约 163 行），添加：

```swift
// 注入 skill 列表到 composer
if let registry = skillRegistry {
    composer.availableSkills = registry.userInvocableSkills.map { skill in
        SkillInfo(name: skill.name, description: skill.description, aliases: skill.aliases)
    }
}
```

### 测试要点

1. `SlashPopupTests` 中的所有现有测试必须通过（`SlashPopupItem.command` → `SlashPopupItem.kind` 适配）
2. 新增测试：
   - `test_skillAppearsInEmptyQuery` — 空 `/` 查询包含 skill
   - `test_skillPrefixFilter` — `/sc` 匹配 `screenshot-analyze`
   - `test_skillAliasMatch` — `/an` 通过别名匹配 `screenshot-analyze`
   - `test_skillNoDuplicate` — 多个别名匹配只出现一次
   - `test_skillRenderWithTag` — 渲染包含 `[skill]` 标签
   - `test_mixedSorting` — 命令和 skill 混合字母序
   - `test_agentBusyHidesSkills` — agent 忙碌时 skill 被过滤
   - `test_emptySkillListNoChange` — 无 skill 时行为不变

### Project Structure Notes

- 所有变更在 `Sources/AxionCLI/Chat/Composer/` 目录内，遵循现有文件组织
- `SkillInfo` 定义在 `SlashPopup.swift` 中（与 `SlashPopupItem` 同文件，体量小）
- 测试文件位置不变

### References

- [Source: Sources/AxionCLI/Chat/Composer/SlashPopup.swift] — 当前 SlashPopupItem 和 filter/render 实现
- [Source: Sources/AxionCLI/Chat/Composer/ComposerSlashPopupHandling.swift] — popup 事件处理（Tab/Enter/过滤）
- [Source: Sources/AxionCLI/Chat/Composer/ChatComposer.swift] — ChatComposer 状态和 slashContext
- [Source: Sources/AxionCLI/Chat/Composer/SlashCommandContext.swift] — 上下文过滤
- [Source: Sources/AxionCLI/Chat/SlashCommand.swift] — SlashCommand 枚举定义
- [Source: Sources/AxionCLI/Commands/ChatCommand.swift:145-163] — skillRegistry 初始化和 composer 创建
- [Source: OpenAgentSDK/Types/SkillTypes.swift:56] — SDK Skill struct（name, description, aliases, userInvocable）
- [Source: _bmad-output/implementation-artifacts/deferred-work.md] — 延后工作来源记录
- [Source: Tests/AxionCLITests/Chat/Composer/SlashPopupTests.swift] — 现有测试

## Dev Agent Record

### Agent Model Used

Claude Sonnet 4 (via Axion Story Pipeline)

### Debug Log References

无 — 编译和测试一次通过

### Completion Notes List

- 所有 8 个 AC 全部实现并通过测试
- 保持 SlashPopup 纯函数设计，零 I/O，不 import SDK
- SkillInfo 轻量 struct 隔离 SDK Skill 类型（含闭包等重字段）
- 向后兼容：无 skill 参数时行为完全一致（默认空数组）
- 修复审查问题：删除无用 `_ = matched` 变量

### File List

**修改：**
- `Sources/AxionCLI/Chat/Composer/SlashPopup.swift` — 新增 SkillInfo、SlashPopupItemKind；重构 SlashPopupItem/SlashPopup
- `Sources/AxionCLI/Chat/Composer/ChatComposer.swift` — 新增 availableSkills 属性
- `Sources/AxionCLI/Chat/Composer/ComposerSlashPopupHandling.swift` — completeSelectedCommand→completeSelected，传入 skills
- `Sources/AxionCLI/Commands/ChatCommand.swift` — 注入 skill 列表到 composer
- `Tests/AxionCLITests/Chat/Composer/SlashPopupTests.swift` — 适配新模型 + 新增 14 个 skill 测试
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — 38-9 → done
- `_bmad-output/implementation-artifacts/38-9-slash-popup-skill-completion.md` — Status → done
