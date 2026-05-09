# Story 2.2: 配置系统与分层加载

Status: done

## Story

As a 用户,
I want 所有配置（含 API Key）统一存储在 config.json，支持分层覆盖,
so that 我可以通过一个文件管理所有配置，且环境变量和 CLI 参数可以覆盖文件设置.

## Acceptance Criteria

1. **AC1: config.json 读写**
   - Given ~/.axion/config.json 存在 {"apiKey": "sk-ant-xxx", "maxSteps": 30}
   - When ConfigManager 加载配置
   - Then apiKey 和 maxSteps 正确读取

2. **AC2: 配置文件覆盖默认值**
   - Given ~/.axion/config.json 存在 {"maxSteps": 30}
   - When ConfigManager 加载配置
   - Then maxSteps=30（文件覆盖默认值 20）

3. **AC3: 环境变量覆盖配置文件**
   - Given 环境变量 AXION_MODEL 设置
   - When ConfigManager 加载配置
   - Then model 值来自环境变量（覆盖 config.json）

4. **AC4: CLI 参数优先级最高**
   - Given CLI 参数 --max-steps 10
   - When ConfigManager 加载配置
   - Then maxSteps=10（优先级最高，覆盖环境变量和文件）

5. **AC5: API Key 不泄露**
   - Given API Key 已存储
   - When 运行任何 axion 命令并启用 --verbose
   - Then API Key 不出现在任何终端输出中（NFR9）

6. **AC6: 环境变量 AXION_API_KEY 覆盖文件**
   - Given config.json 含 apiKey，环境变量 AXION_API_KEY 设置
   - When ConfigManager 加载配置
   - Then apiKey 来自环境变量（覆盖 config.json）

## Tasks / Subtasks

- [ ] Task 1: 创建 ConfigManager 分层配置加载器 (AC: #1, #2, #3, #4, #6)
  - [ ] 1.1 创建 `Sources/AxionCLI/Config/ConfigManager.swift`
  - [ ] 1.2 实现 `static let configDirectory` — `~/.axion/`（懒加载，首次访问时创建）
  - [ ] 1.3 实现 `static let configFilePath` — `~/.axion/config.json`
  - [ ] 1.4 实现 `loadConfig(cliOverrides:) async throws -> AxionConfig` 方法：
    - 第 1 层：`AxionConfig.default` 作为基础
    - 第 2 层：读取 `~/.axion/config.json`（文件不存在则跳过，JSON 解析失败用默认值并记录 warning）
    - 第 3 层：读取环境变量 `AXION_MODEL`, `AXION_MAX_STEPS`, `AXION_MAX_BATCHES`, `AXION_MAX_REPLAN_RETRIES`, `AXION_TRACE_ENABLED`, `AXION_SHARED_SEAT_MODE`, `AXION_API_KEY`
    - 第 4 层：应用 CLI 参数覆盖（从 RunCommand 传入的值）
  - [ ] 1.5 实现 `saveConfigFile(_ config: AxionConfig) throws` — 保存完整配置（含 apiKey）到 config.json
  - [ ] 1.6 实现 `ensureConfigDirectory() throws` — 创建 `~/.axion/` 目录

- [ ] Task 2: 编写 ConfigManager 单元测试 (AC: #1, #2, #3, #4, #5, #6)
  - [ ] 2.1 创建 `Tests/AxionCLITests/Config/ConfigManagerTests.swift`
  - [ ] 2.2 测试 `test_loadConfig_noFileNoEnv_returnsDefault()` — 无文件无环境变量返回默认值
  - [ ] 2.3 测试 `test_loadConfig_fileOverridesDefault()` — config.json 覆盖默认值
  - [ ] 2.4 测试 `test_loadConfig_envOverridesFile()` — 环境变量覆盖 config.json
  - [ ] 2.5 测试 `test_loadConfig_cliOverridesEnv()` — CLI 参数覆盖环境变量
  - [ ] 2.6 测试 `test_loadConfig_apiKeyFromFile()` — API Key 从 config.json 读取
  - [ ] 2.7 测试 `test_loadConfig_apiKeyEnvOverridesFile()` — 环境变量 AXION_API_KEY 优先
  - [ ] 2.8 测试 `test_loadConfig_invalidJsonFile_fallsBackToDefault()` — 无效 JSON 使用默认值
  - [ ] 2.9 测试 `test_saveConfigFile_includesApiKey()` — 保存的 JSON 含 apiKey
  - [ ] 2.10 测试使用临时目录（`NSTemporaryDirectory`）隔离文件操作

- [ ] Task 3: 运行全部单元测试确认无回归
  - [ ] 3.1 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionCoreTests" --filter "AxionCLITests"` 确认所有测试通过

## Dev Notes

### 核心目标

这是 Epic 2 的第二个 Story。Story 2.1（CLI 入口与 ArgumentParser 骨架）已完成，CLI 已有 `run`/`setup`/`doctor` 三个子命令骨架。本 Story 实现配置系统的核心：ConfigManager（分层配置加载）。API Key 与其他配置统一存储在 config.json，不再使用 Keychain。Story 2.3（axion setup）和 Story 2.4（axion doctor）将依赖 ConfigManager。

### 关键架构决策

**D1: API Key 存储 — config.json（文件权限 0o600）**
- API Key 与其他配置统一存储在 `~/.axion/config.json`
- 文件权限 0o600（仅用户可读写）
- 环境变量 `AXION_API_KEY` 作为覆盖机制（CI/脚本场景）

**D4: 配置系统 — 分层覆盖（后者覆盖前者）**
1. 默认值（`AxionConfig.default`）
2. `~/.axion/config.json`（文件覆盖默认值）
3. 环境变量 `AXION_*`（覆盖 config.json）
4. CLI 参数 `--max-steps` 等（最高优先级）

### ConfigManager 实现指南

**配置文件路径：**
- 目录：`~/.axion/`（由 `NSHomeDirectory()` + "/.axion" 构建）
- 文件：`~/.axion/config.json`

**环境变量映射：**

| 环境变量 | AxionConfig 字段 | 类型 |
|----------|-----------------|------|
| `AXION_API_KEY` | apiKey | String |
| `AXION_MODEL` | model | String |
| `AXION_MAX_STEPS` | maxSteps | Int |
| `AXION_MAX_BATCHES` | maxBatches | Int |
| `AXION_MAX_REPLAN_RETRIES` | maxReplanRetries | Int |
| `AXION_TRACE_ENABLED` | traceEnabled | Bool |
| `AXION_SHARED_SEAT_MODE` | sharedSeatMode | Bool |

**loadConfig 方法签名：**

```swift
struct ConfigManager {
    /// 分层加载配置：默认值 → config.json → 环境变量 → CLI 覆盖
    /// - Parameter cliOverrides: 从 RunCommand 解析的 CLI 参数
    /// - Returns: 合并后的完整配置（含 API Key）
    static func loadConfig(
        cliOverrides: CLIOverrides? = nil
    ) async throws -> AxionConfig
}

/// CLI 参数覆盖值（从 RunCommand 映射）
struct CLIOverrides {
    var maxSteps: Int?
    var maxBatches: Int?
}
```

**配置文件读写：**
- 读取：`FileManager.default.contents(atPath:)` + `JSONDecoder().decode(AxionConfig.self, from:)`
- 写入：`JSONEncoder().encode(config)` + `FileManager.default.createFile(atPath:configPath:attributes:)`
- 文件权限：`0o600`（仅用户可读写）
- 目录创建：`FileManager.default.createDirectory(atPath:withIntermediateDirectories:attributes:)`

### 测试策略

**ConfigManager 测试：**
- 文件操作使用临时目录（`NSTemporaryDirectory` + UUID）
- 环境变量使用 `setenv`/`unsetenv`（测试后清理）
- 临时目录在测试 tearDown 中清理
- 不依赖真实 `~/.axion/config.json`

### 现有代码状态（必须了解）

**AxionConfig（已存在于 AxionCore/Models/AxionConfig.swift）：**
- `AxionConfig` struct，Codable + Equatable + Sendable
- `CodingKeys` 包含 apiKey（可编解码）
- `static let default` 提供所有默认值

**ConfigKeys（已存在于 AxionCore/Constants/ConfigKeys.swift）：**
- 已定义 `apiKey`, `model`, `maxSteps` 等常量

**AxionError（已存在于 AxionCore/Errors/AxionError.swift）：**
- 已有 `.configError(reason: String)` case
- 配置文件错误使用此 case

**RunCommand（已存在于 AxionCLI/Commands/RunCommand.swift）：**
- 已声明 `maxSteps`, `maxBatches`, `allowForeground`, `verbose` 等参数
- **本 Story 不修改 RunCommand**（`run()` 仍然是 placeholder）

**Package.swift：**
- AxionCLI 已依赖 AxionCore 和 ArgumentParser
- **本 Story 不修改 Package.swift**

### 模块依赖规则

```
AxionCLI/Config/ConfigManager.swift 可以 import:
  - Foundation (系统)
  - AxionCore (项目内部) — 使用 AxionConfig, ConfigKeys, AxionError

禁止 import:
  - AxionHelper (进程隔离)
  - ArgumentParser (ConfigManager 不直接依赖 CLI 框架)
  - Security (不再使用 Keychain)
```

### import 顺序

```swift
// ConfigManager.swift
import Foundation

import AxionCore
```

### 目录结构

```
Sources/AxionCLI/Config/
  ConfigManager.swift     # 分层配置加载器

Tests/AxionCLITests/Config/     # 测试目录
  ConfigManagerTests.swift      # 测试
```

### 禁止事项（反模式）

- **不得使用 `print()` 输出** — 错误通过 `AxionError.configError` 抛出
- **不得创建新的错误类型** — 使用 `AxionError.configError(reason:)`
- **测试不得读写真实的 `~/.axion/` 目录** — 使用临时目录隔离
- **API Key 绝对不出现在日志、trace 或终端输出中** — NFR9 硬性要求

### 与后续 Story 的关系

- **Story 2.3（axion setup）**：将调用 `ConfigManager.saveConfigFile()` 写入配置
- **Story 2.4（axion doctor）**：将调用 `ConfigManager.loadConfig()` 验证配置
- **Epic 3（axion run）**：RunCommand 将调用 `ConfigManager.loadConfig(cliOverrides:)` 加载运行配置
- **本 Story 不修改任何命令文件**（setup/doctor/run 保持 placeholder）

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.2] 原始 Story 定义和 AC
- [Source: _bmad-output/planning-artifacts/architecture.md#D4 配置系统] 分层配置设计
- [Source: _bmad-output/project-context.md#配置系统] 分层配置规则和默认值
- [Source: _bmad-output/project-context.md#模块依赖] AxionCLI 依赖规则
- [Source: Sources/AxionCore/Models/AxionConfig.swift] AxionConfig 模型
- [Source: Sources/AxionCore/Constants/ConfigKeys.swift] 配置键常量
- [Source: Sources/AxionCore/Errors/AxionError.swift] 统一错误类型

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
