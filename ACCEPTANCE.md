# Axion 能力验收文档

验收日期：2026-05-20
验收目标：验证重构后的 planner-system.md 是否正确引导 LLM 选择合适的工具

| # | 测试任务 | 预期工具选择 | 预期行为 | 实际结果 |
|---|----------|-------------|---------|---------|
| 1 | `30+40*30=` | 无工具（直接回答） | LLM 直接计算并返回 1230 | ✅ 通过。直接回答 1230，无工具调用，1 次 LLM 调用 |
| 2 | `帮我打开计算器计算 10 * 67` | axion-helper MCP | 打开 Calculator.app，点击按钮，返回 670 | ✅ 通过。launch_app → list_windows → get_accessibility_tree → click(×10) → get_accessibility_tree 验证 |
| 3 | `今天广州天气如何` | playwright / WebSearch | 搜索广州天气并返回实时结果 | ✅ 通过。playwright 导航到 Google 搜索，返回完整天气数据 |
| 4 | `/polyv-live-cli 获取最新5个频道信息` | Skill 工具 | 调用 polyv-live-cli skill，返回频道列表 | ✅ 通过。Skill 调用成功，通过 Bash 执行 CLI 返回 5 个频道 |
| 5 | `帮我压缩一下~/Downloads/xxx.mp4` | Bash (ffmpeg) | 直接用 Bash 执行 ffmpeg 命令 | ✅ 通过。Bash × 3：ffprobe → ffmpeg(HEVC) → 对比结果。截图 0 次 |

## 验收结论

**5/5 全部通过。** 重构后的系统提示词成功引导 GLM 模型在不同任务类型中选择正确的工具：

- 纯计算任务 → 直接回答
- GUI 任务 → MCP 桌面自动化工具
- 实时信息 → 浏览器/Web 搜索工具
- Skill 匹配 → Skill 工具
- CLI 任务 → Bash 工具（**核心修复点**）

## 关键改动

### 1. `Prompts/planner-system.md` — 重写
- 身份从 "desktop automation agent" → "AI agent on macOS"
- 新增 Tool Selection 规则：CLI 优先用 Bash，GUI 才用 MCP
- 保留 MCP 工具的详细参考（Element Discovery、键盘规则等）

### 2. `AgentBuilder.swift` — 修复 base tools 缺失
- SDK 的 streaming 路径 (`agent.stream()`) 只发送 `options.tools` 到 API
- 之前 `options.tools` 只包含 `[PauseForHuman, Skill]`，Bash 等核心工具从未被发送
- 修复：显式将 `getAllBaseTools(.core) + .specialist)` 加入 `agentTools`
- 同时排除 `ToolSearch` 和 `AskUser`（GLM 模型已知兼容性问题）

### 3. `PromptBuilderTests.swift` — 更新测试
- 3 个旧测试检查已移除的 prompt 内容 → 更新为验证新的 CLI 优先原则
