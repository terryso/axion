# Epic 8–11 手工验收文档（Phase 3）

> 生成日期：2026-05-15
> 分支：feature/phase3-vision-features
> 验收环境：macOS 14+，已通过 `axion setup` 完成首次配置

---

## 前置准备

```bash
# 1. 确认当前分支和编译状态
cd /Users/nick/CascadeProjects/axion
git branch --show-current
swift build

# 2. 确认 axion 可执行
.build/debug/axion --version
```

---

## Epic 8: 多窗口、多 App 工作流

### 8.1 Story 8.1 — 多窗口状态追踪与上下文管理

**AC1: list_windows 返回多应用窗口信息（含 z-order）**

```bash
# 先启动两个应用
open -a Calculator
open -a TextEdit

# 运行 list_windows 查看多应用窗口
.build/debug/axion run "列出所有打开的窗口" --dryrun
# 预期：Planner 生成的计划中可看到多窗口上下文
```

更好的验证方式 — 直接通过 MCP 工具调用：

```bash
# 启动 Helper 后手动测试 list_windows
# 通过 axion run 执行一个涉及多窗口的任务
.build/debug/axion run "打开计算器和文本编辑器"
```

验收要点：
- list_windows 返回所有应用的窗口列表，每项包含 app_name、pid、window_id、title、bounds
- 多窗口上下文可在 Planner 计划中被引用

**AC2: 步骤可引用不同窗口的占位符**

```bash
# 运行涉及两个应用的交互任务
.build/debug/axion run "打开计算器计算 7 乘以 8，然后把结果记在 TextEdit 里"
# 预期：
# - Planner 生成跨应用计划
# - 步骤引用 Calculator 和 TextEdit 的不同 window_id
# - 通过剪贴板或 AX 值在应用间传递数据
```

**AC3: 窗口切换前自动刷新状态**

```bash
# 查看执行日志，确认窗口切换时有 get_window_state 调用
.build/debug/axion run "在计算器和文本编辑器之间来回切换" --verbose 2>&1 | grep -i "window_state\|refresh\|activate"
# 预期：看到窗口激活和状态刷新的日志
```

---

### 8.2 Story 8.2 — 跨应用工作流编排

**AC1: 跨应用计划生成**

```bash
.build/debug/axion run "从计算器复制计算结果，粘贴到 TextEdit" --dryrun
# 预期：生成的计划包含跨应用步骤
# - 激活 Calculator → 获取结果 → cmd+c → 切换 TextEdit → cmd+v
```

**AC2: 完整跨应用工作流执行**

```bash
.build/debug/axion run "打开计算器计算 17 乘以 23，然后把结果 391 粘贴到 TextEdit 新文档中"
# 预期：
# - Calculator 显示 391
# - TextEdit 新文档中包含 "391"
# - 终端显示完成信息
```

**AC3: 失败重规划**

```bash
.build/debug/axion run "从 Safari 复制网页标题，粘贴到备忘录"
# 预期：如果某步骤失败（如 Safari 未安装），自动触发重规划
```

---

### 8.3 Story 8.3 — 窗口布局管理

**AC1: arrange_windows 工具注册**

```bash
# 检查工具列表中包含 arrange_windows
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | .build/debug/axion mcp 2>/dev/null | grep -o '"arrange_windows"'
# 预期：输出包含 "arrange_windows"
```

**AC2: 并排布局**

```bash
# 启动两个应用
open -a Calculator
open -a TextEdit

.build/debug/axion run "把计算器和文本编辑器并排显示，左计算器右文本编辑器"
# 预期：
# - Planner 在计划中包含 arrange_windows 步骤
# - 两个窗口并排显示在屏幕左右两侧
```

**AC3: 布局后坐标重新计算**

```bash
# 布局调整后执行后续操作
.build/debug/axion run "把计算器和文本编辑器并排显示，然后在计算器中点击 5 + 3 ="
# 预期：布局调整后的坐标正确，点击操作在正确位置执行
```

**AC4: resize_window 工具**

```bash
# 检查 resize_window 工具
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | .build/debug/axion mcp 2>/dev/null | grep -o '"resize_window"'
# 预期：输出包含 "resize_window"
```

---

## Epic 9: 录制 → 编译 → 技能复用

### 9.1 Story 9.1 — 操作录制引擎

**AC1: 录制模式启动**

```bash
.build/debug/axion record "open_calculator"
# 预期输出：
# [axion] 正在启动 Helper...
# [axion] 正在启动录制模式...
# [axion] 录制中... 按 Ctrl-C 结束录制
```

**AC2: 录制桌面操作（手动操作后 Ctrl-C 停止）**

```bash
# 在另一个终端或手动操作桌面：
# 1. 打开计算器
# 2. 点击几个按钮
# 3. 回到录制终端按 Ctrl-C

# 预期输出：
# [axion] 正在停止录制...
# [axion] 录制已保存: ~/.axion/recordings/open_calculator.json
# [axion] 录制摘要: N 个事件，耗时 X.X 秒
```

**AC3: 验证录制文件内容**

```bash
cat ~/.axion/recordings/open_calculator.json | /opt/homebrew/bin/python3 -m json.tool | head -30
# 预期：JSON 文件包含 name、createdAt、durationSeconds、events、windowSnapshots 字段
# events 数组中每个元素包含 type（如 click、type_text、app_switch）、坐标、时间戳等
```

**AC4: start_recording / stop_recording MCP 工具**

```bash
# 检查录制工具已注册
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | .build/debug/axion mcp 2>/dev/null | grep -o '"start_recording\|"stop_recording"'
# 预期：输出包含 start_recording 和 stop_recording
```

---

### 9.2 Story 9.2 — 录制编译为可复用技能

**AC1: 基本编译**

```bash
.build/debug/axion skill compile open_calculator
# 预期输出：
# [axion] 技能已编译: ~/.axion/skills/open_calculator.json
# [axion] 步骤数: N
```

**AC2: 检查编译后的技能文件**

```bash
cat ~/.axion/skills/open_calculator.json | /opt/homebrew/bin/python3 -m json.tool | head -40
# 预期：JSON 文件包含 name、description、parameters、steps 字段
# steps 数组中每个元素包含 tool、parameters、purpose 等字段
```

**AC3: 带参数编译**

```bash
.build/debug/axion skill compile open_calculator --param search_term
# 预期：技能文件中对应的值被替换为 {{search_term}} 参数占位符
# 输出包含：[axion] 检测到的参数: search_term
```

**AC4: 冗余步骤优化**

```bash
# 编译时自动去重输出
.build/debug/axion skill compile open_calculator
# 如果录制中有冗余操作，预期看到：
# [axion] 优化移除的冗余步骤: N
```

---

### 9.3 Story 9.3 — 技能库管理与执行

**AC1: 技能执行**

```bash
.build/debug/axion skill run open_calculator
# 预期：
# - 直接回放技能步骤，不调用 LLM
# - Calculator 被打开并执行录制时的操作
# - 输出：技能 'open_calculator' 完成。N 步，耗时 X.X 秒。
```

**AC2: 带参数执行**

```bash
.build/debug/axion skill run open_calculator --param search_term="hello"
# 预期：参数值被注入步骤序列后执行
```

**AC3: 技能列表**

```bash
.build/debug/axion skill list
# 预期输出格式：
# 已保存的技能:
#   open_calculator
#     描述: ...
#     执行次数: N, 上次使用: YYYY-MM-DD HH:MM
```

**AC4: 技能删除**

```bash
.build/debug/axion skill delete open_calculator
# 预期输出：技能 'open_calculator' 已删除。

# 确认删除
.build/debug/axion skill list
# 预期：open_calculator 不再出现
```

**AC5: 执行不存在的技能**

```bash
.build/debug/axion skill run nonexistent_skill
# 预期：报错 "技能不存在: nonexistent_skill"
```

**AC6: 技能执行失败处理**

```bash
# 重新编译一个技能后，故意修改窗口位置再执行
# 预期：如果坐标失效，尝试重试一次，仍失败则报告错误并建议用 axion run 代替
```

---

## Epic 10: macOS 菜单栏 UI

### 10.1 Story 10.1 — 菜单栏常驻状态与服务通信

**AC1: AxionBar 编译与启动**

```bash
# 编译 AxionBar
swift build --target AxionBar

# 启动 AxionBar（需要一个 macOS GUI 会话）
.build/debug/AxionBar &
# 预期：
# - 菜单栏出现 Axion 图标
# - 点击图标显示下拉菜单：快速执行、技能列表、任务历史、设置、退出
```

> **注意：** AxionBar 是 macOS GUI 应用，需要从 Finder 或 `open` 命令启动，不能在纯 SSH 环境中运行。

**AC2: 后端服务检测**

```bash
# 先确保 axion server 未运行
pkill -f "axion server" 2>/dev/null

# 启动 AxionBar 后检查菜单状态
# 预期：状态图标显示 "未连接"，下拉菜单提供 "启动服务" 选项

# 点击 "启动服务"
# 预期：在后台启动 axion server --port 4242，就绪后状态变为 "就绪"
```

**AC3: 后端已运行时自动连接**

```bash
# 先启动后端
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 2

# 启动 AxionBar
.build/debug/AxionBar &
# 预期：AxionBar 自动检测到后端，状态图标显示 "就绪"
```

---

### 10.2 Story 10.2 — 任务管理与实时状态面板

**AC1: 快速执行**

```bash
# 确保后端运行
# 在 AxionBar 菜单中点击 "快速执行"
# 预期：弹出输入框，输入自然语言任务描述后提交执行
```

**AC2: 实时进度显示**

```bash
# 提交一个任务后查看菜单栏状态
# 预期：
# - 状态图标显示执行中动画
# - 下拉菜单显示当前任务名称和进度（步骤 N/M）
```

**AC3: 任务详情面板**

```bash
# 点击正在执行的任务
# 预期：弹出面板显示实时日志流（通过 SSE 事件流获取）
```

**AC4: 任务完成通知**

```bash
# 等待任务执行完成
# 预期：macOS 原生通知弹出：任务完成/失败 + 摘要
```

**AC5: 任务历史**

```bash
# 点击菜单中的 "任务历史"
# 预期：显示最近 20 条任务记录，每条包含任务描述、状态、执行时间
```

---

### 10.3 Story 10.3 — 全局热键与技能快捷触发

**AC1: 热键配置**

```bash
# 在 AxionBar 设置中配置全局热键
# 预期：可以为技能或常用任务绑定全局热键（如 Cmd+Shift+A）
```

**AC2: 热键触发**

```bash
# 配置热键后按下组合键
# 预期：触发绑定的技能或任务，菜单栏图标显示执行状态
```

**AC3: 技能菜单**

```bash
# 先编译一个技能（见 Epic 9）
.build/debug/axion skill compile test_skill

# 在 AxionBar 菜单中点击 "技能"
# 预期：显示所有可用技能列表，可直接点击执行
```

**AC4: 热键需要 Accessibility 权限**

```bash
# 如果未授权 Accessibility 权限
# 预期：热键功能提示用户前往系统设置授权
```

---

## Epic 11: 第三方 SDK 生态

### 11.1 Story 11.1 — Agent 项目模板与脚手架 CLI

**AC1: 脚手架 CLI 可执行**

> **注意：** ScaffoldCLI 在 OpenAgentSDK 仓库中，不在 Axion 仓库内。以下命令需在 OpenAgentSDK 目录下执行。

```bash
# 查找 OpenAgentSDK 仓库
# 假设在 ../open-agent-sdk-swift/
cd ../open-agent-sdk-swift 2>/dev/null || echo "请在 OpenAgentSDK 仓库目录下执行"

# 编译 ScaffoldCLI
swift build --target ScaffoldCLI

# 运行脚手架创建新项目
swift run ScaffoldCLI MyAgent --output /tmp/test-agent
# 预期：在 /tmp/test-agent/ 生成标准 Agent 项目结构
```

**AC2: 生成的项目可编译**

```bash
cd /tmp/test-agent
swift build
# 预期：编译成功
```

**AC3: 检查生成的项目结构**

```bash
find /tmp/test-agent -type f | sort
# 预期包含：
# - Package.swift
# - Sources/MyAgent/main.swift
# - Sources/MyAgent/Tools/
# - Sources/MyAgent/Prompts/
# - README.md
```

**AC4: README 文档完整**

```bash
cat /tmp/test-agent/README.md
# 预期：包含项目结构说明、如何添加自定义工具、如何配置 system prompt、如何运行和调试
```

**AC5: SDK 边界文档参考**

```bash
cat /Users/nick/CascadeProjects/axion/docs/sdk-boundary.md | head -50
# 预期：文档清晰列出 SDK vs 应用层的模块归属和理由
```

---

### 11.2 Story 11.2 — 插件化工具注册与自定义 Agent 扩展

**AC1: defineTool 工厂函数**

```bash
# 查看模板中的工具示例
cat /tmp/test-agent/Sources/MyAgent/Tools/*.swift
# 预期：包含使用 defineTool 注册自定义工具的示例代码
```

**AC2: 多工具注册后 LLM 可发现**

```bash
# 在模板项目的 main.swift 中查看工具注册
cat /tmp/test-agent/Sources/MyAgent/main.swift
# 预期：工具注册到 AgentOptions.tools，运行时 LLM 可发现所有工具
```

**AC3: 通过 axion mcp 复用桌面操作**

```bash
# 验证 axion mcp 暴露的工具列表
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | .build/debug/axion mcp 2>/dev/null | /opt/homebrew/bin/python3 -c "
import json, sys
for line in sys.stdin:
    try:
        data = json.loads(line.strip())
        if 'result' in data and 'tools' in data.get('result', {}):
            tools = data['result']['tools']
            print(f'Total tools: {len(tools)}')
            for t in tools:
                print(f'  - {t[\"name\"]}: {t.get(\"description\", \"\")[:60]}')
    except:
        pass
"
# 预期：列出 20+ 工具，包含 launch_app、click、type_text 等桌面操作工具
```

**AC4: AxionHelper 架构参考**

```bash
# 查看 AxionHelper 架构
ls /Users/nick/CascadeProjects/axion/Sources/AxionHelper/
# 预期目录结构：
# MCP/ - MCP Server 实现（ToolRegistrar）
# Services/ - AX 操作服务
# Models/ - 数据模型
# Protocols/ - 协议定义
```

**AC5: Hooks 安全策略示例**

```bash
# 查看 Axion 的 Hook 注册代码
grep -A 20 "HookRegistry\|HookDefinition\|preToolUse" /Users/nick/CascadeProjects/axion/Sources/AxionCLI/Commands/RunCommand.swift
# 预期：展示如何通过 HookRegistry.register(.preToolUse) 注册安全检查 Hook
```

---

### 11.3 Story 11.3 — 开发者文档与示例库

**AC1: 开发指南文档**

```bash
# 查看 SDK 文档目录（在 OpenAgentSDK 仓库）
ls ../open-agent-sdk-swift/docs/ 2>/dev/null || echo "请在 OpenAgentSDK 仓库查看"
# 预期包含：
# - getting-started.md（快速开始）
# - tool-development-guide.md（工具开发指南）
# - mcp-integration-guide.md（MCP 集成指南）
# - agent-customization-guide.md（Agent 自定义指南）
# - session-memory-guide.md（Session 和 Memory 使用指南）
```

**AC2: 示例代码**

```bash
ls ../open-agent-sdk-swift/Examples/ 2>/dev/null || echo "请在 OpenAgentSDK 仓库查看"
# 预期：包含至少 5 个示例（基础 Agent、自定义工具、MCP 集成、Session 管理、Memory 使用）
```

**AC3: Axion 关键模块内联文档**

```bash
# 检查 Axion 关键模块的内联文档（doc comments）
grep -c "/// " /Users/nick/CascadeProjects/axion/Sources/AxionCLI/Planner/*.swift
grep -c "/// " /Users/nick/CascadeProjects/axion/Sources/AxionCLI/Executor/*.swift
grep -c "/// " /Users/nick/CascadeProjects/axion/Sources/AxionCLI/Memory/*.swift
# 预期：关键模块文件中有充分的 doc comments 说明设计决策
```

**AC4: SDK API 文档**

```bash
# 查看 SDK 边界文档中 API 使用清单
grep -A 50 "SDK API 使用清单" /Users/nick/CascadeProjects/axion/docs/sdk-boundary.md
# 预期：列出所有使用的 SDK 公共 API，包含参数说明和使用场景
```

**AC5: 打包分发指南**

```bash
# 查看分发相关文档
grep -i "homebrew\|distribution\|packaging\|分发" ../open-agent-sdk-swift/docs/*.md 2>/dev/null
# 预期：包含 SPM package 结构、Helper App 签名、Homebrew formula 指南
```

---

## 单元测试验证

在手工验收之外，确认所有单元测试通过：

```bash
swift test --filter "AxionHelperTests.Tools" \
           --filter "AxionHelperTests.Models" \
           --filter "AxionHelperTests.MCP" \
           --filter "AxionHelperTests.Services" \
           --filter "AxionCoreTests" \
           --filter "AxionCLITests" \
           --filter "AxionBarTests"
# 预期：所有测试通过，0 failures
```

---

## 验收检查清单汇总

| Epic | Story | 关键命令 | 通过 |
|------|-------|---------|------|
| 8 | 8.1 | list_windows → 多应用窗口信息 | ☐ |
| 8 | 8.2 | `axion run` 跨应用计划执行 | ☐ |
| 8 | 8.2 | 跨应用剪贴板数据传递 | ☐ |
| 8 | 8.3 | `arrange_windows` MCP 工具注册 | ☐ |
| 8 | 8.3 | 并排布局执行成功 | ☐ |
| 8 | 8.3 | `resize_window` MCP 工具注册 | ☐ |
| 9 | 9.1 | `axion record` 启动录制 | ☐ |
| 9 | 9.1 | Ctrl-C 停止录制 → 保存文件 | ☐ |
| 9 | 9.1 | 录制文件包含 events 和 windowSnapshots | ☐ |
| 9 | 9.2 | `axion skill compile` → 生成技能文件 | ☐ |
| 9 | 9.2 | `--param` 参数化编译 | ☐ |
| 9 | 9.3 | `axion skill run` → 回放执行 | ☐ |
| 9 | 9.3 | `axion skill list` → 显示技能列表 | ☐ |
| 9 | 9.3 | `axion skill delete` → 删除技能 | ☐ |
| 9 | 9.3 | 不存在技能 → 报错提示 | ☐ |
| 10 | 10.1 | AxionBar 编译启动 → 菜单栏图标 | ☐ |
| 10 | 10.1 | 后端未运行 → 显示 "启动服务" | ☐ |
| 10 | 10.1 | 后端运行 → 自动连接 | ☐ |
| 10 | 10.2 | 快速执行 → 提交任务 | ☐ |
| 10 | 10.2 | 实时进度显示（步骤 N/M） | ☐ |
| 10 | 10.2 | 任务完成通知 | ☐ |
| 10 | 10.3 | 全局热键配置与触发 | ☐ |
| 10 | 10.3 | 技能菜单 → 点击执行 | ☐ |
| 11 | 11.1 | ScaffoldCLI → 生成 Agent 项目 | ☐ |
| 11 | 11.1 | 生成项目 `swift build` 成功 | ☐ |
| 11 | 11.2 | `axion mcp` → 列出 20+ 工具 | ☐ |
| 11 | 11.2 | Axion Hook 注册示例可参考 | ☐ |
| 11 | 11.3 | SDK 文档完整（5+ 指南） | ☐ |
| 11 | 11.3 | 示例代码 5+ 个 | ☐ |
| 11 | 11.3 | Axion 关键模块有 doc comments | ☐ |
