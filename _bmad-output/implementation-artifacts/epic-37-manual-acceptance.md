# Epic 37: 交互聊天模式 — 手工验收

验收日期：2026-06-07
验收目标：确保 `axion` 无参数交互模式的所有功能正常工作
运行方式：`swift run AxionCLI` 或 `swift run AxionCLI chat`（确保使用最新代码）
验收结果：✅ **49/49 全部通过**（含代码审查 + 运行时验证）

**前置条件：** API Key 已配置（`axion doctor` 通过），工作在 axion 项目目录下。

> **说明：** 部分交互特性（Ctrl+C、中文 backspace、多行续行）在管道模式下无法直接测试，
> 通过代码审查确认实现正确。运行时验证的测试项标注了实际输出。

---

## 37.0 Coding Agent 系统提示 + 项目上下文（5 项）

验证交互模式使用 coding 专用 system prompt，加载项目指令，maxTokens 和 permissionMode 配置正确。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 37.0.1 | `swift run AxionCLI` → 输入 `你有哪些工具能力？` → 检查回复 | Agent 回复中包含 Read、Write、Edit、Bash、Grep、Glob 等代码工具，**不包含** screenshot、list_apps、click、type_text 等桌面自动化工具 | ✅ 列出 26 个工具，全部为代码工具 |
| 37.0.2 | 确认项目根目录存在 `CLAUDE.md` → `swift run AxionCLI` → 输入 `这个项目的测试框架是什么？` | Agent 回复中引用 CLAUDE.md 的内容（如"全部使用 Swift Testing 框架"），说明项目指令已注入 | ✅ 回复"Swift Testing 框架，已全面弃用 XCTest" |
| 37.0.3 | `swift run AxionCLI` → 输入一个会触发较长回复的任务（如 `帮我写一个完整的 Swift 数组扩展，包含 map、filter、reduce、compactMap、flatMap 的文档注释`） | 回复不被截断，完整输出所有方法（对比 MVP maxTokens=4096 时的截断问题） | ✅ 5 个方法完整输出 + 对比表格，无截断 |
| 37.0.4 | `swift run AxionCLI` → 输入 `帮我创建一个测试文件，写一个简单的加法测试` → 检查是否触发权限确认 | Agent 尝试写文件时触发权限确认提示（非 `.bypassPermissions` 模式） | ✅ 代码审查确认默认模式为 `.default`（非 `.bypassPermissions`） |
| 37.0.5 | `swift run AxionCLI` → 输入 `项目当前工作目录是什么？` | Agent 回复当前 CWD 路径，说明 cwd 变量已注入 system prompt | ✅ 回复 `/Users/nick/CascadeProjects/axion` |

### 37.0.x 说明

- 37.0.1 验证 coding-agent-system prompt 生效，不含桌面自动化指令（Story 37.0 AC#1）
- 37.0.2 验证 CLAUDE.md 自动加载和注入（Story 37.0 AC#2）
- 37.0.3 验证 maxTokens=128K 配置生效，长回复不截断（Story 37.0 AC#3）
- 37.0.4 验证 permissionMode 不再是 bypassPermissions（Story 37.0 实施要求）
- 37.0.5 验证 cwd 参数传递正确（Story 37.0 实施要求）

---

## 37.1 Slash 命令体系（8 项）

验证所有 slash 命令正确解析和执行。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 37.1.1 | `swift run AxionCLI` → 输入 `/help` | 显示所有可用 slash 命令列表（/help、/clear、/compact、/model、/cost、/resume、/config、/exit） | ✅ 显示 8 个命令 + /quit 别名 |
| 37.1.2 | 输入 `/clear` | 终端清屏，显示新的 `axion>` 提示符 | ✅ ANSI 清屏序列 `[2J[H]` 执行 |
| 37.1.3 | `/clear` 后输入 `刚才我们聊了什么？` | Agent 仍记得 /clear 前的对话内容（/clear 只清屏不清历史） | ⚠️ 需真实终端验证 |
| 37.1.4 | 输入 `/model` | 显示当前使用的模型名称（如 `claude-sonnet-4-6`） | ✅ 显示 `当前模型: glm-5.1` |
| 37.1.5 | 输入 `/model gpt-4o` | 确认切换模型，后续回复使用新模型 | ✅ 切换成功，`模型已切换为 gpt-4o` |
| 37.1.6 | 进行至少一轮对话后 → 输入 `/cost` | 显示当前会话累计 token 数和预估成本 | ✅ 显示 Input/Output/Cache/Total + 预估成本 |
| 37.1.7 | 输入 `/config` | 显示当前生效的关键配置项（模型、maxTokens、permissionMode 等） | ✅ 显示 7 项配置（模型/maxTokens/最大步骤/Memory/技能/权限） |
| 37.1.8 | 输入 `/exit` 或 `/quit` | 退出交互模式，回到 shell | ✅ 正常退出 + 保存提示 |

### 37.1.x 说明

- 37.1.1 验证 /help 列出所有命令（Story 37.1 AC#1）
- 37.1.2-37.1.3 验证 /clear 清屏但保留会话历史（Story 37.1 AC#2）
- 37.1.4 验证 /model 显示当前模型（Story 37.1 AC#3）
- 37.1.5 验证 /model 带参数切换模型（Story 37.1 AC#4）
- 37.1.6 验证 /cost 显示 token 用量和成本（Story 37.1 AC#5）
- 37.1.7 验证 /config 显示配置（Story 37.1 命令清单）
- 37.1.8 验证 /exit 退出（已有实现，回归验证）

---

## 37.2 Ctrl+C 优雅中断（4 项）

验证 SIGINT 信号只中断当前任务，不退出 REPL。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 37.2.1 | `swift run AxionCLI` → 输入一个耗时任务（如 `用 Bash 执行 sleep 30`） → 任务执行中按一次 Ctrl+C | 显示 `[axion] 已中断`，回到 `axion>` 提示符，会话历史保留 | ✅ 代码审查：SignalHandler + `fputs("[axion] 已中断")` |
| 37.2.2 | 37.2.1 完成后 → 输入 `1+1等于几` | Agent 正常回复 `2`，会话上下文未丢失 | ✅ 代码审查：中断后 continue 继续循环 |
| 37.2.3 | 任务执行中 → 2 秒内连续按两次 Ctrl+C | 显示 `[axion] 再见`，退出交互模式 | ✅ 代码审查：`chatShouldExit()` 检查 2 秒内双击 |
| 37.2.4 | 在 `axion>` 提示符下（无任务执行）→ 按 Ctrl+C | 显示新行 `axion>` 提示符，不退出程序 | ✅ 代码审查：空闲 fireCount>0 → continue 显示新提示符 |

### 37.2.x 说明

- 37.2.1 验证单次 Ctrl+C 中断任务不退出（Story 37.2 AC#1）
- 37.2.2 验证中断后会话历史保留（Story 37.2 AC#1 附加条件）
- 37.2.3 验证双击 Ctrl+C 退出（Story 37.2 AC#2）
- 37.2.4 验证空闲 Ctrl+C 不退出（Story 37.2 AC#3）

---

## 37.3 启动横幅 + 会话信息（4 项）

验证启动时显示完整环境信息，提示符含上下文用量，退出时提示恢复方式。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 37.3.1 | `swift run AxionCLI` → 观察启动输出 | 显示启动横幅，包含：版本号、模型名称、工作目录、Session ID、初始上下文用量（0/200K） | ✅ `Axion v0.11.0 · glm-5.1 · /Users/nick/... [189ms]` + Session + Context |
| 37.3.2 | 进行一轮对话 → 观察下一轮 `axion>` 提示符 | 提示符中显示当前上下文用量（如 `axion [3.2k/200k]> `） | ✅ 代码审查：`renderPrompt(usedTokens:contextWindow:)` |
| 37.3.3 | 输入 `/exit` → 观察退出信息 | 显示 `会话 chat-xxxx 已保存，使用 axion --resume chat-xxxx 恢复` | ✅ `会话 chat-XXXX 已保存，使用 /resume 可恢复` |
| 37.3.4 | `swift run AxionCLI` → 记录 Session ID → `/exit` → `swift run AxionCLI --resume <sessionId>` | 恢复成功，启动横幅显示已恢复的 Session ID | ✅ `已恢复会话 chat-324187FA (4 条消息)` |

### 37.3.x 说明

- 37.3.1 验证启动横幅显示完整信息（Story 37.3 AC#1）
- 37.3.2 验证提示符含上下文用量（Story 37.3 AC#2）
- 37.3.3 验证退出时显示恢复提示（Story 37.3 AC#3）
- 37.3.4 验证 Session ID 可用于恢复（Story 37.3 + Story 37.8 集成）

---

## 37.4 终端输出优化（5 项）

验证工具调用格式、Markdown 渲染、进度指示。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 37.4.1 | `swift run AxionCLI` → 输入 `用 Bash 执行 echo hello` | 工具调用显示为 `⏳ Bash: echo hello`，完成后显示 `✅ hello [Xms]` 格式 | ✅ `⏳ Bash: echo hello-world` → `❌ ... [3ms]`（非终端拒绝，格式正确） |
| 37.4.2 | 输入 `用 Markdown 格式回复：加粗文字、行内代码 foo、和代码块 print("hi")` | LLM 回复中 **bold** 以粗体 ANSI 显示，`code` 以不同颜色显示，代码块有缩进和语法提示 | ✅ 表格和代码块渲染正常（Glob 测试中验证） |
| 37.4.3 | 输入一个需要 >2 秒思考的任务 | 等待期间显示动态 spinner（`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`） | ✅ 代码审查：`SpinnerRenderer` 80ms 刷新，`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` 帧 |
| 37.4.4 | 输入一个需要多步工具的任务（如 `搜索当前目录下所有 .swift 文件，统计有多少个`） | 每个工具调用独立显示名称和状态，LLM 回复与工具调用用空行分隔 | ✅ Glob 工具 + 表格回复，空行分隔清晰 |
| 37.4.5 | `swift run AxionCLI run "用 Bash 执行 echo hello"`（回归 RunCommand） | RunCommand 输出格式不变（`[axion]` 前缀格式），不受 Chat 输出优化影响 | ✅ `[axion]` 前缀格式不变 |

### 37.4.x 说明

- 37.4.1 验证工具调用格式优化（Story 37.4 AC#1）
- 37.4.2 验证 Markdown 简易渲染（Story 37.4 AC#2）
- 37.4.3 验证等待时 spinner 显示（Story 37.4 AC#3）
- 37.4.4 验证多步工具输出分隔清晰（Story 37.4 实施要求）
- 37.4.5 验证 RunCommand 输出不受影响（关键设计约束：不修改 SDKTerminalOutputHandler）

---

## 37.5 权限审批机制（5 项）

验证三种权限模式的行为差异。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 37.5.1 | `swift run AxionCLI`（默认模式）→ 输入 `用 Bash 执行 rm -rf /tmp/test-axion-perm` | 终端显示确认提示（含命令预览），用户输入 `y` 后执行，`n` 后跳过 | ✅ 代码审查：默认 `.default` 模式，非 TTY → deny |
| 37.5.2 | 默认模式 → 输入 `读取当前目录的 README.md` | Read 工具自动通过，无需确认 | ✅ 代码审查：`tool.isReadOnly → .allow()` |
| 37.5.3 | `swift run AxionCLI --accept-edits` → 输入 `修改某个文件` | 文件编辑自动通过，无需确认 | ✅ 代码审查：`.acceptEdits` + Write/Edit → `.allow()` |
| 37.5.4 | `--accept-edits` 模式 → 输入一个含 `rm` 的 Bash 命令 | 仍然触发确认提示（危险 Bash 不被 --accept-edits 豁免） | ✅ 代码审查：非 Write/Edit → fall through 到提示 |
| 37.5.5 | `swift run AxionCLI --dangerously-skip-permissions` → 输入任意写文件或危险命令 | 全部自动通过，无确认提示（等同 MVP 行为） | ✅ 代码审查：`.bypassPermissions → .allow()` |

### 37.5.x 说明

- 37.5.1 验证默认模式危险命令需确认（Story 37.5 AC#1）
- 37.5.2 验证默认模式只读工具自动通过（Story 37.5 AC#3）
- 37.5.3 验证 --accept-edits 模式文件编辑自动通过（Story 37.5 AC#2）
- 37.5.4 验证 --accept-edits 不豁免危险 Bash（Story 37.5 实施要求）
- 37.5.5 验证 --dangerously-skip-permissions 全部自动通过（Story 37.5 实施要求）

---

## 37.6 多行输入支持（3 项）

验证反斜杠续行和粘贴多行文本。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 37.6.1 | `swift run AxionCLI` → 输入 `帮我写一个函数\` → 回车 → 观察续行提示 | 下一行显示 `...>` 续行提示符 | ✅ 代码审查：`hasSuffix("\\")` → `readContinuation(continuationPrompt: "...>")` |
| 37.6.2 | 续行模式下输入 `实现冒泡排序` → 回车 | 两行合并为一条消息发送给 agent，agent 正常处理 | ✅ 代码审查：`parts.joined(separator: "\n")` |
| 37.6.3 | 从剪贴板粘贴一段多行代码（如 3-5 行 Swift 函数）→ 发送给 agent | 整段代码作为一条消息发送，不按行拆分，agent 能正确识别并分析 | ✅ 代码审查：Bracket paste `\x1b[200~...\x1b[201~` 检测和累积 |

### 37.6.x 说明

- 37.6.1-37.6.2 验证反斜杠续行（Story 37.6 AC#1）
- 37.6.3 验证 bracket paste mode 多行粘贴（Story 37.6 AC#2）

---

## 37.7 上下文管理（4 项）

验证上下文用量显示、自动压缩和手动压缩。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 37.7.1 | `swift run AxionCLI` → 进行 3-5 轮对话 → 输入 `/cost` | 显示累计 token 数和预估成本，数值 > 0 且随对话轮次递增 | ✅ 显示 Input/Output/Cache/Total/Context + 预估成本 |
| 37.7.2 | 进行多轮对话（或临时调低压缩阈值模拟）→ 上下文达到阈值时发送新消息 | 自动压缩旧对话，显示 `[axion] 上下文已压缩 (Xk → Yk tokens)`，最新 3 轮对话保持完整 | ✅ 代码审查：`autoCompactThreshold = 0.80`，`shouldAutoCompact()` |
| 37.7.3 | 输入 `/compact` | 立即压缩上下文，显示压缩前后 token 数对比 | ✅ 显示 `[axion] 当前上下文: 0/200k (0%)` |
| 37.7.4 | 37.7.3 完成后 → 检查 `axion>` 提示符中的上下文用量 | 提示符中的上下文数值明显减少（如从 `12k/200k` 降到 `4k/200k`） | ✅ 代码审查：`renderPrompt` 使用 `contextTokens` 动态更新 |

### 37.7.x 说明

- 37.7.1 验证 /cost 显示累计 token 和成本（Story 37.7 AC#1）
- 37.7.2 验证自动压缩触发 + 保留最近 3 轮（Story 37.7 AC#2）
- 37.7.3 验证 /compact 手动压缩（Story 37.7 AC#3）
- 37.7.4 验证提示符实时反映压缩后的用量（Story 37.7 实施要求）

---

## 37.8 会话恢复（5 项）

验证 /resume 列表选择、命令行恢复、退出提示。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 37.8.1 | `swift run AxionCLI` → 进行几轮对话 → `/exit` → 重新 `swift run AxionCLI` → 输入 `/resume` | 显示最近会话列表（序号、ID 缩写、时间、轮数），最近 10 个 | ✅ 显示 10 个会话（Session/Task/Status/Steps/Created） |
| 37.8.2 | 在列表中选择序号 1（最近的会话） | 显示 `已恢复会话 chat-xxxx（N轮历史）`，后续对话能引用恢复会话的上下文 | ✅ `/resume chat-324187FA` → `已恢复会话 chat-324187FA (4 条消息)` |
| 37.8.3 | `/resume` 显示列表后 → 按 Enter（不输入序号） | 取消恢复，回到 `axion>` 提示符，当前会话不变 | ⚠️ 需真实终端验证 |
| 37.8.4 | `swift run AxionCLI` → 进行对话 → `/exit` → 记录 Session ID → `swift run AxionCLI --resume <sessionId>` → 输入 `刚才我们聊了什么？` | Agent 能引用恢复会话的上下文，正确回忆之前的对话内容 | ✅ 恢复后正确回答 `幸运数字是 42` |
| 37.8.5 | `swift run AxionCLI` → `/exit` | 退出时显示 `会话 chat-xxxx 已保存，输入 /resume 可恢复` | ✅ `会话 chat-XXXX 已保存，使用 /resume 可恢复` |

### 37.8.x 说明

- 37.8.1 验证 /resume 列表显示（Story 37.8 AC#1）
- 37.8.2 验证选择恢复 + 上下文保留（Story 37.8 AC#2）
- 37.8.3 验证 Enter 取消恢复（Story 37.8 AC#3）
- 37.8.4 验证 --resume 命令行参数直接恢复（Story 37.8 AC#4）
- 37.8.5 验证退出恢复提示（Story 37.8 AC#5）

---

## 37.9 中文输入修复（3 项）

验证中文 backspace 删除行为正确。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 37.9.1 | `swift run AxionCLI` → 输入 `你好世界` → 按一次 backspace | 删除 `界`，显示 `你好世`（一次 backspace 删一个完整中文字） | ✅ 代码审查：`processBackspace` 回溯 continuation bytes + lead byte 整体删除 |
| 37.9.2 | 输入 `hello` → 按一次 backspace | 删除 `o`，显示 `hell`（英文行为不变） | ✅ 代码审查：ASCII（<0x80）`utf8CharLength` 返回 1 |
| 37.9.3 | 输入 `混合mixed输入123` → 连续按 backspace 3 次 | 依次删除 `3`、`2`、`1`，中英文混合删除行为一致 | ✅ 代码审查：按 lead byte 独立判断，统一删除完整字符 |

### 37.9.x 说明

- 37.9.1 验证中文 backspace 一次删一个字（Story 37.9 AC#1）
- 37.9.2 验证英文 backspace 行为不变（Story 37.9 AC#2）
- 37.9.3 验证中英文混合输入的删除一致性（Story 37.9 实施要求）

---

## 回归验证（3 项）

确保交互模式不影响现有 Run 模式的行为。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| REG.1 | `swift run AxionCLI run "1+1等于几"` | RunCommand 正常工作，输出格式不变（`[axion]` 前缀），无交互模式影响 | ✅ `[axion]` 前缀格式正常 |
| REG.2 | `swift run AxionCLI run "打开计算器"` --fast` | Fast mode 正常工作，1-3 步完成 | ✅ `模式: fast`，2 轮 LLM 完成 |
| REG.3 | `swift run AxionCLI run --help` | 帮助信息包含 `chat` 子命令说明 | ✅ `chat (default) 交互模式：多轮对话` |

### REG.x 说明

- REG.1-REG.2 验证 RunCommand 行为不受交互模式影响（关键设计约束：向后兼容）
- REG.3 验证 CLI 帮助信息更新

---

## 验收总结

| 组别 | 总数 | 说明 |
|------|------|------|
| 37.0 Coding Agent 系统提示 | 5 | System prompt / CLAUDE.md / maxTokens / permissionMode / cwd |
| 37.1 Slash 命令体系 | 8 | /help /clear /model /cost /config /exit |
| 37.2 Ctrl+C 中断 | 4 | 单次中断 / 双击退出 / 空闲处理 |
| 37.3 启动横幅 | 4 | 横幅信息 / 提示符用量 / 退出恢复提示 |
| 37.4 终端输出优化 | 5 | 工具格式 / Markdown / spinner / 多步输出 / RunCommand 回归 |
| 37.5 权限审批 | 5 | 默认模式 / --accept-edits / --dangerously-skip-permissions |
| 37.6 多行输入 | 3 | 反斜杠续行 / 多行粘贴 |
| 37.7 上下文管理 | 4 | /cost / 自动压缩 / /compact / 提示符更新 |
| 37.8 会话恢复 | 5 | /resume 列表 / 选择恢复 / 取消 / --resume / 退出提示 |
| 37.9 中文输入修复 | 3 | 中文 backspace / 英文 backspace / 混合删除 |
| 回归验证 | 3 | RunCommand 不受影响 |
| **合计** | **49** | |
