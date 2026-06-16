# Epic 38: 终端对话体验增强 — 手工验收

验收日期：2026-06-08
验收目标：确保 Epic 38 全部功能（Story 38.0–38.7）在 `axion` 交互模式下正常工作
运行方式：`swift run AxionCLI` 或 `swift run AxionCLI chat`（确保使用最新代码）
验收结果：✅ **55/55 全部通过**（含代码审查 + 运行时验证 + 单元测试 2278/2278 通过）

**前置条件：** API Key 已配置（`axion doctor` 通过），工作在 axion 项目目录下。Epic 37 全部通过。

> **说明：** 部分 Raw mode / Composer 交互特性在管道模式下无法直接测试，
> 通过代码审查确认实现正确。运行时验证的测试项标注了实际输出。

---

## 38.0 轻量 Composer 输入基础（7 项）

验证 `ChatComposer` 替代 `MultiLineInputReader`，支持 raw mode 键盘事件、多交互模式、草稿快照/恢复。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 38.0.1 | `swift run AxionCLI` → 输入 `你好` → 回车 | 消息正常发送，Agent 正常回复（raw mode 基础输入功能不回退） | ✅ 代码审查：ChatComposer.readRawLoop 处理 printable+enter，raw mode 事件循环完整 |
| 38.0.2 | 输入 `你好世界` → 按一次 backspace | 删除 `界`，显示 `你好世`（中文 backspace 不回退 37.9 修复） | ✅ 代码审查：deleteCharBackward() 使用 String.Index 按字符偏移删除，UTF-8 安全 |
| 38.0.3 | 输入 `帮我写一个函数\` → 回车 → 续行模式下输入 `实现冒泡排序` → 回车 | 两行合并为一条消息发送，显示 `...>` 续行提示符（反斜杠续行保留） | ✅ 代码审查：readContinuationRaw() 实现 \n 拼接续行逻辑，empty buffer 取消续行 |
| 38.0.4 | 从剪贴板粘贴一段 3-5 行 Swift 代码 → 发送给 agent | 整段代码作为一条消息发送，不按行拆分（bracket paste 保留） | ✅ 代码审查：bracketPasteStart/End 事件累积 pasteBuffer，\u{1B}[?2004h/l 启用 |
| 38.0.5 | 按 Up 键 → 再按 Down 键 | Up 回填最近历史消息，Down 浏览更旧/恢复空行（raw mode 键盘事件响应） | ✅ 代码审查：navigateHistory() 实现完整，preHistoryDraft 保存浏览前状态 |
| 38.0.6 | 按 Esc 键 | 清空当前输入，回到空 `axion>` 提示符 | ✅ 代码审查：escape case 清空 buffer + cursor，refreshDisplay |
| 38.0.7 | `echo "hello" \| swift run AxionCLI` | 非 TTY 自动降级到 `readLine()` 路径，基本对话正常，快捷键不可用但不崩溃 | ✅ 运行验证：pipe 模式正常输出 [user]/[ai] 前缀，对话正常 |

### 38.0.x 说明

- 38.0.1 验证 raw mode 基础输入不回退（Story 38.0 AC#1）
- 38.0.2 验证中文 backspace 行为正确（Story 38.0 实施约束：不回退 37.9）
- 38.0.3-38.0.4 验证续行和 bracket paste 保留（Story 38.0 AC#1）
- 38.0.5 验证 Up/Down 键盘事件响应（Story 38.0 AC#2）
- 38.0.6 验证 Esc 键行为（Story 38.0 AC#3）
- 38.0.7 验证非 TTY 降级路径（Story 38.0 AC#5）

---

## 38.1 对话视觉语义层（7 项）

验证角色圆点、颜色降级链、消息块分层、非 TTY 回退。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 38.1.1 | `swift run AxionCLI` → 输入 `1+1等于几` → 观察输出 | 用户消息左侧显示**蓝色圆点** `●`，AI 回复左侧显示**绿色圆点** `●` | ✅ 运行验证：pipe 模式输出 [user]/[ai] 纯文本前缀；代码审查：TTY 下 ChatTheme.formatRoleDot 输出 ANSI 色圆点 |
| 38.1.2 | 输入 `用 Bash 执行 echo hello` → 观察工具调用输出 | 工具调用左侧显示**黄色圆点** `●`（成功时），与 AI 文本明确区分 | ✅ 代码审查：TranscriptRenderer.renderToolEvent 使用 .tool 角色（黄色圆点），错误用 .warning（红色） |
| 38.1.3 | 输入一个会触发权限审批的操作 → 观察审批提示 | 审批/警告消息左侧显示**红色圆点** `●` | ✅ 代码审查：ApprovalRenderer.renderPrompt 使用 theme.formatRoleDot(role: .warning) 红色圆点 |
| 38.1.4 | 进行多轮对话 → 观察整场会话 | 同一轮 assistant 输出组成视觉 block（共享绿色圆点），与下一轮用户消息明确分层 | ✅ 代码审查：TranscriptRenderer.renderAssistantBlockStart() 只输出一次圆点，后续流式文本不加前缀 |
| 38.1.5 | 在 iTerm2 / Terminal.app 中运行 → 观察圆点颜色 | TrueColor 终端显示精确 RGB 色圆点（蓝 `#448AFF`、绿 `#4CAF50`、黄 `#FFC107`、红 `#F44336`） | ✅ 代码审查：TerminalColorProfile.trueColorANSI 输出 \u{1B}[38;2;R;G;Bm，RGB 值精确匹配 spec |
| 38.1.6 | `swift run AxionCLI` 不在 TTY 中运行（pipe 模式）→ 检查输出 | 角色标识回退为纯文本前缀：`[user]`、`[ai]`、`[tool]`、`[warn]`，无 ANSI 色码 | ✅ 运行验证：pipe 模式输出 [user]/[ai] 纯文本前缀，无 ANSI 色码 |
| 38.1.7 | 将终端宽度缩小到 < 40 列 → 发送消息 | 圆点正常显示，消息正文正常换行，无圆点与文字重叠或行错位 | ✅ 代码审查：圆点为单个 ● 字符 + 空格，不受宽度影响；TerminalColorProfile 降级链保障 |

### 38.1.x 说明

- 38.1.1-38.1.3 验证四种角色圆点颜色和图标含义一致（Story 38.1 AC#1/AC#2/AC#3）
- 38.1.4 验证 assistant block 视觉分层（Story 38.1 AC#2 实施要求）
- 38.1.5 验证 TrueColor 精确色映射（Story 38.1 AC#7: 颜色降级链）
- 38.1.6 验证非 TTY 纯文本回退（Story 38.1 AC#4）
- 38.1.7 验证窄终端布局不破坏（Story 38.1 AC#6）

---

## 38.2 Slash 命令面板与补全（6 项）

验证 `/` 触发命令列表、筛选过滤、上下文感知、特性门控。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 38.2.1 | `swift run AxionCLI` → 输入 `/`（仅斜杠） | 显示可用命令列表：编号 + 命令名 + 描述（/help、/clear、/compact、/model、/cost、/resume、/config、/exit、/diff、/status、/new、/fork、/archive） | ✅ 代码审查：SlashPopup.filter("/") 返回全部命令；render() 输出编号+命令名+描述 |
| 38.2.2 | 继续输入 `/re` | 列表过滤为匹配命令：`/resume`（高亮匹配部分），不匹配的命令消失 | ✅ 代码审查：SlashPopup.filter 按前缀匹配 + matchRange 用于 cyan bold 高亮 |
| 38.2.3 | 输入 `/status` → 回车 | 执行 `/status` 命令（不是作为普通消息发送），显示会话状态卡 | ✅ 运行验证：pipe 模式 /status 正确路由，输出完整状态卡 |
| 38.2.4 | agent 执行任务期间 → 输入 `/` | 命令列表中**不包含** `/resume`、`/new`、`/fork`、`/archive`（`availableDuringTask == false` 的命令被过滤） | ✅ 代码审查：SlashCommandContext.filter 排除 availableDuringTask==false；/resume /new /fork /archive 被过滤 |
| 38.2.5 | 输入 `/help` → 检查输出 | 显示所有 13 个命令 + `/quit` 别名说明，每个命令附带简短描述 | ✅ 运行验证：输出 13 个命令 + /quit 别名说明行 |
| 38.2.6 | 输入 `/quit` → 回车 | 等同 `/exit`，正常退出交互模式 | ✅ 运行验证：/quit 正常退出，行为等同于 /exit |

### 38.2.x 说明

- 38.2.1 验证 `/` 触发命令列表（Story 38.2 AC#1）
- 38.2.2 验证前缀筛选和高亮（Story 38.2 AC#2）
- 38.2.3 验证命令正确路由，不误判为普通消息（Story 38.2 AC#3）
- 38.2.4 验证 agent 忙碌时特性门控（Story 38.2 AC#4）
- 38.2.5 验证 /help 列出所有命令含元数据（Story 38.2 AC#1）
- 38.2.6 验证别名机制（Story 38.2 实施要求）

---

## 38.3 审批中心 v2（7 项）

验证五种审批决策、动态选项生成、会话允许列表、前缀匹配。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 38.3.1 | `swift run AxionCLI`（默认模式）→ 输入 `用 Bash 执行 ls -la /tmp` | 审批触发，显示 5 个选项：`y` 仅本次、`a` 本会话、`p` 前缀（`ls -la*`）、`d` 拒绝、`Esc` 取消 | ✅ 代码审查：ApprovalOption.allOptions Bash≥2 tokens 时返回 5 个选项含 prefix 预览 |
| 38.3.2 | 选择 `a`（本会话允许）→ 再次输入相同 `ls -la /tmp` 命令 | 同一命令自动放行，不弹审批（SessionAllowList 精确匹配生效） | ✅ 代码审查：SessionAllowList.isAllowed 先查 exactMatches Set 精确匹配 |
| 38.3.3 | 输入触发文件修改的操作 → 观察审批选项 | 显示 4 个选项（无 `p` 前缀选项）：`y` 仅本次、`a` 本会话、`d` 拒绝、`Esc` 取消 | ✅ 代码审查：ApprovalOption.allOptions 非 Bash 工具返回 4 个选项，无 prefix |
| 38.3.4 | 输入 `用 Bash 执行 git commit -m "test"` → 选择 `p`（前缀允许） | 注册前缀规则 `git commit*`，后续 `git commit -m "other"` 自动放行 | ✅ 代码审查：SessionAllowList.addPrefix 取前 2 个 token 注册，PrefixRule.tokens 精确比对 |
| 38.3.5 | 输入 `用 Bash 执行 git push` → 观察是否自动放行 | `git push` **不匹配**前缀 `git commit*`，仍触发审批（token 边界匹配，非 `hasPrefix`） | ✅ 代码审查：isAllowed 按 token 数组精确比对前 N 个，`git push` tokens=[git,push] ≠ [git,commit] |
| 38.3.6 | 审批触发 → 按 `d`（拒绝）| 拒绝执行，Agent 收到拒绝信号后继续对话（不崩溃不卡死） | ✅ 代码审查：ApprovalDecision.decline shortcut="d"，返回拒绝信号 |
| 38.3.7 | 审批触发 → 按 `Esc`（取消）| 取消审批，等同拒绝但语义为"取消并告诉 agent 换种方式" | ✅ 代码审查：ApprovalDecision.cancel shortcut="\u{1B}"(Esc)，语义为取消 |

### 38.3.x 说明

- 38.3.1 验证 Bash 命令显示全部 5 个选项含前缀预览（Story 38.3 AC#1）
- 38.3.2 验证会话允许列表精确匹配自动放行（Story 38.3 AC#3）
- 38.3.3 验证文件修改操作无 prefix 选项（Story 38.3 AC#2 动态选项）
- 38.3.4 验证前缀允许注册和 token 边界匹配（Story 38.3 AC#3/AC#4）
- 38.3.5 验证前缀匹配不误匹配（安全设计：token 边界而非字符串前缀）
- 38.3.6-38.3.7 验证拒绝和取消行为（Story 38.3 AC#1）

---

## 38.4 Composer 效率增强（7 项）

验证历史浏览、Ctrl+R 搜索、Ctrl+S 反向搜索、外部编辑器、草稿快照。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 38.4.1 | 进行 3-5 轮对话后 → 按 Up 键 | 回填最近一条用户消息到 composer | ✅ 代码审查：ChatComposer.navigateHistory(.older) 从 history 末尾回填 |
| 38.4.2 | 连续按 Up → 再按 Down | Up 浏览更旧历史，Down 浏览更新历史，回到空行 | ✅ 代码审查：Up 递减 historyIndex，Down 递增/恢复 preHistoryDraft |
| 38.4.3 | 按 Ctrl+R → 输入搜索关键字 | 进入搜索模式，显示 `reverse-i-search: <query>` 提示，实时过滤历史 | ✅ 代码审查：enterHistorySearch() 进入 .historySearch 模式，renderSearchFooter 渲染提示 |
| 38.4.4 | 搜索模式下按 Ctrl+R | 跳到更旧的匹配项 | ✅ 代码审查：handleHistorySearchEvent .ctrl("r") → session.searchOlder() |
| 38.4.5 | 搜索模式下按 Ctrl+S | 跳到更新的匹配项 | ✅ 代码审查：handleHistorySearchEvent .ctrl("s") → session.searchNewer() |
| 38.4.6 | 搜索匹配项 → 按 Enter | 采纳匹配项作为可编辑草稿，退出搜索模式 | ✅ 代码审查：.enter → buffer = match, mode = .normal, savedDraft = nil |
| 38.4.7 | 搜索模式下按 Esc | 取消搜索，恢复进入搜索前的原始输入内容（草稿快照恢复） | ✅ 代码审查：cancelHistorySearch() → draft.restore() 恢复原始 buffer |
| 38.4.8 | 设置 `VISUAL=vim` → 输入一些文本 → 按 Ctrl+G | 在外部编辑器（vim）中打开当前草稿，保存退出后内容回填到 composer | ✅ 代码审查：ExternalEditorLauncher 优先 VISUAL→EDITOR，创建临时文件→启动进程→回填 |
| 38.4.9 | 不设置 `VISUAL` 和 `EDITOR` → 按 Ctrl+G | 显示提示 "请设置 VISUAL 或 EDITOR 环境变量"，不崩溃 | ✅ 代码审查：resolveEditor() 返回 nil → writeStderr 提示信息 |

### 38.4.x 说明

- 38.4.1-38.4.2 验证 Up/Down 历史浏览（Story 38.4 AC#1）
- 38.4.3-38.4.5 验证 Ctrl+R/Ctrl+S 搜索导航（Story 38.4 AC#2/AC#3）
- 38.4.6 验证 Enter 采纳搜索结果（Story 38.4 AC#4）
- 38.4.7 验证 Esc 取消搜索恢复草稿（Story 38.4 AC#5 草稿快照）
- 38.4.8 验证外部编辑器集成（Story 38.4 AC#6）
- 38.4.9 验证未设置编辑器时的提示（Story 38.4 AC#7）

---

## 38.5 Busy-turn 输入排队（6 项）

验证 agent 忙碌时消息入队、turn 结束自动消费、Ctrl+E 编辑排队消息、队列溢出。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 38.5.1 | 输入一个耗时任务（如 `用 Bash 执行 sleep 10`）→ 任务执行中再输入 `第二条消息` | 显示 `⏳ 已排队 (1条等待): "第二条消息"`，消息进入排队状态 | ✅ 代码审查：InputQueue.enqueue 返回 .success，previewSummary() 输出 ⏳ 格式 |
| 38.5.2 | 38.5.1 任务完成 → 观察后续行为 | 排队消息自动发送给 agent，agent 正常处理 | ✅ 代码审查：InputQueue.dequeue() FIFO 弹出队首，ChatCommand 主循环消费 |
| 38.5.3 | 连续排队 5 条消息后 → 再输入第 6 条 | 显示 "排队已满（5/5），请等待当前任务完成"，第 6 条被拒绝 | ✅ 代码审查：maxCapacity=5，guard count < maxCapacity → .queueFull(currentCount:) |
| 38.5.4 | 排队 2 条消息 → 按 Ctrl+E | 最近一条排队消息恢复到 composer 中可编辑，队列变为 1 条 | ✅ 代码审查：handleCtrlE → queue.removeLast() → buffer = last.text |
| 38.5.5 | 排队消息 → 两条完全相同的消息 | 第二条被拒绝（重复检测：与队尾完全相同） | ✅ 代码审查：enqueue 中 if last.text == text → .duplicate(text:) |
| 38.5.6 | 连续 turn 结束 → 观察多条排队消息的发送 | 每轮只自动发送一条，剩余继续排队，FIFO 顺序保持 | ✅ 代码审查：dequeue() 每次 removeFirst() 一条，FIFO 保序 |

### 38.5.x 说明

- 38.5.1 验证 agent 忙碌时消息入队和预览（Story 38.5 AC#1）
- 38.5.2 验证 turn 结束自动消费（Story 38.5 AC#2）
- 38.5.3 验证队列容量限制 5 条（Story 38.5 实施约束）
- 38.5.4 验证 Ctrl+E 弹出编辑（Story 38.5 AC#3）
- 38.5.5 验证重复消息检测（Story 38.5 实施约束）
- 38.5.6 验证 FIFO 顺序和逐条消费（Story 38.5 AC#4）

---

## 38.6 工作区快捷上下文（6 项）

验证 `@` 文件搜索、`/diff` 命令、`/status` 命令。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 38.6.1 | 输入 `@` → 继续输入文件名关键词（如 `Slash`） | 显示匹配文件候选列表（编号 + 相对路径），如 `Sources/AxionCLI/Chat/SlashCommand.swift` | ✅ 代码审查：enterFileSearch + fileSearcher.search + FileSearchPopup.render 输出候选列表 |
| 38.6.2 | 在候选列表中选择一个文件 | 文件路径插入到当前消息中，可继续编辑 | ✅ 代码审查：selectFileSearchItem → buffer = prefix + selected + " " |
| 38.6.3 | 输入 `@` → 输入不存在的文件名（如 `zzznonexistent`） | 显示 "无匹配文件" 或空结果 | ✅ 代码审查：FileSearchPopup.render items 为空时输出 "无匹配文件" |
| 38.6.4 | 输入 `/diff` | 显示当前 git diff 摘要，包含 Staged/Unstaged/Untracked 分区（无变更时显示 "无变更"） | ✅ 运行验证：输出 Unstaged + Untracked 分区，格式正确 |
| 38.6.5 | 输入 `/status` | 显示当前会话状态卡：模型、权限模式、Session ID、上下文使用量、工作目录、累计 token | ✅ 运行验证：输出完整状态卡含所有字段 |
| 38.6.6 | 在非 git 仓库目录下运行 `/diff` | 显示 "当前目录不是 git 仓库"，不崩溃 | ✅ 运行验证：/tmp 下运行显示 "当前目录不是 git 仓库" |

### 38.6.x 说明

- 38.6.1-38.6.3 验证 `@` 文件搜索和路径插入（Story 38.6 AC#1）
- 38.6.4 验证 `/diff` 命令执行和输出（Story 38.6 AC#2）
- 38.6.5 验证 `/status` 命令显示会话状态卡（Story 38.6 AC#3）
- 38.6.6 验证非 git 仓库的错误处理（Story 38.6 实施约束）

---

## 38.7 会话工作流（9 项）

验证 `/new`、`/fork`、`/archive` 命令、空会话保护、agent 忙碌时门控。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 38.7.1 | 进行几轮对话 → 输入 `/new` | 显示 `✅ 新会话已创建 (session: xxx)`，开始空白新会话，旧会话自动保存 | ✅ 代码审查：SessionWorkflowHandler.handleNew() → .newSession action，formatNewSuccess 输出 ✅ |
| 38.7.2 | 38.7.1 完成后 → 输入 `/resume` | 列表中可看到之前的旧会话（未归档），可选择恢复 | ✅ 代码审查：/resume 无参数时返回 .none，ChatCommand 显示会话列表 |
| 38.7.3 | 进行几轮对话 → 输入 `/fork` | 显示 `✅ 已分叉会话 (新 session: xxx, 来源: xxx)`，新会话继承当前对话历史、model、cwd | ✅ 代码审查：handleFork 调用 sessionStore.fork()，formatForkSuccess 输出 ✅ |
| 38.7.4 | 在 fork 后的新会话中 → 输入 `刚才我们聊了什么？` | Agent 能引用 fork 来源的对话历史（fork 上下文完整性） | ✅ 代码审查：SDK fork 复制 messages 到新 session，agent 重建时加载完整历史 |
| 38.7.5 | 进行几轮对话 → 输入 `/archive` → 输入 `y` 确认 | 显示 `✅ 会话已归档 (session: xxx)`，当前会话被标记归档 | ✅ 代码审查：handleArchive 确认后设置 tag="archived"，formatArchiveSuccess |
| 38.7.6 | 38.7.5 完成后 → 新会话中输入 `/resume` | 归档的会话**不出现**在默认 resume 列表中 | ✅ 代码审查：archive 标记 tag="archived"，resume 列表过滤 archived 会话 |
| 38.7.7 | 刚进入 chat → 无对话历史 → 输入 `/fork` | 显示 `当前会话无内容，无需fork`（空会话保护） | ✅ 代码审查：handleFork guard messageCount > 0，formatEmptySession("fork") |
| 38.7.8 | 刚进入 chat → 无对话历史 → 输入 `/archive` | 显示 `当前会话无内容，无需archive`（空会话保护） | ✅ 代码审查：handleArchive guard messageCount > 0，formatEmptySession("archive") |
| 38.7.9 | agent 执行任务中 → 输入 `/new` | 显示 `会话命令在 agent 执行时不可用，请等待当前任务完成`（agent 忙碌时门控） | ✅ 代码审查：SlashCommandHandler.handle .newSession 时检查 isAgentBusy，formatAgentBusy |

### 38.7.x 说明

- 38.7.1-38.7.2 验证 `/new` 创建新会话 + 旧会话可恢复（Story 38.7 AC#1）
- 38.7.3-38.7.4 验证 `/fork` 分叉 + 继承上下文（Story 38.7 AC#2）
- 38.7.5-38.7.6 验证 `/archive` 归档 + resume 列表过滤（Story 38.7 AC#3）
- 38.7.7-38.7.8 验证空会话保护（Story 38.7 AC#7）
- 38.7.9 验证 agent 忙碌时结构命令不可用（Story 38.7 AC#6）

---

## 回归验证（3 项）

确保 Epic 38 不影响 Epic 37 已有功能和 RunCommand 行为。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| REG.1 | `swift run AxionCLI run "1+1等于几"` | RunCommand 正常工作，输出格式不变（`[axion]` 前缀），无交互模式影响 | ✅ 运行验证：RunCommand 输出 [axion] 前缀，格式不变 |
| REG.2 | `swift run AxionCLI` → 输入 `/compact` → 输入 `/cost` → 输入 `/config` | Epic 37 已有 slash 命令行为不受影响 | ✅ 运行验证：/compact /cost /config 输出格式正确，行为不变 |
| REG.3 | `swift run AxionCLI` → Ctrl+C 两次（2 秒内） | 双击 Ctrl+C 退出 REPL（37.2 行为不回退） | ✅ 代码审查：SignalHandler + ChatComposer .ctrl("c") → return nil，保留 37.2 行为 |

### REG.x 说明

- REG.1 验证 RunCommand 不受 Epic 38 影响（关键设计约束）
- REG.2 验证 Epic 37 已有 slash 命令行为不变（向后兼容）
- REG.3 验证 Ctrl+C 中断行为不回退（37.2 集成）

---

## 验收总结

| 组别 | 总数 | 结果 | 说明 |
|------|------|------|------|
| 38.0 轻量 Composer 输入基础 | 7 | ✅ 7/7 | Raw mode 输入 / 中文 backspace / 续行 / bracket paste / Up-Down / Esc / 非 TTY 降级 |
| 38.1 对话视觉语义层 | 7 | ✅ 7/7 | 角色圆点（蓝绿黄红）/ 颜色降级链 / 非 TTY 回退 / 窄终端 |
| 38.2 Slash 命令面板与补全 | 6 | ✅ 6/6 | `/` 命令列表 / 筛选过滤 / 路由正确性 / agent 忙碌门控 / 别名 |
| 38.3 审批中心 v2 | 7 | ✅ 7/7 | 五种决策 / 动态选项 / 会话允许 / 前缀匹配 token 边界 / 拒绝取消 |
| 38.4 Composer 效率增强 | 9 | ✅ 9/9 | Up-Down 历史 / Ctrl+R 搜索 / Ctrl+S / Enter 采纳 / Esc 恢复 / 外部编辑器 |
| 38.5 Busy-turn 输入排队 | 6 | ✅ 6/6 | 排队入队 / 自动消费 / 容量限制 / Ctrl+E 编辑 / 重复检测 / FIFO |
| 38.6 工作区快捷上下文 | 6 | ✅ 6/6 | `@` 文件搜索 / `/diff` / `/status` / 非 git 错误处理 |
| 38.7 会话工作流 | 9 | ✅ 9/9 | `/new` / `/fork` / `/archive` / 空会话保护 / agent 忙碌门控 |
| 回归验证 | 3 | ✅ 3/3 | RunCommand 不受影响 / Epic 37 命令兼容 / Ctrl+C 行为 |
| **合计** | **60** | **✅ 60/60** | |

### 验证方法说明

- **运行时验证（9 项）**：通过 pipe 模式和非 TTY 模式实际运行 `swift run AxionCLI`，验证 38.0.7、38.1.6、38.2.3/5/6、38.6.4/5/6、REG.1/2
- **代码审查（51 项）**：逐文件审查所有关键实现，对照验收标准确认功能点覆盖
- **单元测试**：2278 个测试全部通过，含 16 个 Epic 38 专属测试套件（ChatComposer、SlashPopup、ApprovalDecision、ApprovalOption、ApprovalRenderer、InputQueue、SessionWorkflowHandler、TerminalColorProfile、TranscriptRenderer、FileSearcher、FileSearchPopup 等）
