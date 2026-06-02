---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
  - step-04-final-validation
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-axion-gateway-2026-05-29/prd.md
  - _bmad-output/planning-artifacts/architecture.md
project_name: 'axion'
user_name: 'Nick'
date: '2026-05-29'
status: 'complete'
epic: 28
title: 'Gateway 进程基础'
---

# Epic 28: Gateway 进程基础

用户可以用 `axion gateway` 启动包含 HTTP API 的长驻进程，供外部客户端（前端、TG Bot 等）调用。支持 launchd 开机自启、优雅关闭、状态查询。这是 Gateway 的基础层，后续 Epic 29（Telegram）和 Epic 30（自进化）均依赖本 Epic。

**FRs covered:** FR-1.1, FR-1.2, FR-1.3, FR-1.4, FR-1.5, FR-1.6, FR-6.1
**NFRs:** NFR-1, NFR-4
**新增文件:** GatewayCommand.swift, GatewayRunner.swift
**修改文件:** AxionConfig.swift（gateway 字段）, AxionCommand.swift（注册子命令）, DaemonService.swift（复用 plist 逻辑）
**依赖:** 无（基础 Epic）

---

### Story 28.1: Gateway 配置扩展

As a Axion 用户,
I want 在 config.json 中配置 Gateway 相关参数,
So that 我可以自定义 Gateway 行为而无需修改命令行参数.

**Acceptance Criteria:**

**Given** `~/.axion/config.json` 不包含任何 gateway 字段
**When** ConfigManager 加载配置
**Then** 所有 gateway 字段使用默认值（gatewayEnabled=false, curatorIdleHours=2.0, curatorIntervalHours=168.0, taskTimeoutMinutes=10.0, notifyCuratorResults=false）
**And** Codable round-trip 测试通过

**Given** `~/.axion/config.json` 包含 `{"gatewayCuratorIdleHours": 4.0}`
**When** ConfigManager 加载配置
**Then** `curatorIdleHours` 为 4.0，其余 gateway 字段保持默认值

### Story 28.2: GatewayRunner Actor 与 HTTP API 复用

As a Axion 用户,
I want 用 `axion gateway` 启动包含 HTTP API 的长驻进程,
So that 外部客户端可以通过 HTTP API 与 Gateway 交互，无需单独运行 `axion server`.

**Acceptance Criteria:**

**Given** GatewayRunner 未运行
**When** 用户执行 `axion gateway`
**Then** GatewayRunner actor 启动，内部启动 AxionAPI HTTP server（复用现有路由）
**And** HTTP 客户端通过 `localhost:4242` 正常访问（GET /v1/health 返回 200）

**Given** GatewayRunner 正在运行
**When** 进程收到 SIGTERM 信号
**Then** 停止接受新任务，等待运行中任务完成（最多 30 秒），然后退出
**And** HTTP API 返回 503（服务不可用）直到进程退出

**Given** GatewayRunner 正在运行（无运行中任务）
**When** 进程收到 SIGINT（Ctrl-C）
**Then** 立即优雅关闭

### Story 28.3: launchd 守护进程管理

As a Axion 用户,
I want 用 `axion gateway install` 注册开机自启守护进程,
So that Gateway 在 Mac 开机时自动运行，崩溃后自动重启.

**Acceptance Criteria:**

**Given** Gateway 未安装为守护进程
**When** 用户执行 `axion gateway install`
**Then** 生成 `~/Library/LaunchAgents/dev.axion.gateway.plist`（label: dev.axion.gateway）
**And** plist 包含 RunAtLoad=true, KeepAlive(Crashed=true), ThrottleInterval=10
**And** 日志输出到 `~/.axion/gateway.log` + `~/.axion/gateway.err.log`
**And** launchctl bootstrap 成功

**Given** Gateway 已安装为守护进程
**When** 用户执行 `axion gateway uninstall`
**Then** launchctl bootout 成功，plist 文件删除，进程停止

**Given** `AXION_BIN` 环境变量设置为 `/usr/local/bin/axion`
**When** 用户执行 `axion gateway install`
**Then** plist 中 ProgramArguments 使用 `AXION_BIN` 路径

### Story 28.4: Gateway 状态查询

As a Axion 用户,
I want 用 `axion gateway status` 查看 Gateway 运行状态,
So that 我可以确认 Gateway 是否正常运行、上次审查和 Curator 时间.

**Acceptance Criteria:**

**Given** Gateway 守护进程已安装且正在运行
**When** 用户执行 `axion gateway status`
**Then** 输出包含：进程 PID、运行状态（running/stopped/not_installed）、日志路径
**And** 预留字段：TG 连接状态、上次审查时间、上次 curator 时间（后续 Epic 填充）

**Given** Gateway 守护进程未安装
**When** 用户执行 `axion gateway status`
**Then** 输出 `status: not_installed`

**Given** Gateway 守护进程已安装但已停止
**When** 用户执行 `axion gateway status`
**Then** 输出 `status: stopped`，显示上次已知 PID

---

## 实现参考

### 复用组件

| 现有文件 | 复用方式 |
|---------|---------|
| `Sources/AxionCLI/Services/DaemonService.swift` | plist 生成 + launchctl 操作。当前 `daemonLabel` 硬编码为 `"dev.axion.server"`，Gateway 需参数化为接受 label/plistPath 参数，或创建 `GatewayDaemonService` 子类 |
| `Sources/AxionCLI/Commands/DaemonCommand.swift` | 子命令结构参考（install/status/uninstall 三件套）。`GatewayCommand` 采用相同模式 |
| `Sources/AxionCLI/Commands/ServerCommand.swift` | HTTP server 启动逻辑。`GatewayCommand.run()` 需复用其中 `AgentHTTPServer` 创建和 `runHandler` 配置 |
| `Sources/AxionCLI/API/AxionAPI.swift` | `registerCustomRoutes()` 需在 Gateway 进程内调用，确保 HTTP API 功能正常 |
| `Sources/AxionCore/Models/AxionConfig.swift` | Codable 模型，新增 gateway 字段使用 `decodeIfPresent` 模式（参考现有 curator 字段实现） |
| `Sources/AxionCLI/Services/AxionRuntime.swift` | `AxionRuntime` actor — `execute()` 和 `run()` 方法是任务执行的入口。GatewayRunner 持有一个共享实例 |

### AxionConfig 新增字段清单

```swift
// 以下字段全部使用 decodeIfPresent，Optional 类型
var gatewayEnabled: Bool?                  // 默认 false，控制 Gateway 是否启动
var gatewayCuratorIdleHours: Double?       // 默认 2.0，Curator 空闲触发阈值
var gatewayCuratorIntervalHours: Double?   // 默认 168.0（7 天），Curator 运行间隔
var gatewayTaskTimeoutMinutes: Double?     // 默认 10.0，任务超时时间
var gatewayNotifyCuratorResults: Bool?     // 默认 false，是否推送审查结果到 TG
```

注：`gatewayTelegramBotToken` 和 `gatewayTelegramAllowedUsers` 不写入 config.json，通过环境变量 `AXION_TELEGRAM_BOT_TOKEN` 和 `AXION_TELEGRAM_ALLOWED_USERS` 传入。

### launchd plist 规格

与现有 `dev.axion.server` plist 的差异：
- Label: `dev.axion.gateway`（不是 `dev.axion.server`）
- Plist 路径: `~/Library/LaunchAgents/dev.axion.gateway.plist`
- ProgramArguments: `[binPath, "gateway", "start"]`
- 日志: `~/.axion/gateway.log` + `~/.axion/gateway.err.log`
- 现有 `KeepAlive` 为 `<true/>`（无限重启），Gateway 改为 `KeepAlive(Crashed=true)`（仅崩溃重启）
- 环境变量传递: `AXION_TELEGRAM_BOT_TOKEN`, `AXION_TELEGRAM_ALLOWED_USERS` 需写入 plist EnvironmentVariables

### DaemonService 参数化策略

建议让 `DaemonService` 支持参数化，而非创建新类：

```swift
// 当前 DaemonService 硬编码
static let daemonLabel = "dev.axion.server"

// 改为 init 参数
init(label: String = "dev.axion.server",
     plistPath: String? = nil,
     logFileName: String = "server.log",
     ...)
```

这样 Gateway 和现有 daemon 共享同一个 `DaemonService`，只是传入不同的 label 和日志文件名。

### GatewayCommand 子命令结构

```swift
struct GatewayCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "gateway",
        abstract: "管理 Axion Gateway 长驻进程",
        subcommands: [
            GatewayStartCommand.self,   // 前台启动（开发调试用）
            GatewayInstallCommand.self, // 注册 launchd 守护进程
            GatewayStatusCommand.self,  // 查看状态
            GatewayUninstallCommand.self // 卸载
        ],
        defaultSubcommand: GatewayStartCommand.self
    )
}
```

### 环境变量

| 变量 | 用途 | 必填 |
|------|------|------|
| `AXION_TELEGRAM_BOT_TOKEN` | TG Bot token | 启动 TG 时必填 |
| `AXION_TELEGRAM_ALLOWED_USERS` | 白名单用户 ID（逗号分隔） | 启动 TG 时必填 |
| `AXION_BIN` | launchd plist 中的可执行文件路径 | install 时可选（不设则自动检测） |

### 文件位置

| 新增/修改文件 | 目录 | 说明 |
|-------------|------|------|
| `GatewayCommand.swift` | `Sources/AxionCLI/Commands/` | CLI 入口（start/install/status/uninstall） |
| `GatewayRunner.swift` | `Sources/AxionCLI/Services/` | Actor 编排器（启停、信号处理、HTTP API + TG + 调度器集成） |
| `AxionConfig.swift` | `Sources/AxionCore/Models/` | 新增 gateway 配置字段 |
| `AxionCommand.swift` | `Sources/AxionCLI/Commands/` | 注册 gateway 子命令 |
| `DaemonService.swift` | `Sources/AxionCLI/Services/` | 参数化 label/logPath 以支持 Gateway plist |
