# Skill 生命周期闭环 Spec

## 问题分析

当前 skill 系统存在三个断裂：

1. **`~/.axion/skills/` 不可被发现** — `SkillLoader.defaultSkillDirectories()` 扫描 5 个路径（`~/.claude/skills/`、`~/.agents/skills/` 等），不包含 `~/.axion/skills/`。复制到这里的 skill 不会被加载。
2. **Agent 无法持久化创建 skill** — `review_create_skill` 只在内存 `SkillRegistry` 中注册，不写磁盘。agent 重启后 skill 丢失。且没有任何运行时工具允许 agent 主动创建并保存 skill。
3. **Curator 管道断链** — Curator 只处理 `provenance == .agentCreated` 的 skill，但整个代码库没有任何地方调用 `setProvenance(., .agentCreated)`。因此 Curator 的两阶段管道（机械式生命周期 + LLM 伞形合并）实际上永远不会执行任何操作。

---

## 设计决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| `save_skill` 工具归属 | **SDK 侧** | SDK 已有完整的 skill 基础设施（SkillLoader、SkillRegistry、SkillUsageStore），save_skill 是自演进体系的一部分 |
| `userInvocable` 默认值 | **true** | Agent 创建 skill 是因为识别到可复用模式，用户应能直接触发；curator 的 review_create_skill 才是 false |
| 归档策略 | **方案 A：移到 `.archived/` 目录** | SkillLoader 不扫描 `.` 开头目录，无需改 SkillLoader 读 frontmatter 逻辑 |

---

## 实施进度

| 章节 | SDK 侧 | Axion 侧 |
|------|--------|----------|
| 2a. `save_skill` 工具 | **已完成** (0.7.4) | — |
| 2b. AgentBuilder 注册 `save_skill` | — | 待做 |
| 2c. System prompt 指引 | — | 待做 |
| 2d. `review_create_skill` 持久化 | **已完成** (0.7.4) | — |
| 3a. Provenance 标记链路 | **已完成** (0.7.4) | — |
| 3b. Curator 产出持久化 | **已完成** (0.7.4) | — |
| 3c. Retired skill 过滤 | **已完成** (0.7.4) | — |
| 1. `~/.axion/skills/` 发现路径 | — | 待做 |
| skillsDir 传递链 | — | **已完成** (编译适配) |

---

## Spec

### 1. `~/.axion/skills/` 纳入 Skill 发现路径

**目标**：`~/.axion/skills/` 下的 skill 与 `~/.claude/skills/` 等路径的 skill 一样可被发现、加载和使用。

**方案**：在所有调用 `registerDiscoveredSkills()` 的地方，将 `~/.axion/skills/` 加入扫描目录列表。

**修改文件**：`Sources/AxionCLI/Config/ConfigManager.swift`

新增统一方法：

```swift
extension ConfigManager {
    /// Skill 发现扫描目录列表，last-wins 优先级。
    static var skillDiscoveryDirectories: [String] {
        let axionSkillsDir = (defaultConfigDirectory as NSString).appendingPathComponent("skills")
        return SkillLoader.defaultSkillDirectories() + [axionSkillsDir]
    }
}
```

**扫描优先级**（last-wins）：
1. `~/.config/agents/skills`（最低）
2. `~/.agents/skills`
3. `~/.claude/skills`
4. `$PWD/.agents/skills`
5. `$PWD/.claude/skills`
6. `~/.axion/skills`（新增，最高优先级）

所有调用点统一改为 `registerDiscoveredSkills(from: ConfigManager.skillDiscoveryDirectories)`：

| 调用位置 | 文件 |
|----------|------|
| `AgentBuilder.build()` | `Sources/AxionCLI/Services/AgentBuilder.swift` |
| Gateway 启动 | `Sources/AxionCLI/Commands/GatewayCommand.swift` |
| Curator 构建 | `Sources/AxionCLI/Commands/CuratorCommand.swift` |
| Run 命令 | `Sources/AxionCLI/Commands/RunCommand.swift` |
| Server 命令 | `Sources/AxionCLI/Commands/ServerCommand.swift` |
| Skill list 命令 | `Sources/AxionCLI/Commands/SkillListCommand.swift` |

---

### 2. Agent 运行时可创建并持久化 Skill

#### 2a. 新增 `save_skill` 工具（SDK 侧）

**文件**：SDK 新增 `Sources/OpenAgentSDK/Tools/Advanced/SaveSkillTool.swift`

**工具名**：`save_skill`

**入参**：
- `name`（必填）：skill 名称，只允许 `[a-z0-9-]`
- `description`（必填）：skill 描述
- `promptTemplate`（必填）：skill 的 prompt 模板
- `whenToUse`（可选）：触发条件
- `aliases`（可选，逗号分隔）：别名列表
- `userInvocable`（可选，默认 `true`）：是否用户可直接调用

**工厂函数签名**：

```swift
public func createSaveSkillTool(
    skillRegistry: SkillRegistry,
    usageStore: SkillUsageStore,
    skillsDir: String
) -> ToolProtocol
```

其中 `skillsDir` 是 `~/.axion/skills/` 的绝对路径，由 Axion 侧传入。

**行为**：
1. 校验名称合法性（`[a-z0-9-]`，非空）
2. 检查同名 skill 是否已存在：
   - 若已存在且 provenance 为 `bundled` 或 `userDefined` → 返回错误，不允许覆盖
   - 若已存在且 provenance 为 `agentCreated` → 允许覆盖
3. 创建目录 `<skillsDir>/<name>/`
4. 写入 `SKILL.md`：

```markdown
---
name: <name>
description: <description>
when-to-use: <whenToUse>
aliases: <aliases>
---

<promptTemplate>
```

5. 构造 `Skill` 对象并 `skillRegistry.register()`（当前会话立即可用）
6. 在 `usageStore` 中 `setProvenance(name, .agentCreated)`
7. 返回 `{"success": true, "message": "Skill '<name>' created"}`

#### 2b. 在 AgentBuilder 中注册 `save_skill`

**文件**：`Sources/AxionCLI/Services/AgentBuilder.swift`

在构建 agent 时，将 `save_skill` 工具注入。`AgentBuilder` 已有 `skillsDir` 和 `SkillUsageStore` 实例（在 step 11 创建），复用即可：

```swift
let saveSkillTool = createSaveSkillTool(
    skillRegistry: skillRegistry,
    usageStore: concreteStore,
    skillsDir: skillsDir
)
// 加入 agent.options.tools
```

**注意**：`save_skill` 需要在 `noMemory == false` 且 `dryrun == false` 时才注入（与 ReviewOrchestrator 同条件），因为需要 `SkillUsageStore`。

#### 2c. 在 system prompt 中告知 agent 可以创建 skill

在 Axion 的 system prompt 中增加一段指引：

> 当你在对话中发现反复出现的模式、用户特定的偏好、或可复用的工作流时，你可以使用 `save_skill` 工具将其保存为一个 skill。保存的 skill 会持久化到磁盘，在未来的会话中自动加载。skill 应该是类级别的通用指令，不是 session 级别的临时笔记。

#### 2d. Review agent 的 `review_create_skill` 持久化

**文件**：SDK `Sources/OpenAgentSDK/Tools/Review/ReviewSkillCreateTool.swift`

当前只在内存注册。改为：

1. 工厂函数增加 `skillsDir: String` 和 `usageStore: SkillUsageStore` 参数
2. 创建 skill 时同时写 `SKILL.md` 到 `<skillsDir>/<name>/SKILL.md`
3. 调用 `usageStore.setProvenance(name, .agentCreated)`
4. 在内存 `skillRegistry` 中注册（保持不变）

**注意**：`createReviewTools()` 函数签名也需要更新，透传 `skillsDir`。

---

### 3. Curator 管道闭环

#### 3a. Provenance 标记链路

| 场景 | 当前 | 应有 |
|------|------|------|
| `save_skill` 工具创建 | 不存在 | `agentCreated` |
| `review_create_skill` 创建 | 无 provenance（不写 usageStore） | `agentCreated` |
| 用户手动复制到 `~/.axion/skills/` 的 skill | `userDefined`（默认） | 保持 `userDefined` |

**关键**：`save_skill` 和 `review_create_skill` 必须在 `SkillUsageStore` 中调用 `setProvenance(name, .agentCreated)`。这是 Curator 管道能工作的前提。

#### 3b. Curator 产出的 skill 持久化

Curator Phase 2 通过 `review_create_skill`、`review_update_skill`、`review_add_skill_file` 操作 skill。需要：

**`review_create_skill`**（见 2d）：写 `SKILL.md` 到磁盘 + 标记 `agentCreated`。

**`review_update_skill`**：
- **文件**：SDK `Sources/OpenAgentSDK/Tools/Review/ReviewSkillUpdateTool.swift`
- 当前流程：`SkillEvolver.evolve()` → LLM → evolved skill → `skillRegistry.replace()`
- 补充：evolved skill 继承 `original.baseDir`，用 `baseDir` 重建 SKILL.md
- 写回逻辑：从 evolved skill 的字段（name, description, whenToUse, aliases, promptTemplate）重建完整的 SKILL.md（frontmatter + body），覆盖 `<baseDir>/SKILL.md`
- 如果 `baseDir` 为 nil（纯内存创建的 skill），则写入 `<skillsDir>/<name>/SKILL.md`

**`review_add_skill_file`**：
- **文件**：SDK `Sources/OpenAgentSDK/Tools/Review/ReviewSkillFileTool.swift`
- 当前已写磁盘（依赖 `skill.baseDir`），但如果是纯内存创建的 skill（`baseDir == nil`），会返回错误 "programmatically created skills cannot have files added"
- 补充：当 `baseDir == nil` 时，先在 `<skillsDir>/<name>/` 创建目录和 SKILL.md，再写 support 文件

**`curator_archive_skill`** — 归档方案（方案 A：移目录）：
- **文件**：SDK `Sources/OpenAgentSDK/Tools/Review/CuratorArchiveTool.swift`
- 行为：将 `<skillsDir>/<name>/` 移动到 `<skillsDir>/.archived/<name>/`
- `.archived/` 以 `.` 开头，`SkillLoader` 的目录扫描不会进入
- 需要新增 `skillsDir` 参数传入
- 从 `skillRegistry` 中移除该 skill（不只是 replace 为 retired 状态）
- 在 `usageStore` 中更新 `lastManagedAt`，保持 `absorbedInto` 记录不变
- 归档是可恢复的：用户可以手动从 `.archived/` 移回，或通过命令行 `axion skill unarchive <name>`

#### 3c. Retired skill 从 skill 列表隐藏

**问题**：当前 `SkillTool`（agent 调用 skill 的工具）和 `SkillRegistry.userInvocableSkills` 不过滤 `lifecycleState`。Curator 在运行时将 skill 标为 retired 后，在 agent 重启前该 skill 仍会被列出和调用。

**方案**：在 `SkillRegistry.userInvocableSkills` 中增加 `lifecycleState` 过滤：

```swift
// SkillRegistry.swift - userInvocableSkills
public var userInvocableSkills: [Skill] {
    queue.sync {
        orderedNames.compactMap { name -> Skill? in
            guard let skill = skills[name],
                  skill.userInvocable,
                  skill.isAvailable(),
                  skill.lifecycleState != .retired,   // 新增
                  skill.lifecycleState != .deprecated  // 新增
            else {
                return nil
            }
            return skill
        }
    }
}
```

这样 deprecated 和 retired 的 skill 不会出现在 agent 可见的 skill 列表中，但仍然在 registry 中保留（Curator 可以操作它们）。

#### 3d. `save_skill` 与 `review_create_skill` 名称冲突处理

两个工具都能创建 skill 到同一个 `~/.axion/skills/` 目录。冲突规则：

| 场景 | 处理 |
|------|------|
| `save_skill` 创建已存在且 provenance 为 `agentCreated` 的 skill | 允许覆盖 |
| `save_skill` 创建已存在且 provenance 为 `bundled`/`userDefined` 的 skill | 返回错误 |
| `review_create_skill` 创建已存在的 skill | 返回 "already exists"（保持当前行为） |
| `save_skill` 和 `review_create_skill` 先后创建同名 skill | 先到先得，后者报错 |

#### 3e. Gateway 模式下的 skill 热更新

Gateway 模式下 agent 长驻。`save_skill` 创建 skill 后：
- 当前 agent 进程：通过 `skillRegistry.register()` 立即可用
- `SkillUsageStore` 是 actor，`save_skill` 和 Curator 共享同一个实例，provenance 写入立即可见
- 无需重启 agent

**关键**：`AgentBuilder` 已在 step 11 构建 `SkillUsageStore`（当 `noMemory == false` 且 `dryrun == false` 时）。`save_skill` 工具共享同一个 store 实例。

---

## 修改文件清单

### Axion 侧

| 文件 | 修改内容 | 状态 |
|------|----------|------|
| `Sources/AxionCLI/Config/ConfigManager.swift` | 新增 `skillDiscoveryDirectories` 计算属性 | 待做 |
| `Sources/AxionCLI/Services/AgentBuilder.swift` | 1) 注册 `save_skill` 工具<br>2) 使用 `ConfigManager.skillDiscoveryDirectories` 发现 skill | 部分完成（skillsDir 已传） |
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | 使用统一发现路径 | skillsDir 已传；发现路径待做 |
| `Sources/AxionCLI/Commands/CuratorCommand.swift` | 使用统一发现路径 | skillsDir 已传；发现路径待做 |
| `Sources/AxionCLI/Commands/RunCommand.swift` | 使用统一发现路径 | 待做 |
| `Sources/AxionCLI/Commands/ServerCommand.swift` | 使用统一发现路径 | 待做 |
| `Sources/AxionCLI/Commands/SkillListCommand.swift` | 使用统一发现路径 | 待做 |
| System prompt 文件 | 增加 skill 创建指引 | 待做 |
| `Tests/AxionCLITests/Services/RunOrchestratorReviewTests.swift` | 补充 `skillsDir` 参数 | **已完成** |

### SDK 侧（open-agent-sdk-swift） — 已全部完成，已发布为 0.7.4

| 文件 | 修改内容 |
|------|----------|
| 新增 `Skills/SkillWriter.swift` | 共享 helper，写 SKILL.md 到磁盘（frontmatter + body） |
| 新增 `Tools/Advanced/SaveSkillTool.swift` | `save_skill` 工具实现 |
| `Tools/Review/ReviewSkillCreateTool.swift` | 加 `skillsDir` + `usageStore`；写磁盘；标记 `agentCreated` |
| `Tools/Review/ReviewSkillUpdateTool.swift` | evolved skill 写回磁盘；`baseDir == nil` 时写入 `skillsDir` |
| `Tools/Review/ReviewSkillFileTool.swift` | `baseDir == nil` 时先 materialize 再写 support 文件 |
| `Tools/Review/CuratorArchiveTool.swift` | 移目录到 `.archived/`；`registry.unregister()` |
| `Tools/Review/ReviewTools.swift` | `createReviewTools()` 增加 `skillsDir` 参数 |
| `Tools/SkillRegistry.swift` | `userInvocableSkills` 过滤 retired/deprecated |
| `Utils/IntelligentCurator.swift` | 增加 `skillsDir` 属性，透传给 `createReviewTools()` |
| `Utils/ReviewOrchestrator.swift` | 增加 `skillsDir` 属性，透传给 `createReviewTools()` |
| `Stores/SkillUsageStore.swift` | 新增 `public static let defaultSkillsDir` |

---

## 验收标准

1. 手动将一个有效的 skill 目录（含 `SKILL.md`）复制到 `~/.axion/skills/`，启动 `axion run` 或 `axion gateway`，agent 能通过 Skill 工具调用该 skill
2. 通过 TG 给 agent 发消息让它创建一个 skill，agent 调用 `save_skill` 后，`~/.axion/skills/<name>/SKILL.md` 存在于磁盘，且 `.usage.json` 中该 skill 的 provenance 为 `agentCreated`
3. 重启 agent 后，agent 仍能发现并使用之前创建的 skill
4. Curator 运行时（`axion curator run`），能正确识别 `agentCreated` 的 skill 并执行生命周期评估（Phase 1）和 LLM 合并（Phase 2）
5. Curator 合并后的伞形 skill 写入了 `~/.axion/skills/`，且被归档的 skill 目录移到了 `~/.axion/skills/.archived/`
6. 被归档的 skill 在下一次 agent 启动后不会出现在 skill 列表中
7. `save_skill` 创建的 skill 当前会话立即可用（不需要重启）
8. 尝试覆盖 `userDefined` provenance 的 skill 时返回错误
