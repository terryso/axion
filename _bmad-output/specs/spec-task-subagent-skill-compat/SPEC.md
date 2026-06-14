---
id: SPEC-task-subagent-skill-compat
companions:
  - brownfield-analysis.md
  - architecture.md
  - implementation-plan.md
  - test-plan.md
  - ../../project-context.md
sources:
  - https://code.claude.com/docs/en/skills
  - https://code.claude.com/docs/en/sub-agents
  - https://code.claude.com/docs/en/agent-sdk/subagents
  - https://code.claude.com/docs/en/mcp
---

> **规范合约。** 本 SPEC 及 `companions:` 中列出的文件构成完整的、经保真验证的构建、测试、验收合约。frontmatter 中列出的源文件仅用于溯源；本 spec 的代码事实已经沉淀到 companion，不要求下游重复查阅源叙事。

# Claude Task 子代理 Skill 兼容

## Why

Axion 已能发现和直接执行 `/skill-name args`，但 Claude Code 生态中的 workflow skill 会在 `SKILL.md` 中要求调用 `Task(subagent_type: "general-purpose", description: ..., prompt: ...)` 来派生子代理。Claude Code/Agent SDK 现在把这个子代理入口称为 `Agent`，旧 `Task` 形状是兼容别名；Axion 的本地 SDK 已经有 `Agent` tool 和 `SubAgentSpawner`，因此本工作应把 `Task` 当作 `Agent` 的 Claude Code alias，而不是新增一套独立子代理运行时。

BMAD 的 `bmad-story-pipeline` 正依赖这个语义：父 skill 读取 workflow steps，然后每一步通过 Task/Agent 子代理执行一个 `/bmad-*` 单步 skill。当前 Axion 会把 `Task(...)` 当作普通 prompt 文本，不会把它稳定映射成宿主级子代理工具调用，导致这类 Claude Code skill 在 Axion 中只能偶然靠模型猜测执行，无法成为可测试能力。

同时，Claude Code skill/subagent 机制不是“只加载 prompt”。skill 可以声明工具需求，subagent 可以限制 `tools`、声明 `mcpServers` 和 `skills`，MCP 工具还有 ToolSearch/alwaysLoad 这样的可见性策略。Axion 当前 lightweight skill agent 只给 core tools，且普通 agent 固定排除 `ToolSearch`，这会让需要 WebSearch、MCP、ToolSearch 或跨 skill 调用的 Claude Code skill 失真。兼容目标必须覆盖工具可见性和权限继承，而不是只接上 `Task` 名称。

## Capabilities

- id: CAP-1
  intent: 用户可以在 Axion 中直接运行包含 Claude Code `Task(...)` 指令的 filesystem skill，并获得与 Claude Code 相同的顺序子任务执行语义。
  success: 在安装 `bmad-story-pipeline` 与其引用的单步 BMAD skills 后，输入 `/bmad-story-pipeline <story-id>` 会按 workflow 文件顺序派生每个 Task 子任务；父执行等待每个子任务完成后再进入下一步。

- id: CAP-2
  intent: Axion agent 可以识别 Claude Code 风格的 `Task` 工具调用形状，并将其映射为 SDK `Agent` 子代理能力的别名。
  success: 工具池中存在名为 `Agent` 和兼容名 `Task` 的 subagent launcher；两者共用同一 schema 和执行体，接受 `prompt`、`description`、`subagent_type`；模型调用任一名称时，SDK 提供非空 `SubAgentSpawner`，并返回子代理结果而不是 `Agent spawner not available`。

- id: CAP-3
  intent: Task 子代理可以执行 prompt 中的 `/skill-name args` 命令，并复用父会话已经发现的 SkillRegistry。
  success: 子代理收到 `Execute /bmad-create-story 1-1 yolo ...` 时，可以通过 Skill tool 执行 `bmad-create-story`，而不是把 slash 文本当作普通聊天内容或报未知命令。

- id: CAP-4
  intent: filesystem skill 直接执行时可以可靠访问 skill 包内的 supporting files。
  success: 直接 `/bmad-story-pipeline 1-1` 时，agent 能定位并读取该 skill 目录下的 `references/workflow-steps.md`；不依赖当前工作目录碰巧存在同名相对路径。

- id: CAP-5
  intent: 子任务执行保持 Axion 既有权限、dry-run、no-skills 和工具边界语义。
  success: dry-run 不暴露 side-effect Task/Skill/Bash 工具；`--no-skills` 不允许 skill pipeline 执行；子代理默认不继承 `Agent`/`Task` 递归派生能力，除非未来显式开启嵌套子代理。

- id: CAP-6
  intent: 用户能在 streaming 输出中看见每个 Task 子任务的开始、完成、失败与摘要。
  success: 运行 pipeline 时，终端至少显示每个 Task 的 `description`、被执行的 `/skill-name args`、完成状态、错误信息；任一步失败时父 pipeline 停止并报告失败步骤。

- id: CAP-7
  intent: 兼容层有可隔离的单元测试和少量可选 E2E 验证，不依赖真实外部服务完成默认开发验证。
  success: Swift Testing 单元测试覆盖 tool 注册、Task schema、spawner 注入、子代理工具过滤、skill supporting-file prompt 注入和 dry-run/no-skills 行为；真实 API E2E 只作为可跳过验证，不进入默认单元测试命令。

- id: CAP-8
  intent: Claude Code skill/subagent 的工具声明不会被 Axion lightweight skill runtime 静默缩窄。
  success: direct skill execution 和 Task child agent 会从同一份可配置工具池中继承 SDK core/specialist、Skill、Agent/Task、WebSearch/WebFetch、MCP resource/tool、ToolSearch 可见性策略；`allowed-tools`/subagent `tools` 能过滤这些工具，未知或当前不支持的工具名会产生可诊断信息，而不是被解析成“无限制”或静默忽略。

## Constraints

- 必须使用 Swift 和现有 `open-agent-sdk-swift` path dependency；运行时不得引入 Node.js 或 Python 编排层。
- 必须保持现有 `/skill-name args` 直接执行路径：built-in slash command 优先，SkillRegistry 匹配第二，未知 `/xxx` 继续透传给普通 agent。
- 必须优先复用 SDK 已有 `AgentTool`、`SubAgentSpawner`、`SkillTool`、`SkillRegistry`、`executeSkillStream`，避免在 Axion 侧复制一套 agent runtime。
- `Task` 是 side-effect tool；dry-run、权限模式、tool allowlist、session allowlist 必须按现有工具规则处理。
- 子代理默认移除 `Agent` 与 `Task` 两个派生工具，避免 pipeline skill 造成无限递归或失控并发；未来如支持 nested subagents 必须显式开启并有深度/预算限制。
- 不允许因为 skill execution 是 lightweight path 就一刀切移除 MCP、WebSearch/WebFetch、ToolSearch 或跨 skill 调用能力；这些工具必须由 config、permission mode、skill `allowed-tools`、subagent `tools`/`mcpServers` 和 dry-run/no-skills 策略共同决定。
- `allowed-tools` 解析必须能表达 Claude Code 常见工具名、SDK 工具名、`Agent`/`Task`、`Skill`、Web tools、MCP namespaced tool；不能因遇到未知工具名就退化成无工具限制。
- 单元测试必须使用 Swift Testing，不能调用真实 `AgentBuilder.build()`、真实 MCP、真实 Helper 进程或桌面通知。
- 开发完成后的默认验证只运行项目定义的单元测试范围，不运行 `Tests/**/Integration/` 或 `Tests/**/AxionE2ETests/`。

## Non-goals

- 不实现完整 workflow/DAG 引擎；本工作只兼容 Claude Code skill 中的 Task 子代理模式。
- 不实现 background subagent、resume subagent、worktree isolation、team coordination 的完整运行时语义；这些字段可以保留但不作为验收范围。
- 不实现完整 `.claude/agents/*.md` 管理 UI、agent marketplace 或 subagent 文件热加载；本工作只要求现有 SDK `AgentDefinition` 能被 `Agent`/`Task` alias 正确调用，并记录 filesystem subagent definition 的后续差距。
- 不硬编码 BMAD 专属命令别名表。旧命令名兼容应通过 skill aliases 或更新 skill 包解决。
- 不改变现有 skill frontmatter 格式或要求用户重写已有 Claude Code skill。
- 不让 `Task(...)` 代码块在宿主层被静态解析执行；执行仍由模型通过工具调用完成，但工具名和 prompt guidance 必须让该调用稳定可达、可测。

## Success signal

在 Axion 交互模式中输入 `/bmad-story-pipeline 1-1`，agent 读取 pipeline skill 的 `references/workflow-steps.md`，依次调用 `Task` tool 派生子代理执行 `/bmad-create-story 1-1 yolo`、`/bmad-testarch-atdd 1-1 yolo`、`/bmad-dev-story 1-1 yolo`、`/bmad-code-review 1-1 yolo`、`/bmad-testarch-trace 1-1 yolo`。每一步完成后父 agent 汇总状态；任一步失败则停止，报告失败 step 和可手动重试的命令。

## Assumptions

- 当前主要兼容目标是 Claude Code skill 生态中已存在的 `Task(subagent_type: "general-purpose", description: ..., prompt: ...)` 形状。
- `general-purpose` 子代理不需要专门 AgentDefinition；未命中特定定义时可继承父模型和默认系统提示。
- BMAD 单步 skills 已通过 `.agents/skills` 或 `.claude/skills` 安装，并可由 Axion 的 `SkillRegistry` 发现。
- 真实 pipeline 的长耗时行为由现有 maxSteps 和用户权限策略约束，本 spec 不新增独立预算系统。

## Open Questions

- `Task` alias 应长期放在 SDK 作为 `createTaskTool()`，还是只作为 Axion 的 Claude Code compatibility wrapper？当前倾向 SDK，因为 spawner detection、child tool filtering 和 Agent alias 应保持同层。
- 是否需要在 Axion 中显示 `Task` 子代理的层级 tree，还是先使用现有 tool progress 和文本摘要即可？
- 是否要给旧 BMAD 命令名如 `/bmad-bmm-create-story` 提供 alias migration 提示，还是要求用户同步 skill 包到新命令名？
- 是否需要补齐 `.claude/agents/*.md` filesystem subagent discovery，还是先只依赖 SDK `AgentDefinition` 和内置 `general-purpose`？
- `ToolSearch` 对 GLM 的干扰应继续作为 Axion 默认关闭，还是改为 provider/config 控制，并允许 skill/subagent 显式声明时启用？
