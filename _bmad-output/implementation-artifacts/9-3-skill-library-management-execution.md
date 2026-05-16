# Story 9.3: 技能库管理与执行

Status: done

## Story

As a 用户,
I want 管理和执行已保存的技能,
So that 常用操作可以一键执行，无需每次描述任务.

## Acceptance Criteria

1. **AC1: `axion skill run` 基本执行**
   Given 技能文件存在 `~/.axion/skills/open_calculator.json`
   When 运行 `axion skill run open_calculator`
   Then 直接回放技能中的步骤序列，不调用 LLM，通过 MCP 调用 Helper 执行

2. **AC2: 参数化执行**
   Given 技能包含参数 `{{url}}`
   When 运行 `axion skill run open_calculator --param url=https://example.com`
   Then 将参数值注入步骤序列后执行

3. **AC3: `axion skill list` 技能列表**
   Given 运行 `axion skill list`
   When 查看技能库
   Then 显示所有已保存的技能：名称、描述、参数列表、上次使用时间、执行次数

4. **AC4: `axion skill delete` 删除技能**
   Given 运行 `axion skill delete open_calculator`
   When 删除技能
   Then 移除技能文件，`axion skill list` 不再显示该技能

5. **AC5: 执行失败重试**
   Given 技能执行中某步骤失败
   When 回放失败
   Then 记录失败位置，尝试重试一次（元素坐标可能因窗口位置变化而失效），仍失败则报告错误并建议用 `axion run` 代替

6. **AC6: 执行成功摘要**
   Given 技能执行成功
   When 回放完成
   Then 显示 "技能完成。N 步，耗时 X 秒。" 以及技能名称，响应时间显著短于 LLM 规划模式

## Tasks / Subtasks

- [x] Task 1: 扩展 Skill 模型支持执行元数据 (AC: #3, #6)
  - [x] 1.1 在 `Sources/AxionCore/Models/Skill.swift` 扩展 `Skill` 添加可选字段：`lastUsedAt: Date?`、`executionCount: Int`（默认 0）
  - [x] 1.2 使用 `decodeIfPresent` + 默认值模式（参考 project-context.md 部分解码规范），保证旧技能文件向后兼容
  - [x] 1.3 更新 `Tests/AxionCoreTests/Models/SkillTests.swift` 添加新字段 round-trip 测试和向后兼容测试

- [x] Task 2: 创建 SkillExecutor 服务 (AC: #1, #2, #5, #6)
  - [x] 2.1 在 `Sources/AxionCLI/Services/` 创建 `SkillExecutor.swift`
  - [x] 2.2 定义 `SkillExecutor` struct，依赖 `MCPClientProtocol`（与 StepExecutor 相同的协议）
  - [x] 2.3 实现 `execute(skill:paramValues:) async throws -> SkillExecutionResult`
  - [x] 2.4 步骤参数解析：将 `{{param}}` 占位符替换为用户提供的 `--param key=value` 值，未提供的参数使用 `defaultValue`
  - [x] 2.5 步骤类型转换：`SkillStep.arguments` 的 `[String: String]` 转换为 MCP `callTool` 所需的 `[String: Value]`（字符串值转 `.string()`，尝试 Int 解析转 `.int()`）
  - [x] 2.6 步骤间等待：如果 `waitAfterSeconds > 0`，执行 `Task.sleep` 后继续
  - [x] 2.7 失败重试：单步失败时重试一次（捕获 `AxionError.mcpError`），仍失败则终止并报告失败步骤索引
  - [x] 2.8 返回 `SkillExecutionResult`：`success: Bool`、`stepsExecuted: Int`、`failedStepIndex: Int?`、`durationSeconds: TimeInterval`、`errorMessage: String?`
  - [x] 2.9 不调用 SafetyChecker（技能执行等同于 `--allow-foreground` 模式，用户显式触发）

- [x] Task 3: 创建 `axion skill run` CLI 命令 (AC: #1, #2, #6)
  - [x] 3.1 在 `Sources/AxionCLI/Commands/` 创建 `SkillRunCommand.swift`
  - [x] 3.2 参数：`name: String`，可选 `--param`（可重复，格式 `key=value`）
  - [x] 3.3 使用 `RecordCommand.sanitizeFileName()` 进行路径安全处理
  - [x] 3.4 加载 `~/.axion/skills/{name}.json`，反序列化为 `Skill`
  - [x] 3.5 验证所有必需参数已提供（无 defaultValue 的参数必须在 `--param` 中指定）
  - [x] 3.6 启动 HelperProcessManager → 创建 MCPClientProtocol 适配器 → 调用 SkillExecutor.execute()
  - [x] 3.7 执行完成后更新技能文件的 `lastUsedAt` 和 `executionCount`
  - [x] 3.8 显示执行摘要："技能完成。N 步，耗时 X 秒。" 或 "步骤 N 失败: {reason}。建议使用 axion run 代替。"
  - [x] 3.9 注册 SIGINT handler 传播到 Helper（参考 RecordCommand 的 withTaskCancellationHandler 模式）
  - [x] 3.10 添加 `--allow-foreground` 标志（与 RunCommand 一致），默认为 true

- [x] Task 4: 创建 `axion skill list` CLI 命令 (AC: #3)
  - [x] 4.1 在 `Sources/AxionCLI/Commands/` 创建 `SkillListCommand.swift`
  - [x] 4.2 扫描 `~/.axion/skills/` 目录下所有 `.json` 文件
  - [x] 4.3 逐个反序列化为 `Skill`，收集名称、描述、参数、lastUsedAt、executionCount
  - [x] 4.4 格式化输出到 stdout（参考 MemoryListCommand 的表格/列表模式）
  - [x] 4.5 空技能库时显示 "无已保存的技能。使用 axion skill compile <name> 创建技能。"

- [x] Task 5: 创建 `axion skill delete` CLI 命令 (AC: #4)
  - [x] 5.1 在 `Sources/AxionCLI/Commands/` 创建 `SkillDeleteCommand.swift`
  - [x] 5.2 参数：`name: String`
  - [x] 5.3 使用 `RecordCommand.sanitizeFileName()` 进行路径安全处理
  - [x] 5.4 删除 `~/.axion/skills/{name}.json`，文件不存在时报错
  - [x] 5.5 显示确认消息："技能 '{name}' 已删除。"

- [x] Task 6: 更新 SkillCommand 命令组 (AC: #1-#6)
  - [x] 6.1 在 `SkillCommand.swift` 的 subcommands 中添加 `SkillRunCommand.self`、`SkillListCommand.self`、`SkillDeleteCommand.self`

- [x] Task 7: 单元测试 (AC: #1-#6)
  - [x] 7.1 `Tests/AxionCLITests/Services/SkillExecutorTests.swift` — 核心执行逻辑测试
  - [x] 7.2 测试参数替换：`{{url}}` 被正确替换为用户提供的值
  - [x] 7.3 测试参数默认值：未提供参数时使用 `SkillParameter.defaultValue`
  - [x] 7.4 测试必需参数缺失：抛出正确错误
  - [x] 7.5 测试 String→Value 类型转换：纯数字字符串转为 `.int()`，其他为 `.string()`
  - [x] 7.6 测试 waitAfterSeconds：验证 sleep 调用（通过 Mock MCPClient 检查调用间隔）
  - [x] 7.7 测试失败重试：第一步失败后重试一次成功 → 整体成功
  - [x] 7.8 测试重试仍失败：两次失败 → 返回失败结果，包含 failedStepIndex
  - [x] 7.9 `Tests/AxionCLITests/Commands/SkillRunCommandTests.swift` — 参数解析和路径测试
  - [x] 7.10 `Tests/AxionCLITests/Commands/SkillListCommandTests.swift` — 列表逻辑测试（空目录、多个技能文件）
  - [x] 7.11 `Tests/AxionCLITests/Commands/SkillDeleteCommandTests.swift` — 删除逻辑测试

## Dev Notes

### 核心架构决策

**技能执行需要 Helper 进程（与 compile 不同）** — `axion skill run` 需要通过 MCP 调用 Helper 执行实际的桌面操作（click、type_text 等）。这与 `axion skill compile`（纯数据转换，不需要 Helper）不同。

**SkillExecutor 不走 StepExecutor 的 PlaceholderResolver/SafetyChecker 管线** — 技能步骤是确定性的工具调用序列（无 `$pid`/`$window_id` 占位符），不需要 PlaceholderResolver。SafetyChecker 也不适用（用户显式触发技能，等同于 `--allow-foreground`）。

**SkillStep.arguments 是 `[String: String]`，MCP 需要 `[String: Value]`** — 执行时需要类型转换：尝试 Int 解析的字符串（如 `"500"`）转为 `.int(500)`，其他转为 `.string()`。这与 StepExecutor 不同（Plan.steps 使用 `Value` 枚举，有明确类型信息）。

### SkillExecutionResult 模型

```swift
struct SkillExecutionResult {
    let success: Bool
    let stepsExecuted: Int
    let failedStepIndex: Int?
    let durationSeconds: TimeInterval
    let errorMessage: String?
}
```

### 参数注入逻辑

```swift
// 1. 解析 --param key=value 为 [String: String]
// 2. 对每个 SkillStep.arguments 中的值：
//    - 如果包含 "{{param}}"，替换为 paramValues[param] ?? parameter.defaultValue ?? throw error
//    - 如果不包含 "{{...}}"，保持原值
// 3. 替换后的 arguments 传入 MCP callTool
```

### MCPClientProtocol 适配

`SkillExecutor` 接收 `MCPClientProtocol`（AxionCore 中定义的协议），与 StepExecutor 使用相同的协议。`HelperProcessManager` 的 `callTool` 方法签名是 `callTool(name:arguments:) -> String`，需要创建一个轻量适配器将 `HelperProcessManager` 包装为 `MCPClientProtocol`：

```swift
// HelperProcessManager 的 callTool 接受 [String: AxionCore.Value]
// MCPClientProtocol 的 callTool 也接受 [String: AxionCore.Value]
// 但 HelperProcessManager 是 actor，需要 await
// SkillRunCommand 中可以创建匿名 struct 实现 MCPClientProtocol
```

**注意**：`HelperProcessManager` 是 actor，其 `callTool` 方法已经是 `async throws -> String`。但 `MCPClientProtocol` 也定义了 `callTool(name:arguments:) async throws -> String`，参数类型一致。不过 `HelperProcessManager` 的 `callTool` 参数类型是 `[String: AxionCore.Value]`，与 `MCPClientProtocol` 一致。可以直接在 `SkillRunCommand` 中创建适配器：

```swift
struct HelperMCPClientAdapter: MCPClientProtocol {
    let manager: HelperProcessManager
    func callTool(name: String, arguments: [String: Value]) async throws -> String {
        try await manager.callTool(name: name, arguments: arguments)
    }
    func listTools() async throws -> [String] {
        try await manager.listTools()
    }
}
```

### 执行流程（SkillRunCommand）

```
1. 解析 CLI 参数
2. sanitizeFileName(name)
3. 加载 ~/.axion/skills/{name}.json → Skill
4. 验证必需参数已提供
5. HelperProcessManager().start()
6. HelperMCPClientAdapter(manager) → MCPClientProtocol
7. SkillExecutor(client).execute(skill:paramValues:)
8. 更新技能文件 (lastUsedAt, executionCount)
9. HelperProcessManager.stop()
10. 显示执行摘要
```

### 失败重试逻辑（AC5）

```swift
for (index, step) in skill.steps.enumerated() {
    do {
        let resolvedArgs = resolveParams(step.arguments, paramValues: paramValues, parameters: skill.parameters)
        let mcpArgs = toStringValueDict(resolvedArgs)
        _ = try await client.callTool(name: step.tool, arguments: mcpArgs)
    } catch {
        // Retry once
        do {
            _ = try await client.callTool(name: step.tool, arguments: mcpArgs)
        } catch {
            return SkillExecutionResult(success: false, stepsExecuted: index, failedStepIndex: index, ...)
        }
    }
    if step.waitAfterSeconds > 0 {
        try await Task.sleep(nanoseconds: UInt64(step.waitAfterSeconds * 1_000_000_000))
    }
}
```

### 技能执行元数据更新

执行成功后，更新技能文件的 `lastUsedAt`（当前时间）和 `executionCount`（+1）。重新序列化并覆盖写入文件。需要修改 `Skill` struct 为 `var` 属性（当前为 `let`）。

**关键决策**：`Skill` 的 `lastUsedAt` 和 `executionCount` 字段仅在执行时更新，编译时不设置。使用 `decodeIfPresent + ?? default` 模式确保旧文件兼容。

### Skill list 输出格式

```
已保存的技能:
  open_calculator
    描述: 操作录制: open_calculator (编译自录制文件)
    参数: url (默认值: 无), search_term (默认值: 无)
    执行次数: 5, 上次使用: 2026-05-14 10:30
```

### 需要创建的新文件

1. `Sources/AxionCLI/Services/SkillExecutor.swift` [NEW] — 技能执行引擎
2. `Sources/AxionCLI/Commands/SkillRunCommand.swift` [NEW] — run 子命令
3. `Sources/AxionCLI/Commands/SkillListCommand.swift` [NEW] — list 子命令
4. `Sources/AxionCLI/Commands/SkillDeleteCommand.swift` [NEW] — delete 子命令
5. `Tests/AxionCLITests/Services/SkillExecutorTests.swift` [NEW]
6. `Tests/AxionCLITests/Commands/SkillRunCommandTests.swift` [NEW]
7. `Tests/AxionCLITests/Commands/SkillListCommandTests.swift` [NEW]
8. `Tests/AxionCLITests/Commands/SkillDeleteCommandTests.swift` [NEW]

### 需要修改的现有文件

1. `Sources/AxionCore/Models/Skill.swift` [UPDATE] — 添加 `lastUsedAt`、`executionCount` 字段，将相关属性改为 `var`
2. `Sources/AxionCLI/Commands/SkillCommand.swift` [UPDATE] — 添加三个子命令到 subcommands
3. `Tests/AxionCoreTests/Models/SkillTests.swift` [UPDATE] — 新字段测试

### 关键约束

- **NFR31（首步延迟 < 100ms）**：技能执行不涉及 LLM，从调用 `skill run` 到第一个 MCP 工具调用的延迟必须 < 100ms。HelperProcessManager.start() 是主要耗时（需要启动 Helper 进程），但 Helper 可能已在运行
- **NFR34（准确率 >= 95%）**：编译后的步骤序列在相同窗口布局下必须能正确回放。SkillExecutor 需要忠实地将 SkillStep 映射到 MCP 调用
- **stdout 纯净原则**：命令输出使用 `TerminalOutput` 或 `print`
- **JSON 字段命名**：snake_case（CodingKeys 映射）
- **文件名安全**：复用 `RecordCommand.sanitizeFileName()`
- **不引入新的错误类型**：统一使用 `AxionError`
- **SkillStep.arguments 值均为 String**：执行时负责类型转换为 Value

### 前一 Story 的关键学习（Story 9.2）

- **@Tool 宏模式**：Helper 端工具使用 `@Tool` struct + `ToolRegistrar.registerAll`
- **ToolNames 常量**：必须是 snake_case
- **测试文件镜像源结构**：`Tests/AxionCLITests/Services/`、`Tests/AxionCoreTests/Models/`
- **stdout 纯净原则**：SkillCompileCommand 使用 `print` 输出摘要
- **95 个测试全部通过**，零回归 — 新增代码不应破坏现有测试
- **错误处理**：统一使用 `AxionError` 枚举
- **sanitizeFileName**：已存在于 RecordCommand，可复用
- **SkillCompileCommand.skillsDirectory()**：已定义 `~/.axion/skills` 路径，考虑提取到 AxionCore 共享常量，或在 SkillExecutor 中复用
- **Skill 模型 JSON 格式**：snake_case CodingKeys，encoder 使用 `[.sortedKeys, .prettyPrinted]`
- **HelperProcessManager 是 actor**：所有方法需要 `await` 调用
- **MCPClientProtocol**：定义在 AxionCore，方法签名 `callTool(name:arguments:) async throws -> String`，参数类型 `[String: Value]`

### HelperProcessManager 使用模式（参考 RecordCommand）

```swift
// RecordCommand 的 Helper 使用模式：
let helperManager = HelperProcessManager()
try await helperManager.start()
// ... 使用 helperManager.callTool(name:arguments:) ...
await helperManager.stop()

// SkillRunCommand 应该使用相同模式
// 但需要 MCPClientProtocol 适配器给 SkillExecutor
```

### Project Structure Notes

- SkillExecutor 放在 `Sources/AxionCLI/Services/`（与 RecordingCompiler 同级）
- Skill 模型扩展在 `Sources/AxionCore/Models/Skill.swift`
- 命令文件在 `Sources/AxionCLI/Commands/`
- 测试文件遵循镜像源结构
- SkillExecutor 依赖 `MCPClientProtocol`（AxionCore 协议），通过构造注入

### References

- Story 9.2 技能文件格式: `Sources/AxionCore/Models/Skill.swift`
- Story 9.2 编译逻辑: `Sources/AxionCLI/Services/RecordingCompiler.swift`
- Helper MCP 通信: `Sources/AxionCLI/Helper/HelperProcessManager.swift`
- StepExecutor 执行模式: `Sources/AxionCLI/Executor/StepExecutor.swift`
- MCPClientProtocol: `Sources/AxionCore/Protocols/MCPClientProtocol.swift`
- Value 类型: `Sources/AxionCore/Models/Step.swift` (Value enum)
- SafetyChecker: `Sources/AxionCLI/Executor/SafetyChecker.swift`
- RecordCommand 模式: `Sources/AxionCLI/Commands/RecordCommand.swift`
- SkillCommand 命令组: `Sources/AxionCLI/Commands/SkillCommand.swift`
- MemoryListCommand 模式: `Sources/AxionCLI/Commands/MemoryCommand.swift`
- AxionError: `Sources/AxionCore/Errors/AxionError.swift`
- ToolNames 常量: `Sources/AxionCore/Constants/ToolNames.swift`
- CLI 入口: `Sources/AxionCLI/AxionCLI.swift`
- NFR31/NFR34/NFR36: `_bmad-output/planning-artifacts/epics.md`
- FR55/FR56: `_bmad-output/planning-artifacts/epics.md`
- Project Context: `_bmad-output/project-context.md`

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- 13/13 Skill model tests pass (including 5 new execution metadata tests)
- 14/14 SkillExecutor tests pass (parameter replacement, type conversion, retry, multi-step)
- 4/4 SkillRunCommand tests pass
- 5/5 SkillListCommand tests pass (empty dir, multi-skill, non-JSON filtering)
- 3/3 SkillDeleteCommand tests pass
- 122/122 total unit tests pass, zero regressions

### Completion Notes List

- ✅ Extended Skill model with `lastUsedAt: Date?` and `executionCount: Int` (var for mutability), backward-compatible decoding
- ✅ Created SkillExecutor with parameter injection ({{param}} → value/default/error), String→Value type conversion, step retry (once), waitAfterSeconds sleep
- ✅ Created SkillRunCommand with HelperProcessManager lifecycle, MCPClientProtocol adapter (HelperMCPClientAdapter), SIGINT handler, metadata update
- ✅ Created SkillListCommand with directory scanning, formatted output, empty-state message
- ✅ Created SkillDeleteCommand with path safety and confirmation message
- ✅ Updated SkillCommand to register all 4 subcommands (compile, run, list, delete)
- ✅ All acceptance criteria satisfied: AC1-AC6

### File List

**New Files:**
- Sources/AxionCLI/Services/SkillExecutor.swift
- Sources/AxionCLI/Commands/SkillRunCommand.swift
- Sources/AxionCLI/Commands/SkillListCommand.swift
- Sources/AxionCLI/Commands/SkillDeleteCommand.swift
- Tests/AxionCLITests/Services/SkillExecutorTests.swift
- Tests/AxionCLITests/Commands/SkillRunCommandTests.swift
- Tests/AxionCLITests/Commands/SkillListCommandTests.swift
- Tests/AxionCLITests/Commands/SkillDeleteCommandTests.swift

**Modified Files:**
- Sources/AxionCore/Models/Skill.swift — added lastUsedAt, executionCount fields; init(from:) for backward compat
- Sources/AxionCLI/Commands/SkillCommand.swift — added 3 subcommands
- Tests/AxionCoreTests/Models/SkillTests.swift — added 5 new tests for execution metadata

### Change Log

- 2026-05-15: Story 9.3 implementation complete — skill library management and execution (run/list/delete commands, SkillExecutor service, execution metadata tracking)
- 2026-05-15: Senior Developer Review (AI) — 5 issues found and auto-fixed:
  - [CRITICAL] Task 7.6 waitAfterSeconds test was missing → added 2 tests verifying sleep behavior
  - [HIGH] AC6: success message now includes skill name (e.g. "技能 'open_calculator' 完成。")
  - [HIGH] Metadata (lastUsedAt/executionCount) now only updated on successful execution, not on failure
  - [MEDIUM] SkillDeleteCommandTests.test_deleteNonexistent_throws was a no-op → now actually tests FileManager behavior
  - [MEDIUM] allowForeground flag noted as unused (by design per Dev Notes 2.9)
  - 146/146 tests pass after fixes
