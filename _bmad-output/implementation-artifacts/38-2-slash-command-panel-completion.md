---
baseline_commit: "ba62e7d"
---

# Story 38.2: Slash 命令面板与补全

Status: done

## Story

As a Axion CLI 用户,
I want 输入 `/` 时看到命令列表、描述和筛选结果,
So that 我不必记住所有 slash 命令。

## 为什么现在做

Story 38.0 已完成 `ChatComposer` raw mode 输入层，`ComposerMode.slashPopup(query:)` 已预留但未实现交互。Story 38.1 完成了视觉语义层（`ChatTheme` + `TranscriptRenderer`）。现在 Story 38.2 可以在已有 `ChatComposer` 事件循环中拦截 `/` 输入和 Tab/Up/Down/Esc 按键，利用 `ChatTheme` 的颜色系统渲染命令列表。

当前问题：
1. `/help` 是唯一发现命令的途径，用户必须记忆命令名
2. `SlashCommand` 枚举缺少 `aliases`/`acceptsArgs`/`availableDuringTask`/`availableInSide` 等元数据
3. 没有上下文感知过滤（agent 忙碌时仍显示 `/new` 等不适用命令）
4. 没有 `/` 触发的实时命令列表和筛选

## Acceptance Criteria

1. **AC1: `/` 触发命令面板** — 用户在空行或行首输入 `/` 时，composer 切换到 `slashPopup` 模式，在 prompt 行下方显示可用命令列表（编号 + 命令名 + 描述），列表根据当前上下文动态过滤。

2. **AC2: 实时筛选** — 用户继续输入字符（如 `/re`），命令列表实时过滤为只显示匹配命令（大小写不敏感前缀匹配），精确匹配优先排列。匹配字符高亮显示。

3. **AC3: 上下文感知过滤** — agent 正在执行任务时，不显示 `/resume` 等结构性命令；未来 side 会话中只显示可用命令。通过 `SlashCommandContext` struct 控制过滤维度。

4. **AC4: 命令元数据** — `SlashCommand` enum 增加计算属性：`aliases: [String]`、`acceptsArgs: Bool`、`availableDuringTask: Bool`、`availableInSide: Bool`。`/quit` 作为 `/exit` 的别名不出现在 `allCases` 中但在 `parse()` 和面板中均可用。

5. **AC5: Tab/Enter 补全** — Tab 或 Enter 补全当前高亮/唯一匹配的命令名。补全后如果命令 `acceptsArgs`，光标停在命令名后空格处等待参数输入；如果不接受参数，直接提交。

6. **AC6: 键盘导航** — Up/Down 在命令列表中移动高亮项。高亮项的描述完整显示。Enter 选中高亮项。

7. **AC7: Esc 取消** — Esc 取消 slash popup，恢复进入前原始草稿内容（通过 `ComposerDraft.restore()`），回到 `ComposerMode.normal`。

8. **AC8: 非 TTY 降级** — 非 TTY 模式下不触发 slash popup（无 raw mode，无按键拦截）。`/help` 仍正常工作。用户仍可手动输入 `/` + 命令名。

9. **AC9: NFR — 命令列表渲染** — CaseIterable 遍历 + 过滤 + 输出 < 50ms。命令数量少（< 20），渲染开销可忽略。

## Tasks / Subtasks

- [x] Task 1: 扩展 `SlashCommand` 元数据（AC4）
  - [x] 添加 `aliases: [String]` 计算属性（`/exit` → `["quit"]`，其余为空数组）
  - [x] 添加 `acceptsArgs: Bool` 计算属性（`.model` → true, `.resume` → true, 其余 → false）
  - [x] 添加 `availableDuringTask: Bool` 计算属性（`.help`/`.cost`/`.config`/`.clear`/`.exit` → true，`.resume` → false，默认 true）
  - [x] 添加 `availableInSide: Bool` 计算属性（全部 true — side 会话功能延后到 38.8，预留字段）
  - [x] 添加 `allNames: [String]` 计算属性（rawValue + aliases）

- [x] Task 2: 创建 `SlashCommandContext` struct（AC3）
  - [x] 定义 `SlashCommandContext`：`isAgentBusy: Bool`、`isSideSession: Bool`
  - [x] 添加 `filter(_ commands: [SlashCommand]) -> [SlashCommand]` 方法
  - [x] agent 忙碌时排除 `availableDuringTask == false` 的命令
  - [x] side 会话时排除 `availableInSide == false` 的命令
  - [x] 纯 struct，零外部依赖

- [x] Task 3: 创建 `SlashPopup` struct（AC1/AC2/AC5/AC6/AC9）
  - [x] 定义 `SlashPopupItem`：`command: SlashCommand`、`matchRange: Range<String.Index>?`
  - [x] 实现 `filter(query:context:) -> [SlashPopupItem]` — 大小写不敏感前缀匹配 + 精确匹配优先 + 高亮 range 计算
  - [x] 实现 `render(items:selectedIndex:theme:) -> String` — 编号列表 + 描述 + 选中标记 + 匹配高亮
  - [x] 纯 struct + 纯函数，所有方法返回 String，零 I/O
  - [x] 通过 `ChatTheme` 获取颜色（复用 38.1 的颜色降级链）

- [x] Task 4: 集成到 `ChatComposer` 事件循环（AC1/AC5/AC6/AC7）
  - [x] 修改 `readRawLoop` 中 `.printable` 分支：检测 buffer 为空或仅 `/` 时输入 `/` 触发 `enterSlashPopup()`
  - [x] 实现 `enterSlashPopup()`：`saveDraft()` → 设置 `mode = .slashPopup(query: "/")` → 渲染命令列表
  - [x] 在 `slashPopup` 模式下拦截按键：
    - [x] `.printable` → 追加到 query → 重新过滤 → 重新渲染
    - [x] `.backspace` → 如果 query 只有 `/`，取消 popup 恢复 draft；否则删除 query 最后一个字符
    - [x] `.up` / `.down` → 移动 `selectedPopupIndex`
    - [x] `.tab` / `.enter` → 补全选中命令（`acceptsArgs` → 留在编辑模式；否则直接提交）
    - [x] `.escape` → 恢复 draft → 回到 normal
  - [x] 添加 `slashPopupState` 内部属性跟踪：`popupItems: [SlashPopupItem]`、`selectedPopupIndex: Int`

- [x] Task 5: 集成 `SlashCommandContext` 到 `ChatCommand`（AC3）
  - [x] 在 `ChatCommand` REPL 循环中，`composer.readInput()` 前设置当前上下文
  - [x] 通过注入闭包或直接属性传递 `isAgentBusy` 状态给 composer
  - [x] agent.stream() 运行期间标记 `isAgentBusy = true`，完成后恢复 `false`

- [x] Task 6: 编写单元测试（AC1–AC9）
  - [x] `SlashCommandMetadataTests`：验证每个命令的 aliases/acceptsArgs/availableDuringTask/availableInSide
  - [x] `SlashCommandContextTests`：验证 isAgentBusy/isSideSession 过滤逻辑
  - [x] `SlashPopupTests`：
    - [x] 空查询返回所有可用命令
    - [x] `/re` 过滤返回 `/resume`
    - [x] 精确匹配优先排列
    - [x] 大小写不敏感匹配
    - [x] render 输出包含编号、命令名、描述、选中标记
    - [x] 匹配字符高亮（ANSI 码包含）
    - [x] 无匹配时输出"无匹配命令"提示
  - [x] `ChatComposerSlashPopupTests`（使用 MockKeyReader）：
    - [x] 输入 `/` 触发 slashPopup 模式
    - [x] 继续输入 `re` 过滤列表
    - [x] Tab 补全选中命令
    - [x] Enter 选中命令并提交（acceptsArgs=false 时）
    - [x] Enter 选中命令并留空参数（acceptsArgs=true 时）
    - [x] Up/Down 移动选中
    - [x] Esc 取消恢复原始草稿
    - [x] Backspace 从 `/re` 退回到 `/r`
    - [x] Backspace 从 `/` 取消 popup
  - [x] 使用 Swift Testing 框架

## Dev Notes

### 核心架构决策

**四层架构（与 Codex 对齐）：**

1. **定义层**（`SlashCommand.swift`）：枚举 + 元数据（aliases/acceptsArgs/availableDuringTask/availableInSide）
2. **过滤层**（`SlashCommandContext.swift`）：上下文感知过滤（isAgentBusy/isSideSession）
3. **UI 层**（`SlashPopup.swift`）：编号列表渲染 + 匹配高亮 + 选中标记
4. **交互层**（`ChatComposer.swift`）：按键拦截 + 模式切换 + 补全逻辑

**REPL 模式下的"弹出"方案：**

Codex 用全屏 TUI overlay 弹出命令列表。Axion 是行式 REPL，采用**追加输出**方案：
- slash popup 触发时，在 prompt 行下方**追加输出**编号命令列表（append-only）
- 用户输入筛选文字时，先清除之前的列表输出（`\u{1B}[A` 上移 + `\u{1B}[K` 清行），再重新输出过滤后的列表
- 这种方案不需要覆盖已有 transcript 内容，只操作当前可见的"弹出区域"

**清除列表输出的策略：**
- 记录 popup 渲染的行数 `popupRenderedLines`
- 重新渲染前：输出 `\u{1B}[\(popupRenderedLines)A` 上移 + 每行 `\u{1B}[K` 清行
- 选中/取消时：清除弹出区域

### 与现有代码的关系

**`SlashCommand.swift`（主要修改）：**
当前结构：`CaseIterable` enum + `parse()` + `parseArgument()` + `helpText`

修改内容：
- 增加 4 个计算属性：`aliases`、`acceptsArgs`、`availableDuringTask`、`availableInSide`
- 增加 `allNames` 计算属性（rawValue + aliases）
- `parse()` 不修改（已支持 `/quit` → `.exit`）
- `allCases` 不修改（`/quit` 不在其中，`/help` 的输出通过 `handleHelp()` 控制）

**`ChatComposer.swift`（主要修改）：**
当前 `readRawLoop` 中 `.printable` 和快捷键处理：
- `.printable` → `insertChar` + `refreshDisplay`：需要在 buffer 为 `/` 时检测并触发 slashPopup
- `.up` / `.down` / `.tab` → 当前 `break`（不吞键）：在 slashPopup 模式下实现导航/补全
- `.escape` → 当前清空或恢复 draft：slashPopup 模式下恢复 draft + 回到 normal

交互流程：
```
用户输入 "/" → saveDraft() → mode = .slashPopup(query: "/")
  → 渲染完整命令列表
用户输入 "r" → query 更新为 "/r" → 过滤列表 → 重新渲染
用户输入 "e" → query 更新为 "/re" → 过滤列表 → 重新渲染（只剩 /resume）
用户按 Tab → 补全为 "/resume "（acceptsArgs=true，留空参数区）
用户输入 "chat-abc" → buffer = "/resume chat-abc"
用户按 Enter → 提交
```

**`SlashCommandHandler.swift`（微调）：**
- `handleHelp()` 已能正确输出命令列表，本 Story 不修改其逻辑
- 但可优化为使用 `SlashCommandContext` 过滤后再显示（让 /help 也上下文感知），这是增强项不是必须

**`ChatCommand.swift`（集成点）：**
- 在 REPL 循环中，`agent.stream()` 运行期间传递 `isAgentBusy` 状态
- 注入方式：通过 `composer.setSlashContext(SlashCommandContext(isAgentBusy: true))` 或闭包
- agent turn 结束后重置为 `SlashCommandContext(isAgentBusy: false)`

**`ChatTheme.swift`（复用，不修改）：**
- 复用 `TerminalColorProfile` 和 `ChatTheme` 的颜色系统
- slash popup 的匹配高亮使用 `ChatTheme` 的 cyan/bold 样式
- 选中行使用 dim 或反转色

### 模块边界

**新增文件：**
```
Sources/AxionCLI/Chat/Composer/SlashPopup.swift          # ~150 行：过滤 + 渲染纯函数
Sources/AxionCLI/Chat/Composer/SlashCommandContext.swift  # ~40 行：上下文过滤 struct
```

**修改文件：**
```
Sources/AxionCLI/Chat/SlashCommand.swift                  # 增加元数据计算属性
Sources/AxionCLI/Chat/Composer/ChatComposer.swift          # slashPopup 模式交互逻辑
Sources/AxionCLI/Commands/ChatCommand.swift                # 注入 isAgentBusy 上下文
```

**保留不动：**
```
Sources/AxionCLI/Chat/SlashCommandHandler.swift            # 不修改（/help 输出逻辑保持原样）
Sources/AxionCLI/Chat/Composer/ComposerMode.swift           # 不修改（.slashPopup 已定义）
Sources/AxionCLI/Chat/Composer/ComposerDraft.swift          # 不修改（snapshot/restore 已可用）
Sources/AxionCLI/Chat/Composer/KeyEvent.swift               # 不修改
Sources/AxionCLI/Chat/Composer/KeyEventReader.swift         # 不修改
Sources/AxionCLI/Chat/Theme/*                               # 不修改（复用颜色系统）
Sources/AxionCLI/Chat/ChatOutputFormatter.swift             # 不修改
```

**新增测试文件：**
```
Tests/AxionCLITests/Chat/Composer/SlashPopupTests.swift          # ~150 行
Tests/AxionCLITests/Chat/Composer/SlashCommandContextTests.swift  # ~60 行
Tests/AxionCLITests/Chat/SlashCommandMetadataTests.swift          # ~80 行（新增元数据测试）
Tests/AxionCLITests/Chat/Composer/ChatComposerSlashPopupTests.swift # ~200 行
```

### 绝对禁止

- **不能修改 `SlashCommandHandler` 的核心逻辑** — `/help`/`/cost`/`/compact`/`/model`/`/resume`/`/config`/`/exit` 的处理逻辑不变。slash popup 只改变命令的**发现方式**，不改变命令的**执行路径**。
- **不能修改 `ComposerMode` enum** — `.slashPopup(query:)` 已由 Story 38.0 定义，直接使用。
- **不能修改 `ComposerDraft`** — `snapshot()`/`restore()` 已可用。
- **不能修改 `ChatTheme` 或 `TerminalColorProfile`** — 复用现有颜色系统，不新增颜色。
- **不能在 `SlashPopup` 或 `SlashCommandContext` 中做 I/O** — 纯函数/struct，所有渲染返回 String。
- **不能引入新的第三方依赖**
- **不能破坏现有 `SlashCommandTests`** — 新增元数据测试不改变已有测试断言。

### Slash Popup 交互状态机

```
ComposerMode.normal（buffer 为空或只有 "/"）
  ↓ [输入 "/"]
saveDraft() → mode = .slashPopup(query: "/")
  → 渲染完整命令列表
  ↓
ComposerMode.slashPopup(query: "/re")
  ↓ [.printable → query 更新 → 过滤 → 重新渲染]
  ↓ [.up/.down → 移动 selectedIndex → 重新渲染]
  ↓ [.tab/.enter → 补全选中命令]
  ↓ [.escape → restoreDraft() → mode = .normal]
  ↓ [.backspace → query 退格，如果只剩 "/" 再 backspace → 取消 popup]
```

### Codex 架构参考

| Codex 文件 | 行数 | 参考内容 | Axion 适配 |
|-----------|------|---------|-----------|
| `slash_command.rs` | ~800 | `SlashCommand` 枚举 + strum 宏驱动元数据 | Swift `CaseIterable` + 计算属性 |
| `bottom_pane/slash_commands.rs` | ~300 | `BuiltinCommandFlags` 特性门控 | `SlashCommandContext` struct |
| `bottom_pane/command_popup.rs` | ~200 | `CommandPopup` Widget 渲染 | `SlashPopup` 纯函数渲染 |
| `bottom_pane/chat_composer/slash_input.rs` | ~150 | 输入解析和补全逻辑 | ChatComposer 事件循环中拦截 |
| `chatwidget/slash_dispatch.rs` | ~400 | 路由分发 | 复用现有 `SlashCommandHandler.handle()` |

**Codex 与 Axion 的关键差异：**
- Codex 用全屏 TUI overlay 弹出 → Axion 用行式追加输出 + ANSI 清行
- Codex 的 strum 宏自动生成元数据 → Axion 用 Swift 计算属性手动定义
- Codex 支持模糊匹配 → Axion 用前缀匹配（命令数量少，前缀匹配足够）

### 匹配算法

```swift
// 大小写不敏感前缀匹配
func matches(query: String, command: SlashCommand) -> Bool {
    let q = query.dropFirst()  // 去掉开头的 "/"
    guard !q.isEmpty else { return true }  // 只有 "/" 返回全部
    let lowerQ = q.lowercased()
    // 精确匹配 rawValue
    if command.rawValue.lowercased().hasPrefix(lowerQ) { return true }
    // 别名匹配
    return command.aliases.contains { $0.lowercased().hasPrefix(lowerQ) }
}

// 排序：精确匹配优先
func sortPriority(query: String, items: [SlashPopupItem]) -> [SlashPopupItem] {
    items.sorted { a, b in
        let aExact = a.command.rawValue.lowercased() == "/" + query.lowercased()
        let bExact = b.command.rawValue.lowercased() == "/" + query.lowercased()
        if aExact != bExact { return aExact }
        return a.command.rawValue < b.command.rawValue
    }
}
```

### Epic 37 回顾教训（必须遵循）

1. **L1: 接线验证是独立任务** — `SlashPopup` 的每个渲染方法必须在 `ChatComposer` 的 slashPopup 模式分支中有对应调用点。`SlashCommandContext` 的过滤必须在 `SlashPopup.filter()` 中被调用。用 `// AC#` 注释标注。

2. **L4: 纯函数 + DI 模式** — `SlashPopup` 和 `SlashCommandContext` 是纯 struct，零 I/O。`ChatTheme` 通过参数注入。测试中通过注入覆盖。

3. **C3: AC10 未知命令是死代码的教训** — 确保新增的 `aliases`/`acceptsArgs` 等元数据在 `SlashPopup` 和 `SlashCommandContext` 中有实际使用，不只是定义。

4. **TD4 消除双份逻辑** — `SlashPopup` 的过滤逻辑与 `SlashCommandHandler.handleHelp()` 的列表生成不应重复。`handleHelp()` 可选地改为调用 `SlashPopup` 的渲染方法（增强项），但核心是 `SlashPopup` 自身完整。

5. **Story 38.0 Review H1 教训** — 在 ChatComposer 的事件循环中添加 slashPopup 分支时，注意不要遗漏任何 KeyEvent case，特别是 bracket paste（slashPopup 模式下应忽略粘贴或直接取消 popup）。

### 测试策略

**单元测试（Mock 策略）：**

| 组件 | Mock 策略 | 理由 |
|------|---------|------|
| `SlashCommand` 元数据 | 直接测试（纯计算属性） | 无外部依赖 |
| `SlashCommandContext` | 直接测试（纯 struct） | 无外部依赖 |
| `SlashPopup` | 直接测试（纯函数，返回 String） | 无 I/O |
| `ChatComposer` slashPopup 交互 | MockKeyReader 注入按键序列 + Mock writeStdout 捕获输出 | 验证完整交互流程 |

**关键测试场景：**
- `SlashCommand.model.acceptsArgs == true`
- `SlashCommand.exit.aliases == ["quit"]`
- `SlashCommand.resume.availableDuringTask == false`
- `SlashCommandContext(isAgentBusy: true)` 过滤掉 `/resume`
- 空查询 `/` 返回所有 `availableDuringTask == true` 的命令
- `/re` 只返回 `/resume`
- `/c` 返回 `/clear`、`/compact`、`/cost`、`/config`（前缀匹配）
- 渲染输出包含编号（`1.`）、命令名、描述、匹配高亮
- 选中标记（如 `▶` 或 `>`）
- ChatComposer: 输入 `/` → writeStdout 包含命令列表
- ChatComposer: 输入 `/re` → writeStdout 只包含 `/resume`
- ChatComposer: Tab 补全 → buffer 更新为 `/resume `
- ChatComposer: Esc → draft 恢复 → mode 回到 normal
- ChatComposer: Up/Down → selectedIndex 变化

### Project Structure Notes

- 新文件放在 `Sources/AxionCLI/Chat/Composer/` 目录（与 ChatComposer 同级）
- 测试目录 `Tests/AxionCLITests/Chat/Composer/` 镜像源结构
- `SlashCommandMetadataTests` 放在 `Tests/AxionCLITests/Chat/`（与现有 `SlashCommandTests.swift` 同目录）
- 文件命名遵循 PascalCase
- Import 顺序：`import Foundation`

### References

- [Source: docs/epics/epic-38-terminal-conversation-ux.md#Story 38.2]
- [Source: docs/epics/epic-38-terminal-conversation-ux.md#Codex 架构模式总结 CM-5 特性门控]
- [Source: _bmad-output/implementation-artifacts/38-0-lightweight-composer-input-foundation.md#Dev Notes]
- [Source: _bmad-output/implementation-artifacts/38-1-conversation-visual-semantic-layer.md#Dev Notes]
- [Source: _bmad-output/implementation-artifacts/epic-37-retro-2026-06-08.md#Lessons Learned]
- [Source: Sources/AxionCLI/Chat/SlashCommand.swift]
- [Source: Sources/AxionCLI/Chat/SlashCommandHandler.swift]
- [Source: Sources/AxionCLI/Chat/Composer/ChatComposer.swift]
- [Source: Sources/AxionCLI/Chat/Composer/ComposerMode.swift]
- [Source: Sources/AxionCLI/Chat/Composer/ComposerDraft.swift]
- [Source: Sources/AxionCLI/Chat/Composer/KeyEvent.swift]
- [Source: Sources/AxionCLI/Chat/Theme/ChatTheme.swift]
- [Source: Sources/AxionCLI/Chat/Theme/TerminalColorProfile.swift]
- [Source: Sources/AxionCLI/Commands/ChatCommand.swift]
- [Source: Tests/AxionCLITests/Chat/SlashCommandTests.swift]
- Codex 参考：`slash_command.rs`（枚举 + 元数据）、`bottom_pane/slash_commands.rs`（过滤门控）、`bottom_pane/command_popup.rs`（渲染）、`bottom_pane/chat_composer/slash_input.rs`（补全逻辑）

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

### Completion Notes List

- ✅ Task 1: 在 `SlashCommand.swift` 添加 5 个计算属性：`aliases`、`acceptsArgs`、`availableDuringTask`、`availableInSide`、`allNames`。`/quit` 作为 `/exit` 别名在 parse() 和面板中均可用，不出现在 allCases 中。
- ✅ Task 2: 创建 `SlashCommandContext.swift` — 纯 struct，零依赖。`filter()` 方法根据 isAgentBusy/isSideSession 过滤不可用命令。agent 忙碌时排除 `/resume`。
- ✅ Task 3: 创建 `SlashPopup.swift` — 纯 struct + 纯函数。`filter()` 实现大小写不敏感前缀匹配 + 精确匹配优先 + 别名匹配。`render()` 输出编号列表 + 描述 + 选中标记 ▶ + 匹配高亮（ANSI cyan+bold）。通过 ChatTheme 颜色降级链适配终端。
- ✅ Task 4: 集成到 `ChatComposer.swift` 事件循环。slashPopup 模式下拦截所有按键：printable 继续筛选、backspace 退格/取消、up/down 导航、tab/enter 补全、escape 取消恢复 draft。使用 ANSI 上移+清行实现行式追加输出方案。
- ✅ Task 5: 在 `ChatCommand.swift` REPL 循环中，agent.stream() 前设置 `slashContext.isAgentBusy = true`，完成后恢复 `false`。
- ✅ Task 6: 编写 4 个测试文件，共 58 个新测试用例。全部测试通过（含回归），零失败。
- 🐛 修复：enterSlashPopup 保存 draft 时需保存 "/" 插入前的状态（空字符串），而非插入后的 "/"。

### File List

**新增文件：**
- Sources/AxionCLI/Chat/Composer/SlashPopup.swift
- Sources/AxionCLI/Chat/Composer/SlashCommandContext.swift
- Tests/AxionCLITests/Chat/SlashCommandMetadataTests.swift
- Tests/AxionCLITests/Chat/Composer/SlashCommandContextTests.swift
- Tests/AxionCLITests/Chat/Composer/SlashPopupTests.swift
- Tests/AxionCLITests/Chat/Composer/ChatComposerSlashPopupTests.swift

**修改文件：**
- Sources/AxionCLI/Chat/SlashCommand.swift
- Sources/AxionCLI/Chat/Composer/ChatComposer.swift
- Sources/AxionCLI/Commands/ChatCommand.swift
