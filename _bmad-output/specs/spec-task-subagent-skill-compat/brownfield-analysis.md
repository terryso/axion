# Brownfield Analysis

本文件记录当前 Axion 和 SDK 的真实状态，作为实现约束。下游实现时应以这些代码事实为起点，而不是从 Claude Code 的行为重新假设。

## 用户触发路径

Axion 交互模式已经具备 `/skill-name args` 直接执行能力：

- `ChatCommand` 在启动时创建 `SkillRegistry`，注册 Axion built-in skills，并从 `ConfigManager.skillDiscoveryDirectories` 发现 filesystem skills。
- `ChatCommandInputRouter.route()` 先解析 built-in slash command，再解析 resume 数字，再用 `resolveSkillName` 匹配 `/skill-name args`。
- 匹配到 skill 时，`ChatCommand` 使用 `agent.executeSkillStream(skillExec.name, args: skillExec.args)`；未匹配的 `/xxx` 继续走 `agent.stream(taskText)`。

代码位置：

- `Sources/AxionCLI/Commands/ChatCommand.swift:180` 到 `186`
- `Sources/AxionCLI/Chat/ChatCommandInputRouter.swift:28` 到 `49`
- `Sources/AxionCLI/Commands/ChatCommand.swift:617` 到 `624`

结论：用户输入 `/bmad-story-pipeline 1-1` 可以进入 skill execution path；问题不在 slash routing。

## Axion 当前工具池

普通 agent build 当前包含：

- SDK core tools 和 specialist tools，排除 `ToolSearch` 与 `AskUser`
- 非 dry-run 时追加 `Skill` tool
- 非 dry-run 时追加 storage/app uninstall tools
- review infrastructure 可用时追加 `save_skill`

代码位置：

- `Sources/AxionCLI/Services/AgentBuilder.swift:130` 到 `146`
- `Sources/AxionCLI/Services/AgentBuilder.swift:191` 到 `212`

当前缺口：

- 没有追加 `createAgentTool()`
- 没有追加 Claude Code 兼容名 `Task`
- 因此模型即使读到 `Task(...)` 指令，也没有名为 `Task` 的 tool 可调用
- 固定排除 `ToolSearch`；这可能适合当前 GLM 提示稳定性，但与 Claude Code 的 ToolSearch/alwaysLoad 可见性模型不一致，不能成为 skill/subagent 兼容层的硬规则

## Skill 专用 agent build

`AgentBuilder.buildSkillAgent()` 是 AxionRuntime 里的 lightweight skill execution path：

- 创建只含目标 skill 的 registry
- 工具只有 SDK core tools，排除 `ToolSearch` 和 `AskUser`
- 不包含 MCP servers、SkillTool、Memory、specialist tools、Agent/Task tool

代码位置：

- `Sources/AxionCLI/Services/AgentBuilder.swift:294` 到 `333`

结论：如果非交互路径通过 `AxionRuntime.executeSkill()` 执行 Task-based skill，也需要考虑是否给 skill agent 注册 Task 兼容 tool。

补充结论：仅追加 Task 仍不够。Claude Code skill 可以依赖 WebSearch、WebFetch、MCP tools、ToolSearch 或跨 skill 调用；Axion 的 skill agent 应从正常 agent 的可配置工具池继承，再按 dry-run、no-skills、permission 和 skill 限制过滤，而不是默认只给 core tools。

## Skill 工具限制当前状态

SDK `Skill` 已经有 `toolRestrictions`：

- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/SkillTypes.swift:12` 到 `35`
- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/SkillTypes.swift:69` 到 `70`

`SkillLoader` 会解析 frontmatter 的 `allowed-tools`：

- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Skills/SkillLoader.swift:99`
- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Skills/SkillLoader.swift:325` 到 `345`

但当前解析有兼容缺口：

- 只映射到固定 `ToolRestriction` enum，无法表达任意 MCP namespaced tool、custom tool、未来工具或 Claude Code 原始大小写名称。
- regex 提取后只保留 enum 命中的项；未知项会被忽略。如果全部未知，结果是 `nil`，运行时会被解释成“没有限制”。
- `executeSkill()` 和 `executeSkillStream()` 会把 restrictions 写入 `options.allowedTools`，但 raw value 是 `bash/read/...` 小写形式；真实工具名是 `Bash`、`Read`、`WebSearch` 等大小写名称时，需要确认过滤逻辑是否大小写兼容且覆盖 MCP/custom tool。
- `SkillTool` 明确不压入 ToolRestriction stack，注释说明因为限制只认识 SDK 内部工具名，会阻塞 MCP tools；这证实 MCP/custom tool 限制语义还没有完成。

结论：Claude Code 兼容层必须把 `allowed-tools` 从 enum-only 升级为“原始工具名 + 规范化别名 + unknown diagnostics”的模型，且过滤应发生在完整 assembled tool pool 上。

## SDK 子代理能力已存在但未接入 Axion

SDK 有 `Agent` tool：

- 工具名为 `Agent`
- schema 包含 `prompt`、`description`、`subagent_type`、`model`、`name`、`maxTurns`、`run_in_background`、`isolation`、`team_name`、`mode`、`resume`
- 执行时从 `ToolContext.agentSpawner` 获取 `SubAgentSpawner`
- `subagent_type` 缺省为 `general-purpose`

代码位置：

- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/Advanced/AgentTool.swift:96` 到 `153`

SDK 只有在工具池中存在名为 `Agent` 的 tool 时才创建 spawner：

- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift:2600` 到 `2607`
- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift:3223` 到 `3238`

结论：单独实现一个名为 `Task` 的 tool 还不够；要么同时注册 `Agent`，要么修改 SDK spawner detection，让 `Task` 也能触发 spawner。

命名结论：外部 Claude Code/Agent SDK 文档中的当前 subagent launcher 名称是 `Agent`，旧 `Task` 调用形状是兼容 alias。Axion 侧不应把 `Task` 设计成第二套子代理抽象，应把它实现为 `Agent` 的同 schema、同执行体 alias。

## SDK 子代理默认过滤

`DefaultSubAgentSpawner` 目前创建子 agent 时：

- 使用父工具池过滤后的 `subTools`
- 只移除名为 `Agent` 的工具
- `skills`、`runInBackground`、`isolation`、`teamName`、`resume` 字段标注为 deferred

代码位置：

- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Core/DefaultSubAgentSpawner.swift:111` 到 `125`
- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Core/DefaultSubAgentSpawner.swift:130` 到 `144`

结论：如果新增 `Task` tool，必须同步更新子工具过滤，避免子代理默认继承 `Task` 后递归派生。

额外缺口：`DefaultSubAgentSpawner` 的 enhanced fields 已包含 `mcpServers` 和 `skills` 参数，但实现里 reference MCP server resolution、skills、background、isolation、team、resume 都标注为 deferred。Claude Code subagent 兼容至少要把 unsupported/deferred 字段暴露成可诊断信息，否则用户会以为 subagent 声明已经生效。

## Skill supporting files 暴露差异

`SkillLoader.loadSkillFromDirectory()` 会保存：

- `baseDir`
- `supportingFiles`
- `promptTemplate`

它只会改写 Markdown link 中的 `](references/*.md)`，不会改写纯文本 `references/workflow-steps.md`。

代码位置：

- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Skills/SkillLoader.swift:84` 到 `112`
- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Skills/SkillLoader.swift:273` 到 `289`

`executeSkillStream()` 最终只把 `skill.promptTemplate` 和 `User request` 拼成 prompt，不附带 `baseDir` 或 `supportingFiles`：

- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift:3205` 到 `3217`

`SkillTool` 则会在 JSON result 中返回 `baseDir` 和 `supportingFiles`：

- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/Advanced/SkillTool.swift:116` 到 `139`

结论：直接 `/bmad-story-pipeline 1-1` 绕过 `SkillTool`，因此必须补齐直接 skill execution 的 package context，否则 `references/workflow-steps.md` 可能被错误解析为项目工作目录下的路径。

## Claude Code 机制对照后的额外差距

来自 Claude Code skills、subagents、Agent SDK subagents 和 MCP 文档的对照结论：

- Skill 是 package，而不是一段 prompt；supporting files/scripts/templates/assets 通过 progressive disclosure 按需读取。Axion 已保存 `baseDir` 和 `supportingFiles`，但 direct `executeSkillStream()` 没有把这些 metadata 传给模型。
- Skill 可被 `/skill-name` 手动触发。Axion 已有 direct slash routing，但 skill listing、description budget、visibility override 还没有对齐 Claude Code 的完整行为。
- Subagent 可以通过 filesystem definition 声明 `tools`、model、prompt 等。Axion SDK 有 `AgentDefinition` 类型，但当前 `AgentTool.swift` 只内置 `Explore` 和 `Plan`，没有加载 `.claude/agents/*.md`。
- MCP 工具可以 deferred，也可以 `alwaysLoad`。Axion 当前 normal agent 直接排除 `ToolSearch`，skill agent 又禁用 MCP servers；这会让需要 MCP/search 的 Claude Code skill 失真。
- Agent SDK subagent 可声明 `mcpServers` 和 `skills`。Axion 当前 spawner 对 reference MCP server lookup 与 skills wiring 仍是 deferred。

结论：MVP 可先完成 Task alias + full registry + supporting files，但 spec 必须记录工具策略、MCP/search、filesystem subagent definitions 和 diagnostics 这些后续差距。

## BMAD pipeline 兼容风险

远端 `bmad-story-pipeline` 当前 workflow steps 使用这些命令：

- `/bmad-create-story {STORY_ID} yolo`
- `/bmad-testarch-atdd {STORY_ID} yolo`
- `/bmad-dev-story {STORY_ID} yolo`
- `/bmad-code-review {STORY_ID} yolo`
- `/bmad-testarch-trace {STORY_ID} yolo`

本机 `~/.agents/skills/bmad-story-pipeline/references/workflow-steps.md` 已改成新命令名，但同一 skill 的 `SKILL.md` 正文仍有旧命令名：

- `/bmad-bmm-create-story`
- `/bmad-tea-testarch-atdd`
- `/bmad-bmm-dev-story`
- `/bmad-bmm-code-review`
- `/bmad-tea-testarch-trace`

Axion 项目内已安装的 BMAD 单步 skills 是新命名，如 `.agents/skills/bmad-create-story/SKILL.md`、`.agents/skills/bmad-dev-story/SKILL.md`、`.agents/skills/bmad-code-review/SKILL.md`、`.agents/skills/bmad-testarch-atdd/SKILL.md`、`.agents/skills/bmad-testarch-trace/SKILL.md`。

结论：兼容层不应硬编码旧名称；运行时应在找不到 skill 时给出明确错误，提示同步 skill 包或通过 aliases 解决。短期验证前还需要让本机 `SKILL.md` 和 `references/workflow-steps.md` 的命令名保持一致，否则父 prompt 可能仍从正文里的旧 `Task(...)` 片段派生错误命令。
