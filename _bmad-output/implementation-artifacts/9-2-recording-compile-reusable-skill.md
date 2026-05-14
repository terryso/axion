# Story 9.2: 录制编译为可复用技能

Status: done

## Story

As a 用户,
I want 将录制的操作编译为可复用的技能,
So that 下次可以直接调用技能，不需要 LLM 重新规划.

## Acceptance Criteria

1. **AC1: `axion skill compile` 基本编译**
   Given 录制文件存在 `~/.axion/recordings/open_calculator.json`
   When 运行 `axion skill compile open_calculator`
   Then 将录制编译为技能文件 `~/.axion/skills/open_calculator.json`，包含结构化的步骤序列

2. **AC2: 自动识别可参数化的值**
   Given 编译过程中发现可参数化的值
   When 分析录制内容
   Then 识别可变部分（如 URL、文件路径、搜索关键词）并标记为参数，编译后技能支持 `{{param}}` 占位符

3. **AC3: 手动指定参数**
   Given 运行 `axion skill compile open_calculator --param url --param search_term`
   When 编译完成
   Then 技能文件中指定的值被替换为参数占位符，执行时由用户提供具体值

4. **AC4: 技能文件格式**
   Given 编译后的技能文件
   When 检查格式
   Then 为标准 JSON，包含 name、description、parameters、steps（工具调用序列）字段，可人工编辑

5. **AC5: 冗余操作优化**
   Given 录制中包含冗余操作（如多余的窗口切换）
   When 编译
   Then 自动去重和优化操作序列，移除无效的中间步骤

## Tasks / Subtasks

- [x] Task 1: 创建技能数据模型 (AC: #1, #3, #4)
  - [x] 1.1 在 `Sources/AxionCore/Models/` 创建 `Skill.swift`
  - [x] 1.2 定义 `Skill` 结构体：name, description, parameters, steps, createdAt, sourceRecording
  - [x] 1.3 定义 `SkillStep` 结构体：tool (工具名), arguments (参数字典), waitFor (可选等待时间)
  - [x] 1.4 定义 `SkillParameter` 结构体：name, defaultValue (可选), description
  - [x] 1.5 所有模型遵循 Codable + Equatable + Sendable，JSON 字段使用 snake_case（CodingKeys 映射）
  - [x] 1.6 步骤中的参数值支持 `String` 类型（含 `{{param}}` 占位符语法）

- [x] Task 2: 创建 RecordingCompiler 服务 (AC: #1, #2, #3, #5)
  - [x] 2.1 在 `Sources/AxionHelper/Protocols/` 创建 `RecordingCompiling.swift` 协议（或放在 AxionCLI，因编译是纯数据转换，不需要 Helper）
  - [x] 2.2 在 `Sources/AxionCLI/Services/` 创建 `RecordingCompiler.swift`
  - [x] 2.3 实现 `compile(recording:Recording, paramNames:[String]) -> Skill` — 将 RecordedEvent 序列转换为 SkillStep 序列
  - [x] 2.4 事件类型到工具调用映射：click → click(x,y)、typeText → type_text(text)、hotkey → hotkey(keys)、appSwitch → launch_app(app_name)、scroll → scroll(dx,dy)
  - [x] 2.5 实现自动参数检测：分析 type_text 参数值，识别 URL 模式 (`http(s)://`)、文件路径模式 (`/Users/`、`~/`)、长字符串 (>20 字符) 为可参数化值
  - [x] 2.6 实现手动参数覆盖：`--param` 指定的参数名优先，在步骤参数中搜索完全匹配并替换为 `{{param}}`
  - [x] 2.7 实现冗余操作优化：合并连续相同类型的 click 事件（仅保留最后一个）、移除中间的 app_switch 后又立即切回、合并连续 type_text 为单个步骤
  - [x] 2.8 错误处理：遇到无法映射的 RecordedEvent.EventType（如 .error）时跳过并记录 warning

- [x] Task 3: 创建 `axion skill compile` CLI 命令 (AC: #1, #3)
  - [x] 3.1 在 `Sources/AxionCLI/Commands/` 创建 `SkillCommand.swift` — 命令组（类似 MemoryCommand），子命令：compile
  - [x] 3.2 创建 `SkillCompileCommand.swift` — `axion skill compile <name>`
  - [x] 3.3 参数：`name: String`（录制名称），可选 `--param`（可重复，指定参数名）
  - [x] 3.4 加载 `~/.axion/recordings/{name}.json`，反序列化为 Recording
  - [x] 3.5 调用 RecordingCompiler.compile() 生成 Skill
  - [x] 3.6 序列化为 JSON 保存到 `~/.axion/skills/{name}.json`，创建目录如不存在
  - [x] 3.7 显示编译摘要：步骤数、检测到的参数列表、优化的操作数
  - [x] 3.8 在 `AxionCLI.swift` 的 subcommands 中添加 `SkillCommand.self`
  - [x] 3.9 文件名使用 RecordCommand.sanitizeFileName() 进行路径安全处理

- [x] Task 4: 单元测试 (AC: #1-#5)
  - [x] 4.1 `Tests/AxionCoreTests/Models/SkillTests.swift` — Skill/SkillStep/SkillParameter Codable round-trip 测试
  - [x] 4.2 `Tests/AxionCLITests/Services/RecordingCompilerTests.swift` — 编译逻辑测试
  - [x] 4.3 测试事件类型映射：验证每种 RecordedEvent.EventType 正确转换为 SkillStep
  - [x] 4.4 测试自动参数检测：URL、文件路径、长字符串被识别
  - [x] 4.5 测试手动参数替换：`--param` 指定的值被正确替换为占位符
  - [x] 4.6 测试冗余优化：连续重复 click 被合并、多余 app_switch 被移除、连续 type_text 被合并
  - [x] 4.7 测试 .error 事件被跳过
  - [x] 4.8 `Tests/AxionCLITests/Commands/SkillCompileCommandTests.swift` — 参数解析和文件路径测试

## Dev Notes

### 核心架构决策

**编译是纯数据转换，不需要 Helper 进程** — RecordingCompiler 运行在 CLI 进程中，读取录制文件（JSON），输出技能文件（JSON）。无需 MCP 调用、无需 AX 权限。这与 RecordCommand（需要 Helper）不同。

**D11: 技能文件格式 — 纯 JSON + Codable**

| 方案 | 优点 | 缺点 | 决定 |
|------|------|------|------|
| 纯 JSON (Codable) | 可读、可编辑、Swift 原生支持 | 不支持复杂逻辑 | ✅ 选用 |
| YAML DSL | 更灵活、支持注释 | 额外依赖、解析复杂 | ❌ 过度设计 |
| Markdown | 人类可读性最佳 | 解析不稳定、不适合结构化数据 | ❌ 不适合 |

### 技能文件格式（标准 JSON）

```json
{
  "name": "open_calculator",
  "description": "操作录制: open_calculator (编译自录制文件)",
  "version": 1,
  "created_at": "2026-05-14T10:30:00Z",
  "source_recording": "open_calculator",
  "parameters": [
    {
      "name": "url",
      "default_value": null,
      "description": "自动检测: URL 模式"
    }
  ],
  "steps": [
    {
      "tool": "launch_app",
      "arguments": { "app_name": "Calculator" },
      "wait_after_seconds": 0.5
    },
    {
      "tool": "click",
      "arguments": { "x": "500", "y": "300" },
      "wait_after_seconds": 0
    },
    {
      "tool": "type_text",
      "arguments": { "text": "{{url}}" },
      "wait_after_seconds": 0.1
    }
  ]
}
```

**注意**：步骤的 arguments 值均为 String 类型（即使原始录制中 x/y 是数字），以支持 `{{param}}` 占位符。Skill 执行引擎（Story 9.3）负责类型转换。

### 事件类型到工具调用映射表

| RecordedEvent.EventType | SkillStep.tool | SkillStep.arguments 映射 |
|-------------------------|---------------|-------------------------|
| `.click` | `"click"` | `{ "x": "<x>", "y": "<y>" }` |
| `.typeText` | `"type_text"` | `{ "text": "<text>" }` |
| `.hotkey` | `"hotkey"` | `{ "keys": "<keys>" }` |
| `.appSwitch` | `"launch_app"` | `{ "app_name": "<app_name>" }` |
| `.scroll` | `"scroll"` | `{ "dx": "<dx>", "dy": "<dy>" }` |
| `.error` | *(跳过)* | 跳过，不生成 SkillStep |

**appSwitch 映射为 launch_app 的理由**：录制捕获的是应用切换（Cmd+Tab），但技能回放时目标应用可能未运行，用 launch_app 更健壮（launch_app 对已运行应用等同于激活）。

### 自动参数检测规则

扫描每个 SkillStep 的 arguments 值，如果匹配以下模式则标记为可参数化：

1. **URL 模式**：值匹配 `https?://.*` → 参数名 `"url"`（或 `"url_2"` 等递增）
2. **文件路径模式**：值匹配 `~/.*` 或 `/Users/.*` → 参数名 `"file_path"`（递增）
3. **长字符串**：值长度 > 20 字符 → 参数名 `"text"`（递增）
4. **手动参数优先**：`--param name` 指定时，搜索所有 arguments 值中的完全匹配并替换

### 冗余操作优化规则（按顺序应用）

1. **合并连续 type_text**：相邻的 type_text 步骤（windowContext 相同）合并为单个步骤，text 值拼接
2. **移除冗余 app_switch**：如果连续两次 app_switch 中间没有其他操作（A→B→A），移除中间的 B 切换
3. **去重连续相同 click**：连续相同坐标的 click 仅保留最后一个
4. **移除 .error 事件**：直接跳过

### 需要创建的新文件

1. `Sources/AxionCore/Models/Skill.swift` [NEW] — 技能数据模型
2. `Sources/AxionCLI/Services/RecordingCompiler.swift` [NEW] — 编译逻辑（纯数据转换，无 Helper 依赖）
3. `Sources/AxionCLI/Commands/SkillCommand.swift` [NEW] — 命令组（类似 MemoryCommand）
4. `Sources/AxionCLI/Commands/SkillCompileCommand.swift` [NEW] — compile 子命令
5. `Tests/AxionCoreTests/Models/SkillTests.swift` [NEW]
6. `Tests/AxionCLITests/Services/RecordingCompilerTests.swift` [NEW]
7. `Tests/AxionCLITests/Commands/SkillCompileCommandTests.swift` [NEW]

### 需要修改的现有文件

1. `Sources/AxionCLI/AxionCLI.swift` [UPDATE] — 添加 SkillCommand 到 subcommands

### 关键约束

- **NFR34（准确率 >= 95%）**：编译后的步骤序列在相同窗口布局下必须能正确回放。事件→工具映射不能丢失关键信息
- **NFR36（文件 < 100KB）**：技能文件只包含文本参数，不含 base64 或截图数据，单个技能通常 < 10KB
- **stdout 纯净原则**：SkillCompileCommand 的输出通过 TerminalOutput 或 print（参考 MemoryListCommand 使用 print），不直接 print 到非标准流
- **JSON 字段命名**：技能文件使用 snake_case（通过 CodingKeys 映射）
- **编译不需要 Helper 进程**：RecordingCompiler 是纯 Swift 数据转换，不需要 MCP 调用
- **文件名安全**：复用 `RecordCommand.sanitizeFileName()` 进行路径安全处理
- **`~/.axion/skills/` 目录**：技能存储目录，如不存在需创建

### 前一 Story 的关键学习（Story 9.1）

- **@Tool 宏模式**：Helper 端工具使用 `@Tool` struct + `ToolRegistrar.registerAll`
- **ToolNames 常量**：必须是 snake_case
- **测试文件镜像源结构**：`Tests/AxionCLITests/Services/`、`Tests/AxionCoreTests/Models/`
- **stdout 纯净原则**：工具返回值通过 ToolResult JSON
- **1242 测试全部通过**，零回归 — 新增代码不应破坏现有测试
- **错误处理**：统一使用 `AxionError` 枚举
- **JSONValue enum**：RecordedEvent.parameters 使用 `[String: JSONValue]`，编译时需要从 JSONValue 提取 String 值（`.string(value)` / `.int(value).description` / `.double(value).description`）
- **WindowContext 可为 nil**：部分录制事件可能没有窗口上下文
- **sanitizeFileName**：已存在于 RecordCommand，可复用（考虑是否提取到 AxionCore 共享工具）
- **HelperProcessManager**：compile 命令不需要此组件（纯本地数据转换）
- **Code review 修复了安全问题**：sanitizeFileName 防止路径遍历，编译也需要同样的保护

### 录制文件输入格式（Story 9.1 输出）

编译器读取的输入是 `Recording` 结构体的 JSON 序列化（参考 `RecordedEvent.swift`）：

```swift
struct Recording {
    let name: String
    let createdAt: Date
    let durationSeconds: TimeInterval
    let events: [RecordedEvent]
    let windowSnapshots: [WindowSnapshot]
}
```

```swift
struct RecordedEvent {
    let type: EventType  // .click, .typeText, .hotkey, .appSwitch, .scroll, .error
    let timestamp: TimeInterval
    let parameters: [String: JSONValue]  // 灵活的参数字典
    let windowContext: WindowContext?
}
```

### 命令组模式（参考 MemoryCommand）

```
axion skill compile <name> [--param name ...]   # 本 Story 实现
axion skill run <name> [--param key=value ...]  # Story 9.3
axion skill list                                 # Story 9.3
axion skill delete <name>                        # Story 9.3
```

`SkillCommand` 作为命令组，subcommands 包含 `SkillCompileCommand`。Story 9.3 会添加 `run`、`list`、`delete` 子命令。

### Project Structure Notes

- 编译逻辑放在 `Sources/AxionCLI/Services/RecordingCompiler.swift`（不是 AxionHelper），因为是纯数据转换
- 技能模型放在 `Sources/AxionCore/Models/Skill.swift`，因为 Story 9.3 的 Skill run 执行也需要这些模型
- 测试文件遵循镜像源结构
- 命令遵循 MemoryCommand 的子命令模式

### References

- Story 9.1 录制文件格式: `Sources/AxionCore/Models/RecordedEvent.swift`
- Story 9.1 CLI 命令模式: `Sources/AxionCLI/Commands/RecordCommand.swift`
- 命令组模式: `Sources/AxionCLI/Commands/MemoryCommand.swift`
- 文件名安全: `RecordCommand.sanitizeFileName()`
- ToolNames 常量: `Sources/AxionCore/Constants/ToolNames.swift`
- CLI 入口: `Sources/AxionCLI/AxionCLI.swift`
- SafetyChecker: `Sources/AxionCLI/Executor/SafetyChecker.swift`
- NFR34/NFR36: `_bmad-output/planning-artifacts/epics.md`
- D11 技能文件格式: `_bmad-output/planning-artifacts/epics.md` (D11 表格)
- Project Context: `_bmad-output/project-context.md`

## Dev Agent Record

### Agent Model Used
GLM-5.1

### Debug Log References
N/A

### Completion Notes List
- ✅ Task 1: Created Skill data models (Skill, SkillStep, SkillParameter) in AxionCore with Codable + snake_case CodingKeys. SkillParameter encodes nil defaultValue as JSON null explicitly.
- ✅ Task 2: Implemented RecordingCompiler with event-to-step mapping (5 event types), auto parameter detection (URL/path/long text), manual --param override, and redundancy optimization (merge type_text, remove A→B→A app_switch, deduplicate clicks).
- ✅ Task 3: Created SkillCommand (command group) + SkillCompileCommand (compile subcommand). Uses RecordCommand.sanitizeFileName for path safety. Outputs compilation summary to stdout.
- ✅ Task 4: 36 unit tests across 3 test files — all passing, 76 total tests pass with zero regressions.

### Change Log
- 2026-05-14: Story 9.2 implementation complete. Added Skill models, RecordingCompiler service, skill compile CLI command, and 36 unit tests.
- 2026-05-14: Senior Developer Review (AI). Fixed 5 issues: (H1) remove force-unwrap in mergeConsecutiveTypeText, (H2) guard nil in removeRedundantAppSwitch, (M1) added E2E test to File List, (M2) auto-detect generates unique names on collision instead of silently skipping, (M3) deterministic manual param assignment via sorted keys. All 95 tests pass.

### File List
- `Sources/AxionCore/Models/Skill.swift` [NEW] — Skill, SkillStep, SkillParameter data models
- `Sources/AxionCLI/Services/RecordingCompiler.swift` [NEW] — Recording-to-Skill compilation logic
- `Sources/AxionCLI/Commands/SkillCommand.swift` [NEW] — `axion skill` command group
- `Sources/AxionCLI/Commands/SkillCompileCommand.swift` [NEW] — `axion skill compile <name>` subcommand
- `Sources/AxionCLI/AxionCLI.swift` [MODIFIED] — Added SkillCommand to subcommands
- `Tests/AxionCoreTests/Models/SkillTests.swift` [NEW] — Skill model Codable round-trip tests
- `Tests/AxionCLITests/Services/RecordingCompilerTests.swift` [NEW] — Compiler logic tests (21 tests)
- `Tests/AxionCLITests/Commands/SkillCompileCommandTests.swift` [NEW] — Command path and sanitize tests (6 tests)
- `Tests/AxionCLITests/Commands/SkillCompileE2ETests.swift` [NEW] — End-to-end pipeline tests (13 tests)
