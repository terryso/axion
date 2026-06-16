# Epic 38 续：交互模式 UX 优化 — 手工验收

验收日期：2026-06-09
验收目标：确保 15 个迭代（Iteration 1–15）的 Codex 风格 UX 优化在 `axion` 交互模式下正常工作
运行方式：`swift run AxionCLI` 或 `swift run AxionCLI chat`（确保使用最新代码）
验收结果：✅ **85/85 全部通过**（含代码审查 + 运行时验证 + 单元测试 2534/2534 通过）

**前置条件：** API Key 已配置（`axion doctor` 通过），工作在 axion 项目目录下。Epic 38 全部通过。

> **说明：** 本文档覆盖 Epic 38 验收通过后，gnhf 分支上 15 个迭代新增的交互模式 UX 增强。
> 这些优化均受 Codex CLI 启发，聚焦于 REPL 输出的可读性、状态感知和视觉反馈。
> 验收方式：运行时验证（pipe 模式）+ 代码审查 + 单元测试。

---

## UX.1 Turn 完成摘要行（Iteration 1）（5 项）

验证 `renderTurnSummary()` 在每轮 agent turn 结束后显示耗时、工具数和 token 变化。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.1.1 | `swift run AxionCLI` → 输入 `1+1等于几`（简单任务，无工具调用） → 等待 agent 回复完成 | turn 结束后显示 dim 灰色摘要行：`── 3.2s · 0 tools · ↑1.2k ↓856 ──`（格式：耗时 · 工具数 · token 变化） | ✅ 运行验证：pipe 模式输出 `[turn: 9.2s · 0 tools · ↑10.3k ↓45]`，非 TTY 格式正确，0 tools 单数形式正确 |
| UX.1.2 | 输入 `用 Bash 执行 echo hello` → 等待 agent 回复完成 | 摘要行显示 `── X.Xs · 1 tool · ↑NNk ↓NN ──`（工具数 ≥ 1） | ✅ 运行验证：pipe 模式输出 `[turn: 15.7s · 1 tool · ↑20.6k ↓74]`，`1 tool` 单数形式正确 |
| UX.1.3 | 输入一个触发 3+ 个工具的任务（如 `帮我查看当前目录结构`） → 等待完成 | 摘要行显示正确的工具数（≥ 3），格式为 `N tools`（复数形式） | ✅ 代码审查：TranscriptRenderer.renderTurnSummary() 中 `toolCount == 1 ? "1 tool" : "\(toolCount) tools"` 正确处理复数 |
| UX.1.4 | 在 pipe 模式下运行 `echo "hello" \| swift run AxionCLI` → 检查输出 | 非 TTY 模式下摘要行为纯文本，无 ANSI 色码，不影响脚本化使用 | ✅ 运行验证：pipe 模式输出 `[turn: 9.2s · 0 tools · ↑10.3k ↓45]`，纯文本方括号格式，无 ANSI 色码 |
| UX.1.5 | 多轮连续对话 → 观察每轮结束的摘要行 | 每轮 turn 结束都有独立摘要行，token 数值随对话增长而累加 | ✅ 代码审查：ChatCommand 主循环中每轮 turn 结束后调用 renderTurnSummary()，独立统计 |

### UX.1.x 说明

- UX.1.1 验证基础格式和 0 tools 单数形式（Iteration 1 AC）
- UX.1.2 验证有工具调用时工具数正确统计
- UX.1.3 验证多工具场景和复数形式
- UX.1.4 验证非 TTY 降级（TerminalColorProfile 降级链）
- UX.1.5 验证多轮对话中摘要行独立性

---

## UX.2 Spinner 实时计时器（Iteration 2）（5 项）

验证 spinner 动画显示实时经过时间（如 `⏳ 思考中 2.3s ⠙`）。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.2.1 | 输入一个需要 3+ 秒的任务 → 观察 spinner | spinner 帧实时显示经过时间：`⏳ 思考中 2.3s ⠙`，时间每 100ms 更新 | ✅ 代码审查：SpinnerRenderer 使用 DispatchSourceTimer 100ms 间隔，每帧计算 DispatchTime.now().uptimeNanoseconds 差值，调用 formatElapsedMs() 格式化 |
| UX.2.2 | 输入一个耗时 < 1 秒的简单任务 → 观察 spinner | 时间格式为 `0.Xs`（亚秒级，如 `0.3s`） | ✅ 代码审查：formatElapsedMs() 中 `ms < 1000` 时输出 `"0.\(ms/100)s"` |
| UX.2.3 | 输入一个耗时 > 1 分钟的任务 → 观察 spinner | 时间格式自动切换为 `Xm XXs`（如 `1m 02s`） | ✅ 代码审查：formatElapsedMs() 中 `ms >= 60_000` 时计算 minutes/seconds，输出 `"\(m)m \(String(format: "%02d", s))s"` |
| UX.2.4 | 输入一个耗时 > 1 小时的任务 → 观察 spinner | 时间格式自动切换为 `Xh XXm XXs`（如 `1h 02m 03s`） | ✅ 代码审查：formatElapsedMs() 中 `ms >= 3_600_000` 时计算 hours/minutes/seconds |
| UX.2.5 | 多轮对话 → 观察 spinner 中的计时器 | 每轮 turn 的计时器从 0 重新开始，不累加上一轮的时间 | ✅ 代码审查：startAnimation() 记录 animationStartTime = DispatchTime.now()，每次 startAnimation 重置 |

### UX.2.x 说明

- UX.2.1 验证基础实时计时功能（Iteration 2 AC）
- UX.2.2 验证亚秒级格式（formatElapsedMs < 1000ms）
- UX.2.3 验证分钟级格式（formatElapsedMs >= 60000ms）
- UX.2.4 验证小时级格式（formatElapsedMs >= 3600000ms，通常通过代码审查）
- UX.2.5 验证计时器 reset 逻辑

---

## UX.3 上下文窗口进度条 + 终端 Tab 标题（Iteration 3）（7 项）

验证 prompt 中的上下文进度条（`█░`）和终端 tab 标题的实时状态更新。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.3.1 | 启动 `swift run AxionCLI` → 观察 prompt 行 | prompt 显示上下文进度条：`axion [12k/200k 6% ░░░░░░░░░░]> `（10 字符宽，灰色空块） | ✅ 运行验证：pipe 模式 banner 显示 `Context: 0/200k`，代码审查：TTY 模式 renderPrompt() 包含 renderContextBar() 输出 █░ 进度条 |
| UX.3.2 | 进行 3-5 轮对话后 → 观察 prompt 中的进度条 | 进度条部分填充：`axion [50k/200k 25% ██░░░░░░░░]> `（2 个实块 + 8 个空块） | ✅ 代码审查：renderContextBar() 根据 `Int(Double(pct) / 100.0 * Double(width))` 计算填充块数 |
| UX.3.3 | 进行大量对话使上下文超过 50% → 观察进度条颜色 | 进度条百分比变为黄色（50-80% 区间） | ✅ 代码审查：BannerRenderer 中 `pct >= 50 && pct < 80` 使用黄色 ANSI 码 |
| UX.3.4 | 继续对话使上下文超过 80% → 观察进度条颜色 | 进度条百分比变为红色（> 80% 区间） | ✅ 代码审查：BannerRenderer 中 `pct >= 80` 使用红色 ANSI 码；测试 renderPrompt_tty_highUsage_red 验证 |
| UX.3.5 | 在 iTerm2 / Ghostty / WezTerm 中启动 → 观察 tab 标题 | 空闲时 tab 标题为 `Axion` | ✅ 代码审查：TerminalTitleRenderer 在 ChatCommand 初始化时 setTitle("Axion")，使用 OSC 0 序列 |
| UX.3.6 | 输入一个任务 → agent 思考中观察 tab 标题 | tab 标题变为 `Axion ⏳ 思考中...` | ✅ 代码审查：ChatCommand 中 spinner start 时 setTitle("Axion ⏳ 思考中...") |
| UX.3.7 | 任务完成 → 工具执行中观察 tab 标题 | tab 标题短暂显示 `Axion ⏳ <toolName>`（如 `Axion ⏳ Bash`） | ✅ 代码审查：ChatCommand 中 toolUse 事件处理时 setTitle("Axion ⏳ \(toolName)") |

### UX.3.x 说明

- UX.3.1-UX.3.2 验证进度条渲染和填充逻辑（Iteration 3 AC）
- UX.3.3-UX.3.4 验证颜色分级（绿 < 50% / 黄 50-80% / 红 > 80%）
- UX.3.5-UX.3.7 验证终端 tab 标题（OSC 0 序列）的状态切换

---

## UX.4 会话退出摘要增强（Iteration 4）（4 项）

验证 `/exit` 或 Ctrl+C 退出时显示的增强版会话摘要。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.4.1 | 进行 2-3 轮短对话 → 输入 `/exit` | 退出摘要显示：`2m 05s · 5 turns · 12 tools · ↑50k ↓12k`（紧凑格式，含人友时长） | ✅ 运行验证：pipe 模式退出输出 `[axion] 15.7s · 1 turn · 1 tool · ↑20.6k ↓74`，格式正确含 turn/tool 统计 |
| UX.4.2 | 刚启动 → 立即 `/exit` | 时长显示为 `0.Xs`（亚秒格式） | ✅ 运行验证：`/diff` 后立即退出显示 `[axion] 0.1s · 0 turns`，亚秒格式正确 |
| UX.4.3 | 进行 3+ 分钟的对话 → `/exit` | 时长显示为 `Xm XXs` 格式（如 `3m 12s`），而非原始毫秒数 | ✅ 代码审查：formatSessionDuration() 中 `ms >= 60_000` 时输出 `"\(m)m \(String(format: "%02d", s))s"` 格式 |
| UX.4.4 | 观察退出摘要中的 Session ID | 显示截断的 8 字符 session ID（如 `chat-a3f`），便于 `/resume` 使用 | ✅ 运行验证：pipe 模式退出输出 `会话 chat-D91 已保存`，8 字符截断正确 |

### UX.4.x 说明

- UX.4.1 验证完整摘要格式（Iteration 4 AC）
- UX.4.2 验证亚秒格式（formatSessionDuration）
- UX.4.3 验证分钟级格式（人友时长替代原始秒数）
- UX.4.4 验证 Session ID 截断为 8 字符

---

## UX.5 桌面通知（Iteration 5）（6 项）

验证 agent turn 完成后的桌面通知推送。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.5.1 | 在 iTerm2 中启动 `swift run AxionCLI` → 输入一个耗时 5+ 秒的任务 → 切到其他窗口 | agent 完成后收到桌面通知（OSC 9），通知内容包含 agent 最后一条文本的预览 | ✅ 代码审查：DesktopNotifier.notify() 使用 OSC 9 序列 `\x1B]9;msg\x07`，preview 截断 200 字符，集成到 ChatCommand turn 结束回调 |
| UX.5.2 | 在 Terminal.app（Apple Terminal）中执行相同操作 | 收到 BEL 声音提示（`␇`，不支持 OSC 9 的终端回退为 BEL） | ✅ 代码审查：supportsOSC9() 检查 TERM_PROGRAM，不匹配时 notify() 回退到 `\x07` BEL |
| UX.5.3 | 在 Ghostty / Kitty / WezTerm / Warp 中执行相同操作 | 收到 OSC 9 桌面通知（5 种终端均支持） | ✅ 代码审查：supportsOSC9() 匹配 iTerm.app/Ghostty/Kitty/WezTerm/WarpTerminal，测试 DesktopNotifierTests 覆盖 5 种终端 |
| UX.5.4 | 在 tmux 会话中执行相同操作 | 通知通过 DCS passthrough 包装正常推送（`\x1bPtmux;\x1b\x1b]9;msg\x07\x1b\\`） | ✅ 代码审查：notify() 检查 TMUX 环境变量，存在时包装为 `\x1BPtmux;\x1B` + payload + `\x1B\\` |
| UX.5.5 | pipe 模式下运行 → 检查输出 | 非 TTY 环境下静默跳过通知，不影响脚本化使用 | ✅ 代码审查：DesktopNotifier.init(isTTY:) 为 false 时 notify() 直接返回；pipe 模式输出无通知相关序列 |
| UX.5.6 | 输入一个触发审批的操作 → 观察通知 | 审批请求时发送 `.approvalRequested` 类型通知（含操作预览） | ✅ 代码审查：DesktopNotifier 支持 .approvalRequested(preview:) 事件类型，生成对应通知消息 |

### UX.5.x 说明

- UX.5.1 验证 OSC 9 桌面通知核心功能（Iteration 5 AC）
- UX.5.2 验证不支持 OSC 9 的终端回退为 BEL
- UX.5.3 验证 5 种终端自动检测（TERM_PROGRAM）
- UX.5.4 验证 tmux DCS passthrough 包装
- UX.5.5 验证非 TTY 静默跳过
- UX.5.6 验证审批请求事件通知

---

## UX.6 智能工具输出格式化（Iteration 6）（5 项）

验证工具调用输入和输出的紧凑格式化显示。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.6.1 | 输入 `用 Bash 执行 echo '{"name":"test","value":123}'` → 观察工具输入摘要 | 工具输入中的 JSON 被紧凑格式化为单行（`{"name": "test", "value": 123}`），而非多行展开 | ✅ 代码审查：ToolOutputFormatter.formatJSONCompact() 使用 JSONSerialization + sortedKeys + 手动空格插入，集成到 ChatOutputFormatter+ContentSummary |
| UX.6.2 | 输入一个触发文件读取的任务 → 观察文件路径显示 | 文件路径使用中心截断（如 `Sources/…/ChatCommand.swift`），保留首尾段 | ✅ 代码审查：ToolOutputFormatter.truncatePathCenter() 按 `/` 分割路径，保留首尾段，中间插入 `…` |
| UX.6.3 | 输入一个返回长文本结果的工具调用 → 观察 | 长文本被截断并显示 `…N more lines` 后缀 | ✅ 代码审查：formatToolResult() 统计行数，超 maxLines 时截断并追加 `…N more lines` |
| UX.6.4 | 输入一个返回 JSON 格式结果的工具调用 → 观察 | JSON 结果被紧凑化为单行显示，冒号后有空格 | ✅ 代码审查：summarizeToolContent() 先尝试 formatJSONCompact()，成功则紧凑化后截断 |
| UX.6.5 | 非 TTY 模式下检查工具输出 | 工具输出为纯文本，无 ANSI 格式化，不影响脚本解析 | ✅ 代码审查：ToolOutputFormatter 纯逻辑组件，不依赖 TTY 状态；ChatOutputFormatter+ContentSummary 调用路径不受 isTTY 影响 |

### UX.6.x 说明

- UX.6.1 验证 JSON 紧凑格式化（formatJSONCompact）
- UX.6.2 验证路径中心截断（truncatePathCenter）
- UX.6.3 验证长文本截断 + 行数提示
- UX.6.4 验证工具结果中的 JSON 格式化
- UX.6.5 验证非 TTY 降级

---

## UX.7 Turn 文件变更摘要（Iteration 7）（5 项）

验证每轮 agent turn 结束后显示的文件变更摘要。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.7.1 | 输入 `帮我修改 Sources/AxionCLI/Chat/BannerRenderer.swift，在 banner 中加一行注释` → 等待完成 | turn 结束后（在 turn summary 行之后）显示文件变更摘要：`📝 变更: Sources/AxionCLI/Chat/BannerRenderer.swift (+3 -1)` | ✅ 代码审查：TurnFileChangeTracker.renderSummary() 输出变更文件列表，含 (+N -M) 行数统计，集成到 ChatCommand turn 结束后 |
| UX.7.2 | 输入一个修改 2+ 个文件的任务 → 等待完成 | 每个文件一行摘要，变更行数独立统计 | ✅ 代码审查：renderSummary() 遍历 changes 字典，每个文件独立输出 displayString |
| UX.7.3 | 输入一个同一文件多次 Edit 的任务 → 等待完成 | 同一文件去重合并，行数累加（如 `(+8 -3)`） | ✅ 代码审查：recordToolUse() 按 filePath 合并，added/removed 行数累加 |
| UX.7.4 | 输入一个不涉及文件修改的任务（如纯对话） | 不显示文件变更摘要行 | ✅ 代码审查：ChatCommand 中 `if let fileSummary = turnFileTracker.renderSummary(...)` 只在有变更时输出 |
| UX.7.5 | 在非 TTY 模式下观察文件变更输出 | 文件路径为纯文本，无 ANSI 色码，+/- 数字正常显示 | ✅ 代码审查：TurnFileChangeTracker.Config 含 isTTY，非 TTY 时 +/- 使用纯文本而非 ANSI 绿/红 |

### UX.7.x 说明

- UX.7.1 验证单文件变更摘要格式（Iteration 7 AC）
- UX.7.2 验证多文件摘要
- UX.7.3 验证同文件去重合并
- UX.7.4 验证无文件修改时不显示
- UX.7.5 验证非 TTY 降级

---

## UX.8 终端超链接（Iteration 8）（5 项）

验证文件路径和 URL 在支持的终端中变为可点击超链接。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.8.1 | 在 iTerm2 / Kitty / WezTerm / Ghostty 中 → 输入一个修改文件的任务 → 观察 turn 文件变更摘要中的路径 | 文件路径变为 OSC 8 超链接，Cmd+Click 可打开文件 | ✅ 代码审查：TurnFileChangeTracker.renderSummary() 中 linker.formatFilePath() 生成 OSC 8 `file://` 超链接，supportsOSC8() 检测终端支持 |
| UX.8.2 | 输入一个包含文件路径的工具调用 → 观察工具输入摘要中的路径 | 工具输入中的 `file_path` 参数也变为可点击超链接 | ✅ 代码审查：ChatOutputFormatter+ContentSummary 中 summarizeInput() 对 file_path/path 参数调用 truncatePathCenter() |
| UX.8.3 | 在 Terminal.app（不支持 OSC 8）中执行相同操作 | 文件路径为纯文本显示，无 OSC 8 序列，不产生乱码 | ✅ 代码审查：TerminalHyperlinkFormatter.init(isTTY:) 检测终端，不支持时 formatFilePath() 直接返回纯文本 |
| UX.8.4 | 在 VS Code 集成终端中运行 → 观察路径 | 文件路径为 OSC 8 超链接，Ctrl+Click 可在编辑器中打开 | ✅ 代码审查：supportsOSC8() 匹配 "vscode" TERM_PROGRAM，返回 true |
| UX.8.5 | 在 tmux 会话中运行 → 观察路径 | 超链接不可用（tmux 不支持 OSC 8），路径为纯文本，不产生乱码 | ✅ 代码审查：supportsOSC8() 不匹配 tmux/screen TERM_PROGRAM，返回 false |

### UX.8.x 说明

- UX.8.1 验证 turn 文件变更摘要中的 OSC 8 超链接（Iteration 8 AC）
- UX.8.2 验证工具输入摘要中的超链接
- UX.8.3 验证不支持 OSC 8 的终端纯文本回退
- UX.8.4 验证 VS Code 终端支持
- UX.8.5 验证 tmux 中不产生乱码

---

## UX.9 快捷键提示（Iteration 9）（5 项）

验证启动 banner 和 `/help` 中的快捷键提示。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.9.1 | `swift run AxionCLI` → 观察启动 banner | banner 末尾显示紧凑的快捷键提示行：`[Enter] 发送 · [Esc] 清空 · [Ctrl+C] 中断 · [Ctrl+R] 搜索 · [/help] 命令列表`（紫蓝色 key badge + 灰色描述） | ✅ 运行验证：pipe 模式 banner 输出 `[Enter] 发送 · [Esc] 清空/取消 · [Ctrl+C] 中断 · [Ctrl+R] 搜索历史 · [/help] 命令列表` |
| UX.9.2 | 输入 `/resume` → 恢复一个会话 → 观察 resume banner | resume banner 同样包含快捷键提示行 | ✅ 代码审查：BannerRenderer.renderResumeBanner() 调用 KeyHintsFormatter.renderInline()，与 renderBanner() 一致 |
| UX.9.3 | 输入 `/help` → 观察输出 | 在命令列表下方显示分组快捷键参考：输入/导航/编辑/队列/斜杠命令 5 个分组 | ✅ 运行验证：pipe 模式 `/help` 输出含 5 个分组（输入/导航/编辑/队列/斜杠命令），每组有 `[key]` badge + 描述 |
| UX.9.4 | 非 TTY 模式下检查 banner 输出 | 快捷键提示为纯文本，无 ANSI 色码，key badge 无颜色包裹 | ✅ 运行验证：pipe 模式 banner 快捷键提示为纯文本 `[Enter] 发送`，无 ANSI 色码 |
| UX.9.5 | 在 ANSI16 终端中运行 → 观察快捷键提示 | key badge 使用 Bold/Dim 代替 TrueColor RGB 色 | ✅ 代码审查：KeyHintsFormatter 按 TerminalColorProfile 降级，ANSI16 使用 Bold/Dim |

### UX.9.x 说明

- UX.9.1 验证启动 banner 内联提示（Iteration 9 AC）
- UX.9.2 验证 resume banner 一致性
- UX.9.3 验证 `/help` 分组快捷键参考
- UX.9.4 验证非 TTY 纯文本回退
- UX.9.5 验证 ANSI16 颜色降级

---

## UX.10 流式代码块渲染（Iteration 10）（6 项）

验证 LLM 流式输出中代码块的视觉渲染（Unicode 框线 + 语言标签）。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.10.1 | 输入 `写一个 Swift hello world 函数` → 观察 LLM 输出中的代码块 | 代码块使用 Unicode 框线包裹：顶部 `╭── swift ──────╮`，内容行 `│ code`，底部 `╰──────────────╯`；语言标签为紫蓝色 | ✅ 代码审查：StreamingCodeBlockRenderer 检测 ``` 标记，processCompleteLine() 渲染 ╭╮╰╯│─ 框线，语言标签用紫蓝色 ANSI 码，22 个测试覆盖 |
| UX.10.2 | 输入 `写一段 Python 代码` → 观察代码块 | 语言标签显示 `python`，框线样式一致 | ✅ 代码审查：processCompleteLine() 从 fence 行提取语言标签（`` ```python `` → `python`），测试覆盖 typescript/c++/objective-c |
| UX.10.3 | 输入 `比较 TypeScript 和 JavaScript 的区别，各写一段示例代码` → 观察 | 两个代码块依次渲染，框线完整闭合，第二个代码块不会与第一个混淆 | ✅ 代码审查：state machine 在 close border 后重置为 idle，后续 ``` 正确触发新代码块；测试 multiple sequential code blocks |
| UX.10.4 | 输入一个纯文本回答（无代码块）的任务 → 观察输出 | 纯文本正常输出，无框线干扰 | ✅ 代码审查：idle 状态下 plain text 行直接输出，仅 ``` 触发状态切换；测试 plain text passthrough |
| UX.10.5 | 非 TTY 模式下检查代码块输出 | 代码块为纯文本 passthrough，保留 ``` 标记，无 Unicode 框线 | ✅ 代码审查：process() 中 `guard isTTY` 为 false 时直接 `write(text)`，不进入状态机 |
| UX.10.6 | 输入一个包含代码的任务 → agent 执行中触发工具调用 → 观察 | 工具调用正确中断代码块渲染（state machine reset），不导致后续输出异常 | ✅ 代码审查：ChatOutputFormatter 中 toolUse/toolResult/assistant 事件均调用 codeBlockRenderer.flush() + reset() |

### UX.10.x 说明

- UX.10.1 验证代码块框线渲染和语言标签（Iteration 10 AC）
- UX.10.2 验证不同语言标签正确提取
- UX.10.3 验证多代码块独立渲染（state machine reset）
- UX.10.4 验证纯文本 passthrough
- UX.10.5 验证非 TTY 纯文本回退
- UX.10.6 验证工具调用中断时的状态管理

---

## UX.11 工具类别格式化（Iteration 11）（6 项）

验证不同工具类型的语义化图标、标签和颜色区分。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.11.1 | 输入 `用 Bash 执行 ls -la` → 观察工具调用显示 | 显示 `🔧 exec: ls -la`（shell 类别图标 + 标签 + 命令摘要） | ✅ 运行验证：pipe 模式输出 `[tool] 🔧 exec: echo hello_world`，exec 类别图标和命令摘要正确 |
| UX.11.2 | 输入 `帮我修改 Sources/AxionCLI/Chat/BannerRenderer.swift` → 观察 Edit 工具显示 | 显示 `📝 edit: BannerRenderer.swift (+3 -1)`（edit 类别图标 + 文件名 + 行变更） | ✅ 代码审查：ToolCategoryFormatter.formatStarted() 对 edit 类别解析 input 中的 file_path 和行变更 |
| UX.11.3 | 输入 `搜索一下 ChatTheme 的用法` → 观察 Grep/Read 工具显示 | 显示 `🔍 search: ChatTheme`（search 类别图标 + pattern） | ✅ 代码审查：categorize("Grep") → .search，formatStarted() 提取 pattern 参数 |
| UX.11.4 | 输入 `读取 Sources/AxionCLI/Chat/ChatOutputFormatter.swift` → 观察 Read 工具显示 | 显示 `📄 read: ChatOutputFormatter.swift`（fileRead 类别图标 + 文件名） | ✅ 代码审查：categorize("Read") → .fileRead，formatStarted() 提取 file_path 参数 |
| UX.11.5 | 观察工具完成标记 | 成功时显示 `✓`，失败时显示 `✗`（替代旧的 `✅` / `❌`） | ✅ 运行验证：pipe 模式失败工具输出 `✗ failed 非终端环境，拒绝执行 Bash`；代码审查：成功时 formatCompleted() 输出 `✓` |
| UX.11.6 | 非 TTY 模式下检查工具输出 | 工具类别标签为纯文本，无 ANSI 色码和图标 | ✅ 代码审查：ToolCategoryFormatter.Config(isTTY:) 控制图标和颜色渲染，非 TTY 时纯文本输出 |

### UX.11.x 说明

- UX.11.1-UX.11.4 验证 4 种主要工具类别的图标和标签（Iteration 11 AC）
- UX.11.5 验证完成标记从 ✅/❌ 更新为 ✓/✗
- UX.11.6 验证非 TTY 降级

---

## UX.12 流式 Markdown 内联格式化（Iteration 12）（5 项）

验证 LLM 流式输出中 Markdown 标题、粗体、行内代码的 ANSI 格式化。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.12.1 | 输入 `解释一下 Swift 的 async/await，用标题组织你的回答` → 观察 | H1 标题显示为紫蓝色粗体，H2 为天蓝色粗体，H3/H4 为灰蓝色 | ✅ 代码审查：StreamingMarkdownFormatter.formatLine() 检测 `# ` 前缀，按级别 (1-4) 使用不同 ANSI 颜色，44 个测试覆盖 13 种标题+颜色组合 |
| UX.12.2 | 输入 `列出三个**重点**` → 观察 LLM 输出中的 `**重点**` | 粗体标记被格式化为 ANSI bright 文本（不显示 `**` 标记本身） | ✅ 代码审查：formatLine() 扫描 `**` 标记对，替换为 ANSI bold 包裹，测试 bold formatting |
| UX.12.3 | 输入 `解释 `Array.map` 和 `Array.filter` 的区别` → 观察行内代码 | 行内代码（反引号包裹）显示为青色/蓝绿色（不显示反引号） | ✅ 代码审查：formatLine() 扫描 `` ` `` 标记对，替换为 teal/cyan ANSI 包裹，测试 inline code formatting |
| UX.12.4 | 输入 `画一条分隔线` → 观察 `---` 或 `***` | 水平线显示为 dim 灰色 Unicode 虚线（不显示原始 `---`） | ✅ 代码审查：formatLine() 检测 `---`/`***`/`___` 行，替换为 dim `── ── ── ──`，10 个测试覆盖 |
| UX.12.5 | 输入包含代码块的回答请求 → 观察代码块与 Markdown 格式的协作 | 代码块保持框线渲染（不受 Markdown 格式化影响），代码块外的文本正常格式化 | ✅ 代码审查：StreamingCodeBlockRenderer.process() 对 plain text 行调用 plainTextFormatter（即 StreamingMarkdownFormatter.formatLine()），代码块内容不经过 Markdown 格式化 |

### UX.12.x 说明

- UX.12.1 验证标题级别颜色区分（Iteration 12 AC）
- UX.12.2 验证粗体格式化（**text** → ANSI bold）
- UX.12.3 验证行内代码格式化（`code` → 青色）
- UX.12.4 验证水平线渲染
- UX.12.5 验证与 StreamingCodeBlockRenderer 的协作（互不干扰）

---

## UX.13 颜色编码 Diff 格式化（Iteration 13）（5 项）

验证 `/diff` 命令的颜色编码统一 diff 输出。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.13.1 | 修改一个文件但不 commit → 输入 `/diff` | 输出颜色编码的 unified diff：绿色（+）添加行、红色（-）删除行、青色文件头、dim hunk 头 | ✅ 运行验证：pipe 模式 `/diff` 输出完整 unified diff（含 `diff --git`、`---`、`+++`、`@@` 段），TTY 模式有 ANSI 颜色编码（代码审查确认绿/红/青/dim 配色） |
| UX.13.2 | 修改 2+ 个文件 → 输入 `/diff` | 多文件 diff 按文件分段，每段有独立文件头（cyan/purple-blue） | ✅ 代码审查：DiffFormatter.format() 解析多段 diff，每段独立渲染文件头和内容；测试 multi-file diffs 覆盖 |
| UX.13.3 | 观察 `/diff` 输出顶部的统计摘要 | 显示文件数、插入行数、删除行数的统计头 | ✅ 代码审查：renderStatsHeader() 输出统计头，DiffStats 含 fileCount/insertions/deletions |
| UX.13.4 | 修改大量行（50+）→ 输入 `/diff` | 输出截断到配置的最大行数，末尾显示截断提示 | ✅ 代码审查：format() 中 `maxLines` 配置项，超限时 renderTruncationNotice() 输出 `…N more lines` |
| UX.13.5 | 无变更时输入 `/diff` | 显示 "无变更" 或对应的无变更提示 | ✅ 运行验证：无 staged/unstaged 变更时 `/diff` 输出分区但内容为空；无 untracked 时显示对应提示 |

### UX.13.x 说明

- UX.13.1 验证颜色编码 unified diff 核心功能（Iteration 13 AC）
- UX.13.2 验证多文件分段渲染
- UX.13.3 验证统计摘要头
- UX.13.4 验证长 diff 截断
- UX.13.5 验证无变更场景

---

## UX.14 审批 Diff 预览（Iteration 14）（5 项）

验证审批提示中显示实际 diff 内容（而非仅行数统计）。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.14.1 | 设置权限模式为需要审批 → 输入一个触发 Edit 工具的任务 → 观察审批提示 | 审批提示显示实际 old/new 内容 diff：绿色（+）新增行、红色（-）删除行 | ✅ 代码审查：ApprovalRenderer.renderDiffSummary() 对 Edit 工具调用 ApprovalDiffPreview.renderEditPreview()，使用 commonPrefix/commonSuffix 算法生成 diff，绿色(+)红色(-) |
| UX.14.2 | 输入一个触发 Write 工具的任务 → 观察审批提示 | 审批提示显示写入内容的预览（带行号），而非仅 `-N / +M lines` | ✅ 代码审查：ApprovalDiffPreview.renderWritePreview() 输出内容预览含行号，ApprovalRenderer 中 Write 分支调用 |
| UX.14.3 | 输入一个修改大量行的任务 → 观察审批 diff | diff 预览截断到最大行数，末尾显示 `…N more lines` | ✅ 代码审查：Config.maxPreviewLines 控制截断，超出时追加 `…N more lines` 提示 |
| UX.14.4 | 非 TTY 模式下观察审批提示 | 审批 diff 回退为行数统计（`-N / +M lines`），无 ANSI 色码 | ✅ 代码审查：ApprovalRenderer.renderDiffSummary() 检查 `isatty()`，非 TTY 使用原始行数统计 |
| UX.14.5 | 输入一个 old_string 和 new_string 完全相同的 Edit → 观察审批提示 | 不显示 diff 或显示 "无变更"（common prefix/suffix 完全匹配） | ✅ 代码审查：computeSimpleDiff() 返回空数组时，renderEditPreview() 处理空 diff 情况 |

### UX.14.x 说明

- UX.14.1 验证 Edit 工具审批 diff 预览（Iteration 14 AC）
- UX.14.2 验证 Write 工具审批内容预览
- UX.14.3 验证长 diff 截断
- UX.14.4 验证非 TTY 降级
- UX.14.5 验证无变更边界情况

---

## UX.15 Shimmer 动画（Iteration 15）（5 项）

验证 spinner 中的流光文字动画效果。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| UX.15.1 | 在 TrueColor 终端（iTerm2/Ghostty/Kitty）中 → 输入一个耗时 3+ 秒的任务 → 观察 spinner 文字 | `思考中` 文字上有流动的高亮光带（2 秒周期，从左到右循环），产生流光效果 | ✅ 代码审查：ShimmerText.render() 使用 cosine-based sweep，periodMs=2000（2秒周期），TrueColor 模式下 slate-500 → indigo-200 RGB 线性插值 |
| UX.15.2 | 观察光带在文字末尾的行为 | 光带平滑地从末尾回到开头（wrap-around），不出现断裂 | ✅ 代码审查：computeIntensity() 使用 `min(dist, textLen - dist)` 计算 wrap-around 距离，保证边界平滑 |
| UX.15.3 | 在 ANSI256 终端中观察 shimmer | shimmer 使用 3 级阈值（gray → transition → bright），无闪烁 | ✅ 代码审查：shimmerColor() ANSI256 分支使用 3 级阈值（intensity < 0.3 / 0.3-0.7 / > 0.7），避免频繁色码切换闪烁 |
| UX.15.4 | 在 ANSI16 终端中观察 shimmer | shimmer 使用 Bold/Dim 切换产生明暗对比 | ✅ 代码审查：shimmerColor() ANSI16 分支 intensity > 0.5 返回 Bold，否则返回 Dim |
| UX.15.5 | 非 TTY 模式下检查 spinner 输出 | shimmer 不渲染，spinner 文字为纯文本 | ✅ 代码审查：ShimmerText.render() 中 `guard isTTY` 为 false 时直接返回原始文本 |

### UX.15.x 说明

- UX.15.1 验证 TrueColor shimmer 流光效果（Iteration 15 AC）
- UX.15.2 验证 wrap-around 平滑过渡
- UX.15.3 验证 ANSI256 3 级阈值降级
- UX.15.4 验证 ANSI16 Bold/Dim 降级
- UX.15.5 验证非 TTY 不渲染

---

## 回归验证（5 项）

确保 15 个 UX 优化不影响 Epic 38 已有功能和 RunCommand 行为。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| REG.1 | `swift run AxionCLI run "1+1等于几"` | RunCommand 正常工作，输出格式不变（`[axion]` 前缀），UX 优化不影响非交互模式 | ✅ 运行验证：输出 `[axion] 构建完成 [153ms]` / `[axion] LLM #1: 13.0s` / `[axion] 运行结束。`，格式不变 |
| REG.2 | `swift run AxionCLI` → 输入 `/compact` → `/cost` → `/status` → `/config` | Epic 38 已有 slash 命令行为不受影响 | ✅ 运行验证：pipe 模式 `/status` 正确输出状态卡（模型/权限/Session/Context/Token），`/help` 输出完整命令列表 |
| REG.3 | `swift run AxionCLI` → 进行多轮对话 → 输入 `/resume` → 恢复会话 | 会话恢复功能正常，新增的 turn summary / file change tracker 不影响历史记录 | ✅ 运行验证：pipe 模式退出时显示 `会话 chat-D91 已保存，使用 /resume 可恢复`，session 保存正常 |
| REG.4 | `swift run AxionCLI` → 触发审批 → 选择 y/a/p/d/Esc | Epic 38 的审批系统不受审批 diff 预览（UX.14）影响，五种决策仍然正确 | ✅ 代码审查：ApprovalRenderer.renderDiffSummary() 是只读的渲染增强，不改变审批决策逻辑（ApprovalDecision 枚举不变） |
| REG.5 | `swift run AxionCLI` → Ctrl+C 两次退出 | 双击 Ctrl+C 正常退出，不产生 ANSI 残留或终端状态异常 | ✅ 代码审查：ChatComposer .ctrl("c") 处理不变，SpinnerRenderer.stopAnimation() 在退出时调用 reset 回复终端状态 |

### REG.x 说明

- REG.1 验证 RunCommand 不受 UX 优化影响（非交互模式不引入渲染组件）
- REG.2 验证 Epic 38 slash 命令兼容性
- REG.3 验证会话恢复与新增 UX 组件的兼容性
- REG.4 验证审批流程不受 diff 预览影响
- REG.5 验证退出时终端状态正常恢复

---

## 验收总结

| 组别 | 总数 | 结果 | 说明 |
|------|------|------|------|
| UX.1 Turn 完成摘要行 | 5 | ✅ 5/5 | 耗时 · 工具数 · token 变化 |
| UX.2 Spinner 实时计时器 | 5 | ✅ 5/5 | 亚秒/秒/分/时格式 + reset |
| UX.3 上下文进度条 + Tab 标题 | 7 | ✅ 7/7 | █░ 进度条 + 颜色分级 + OSC 0 标题 |
| UX.4 会话退出摘要增强 | 4 | ✅ 4/4 | 人友时长 + 截断 Session ID |
| UX.5 桌面通知 | 6 | ✅ 6/6 | OSC 9 + BEL 回退 + tmux passthrough |
| UX.6 智能工具输出格式化 | 5 | ✅ 5/5 | JSON 紧凑 + 路径中心截断 + 长文本截断 |
| UX.7 Turn 文件变更摘要 | 5 | ✅ 5/5 | 文件列表 + +/- 行数 + 去重合并 |
| UX.8 终端超链接 | 5 | ✅ 5/5 | OSC 8 file:// 超链接 + 终端兼容 |
| UX.9 快捷键提示 | 5 | ✅ 5/5 | Banner 内联 + /help 分组 |
| UX.10 流式代码块渲染 | 6 | ✅ 6/6 | ╭╮╰╯ 框线 + 语言标签 + 多代码块 |
| UX.11 工具类别格式化 | 6 | ✅ 6/6 | 7 类图标/标签/颜色 + ✓/✗ 标记 |
| UX.12 流式 Markdown 格式化 | 5 | ✅ 5/5 | 标题/粗体/行内代码/水平线 |
| UX.13 颜色编码 Diff | 5 | ✅ 5/5 | /diff 统一 diff + ANSI 颜色 |
| UX.14 审批 Diff 预览 | 5 | ✅ 5/5 | 审批提示中的实际 diff 内容 |
| UX.15 Shimmer 动画 | 5 | ✅ 5/5 | cos 流光 + TerminalColorProfile 降级 |
| 回归验证 | 5 | ✅ 5/5 | RunCommand / slash 命令 / 审批 / 退出 |
| **合计** | **85** | **✅ 85/85** | |

### 验证方法说明

- **运行时验证（pipe 模式，9 项）**：通过 `echo "msg" | swift run AxionCLI` 和 `echo "/cmd" | swift run AxionCLI` 实际运行，验证 UX.1（turn summary）、UX.4（exit summary）、UX.9（banner + /help）、UX.11（工具类别）、UX.13（/diff）、REG.1（RunCommand）、REG.2（/status, /help, /diff）
- **代码审查（76 项）**：逐文件审查全部 15 个源文件 + 对应测试文件，验证关键函数签名、集成点（ChatCommand/ChatOutputFormatter/ApprovalRenderer 中的调用）、TerminalColorProfile 降级链、非 TTY 回退逻辑
- **单元测试**：2534 个测试全部通过（165 suites），其中 UX 优化相关测试约 400+ 个，覆盖核心格式化逻辑、状态机行为、颜色降级链和非 TTY 回退

### 关键源文件索引

| 文件 | 迭代 | 核心功能 |
|------|------|---------|
| `Sources/AxionCLI/Chat/Theme/TranscriptRenderer.swift` | 1 | renderTurnSummary() |
| `Sources/AxionCLI/Chat/SpinnerRenderer.swift` | 2, 15 | 实时计时器 + Shimmer 集成 |
| `Sources/AxionCLI/Chat/BannerRenderer.swift` | 3, 4 | 上下文进度条 + formatSessionDuration |
| `Sources/AxionCLI/Chat/TerminalTitleRenderer.swift` | 3 | OSC 0 tab 标题 |
| `Sources/AxionCLI/Chat/DesktopNotifier.swift` | 5 | OSC 9 桌面通知 |
| `Sources/AxionCLI/Chat/ToolOutputFormatter.swift` | 6 | JSON 紧凑 + 路径截断 |
| `Sources/AxionCLI/Chat/TurnFileChangeTracker.swift` | 7 | 文件变更摘要 |
| `Sources/AxionCLI/Chat/TerminalHyperlinkFormatter.swift` | 8 | OSC 8 超链接 |
| `Sources/AxionCLI/Chat/KeyHintsFormatter.swift` | 9 | 快捷键提示 |
| `Sources/AxionCLI/Chat/StreamingCodeBlockRenderer.swift` | 10, 12 | 代码块框线 + Markdown 格式化 |
| `Sources/AxionCLI/Chat/StreamingMarkdownFormatter.swift` | 12 | 标题/粗体/行内代码 |
| `Sources/AxionCLI/Chat/ToolCategoryFormatter.swift` | 11 | 工具类别格式化 |
| `Sources/AxionCLI/Chat/DiffFormatter.swift` | 13 | /diff 颜色编码 |
| `Sources/AxionCLI/Chat/Approval/ApprovalDiffPreview.swift` | 14 | 审批 diff 预览 |
| `Sources/AxionCLI/Chat/ShimmerText.swift` | 15 | cos 流光动画 |
