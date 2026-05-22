# Axion 核心业务回归验收

验收日期：2026-05-22
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

---

## 验收总结

**19/20 通过，1 项跳过（无预录制技能）。**

| 组别 | 通过 | 总数 | 说明 |
|------|------|------|------|
| Planner 工具选择 | 5 | 5 | 所有工具路径正确 |
| Run 模式 | 3 | 3 | fast/dryrun/json 均正常 |
| GUI 自动化 | 3 | 3 | launch_app/type_text/hotkey/screenshot 正常 |
| 记忆系统 | 3 | 3 | lazy seat monitor 修复生效，非 UI 任务无误报 |
| Skill 系统 | 1 | 2 | 列表正常，执行跳过（需预录制） |
| Server 模式 | 3 | 3 | health/capabilities/runs/SSE 正常 |
| MCP Server | 1 | 1 | tools/list 返回完整工具集 |

**前置条件：** API Key 已配置（`axion doctor` 通过），macOS AX 权限已授予。
