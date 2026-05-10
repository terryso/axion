# Manual Acceptance Test: Story 3.8 — SDK 边界文档与端到端验证

**日期**: 2026-05-10
**测试人**: nick
**CLI 版本**: axion 0.1.0 (debug build)

## 前置条件

- [x] macOS 14+ 桌面环境 (macOS 15.7.3)
- [x] AxionHelper 已编译 (`.build/debug/AxionHelper`)
- [x] Anthropic API Key 已配置 (via config.json)
- [x] Accessibility 权限已授予
- [x] 屏幕录制权限已授予
- [x] `axion doctor` 检查全部通过

---

## AC4: Calculator 端到端验证

**命令**: `AXION_HELPER_PATH=./build/debug/AxionHelper axion run "打开计算器，计算 17 乘以 23"`
**运行 ID**: 20260510-z6880l
**耗时**: ~4 分 22 秒

**验证步骤**:

| # | 检查项 | 预期结果 | 通过? |
|---|--------|----------|-------|
| 1 | CLI 启动 | 无崩溃，显示 run ID | PASS |
| 2 | Helper 启动 | MCP 连接成功，工具调用正常 | PASS |
| 3 | LLM 规划 | Agent 生成 launch_app → screenshot → click 步骤 | PASS |
| 4 | 步骤执行 | 终端显示逐步执行进度（90 个事件） | PASS |
| 5 | 最终结果 | Calculator 显示 391 | PASS |
| 6 | 终端输出 | 显示 "完成" 和结果汇总 | PASS |
| 7 | trace 文件 | trace.jsonl 完整（90 事件：run_start → tool_use/tool_result → result → run_done） | PASS |
| 8 | Helper 退出 | 运行正常结束，退出码 0 | PASS |

**观察**: LLM 经过多次尝试（先 click 按钮失败，再 hotkey 失败，最终通过 click 按钮 + type_text 组合成功）。Agent 具有自纠错能力。

---

## AC5: TextEdit 端到端验证

**命令**: `AXION_HELPER_PATH=./build/debug/AxionHelper axion run "打开 TextEdit，输入 Hello World"`
**运行 ID**: 20260510-ex5r79
**耗时**: ~5 分钟

**验证步骤**:

| # | 检查项 | 预期结果 | 通过? |
|---|--------|----------|-------|
| 1 | CLI 启动 | 无崩溃 | PASS |
| 2 | TextEdit 打开 | launch_app 成功，pid=23171 | PASS |
| 3 | 文本输入 | Agent 使用 AX tree 定位 AXTextArea，点击后 type_text "Hello World" | PASS |
| 4 | 完成通知 | 终端显示任务完成 | PASS |
| 5 | trace 文件 | 完整记录（40 事件） | PASS |

**观察**: Agent 正确使用 get_accessibility_tree 定位输入区域，操作流程非常顺畅。

---

## AC6: Finder 端到端验证

**命令**: `AXION_HELPER_PATH=./build/debug/AxionHelper axion run "打开 Finder，进入下载目录"`
**运行 ID**: 20260510-7ej9wi
**耗时**: ~2 分钟

**验证步骤**:

| # | 检查项 | 预期结果 | 通过? |
|---|--------|----------|-------|
| 1 | CLI 启动 | 无崩溃 | PASS |
| 2 | Finder 操作 | Spotlight 打开 Finder → Cmd+Shift+G → 输入 ~/Downloads → 回车 | PASS |
| 3 | 完成通知 | 窗口标题显示 "下载" | PASS |
| 4 | trace 文件 | 完整记录（43 事件） | PASS |

**观察**: Agent 使用了 Spotlight + "前往文件夹" 快捷键的方式，非常智能。

---

## AC7: Safari 浏览器端到端验证

**命令**: `AXION_HELPER_PATH=./build/debug/AxionHelper axion run "打开 Safari，访问 example.com"`
**运行 ID**: 20260510-2655ra
**耗时**: ~7 秒

**验证步骤**:

| # | 检查项 | 预期结果 | 通过? |
|---|--------|----------|-------|
| 1 | CLI 启动 | 无崩溃 | PASS |
| 2 | Safari 操作 | launch_app 成功 → open_url https://example.com 成功 | PASS |
| 3 | 完成通知 | 终端显示任务完成 | PASS |
| 4 | trace 文件 | 完整记录（10 事件） | PASS |

**观察**: 最简洁的测试用例，仅 2 步即完成（launch_app + open_url），10 个 trace 事件。

---

## 测试结果汇总

| AC | 场景 | 状态 | 运行 ID | trace 事件数 |
|----|------|------|---------|-------------|
| AC4 | Calculator 17x23=391 | **PASS** | 20260510-z6880l | 90 |
| AC5 | TextEdit Hello World | **PASS** | 20260510-ex5r79 | 40 |
| AC6 | Finder 下载目录 | **PASS** | 20260510-7ej9wi | 43 |
| AC7 | Safari example.com | **PASS** | 20260510-2655ra | 10 |

## 修复记录

端到端验证前发现并修复了一个问题：

1. **系统 prompt 不兼容 SDK Agent Loop**：原 `planner-system.md` 指导 LLM 输出 JSON 计划文本，但 SDK Agent Loop 需要 LLM 直接调用 MCP 工具。已重写 prompt 为 SDK Agent Loop 兼容格式。

**签字**: nick **日期**: 2026-05-10
