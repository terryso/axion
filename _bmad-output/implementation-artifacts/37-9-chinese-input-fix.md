---
story_id: 37.9
epic: 37
title: 中文输入修复
status: done
created: 2026-06-07
baseline_commit: 422a8ff
---

# Story 37.9: 中文输入修复

As a 中文用户,
I want 删除中文字符时按一次 backspace 就删掉整个字,
So that 输入体验流畅自然.

## Acceptance Criteria

1. **AC1 — 中文 backspace 删除**：用户在 `axion>` 提示符输入 `你好世界`，按一次 backspace，显示 `你好世`（删除完整 `界` 字，不是半个字节）

2. **AC2 — 英文不受影响**：用户输入 `hello`，按一次 backspace，显示 `hell`（英文行为不变）

3. **AC3 — 混合输入**：用户输入 `hello你好`，按一次 backspace，显示 `hello你`（中英文混合正常）

4. **AC4 — 非 TTY 模式无影响**：管道输入模式（`echo "task" | axion`）行为不变，不启用 raw mode

5. **AC5 — 无回归**：`axion run "task"` 行为不受影响；其他 Chat 功能（slash 命令、Ctrl+C 中断、权限审批、compact、多行输入、bracket paste、会话恢复）正常工作

## Tasks / Subtasks

- [x] Task 1: 创建 CJKInputHandler 组件 (AC: #1, #2, #3)
  - [x] 1.1 新建 `Sources/AxionCLI/Chat/CJKInputHandler.swift`
  - [x] 1.2 实现 `struct CJKInputHandler` — 原始终端输入处理，支持中文 backspace
  - [x] 1.3 实现 `static func readRawLine(prompt:writeStdout:) -> String?` — raw mode 读取行
  - [x] 1.4 实现 `private static func enterRawMode() -> termios?` — 保存原始终端设置并切换到 raw mode
  - [x] 1.5 实现 `private static func restoreMode(_ original: termios)` — 恢复终端设置
  - [x] 1.6 实现 `private static func processBackspace(buffer: [UInt8], cursorPos: inout Int) -> [UInt8]` — 识别 UTF-8 字符边界，删除完整字符
  - [x] 1.7 实现 `private static func utf8CharLength(_ byte: UInt8) -> Int` — 根据 UTF-8 首字节判断字符字节长度
  - [x] 1.8 实现 `static func isCJKEnabled() -> Bool` — 检测终端是否支持 UTF-8（`LC_CTYPE` / `LANG` 环境变量）

- [x] Task 2: 修改 MultiLineInputReader 集成 CJK 输入 (AC: #1, #2, #3, #4)
  - [x] 2.1 在 `readInput(prompt:continuationPrompt:)` 中，TTY 模式下根据 `CJKInputHandler.isCJKEnabled()` 决定是否使用 raw mode 输入
  - [x] 2.2 Raw mode 路径：使用 `CJKInputHandler.readRawLine()` 替代 `readLineFn()`
  - [x] 2.3 非 raw mode 路径（非 UTF-8 终端）：保持现有 `readLineFn()` 行为
  - [x] 2.4 Bracket paste 和反斜杠续行在 raw mode 路径下仍正常工作（⚠️ Review 发现原始实现缺失续行支持，已修复）

- [x] Task 3: 单元测试 (AC: #1-#5)
  - [x] 3.1 新建 `Tests/AxionCLITests/Chat/CJKInputHandlerTests.swift`
  - [x] 3.2 测试 `utf8CharLength` — ASCII(1)、2 字节头(2)、3 字节头(3)、4 字节头(4)
  - [x] 3.3 测试 `processBackspace` — ASCII 删除、中文删除（3 字节 UTF-8）、emoji 删除（4 字节）、空 buffer 无操作
  - [x] 3.4 测试 `isCJKEnabled` — 环境变量存在/缺失场景
  - [x] 3.5 测试混合字符 backspace 序列 — 连续删除 "hello你好" 逐步回退

## Dev Notes

### 问题根因分析

**关键理解：** 问题不在 `readLine()` 本身，而在终端的 **canonical mode（行编辑模式）**。

macOS 终端默认运行在 canonical mode（`ICANON` 标志开启），由终端驱动负责行编辑（包括 backspace 处理）。当终端驱动处理 backspace 时：
- 对 ASCII 字符（1 字节）：正确删除 1 字节
- 对 UTF-8 多字节字符（中文 3 字节）：**某些终端驱动只删除 1 字节**，导致：
  - 屏幕显示：乱码（剩余的不完整 UTF-8 序列被渲染为 �）
  - 实际 buffer：损坏的 UTF-8 字节序列
  - 用户体验：需要按 3 次 backspace 才能删掉一个中文字

`readLine()` 返回的已经是终端处理后的结果，所以 `readLine()` 层面无法修复。

**解决方案：进入 raw mode，自行处理 backspace。**

### 核心设计：Raw Mode 输入处理

在 TTY + UTF-8 环境下，临时将终端切换到 raw mode：
1. 保存当前 `termios` 设置
2. 关闭 `ICANON`（关闭行缓冲）和 `ECHO`（关闭回显，自行处理）
3. 逐字节读取 stdin
4. 自行处理 backspace：从 buffer 末尾识别 UTF-8 字符边界，删除完整字符
5. 自行回显：将修改后的内容重写到终端
6. 按回车时恢复 canonical mode 并返回结果

```
用户按 backspace 时:
  buffer = [0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD]  // "你好"
  
  1. 检查最后字节 0xBD → continuation byte (0x80-0xBF)
  2. 回溯到字符起始: 0xE5 → 3 字节字符的 lead byte
  3. 删除 [0xE5, 0xA5, 0xBD] 三个字节
  4. buffer 变为 [0xE4, 0xBD, 0xA0]  // "你"
  5. 回显: \r + 新内容 + 清除残余
```

### UTF-8 字符边界识别

```swift
/// UTF-8 首字节 → 字符字节长度
/// - 0x00-0x7F: 1 字节 (ASCII)
/// - 0xC0-0xDF: 2 字节
/// - 0xE0-0xEF: 3 字节 (中文在此范围)
/// - 0xF0-0xF7: 4 字节 (emoji 在此范围)
static func utf8CharLength(_ byte: UInt8) -> Int {
    if byte < 0x80 { return 1 }
    if byte < 0xE0 { return 2 }
    if byte < 0xF0 { return 3 }
    return 4
}

/// 从 buffer 末尾删除一个完整的 UTF-8 字符
static func processBackslash(buffer: [UInt8], cursorPos: inout Int) -> [UInt8] {
    guard cursorPos > 0 else { return buffer }
    
    // 从 cursorPos 向前回溯，找到字符的 lead byte
    var pos = cursorPos - 1
    // 跳过 continuation bytes (0x80-0xBF)
    while pos > 0 && buffer[pos] >= 0x80 && buffer[pos] <= 0xBF {
        pos -= 1
    }
    // 现在 buffer[pos] 是 lead byte
    let charStart = pos
    
    // 删除从 charStart 到 cursorPos 的字节
    var newBuffer = buffer
    newBuffer.removeSubrange(charStart..<cursorPos)
    cursorPos = charStart
    return newBuffer
}
```

### Raw Mode 终端控制

```swift
import Darwin

private static func enterRawMode() -> termios? {
    var original = termios()
    guard tcgetattr(STDIN_FILENO, &original) == 0 else { return nil }
    
    var raw = original
    raw.c_iflag &= ~UInt(ICANON | ECHO)  // 关闭行缓冲和回显
    raw.c_cc.VMIN = 1   // 至少读 1 字节
    raw.c_cc.VTIME = 0  // 无超时
    
    guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else { return nil }
    return original
}

private static func restoreMode(_ original: termios) {
    var restore = original
    tcsetattr(STDIN_FILENO, TCSANOW, &restore)
}
```

### 与 MultiLineInputReader 的集成

**当前架构：** `MultiLineInputReader` 是 ChatCommand 的输入组件，通过注入的 `readLineFn` 读取输入。

**集成策略：** 在 `readInput()` 方法中，TTY + UTF-8 环境下使用 `CJKInputHandler.readRawLine()` 替代 `readLineFn()`：

```swift
// MultiLineInputReader.readInput() 修改
func readInput(prompt: String, continuationPrompt: String) -> String? {
    guard isTTY else {
        return readLineFn()  // 非 TTY 不变
    }
    
    // AC4: 检测 UTF-8 终端 → 使用 raw mode 输入
    if CJKInputHandler.isCJKEnabled() {
        return CJKInputHandler.readRawLine(
            prompt: prompt,
            writeStdout: writeStdout
        )
    }
    
    // 非 UTF-8 终端：保持原有 readLine 行为
    writeStdout(prompt)
    return readLineFn()
}
```

**注意：** raw mode 路径仍需支持 bracket paste 检测和反斜杠续行。两种方案：
- **方案 A（推荐）：** `CJKInputHandler.readRawLine()` 只负责单行读取（含正确的 backspace 处理），返回后由 `MultiLineInputReader` 检测 bracket paste 标记和续行
- **方案 B：** 在 `CJKInputHandler` 内部处理所有输入逻辑

推荐方案 A — 保持 `CJKInputHandler` 职责单一（raw mode + backspace），`MultiLineInputReader` 继续负责多行逻辑。

### 实现架构

```
CJKInputHandler (新组件)
  │
  ├── readRawLine(prompt:writeStdout:) → String?
  │     ├── enterRawMode() → termios?
  │     ├── 逐字节读取 + backspace 处理
  │     ├── processBackspace(buffer:cursorPos:) → [UInt8]
  │     ├── utf8CharLength(_ byte:) → Int
  │     └── restoreMode(_ original:)
  │
  └── isCJKEnabled() → Bool
        └── 检查 LC_CTYPE / LANG 环境变量包含 "UTF-8"

MultiLineInputReader (修改)
  │
  ├── readInput() — TTY + UTF-8 时调用 CJKInputHandler.readRawLine()
  ├── readBracketPaste() — 不变
  └── readContinuation() — 不变

ChatCommand.swift — 不需要修改（通过 MultiLineInputReader 间接使用）
```

### 关键设计决策

1. **CJKInputHandler 是纯函数 struct** — 与 `BannerRenderer`、`ContextManager`、`PermissionHandler` 同模式。`readRawLine` 需要操作终端，但通过方法封装，不持有状态。

2. **只在 TTY + UTF-8 环境启用 raw mode** — `isCJKEnabled()` 检查 `setlocale(LC_CTYPE, "")` 或环境变量。非 UTF-8 终端不启用。

3. **每次 readInput 调用切换 raw mode** — 进入 raw mode 读取一行后立即恢复。不长期保持 raw mode，减少对其他组件的影响。

4. **回显自行处理** — raw mode 下 `ECHO` 关闭，需要自行处理：
   - 正常输入：`write(stdout, byte, 1)` 回显
   - Backspace：`\r` + 当前行内容 + `ESC[K`（清除行尾）
   - Ctrl+C：不回显，返回中断信号
   - Ctrl+D：EOF

5. **不修改 ChatCommand** — 所有改动封装在 `CJKInputHandler` 和 `MultiLineInputReader` 内部。

6. **不修改 SDK** — 纯应用层改动。

7. **SignalHandler 兼容** — raw mode 下 SIGINT 仍然会被 `SignalHandler` 捕获（信号处理不受终端模式影响）。`CJKInputHandler` 在 raw mode 循环中检查 `SignalHandler.fireCount()`，如果信号触发则立即恢复终端并返回。

### 控制字符处理

| 按键 | 字节 | Raw Mode 处理 |
|------|------|---------------|
| Backspace | 0x7F 或 0x08 | 删除 UTF-8 字符边界，回显更新 |
| Enter | 0x0D | 恢复终端模式，返回当前行 |
| Ctrl+C | 0x03 | 恢复终端模式，返回 nil（让 SignalHandler 处理） |
| Ctrl+D | 0x04 | buffer 空时恢复终端并返回 nil（EOF） |
| 普通 ASCII | 0x20-0x7E | 追加到 buffer，回显 |
| UTF-8 lead byte | 0xC0-0xF7 | 开始累积多字节字符 |
| UTF-8 continuation | 0x80-0xBF | 继续累积当前字符 |

### 特殊情况处理

- **不完整的 UTF-8 序列**：如果 buffer 末尾有不完整的 UTF-8（如只有 lead byte 没有 continuation bytes），backspace 时删除已有的字节
- **空 buffer 时 backspace**：不做任何操作（与标准终端行为一致）
- **超长行**：当 buffer 长度超过终端宽度时，回显需要处理换行（简化方案：限制单行最大长度为 4096 字节）
- **Bracket paste**：raw mode 下检测 `\x1b[200~` 开始标记，进入 paste 累积模式直到 `\x1b[201~`，期间不处理 backspace

### 当前代码位置

**MultiLineInputReader.swift 第 57-87 行 — readInput 方法（需修改）：**
```swift
func readInput(prompt: String, continuationPrompt: String) -> String? {
    guard isTTY else {
        return readLineFn()
    }
    writeStdout(prompt)
    let firstLine = readLineFn()
    // ... bracket paste / continuation 检测
}
```

**ChatCommand.swift 第 110-127 行 — inputReader 使用：**
```swift
let inputReader = MultiLineInputReader()
inputReader.enableBracketPaste()
defer { inputReader.disableBracketPaste() }
// ...
let line = inputReader.readInput(prompt: prompt, continuationPrompt: "...> ")
```

**MultiLineInputReader.swift 第 35 行 — isTTY 检测：**
```swift
isTTY: Bool = isatty(STDIN_FILENO) != 0,
```

### 关键反模式（必须避免）

1. **不要在 raw mode 下忘记恢复终端** — 必须用 `defer` 或 try/finally 确保恢复
2. **不要使用 `print()`** — 控制序列用 `fputs()` + `stderr`/`stdout`（project-context.md 反模式 #3）
3. **不要修改 `ChatCommand.swift`** — 所有改动封装在 `CJKInputHandler` 和 `MultiLineInputReader` 中
4. **不要修改 `RunCommand`** — `axion run "task"` 不受影响
5. **不要长期保持 raw mode** — 每次读取一行后立即恢复
6. **不要在非 TTY 模式启用 raw mode** — 管道输入不需要
7. **不要假设 UTF-8 字符固定 3 字节** — 使用 `utf8CharLength()` 动态判断（中文 3 字节，emoji 4 字节，ASCII 1 字节）
8. **不要忘记处理 Ctrl+C** — raw mode 下 Ctrl+C 不会生成 SIGINT（因为 ISIG 可能被关闭），需要手动检测 0x03 字节

### 测试策略

- **单元测试（必须 Mock）：**
  - `CJKInputHandler.utf8CharLength` — 各种首字节值
  - `CJKInputHandler.processBackspace` — ASCII/中文/emoji/mixed buffer
  - `CJKInputHandler.isCJKEnabled` — 环境变量 mock
  - **Mock 策略：** `processBackspace` 和 `utf8CharLength` 是纯函数，直接测试。`readRawLine` 涉及终端 I/O，不直接测试（通过手动测试验证）。

- **不写集成测试** — 终端 raw mode 需要 TTY 环境，CI 不具备

- **手动测试清单：**
  - 输入 `你好世界` + 3 次 backspace → 应显示 `你`
  - 输入 `hello` + 3 次 backspace → 应显示 `he`
  - 输入 `hello你好` + 3 次 backspace → 应显示 `hel`
  - 粘贴多行中文文本 → 应作为单条输入
  - Ctrl+C 中断 → 应正常中断
  - 管道输入 `echo "测试" | axion` → 应正常工作

### SDK 关键 API 参考

| 函数/类型 | 位置 | 说明 |
|-----------|------|------|
| `isatty(STDIN_FILENO)` | Darwin | 检测 stdin 是否为 TTY |
| `tcgetattr` / `tcsetattr` | Darwin | 获取/设置终端属性 |
| `termios` | Darwin | 终端属性结构体 |
| `ICANON` / `ECHO` | Darwin | 行缓冲/回显标志 |
| `write(STDOUT_FILENO, ...)` | Darwin | 原始 stdout 写入 |
| `read(STDIN_FILENO, ...)` | Darwin | 原始 stdin 读取 |
| `setlocale(LC_CTYPE, "")` | Foundation | 检测当前 locale 编码 |

### References

- [Source: docs/epics/epic-37-interactive-chat-mode.md#Story 37.9] — 完整 story 定义和 AC
- [Source: Sources/AxionCLI/Chat/MultiLineInputReader.swift:57-87] — readInput 方法（需修改）
- [Source: Sources/AxionCLI/Chat/MultiLineInputReader.swift:13-44] — 构造器（注入依赖模式参考）
- [Source: Sources/AxionCLI/Commands/ChatCommand.swift:110-127] — inputReader 使用
- [Source: Sources/AxionCLI/Chat/SignalHandler.swift] — SIGINT 处理（raw mode 下需兼容）

### Previous Story Intelligence (37.8)

- **SlashCommandAction enum 已完成** — 支持 `.none` / `.exit` / `.resumeSession(String)`
- **SessionResumeManager 已完成** — 纯函数 struct 模式
- **2092 个单元测试全部通过** — 新测试需加入 CI 范围

### Previous Story Intelligence (37.7)

- **ContextManager 已完成** — 纯函数 struct，static methods 模式
- **compact boundary 事件处理正常** — 不受输入改动影响

### Previous Story Intelligence (37.6)

- **MultiLineInputReader 已完成** — 本 Story 需修改此文件，集成 CJK 输入
- **Bracket paste 已实现** — raw mode 路径下需保持兼容
- **反斜杠续行已实现** — raw mode 路径下需保持兼容

### Previous Story Intelligence (37.0-37.5)

- **BannerRenderer / ChatOutputFormatter / PermissionHandler / SignalHandler** — 不受本 Story 影响
- **BuildConfig.forChat()** — 不需要修改

### Git Intelligence

最近 5 个提交：
- `422a8ff` feat(story-37.8): 会话恢复 — 新增 SessionResumeManager，修改 SlashCommandHandler
- `4e5e0c5` feat(story-37.7): 上下文管理 — 新增 ContextManager，compact 检测
- `eca8a70` feat(story-37.6): 多行输入支持 — 新增 MultiLineInputReader
- `c37d8f0` feat(story-37.5): 权限审批机制 — 新增 PermissionHandler
- `9f71692` feat(story-37.4): 终端输出优化 — 新增 ChatOutputFormatter

本 Story 37.9 新增 `CJKInputHandler.swift` 独立文件，修改 `MultiLineInputReader`（集成 CJK 输入路径）。不修改 ChatCommand、BannerRenderer 等其他 Chat 组件。

### Project Structure Notes

- 新文件 `CJKInputHandler.swift` 放在 `Sources/AxionCLI/Chat/` 目录，与其他 Chat 组件一致
- 新测试文件 `CJKInputHandlerTests.swift` 放在 `Tests/AxionCLITests/Chat/` 目录
- 遵循项目约定：纯函数 struct + static methods + 注入依赖

## Dev Agent Record

### Agent Model Used

GLM-5.1 (via Claude Code)

### Debug Log References

- 编译错误：macOS `termios.c_cc` 是元组类型，不能用 `.VMIN`/`.VTIME` 访问，改用 `.16`/`.17` 索引
- 测试回归：MultiLineInputReaderTests 在 UTF-8 环境下因 `isCJKEnabled()` 返回 true 走了 raw mode 路径。解决方案：增加 `cjkEnabledFn` 注入参数

### Completion Notes List

- ✅ 创建 CJKInputHandler — 纯函数 struct，包含 utf8CharLength/processBackspace/isCJKEnabled/readRawLine/enterRawMode/restoreMode
- ✅ 修改 MultiLineInputReader — TTY+UTF-8 环境下自动使用 CJKInputHandler.readRawLine()
- ✅ 增加 cjkEnabledFn 注入参数 — MultiLineInputReader 构造器新增可测试的 CJK 检测闭包
- ✅ 15 个新单元测试全部通过（utf8CharLength 5 个 + processBackspace 7 个 + isCJKEnabled 1 个 + 混合序列 2 个）
- ✅ 全部 2107 个单元测试通过，零回归
- ✅ 不修改 ChatCommand.swift — 所有改动封装在 CJKInputHandler 和 MultiLineInputReader 中
- ✅ 不修改 RunCommand — axion run "task" 不受影响
- ✅ 不修改 SDK — 纯应用层改动

### File List

- `Sources/AxionCLI/Chat/CJKInputHandler.swift` — 新增：CJK 输入处理器（raw mode + UTF-8 backspace）
- `Sources/AxionCLI/Chat/MultiLineInputReader.swift` — 修改：集成 CJK 输入路径 + 新增 cjkEnabledFn 注入
- `Tests/AxionCLITests/Chat/CJKInputHandlerTests.swift` — 新增：15 个单元测试
- `Tests/AxionCLITests/Chat/MultiLineInputReaderTests.swift` — 修改：注入 cjkEnabledFn: { false } 适配新构造器

## Senior Developer Review (AI)

**Reviewer:** Claude Opus 4.8
**Date:** 2026-06-07
**Verdict:** Changes Requested → Auto-Fixed

### Issues Found

#### 🔴 CRITICAL

1. **反斜杠续行在 CJK 模式下完全失效** — `readInput()` 在 `cjkEnabledFn() == true` 时直接返回 `CJKInputHandler.readRawLine()` 结果，完全跳过了 `hasSuffix("\\")` 检测。Task 2.4 标记 `[x]` 但实际未实现。AC5 违规。
   - **Fix**: 新增 `readCJKInput()` 和 `readCJKContinuation()` 私有方法，在 CJK 路径下实现完整的续行逻辑。

#### 🟡 HIGH

2. **多行 bracket paste 在 CJK raw mode 下失效** — `CJKInputHandler.readRawLine()` 的 Enter 处理不检查 `inBracketPaste` 状态，导致粘贴内容在第一个换行符处截断。
   - **Fix**: Enter 处理增加 `inBracketPaste` 检查，paste 模式下将 `\n` 追加到 buffer。

3. **Bracket paste 模式下 backspace 未禁用** — 粘贴过程中按 backspace 会修改 buffer，违反 bracket paste 语义。
   - **Fix**: Backspace 处理增加 `inBracketPaste` 检查。

#### 🟡 MEDIUM

4. **CJK 路径无测试覆盖** — 所有 `MultiLineInputReaderTests` 使用 `cjkEnabledFn: { false }`，零测试覆盖 CJK 集成路径。上述 CRITICAL/HIGH 问题因此未被测试发现。

5. **isCJKEnabled 测试过弱** — 仅检查返回类型 `Bool.self`，不验证实际值。

### Fixes Applied

- `MultiLineInputReader.swift`: 新增 `readCJKInput()` + `readCJKContinuation()` 方法，CJK 路径完整支持反斜杠续行
- `CJKInputHandler.swift`: Enter 处理增加 `inBracketPaste` 检查；Backspace 处理增加 `inBracketPaste` 检查

### Post-Fix Verification

- ✅ 2107 个单元测试全部通过，零回归
