---
title: 'ChatComposer 多行编辑：Shift+Enter 换行 + Up/Down 行间导航 + Home/End'
type: 'feature'
created: '2026-06-10'
status: 'done'
baseline_commit: 'c9daf59659a2eb8b910ec059cca90e5de53fbc93'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** ChatComposer 当前无法在输入中手动换行（Enter 直接提交），且粘贴多行文本后 Up/Down 被历史导航占用，无法在行间移动光标去编辑。用户也无法快速跳到行首/行尾。

**Approach:** 三个联动改动：(1) 通过 Kitty 键盘协议 CSI u 模式检测 Shift+Enter 插入换行符；(2) 参考 CC 行为——单行 buffer 时 Up/Down 走历史，多行时先在行间移动，仅在首行 Up / 末行 Down 溢出时翻历史；(3) 新增 Home/End 支持。

## Boundaries & Constraints

**Always:**
- 不支持 CSI u 的终端（大多数默认配置），Shift+Enter fallback 为普通 Enter（提交），用户仍可用 `\`+Enter 续行或 bracket paste 输入多行
- 进入/退出 raw mode 时正确启用/禁用 CSI u 模式，异常退出不残留终端状态
- 反斜杠续行、bracket paste、Ctrl+C 中断、prefill、draft 恢复等现有功能无回归
- 所有显示使用 `\r\n`（OPOST 禁用），refreshDisplay 多行感知重绘正确

**Ask First:** 无（所有设计决策已确认）

**Never:**
- 不改变 `Enter` = 提交 的语义
- 不修改 AxionCore 模块
- 不修改 AxionBar / AxionHelper
- 不引入新的第三方依赖

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Shift+Enter 换行（CSI u 模式） | buffer="hello", 按 Shift+Enter | buffer="hello\n", cursor 移到新行开头 | N/A |
| Shift+Enter 不支持时 | 终端未启用 CSI u | Shift+Enter 等同 Enter，正常提交 | 无错误，用户无感 |
| 多行 Up 行间移动 | buffer="line1\nline2", 光标在 line2 | 光标移到 line1 对应列位置 | N/A |
| 多行首行 Up 溢出 | buffer="line1\nline2", 光标在 line1 | 触发历史导航（older） | N/A |
| 多行末行 Down 溢出 | buffer="line1\nline2", 光标在 line2 | 触发历史导航（newer） | N/A |
| 单行 Up/Down | buffer="hello" (单行无 \n) | Up=历史 older, Down=历史 newer（与当前行为一致） | N/A |
| Home 键 | 光标在行中间 | 跳到当前行首 | N/A |
| End 键 | 光标在行首 | 跳到当前行尾 | N/A |
| Ctrl+A / Ctrl+E | 光标在行中间/行尾 | Ctrl+A=Home, Ctrl+E=End | N/A |
| Bracket paste 多行后编辑 | 粘贴 3 行文本 | Up/Down 在 3 行间移动，首行 Up 翻历史 | N/A |

</frozen-after-approval>

## Code Map

- `Sources/AxionCLI/Chat/Composer/KeyEvent.swift` -- KeyEvent 枚举定义，需新增 `.shiftEnter`、`.home`、`.end` case
- `Sources/AxionCLI/Chat/Composer/KeyEventReader.swift` -- termios raw mode 管理，需添加 CSI u 模式启用/禁用
- `Sources/AxionCLI/Chat/Composer/KeyEventReader+EscapeParsing.swift` -- CSI 序列解析，需解析 CSI u 格式（`\x1b[13;2u`）、Home/End 序列
- `Sources/AxionCLI/Chat/Composer/ChatComposer.swift` -- 主事件循环，需修改 `.enter`/`.up`/`.down` 处理逻辑，新增 `.shiftEnter`/`.home`/`.end` 分支
- `Sources/AxionCLI/Chat/Composer/ChatComposer+DisplayHelpers.swift` -- display helpers，需新增行间光标移动辅助方法
- `Sources/AxionCLI/Chat/Composer/ComposerHistoryNavigation.swift` -- 历史导航，需与多行行间移动协调
- `Tests/AxionCLITests/Chat/Composer/ChatComposerTests.swift` -- 主测试文件
- `Tests/AxionCLITests/Chat/Composer/KeyEventTests.swift` -- KeyEvent 解析测试
- `Tests/AxionCLITests/Chat/Composer/DisplayHelpersTests.swift` -- Display helper 测试

## Tasks & Acceptance

**Execution:**

- [ ] `KeyEvent.swift` -- 新增 `case shiftEnter`、`case home`、`case end` 到 KeyEvent 枚举；Equatable 自动合成

- [ ] `KeyEventReader+EscapeParsing.swift` -- 在 `parseCSITilde()` 中新增 Home (param=1 → `\x1b[1~`) 和 End (param=4 → `\x1b[4~`) 映射；在 `parseCSI()` 中新增终结字节 `0x75`（'u'）分支处理 CSI u 格式：解析 `params` 中的 `keycode;modifiers`，当 keycode=13 且 modifiers 含 shift(位1) 时返回 `.shiftEnter`，当 keycode=72 且 modifiers 含 shift 时返回 `.home`（Shift+Home），当 keycode=76 且 modifiers 含 shift 时返回 `.end`（Shift+End）；无修饰的 Home/End 也通过 CSI u keycode 72/76 解析。在 `parseSS3()` 中新增 `0x48`（'H'→Home）、`0x46`（'F'→End）映射

- [ ] `KeyEventReader.swift` -- 新增 `enableKittyKeyboard()` 和 `disableKittyKeyboard()` 方法；`enableKittyKeyboard()` 发送 `\x1b[>9u`（flags=9: disambiguate + report all keys as escape codes）；`disableKittyKeyboard()` 发送 `\x1b[<u`（reset）；在 `create()` 中 raw mode 设置成功后调用 enable，在 `restore()` 中先 disable 再恢复 termios；新增 `static func applyKittyFlags(_ flags: Int) -> [UInt8]` 生成 CSI u 序列

- [ ] `ChatComposer+DisplayHelpers.swift` -- 新增 `currentLineIndex(cursor:buffer:) -> Int` 计算光标所在行号（0-based）；新增 `lineStartOffset(lineIndex:buffer:) -> Int` 和 `lineEndOffset(lineIndex:buffer:) -> Int`；新增 `moveCursorToLine(_ lineIndex:Int, inBuffer:buffer:, prompt:String)` 计算新光标位置并调用 refreshDisplay

- [ ] `ChatComposer.swift` -- 在 `.enter` case 之前新增 `.shiftEnter` 分支：在 buffer 光标位置插入 `\n`，cursor 后移，refreshDisplay；重写 `.up` 和 `.down` 逻辑：判断 `buffer.contains("\n")`，是则计算当前行号，多行中间行 → 行间移动，首行 Up / 末行 Down → 调用 navigateHistory；单行 buffer 保持当前历史导航逻辑不变；新增 `.home` 分支：计算当前行首 offset，移动 cursor；新增 `.end` 分支：计算当前行尾 offset，移动 cursor；在 `.ctrl("a")` 和 `.ctrl("e")` 的 KeyEventReader 解析旁确保 Composer 层面也映射到 Home/End 行为（Ctrl+A 已在 KeyEventReader 层返回 `.ctrl("a")`，在 Composer 循环 default 分支前新增 `.ctrl("a")` → Home 行为、`.ctrl("e")` → End 行为）

- [ ] `Tests/AxionCLITests/Chat/Composer/KeyEventTests.swift` -- 新增测试：CSI u Shift+Enter 解析（`\x1b[13;2u`）、CSI u plain Enter 解析（`\x1b[13u`）、Home (`\x1b[1~`) 和 End (`\x1b[4~`)、SS3 Home (`\x1bOH`) 和 End (`\x1bOF`)、CSI u Home/End

- [ ] `Tests/AxionCLITests/Chat/Composer/ChatComposerTests.swift` -- 新增测试：shiftEnter 插入换行、shiftEnter 后继续输入并 Enter 提交、多行 Up/Down 行间移动、多行首行 Up 溢出到历史、多行末行 Down 溢出到历史、Home/End 在单行和多行的行为、Ctrl+A/Ctrl+E 行为

**Acceptance Criteria:**

- Given CSI u 模式终端, when 用户按 Shift+Enter, then buffer 中插入 `\n` 并正确显示多行
- Given 非 CSI u 终端, when 用户按 Shift+Enter, then 行为等同于 Enter 提交（无报错无残留）
- Given 多行 buffer "line1\nline2" 且光标在 line2, when 按 Up, then 光标移到 line1
- Given 多行 buffer "line1\nline2" 且光标在 line1, when 按 Up, then 触发历史导航
- Given 单行 buffer, when 按 Up/Down, then 直接触发历史导航（与当前行为一致）
- Given 光标在行中间, when 按 Home 或 Ctrl+A, then 光标跳到当前行首
- Given 光标在行首, when 按 End 或 Ctrl+E, then 光标跳到当前行尾
- Given 已有功能（bracket paste, 反斜杠续行, Ctrl+C, Esc, 历史搜索）, when 正常使用, then 无回归

## Spec Change Log

## Design Notes

**Kitty 键盘协议 CSI u 模式：**
- 启用：`\x1b[>9u`（flags=9 = disambiguate(1) + report-all-keys(8)）
- 禁用：`\x1b[<u`（reset to legacy mode）
- 在 raw mode 中 `ISIG` 已禁用，Ctrl+C 由 `0x03` 字节捕获，不受 CSI u 影响
- 不支持 CSI u 的终端会忽略 `\x1b[>9u` 序列，Shift+Enter 仍发送 `0x0D`（等同 Enter），无副作用

**CSI u 编码格式：** `\x1b[keycode;event_type;modifiers u`
- event_type: 1=press, 2=repeat, 3=release；仅处理 1（press）
- modifiers: 位掩码 — bit0=shift, bit1=alt, bit2=ctrl, bit3=super
- 示例：Shift+Enter = `\x1b[13;1;2u` 或简写 `\x1b[13;2u`（省略 event_type）

**多行 Up/Down 决策树：**
```
buffer 含 \n?
├─ 否 → 当前行为（空 buffer 或 historyIndex>=0 时历史导航）
└─ 是 → 计算当前行号 (0-based)
    ├─ Up 且 currentLine > 0 → 移到上一行
    ├─ Up 且 currentLine == 0 → navigateHistory(.older)
    ├─ Down 且 currentLine < lastLine → 移到下一行
    └─ Down 且 currentLine == lastLine → navigateHistory(.newer)
```

## Verification

**Commands:**
- `swift build` -- expected: 零错误零警告
- `swift test --filter "AxionCLITests.Chat.Composer"` -- expected: 所有测试通过（含新增测试）
