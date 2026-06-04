---
title: 'Skill 生命周期闭环'
type: 'feature'
created: '2026-06-04'
status: 'done'
context: []
baseline_commit: '1676abe'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## 意图

**问题：** Skill 系统存在三个断裂：(1) `~/.axion/skills/` 不在发现路径中，复制到这里的 skill 不会被加载；(2) agent 运行时无法持久化创建 skill — `save_skill` 工具已在 SDK 0.7.4 实现，但未接入 AgentBuilder；(3) Curator 管道永远不会执行，因为没有代码将 skill 标记为 `agentCreated`。

**方案：** 通过 `ConfigManager.skillDiscoveryDirectories` 计算属性将 `~/.axion/skills/` 加入发现路径；在 AgentBuilder 中注册 SDK 的 `createSaveSkillTool`（复用 SkillUsageStore）；在 system prompt 中增加 skill 创建指引。

## 边界与约束

**必须：**
- 所有 `registerDiscoveredSkills()` 调用点统一使用 `ConfigManager.skillDiscoveryDirectories`，禁止硬编码目录列表
- `save_skill` 工具仅在 `noMemory == false && dryrun == false` 时注入（与 ReviewOrchestrator 同条件，因为需要 SkillUsageStore）
- 发现优先级 last-wins，`~/.axion/skills/` 作为最高优先级追加在末尾
- 更新全部 7 个现有调用点

**先问：**
- 无 — 所有决策已在输入 spec 中确定

**禁止：**
- 不修改 SDK 代码 — SDK 侧变更已全部在 0.7.4 发布
- 不修改 SkillLoader 的 defaultSkillDirectories — 扩展而非修改
- 不修改 AxionRuntime 的 skill 执行路径（仅用于 bumpView，不涉及发现）

</frozen-after-approval>

## Code Map

- `Sources/AxionCLI/Config/ConfigManager.swift` — 配置加载，定义 `defaultConfigDirectory`（~/.axion），无 `import OpenAgentSDK`，需新增计算属性
- `Sources/AxionCLI/Services/AgentBuilder.swift:200-207` — step 4 skill 发现与注册，`registerDiscoveredSkills()` 无参调用
- `Sources/AxionCLI/Services/AgentBuilder.swift:248-261` — step 8 工具构建，MemoryTool 条件注入位置
- `Sources/AxionCLI/Services/AgentBuilder.swift:312-374` — step 11 `skillsDir` + `SkillUsageStore` 创建（需提前到 step 4）
- `Sources/AxionCLI/Services/AgentBuilder.swift:535-575` — `buildFullSystemPrompt()`，Universal Memory Operations 段（line 552-561）后追加 save_skill 指引
- `Sources/AxionCLI/Commands/RunCommand.swift:86` — 直接 skill 执行路径的发现
- `Sources/AxionCLI/Commands/ServerCommand.swift:54` — server 启动时的 skill 发现
- `Sources/AxionCLI/Commands/GatewayCommand.swift:64,424` — gateway 启动 + curator registry 的 skill 发现（2 处）
- `Sources/AxionCLI/Commands/CuratorCommand.swift:38` — 独立 curator 的 skill 发现
- `Sources/AxionCLI/Commands/SkillListCommand.swift:19` — skill list 命令的发现
- `SDK:Sources/OpenAgentSDK/Tools/Advanced/SaveSkillTool.swift` — `createSaveSkillTool(skillRegistry:usageStore:skillsDir:) -> ToolProtocol`
- `SDK:Sources/OpenAgentSDK/Skills/SkillLoader.swift:125` — `defaultSkillDirectories()` 返回 5 个目录（不含 ~/.axion/skills/）

## 任务与验收

**执行：**

- [x] `Sources/AxionCLI/Config/ConfigManager.swift` — 新增 `import OpenAgentSDK`；新增 `static var skillDiscoveryDirectories: [String]` 计算属性，返回 `SkillLoader.defaultSkillDirectories() + [axionSkillsDir]`，其中 `axionSkillsDir` 从 `defaultConfigDirectory` 派生（`~/.axion/skills/`）。唯一来源。

- [x] `Sources/AxionCLI/Services/AgentBuilder.swift` — 四处修改：(1) line 205 `registerDiscoveredSkills()` → `registerDiscoveredSkills(from: ConfigManager.skillDiscoveryDirectories)`。(2) 将 `skillsDir` 和 `SkillUsageStore` 创建从 step 11（line 324-325）提前到 step 4 之前（约 line 199，和 `memoryDir` 并列），声明 `let usageStore: SkillUsageStore?`，条件 `!noMemory && !dryrun`。(3) step 8（line 253-261）与 MemoryTool 并列注入 `createSaveSkillTool`，复用同一 `usageStore` 和 `skillsDir`。Step 11 复用该 `usageStore`。(4) `buildFullSystemPrompt()` 的 Universal Memory Operations 段之后追加 `save_skill` 使用指引。

- [x] `Sources/AxionCLI/Commands/RunCommand.swift` — line 86 `registerDiscoveredSkills()` → `registerDiscoveredSkills(from: ConfigManager.skillDiscoveryDirectories)`。

- [x] `Sources/AxionCLI/Commands/ServerCommand.swift` — line 54 `registerDiscoveredSkills()` → `registerDiscoveredSkills(from: ConfigManager.skillDiscoveryDirectories)`。

- [x] `Sources/AxionCLI/Commands/GatewayCommand.swift` — 两处（line 64, line 424）→ `registerDiscoveredSkills(from: ConfigManager.skillDiscoveryDirectories)`。

- [x] `Sources/AxionCLI/Commands/CuratorCommand.swift` — line 38 → `registerDiscoveredSkills(from: ConfigManager.skillDiscoveryDirectories)`。

- [x] `Sources/AxionCLI/Commands/SkillListCommand.swift` — line 19 → `registerDiscoveredSkills(from: ConfigManager.skillDiscoveryDirectories)`。

**验收标准：**
- Given `~/.axion/skills/test-skill/` 下有有效 SKILL.md，when 启动 `axion run "test"`，then skill 可被发现并出现在 agent 的 Available Skills 段
- Given agent 以 memory 模式运行，when agent 调用 `save_skill`，then `~/.axion/skills/<name>/SKILL.md` 写入磁盘且当前会话立即可用
- Given `noMemory == true` 或 `dryrun == true`，when `AgentBuilder.build()` 执行，then `save_skill` 不在 agent 工具列表中
- Given 全部 7 个调用点已更新，when grep `registerDiscoveredSkills()`，then 不存在不带 `from:` 参数的调用

## Spec Change Log

## 设计说明

**save_skill 注入时序：** `SkillUsageStore` 必须在 step 8（工具构建，line 248）之前创建，因为 `agentTools` 在 step 9 封入 `AgentOptions`，step 10 创建 Agent 后工具列表即冻结。解决方案：将 `skillsDir` 和 `SkillUsageStore` 的创建从 step 11（line 324-325）提前到 step 3 附近（和 `memoryDir` 并列），声明为 `let usageStore: SkillUsageStore?`。Step 8 中条件注入 `save_skill`（与 MemoryTool 并列），step 11 复用同一实例给 ReviewOrchestrator 和 Curator。

**System prompt 指引** — 在 `buildFullSystemPrompt()` 的 Universal Memory Operations 段之后追加：
> 当你在对话中发现可复用模式、用户偏好或工作流时，可以使用 `save_skill` 工具将其持久化为 skill。保存的 skill 会写入磁盘，在未来的会话中自动加载。skill 应该是类级别的通用指令，不是 session 级别的临时笔记。

## 验证

**命令：**
- `swift build` -- 预期：基于 SDK 0.7.4 干净编译
- `grep -rn "registerDiscoveredSkills()" Sources/ --include="*.swift" | grep -v "from:"` -- 预期：零匹配（全部调用已更新）
- `swift test --filter "AxionCLITests"` -- 预期：全部单元测试通过

## Suggested Review Order

**Discovery path unification**

- Single source of truth for skill discovery directories
  [`ConfigManager.swift:95`](../../Sources/AxionCLI/Config/ConfigManager.swift#L95)

- Shared SkillUsageStore hoisted before skill registration + tool building
  [`AgentBuilder.swift:200`](../../Sources/AxionCLI/Services/AgentBuilder.swift#L200)

- Discovery callsite updated to use centralized directories
  [`AgentBuilder.swift:209`](../../Sources/AxionCLI/Services/AgentBuilder.swift#L209)

**save_skill tool injection**

- Tool injected conditionally alongside MemoryTool in step 8
  [`AgentBuilder.swift:270`](../../Sources/AxionCLI/Services/AgentBuilder.swift#L270)

- System prompt guidance gated on tool availability (review patch)
  [`AgentBuilder.swift:224`](../../Sources/AxionCLI/Services/AgentBuilder.swift#L224)

- Conditional prompt text appended only when tool is present
  [`AgentBuilder.swift:574`](../../Sources/AxionCLI/Services/AgentBuilder.swift#L574)

**Step 11 reuse of hoisted usageStore**

- ReviewOrchestrator + Curator now reuse the earlier usageStore
  [`AgentBuilder.swift:332`](../../Sources/AxionCLI/Services/AgentBuilder.swift#L332)

**7 callsite migrations**

- [`RunCommand.swift:86`](../../Sources/AxionCLI/Commands/RunCommand.swift#L86)
- [`ServerCommand.swift:54`](../../Sources/AxionCLI/Commands/ServerCommand.swift#L54)
- [`GatewayCommand.swift:64`](../../Sources/AxionCLI/Commands/GatewayCommand.swift#L64)
- [`GatewayCommand.swift:424`](../../Sources/AxionCLI/Commands/GatewayCommand.swift#L424)
- [`CuratorCommand.swift:38`](../../Sources/AxionCLI/Commands/CuratorCommand.swift#L38)
- [`SkillListCommand.swift:19`](../../Sources/AxionCLI/Commands/SkillListCommand.swift#L19)
