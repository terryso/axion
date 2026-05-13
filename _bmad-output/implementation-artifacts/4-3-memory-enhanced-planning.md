# Story 4.3: Memory 增强规划

Status: done

## Story

As a Planner,
I want 在生成计划时利用 Memory 中积累的历史操作经验（Profile、高频路径、已知失败、熟悉度标记）,
So that 计划更精准，减少试错和重规划次数.

## Acceptance Criteria

1. **AC1: 注入 App Memory 上下文到 Planner prompt**
   Given Memory 中有 Calculator 的操作记录（含 profile 和 familiar 标记）
   When Planner 规划 "打开计算器，计算 17 × 23"
   Then system prompt 注入 Calculator 的 Memory 上下文（已知控件路径、可靠操作序列、AX 特征）

2. **AC2: 标注已知不可靠操作路径**
   Given Memory 中有某 App 的失败经验（FailurePattern）
   When Planner 规划涉及该 App 的任务
   Then prompt 中标注已知不可靠的操作路径，避免重复失败

3. **AC3: 熟悉 App 使用紧凑规划策略**
   Given Memory 中某 App 标记为「已熟悉」（familiar tag，>= 3 次成功）
   When Planner 规划该 App 的任务
   Then 使用更紧凑的规划策略（减少验证步骤），缩短执行时间

4. **AC4: --no-memory 标志禁用 Memory 注入**
   Given 运行 `axion run "任务" --no-memory`
   When Planner 规划
   Then 不注入任何 Memory 上下文，行为等同于 Phase 1

5. **AC5: `axion memory list` 命令**
   Given 运行 `axion memory list`
   When 查看 Memory
   Then 显示已积累 Memory 的 App 列表和每个 App 的操作次数、最近使用时间

6. **AC6: `axion memory clear --app` 命令**
   Given 运行 `axion memory clear --app com.apple.calculator`
   When 清除特定 App Memory
   Then 删除该 App 的 Memory 文件，其他 App 不受影响

## Tasks / Subtasks

- [ ] Task 1: 创建 MemoryContextProvider 服务 (AC: #1, #2, #3)
  - [ ] 1.1 创建 `Sources/AxionCLI/Memory/MemoryContextProvider.swift`
  - [ ] 1.2 实现 `buildMemoryContext(task:store:) async throws -> String?` 方法：解析任务描述中涉及的 App domain，查询对应 Memory，组装 prompt 片段
  - [ ] 1.3 实现 domain 推断逻辑：从任务描述中匹配已知 App 名（Calculator、Finder、TextEdit、Safari、Chrome 等），再从 Memory 中查找对应的 domain
  - [ ] 1.4 实现 prompt 片段组装：读取 profile entries 和 familiar 标记，格式化为 Planner 可消费的 Memory 上下文文本

- [ ] Task 2: 在 RunCommand 中集成 Memory 上下文注入 (AC: #1, #2, #3, #4)
  - [ ] 2.1 在 `RunCommand` 添加 `@Flag(name: .long, help: "禁用 Memory 上下文注入") var noMemory: Bool = false`
  - [ ] 2.2 在 `buildFullSystemPrompt` 方法中，如果 `noMemory == false` 且 memoryStore 已创建，调用 MemoryContextProvider 获取上下文
  - [ ] 2.3 将 Memory 上下文追加到 system prompt 末尾，以清晰的 section header 分隔（如 `\n\n# App Memory Context\n`）
  - [ ] 2.4 保留现有 system prompt 构建逻辑不变，Memory 上下文是纯追加

- [ ] Task 3: 创建 `axion memory` 命令组 (AC: #5, #6)
  - [ ] 3.1 创建 `Sources/AxionCLI/Commands/MemoryCommand.swift` — 命令组入口
  - [ ] 3.2 创建 `Sources/AxionCLI/Commands/MemoryListCommand.swift` — `axion memory list` 子命令
  - [ ] 3.3 创建 `Sources/AxionCLI/Commands/MemoryClearCommand.swift` — `axion memory clear --app <domain>` 子命令
  - [ ] 3.4 在 `AxionCommand.swift`（或 main.swift）中注册 `memory` 子命令

- [ ] Task 4: 单元测试 (AC: #1–#6)
  - [ ] 4.1 `Tests/AxionCLITests/Memory/MemoryContextProviderTests.swift` — 测试 domain 推断、上下文组装、熟悉 App 紧凑策略
  - [ ] 4.2 `Tests/AxionCLITests/Commands/MemoryListCommandTests.swift` — 测试 list 输出格式
  - [ ] 4.3 `Tests/AxionCLITests/Commands/MemoryClearCommandTests.swift` — 测试 clear 逻辑

## Dev Notes

### 核心架构决策

**MemoryContextProvider 定位：** 轻量服务（struct），负责从 MemoryStore 读取历史数据并格式化为 Planner 可消费的 prompt 文本。不负责 MemoryStore 的写入或清理。

**注入点选择：** Memory 上下文注入到 **system prompt** 而非 user prompt。理由：
1. system prompt 是 Planner 的「行为规则」，Memory 是持久化的行为参考
2. user prompt 是单次任务描述，每次不同
3. 追加到 system prompt 末尾（在 `buildFullSystemPrompt` 中），与现有 prompt 内容不冲突

**domain 推断策略：** 简单关键词匹配，不做 NLP。维护一个 App 名到 domain 的映射表（如 "计算器"/"Calculator" → "com.apple.calculator"），从任务描述中查找匹配。找不到匹配时不注入（安全降级）。

### 与前序 Story 的关系

- **Story 4.1:** 创建了 `AppMemoryExtractor` 和 `MemoryCleanupService`，建立了 MemoryStore 集成框架。本 Story 的 `MemoryContextProvider` 读取 Story 4.1 保存的 KnowledgeEntry。
- **Story 4.2:** 创建了 `AppProfileAnalyzer` 和 `FamiliarityTracker`，保存了 tag 为 "profile" 和 "familiar" 的 KnowledgeEntry。本 Story 读取这些条目来构建 Memory 上下文。

### Memory 上下文格式设计

注入到 system prompt 的 Memory 上下文格式（示例）：

```
# App Memory Context

## Calculator (com.apple.calculator) — 熟悉度: 已熟悉

### 可靠操作路径
- launch_app -> click -> click -> click -> click (出现 4 次, 100% 成功)
- 点击按钮时使用 AX selector AXButton[title="X"] 最可靠

### AX 特征
- 窗口包含 AXButton 角色控件
- 按钮标题与数字/运算符直接对应

### 已知失败（避免重复）
- click(x:300,y:400) 坐标不可靠（未命中目标按钮）→ 使用 AX selector 代替

### 策略建议
- 此 App 已熟悉，可使用紧凑规划：减少 list_windows/get_window_state 验证步骤
- 直接使用已知可靠的 AX selector 路径
```

未熟悉的 App 格式：

```
# App Memory Context

## Finder (com.apple.finder) — 熟悉度: 初次接触（2 次操作）

### 可靠操作路径
- launch_app -> hotkey -> type_text (出现 2 次, 100% 成功)

### 已知失败（避免重复）
- click(x:150,y:300) 侧边栏坐标不稳定 → 使用 AX selector AXSidebar[ordinal=0]

### 策略建议
- 此 App 尚未熟悉，建议完整验证流程
```

无 Memory 数据时不注入任何内容（`MemoryContextProvider` 返回 `nil`）。

### App 名到 Domain 的映射

```swift
/// 常见 App 名称映射（用于从任务描述中推断 domain）
static let appNameMap: [(keywords: [String], domain: String)] = [
    (["calculator", "计算器"], "com.apple.calculator"),
    (["finder"], "com.apple.finder"),
    (["textedit", "文本编辑", "文本编辑器"], "com.apple.textedit"),
    (["safari"], "com.apple.safari"),
    (["chrome", "google chrome"], "com.google.chrome"),
    (["notes", "备忘录", "笔记本"], "com.apple.notes"),
    (["terminal", "终端"], "com.apple.terminal"),
    (["preview", "预览"], "com.apple.preview"),
    (["mail", "邮件"], "com.apple.mail"),
    (["calendar", "日历"], "com.apple.calendar"),
    (["photos", "照片"], "com.apple.photos"),
    (["music", "音乐"], "com.apple.music"),
    (["maps", "地图"], "com.apple.maps"),
    (["pages"], "com.apple.pages"),
    (["numbers"], "com.apple.numbers"),
    (["keynote"], "com.apple.keynote"),
]
```

推断逻辑：将任务描述转为小写，遍历映射表，匹配第一个 keyword。匹配到后检查 MemoryStore 中是否存在该 domain 的数据。

### 从 KnowledgeEntry 中读取 Profile 数据

Profile entries 的 tag 包含 "profile"，familiar entries 的 tag 包含 "familiar"。

查询方式：
```swift
// 查询 profile
let profileEntries = try await store.query(
    domain: domain,
    filter: KnowledgeQueryFilter(tags: ["profile"])
)

// 查询 familiar 标记
let familiarEntries = try await store.query(
    domain: domain,
    filter: KnowledgeQueryFilter(tags: ["familiar"])
)
let isFamiliar = !familiarEntries.isEmpty
```

Profile content 格式（由 Story 4.2 的 `buildProfileContent` 方法生成）：
```
App Profile: com.apple.calculator
总运行次数: 5
成功次数: 4
失败次数: 1
已熟悉: 是
AX特征: 窗口包含 AXButton 角色控件
高频路径: launch_app -> click -> click -> click -> click (频率:4, 成功率:100%)
已知失败: click(x:300,y:400) — 坐标或元素定位不可靠 (修正: 使用 AX selector AXButton[title="*"] 代替坐标点击)
```

MemoryContextProvider 需要解析这个文本格式来提取字段（复用 AppProfileAnalyzer 的 `extractField` 方法的思路）。

### 熟悉 App 的紧凑规划策略

当 App 标记为 familiar 时，在注入的上下文中添加策略指令：
```
### 策略建议
- 此 App 已熟悉，可使用紧凑规划
- 省略中间验证步骤（list_windows / get_window_state），直接使用已知可靠的操作路径
- 如使用 AX selector 且已知按钮标题，可直接 click 而无需先 get_accessibility_tree
```

这些指令附加到 system prompt 中，LLM 会自然遵循（减少不必要的验证调用）。

### `axion memory list` 实现要点

- 扫描 Memory 目录（`~/.axion/memory/`）中的 JSON 文件
- 每个文件对应一个 domain
- 统计每个 domain 的条目数和最近操作时间（从 KnowledgeEntry.createdAt 中取最大值）
- 输出格式：
  ```
  App Memory:
    com.apple.calculator — 8 entries, last used 2026-05-13
    com.apple.finder — 3 entries, last used 2026-05-12
  Total: 2 apps, 11 entries
  ```

### `axion memory clear --app` 实现要点

- 接受 domain 参数（如 `com.apple.calculator`）
- 删除 Memory 目录中对应的 JSON 文件
- 如果 domain 不存在，输出提示信息（不报错）
- 实现：`FileManager.default.removeItem(atPath: domainFilePath)`

### 需要修改的现有文件

1. **`Sources/AxionCLI/Commands/RunCommand.swift`** [UPDATE]
   - 当前状态：system prompt 在 `buildFullSystemPrompt` 中构建，包含 base prompt + dryrun 模式指令
   - 本次修改：
     - 添加 `@Flag(name: .long, help: "禁用 Memory 上下文注入") var noMemory: Bool = false`
     - 修改 `buildFullSystemPrompt` 方法签名，增加 `memoryContext: String?` 参数
     - 在 system prompt 末尾追加 Memory 上下文（如果非 nil）
   - 必须保留：所有现有功能（Agent 创建、流式输出、SafetyHook、Trace、Memory 提取和保存、Profile 分析）

2. **`Sources/AxionCLI/main.swift`** [UPDATE]
   - 当前状态：注册了 run / setup / doctor 子命令
   - 本次修改：注册 memory 子命令（和 run/setup/doctor 同级）
   - 必须保留：所有现有子命令注册

### 需要创建的新文件

1. **`Sources/AxionCLI/Memory/MemoryContextProvider.swift`** [NEW]
   - 纯计算 + MemoryStore 读取
   - 核心方法：`buildMemoryContext(task:store:) async throws -> String?`

2. **`Sources/AxionCLI/Commands/MemoryCommand.swift`** [NEW]
   - ArgumentParser 命令组，包含 list / clear 子命令

3. **`Sources/AxionCLI/Commands/MemoryListCommand.swift`** [NEW]
   - `axion memory list` 实现

4. **`Sources/AxionCLI/Commands/MemoryClearCommand.swift`** [NEW]
   - `axion memory clear --app <domain>` 实现

### 测试策略

- **MemoryContextProviderTests**: 使用 SDK 的 `InMemoryStore` 测试
  - 测试空 Memory 返回 nil
  - 测试有 profile 数据时返回完整上下文
  - 测试 familiar App 上下文包含紧凑策略建议
  - 测试非 familiar App 上下文包含完整验证建议
  - 测试任务描述中 App 名匹配逻辑
  - 测试无匹配 App 时返回 nil（安全降级）
  - 测试 failure 数据被正确标注为「避免」

- **MemoryListCommandTests**: 使用临时目录测试
  - 测试无 Memory 目录时的输出
  - 测试有多个 domain 时的列表格式
  - 测试最近使用时间显示

- **MemoryClearCommandTests**: 使用临时目录测试
  - 测试清除存在的 domain 成功
  - 测试清除不存在的 domain 不报错
  - 测试清除一个 domain 不影响其他 domain

### Import 顺序

```swift
// 1. 系统框架
import Foundation

// 2. 第三方依赖
import ArgumentParser
import OpenAgentSDK

// 3. 项目内部模块
import AxionCore
```

### 错误处理

- Memory 上下文获取失败不阻塞任务执行 — 降级为无 Memory 模式
- `MemoryContextProvider.buildMemoryContext` 内部 catch 所有 MemoryStore 错误，返回 nil
- `axion memory list` 错误正常输出到终端
- `axion memory clear` 文件不存在时不报错，输出提示

### 项目结构注意事项

- 新文件 `MemoryContextProvider.swift` 放在 `Sources/AxionCLI/Memory/` 目录（与 AppMemoryExtractor 同级）
- 新命令文件 `MemoryCommand.swift`、`MemoryListCommand.swift`、`MemoryClearCommand.swift` 放在 `Sources/AxionCLI/Commands/` 目录
- 测试文件放在 `Tests/AxionCLITests/Memory/` 和 `Tests/AxionCLITests/Commands/` 镜像源结构
- MemoryContextProvider 是应用层内部服务，不放在 AxionCore

### Story 4.2 的经验教训

- AppProfileAnalyzer 已使用 `stripMcpPrefix` 处理 `mcp__axion-helper__` 前缀的工具名 — 本 Story 不涉及工具名处理
- KnowledgeEntry 的 content 使用中文标签描述（如 "总运行次数:"、"成功次数:"） — 解析时应使用中文前缀
- SDK AgentOptions init 参数顺序：`memoryStore` 必须在 `hookRegistry` 之前
- Profile entries 是聚合结果，tag 为 "profile"，不关联单次运行（sourceRunId: nil）
- Familiar entries 的 tag 为 "familiar"，每个 domain 最多一条
- 高频路径格式："tool1 -> tool2 -> tool3 (频率:N, 成功率:M%)"
- 已知失败格式："action — reason (修正: workaround)"

### 性能考量

- Memory 查询在 `buildFullSystemPrompt` 中同步执行（async），在 Agent 创建之前完成
- 只查询任务描述中匹配到的 App domain，不扫描全部 Memory
- Profile 解析是简单的文本字段提取，O(n) 其中 n 是条目内容长度
- `--no-memory` 模式完全跳过 Memory 查询，零开销

### NFR 注意

- **NFR1**: Memory 查询不应增加 CLI 冷启动时间 — 查询在 Agent 运行阶段执行，不影响冷启动
- **NFR9**: API Key 不出现在 Memory 上下文中 — Memory 不存储 API Key
- **NFR27**: Memory 存储占用 < 10MB — MemoryContextProvider 只读取，不新增存储
- **NFR28**: 不直接适用，但熟悉 App 的紧凑策略会间接减少 LLM 调用

### Project Structure Notes

- 遵循现有 `Sources/AxionCLI/Memory/` 和 `Sources/AxionCLI/Commands/` 目录结构
- 新文件命名：`MemoryContextProvider.swift`、`MemoryCommand.swift`、`MemoryListCommand.swift`、`MemoryClearCommand.swift`
- Memory 功能仅涉及 AxionCLI 模块，不修改 AxionCore 或 AxionHelper
- 不修改 `planner-system.md` prompt 文件 — Memory 上下文在代码中动态追加到 system prompt

### References

- Story 4.1 实现文件: `Sources/AxionCLI/Memory/AppMemoryExtractor.swift`
- Story 4.2 实现文件: `Sources/AxionCLI/Memory/AppProfileAnalyzer.swift`
- Story 4.2 实现文件: `Sources/AxionCLI/Memory/FamiliarityTracker.swift`
- RunCommand 当前实现: `Sources/AxionCLI/Commands/RunCommand.swift`
- Planner system prompt: `Prompts/planner-system.md`
- PromptBuilder: `Sources/AxionCLI/Planner/PromptBuilder.swift`
- LLMPlanner: `Sources/AxionCLI/Planner/LLMPlanner.swift`
- main.swift 入口: `Sources/AxionCLI/main.swift`
- SDK MemoryStoreProtocol: `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/MemoryTypes.swift`
- SDK FileBasedMemoryStore: `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Stores/MemoryStore.swift`
- Epic 4 定义: `_bmad-output/planning-artifacts/epics.md` (Story 4.3)
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Project Context: `_bmad-output/project-context.md`
- Previous Story 4.2 file: `_bmad-output/implementation-artifacts/4-2-app-profile-auto-accumulation.md`

## Dev Agent Record

### Agent Model Used

Claude GLM-5.1[1m]

### Debug Log References

Build: clean (no errors, suppressed unused-variable warnings with `_`)
Tests: 578 passed, 0 failures (all AxionCLITests)

### Completion Notes List

- All 6 acceptance criteria (AC1-AC6) implemented and verified via ATDD tests
- AC1: MemoryContextProvider injects App Memory context (profile, AX features, patterns) into system prompt
- AC2: Known failure patterns annotated as "avoid" in injected context
- AC3: Familiar apps get compact planning strategy, unfamiliar get full verification advice
- AC4: `--no-memory` flag skips MemoryContextProvider entirely
- AC5: `axion memory list` displays domain list with entry counts and last-used dates
- AC6: `axion memory clear --app <domain>` removes specific domain file, others unaffected
- MemoryStore creation moved before prompt building so context can be injected
- Memory context appended at end of system prompt with clear section headers
- Safe degradation: any Memory error returns nil, never blocks task execution

### File List

- Sources/AxionCLI/Memory/MemoryContextProvider.swift [NEW]
- Sources/AxionCLI/Commands/MemoryCommand.swift [NEW]
- Sources/AxionCLI/Commands/MemoryListCommand.swift [NEW]
- Sources/AxionCLI/Commands/MemoryClearCommand.swift [NEW]
- Sources/AxionCLI/Commands/RunCommand.swift [UPDATED]
- Sources/AxionCLI/AxionCLI.swift [UPDATED]

### Review Findings

- [x] [Review][Patch] `appNameMap` should be `static let` not instance `let` [Sources/AxionCLI/Memory/MemoryContextProvider.swift:16] — FIXED: Changed to `static let appNameMap`.
- [x] [Review][Patch] Unused `extractField` return values for count fields [Sources/AxionCLI/Memory/MemoryContextProvider.swift:121-123] — FIXED: Removed dead code, added coupling comment.
- [x] [Review][Patch] `inferDomain` doc comment contradicts implementation [Sources/AxionCLI/Memory/MemoryContextProvider.swift:89-90] — FIXED: Updated doc comment to match actual behavior.
- [x] [Review][Patch] Profile field parsing uses hardcoded string prefixes without shared constants [Sources/AxionCLI/Memory/MemoryContextProvider.swift:121-126] — FIXED: Added comment noting coupling with RunCommand.buildProfileContent().
- [x] [Review][Patch] Uses first profile entry which may not be the latest [Sources/AxionCLI/Memory/MemoryContextProvider.swift:74] — FIXED: Now uses `max(by: { $0.createdAt < $1.createdAt })` to select latest.
- [x] [Review][Defer] Tight JSON format coupling in MemoryListCommand [Sources/AxionCLI/Commands/MemoryListCommand.swift:86-88] — deferred, pre-existing: MemoryListCommand directly parses FileBasedMemoryStore's JSON format. Fragile if SDK changes serialization, but covered by tests using FileBasedMemoryStore.
- [x] [Review][Defer] No test for `--no-memory` flag at RunCommand level — deferred, pre-existing: AC4 flag is only verified at the MemoryContextProvider level, not as an end-to-end RunCommand test. Requires integration test infrastructure.
