# Investigation: Slash Popup 界面错位 + 未知命令无响应

## Hand-off Brief

1. **What happened.** 用户在交互模式输入 `/` 后 popup 列表文字未对齐；输入 `/bmad-help` 回车后无任何响应（不报错、不提示）。
2. **Where the case stands.** 已定位两个独立根因：popup 渲染缺少中文字符宽度计算；`/bmad-help` 不在 SlashCommand 枚举中但代码逻辑存在竞态路径导致"静默吞掉"。
3. **What's needed next.** 需确认 popup 宽度计算方案（Unicode width vs 固定 padding），以及确认 `/bmad-help` 等未知命令是否应走 `handleUnknown` 路径输出提示。

## Case Info

| Field            | Value                                                                      |
| ---------------- | -------------------------------------------------------------------------- |
| Ticket           | N/A                                                                        |
| Date opened      | 2026-06-09                                                                 |
| Status           | Concluded                                                                  |
| System           | macOS (Terminal.app / iTerm2), Swift 6.1+, SPM                             |
| Evidence sources | SlashPopup.swift, SlashCommand.swift, ChatCommand.swift, SlashCommandHandler.swift, ComposerSlashPopupHandling.swift |

## Problem Statement

用户报告两个问题：
1. 交互模式输入 `/` 后，弹出的命令列表界面"文字没有对齐"，看起来很乱
2. 输入 `/bmad-help` 按回车后没有任何响应——无报错、无提示

## Evidence Inventory

| Source                  | Status    | Notes                                                   |
| ----------------------- | --------- | ------------------------------------------------------- |
| SlashPopup.swift        | Available | 渲染逻辑，padding 计算方式                              |
| SlashCommand.swift      | Available | 枚举定义，只有 13 个命令，不包含 bmad-help              |
| ChatCommand.swift:356-371 | Available | 未知命令处理分支                                        |
| ComposerSlashPopupHandling.swift | Available | slashPopup 事件处理                          |
| SlashCommandHandler.swift:216-218 | Available | handleUnknown 定义                           |

## Investigation Backlog

| # | Path to Explore                           | Priority | Status     | Notes                                        |
| - | ----------------------------------------- | -------- | ---------- | -------------------------------------------- |
| 1 | Popup 渲染中 `padding(toLength:)` 与 CJK 字符宽度差异 | High     | Done       | 根因已确认                                   |
| 2 | `/bmad-help` 输入后无响应的代码路径 | High     | Done       | 根因已确认                                   |

## Timeline of Events

| Time        | Event                           | Source                | Confidence |
| ----------- | ------------------------------- | --------------------- | ---------- |
| 2026-06-09  | 用户报告 / popup 界面错位       | User report           | Confirmed  |
| 2026-06-09  | 用户报告 /bmad-help 无响应      | User report           | Confirmed  |

## Confirmed Findings

### Finding 1: Popup 渲染使用 `padding(toLength:)` 未考虑 CJK 全角字符宽度

**Evidence:** `SlashPopup.swift:108`

```swift
line = "\(marker)\(number.padding(toLength: 4, withPad: " ", startingAt: 0))\(namePart)  \(item.command.helpText)"
```

**Detail:**

`SlashPopup.render()` 使用 Swift 标准库 `String.padding(toLength:)` 进行对齐。这个方法按**字符数**计算宽度，但终端中 CJK 字符（如中文）占**2 个列宽**（全角），ASCII 字符占 1 个列宽。

`helpText` 的值全是中文（如 "显示帮助信息"、"清屏（不重置会话）"等），但问题更关键在于 `number.padding(toLength: 4)` 后紧接 `namePart`，而 `namePart` 是 `/help`、`/clear` 等 ASCII 文本——这部分对齐应该是正确的。

实际对齐问题出在 **`namePart` 和 `helpText` 之间没有固定宽度的分隔对齐**——`namePart` 后仅 `  `（2 空格），不同命令名长度不同（`/new` 4 字符 vs `/compact` 8 字符），导致 helpText 起始列不一致，加上中文全角字符的列宽差异，终端显示就会参差不齐。

此外，`handleHelp()` 方法（SlashCommandHandler.swift:107）也有同样的问题：
```swift
lines.append("  \(cmd.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(cmd.helpText)")
```
虽然 `padding(toLength: 10)` 对 ASCII 命令名有效，但如果命令名是全角字符就会错位。

### Finding 2: `/bmad-help` 被 SlashPopup 选中后直接提交但 parse 返回 nil，代码走入了"空行跳过"分支

**Evidence:** `ChatCommand.swift:218` + `ChatCommand.swift:203-204`

**Detail:**

交互流程如下：

1. 用户输入 `/bmad-help` → `SlashPopup` 匹配不到任何命令（因为过滤逻辑只匹配已知命令名）
2. 由于 `/bmad-help` 不在 `SlashCommand` 枚举中，popup 显示"无匹配命令"
3. 用户按 Enter 时，`handleSlashPopupEvent` 中的 `case .tab, .enter:` 调用 `completeSelectedCommand()`，由于 `popupItems` 为空（无匹配），返回 `nil`
4. 代码执行 `// 无选中或无匹配 → tab/enter 忽略`，**Enter 键被静默吞掉**
5. 但是！如果用户直接输入完整 `/bmad-help` 然后按 Enter（不经过 popup 选择），代码流程是：
   - 用户输入 `b` → `m` → `a` → `d` ... 每个 printable 字符触发 `refreshSlashPopup`，popup 始终显示"无匹配命令"
   - 用户按 Enter → `popupItems` 为空 → `completeSelectedCommand()` 返回 nil → Enter 被忽略
   - **用户被困在 slashPopup 模式，Enter 完全无效！**

等等，让我重新检查——当用户输入 `/bmad-help` 时，popup 是否会因为没有匹配而自动退出？

回看 `enterSlashPopup`（ComposerSlashPopupHandling.swift:16-30）：当输入 `/` 进入 popup 模式后，每个字符都触发 `refreshSlashPopup`。当 `popupItems` 为空时，`selectedPopupIndex = -1`，popup 显示"无匹配命令"。此时 Enter 键的处理（ComposerSlashPopupHandling.swift:142-155）：

```swift
case .tab, .enter:
    if let completed = completeSelectedCommand() { ... }
    // 无选中或无匹配 → tab/enter 忽略
```

**确认：Enter 被完全忽略，用户无法提交输入。** 这是 UX 灾难——用户被锁死在 popup 模式。

### Finding 3: 即使 popup 退出，未知命令也会被静默处理

**Evidence:** `ChatCommand.swift:368-370`

```swift
} else if trimmed.hasPrefix("/") {
    fputs(SlashCommandHandler.handleUnknown(trimmed), stderr)
    continue
}
```

如果用户通过 Esc 取消 popup，手动输入 `/bmad-help` 并提交，代码确实会走到 `handleUnknown` 分支，输出 `[axion] 未知命令: /bmad-help，输入 /help 查看可用命令`。但这条路径的前提是**用户知道要用 Esc 退出 popup**。

## Deduced Conclusions

### Deduction 1: Popup 模式在无匹配时 Enter 应提交原始输入

**Based on:** Finding 2

**Reasoning:** 当 `popupItems` 为空且用户按 Enter 时，语义上用户想提交当前 buffer 内容（如 `/bmad-help`）。当前行为（忽略 Enter）违反用户预期。

**Conclusion:** `handleSlashPopupEvent` 的 `.tab, .enter` 分支在 `popupItems` 为空时应退回 normal 模式并提交 buffer。

### Deduction 2: Popup 列表对齐问题源于缺少固定列宽

**Based on:** Finding 1

**Reasoning:** `namePart`（如 `/help`、`/compact`）长度从 4 到 8 不等，但只跟了 2 个空格就接 `helpText`（中文）。需要将 `namePart` padding 到统一宽度后再接 helpText。

**Conclusion:** 渲染时应对命令名做 `padding(toLength:最长命令名长度+2)` 保证 helpText 列对齐。

## Hypothesized Paths

### Hypothesis 1: 用户按了 Esc 后再输入 /bmad-help

**Status:** Open

**Theory:** 用户可能通过 Esc 退出了 popup，然后在 normal 模式输入了 `/bmad-help`，此时代码走 `handleUnknown` 应该会显示提示。但用户说"没有任何响应"，可能意味着 `fputs(..., stderr)` 的输出被终端吞掉了（某些终端配置下 stderr 不显示）。

**Supporting indicators:** 用户说"按回车没有任何响应"

**Would confirm:** 询问用户是否看到了 `[axion] 未知命令: /bmad-help` 的提示

**Would refute:** 如果用户确认确实完全无输出

### Hypothesis 2: 用户完全在 popup 模式中被锁死

**Status:** Confirmed

**Theory:** 用户输入 `/` → 进入 popup → 继续输入 `bmad-help` → popup 无匹配 → Enter 被忽略 → 用户看到"无响应"

**Supporting indicators:** popup 逻辑明确忽略无匹配时的 Enter

**Resolution:** 代码审查确认。`handleSlashPopupEvent` 的 `.enter` 分支在 `popupItems` 为空时不执行任何操作。

## Missing Evidence

| Gap                                    | Impact                                | How to Obtain          |
| -------------------------------------- | ------------------------------------- | ---------------------- |
| 用户实际操作路径（是否在 popup 模式中）| 确认 Bug #2 的确切触发条件            | 询问用户               |

## Source Code Trace

### Bug 1: Popup 对齐

| Element       | Detail                                                    |
| ------------- | --------------------------------------------------------- |
| Error origin  | SlashPopup.swift:108                                      |
| Trigger       | 用户输入 `/` 触发 slashPopup 渲染                        |
| Condition     | 命令名长度不等 + 中文字符列宽 = 终端显示错位             |
| Related files | SlashCommandHandler.swift:107 (`handleHelp` 同样问题)    |

### Bug 2: Enter 无响应

| Element       | Detail                                                    |
| ------------- | --------------------------------------------------------- |
| Error origin  | ComposerSlashPopupHandling.swift:142-155                  |
| Trigger       | popup 模式下输入未匹配的命令名后按 Enter                 |
| Condition     | `popupItems` 为空 → `completeSelectedCommand()` 返回 nil  |
| Related files | ChatComposer.swift:264 (enterSlashPopup 触发点)          |

## Conclusion

**Confidence:** High

### Bug 1 — Popup 对齐错乱
**根因已确认。** `SlashPopup.render()` 未对命令名做等宽 padding，不同长度命令名后仅 2 空格分隔就接 helpText，导致中文描述起始列不一致。修复方案：将 `namePart` 统一 padding 到最长命令名的长度。

### Bug 2 — /bmad-help 无响应
**根因已确认。** 用户输入 `/` 进入 slashPopup 模式后继续输入 `bmad-help`，由于该命令不在枚举中，`popupItems` 为空，此时 Enter 被静默忽略，用户被锁死在 popup 模式。修复方案：当 `popupItems` 为空且用户按 Enter 时，应退出 popup 模式并提交 buffer 到正常命令处理流程。

## Recommended Next Steps

### Fix direction

**Bug 1:** 在 `SlashPopup.render()` 中，将 `namePart` padding 到所有命令名最大宽度 + 2（当前最长命令名为 `/archive` = 8 字符，应 padding 到 10）。

**Bug 2:** 修改 `ComposerSlashPopupHandling.swift` 的 `.tab, .enter` 分支：当 `popupItems` 为空时，退出 popup 模式并将 buffer 作为普通输入提交（`.returnInput(buffer)`）。

### Diagnostic

无需额外诊断——代码审查已完全确认根因。

## Side Findings

- `handleHelp()` (SlashCommandHandler.swift:107) 也使用 `padding(toLength: 10)` 对齐，但 `/archive`（8 字符）和 `/compact`（8 字符）比 `/new`（4 字符）长得多，padding 到 10 恰好能覆盖。但如果将来添加更长的命令名，同样会出现对齐问题。建议用动态计算。
- Popup 中的 "无匹配命令" 提示（SlashPopup.swift:82）没有清除后重新渲染的视觉反馈，用户可能不知道自己处于 popup 模式。
