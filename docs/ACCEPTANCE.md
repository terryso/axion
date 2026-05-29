# Axion 核心业务回归验收

验收日期：2026-05-27
验收目标：确保重构后各核心业务路径正常工作

运行方式：`swift run axion run "任务描述"`（确保使用最新代码）

---

## 1. Planner 工具选择（5 项）

验证 LLM 根据任务类型选择正确的工具路径。

| # | 测试任务 | 预期工具选择 | 预期行为 | 实际结果 |
|---|----------|-------------|---------|---------|
| 1.1 | `30+40*30=` | 无工具（直接回答） | LLM 直接计算并返回 1230，0 次工具调用 | ✅ 通过。答案 1230，1 次 LLM 调用，0 次工具调用 |
| 1.2 | `帮我打开计算器计算 10 * 67` | axion-helper MCP | 打开 Calculator，点击按钮，返回 670 | ✅ 通过。launch_app → list_windows → get_accessibility_tree → click → verify，结果 670 |
| 1.3 | `今天广州天气如何` | WebSearch / WebFetch | 搜索并返回实时天气信息 | ✅ 通过。WebSearch → WebFetch 获取天气数据 |
| 1.4 | `/polyv-live-cli 获取最新5个频道信息` | Skill 工具 | 调用 polyv-live-cli skill 返回频道列表 | ✅ 通过。Skill → Bash 执行 CLI，返回 5 个频道 |
| 1.5 | `帮我压缩一下~/Downloads/test-acceptance.mp4` | Bash (ffmpeg) | 用 Bash 执行 ffmpeg 压缩命令 | ✅ 通过。Bash × 4：file → ffprobe → hexdump → ls，正确识别空文件并提示 |

## 2. Run 模式（3 项）

验证不同运行模式的 CLI 参数正确生效。

| # | 命令 | 预期行为 | 实际结果 |
|---|------|---------|---------|
| 2.1 | `swift run AxionCLI run "打开计算器" --fast` | Fast mode：1-3 步完成，无 screenshot 验证 | ✅ 通过。1 步完成，输出 "Fast mode 完成"，截图 0 次 |
| 2.2 | `swift run AxionCLI run "打开计算器计算 5+3" --dryrun` | Dryrun：只规划不执行，输出计划文本 | ✅ 通过。输出 8 步详细计划，未执行任何工具 |
| 2.3 | `swift run AxionCLI run "1+1等于几" --json` | JSON 输出：合法 JSON，含 runId/status/steps | ✅ 通过。含 runId/status:"success"/task/steps/numTurns/durationMs |

## 3. GUI 自动化（3 项）

验证核心桌面操作工具链。

| # | 测试任务 | 预期工具序列 | 预期行为 | 实际结果 |
|---|----------|-------------|---------|---------|
| 3.1 | `打开文本编辑，输入 Hello World` | launch_app → type_text | 打开 TextEdit，输入文字 | ✅ 通过。launch_app(TextEdit) → type_text("Hello World") |
| 3.2 | `打开访达，用快捷键 Cmd+Shift+D 跳转到下载文件夹` | launch_app → hotkey | 打开 Finder，执行快捷键 | ✅ 通过。launch_app(Finder) → hotkey(cmd+shift+d) |
| 3.3 | `打开计算器，截图看看当前界面` | launch_app → screenshot | 截图并返回画面描述 | ✅ 通过。launch_app(Calculator) → screenshot，LLM 正确描述计算器界面 |

## 4. 记忆系统（3 项）

验证 Memory 的基本读写和 lazy seat monitor 修复。

| # | 命令 | 预期行为 | 实际结果 |
|---|------|---------|---------|
| 4.1 | `swift run AxionCLI run "Python 的 list comprehension 语法是什么"` | 非 UI 任务：不触发 seat monitor 警告 | ✅ 通过。无 "检测到外部桌面操作" 警告，无 Helper 工具调用 |
| 4.2 | `swift run AxionCLI memory list` | 列出已积累的记忆，含状态图标和分类 | ✅ 通过。显示 23 domains、585 entries，含状态图标和 confidence |
| 4.3 | `swift run AxionCLI run "1+2等于几" --no-memory` | 带 --no-memory 运行，不注入记忆上下文 | ✅ 通过。正常完成，答案 3 |

## 5. Skill 系统（2 项）

验证技能列表和执行链路。

| # | 命令 | 预期行为 | 实际结果 |
|---|------|---------|---------|
| 5.1 | `swift run AxionCLI skill list` | 列出已保存的技能列表 | ✅ 通过。列出 79 个技能（prompt + built-in 类型） |
| 5.2 | `swift run AxionCLI skill run <技能名>` | 执行已保存技能 | ⏭️ 跳过。无预录制技能（需手动录制） |

## 6. Server 模式（3 项）

验证 HTTP API 端点。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 6.1 | `GET /v1/health` | 返回 200，status: "ok" | ✅ 通过。`{"status":"ok","version":"1.0.0"}` |
| 6.2 | `GET /v1/capabilities` | 返回版本号、工具列表、feature flags | ✅ 通过。含 version/tools/features/statuses |
| 6.3 | `POST /v1/runs` → `GET SSE` | 返回 202 + run_id，SSE 流推送事件 | ✅ 通过。返回 run_id + status:"queued"，SSE 连接成功 |

## 7. MCP Server 模式（1 项）

验证外部 Agent 可通过 MCP 协议调用 Axion。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 7.1 | MCP `tools/list` via stdio | 返回 Helper 工具 + run_task 等 | ✅ 通过。47 个工具：23 个 axion-helper 工具 + SDK 内建工具 + run_task/query_task_status |

## 10. Gateway 模式（6 项）

验证 Epic 28 引入的 Gateway 长驻进程、launchd 守护进程管理、状态查询。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 10.1 | `swift run AxionCLI gateway start --port 4243 &` → `curl -s http://127.0.0.1:4243/v1/health` | Gateway 前台启动 HTTP 服务，health 端点返回 `{"status":"ok"}` | ✅ 通过。返回 `{"version":"1.0.0","status":"ok"}` |
| 10.2 | `curl -s http://127.0.0.1:4243/v1/gateway/status` | 返回 JSON 含 `status:"running"`、`active_tasks`、`uptime_seconds`、`label:"dev.axion.gateway"` | ✅ 通过。含 status/active_tasks:0/uptime_seconds:5.46/pid/label，预留字段为 null |
| 10.3 | 先 kill 10.1 的进程 → `swift run AxionCLI gateway status` | 显示 `status: not_installed`（未安装 daemon 时） | ✅ 通过。显示 `Gateway status: not_installed`，含 label/plist/log/占位字段 |
| 10.4 | `swift run AxionCLI gateway install` | 创建 `~/Library/LaunchAgents/dev.axion.gateway.plist`，launchctl bootstrap 成功，输出 plist 路径和日志路径 | ✅ 通过。plist 含 label:dev.axion.gateway、gateway start、KeepAlive:Crashed、日志路径 |
| 10.5 | `swift run AxionCLI gateway status` | 显示 `status: running`，含 PID、活跃任务数、运行时长、日志路径 | ✅ 通过。PID:36978、Active tasks:0、Uptime:18s、含 TG/review/curator 占位 |
| 10.6 | `swift run AxionCLI gateway uninstall` | launchctl bootout 成功，plist 文件删除，进程停止 | ✅ 通过。plist 已删除，status 回到 not_installed |

### 10.x 说明

- 10.1 验证 `gateway start` 复用 ServerCommand 的 HTTP API（Story 28.2 AC#1）
- 10.2 验证 `GET /v1/gateway/status` 返回实时运行时状态（Story 28.4 AC#4）
- 10.3 验证未安装 daemon 时 status 降级输出（Story 28.4 AC#2）
- 10.4 验证 plist 生成：label=`dev.axion.gateway`、KeepAlive=Crashed、日志=`gateway.log`/`gateway.err.log`（Story 28.3 AC#1）
- 10.5 验证运行中 gateway 的 status 含实时数据 + HTTP 查询成功（Story 28.4 AC#1）
- 10.6 验证 uninstall 清理完整（Story 28.3 AC#2）

---

## 验收总结

**34/35 通过，1 项跳过（无预录制技能）。**

| 组别 | 通过 | 总数 | 说明 |
|------|------|------|------|
| Planner 工具选择 | 5 | 5 | 所有工具路径正确 |
| Run 模式 | 3 | 3 | fast/dryrun/json 均正常 |
| GUI 自动化 | 3 | 3 | launch_app/type_text/hotkey/screenshot 正常 |
| 记忆系统 | 3 | 3 | lazy seat monitor 修复生效，非 UI 任务无误报 |
| Skill 系统 | 1 | 2 | 列表正常，执行跳过（需预录制） |
| Server 模式 | 3 | 3 | health/capabilities/runs/SSE 正常 |
| MCP Server | 1 | 1 | tools/list 返回完整工具集 |
| Self-Evolution | 4 | 4 | --no-review/curator status/doctor/help 正常 |
| Agent Runtime | 5 | 5 | Session/Resume/持久化全部通过 |
| Gateway 模式 | 6 | 6 | gateway start/install/uninstall/status 全部通过 |

## 8. Self-Evolution（Review & Curator）（4 项）

验证 Phase 8 自进化功能的回归。

| # | 命令 | 预期行为 | 实际结果 |
|---|------|---------|---------|
| 8.1 | `swift run AxionCLI run "1+1等于几" --no-review` | 正常完成，不触发 review | ✅ 通过。正常完成，无 review 输出 |
| 8.2 | `swift run AxionCLI doctor` | 包含 Review/Curator 检查项 | ✅ 通过。显示 review 间隔、curator 启用状态、review 模型 |
| 8.3 | `swift run AxionCLI curator status` | 显示策展配置和上次运行时间 | ✅ 通过。显示启用/间隔/上次策展/下次策展/运行次数 |
| 8.4 | `swift run AxionCLI run --help` | 包含 `--no-review` 和 `--review-model` 选项 | ✅ 通过。两个选项正确显示 |

## 9. Agent Runtime — Session + Resume（5 项）

验证 Epic 24-27 引入的 AxionRuntime、Session 持久化、Session Resume、Daemon 集成。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 9.1 | `swift run AxionCLI run "1+2等于几"` → `swift run AxionCLI sessions` | 先执行一次 run 产生 session，再列出 session 列表，包含刚执行的 task、status=COMPLETED、steps/duration | ✅ 通过。sessions 列表显示 task "1+2等于几"、status=completed、duration |
| 9.2 | `swift run AxionCLI sessions --active` | 只显示 status=RUNNING 的 session（无活跃 session 时输出空列表） | ✅ 通过。只列出 status=running 的 session |
| 9.3 | 从 9.1 获取 session-id → `swift run AxionCLI resume <session-id>` | 恢复之前的 session，agent 基于历史上下文继续对话，输出包含历史信息 | ✅ 通过。agent 回顾了 "1+2=3" 的历史上下文 |
| 9.4 | `swift run AxionCLI resume <invalid-session-id>` | 显示错误信息 "Session not found" | ✅ 通过。显示 "Session not found: invalid-session-123" |
| 9.5 | `ls ~/.axion/sessions/` → 检查任意 session 目录下存在 `axion-state.json` | `axion-state.json` 存在，包含 status/totalSteps/durationMs/updatedAt 字段 | ✅ 通过。axion-state.json 含 status:"completed"/totalSteps/durationMs/updatedAt |

### 9.x 回归说明

Epic 24（AxionRuntime Core）、Epic 25（EventHandler 体系）、Epic 26（CLI + API 改造）属于内部重构。
回归验证通过上述 1-8 组全部测试通过即可确认，不额外新增手工测试项。

---

**前置条件：** API Key 已配置（`axion doctor` 通过），macOS AX 权限已授予。
