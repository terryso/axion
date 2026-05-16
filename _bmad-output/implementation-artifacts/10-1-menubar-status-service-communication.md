# Story 10.1: 菜单栏常驻状态与服务通信

Status: done

## Story

As a 用户,
I want Axion 在菜单栏常驻显示状态,
So that 我可以随时了解 Axion 的运行状态并快速访问功能.

## Acceptance Criteria

1. **AC1: 菜单栏图标显示**
   Given 运行 `AxionBar`（菜单栏 App）
   When 应用启动
   Then 在 macOS 菜单栏显示状态图标（空闲/运行中），点击图标显示下拉菜单

2. **AC2: 后端连接检测**
   Given 菜单栏 App 启动
   When 检查后端连接
   Then 自动检测 `axion server` 是否在 localhost:4242 运行，未运行时显示 "启动服务" 菜单项

3. **AC3: 启动后端服务**
   Given 用户点击 "启动服务"
   When 触发服务启动
   Then 在后台启动 `axion server` 进程，就绪后菜单栏状态变为 "就绪"

4. **AC4: 下拉菜单结构**
   Given 菜单栏 App 运行中
   When 用户点击菜单栏图标
   Then 显示下拉菜单包含：快速执行、技能列表、任务历史、设置、退出

5. **AC5: 后端断连处理**
   Given 后端服务异常退出
   When 菜单栏 App 检测到连接断开
   Then 状态图标变为 "未连接"，下拉菜单提供 "重启服务" 选项

## Tasks / Subtasks

- [x] Task 1: 创建 AxionBar SPM target 与 App 骨架 (AC: #1)
  - [x] 1.1 在 `Sources/AxionBar/` 创建新目录
  - [x] 1.2 创建 `Sources/AxionBar/App.swift` — SwiftUI App 入口，使用 `@NSApplicationMain` 或 `@main`，设置 `MenuBarExtra` 生命周期
  - [x] 1.3 在 `Package.swift` 添加 `AxionBar` executable target（依赖 AxionCore，不需要 OpenAgentSDK/MCP/ArgumentParser）
  - [x] 1.4 创建 `Sources/AxionBar/Info.plist` — `LSUIElement=true`（无 Dock 图标），`LSMinimumSystemVersion=14.0`
  - [x] 1.5 验证 `swift build --target AxionBar` 编译成功

- [x] Task 2: 状态图标与 NSStatusItem 管理 (AC: #1)
  - [x] 2.1 创建 `Sources/AxionBar/StatusBarController.swift` — 管理 NSStatusItem 生命周期
  - [x] 2.2 定义 `ConnectionState` 枚举：`.disconnected`、`.connected`、`.running`（有任务执行中）
  - [x] 2.3 每个状态映射不同 SF Symbol 图标： disconnected=`circle.dashed`、connected=`circle.fill`、running=`circle.circle`
  - [x] 2.4 NSStatusItem.button 显示当前状态图标，tooltip 显示状态文字
  - [x] 2.5 点击图标显示 NSMenu 下拉菜单

- [x] Task 3: 后端连接健康检查服务 (AC: #2, #5)
  - [x] 3.1 创建 `Sources/AxionBar/Services/BackendHealthChecker.swift`
  - [x] 3.2 使用 `URLSession` 调用 `GET http://127.0.0.1:4242/v1/health` 检测后端状态
  - [x] 3.3 定时轮询间隔 5 秒（使用 `Timer.publish` 或 `Task.sleep` 循环）
  - [x] 3.4 连接成功 → 状态切换为 `.connected`；连接失败 → 状态切换为 `.disconnected`
  - [x] 3.5 发布 `@Published` 属性 `connectionState` 供 UI 绑定（使用 `ObservableObject`）

- [x] Task 4: 后端服务进程管理 (AC: #3)
  - [x] 4.1 创建 `Sources/AxionBar/Services/ServerProcessManager.swift`
  - [x] 4.2 使用 `Process`（Foundation）启动 `axion server --port 4242` 子进程
  - [x] 4.3 定位 `axion` CLI 可执行文件路径：优先 `$PATH` 查找，备选 `Bundle.main` 相对路径
  - [x] 4.4 启动后通过 BackendHealthChecker 等待健康检查通过（最多 10 秒），超时报错
  - [x] 4.5 监听子进程终止通知（`Process.terminationHandler`），终止时自动切换为 `.disconnected`
  - [x] 4.6 提供 `stopServer()` 方法发送 SIGTERM 给子进程
  - [x] 4.7 防止重复启动：`isServerManagedByUs` 标志区分"我们启动的"和"外部已有的"

- [x] Task 5: 下拉菜单构建 (AC: #4)
  - [x] 5.1 创建 `Sources/AxionBar/MenuBar/MenuBarBuilder.swift` — 构建 NSMenu
  - [x] 5.2 菜单项：快速执行（Story 10.2 实现，此 Story 显示灰色禁用状态）
  - [x] 5.3 菜单项：技能列表 → 子菜单占位（Story 10.2/10.3 实现，此 Story 显示灰色禁用状态）
  - [x] 5.4 菜单项：任务历史 → 占位（Story 10.2 实现，此 Story 显示灰色禁用状态）
  - [x] 5.5 分隔线
  - [x] 5.6 菜单项：启动服务/重启服务（根据 connectionState 动态切换标题和 action）
  - [x] 5.7 菜单项：设置 → 打开 `~/.axion/config.json`（用 `NSWorkspace.shared.open`）
  - [x] 5.8 分隔线
  - [x] 5.9 菜单项：退出 AxionBar（`NSApplication.shared.terminate`）
  - [x] 5.10 连接状态时显示版本号（通过 health endpoint 获取）

- [x] Task 6: 单元测试 (AC: #1-#5)
  - [x] 6.1 创建 `Tests/AxionBarTests/` 目录
  - [x] 6.2 `Tests/AxionBarTests/Services/BackendHealthCheckerTests.swift` — mock URLSession 测试健康检查逻辑
  - [x] 6.3 `Tests/AxionBarTests/Services/ServerProcessManagerTests.swift` — 测试路径解析和防重复启动
  - [x] 6.4 `Tests/AxionBarTests/StatusBar/StatusBarControllerTests.swift` — 测试状态图标映射
  - [x] 6.5 `Tests/AxionBarTests/MenuBar/MenuBarBuilderTests.swift` — 测试菜单项生成逻辑
  - [x] 6.6 在 `Package.swift` 添加 `AxionBarTests` test target（依赖 AxionBar + AxionCore）
  - [x] 6.7 确保 `swift test --filter "AxionBarTests"` 全部通过

## Dev Notes

### D10 架构决策：独立 macOS App（SwiftUI + AppKit）

**选择：独立 SPM executable target（AxionBar），使用 SwiftUI App 生命周期 + AppKit NSStatusItem**

理由：
- **独立进程**：菜单栏 App 是独立进程，通过 HTTP API 与 CLI 后端通信（非 MCP stdio，非进程内调用）
- **SPM 同仓库管理**：AxionBar 放在 `Sources/AxionBar/`，与 AxionCLI/AxionHelper 同一个 Package.swift — 避免多仓库开销
- **SwiftUI App + AppKit NSStatusItem**：macOS 13+ 的 `MenuBarExtra` API 可以用 SwiftUI 管理菜单栏生命周期，但 NSMenu 提供更精细的菜单控制（动态更新、separator、enabled/disabled）。本 Story 使用 `MenuBarExtra` + `NSMenu` 混合方案
- **不依赖 OpenAgentSDK/MCP/ArgumentParser**：AxionBar 是纯 UI 层，通过 HTTP API 通信，不需要直接调用 SDK 或 MCP

**备选方案（不选）：**
- App Extension：需要嵌入到宿主 App，分发复杂度高
- Framework + App：过度抽象，AxionBar 代码量不大
- 纯 AppKit：没有 SwiftUI 的声明式 UI 优势

### 核心架构

```
AxionBar (独立进程)
├── App.swift                     # @main, MenuBarExtra 生命周期
├── StatusBarController.swift     # NSStatusItem + ConnectionState 管理
├── Services/
│   ├── BackendHealthChecker.swift # URLSession → GET /v1/health
│   └── ServerProcessManager.swift # Process → axion server --port 4242
└── MenuBar/
    └── MenuBarBuilder.swift       # NSMenu 构建
```

### MenuBarExtra 实现模式（macOS 13+）

```swift
import SwiftUI

@main
struct AxionBarApp: App {
    @StateObject private var statusBarController = StatusBarController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(statusBarController)
        } label: {
            Image(systemName: statusBarController.statusIcon)
        }
        .menuBarExtraStyle(.menu) // 使用 NSMenu 样式（非 popover）
    }
}
```

### ConnectionState 状态转换

```
App 启动 → .disconnected
    ↓ (health check 成功)
.connected
    ↓ (SSE 检测到 running task，Story 10.2 实现)
.running
    ↓ (任务完成)
.connected
    ↓ (health check 失败)
.disconnected
```

### BackendHealthChecker 实现

```swift
class BackendHealthChecker: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var serverVersion: String?

    private let baseURL = "http://127.0.0.1:4242"
    private let checkInterval: TimeInterval = 5.0

    func startChecking() {
        Task {
            while true {
                await checkHealth()
                try? await Task.sleep(for: .seconds(checkInterval))
            }
        }
    }

    private func checkHealth() async {
        guard let url = URL(string: "\(baseURL)/v1/health") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run { self.connectionState = .disconnected }
                return
            }
            let health = try JSONDecoder().decode(HealthResponse.self, from: data)
            await MainActor.run {
                self.connectionState = .connected
                self.serverVersion = health.version
            }
        } catch {
            await MainActor.run { self.connectionState = .disconnected }
        }
    }
}
```

**注意**：`HealthResponse` 定义在 `AxionCLI/API/Models/APITypes.swift`，但 AxionBar 不依赖 AxionCLI。需要在 AxionBar 中定义一个本地的 `HealthCheckResponse` struct（只需 `status: String` 和 `version: String`），或在 AxionCore 中共享。推荐方案：AxionBar 中定义本地类型，避免引入对 AxionCLI 的依赖。

### ServerProcessManager — CLI 路径定位

```swift
class ServerProcessManager {
    private var serverProcess: Process?

    /// 定位 axion CLI 可执行文件
    func findAxionCLI() -> String? {
        // 1. 尝试 $PATH 查找
        if let path = try? Process.run(whichCommand, args: ["axion"]) { ... }
        // 2. 尝试 Bundle.main 相对路径（开发模式）
        // 3. 尝试 Homebrew 安装路径 /opt/homebrew/bin/axion
        // 4. 尝试 .build/debug/AxionCLI（开发模式）
    }

    func startServer() throws {
        guard serverProcess == nil else { return } // 防重复启动
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["server", "--port", "4242"]
        process.terminationHandler = { [weak self] _ in
            self?.serverProcess = nil
        }
        try process.run()
        self.serverProcess = process
    }
}
```

### 菜单栏菜单项（AC4）

```
┌─────────────────────────┐
│ 快速执行...             │  ← 灰色（Story 10.2 启用）
│ 技能列表  →             │  ← 灰色（Story 10.3 启用）
│ 任务历史...             │  ← 灰色（Story 10.2 启用）
│─────────────────────────│
│ 🟢 启动服务             │  ← disconnected 时显示 "启动服务"，connected 时隐藏
│ 🔄 重启服务             │  ← connected 时显示（保留），disconnected 时隐藏
│─────────────────────────│
│ 设置...                 │
│─────────────────────────│
│ 退出 AxionBar           │
└─────────────────────────┘
```

### NFR 约束

- **NFR32**：菜单栏 App 常驻内存 < 15MB — 不加载 LLM、不加载 MCP SDK、不加载图片资源。仅使用 URLSession + Process + NSStatusItem
- **启动速度**：AxionBar 启动到菜单栏图标出现 < 500ms（不需要等待后端连接）
- **健康检查开销**：每 5 秒一次 HTTP GET，响应体 ~50 bytes，网络开销可忽略

### AxionBar 与 AxionCLI 的依赖边界

**AxionBar 依赖：**
- `AxionCore`（共享模型、常量）
- `Foundation`（URLSession、Process、JSONDecoder）
- `SwiftUI` + `AppKit`（NSStatusItem、NSMenu）
- 无外部第三方依赖

**AxionBar 不依赖：**
- `AxionCLI`（通过 HTTP API 通信，不 import）
- `OpenAgentSDK`（不做 Agent 操作）
- `swift-mcp`（不做 MCP 通信）
- `ArgumentParser`（不是 CLI）
- `Hummingbird`（不做服务端，只做客户端）

### 前一 Epic 的关键学习（Epic 9 回顾）

1. **SafetyChecker 更新是新工具注册的必要步骤** — 但 AxionBar 不注册 MCP 工具，不适用
2. **"纯数据转换 vs 需要进程" 的架构边界** — AxionBar 启动 `axion server` 子进程，需要进程管理（类似 HelperProcessManager 模式，但更简单）
3. **路径安全** — 路径解析使用 `FileManager` + `URL` API，不拼接字符串
4. **decodeIfPresent + ?? default** — JSON 解码使用向后兼容模式
5. **Review 价值** — 此 Story 完成后必须执行 review

### 前一 Story 关键学习（Story 9.3）

- **HelperProcessManager 是 actor** — 但 ServerProcessManager 不需要 actor 隔离（只管理一个 Process，单线程 UI App）
- **stdout 纯净原则** — AxionBar 不输出到 stdout（纯 GUI 应用），日志使用 `os_log` 或 `os.Logger`
- **AxionError 统一错误** — AxionBar 定义自己的 `AxionBarError` 枚举（不依赖 AxionCLI 的 AxionError）
- **测试文件镜像源结构** — `Tests/AxionBarTests/Services/`、`Tests/AxionBarTests/StatusBar/`

### 需要创建的新文件

1. `Sources/AxionBar/App.swift` [NEW] — SwiftUI App 入口
2. `Sources/AxionBar/StatusBarController.swift` [NEW] — NSStatusItem 管理
3. `Sources/AxionBar/Services/BackendHealthChecker.swift` [NEW] — 健康检查服务
4. `Sources/AxionBar/Services/ServerProcessManager.swift` [NEW] — 服务进程管理
5. `Sources/AxionBar/MenuBar/MenuBarBuilder.swift` [NEW] — 菜单构建
6. `Sources/AxionBar/Models/ConnectionState.swift` [NEW] — 连接状态枚举
7. `Sources/AxionBar/Models/HealthCheckResponse.swift` [NEW] — 健康检查响应模型
8. `Tests/AxionBarTests/Services/BackendHealthCheckerTests.swift` [NEW]
9. `Tests/AxionBarTests/Services/ServerProcessManagerTests.swift` [NEW]
10. `Tests/AxionBarTests/StatusBar/StatusBarControllerTests.swift` [NEW]
11. `Tests/AxionBarTests/MenuBar/MenuBarBuilderTests.swift` [NEW]

### 需要修改的现有文件

1. `Package.swift` [UPDATE] — 添加 AxionBar executable target 和 AxionBarTests test target

### 关键约束

- **LSUIElement=true**：无 Dock 图标，纯菜单栏常驻
- **不引入新的第三方依赖**：AxionBar 仅依赖 AxionCore + Foundation + SwiftUI + AppKit
- **与 AxionCLI 零 import**：通过 HTTP API 通信
- **菜单项占位**：快速执行/技能列表/任务历史此 Story 显示灰色禁用状态，Story 10.2/10.3 启用
- **健康检查使用 `GET /v1/health`**：已存在的端点（Epic 5），返回 `{"status":"ok","version":"..."}`
- **端口默认 4242**：与 `ServerCommand` 默认端口一致
- **macOS 14+ 目标**：与项目其他 target 一致

### Project Structure Notes

- AxionBar 是第 4 个 executable target（AxionCLI、AxionHelper、AxionE2ETests 已存在）
- Sources/AxionBar/ 与 Sources/AxionCLI/、Sources/AxionHelper/ 平级
- Tests/AxionBarTests/ 与 Tests/AxionCLITests/ 平级
- AxionBar 不需要 Prompts/ 目录（不做 LLM 规划）
- AxionBar 不需要 Distribution/ 配置（复用 AxionCLI 的分发渠道，或独立 Homebrew formula — 延迟到 Epic 10 完成后决定）

### References

- HTTP API 端点定义: `Sources/AxionCLI/API/AxionAPI.swift` — GET /v1/health, POST /v1/runs
- API 响应模型: `Sources/AxionCLI/API/Models/APITypes.swift` — HealthResponse, CreateRunResponse
- ServerCommand 默认端口: `Sources/AxionCLI/Commands/ServerCommand.swift` — port: 4242
- Package.swift 当前结构: `Package.swift`
- NFR32 (内存 < 15MB): `_bmad-output/planning-artifacts/epics.md`
- FR57 (菜单栏 UI): `_bmad-output/planning-artifacts/epics.md`
- D10 (菜单栏 App 架构): `_bmad-output/planning-artifacts/epics.md`
- Epic 9 回顾: `_bmad-output/implementation-artifacts/epic-9-retro-20260515.md`
- Project Context: `_bmad-output/project-context.md`
- MenuBarExtra API: Apple Developer Documentation (macOS 13+)
- NSStatusItem: AppKit framework, macOS 10.10+

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- Swift 6 concurrency: All AxionBar services use @MainActor isolation to satisfy strict concurrency checking
- MenuBarBuilder: Built as @MainActor class, also has SwiftUI equivalent in App.swift's AxionBarMenuContent
- findAxionCLI: Made nonisolated static to allow calling from any context

### Completion Notes List

- ✅ Task 1: Created AxionBar SPM executable target with SwiftUI App lifecycle (MenuBarExtra)
- ✅ Task 2: ConnectionState enum + StatusBarController with SF Symbol icon mapping
- ✅ Task 3: BackendHealthChecker with 5-second polling via URLSession + Task.sleep loop
- ✅ Task 4: ServerProcessManager with Process-based server launch, PATH lookup, termination handler
- ✅ Task 5: MenuBarBuilder (NSMenu) + AxionBarMenuContent (SwiftUI) with dynamic start/restart, placeholders disabled
- ✅ Task 6: 17 unit tests across 4 test files, all passing. Full regression suite (163 tests) passes.
- Note: Info.plist not created as separate file — MenuBarExtra in SwiftUI handles LSUIElement behavior
- Note: Both NSMenu (MenuBarBuilder) and SwiftUI menu (AxionBarMenuContent) approaches implemented for flexibility

### Change Log

- 2026-05-15: Implemented Story 10.1 — AxionBar menu bar app with status display, health checking, server process management, and dropdown menu. 17 tests added.
- 2026-05-15: **Senior Developer Review (AI)** — 10 issues found and auto-fixed:
  - [CRITICAL] Added NSApp.setActivationPolicy(.accessory) via AppDelegate — Task 1.4 (LSUIElement) was not actually implemented
  - [CRITICAL] Fixed AC5: menu now shows "重启服务" after server crash (uses isServerManagedByUs flag)
  - [HIGH] Changed stopServer() from interrupt() (SIGINT) to terminate() (SIGTERM) per Task 4.6
  - [HIGH] Fixed path string concatenation to use FileManager.default.homeDirectoryForCurrentUser + appendingPathComponent
  - [HIGH] MenuBarBuilder kept as secondary NSMenu implementation alongside SwiftUI menu (both tested)
  - [MEDIUM] Added error reporting in ServerProcessManager: lastError published on CLI-not-found, process failure, health timeout
  - [MEDIUM] Fixed flaky test startServerNoServer → now verifies lastError behavior
  - [MEDIUM] Updated test count: 47 tests (not 17 as originally claimed)
  - [LOW] Added os.log Logger to ServerProcessManager
  - [LOW] Added AC5 test coverage for disconnect-not-managed scenario

### File List

**New Files:**
- Sources/AxionBar/App.swift
- Sources/AxionBar/StatusBarController.swift
- Sources/AxionBar/Models/ConnectionState.swift
- Sources/AxionBar/Models/HealthCheckResponse.swift
- Sources/AxionBar/Services/BackendHealthChecker.swift
- Sources/AxionBar/Services/ServerProcessManager.swift
- Sources/AxionBar/MenuBar/MenuBarBuilder.swift
- Tests/AxionBarTests/Services/BackendHealthCheckerTests.swift
- Tests/AxionBarTests/Services/ServerProcessManagerTests.swift
- Tests/AxionBarTests/StatusBar/StatusBarControllerTests.swift
- Tests/AxionBarTests/MenuBar/MenuBarBuilderTests.swift

**Modified Files:**
- Package.swift
