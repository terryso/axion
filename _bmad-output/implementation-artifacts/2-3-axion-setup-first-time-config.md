# Story 2.3: axion setup 首次配置命令

Status: done

## Story

As a 新用户,
I want 通过 `axion setup` 引导完成首次配置（API Key 输入、权限检查）,
so that 我可以在 5 分钟内准备好使用 Axion.

## Acceptance Criteria

1. **AC1: 提示输入 API Key**
   - Given 运行 `axion setup`
   - When 引导开始
   - Then 提示用户输入 Anthropic API Key

2. **AC2: API Key 写入 config.json**
   - Given API Key 输入完成（非空字符串）
   - When setup 继续
   - Then 将 API Key 写入 `~/.axion/config.json`（文件权限 0o600）
   - And 目录 `~/.axion/` 不存在时自动创建

3. **AC3: Accessibility 权限检查**
   - Given API Key 已存储
   - When setup 检查 Accessibility 权限
   - Then 如已授权则显示通过，未授权则提示前往系统偏好设置授权

4. **AC4: 屏幕录制权限检查**
   - Given Accessibility 已授权（或提示后继续）
   - When setup 检查屏幕录制权限
   - Then 如已授权则显示通过，未授权则提示授权步骤

5. **AC5: 完成提示**
   - Given 所有配置完成
   - When setup 结束
   - Then 显示 "Setup complete! 运行 axion doctor 检查环境" 提示

6. **AC6: API Key 不泄露（NFR9）**
   - Given 用户已输入 API Key
   - When setup 显示配置摘要
   - Then API Key 被掩码显示（如 `sk-ant-***...xyz`），完整值不出现在终端输出中

7. **AC7: 重复运行处理**
   - Given `~/.axion/config.json` 已存在且含 apiKey
   - When 再次运行 `axion setup`
   - Then 提示用户 API Key 已存在，可选择保留或替换

## Tasks / Subtasks

- [x] Task 1: 创建 SetupCommand 实现主体 (AC: #1, #2, #5, #6, #7)
  - [x] 1.1 修改 `Sources/AxionCLI/Commands/SetupCommand.swift`，实现 `run() throws` 方法
  - [x] 1.2 创建 `Sources/AxionCLI/IO/SetupIO.swift` — 定义 SetupIO 协议（抽象终端 I/O，方便测试）
    ```swift
    protocol SetupIO {
        func write(_ line: String)
        func prompt(_ question: String) -> String
        func promptSecret(_ question: String) -> String
        func confirm(_ question: String, defaultAnswer: Bool) -> Bool
    }
    ```
  - [x] 1.3 创建 `Sources/AxionCLI/IO/TerminalSetupIO.swift` — 基于 FileHandle.stdin/stdout 的真实终端实现
    - `write()`: 使用 `FileHandle.standardOutput.write()`
    - `prompt()`: 读取 stdin 一行
    - `promptSecret()`: 使用 `stty -echo` 关闭回显（参考 OpenClick `promptSecret` 模式）
    - `confirm()`: 读取 y/n 确认
  - [x] 1.4 实现引导流程：
    - 步骤 1: 检查 API Key 是否已存在于 config.json → AC7 重复运行处理
    - 步骤 2: 提示输入 API Key → AC1
    - 步骤 3: 调用 `ConfigManager.ensureConfigDirectory()` + `ConfigManager.saveConfigFile()` 保存 → AC2
    - 步骤 4: 检查 Accessibility 权限 → AC3
    - 步骤 5: 检查屏幕录制权限 → AC4
    - 步骤 6: 显示完成提示 → AC5
  - [x] 1.5 实现 API Key 掩码函数 `maskApiKey(_ key: String) -> String`
    - 格式: `sk-ant-***...xyz`（显示前 6 字符和后 3 字符，中间用 `***` 替代）
    - key 长度 <= 9 时显示 `***`

- [x] Task 2: 创建 PermissionChecker 权限检查服务 (AC: #3, #4)
  - [x] 2.1 创建 `Sources/AxionCLI/Permissions/PermissionChecker.swift`
    ```swift
    enum PermissionStatus {
        case granted
        case notGranted
        case unknown
    }

    struct PermissionChecker {
        static func checkAccessibility() -> PermissionStatus
        static func checkScreenRecording() -> PermissionStatus
    }
    ```
  - [x] 2.2 实现权限检查逻辑：
    - **Accessibility**: 使用 `AXIsProcessTrusted()`（ApplicationServices 框架）
    - **屏幕录制**: 使用 `CGPreflightScreenCaptureAccess()`（CoreGraphics 框架，macOS 10.15+）
    - 注意: CLI 进程本身检查权限状态是**指示性**的 — 实际需要 Helper App 获得授权。setup 命令检查的是系统级状态并引导用户。
  - [x] 2.3 在 setup 流程中显示检查结果和修复建议：
    - 通过: `"  [OK] Accessibility: 已授权"`
    - 未授权: `"  [FAIL] Accessibility: 未授权"` + `"  -> 打开 系统设置 > 隐私与安全 > 辅助功能，添加 AxionHelper"`
    - 屏幕录制类似

- [x] Task 3: 编写单元测试 (AC: #1–#7)
  - [x] 3.1 创建 `Tests/AxionCLITests/Commands/SetupCommandTests.swift`
  - [x] 3.2 测试 `test_maskApiKey_longKey_showsMasked()` — 长密钥掩码正确
  - [x] 3.3 测试 `test_maskApiKey_shortKey_showsMasked()` — 短密钥掩码正确
  - [x] 3.4 测试 `test_maskApiKey_emptyKey_returnsEmpty()` — 空密钥处理
  - [x] 3.5 测试 `test_setupIO_writesOutput()` — SetupIO.write 输出正确
  - [x] 3.6 测试 `test_setup_promptsForApiKey_whenNoConfig()` — 无配置时提示输入
  - [x] 3.7 测试 `test_setup_savesApiKey_toConfigJson()` — API Key 正确保存到文件
  - [x] 3.8 测试 `test_setup_showsMaskedApiKey_inSummary()` — 摘要中 API Key 被掩码
  - [x] 3.9 测试 `test_setup_detectsExistingApiKey()` — 检测已有 API Key
  - [x] 3.10 创建 MockSetupIO 用于测试（实现 SetupIO 协议，预设输入/捕获输出）
  - [x] 3.11 测试使用临时目录（`NSTemporaryDirectory` + UUID）隔离文件操作

- [x] Task 4: 运行全部单元测试确认无回归
  - [x] 4.1 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionCoreTests" --filter "AxionCLITests"` 确认所有测试通过

## Dev Notes

### 核心目标

这是 Epic 2 的第三个 Story。Story 2.1（CLI 入口与 ArgumentParser 骨架）和 Story 2.2（ConfigManager 分层配置加载）已完成。本 Story 实现 `axion setup` 命令的完整引导流程：API Key 输入 + 保存 + 权限检查 + 完成提示。

### 关键设计决策

**D1（已修订）: API Key 存储在 config.json（文件权限 0o600）**
- Story 2.2 实现时已将 API Key 统一存储在 `~/.axion/config.json`，不再使用 Keychain
- setup 命令直接调用 `ConfigManager.saveConfigFile()` 保存含 API Key 的配置
- 文件权限 0o600（仅用户可读写）

**D4: 配置系统分层覆盖**
- `axion setup` 写入的是第 2 层（config.json）
- 环境变量 `AXION_API_KEY` 可覆盖（CI/脚本场景）

### SetupIO 协议（测试关键）

**为什么需要 SetupIO 协议：**
- `SetupCommand.run()` 是 `throws`（同步），不使用 async
- 终端 I/O（stdin/stdout）不可直接在单元测试中模拟
- 通过协议注入，测试可以提供 MockSetupIO 预设输入序列

**协议方法映射到 Setup 流程：**

| 流程步骤 | 使用的 SetupIO 方法 | Mock 行为 |
|---------|-------------------|----------|
| 提示输入 API Key | `promptSecret("Anthropic API Key: ")` | 返回预设的 API Key |
| API Key 已存在，确认是否替换 | `confirm("API Key 已存在，是否替换？", defaultAnswer: false)` | 返回 true/false |
| 权限未授权，确认是否继续 | `confirm("是否继续？", defaultAnswer: true)` | 返回 true |
| 显示进度/结果 | `write("...")` | 捕获输出到数组 |

### PermissionChecker 实现指南

**Accessibility 权限检查：**
```swift
import ApplicationServices

static func checkAccessibility() -> PermissionStatus {
    let trusted = AXIsProcessTrusted()
    return trusted ? .granted : .notGranted
}
```

**屏幕录制权限检查：**
```swift
import CoreGraphics

static func checkScreenRecording() -> PermissionStatus {
    if #available(macOS 10.15, *) {
        let hasAccess = CGPreflightScreenCaptureAccess()
        return hasAccess ? .granted : .notGranted
    }
    return .unknown
}
```

**重要说明：**
- `AXIsProcessTrusted()` 检查的是**调用进程**的权限状态
- CLI 进程本身不需要 AX 权限，但此检查可以指示系统级配置状态
- 实际需要 Helper App 获得授权（Story 1.6 已处理 Helper 签名和打包）
- setup 的权限检查是**用户引导**性质，而非功能验证

**权限提示文案：**
- Accessibility 未授权: `"  -> 打开 系统设置 > 隐私与安全 > 辅助功能，添加 AxionHelper.app"`
- 屏幕录制未授权: `"  -> 打开 系统设置 > 隐私与安全 > 屏幕录制，添加 AxionHelper.app"`

### 现有代码状态（必须了解）

**SetupCommand.swift（当前状态 — placeholder）：**
- `run()` 方法只抛出 `CleanExit.message("Setup command not yet implemented")`
- 本 Story 完全重写此方法

**ConfigManager.swift（Story 2.2 已完成）：**
- `loadConfig(configDirectory:cliOverrides:)` — 加载配置
- `saveConfigFile(_:toDirectory:)` — 保存配置到指定目录
- `ensureConfigDirectory(atPath:)` — 确保目录存在
- `defaultConfigDirectory` — `~/.axion/`

**AxionConfig（AxionCore）：**
- `apiKey: String?` — 可空，Codable 可编解码
- `static let default` — apiKey 为 nil

**AxionError（AxionCore）：**
- `.configError(reason: String)` — 配置相关错误

**ConfigKeys（AxionCore）：**
- `apiKey = "apiKey"` — JSON 字段名

### 模块依赖规则

```
SetupCommand.swift 可以 import:
  - Foundation (系统)
  - ApplicationServices (系统 — AXIsProcessTrusted)
  - CoreGraphics (系统 — CGPreflightScreenCaptureAccess)
  - ArgumentParser (第三方)
  - AxionCore (项目内部)

禁止 import:
  - AxionHelper (进程隔离)
  - OpenAgentSDK (setup 不需要 Agent 功能)
```

### import 顺序

```swift
// SetupCommand.swift
import ApplicationServices
import ArgumentParser
import CoreGraphics
import Foundation

import AxionCore
```

### 目录结构

```
Sources/AxionCLI/
  Commands/
    SetupCommand.swift              # 修改：实现 setup 引导流程
  IO/
    SetupIO.swift                   # 新建：SetupIO 协议定义
    TerminalSetupIO.swift           # 新建：真实终端 I/O 实现
  Permissions/
    PermissionChecker.swift         # 新建：权限检查服务

Tests/AxionCLITests/
  Commands/
    SetupCommandTests.swift         # 新建：SetupCommand 单元测试
```

### 禁止事项（反模式）

- **不得使用 `print()` 输出** — 通过 `SetupIO.write()` 输出
- **不得创建新的错误类型** — 使用 `AxionError.configError(reason:)`
- **测试不得读写真实的 `~/.axion/` 目录** — 使用临时目录隔离
- **API Key 绝对不出现在终端输出中** — NFR9 硬性要求，使用 `maskApiKey()` 掩码
- **不得 import Security（Keychain）** — API Key 存储在 config.json，不使用 Keychain
- **不得在 setup 中启动 Helper 进程** — setup 只做配置和权限检查

### 与后续 Story 的关系

- **Story 2.4（axion doctor）**：将复用 `PermissionChecker`，并检查 config.json 完整性
- **Epic 3（axion run）**：RunCommand 将调用 `ConfigManager.loadConfig()` 读取 setup 写入的配置
- **Story 2.5（Homebrew 分发）**：安装后引导用户运行 `axion setup`

### 参考实现（OpenClick）

OpenClick 的 `src/setup.ts` 提供了以下参考模式：
- `SetupIO` 协议抽象终端 I/O（`write`, `prompt`, `secret`, `select`）
- `promptSecret()` 使用 `stty -echo` 隐藏 API Key 输入
- `configureApiKey()` 先检查已有 Key，提供 keep/replace 选项
- `maskApiKey()` 掩码显示格式

OpenClick 的 `src/doctor.ts` 提供了以下参考模式：
- `CheckResult` 结构（name, status, detail, fixHint）
- `SystemProbe` 协议抽象系统检查
- 检查结果格式化输出（mark + name + detail + hint）

**关键差异：**
- OpenClick 用 Bun/Node.js TUI 库做交互，Axion 用纯 stdin/stdout
- OpenClick 通过 Helper 进程的 `check_permissions` 子命令检查权限，Axion 直接用系统 API
- OpenClick 支持 Anthropic/OpenAI 双 provider，Axion MVP 只支持 Anthropic
- Axion 不做 Helper 的安装/签名引导（Helper 已包含在 Homebrew 安装包中）

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.3] 原始 Story 定义和 AC
- [Source: _bmad-output/planning-artifacts/architecture.md#D1 API Key 存储] API Key 存储决策（config.json 0o600）
- [Source: _bmad-output/planning-artifacts/architecture.md#D4 配置系统] 分层配置设计
- [Source: _bmad-output/project-context.md#配置系统] 分层配置规则和默认值
- [Source: _bmad-output/project-context.md#模块依赖] AxionCLI 依赖规则
- [Source: Sources/AxionCLI/Config/ConfigManager.swift] ConfigManager 已有 API（saveConfigFile, ensureConfigDirectory）
- [Source: Sources/AxionCore/Models/AxionConfig.swift] AxionConfig 模型（apiKey: String?）
- [Source: Sources/AxionCore/Errors/AxionError.swift] 统一错误类型（.configError）
- [Source: Sources/AxionCLI/Commands/SetupCommand.swift] 当前 placeholder 实现（需完全重写）
- [Source: /Users/nick/CascadeProjects/openclick/src/setup.ts] OpenClick setup 参考（SetupIO 模式、promptSecret、maskApiKey）
- [Source: /Users/nick/CascadeProjects/openclick/src/doctor.ts] OpenClick doctor 参考（CheckResult、权限检查）

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

No debug issues encountered during implementation.

### Completion Notes List

- All 4 tasks and 11 subtasks completed
- Created SetupIO protocol for testable terminal I/O abstraction
- Implemented TerminalSetupIO with stty -echo for secret input
- Implemented PermissionChecker using AXIsProcessTrusted() and CGPreflightScreenCaptureAccess()
- Implemented full setup flow: API Key input/save, permission checks, completion message
- Implemented maskApiKey() for NFR9 compliance (API Key never shown in full)
- Handled AC7 repeat-run scenario (detect existing key, offer keep/replace)
- Empty input validation with re-prompt
- Whitespace trimming on API Key input
- All 23 new SetupCommand tests pass
- All 94 total unit tests pass (0 regressions)

### File List

- Sources/AxionCLI/Commands/SetupCommand.swift (modified - full rewrite with setup flow)
- Sources/AxionCLI/IO/SetupIO.swift (new - protocol definition)
- Sources/AxionCLI/IO/TerminalSetupIO.swift (new - real terminal I/O implementation)
- Sources/AxionCLI/Permissions/PermissionChecker.swift (new - permission checking service)
- Sources/AxionCLI/Config/ConfigManager.swift (modified - made defaultConfigDirectory internal)
- Tests/AxionCLITests/Commands/SetupCommandTests.swift (modified - replaced stubs with real tests)

### Review Findings

- [x] [Review][Patch] Terminal echo-off state on interruption — `TerminalSetupIO.promptSecret()` 中 `stty -echo` 后若进程被中断（SIGINT），终端将保持无回显状态。已修复：使用 `defer { shell("stty echo") }` 确保始终恢复。 [`TerminalSetupIO.swift:25-27`]
- [x] [Review][Patch] Deprecated Process API — `TerminalSetupIO.shell()` 使用已弃用的 `task.launchPath` + `task.launch()`。已替换为 `task.executableURL` + `task.run()`。 [`TerminalSetupIO.swift:52-59`]
- [x] [Review][Patch] Import 顺序偏差 — `SetupCommand.swift` 中 ArgumentParser 混在系统框架之间。已修正为系统框架 → 第三方 → 项目内部。 [`SetupCommand.swift:1-7`]
- [ ] [Review][Defer] `CGPreflightScreenCaptureAccess()` 会触发系统弹窗 — macOS API 限制，无纯"检查"API。deferred，pre-existing
- [ ] [Review][Defer] maskApiKey 对长度 10 的 key 掩码过弱（9/10 字符可见） — 规格设计问题，实际 Anthropic key 100+ 字符。deferred，pre-existing
- [ ] [Review][Defer] PermissionChecker 不可 Mock（无协议抽象） — Story 2.4 复用时需处理。deferred，pre-existing
