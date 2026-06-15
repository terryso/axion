---
stepsCompleted: ['step-01-preflight-and-context', 'step-04-generate-tests', 'step-05-validate-and-complete']
lastStep: 'step-05-validate-and-complete'
lastSaved: '2026-06-15'
storyId: '40.2'
storyKey: '40-2-shared-tool-profile-helper-with-behavior-parity'
storyFile: '_bmad-output/implementation-artifacts/40-2-shared-tool-profile-helper-with-behavior-parity.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-40-2-shared-tool-profile-helper-with-behavior-parity.md'
generatedTestFiles:
  - 'Tests/AxionCLITests/Services/AgentBuilderToolProfileTests.swift'
inputDocuments:
  - '_bmad-output/implementation-artifacts/40-2-shared-tool-profile-helper-with-behavior-parity.md'
  - '_bmad-output/project-context.md'
  - 'CLAUDE.md'
  - 'Sources/AxionCLI/Services/AgentBuilder.swift'
  - 'Sources/AxionCLI/Tools/StorageScanTool.swift'
  - 'Sources/AxionCLI/Tools/ProposeStoragePlanTool.swift'
  - 'Sources/AxionCLI/Tools/ExecuteStoragePlanTool.swift'
  - 'Sources/AxionCLI/Tools/UndoStorageOpTool.swift'
  - 'Sources/AxionCLI/Tools/ScanAppUninstallTool.swift'
  - 'Sources/AxionCLI/Tools/ExecuteAppUninstallTool.swift'
  - 'Sources/AxionCLI/Memory/MemoryTool.swift'
  - 'Sources/AxionCLI/Config/AxionConfig.swift'
  - '/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/ToolRegistry.swift'
  - '/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/Advanced/SkillTool.swift'
  - '/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/Advanced/SaveSkillTool.swift'
  - '/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Stores/SkillUsageStore.swift'
  - '/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/SkillRegistry.swift'
framework: 'Swift Testing (import Testing / @Suite / @Test / #expect)'
tddPhase: 'RED'
executionMode: 'yolo (非交互 Create)'
---

# ATDD Checklist — Story 40.2 Shared Tool Profile Helper With Behavior Parity

## 1. 测试套件概览

- **测试文件**：`Tests/AxionCLITests/Services/AgentBuilderToolProfileTests.swift`
- **框架**：Swift Testing（`@Suite("AgentBuilder.buildToolProfile (Story 40.2)")`）
- **testTarget**：`AxionCLITests`（被默认单元测试命令 `--filter "AxionCLITests"` 命中）
- **TDD 阶段**：RED（被测对象 `AgentBuilder.buildToolProfile(...)` 尚不存在 → 整文件编译失败）
- **依赖**：`AxionCLITests` 已直接依赖 `OpenAgentSDK` product（`Package.swift`），`import OpenAgentSDK`
  合法；`@testable import AxionCLI` 访问内部 Storage/Memory 工具类型

## 2. AC 覆盖映射

| AC | 描述 | 覆盖方式 | @Test | 当前 red/green |
|----|------|----------|-------|----------------|
| AC1 | 提取 shared tool profile helper，非 dry-run / dry-run 行为 parity | 单测（直接调纯函数 helper） | `test_buildToolProfile_nonDryrun_includesSkillMemoryStorageAndSaveSkill`、`test_buildToolProfile_nonDryrun_includesCoreAndSpecialistBaseTools`、`test_buildToolProfile_dryrun_excludesBashAndSkill` | RED |
| AC2 | helper 返回 `[ToolProtocol]`，`.name` 可读，纯函数无副作用 | 单测（读返回值 `.name`） | `test_buildToolProfile_returnsToolProtocolsWithNameAccessible` | RED |
| AC3 | `build()` / `buildSkillAgent()` 可见行为不变 | **既有回归**（不新增 @Test） | — | 由 Step 4「运行默认单元测试」的既有 `AxionCLITests` 套件零回归验证；本 story 显式不碰 `buildSkillAgent()` |
| AC4 | dry-run 工具过滤不回退（排 Bash/Skill/Memory/Storage/save_skill） | 单测（dry-run 入参断言排除集） | `test_buildToolProfile_dryrun_excludesBashAndSkill`、`test_buildToolProfile_dryrun_excludesSideEffectTools` | RED |
| AC5 | 新增单元测试覆盖非 dry-run 与 dry-run 工具名 parity | 单测（本文件全部 @Test） | 全部 7 个 @Test | RED |

## 3. @Test 清单（共 7 个）

1. `test_buildToolProfile_nonDryrun_includesSkillMemoryStorageAndSaveSkill` — AC1/AC5
   （非 dry-run 含 Skill / Memory / 6 个 Storage 工具 / save_skill[usageStore 非 nil]）
2. `test_buildToolProfile_nonDryrun_excludesToolSearchAndAskUser` — AC1/AC5
   （非 dry-run 排除 `AgentBuilder.excludedToolNames`）
3. `test_buildToolProfile_nonDryrun_includesCoreAndSpecialistBaseTools` — AC1/AC5
   （非 dry-run 含 `getAllBaseTools(tier: .core) + .specialist` 过滤 `excludedToolNames` 后全集）
4. `test_buildToolProfile_dryrun_excludesBashAndSkill` — AC4/AC5
   （dry-run 排除 `["Bash", "Skill"]`）
5. `test_buildToolProfile_dryrun_excludesSideEffectTools` — AC4/AC5
   （dry-run 排除 Memory / 6 个 Storage 工具 / save_skill）
6. `test_buildToolProfile_noSkillsTrue_omitsSkillToolOnly` — AC1
   （`noSkills: true` 仅省略 Skill 工具，Memory/Storage 保留）
7. `test_buildToolProfile_returnsToolProtocolsWithNameAccessible` — AC2
   （返回值为 `[ToolProtocol]`，每个 `.name` 非空可读、唯一）

## 4. Given / When / Then（按 AC）

### AC1 — 提取 shared tool profile helper，行为 parity
- **Given** 当前 `AgentBuilder.build()` 第 140–189 行（base tools 过滤 + Skill + Memory + Storage）
  与第 206–212 行（save_skill）内联组装 `agentTools`
- **When** 提取为 `AgentBuilder.buildToolProfile(noSkills:noMemory:dryrun:skillRegistry:memoryDir:config:usageStore:skillsDir:)`
  并由 `build()` 调用
- **Then** 非dry-run 路径工具名集合含 Skill/Memory/Storage 6 工具/save_skill；
  dry-run 路径排除 Bash/Skill/Memory/Storage/save_skill（断言点见 @Test 1/3/4/5/6）

### AC2 — helper 返回可测试的工具名检查输出
- **Given** 新提取的纯函数 helper
- **When** 在测试中直接调用（传已构造的 `skillRegistry`/`config`/`usageStore`，不内部 resolve）
- **Then** 返回 `[ToolProtocol]`，调用方可读 `.name` 做工具名断言（@Test 7）

### AC3 — `build()` 与 `buildSkillAgent()` 可见行为不变
- **Given** helper 提取完成
- **When** 运行既有 `AxionCLITests` 单元测试套件
- **Then** 零回归（既有测试全绿）；`buildSkillAgent()` 本 story 不触碰（由 Step 4 运行默认命令验证）

### AC4 — dry-run 工具过滤不回退
- **Given** `dryrun == true`
- **When** helper 构建工具池
- **Then** 不出现 Bash/Skill/Memory/Storage（含 execute/undo 副作用）/save_skill（@Test 4/5）

### AC5 — 新增单元测试覆盖非 dry-run 与 dry-run 工具名 parity
- **Given** helper 已提取
- **When** 新增 Swift Testing 测试（本文件）
- **Then** 覆盖非 dry-run + dry-run 工具名 parity，断言 dry-run 不含 Bash/Skill/Memory/Storage（全部 @Test）

## 5. Red-to-Green Gate 行为

**当前 RED 状态（HEAD = `d1e34e1`，helper 未实现）**：
`Tests/AxionCLITests/Services/AgentBuilderToolProfileTests.swift` **编译失败**。

实测编译错误（`swift build --target AxionCLITests`，全文件唯一错误源）：

```
error: type 'AgentBuilder' has no member 'buildToolProfile'
```

- 7 处 `AgentBuilder.buildToolProfile(...)` 调用全部报 `no member 'buildToolProfile'`
- 衍生错误（级联，非独立缺陷）：`'nil' requires a contextual type`（无法推断 helper 返回类型导致
  `usageStore:` 参数标签的 nil 无上下文）、`cannot infer key path type from context`（无法
  推断返回 `[ToolProtocol]` 导致 `.map(\.name)` key path 无根类型）
- `grep -oE "/[^ ]+\.swift"` 确认：**仅** `AgentBuilderToolProfileTests.swift` 报错，其余
  `AxionCLITests` 文件与 `AxionCLI` 主体零编译错误
- 这是预期的确定性 RED gate：所有错误在 dev 实现 `buildToolProfile(...)` 后一并消失

**GREEN 条件**（Step 3 dev-story 实现后）：
1. `AgentBuilder.swift` 新增 `static func buildToolProfile(noSkills:noMemory:dryrun:skillRegistry:memoryDir:config:usageStore:skillsDir:) -> [ToolProtocol]`
2. `build()` 第 140–189 / 206–212 行平移到 helper，`build()` 改调用 helper
3. `swift build --target AxionCLITests` 编译通过（无 `no member 'buildToolProfile'`）
4. `swift test --filter "AxionCLITests"` 运行通过：7 个 @Test 全绿

## 6. 关键决策与降级处理

### 6.1 直接调纯函数 helper，不调真实 `build()`（CLAUDE.md 强制）
AC2 的核心价值是 helper 成为**可单测的纯函数**。本测试**不调用** `AgentBuilder.build()`
（那会 `resolveApiKey` + `HelperPathResolver` + 真实 MCP resolve），而是直接调用 helper。
helper 入参全部由测试构造：`AxionConfig(apiKey: "sk-test")`、空 `SkillRegistry()`、
`SkillUsageStore(skillsDir: <temp>)`、临时 `memoryDir`/`skillsDir`。

### 6.2 工具名不硬编码（CLAUDE.md 反模式 #10）
期望工具名一律从真实工具实例 `.name` 读取，避免「bogus test」（测试纯字面量）：
- `MemoryTool(store: UniversalMemoryStore(memoryDir:)).name` → 读真实 `MemoryTool` 名
- `StorageScanTool(scanner:..., config:).name` 等 6 个 Storage 工具 → 读真实实例名
- `createSkillTool(registry:).name` → 读 SDK 工厂产物名（`"Skill"`）
- `createSaveSkillTool(skillRegistry:usageStore:skillsDir:).name` → 读真实名（`"save_skill"`）
- `AgentBuilder.excludedToolNames`（既有静态常量）→ 引用真实排除集，不重复字面量
- dry-run 排除集 `["Bash", "Skill"]`：唯一例外，沿用 `build()` 第 140 行字面量（无对应公开常量可引用），注释标明来源

### 6.3 `save_skill` 名读取的特殊处理
SDK `createSaveSkillTool` 的 `usageStore` 入参为**非可选** `SkillUsageStore`（`SaveSkillTool.swift:27`），
而 `save_skill` 工具只在 `usageStore != nil` 时注册。故：
- 非dry-run + usageStore 非 nil 的 @Test（1/6）：用真实 `createSaveSkillTool(...).name` 读取
- dry-run + usageStore == nil 的 @Test（5）：无法构造 `createSaveSkillTool`（需非可选 store），
  改用字面量 `"save_skill"` 断言（注释标明：这是唯一无法从真实实例读取的场景）

### 6.4 `SkillUsageStore` 构造的副作用隔离
`SkillUsageStore(skillsDir:)` 在 init 调用 `loadSync` 读 `{skillsDir}/.usage.json`（非纯构造）。
测试用临时目录（`NSTemporaryDirectory()`）隔离，目录不存在文件时 `loadSync` 返回空、不崩溃、
不触碰真实 `~/.axion/`。符合 CLAUDE.md「AxionBar 测试用临时目录」反模式 #12 的精神。

### 6.5 AC3 由既有回归覆盖，不新增 @Test
AC3（`build()`/`buildSkillAgent()` 可见行为不变）的验证方式是「既有 `AxionCLITests` 套件零回归」。
本 story 不为 AC3 新增 @Test —— 因为「不变」的最佳证据是既有测试不受影响，新增断言式测试反而
可能掩盖回归。Step 4（运行默认单元测试命令）负责执行该回归验证。

### 6.6 `buildSkillAgent()` 显式不覆盖
Story 红线明确：`buildSkillAgent()` 的工具池 parity 由 Story 40.4/40.5 单独处理，本 story 不触碰。
故本文件无任何针对 `buildSkillAgent` 的断言（scope creep 防护）。

## 7. 约束遵循确认

- [x] 仅 Swift Testing（`import Testing` / `@Suite` / `@Test` / `#expect`），无 `import XCTest`
- [x] 不调真实 `AgentBuilder.build()`（只调纯函数 helper）
- [x] 不连 MCP、不起 Helper、不发真实 API key、不调真实 `executeSkillStream`
- [x] 工具名不硬编码：从真实工具实例 `.name` / `AgentBuilder.excludedToolNames` 读取
      （唯一例外 `["Bash","Skill"]` dry-run 排除集，注释标明来源）
- [x] 测试文件位于 `Tests/AxionCLITests/Services/`，被默认单元测试命令 `--filter "AxionCLITests"` 命中
- [x] 命名遵循 `test_被测单元_场景_预期结果`
- [x] 不运行 `Tests/**/Integration/`、`Tests/**/AxionE2ETests/`
- [x] 红线遵守：不注册 Agent/Task（40.3）、不改 `excludedToolNames`（40.5）、不碰 `buildSkillAgent`（40.4/40.5）

## 8. 阻塞点 / 风险

- 无阻塞点。RED 状态是预期的确定性 gate（`buildToolProfile` 未实现）。
- 风险（低）：dev 实现 helper 时若签名与测试入参标签不一致（如 `noSkills:` 改名、参数顺序调整），
  测试需同步调整参数标签 —— 这是 dev 的职责，不影响 RED gate 的确定性。
- 风险（低）：dev 若选择返回 `ToolProfile` 结构体而非裸 `[ToolProtocol]`，测试需改为
  `.tools` 属性访问 —— story Task 1.5 明确允许 dev 选择，dev 实现时据实调整测试（GREEN 阶段动作）。
- 风险（信息性）：`save_skill` 在 dry-run 是否注册取决于 `buildReviewInfrastructure` 在 dry-run
  是否返回非 nil `usageStore`。本测试 dry-run 入参传 `usageStore: nil`，与「review infra 在 dry-run
  返回 nil」假设一致；若 dev 发现既有行为是 dry-run 也返回非 nil usageStore，应据实调整测试入参（parity 第一）。

## 9. 下游交接

- **storyKey**：`40-2-shared-tool-profile-helper-with-behavior-parity`
- **storyFile**：`_bmad-output/implementation-artifacts/40-2-shared-tool-profile-helper-with-behavior-parity.md`
- **generatedTestFiles**：`Tests/AxionCLITests/Services/AgentBuilderToolProfileTests.swift`
- **下一步推荐 workflow**：`dev-story`（实现 helper → RED 转 GREEN）→ `code-review` → `trace`
