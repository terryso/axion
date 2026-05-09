# Story 2.4: axion doctor 环境检查命令

Status: done

## Story

As a 用户,
I want 通过 `axion doctor` 检查系统环境和配置状态,
so that 我可以快速定位和修复配置问题.

## Acceptance Criteria

1. **AC1: API Key 检查**
   - Given 运行 `axion doctor`
   - When 检查 API Key
   - Then 报告 config.json 中是否存在有效的 API Key

2. **AC2: API Key 缺失建议**
   - Given API Key 缺失
   - When doctor 输出
   - Then 建议运行 `axion setup` 配置 API Key

3. **AC3: Accessibility 权限检查**
   - Given Accessibility 权限检查
   - When doctor 运行
   - Then 报告权限状态，未授权时给出 "前往系统设置 > 隐私与安全 > 辅助功能" 的具体步骤

4. **AC4: 屏幕录制权限检查**
   - Given 屏幕录制权限检查
   - When doctor 运行
   - Then 报告权限状态，未授权时给出修复建议

5. **AC5: macOS 版本检查**
   - Given macOS 版本检查
   - When doctor 运行
   - Then 报告当前版本是否满足 14.0+ 要求（NFR21）

6. **AC6: 所有检查通过**
   - Given 所有检查通过
   - When doctor 完成
   - Then 显示 "All checks passed!"

7. **AC7: 明确修复建议（NFR14）**
   - Given 任何检查失败
   - When doctor 输出
   - Then 每个失败项附带明确的修复建议，不只是报错

8. **AC8: API Key 不泄露（NFR9）**
   - Given API Key 存在于 config.json
   - When doctor 显示 API Key 状态
   - Then API Key 被掩码显示（复用 `maskApiKey()`），完整值不出现在终端输出中

9. **AC9: 配置文件完整性检查**
   - Given config.json 存在但格式损坏
   - When doctor 运行
   - Then 报告配置文件解析失败，建议重新运行 `axion setup`

## Tasks / Subtasks

- [x] Task 1: 创建 DoctorCommand 主体逻辑 (AC: #1–#9)
  - [x] 1.1 修改 `Sources/AxionCLI/Commands/DoctorCommand.swift`，实现 `run() throws` 方法
  - [x] 1.2 定义 `CheckResult` 结构体：
    ```swift
    enum CheckStatus { case ok, fail }
    struct CheckResult {
        let name: String
        let status: CheckStatus
        let detail: String
        let fixHint: String?
    }
    ```
  - [x] 1.3 定义 `DoctorReport` 结构体：
    ```swift
    struct DoctorReport {
        let results: [CheckResult]
        var allOk: Bool { results.allSatisfy { $0.status == .ok } }
    }
    ```
  - [x] 1.4 创建 `Sources/AxionCLI/IO/DoctorIO.swift` — 定义 DoctorIO 协议（抽象终端 I/O）
    ```swift
    protocol DoctorIO {
        func write(_ line: String)
    }
    ```
  - [x] 1.5 创建 `Sources/AxionCLI/IO/TerminalDoctorIO.swift` — 基于 FileHandle.stdout 的真实终端实现
  - [x] 1.6 实现可测试的 `runDoctor` 静态方法：
    ```swift
    static func runDoctor(
        io: DoctorIO,
        configDirectory: String? = nil
    ) -> DoctorReport
    ```
  - [x] 1.7 实现各项检查的调用序列和结果收集：
    - check 1: config.json 存在性和解析性
    - check 2: API Key 存在性（从加载的 config 中读取）
    - check 3: macOS 版本（使用 `ProcessInfo.operatingSystemVersion` 或 `sw_vers`）
    - check 4: Accessibility 权限（复用 `PermissionChecker.checkAccessibility()`）
    - check 5: 屏幕录制权限（复用 `PermissionChecker.checkScreenRecording()`）
  - [x] 1.8 实现格式化输出逻辑：
    - 每项检查输出: `[OK]` 或 `[FAIL]` + 检查名 + 详情
    - 失败项附加 `->` 前缀的修复建议
    - 最后输出汇总: "All checks passed!" 或 "N check(s) failed."
  - [x] 1.9 实现错误处理：配置文件不存在不视为错误（报告缺失即可），格式损坏则报告解析失败

- [x] Task 2: 实现 SystemChecker 检查服务 (AC: #5)
  - [x] 2.1 创建 `Sources/AxionCLI/Checks/SystemChecker.swift`
    ```swift
    struct SystemChecker {
        static func macOSVersion() -> String
        static func isMacOSVersionSupported() -> Bool  // >= 14.0
    }
    ```
  - [x] 2.2 实现 macOS 版本获取：
    ```swift
    static func macOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static func isMacOSVersionSupported() -> Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion >= 14
    }
    ```

- [x] Task 3: 编写单元测试 (AC: #1–#9)
  - [x] 3.1 创建 `Tests/AxionCLITests/Commands/DoctorCommandTests.swift`
  - [x] 3.2 创建 `MockDoctorIO`（实现 DoctorIO 协议，捕获输出到数组）
  - [x] 3.3 测试 `test_doctor_reportsApiKeyMissing_whenNoConfig` — 无配置文件时报告 API Key 缺失
  - [x] 3.4 测试 `test_doctor_reportsApiKeyOk_whenConfigured` — 有 API Key 时报告通过
  - [x] 3.5 测试 `test_doctor_showsMaskedApiKey` — API Key 被掩码显示（NFR9）
  - [x] 3.6 测试 `test_doctor_reportsAccessibilityStatus` — 报告 Accessibility 权限状态
  - [x] 3.7 测试 `test_doctor_reportsScreenRecordingStatus` — 报告屏幕录制权限状态
  - [x] 3.8 测试 `test_doctor_reportsMacOSVersion` — 报告 macOS 版本
  - [x] 3.9 测试 `test_doctor_reportsUnsupportedMacOS` — macOS 版本不满足要求时报告失败
  - [x] 3.10 测试 `test_doctor_showsFixHints_forFailedChecks` — 失败项附带修复建议（NFR14）
  - [x] 3.11 测试 `test_doctor_showsAllChecksPassed_whenEverythingOk` — 所有通过时显示 "All checks passed!"
  - [x] 3.12 测试 `test_doctor_showsFailureCount_whenChecksFail` — 有失败时显示失败数
  - [x] 3.13 测试 `test_doctor_reportsCorruptConfig` — 配置文件格式损坏时报告解析失败
  - [x] 3.14 测试使用临时目录隔离文件操作（复用 SetupCommandTests 的模式）

- [x] Task 4: 运行全部单元测试确认无回归
  - [x] 4.1 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` 确认所有测试通过

## Dev Notes

### 核心目标

这是 Epic 2 的第四个 Story。Story 2.1（CLI 入口与 ArgumentParser 骨架）、2.2（ConfigManager 分层配置加载）和 2.3（axion setup 首次配置）已完成。本 Story 实现 `axion doctor` 命令：检查系统环境、配置状态、权限状态，并给出明确的修复建议。

### 关键设计决策

**复用已有组件（必须）：**
- `PermissionChecker`（Story 2.3 创建）— Accessibility 和屏幕录制权限检查
- `ConfigManager`（Story 2.2 创建）— 配置文件加载
- `maskApiKey()`（Story 2.3 创建）— API Key 掩码显示
- `AxionConfig`（AxionCore）— 配置模型，含 `apiKey` 字段

**不创建新组件的情况：**
- 不创建新的权限检查逻辑 — 直接复用 `PermissionChecker`
- 不创建新的配置加载逻辑 — 直接复用 `ConfigManager`（部分加载，不应用 CLI override）
- 不创建新的错误类型 — 使用 `AxionError.configError(reason:)`

### DoctorIO 协议设计

**为什么需要 DoctorIO（不同于 SetupIO）：**
- `DoctorCommand.run()` 是 `throws`（同步），不使用 async
- doctor 只需要 `write()`，不需要 `prompt`/`promptSecret`/`confirm`（doctor 不接受用户输入）
- 协议更简单，只有 `write(_ line: String)` 一个方法
- 通过协议注入，测试可以捕获输出并验证

**与 SetupIO 的关系：**
- DoctorIO 是 SetupIO 的简化子集（只有 write）
- 不继承或复用 SetupIO，因为语义不同（一个是交互式引导，一个是诊断报告）
- MockDoctorIO 只需一个 `capturedOutput: [String]` 数组

### 检查项设计（参考 OpenClick doctor.ts）

**OpenClick 的检查项（参考）：**
1. bun runtime — Axion 无此依赖（纯 Swift）
2. macOS version — **保留**（检查 14.0+）
3. OpenclickHelper installed — **适配**（Helper 存在性检查，但 Homebrew 安装时已包含）
4. OpenclickHelper signature — **简化**（MVP 阶段不验证签名，Homebrew 安装保证完整性）
5. OpenclickHelper daemon running — **不适用**（Axion Helper 按需启动，不长驻）
6. Accessibility — **保留**（复用 PermissionChecker）
7. Screen Recording — **保留**（复用 PermissionChecker）
8. API Key — **保留**（检查 config.json 中的 apiKey）

**Axion doctor 的 5 项检查：**

| # | 检查项 | 通过条件 | 失败修复建议 |
|---|--------|---------|------------|
| 1 | 配置文件 | `~/.axion/config.json` 存在且可解析 | "运行 axion setup 创建配置" |
| 2 | API Key | config.json 中 apiKey 非空 | "运行 axion setup 配置 API Key" |
| 3 | macOS 版本 | >= 14.0（Sonoma） | "Axion 需要 macOS 14 (Sonoma) 或更高版本" |
| 4 | Accessibility | `AXIsProcessTrusted()` 返回 true | "打开 系统设置 > 隐私与安全 > 辅助功能，添加 AxionHelper.app" |
| 5 | 屏幕录制 | `CGPreflightScreenCaptureAccess()` 返回 true | "打开 系统设置 > 隐私与安全 > 屏幕录制，添加 AxionHelper.app" |

**检查顺序：** 配置文件 → API Key → macOS 版本 → Accessibility → 屏幕录制（先快后慢，先本地后系统调用）

### 输出格式设计

```
Axion Doctor — 环境检查

  [OK]   配置文件: ~/.axion/config.json
  [OK]   API Key: sk-ant-***...xyz (anthropic)
  [OK]   macOS 版本: 15.3.1
  [OK]   Accessibility: 已授权
  [OK]   屏幕录制: 已授权

All checks passed!
```

失败示例：
```
Axion Doctor — 环境检查

  [FAIL] API Key: 未配置
  -> 运行 axion setup 配置 API Key
  [OK]   macOS 版本: 15.3.1
  [FAIL] Accessibility: 未授权
  -> 打开 系统设置 > 隐私与安全 > 辅助功能，添加 AxionHelper.app
  [OK]   屏幕录制: 已授权

2 check(s) failed. 运行 axion setup 修复问题。
```

### 现有代码状态（必须了解）

**DoctorCommand.swift（当前状态 — placeholder）：**
```swift
struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "检查系统环境和配置状态"
    )
    func run() throws {
        throw CleanExit.message("Doctor command not yet implemented")
    }
}
```
- 本 Story 完全重写此文件

**PermissionChecker.swift（Story 2.3 已完成 — 直接复用）：**
- `checkAccessibility() -> PermissionStatus`（.granted / .notGranted / .unknown）
- `checkScreenRecording() -> PermissionStatus`
- **已知限制（Story 2.3 Review deferred）：** `CGPreflightScreenCaptureAccess()` 会触发系统弹窗，PermissionChecker 无协议抽象不可 Mock
- **doctor 场景影响：** doctor 只调用一次检查并报告状态，弹窗问题可接受。测试时通过 DoctorIO 捕获输出来间接验证。

**ConfigManager.swift（Story 2.2 已完成 — 直接复用）：**
- `loadConfig(configDirectory:cliOverrides:)` — 加载完整配置（async，不适合 doctor 的同步 run()）
- `defaultConfigDirectory` — 默认 `~/.axion/`
- **注意：** doctor 不应调用 `loadConfig()`（async 方法），而是直接用 `FileManager` + `JSONDecoder` 读取 config.json（同步方式），与 SetupCommand 的模式一致

**SetupCommand.swift（Story 2.3 已完成 — 参考模式）：**
- `runSetup(io:configDirectory:)` — 可测试的静态方法模式（doctor 应复用此模式）
- `maskApiKey()` — 全局函数，doctor 直接调用

**AxionConfig（AxionCore）：**
- `apiKey: String?` — 可空
- `provider: LLMProvider` — anthropic / openai

**AxionError（AxionCore）：**
- `.configError(reason: String)` — 配置相关错误

### 模块依赖规则

```
DoctorCommand.swift 可以 import:
  - Foundation (系统)
  - ApplicationServices (系统 — AXIsProcessTrusted，间接通过 PermissionChecker)
  - CoreGraphics (系统 — CGPreflightScreenCaptureAccess，间接通过 PermissionChecker)
  - ArgumentParser (第三方)
  - AxionCore (项目内部)

禁止 import:
  - AxionHelper (进程隔离)
  - OpenAgentSDK (doctor 不需要 Agent 功能)
```

### import 顺序

```swift
// DoctorCommand.swift
import ArgumentParser
import Foundation

import AxionCore
```

### 目录结构

```
Sources/AxionCLI/
  Commands/
    DoctorCommand.swift              # 修改：实现 doctor 检查逻辑
  IO/
    DoctorIO.swift                   # 新建：DoctorIO 协议定义
    TerminalDoctorIO.swift           # 新建：真实终端 I/O 实现
  Checks/
    SystemChecker.swift              # 新建：macOS 版本检查

Tests/AxionCLITests/
  Commands/
    DoctorCommandTests.swift         # 新建：DoctorCommand 单元测试
```

### 禁止事项（反模式）

- **不得使用 `print()` 输出** — 通过 `DoctorIO.write()` 输出
- **不得创建新的错误类型** — 使用 `AxionError.configError(reason:)`
- **测试不得读写真实的 `~/.axion/` 目录** — 使用临时目录隔离
- **API Key 绝对不出现在终端输出中** — NFR9 硬性要求，复用 `maskApiKey()`
- **不得调用 async 方法** — DoctorCommand.run() 是同步 throws，配置读取用 FileManager + JSONDecoder
- **不得在 doctor 中启动 Helper 进程** — doctor 只做检查，不启动任何进程
- **不得创建重复的权限检查逻辑** — 复用 `PermissionChecker`
- **不得创建重复的配置加载逻辑** — 直接用 FileManager + JSONDecoder 同步读取（参考 SetupCommand 模式）

### 与前后 Story 的关系

- **Story 2.3（axion setup）**：doctor 复用 setup 创建的 `PermissionChecker`、`maskApiKey()`、配置文件路径约定。setup 的完成提示引导用户运行 doctor。
- **Story 2.5（Homebrew 分发）**：安装后引导用户运行 `axion doctor` 验证环境。
- **Epic 3（axion run）**：RunCommand 在启动前可调用 doctor 的检查逻辑验证环境就绪。

### 参考实现（OpenClick doctor.ts）

OpenClick 的 `/Users/nick/CascadeProjects/openclick/src/doctor.ts` 提供了以下参考模式：
- `CheckResult` 结构（name, status, detail, fixHint）— **直接采用**
- `DoctorReport` 结构（results[], allOk）— **直接采用**
- `SystemProbe` 协议抽象系统检查 — **简化为 DoctorIO + 直接调用**
- 检查结果格式化输出（mark + name + detail + hint）— **直接采用**

**关键差异：**
- OpenClick 的 doctor 检查 Helper daemon 运行状态和签名 — Axion Helper 按需启动，不需要此检查
- OpenClick 使用 Bun/Node.js TUI 库（Badge、Box、colorize）做输出 — Axion 用纯文本 `[OK]`/`[FAIL]` 标记
- OpenClick 有 `watchDoctor` 自动刷新模式 — Axion MVP 只做单次检查
- OpenClick 的 `SystemProbe` 接口用于测试注入 — Axion 用 `DoctorIO` 协议（更简单，只需 write）

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.4] 原始 Story 定义和 AC
- [Source: _bmad-output/planning-artifacts/architecture.md#D4] 配置系统设计
- [Source: _bmad-output/planning-artifacts/prd.md#FR3] axion doctor 功能需求
- [Source: _bmad-output/planning-artifacts/prd.md#NFR14] 明确修复建议
- [Source: _bmad-output/planning-artifacts/prd.md#NFR21] macOS 14+ 支持
- [Source: _bmad-output/project-context.md#配置系统] 配置文件路径和分层规则
- [Source: _bmad-output/project-context.md#模块依赖] AxionCLI 依赖规则
- [Source: Sources/AxionCLI/Commands/DoctorCommand.swift] 当前 placeholder 实现（需完全重写）
- [Source: Sources/AxionCLI/Permissions/PermissionChecker.swift] PermissionChecker（复用）
- [Source: Sources/AxionCLI/Config/ConfigManager.swift] ConfigManager（参考 defaultConfigDirectory）
- [Source: Sources/AxionCLI/Commands/SetupCommand.swift] SetupCommand（参考 runSetup 模式和 maskApiKey）
- [Source: Sources/AxionCore/Models/AxionConfig.swift] AxionConfig 模型（apiKey, provider）
- [Source: Sources/AxionCore/Errors/AxionError.swift] 统一错误类型
- [Source: /Users/nick/CascadeProjects/openclick/src/doctor.ts] OpenClick doctor 参考（CheckResult、DoctorReport、输出格式）
- [Source: _bmad-output/implementation-artifacts/2-3-axion-setup-first-time-config.md] Story 2.3 完成记录（PermissionChecker 实现细节、Review deferred items）

### ATDD Artifacts

- Checklist: _bmad-output/test-artifacts/atdd-checklist-2-4-axion-doctor-environment-check.md
- Unit tests: Tests/AxionCLITests/Commands/DoctorCommandTests.swift

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

No issues encountered during implementation.

### Completion Notes List

- Implemented `CheckStatus` enum (`ok`, `fail`) and `CheckResult` struct in DoctorCommand.swift
- Implemented `DoctorReport` struct with `allOk` computed property and `failedCount` helper
- Created `DoctorIO` protocol with single `write()` method for testability
- Created `TerminalDoctorIO` using `FileHandle.standardOutput` for real terminal output
- Created `SystemChecker` with `macOSVersion()` and `isMacOSVersionSupported()` using `ProcessInfo`
- Implemented `DoctorCommand.runDoctor(io:configDirectory:)` static method with 5 checks:
  1. Config file existence and parseability
  2. API Key presence with masked display (reuses `maskApiKey()`)
  3. macOS version >= 14.0 check
  4. Accessibility permission (reuses `PermissionChecker`)
  5. Screen recording permission (reuses `PermissionChecker`)
- Output format: `[OK]`/`[FAIL]` markers with `->` fix hints for failures
- Summary: "All checks passed!" or "N check(s) failed. 运行 axion setup 修复问题。"
- All 22 unit tests pass (was 22 ATDD red-phase scaffolds, now all green)
- Full test suite: 195 tests, 0 failures, no regressions

### File List

- Sources/AxionCLI/Commands/DoctorCommand.swift (modified — full implementation with CheckStatus, CheckResult, DoctorReport, runDoctor)
- Sources/AxionCLI/IO/DoctorIO.swift (new — DoctorIO protocol)
- Sources/AxionCLI/IO/TerminalDoctorIO.swift (new — TerminalDoctorIO implementation)
- Sources/AxionCLI/Checks/SystemChecker.swift (new — macOS version check)
- Tests/AxionCLITests/Commands/DoctorCommandTests.swift (modified — removed XCTSkip, all 22 tests green)

## Change Log

- 2026-05-09: Implemented Story 2.4 — axion doctor environment check command with 5 checks, masked API key display, fix hints, and 22 unit tests
- 2026-05-09: Code review — 3 patches applied, 2 deferred, 8 dismissed

### Review Findings

- [x] [Review][Patch] Eliminate duplicate config file decode — checkConfigFile and loadConfig both read+decode the same file; merged into single checkConfigFile returning (result, config?) tuple [DoctorCommand.swift:111-136]
- [x] [Review][Patch] Strengthen test_doctor_showsAllChecksPassed — test accepted both pass/fail outcomes; added assertion that report.allOk matches output summary [DoctorCommandTests.swift:189-210]
- [x] [Review][Patch] Fix test_doctor_reportsUnsupportedMacOS — test only checked non-empty version string; now also verifies isMacOSVersionSupported() and output contains version number [DoctorCommandTests.swift:180-197]
- [x] [Review][Defer] Permission checks not mockable in tests — PermissionChecker is a concrete struct with no protocol abstraction; known limitation from Story 2.3 review, deferred
- [x] [Review][Defer] FixHint references AxionHelper.app not yet installed — doctor suggests adding AxionHelper.app to permissions, but Helper isn't installed until Story 2.5 (Homebrew); deferred to Story 2.5
