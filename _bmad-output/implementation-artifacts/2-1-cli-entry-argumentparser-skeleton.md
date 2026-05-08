# Story 2.1: CLI 入口与 ArgumentParser 骨架

Status: review

## Story

As a 用户,
I want `axion` 命令可以运行并显示帮助信息,
so that 我可以了解 Axion 提供的命令和用法.

## Acceptance Criteria

1. **AC1: `axion --help` 显示根命令帮助**
   - Given axion 编译完成
   - When 运行 `axion --help`
   - Then 显示根命令帮助，列出 run / setup / doctor 子命令及其简要说明

2. **AC2: `axion --version` 显示版本号**
   - Given axion 编译完成
   - When 运行 `axion --version`
   - Then 显示版本号

3. **AC3: 未知子命令显示错误提示**
   - Given axion 编译完成
   - When 运行 `axion unknown`
   - Then 显示错误提示和帮助信息

## Tasks / Subtasks

- [x] Task 1: 更新 main.swift 入口为完整 ArgumentParser 根命令 (AC: #1, #2)
  - [x] 1.1 将现有 `AxionCLI` struct 改为 root command group，注册子命令（RunCommand, SetupCommand, DoctorCommand）
  - [x] 1.2 设置 `CommandConfiguration`：commandName="axion"、abstract 描述中文、version 从 VERSION 文件或硬编码读取、`defaultSubcommand` 不设置（用户必须明确指定子命令）
  - [x] 1.3 确保 `@main` 入口正确编译通过

- [x] Task 2: 创建 AxionCommand.swift 根命令 (AC: #1)
  - [x] 2.1 创建 `Sources/AxionCLI/Commands/AxionCommand.swift`（或直接在 main.swift 中定义，见 Dev Notes 中的架构决策）
  - [x] 2.2 根命令无自定义选项/参数，仅作为子命令容器
  - [x] 2.3 使用 `subcommands: [RunCommand.self, SetupCommand.self, DoctorCommand.self]` 注册三个子命令

- [x] Task 3: 创建 RunCommand.swift 骨架 (AC: #1)
  - [x] 3.1 创建 `Sources/AxionCLI/Commands/RunCommand.swift`
  - [x] 3.2 定义 `RunCommand: ParsableCommand`，configuration 包含 commandName="run"、abstract="执行桌面自动化任务"
  - [x] 3.3 声明 `@Argument var task: String`（任务描述）和 `@Flag var live: Bool`（实际执行标志）以及 `@Option var maxSteps: Int?`、`@Option var maxBatches: Int?`、`@Flag var allowForeground: Bool`、`@Flag var verbose: Bool`、`@Flag var json: Bool`
  - [x] 3.4 `run()` 方法暂时 `throw CleanExit.message("Run command not yet implemented")`（占位，Epic 3 实现）

- [x] Task 4: 创建 SetupCommand.swift 骨架 (AC: #1)
  - [x] 4.1 创建 `Sources/AxionCLI/Commands/SetupCommand.swift`
  - [x] 4.2 定义 `SetupCommand: ParsableCommand`，configuration 包含 commandName="setup"、abstract="首次配置 Axion"
  - [x] 4.3 `run()` 方法暂时 `throw CleanExit.message("Setup command not yet implemented")`（占位，Story 2.3 实现）

- [x] Task 5: 创建 DoctorCommand.swift 骨架 (AC: #1)
  - [x] 5.1 创建 `Sources/AxionCLI/Commands/DoctorCommand.swift`
  - [x] 5.2 定义 `DoctorCommand: ParsableCommand`，configuration 包含 commandName="doctor"、abstract="检查系统环境和配置状态"
  - [x] 5.3 `run()` 方法暂时 `throw CleanExit.message("Doctor command not yet implemented")`（占位，Story 2.4 实现）

- [x] Task 6: 创建版本管理工具 (AC: #2)
  - [x] 6.1 创建 `Sources/AxionCLI/Constants/Version.swift`，定义 `enum AxionVersion` 含 `static let current = "0.1.0"`（与 VERSION 文件同步）
  - [x] 6.2 在根命令的 `CommandConfiguration` 中通过 `version` 参数引用版本常量

- [x] Task 7: 编写单元测试 (AC: #1, #2, #3)
  - [x] 7.1 创建 `Tests/AxionCLITests/Commands/AxionCommandTests.swift`
  - [x] 7.2 测试 `test_axionHelp_showsSubcommands()`：验证 `--help` 输出包含 "run"、"setup"、"doctor" 关键字
  - [x] 7.3 测试 `test_axionVersion_showsVersion()`：验证 `--version` 输出包含版本号
  - [x] 7.4 测试 `test_unknownSubcommand_showsError()`：验证未知子命令返回非零退出码
  - [x] 7.5 测试 `test_runCommandParsesArguments()`：验证 RunCommand 正确解析 `task`、`--live`、`--max-steps`、`--max-batches`、`--allow-foreground`、`--verbose`、`--json` 参数
  - [x] 7.6 测试 `test_runCommandRequiresTaskArgument()`：验证 RunCommand 缺少 task 参数时报错

- [x] Task 8: 运行全部单元测试确认无回归
  - [x] 8.1 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionCoreTests" --filter "AxionCLITests"` 确认所有测试通过

## Dev Notes

### 核心目标

这是 Epic 2 的第一个 Story。Epic 1（AxionHelper）已完成全部 6 个 Story。本 Story 在 AxionCLI 目标中建立 ArgumentParser 骨架，定义三个子命令（run / setup / doctor），但只搭建结构和参数声明，不实现业务逻辑。

### 当前 AxionCLI/main.swift 状态（必须更新）

现有 `main.swift` 只有一个简单的 placeholder：
```swift
import ArgumentParser

@main
struct AxionCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "axion",
        abstract: "Axion — macOS 桌面自动化 CLI"
    )
    func run() throws {
        print("Axion CLI placeholder")
    }
}
```

需要将此替换为包含子命令的完整根命令。**注意：main.swift 中已有 `@main struct AxionCLI`，保留这个入口点，只需扩展其 CommandConfiguration 和添加 subcommands。**

### 架构决策：文件组织方式

根据架构文档的目录结构定义：
- `Sources/AxionCLI/main.swift` — 入口：ArgumentParser 根命令
- `Sources/AxionCLI/Commands/` — 子命令目录

**推荐方案：** 将 `AxionCLI` 根命令定义保留在 `main.swift` 中（因为是入口点），将 `RunCommand`、`SetupCommand`、`DoctorCommand` 分别放在 `Commands/` 目录下的独立文件中。这与架构文档完全一致。

### ArgumentParser 关键 API

swift-argument-parser 1.5.0+（实际使用 1.7.1）：

```swift
import ArgumentParser

// 根命令（在 main.swift 中）
@main
struct AxionCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "axion",
        abstract: "Axion — macOS 桌面自动化 CLI",
        version: AxionVersion.current,   // --version 支持
        subcommands: [RunCommand.self, SetupCommand.self, DoctorCommand.self]
    )
}

// 子命令示例（在 Commands/RunCommand.swift 中）
struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "执行桌面自动化任务"
    )

    @Argument(help: "任务描述")
    var task: String

    @Flag(name: .long, help: "实际执行模式（默认为干跑模式）")
    var live: Bool = false

    @Option(name: .long, help: "单次运行最大步骤数")
    var maxSteps: Int?

    // ...
}
```

**注意 `@Option` 的 `name` 参数：** `--max-steps` 需要 `name: .customLong("max-steps")` 或使用 `name: .long` 让 ArgumentParser 自动转换 camelCase 为 kebab-case（`maxSteps` -> `--max-steps`）。ArgumentParser 1.5+ 默认将 camelCase 属性名转为 kebab-case CLI 选项，所以 `name: .long` 即可。

### RunCommand 参数设计（参考 PRD FR6-FR10）

| 参数 | 类型 | Flag/Option/Argument | 说明 |
|------|------|---------------------|------|
| `task` | String (positional) | @Argument | 任务描述，必填 |
| `--live` | Bool (flag) | @Flag | 实际执行模式 |
| `--max-steps` | Int? | @Option | 最大步骤数 |
| `--max-batches` | Int? | @Option | 最大批次 |
| `--allow-foreground` | Bool (flag) | @Flag | 允许前台操作 |
| `--verbose` | Bool (flag) | @Flag | 详细输出 |
| `--json` | Bool (flag) | @Flag | JSON 格式输出 |

这些参数在 Epic 3 中才会被实际使用（ConfigManager 加载、RunEngine 传入），本 Story 只需声明它们。

### 版本号来源

项目根目录已有 `VERSION` 文件（内容 `0.1.0`）。两种方案：
1. **编译时读取 VERSION 文件**：需要 build 脚本支持或资源包处理
2. **硬编码常量 + 注释说明**：简单直接，与 VERSION 文件手动同步

**推荐方案 2：** 创建 `AxionVersion.current = "0.1.0"` 常量，注释 `// 与 VERSION 文件同步`。Homebrew formula 更新时 build-release.sh 已经读取 VERSION 文件，CLI 的 `--version` 不需要动态读取。

### 占位命令的退出方式

使用 ArgumentParser 的 `CleanExit` 而非 `print()` + `Foundation.exit()`：
```swift
func run() throws {
    throw CleanExit.message("Run command not yet implemented (Epic 3)")
}
```

这确保 ArgumentParser 正确处理退出码和输出格式。

### 测试方法

ArgumentParser 提供了内置的测试支持。通过 `ParsableCommand.parse()` 或 `ParsableCommand.main()` 进行测试：

```swift
// 解析测试
func test_runCommandParsesArguments() throws {
    let cmd = try RunCommand.parse(["打开计算器", "--live", "--max-steps", "5"])
    XCTAssertEqual(cmd.task, "打开计算器")
    XCTAssertTrue(cmd.live)
    XCTAssertEqual(cmd.maxSteps, 5)
}

// 帮助输出测试
func test_axionHelp_showsSubcommands() throws {
    let helpOutput = try AxionCLI.parse(["--help"])
    // 或者捕获 stdout
}
```

**注意：** `parse()` 返回解析后的命令实例。`parseAsRoot()` 可以从根命令解析子命令。对于 `--help` 和 `--version` 测试，ArgumentParser 会抛出 `CleanExit.help` 或 `CleanExit.versionRequest`，测试中需要 ` XCTAssertThrowsError` 并验证错误类型。

### Commands/ 目录结构

```
Sources/AxionCLI/
  main.swift                    # UPDATE: 扩展为含子命令的根命令
  Commands/                     # NEW directory
    RunCommand.swift            # NEW
    SetupCommand.swift          # NEW
    DoctorCommand.swift         # NEW
  Constants/                    # NEW directory
    Version.swift               # NEW

Tests/AxionCLITests/
  Commands/                     # NEW directory
    AxionCommandTests.swift     # NEW
```

### 前一个 Epic 的经验教训（Epic 1 全部 6 个 Story）

**关键模式（必须遵循）：**
- swift-tools-version: 6.1，编译器 6.2.4
- import 顺序：系统 -> 第三方 -> 项目内部（AxionCore）
- 测试命名：`test_方法名_场景_预期结果`
- AxionHelperTests 排除 Integration 目录（`exclude: ["Integration"]`）
- `nonisolated(unsafe)` 用于全局单例
- Mock 使用 `@unchecked Sendable` + 闭包 handler 模式
- 所有错误使用 `AxionError` 枚举（但在本 Story 中不需要错误处理）

**AxionCore 已有模型（可直接 import AxionCore 使用）：**
- `AxionConfig`：含 `model`, `maxSteps`, `maxBatches`, `maxReplanRetries`, `traceEnabled`, `sharedSeatMode` 字段及 `static let default` 实例
- `ConfigKeys`：字符串常量
- `RunState`, `Plan`, `Step`, `RunContext`：执行循环模型

**RunCommand 的参数应与 AxionConfig 字段对应：**
- `--max-steps` -> `AxionConfig.maxSteps`
- `--max-batches` -> `AxionConfig.maxBatches`
- `--verbose` -> 影响日志级别（debug vs info）
- `--live` -> 影响执行模式
- `--allow-foreground` -> 影响 `AxionConfig.sharedSeatMode`

### 模块依赖规则

```
AxionCLI 可以 import:
  - Foundation (系统)
  - ArgumentParser (第三方)
  - OpenAgentSDK (第三方) — 本 Story 不使用
  - AxionCore (项目内部) — 本 Story 使用 AxionConfig 等模型

AxionCLI 禁止 import:
  - AxionHelper (进程隔离)
```

### 禁止事项（反模式）

- **不得使用 `print()` 输出到 stdout** — 使用 ArgumentParser 的标准输出机制或 `CleanExit.message()`（注意：placeholder 命令的 `CleanExit.message()` 是临时措施，Epic 3 会替换为实际输出）
- **不得在 AxionCLI 中 import AxionHelper**
- **不得创建新的错误类型体系** — 使用 `AxionError`（但本 Story 可能不需要错误处理）
- **不得硬编码 prompt 文本在代码中** — 本 Story 不涉及 prompt
- **子命令的 abstract 必须使用中文** — 与项目整体语言风格一致
- **不得实现任何业务逻辑** — 本 Story 只搭建骨架，run/setup/doctor 的实际逻辑分别在 Epic 3 和 Story 2.3/2.4 中实现

### 性能注意（NFR1）

NFR1 要求 CLI 冷启动到首次 LLM 请求发出 < 2 秒。ArgumentParser 的 `--help` 和 `--version` 解析非常快，不会影响冷启动性能。子命令解析也不应有性能问题。

### Project Structure Notes

遵循架构文档定义的目录结构。本 Story 新增：
- `Sources/AxionCLI/Commands/` 目录（架构文档已规划）
- `Sources/AxionCLI/Constants/` 目录（架构文档已规划，含 Version.swift）
- `Tests/AxionCLITests/Commands/` 目录（镜像源结构）

不创建新的顶级目录。

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.1] 原始 Story 定义和 AC
- [Source: _bmad-output/planning-artifacts/architecture.md#项目结构] AxionCLI 目录结构定义
- [Source: _bmad-output/planning-artifacts/architecture.md#D4 配置系统] 分层配置设计（RunCommand 参数最终传入 ConfigManager）
- [Source: _bmad-output/planning-artifacts/prd.md#实现考量] CLI 入口、ArgumentParser 声明
- [Source: _bmad-output/project-context.md#技术栈] swift-argument-parser 1.5.0+
- [Source: _bmad-output/project-context.md#模块依赖] AxionCLI 依赖规则
- [Source: _bmad-output/project-context.md#import 顺序] 系统框架 -> 第三方 -> 项目内部
- [Source: _bmad-output/project-context.md#反模式] 禁止 print()、禁止 import AxionHelper
- [Source: _bmad-output/implementation-artifacts/1-6-helper-integration-app-packaging.md] Epic 1 收官 Story 的经验教训
- [Source: Sources/AxionCLI/main.swift] 当前入口文件（需更新）
- [Source: Sources/AxionCore/Models/AxionConfig.swift] AxionConfig 模型（RunCommand 参数对应）
- [Source: Package.swift] SPM 清单（AxionCLI 已声明 ArgumentParser 依赖）
- [Source: VERSION] 版本号 0.1.0

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (GLM-5.1)

### Debug Log References

- 遇到 `@main` 与 `main.swift` 冲突：Swift 6.1 中 `main.swift` 被视为顶层代码文件，与 `@main` 属性不兼容。解决方案：将 `main.swift` 重命名为 `AxionCLI.swift`，与项目文件命名规范（文件名与主类型同名）一致。

### Completion Notes List

- Task 1-2: 将 `main.swift` 重命名为 `AxionCLI.swift`，扩展 `AxionCLI` 为含 `subcommands` 和 `version` 的根命令。无 `run()` 方法（纯子命令容器）。
- Task 3: `RunCommand` 声明了 7 个参数/选项（task, live, maxSteps, maxBatches, allowForeground, verbose, json），`run()` 使用 `CleanExit.message()` 占位。
- Task 4: `SetupCommand` 骨架创建完成，`run()` 占位。
- Task 5: `DoctorCommand` 骨架创建完成，`run()` 占位。
- Task 6: `AxionVersion.current = "0.1.0"` 常量定义，与 VERSION 文件同步。
- Task 7: 21 个 ATDD 测试全部从 RED 变为 GREEN。
- Task 8: 全量单元测试（55 个）通过，无回归。

### File List

- Sources/AxionCLI/AxionCLI.swift (modified, renamed from main.swift)
- Sources/AxionCLI/Commands/RunCommand.swift (new)
- Sources/AxionCLI/Commands/SetupCommand.swift (new)
- Sources/AxionCLI/Commands/DoctorCommand.swift (new)
- Sources/AxionCLI/Constants/Version.swift (new)
- Tests/AxionCLITests/Commands/AxionCommandTests.swift (existing, ATDD red->green)

## Change Log

- 2026-05-09: Story 2-1 实现完成 — CLI 入口与 ArgumentParser 骨架，21 个测试全部通过
