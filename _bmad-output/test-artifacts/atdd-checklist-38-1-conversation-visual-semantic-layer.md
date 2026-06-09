---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04-generate-tests
  - step-04c-aggregate
lastStep: step-04c-aggregate
lastSaved: '2026-06-07'
storyId: '38.1'
storyKey: '38-1-conversation-visual-semantic-layer'
storyFile: '_bmad-output/implementation-artifacts/38-1-conversation-visual-semantic-layer.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-38-1-conversation-visual-semantic-layer.md'
generatedTestFiles:
  - Tests/AxionCLITests/Chat/Theme/TerminalColorProfileTests.swift
  - Tests/AxionCLITests/Chat/Theme/ChatThemeTests.swift
  - Tests/AxionCLITests/Chat/Theme/TranscriptRendererTests.swift
  - Tests/AxionCLITests/Chat/Theme/TranscriptIntegrationTests.swift
inputDocuments:
  - _bmad-output/project-context.md
  - _bmad-output/implementation-artifacts/38-1-conversation-visual-semantic-layer.md
  - Sources/AxionCLI/Chat/ChatOutputFormatter.swift
  - Sources/AxionCLI/Chat/SpinnerRenderer.swift
  - Sources/AxionCLI/Chat/BannerRenderer.swift
  - Tests/AxionCLITests/Chat/TerminalOutputTests.swift
  - Tests/AxionCLITests/Chat/BannerRendererTests.swift
---

# ATDD Checklist: Story 38.1 对话视觉语义层

## TDD Red Phase (当前状态)

🔴 所有测试脚手架已生成，引用尚未实现的类型，**无法编译**。

- 单元测试: 4 个文件, ~50 个测试用例
- 编译错误确认: `TerminalColorProfile`、`ChatTheme`、`TranscriptRenderer`、`TranscriptRole` 类型不存在

## Acceptance Criteria 覆盖矩阵

| AC | 描述 | 测试文件 | 测试数量 | 优先级 |
|----|------|---------|---------|--------|
| AC1 | 用户消息角色标识（蓝色圆点） | TranscriptRendererTests, TranscriptIntegrationTests | 4 | P0 |
| AC2 | AI 回复角色标识（绿色圆点） | TranscriptRendererTests, TranscriptIntegrationTests | 3 | P0 |
| AC3 | 工具/审批角色标识（黄色/红色圆点） | TranscriptRendererTests, TranscriptIntegrationTests | 10 | P0 |
| AC4 | 非 TTY 回退（纯文本前缀） | ChatThemeTests, TranscriptRendererTests, TranscriptIntegrationTests | 8 | P0 |
| AC5 | tmux/screen 兼容（无 OSC 乱码） | TranscriptRendererTests | 1 | P1 |
| AC6 | 窄终端兼容（< 40 列） | ChatThemeTests, TranscriptRendererTests | 4 | P1 |
| AC7 | 颜色降级链（TrueColor/Ansi256/Ansi16/Unknown） | TerminalColorProfileTests, ChatThemeTests | 16 | P0 |
| AC8 | NFR 渲染性能（< 1ms） | TranscriptRendererTests | 1 | P1 |

## 测试文件清单

### 1. TerminalColorProfileTests.swift (~120 行)
**路径:** `Tests/AxionCLITests/Chat/Theme/TerminalColorProfileTests.swift`

测试覆盖：
- `detect()` 环境变量探测：trueColor、24bit、xterm-256color、screen-256color、tmux-256color、xterm、vt100、非 TTY
- `ansiColor(for:)` 角色映射：各 profile 下 user/assistant/tool/warning 的 ANSI 码正确性
- TrueColor 24-bit RGB `\033[38;2;R;G;Bm`
- Ansi256 `\033[38;5;Nm`
- Ansi16 标准色码：蓝=34、绿=32、黄=33、红=31
- Unknown：所有角色返回空字符串

### 2. ChatThemeTests.swift (~100 行)
**路径:** `Tests/AxionCLITests/Chat/Theme/ChatThemeTests.swift`

测试覆盖：
- `formatRoleDot(role:)` 各角色圆点输出（TrueColor/Ansi16）
- `formatPlainText(role:)` 纯文本前缀：[user]/[ai]/[tool]/[warn]
- 非 TTY 时 `formatRoleDot` 使用纯文本
- `formatBlock(role:content:)` 完整块格式化
- `separatorLine` TTY/非 TTY 行为
- 窄终端长/短消息不崩溃

### 3. TranscriptRendererTests.swift (~150 行)
**路径:** `Tests/AxionCLITests/Chat/Theme/TranscriptRendererTests.swift`

测试覆盖：
- `renderUserMessage(text:)` 各 profile 输出
- `renderAssistantBlockStart()` 各 profile 输出
- `renderToolEvent(name:summary:duration:isError:)` 正常/错误/耗时
- `renderWarning(message:)` 各 profile 输出
- `renderResult(subtype:)` success/errorMaxTurns/cancelled
- 窄终端兼容
- tmux 无 OSC 转义
- 渲染性能基准（1000 次调用 < 1ms）

### 4. TranscriptIntegrationTests.swift (~150 行)
**路径:** `Tests/AxionCLITests/Chat/Theme/TranscriptIntegrationTests.swift`

测试覆盖：
- ChatOutputFormatter + ChatTheme 集成
- toolUse 输出包含黄色圆点（TTY）和 [tool]（非 TTY）
- toolResult success/error 的圆点颜色
- result errorMaxTurns 的红色圆点
- system paused 的红色圆点
- 向后兼容：保留 ⏳/✅/❌ 图标
- 无 theme 时的向后兼容

## Mock 策略

| 组件 | Mock 方式 | 说明 |
|------|----------|------|
| `TerminalColorProfile.detect()` | 注入闭包参数 | `detect(isTTY:colorterm:term:)` 可测试 |
| `ChatTheme` | 直接测试 | 纯 struct，无外部依赖 |
| `TranscriptRenderer` | 直接测试 | 纯 struct，注入 ChatTheme |
| `ChatOutputFormatter` | 注入 writeStdout/writeStderr + ChatTheme | CaptureOutput 辅助类 |
| `SpinnerRenderer` | `isTTY: false` 静默 | 不干扰测试输出 |

## TDD 实施流程（逐 Task 激活）

### Task 1: TerminalColorProfile（~80 行源码）
1. 创建 `Sources/AxionCLI/Chat/Theme/TerminalColorProfile.swift`
2. 定义 enum + detect() + ansiColor(for:)
3. 运行 `TerminalColorProfileTests` — 验证从红转绿
4. 提交

### Task 2: ChatTheme（~60 行源码）
1. 创建 `Sources/AxionCLI/Chat/Theme/ChatTheme.swift`
2. 定义 struct + formatRoleDot + formatPlainText + formatBlock + separatorLine
3. 运行 `ChatThemeTests` — 验证从红转绿
4. 提交

### Task 3: TranscriptRenderer（~100 行源码）
1. 创建 `Sources/AxionCLI/Chat/Theme/TranscriptRenderer.swift`
2. 定义 TranscriptRole enum + TranscriptRenderer struct
3. 运行 `TranscriptRendererTests` — 验证从红转绿
4. 提交

### Task 4: ChatOutputFormatter 集成
1. 修改 `ChatOutputFormatter` 添加 theme 属性
2. 修改 `ChatCommand` 初始化 ChatTheme
3. 运行 `TranscriptIntegrationTests` — 验证从红转绿
4. 运行现有 `ChatOutputFormatterTests` — 确认向后兼容
5. 提交

## 运行测试命令

```bash
# 全部单元测试（含新测试）
swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests" --filter "AxionBarTests"

# 仅 Chat/Theme 测试
swift test --filter "TerminalColorProfileTests" --filter "ChatThemeTests" --filter "TranscriptRendererTests" --filter "TranscriptIntegrationTests"
```

## 下一步

1. 实现 Task 1: `TerminalColorProfile.swift`
2. 验证 `TerminalColorProfileTests` 编译并通过（红→绿）
3. 依次实现 Task 2 → Task 3 → Task 4
4. 每完成一个 Task，运行对应测试验证
5. 所有测试通过后，更新 story 状态为 done
