# Story 10.2: 任务管理与实时状态面板

Status: done

## Story

As a 用户,
I want 从菜单栏查看和管理任务执行状态,
So that 我不需要切换到终端就能了解自动化任务的进展.

## Acceptance Criteria

1. **AC1: 快速执行任务**
   Given 菜单栏 App 和后端服务均运行
   When 用户点击 "快速执行"
   Then 弹出输入框，用户输入自然语言任务描述后提交执行

2. **AC2: 任务执行中状态**
   Given 任务正在执行
   When 查看菜单栏状态
   Then 状态图标显示执行中动画，下拉菜单显示当前任务名称和进度（步骤 N/M）

3. **AC3: 实时日志面板**
   Given 用户点击正在执行的任务
   When 查看详情
   Then 弹出面板显示实时日志流：步骤描述、工具调用、执行结果（通过 SSE 事件流获取）

4. **AC4: 完成通知**
   Given 任务执行完成
   When 查看结果
   Then 菜单栏弹出通知（macOS native notification）：任务完成/失败 + 摘要

5. **AC5: 任务历史**
   Given 用户点击 "任务历史"
   When 查看历史
   Then 显示最近 20 条任务记录，每条包含任务描述、状态、执行时间

## Tasks / Subtasks

- [x] Task 1: 定义 AxionBar 本地 API 模型 (AC: #1-#5)
  - [x] 1.1 创建 `Sources/AxionBar/Models/RunModels.swift` — 本地 API 请求/响应模型，与 AxionCLI 的 APITypes 解耦
  - [x] 1.2 定义 `BarCreateRunRequest`（task 字段）、`BarCreateRunResponse`（run_id, status）
  - [x] 1.3 定义 `BarRunStatusResponse`（run_id, status, task, total_steps, duration_ms, replan_count, steps）
  - [x] 1.4 定义 `BarStepSummary`（index, tool, purpose, success）
  - [x] 1.5 定义 SSE 事件数据模型：`BarStepStartedData`、`BarStepCompletedData`、`BarRunCompletedData`
  - [x] 1.6 所有 CodingKeys 使用 snake_case（与后端 API 一致）

- [x] Task 2: 实现 TaskSubmissionService — 任务提交服务 (AC: #1)
  - [x] 2.1 创建 `Sources/AxionBar/Services/TaskSubmissionService.swift`
  - [x] 2.2 使用 URLSession `POST /v1/runs` 提交任务，body 为 `{"task": "用户描述"}`
  - [x] 2.3 返回 `run_id` 用于后续状态追踪和 SSE 订阅
  - [x] 2.4 处理错误：后端未连接、HTTP 非 202/200、响应解析失败

- [x] Task 3: 实现 SSEEventClient — 实时事件流客户端 (AC: #3)
  - [x] 3.1 创建 `Sources/AxionBar/Services/SSEEventClient.swift`
  - [x] 3.2 使用 URLSession 连接 `GET /v1/runs/{runId}/events`，逐行解析 SSE 格式
  - [x] 3.3 解析 `event:` 和 `data:` 行，按类型解码为对应模型
  - [x] 3.4 通过 `AsyncStream<BarSSEEvent>` 发布解析后的事件供 UI 消费
  - [x] 3.5 处理连接断开、重连和清理

- [x] Task 4: 实现 RunHistoryService — 历史查询服务 (AC: #5)
  - [x] 4.1 创建 `Sources/AxionBar/Services/RunHistoryService.swift`
  - [x] 4.2 使用 `GET /v1/runs` 获取最近 20 条任务记录
  - [x] 4.3 注意：如果当前 API 不支持列表查询，需要在后端添加 `GET /v1/runs` 端点
  - [x] 4.4 返回 `[BarRunStatusResponse]` 供 UI 展示

- [x] Task 5: 实现 QuickRunView — 快速执行输入窗口 (AC: #1)
  - [x] 5.1 创建 `Sources/AxionBar/Views/QuickRunWindow.swift`
  - [x] 5.2 实现 NSWindow + SwiftUI hosting：包含文本输入框和提交按钮
  - [x] 5.3 输入框使用 NSTextField 或 SwiftUI TextField，支持多行输入
  - [x] 5.4 提交后调用 TaskSubmissionService，成功后关闭窗口并更新 StatusBarController
  - [x] 5.5 连接状态为 disconnected 时，提示用户先启动服务

- [x] Task 6: 实现 TaskDetailPanel — 任务详情面板 (AC: #3)
  - [x] 6.1 创建 `Sources/AxionBar/Views/TaskDetailPanel.swift`
  - [x] 6.2 实现 SwiftUI 窗口：显示任务名称、实时步骤日志流
  - [x] 6.3 订阅 SSEEventClient 的 AsyncStream，实时追加步骤事件到日志列表
  - [x] 6.4 每个步骤显示：工具名、目的描述、执行结果（✓/✗）、耗时
  - [x] 6.5 任务完成后显示汇总信息（总步数、耗时、重规划次数）

- [x] Task 7: 实现 RunHistoryView — 任务历史窗口 (AC: #5)
  - [x] 7.1 创建 `Sources/AxionBar/Views/RunHistoryWindow.swift`
  - [x] 7.2 实现 SwiftUI 窗口：列表显示最近 20 条任务
  - [x] 7.3 每条记录显示：任务描述（截断）、状态（颜色标记）、执行时间
  - [x] 7.4 点击历史任务可打开详情面板（调用 GET /v1/runs/{runId} 获取完整数据）

- [x] Task 8: 更新 StatusBarController — 运行中状态管理 (AC: #2)
  - [x] 8.1 添加 `@Published var currentRunId: String?` 和 `@Published var currentTask: String?`
  - [x] 8.2 添加 `@Published var currentStep: Int` 和 `@Published var totalSteps: Int`
  - [x] 8.3 任务提交成功后设置 running 状态（`connectionState = .running`）
  - [x] 8.4 通过 SSEEventClient 更新步骤进度
  - [x] 8.5 任务完成后恢复 connected 状态
  - [x] 8.6 管理 SSEEventClient 生命周期：任务开始时创建订阅，完成/取消时清理

- [x] Task 9: 启用菜单项与 macOS 通知 (AC: #1, #4)
  - [x] 9.1 更新 `App.swift` 的 `AxionBarMenuContent`：启用 "快速执行" 按钮
  - [x] 9.2 更新 `App.swift`：启用 "任务历史" 按钮
  - [x] 9.3 运行中时在菜单中显示当前任务名称和进度（步骤 N/M）
  - [x] 9.4 点击运行中的任务项时打开 TaskDetailPanel
  - [x] 9.5 更新 `MenuBarBuilder.swift`：同步启用对应菜单项
  - [x] 9.6 任务完成时发送 macOS native notification（UNUserNotificationCenter）

- [x] Task 10: 后端 API 补充（如需要） (AC: #5)
  - [x] 10.1 检查 `GET /v1/runs` 列表端点是否存在
  - [x] 10.2 如不存在，在 `Sources/AxionCLI/API/AxionAPI.swift` 添加 `GET /v1/runs` 端点
  - [x] 10.3 在 `RunTracker` 中添加 `listRuns(limit:)` 方法，返回最近 N 条记录
  - [x] 10.4 端点支持 `?limit=20` 查询参数

- [x] Task 11: 单元测试 (AC: #1-#5)
  - [x] 11.1 创建 `Tests/AxionBarTests/Models/RunModelsTests.swift` — Codable round-trip 测试
  - [x] 11.2 创建 `Tests/AxionBarTests/Services/TaskSubmissionServiceTests.swift` — mock URLSession 测试任务提交
  - [x] 11.3 创建 `Tests/AxionBarTests/Services/SSEEventClientTests.swift` — SSE 解析逻辑测试
  - [x] 11.4 创建 `Tests/AxionBarTests/Services/RunHistoryServiceTests.swift` — 历史查询测试
  - [x] 11.5 更新 `Tests/AxionBarTests/StatusBar/StatusBarControllerTests.swift` — 测试 running 状态转换
  - [x] 11.6 确保 `swift test --filter "AxionBarTests"` 全部通过

## Dev Notes

### 与 Story 10.1 的关系

Story 10.1 已完成：
- AxionBar 基础架构（SPM target、MenuBarExtra、StatusBarController）
- BackendHealthChecker（5 秒轮询 GET /v1/health）
- ServerProcessManager（启动/停止 axion server）
- 下拉菜单结构（"快速执行"、"技能列表"、"任务历史" 当前灰色禁用）
- ConnectionState 枚举（.disconnected / .connected / .running）

**本 Story 启用已占位的菜单项**，添加任务管理功能。

### 核心 API 端点（已存在于 AxionCLI）

| 端点 | 方法 | 用途 | 响应模型 |
|------|------|------|----------|
| `/v1/runs` | POST | 提交任务 | `CreateRunResponse { run_id, status }` |
| `/v1/runs/{runId}` | GET | 查询状态 | `RunStatusResponse { run_id, status, task, ... }` |
| `/v1/runs/{runId}/events` | GET (SSE) | 实时事件流 | SSE event stream |
| `/v1/health` | GET | 健康检查 | `HealthResponse { status, version }` |

**可能需要新增**：`GET /v1/runs` — 列表端点（用于任务历史查询）。检查 `Sources/AxionCLI/API/AxionAPI.swift` 确认是否已存在。如不存在，需要 Task 10 添加。

### SSE 事件格式（后端已实现）

后端 SSE 端点 `GET /v1/runs/{runId}/events` 发送以下事件：

```
event: step_started
data: {"step_index":0,"tool":"launch_app"}
id: 1

event: step_completed
data: {"step_index":0,"tool":"launch_app","purpose":"启动 Calculator","success":true,"duration_ms":320}
id: 2

event: run_completed
data: {"run_id":"20260515-abc123","final_status":"done","total_steps":3,"duration_ms":8200,"replan_count":0}
id: 3
```

AxionBar 需要解析此格式。使用 URLSession 的 bytes stream 逐行读取。

### AxionBar 本地模型 vs AxionCLI API 模型

**关键决策：AxionBar 定义自己的 API 模型，不 import AxionCLI。**

理由（与 Story 10.1 一致）：
- AxionBar 不依赖 AxionCLI（两者通过 HTTP API 通信）
- AxionBar 仅依赖 AxionCore
- AxionBar 的模型只需包含 UI 需要的字段子集
- CodingKeys 使用 snake_case（与后端 JSON 一致），但 Swift 属性名使用 camelCase

模型命名约定：`Bar` 前缀（如 `BarRunStatusResponse`）与 AxionCLI 的 `RunStatusResponse` 区分。

### QuickRunWindow 实现方案

使用 NSPanel + SwiftUI hosting，而非纯 SwiftUI WindowGroup：

```swift
// NSPanel 可以设置为 floating utility window
let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
    styleMask: [.titled, .closable, .fullSizeContentView],
    backing: .buffered, defer: false
)
panel.isFloatingPanel = true
panel.level = .floating
panel.contentView = NSHostingView(rootView: QuickRunInputView(...))
panel.center()
panel.makeKeyAndOrderFront(nil)
```

原因：MenuBarExtra 应用中 WindowGroup 行为不可靠，NSPanel 更可控。

### TaskDetailPanel 实现方案

使用 NSWindow + SwiftUI hosting，订阅 SSE 事件流：

```swift
// 任务详情面板 - 独立窗口
let detailWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
    styleMask: [.titled, .closable, .resizable, .miniaturizable],
    backing: .buffered, defer: false
)
detailWindow.contentView = NSHostingView(rootView: TaskDetailView(runId: runId))
```

SSE 事件通过 `@StateObject` 持有的 SSEEventClient 的 AsyncStream 订阅。

### macOS Native Notification

使用 `UserNotifications` 框架：

```swift
import UserNotifications

func sendNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    
    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil  // 立即发送
    )
    
    UNUserNotificationCenter.current().add(request)
}
```

注意：需要请求通知权限。在 App 启动时调用 `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])`。

### 状态转换扩展

Story 10.1 定义的 ConnectionState 状态转换需要扩展：

```
.connected → (提交任务成功) → .running
.running → (收到 run_completed SSE 事件) → .connected
.running → (SSE 连接断开) → .connected (回退)
```

StatusBarController 需要：
- `currentRunId: String?` — 当前运行任务的 ID
- `currentTask: String?` — 当前任务描述
- `stepProgress: String?` — 进度文本（"步骤 2/5"）

### 菜单结构变化

```
┌─────────────────────────────────────┐
│ ▶ 快速执行...                       │  ← AC1: 启用，打开输入窗口
│ 技能列表  →                         │  ← 仍灰色（Story 10.3）
│─────────────────────────────────────│
│ ▶ 运行中: "打开计算器" 步骤 2/5     │  ← AC2: running 时显示，点击打开详情
│─────────────────────────────────────│  ← running 时才有此区域
│ ▶ 任务历史...                       │  ← AC5: 启用，打开历史窗口
│─────────────────────────────────────│
│ 启动服务 / 重启服务                  │
│─────────────────────────────────────│
│ 设置...                             │
│ Axion v1.2.3                        │
│─────────────────────────────────────│
│ 退出 AxionBar                       │
└─────────────────────────────────────┘
```

### NFR 约束

- **NFR32**：菜单栏 App 常驻内存 < 15MB — SSE 连接不增加显著内存
- SSE 客户端使用 URLSession stream，不缓存完整事件历史
- 任务详情面板关闭时清理 SSE 连接
- 历史列表最多缓存 20 条记录

### 前一 Story 关键学习（Story 10.1）

1. **AxionBar 依赖边界** — 仅依赖 AxionCore + Foundation + SwiftUI + AppKit，不引入第三方依赖
2. **NSApp.setActivationPolicy(.accessory)** — 已在 AppDelegate 中设置，无 Dock 图标
3. **@MainActor 隔离** — 所有 AxionBar 服务使用 @MainActor 隔离
4. **两套菜单实现** — MenuBarBuilder（NSMenu）和 AxionBarMenuContent（SwiftUI）并存，本 Story 需要同时更新两者
5. **健康检查轮询间隔 5 秒** — BackendHealthChecker 已有，不需要修改
6. **URLSession.shared** — 直接使用共享 URLSession，不需要自定义配置
7. **路径使用 FileManager + URL** — 不拼接字符串路径
8. **decodeIfPresent + ?? default** — JSON 解码使用向后兼容模式
9. **os_log/os.Logger** — 日志使用系统日志框架，不使用 print()
10. **stdout 纯净** — AxionBar 不输出到 stdout

### 需要创建的新文件

1. `Sources/AxionBar/Models/RunModels.swift` [NEW] — 本地 API 模型
2. `Sources/AxionBar/Services/TaskSubmissionService.swift` [NEW] — 任务提交
3. `Sources/AxionBar/Services/SSEEventClient.swift` [NEW] — SSE 客户端
4. `Sources/AxionBar/Services/RunHistoryService.swift` [NEW] — 历史查询
5. `Sources/AxionBar/Views/QuickRunWindow.swift` [NEW] — 快速执行窗口
6. `Sources/AxionBar/Views/TaskDetailPanel.swift` [NEW] — 任务详情面板
7. `Sources/AxionBar/Views/RunHistoryWindow.swift` [NEW] — 历史窗口
8. `Tests/AxionBarTests/Models/RunModelsTests.swift` [NEW] — 模型测试
9. `Tests/AxionBarTests/Services/TaskSubmissionServiceTests.swift` [NEW]
10. `Tests/AxionBarTests/Services/SSEEventClientTests.swift` [NEW]
11. `Tests/AxionBarTests/Services/RunHistoryServiceTests.swift` [NEW]

### 需要修改的现有文件

1. `Sources/AxionBar/StatusBarController.swift` [UPDATE] — 添加 running 任务状态管理
2. `Sources/AxionBar/App.swift` [UPDATE] — 启用菜单项、添加通知权限请求
3. `Sources/AxionBar/MenuBar/MenuBarBuilder.swift` [UPDATE] — 启用菜单项
4. `Sources/AxionBar/Models/ConnectionState.swift` [UPDATE] — 可能需要扩展（检查 .running 转换逻辑）
5. `Package.swift` [UPDATE] — 可能需要添加 UserNotifications 框架依赖
6. `Tests/AxionBarTests/StatusBar/StatusBarControllerTests.swift` [UPDATE] — 测试 running 状态

### 可能需要修改的 AxionCLI 文件（Task 10）

1. `Sources/AxionCLI/API/AxionAPI.swift` [UPDATE] — 添加 GET /v1/runs 列表端点
2. `Sources/AxionCLI/API/RunTracker.swift` [UPDATE] — 添加 listRuns 方法
3. `Sources/AxionCLI/API/Models/APITypes.swift` [UPDATE] — 添加 RunListResponse 模型

### 关键约束

- **不引入新的第三方依赖**：SSE 客户端使用 URLSession 原生实现，不使用第三方 SSE 库
- **AxionBar 不 import AxionCLI**：API 模型在 AxionBar 中本地定义
- **两套菜单同步更新**：MenuBarBuilder 和 AxionBarMenuContent 需要同步变更
- **端口默认 4242**：与 Story 10.1 一致
- **macOS 14+ 目标**：与项目其他 target 一致
- **swift-mcp 依赖不需要**：AxionBar 通过 HTTP 通信，不做 MCP

### Project Structure Notes

- 新增 `Sources/AxionBar/Views/` 目录（存放 SwiftUI 窗口视图）
- `Sources/AxionBar/Models/` 扩展（RunModels.swift）
- `Sources/AxionBar/Services/` 扩展（3 个新服务）
- `Tests/AxionBarTests/` 扩展（新增子目录和测试文件）

### References

- Story 10.1 实现: `_bmad-output/implementation-artifacts/10-1-menubar-status-service-communication.md`
- HTTP API 端点定义: `Sources/AxionCLI/API/AxionAPI.swift`
- API 响应模型: `Sources/AxionCLI/API/Models/APITypes.swift`
- SSE EventBroadcaster: `Sources/AxionCLI/API/EventBroadcaster.swift`
- RunTracker: `Sources/AxionCLI/API/RunTracker.swift`
- StatusBarController: `Sources/AxionBar/StatusBarController.swift`
- App.swift: `Sources/AxionBar/App.swift`
- MenuBarBuilder: `Sources/AxionBar/MenuBar/MenuBarBuilder.swift`
- ConnectionState: `Sources/AxionBar/Models/ConnectionState.swift`
- Package.swift: `Package.swift`
- NFR32 (内存 < 15MB): `_bmad-output/planning-artifacts/epics.md`
- FR58 (任务管理面板): `_bmad-output/planning-artifacts/epics.md`
- Project Context: `_bmad-output/project-context.md`
- MenuBarExtra API: Apple Developer Documentation (macOS 13+)
- NSPanel: AppKit framework
- UserNotifications: Apple framework (macOS 10.14+)
- URLSession Stream: Apple Foundation framework

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

### Completion Notes List

- ✅ Task 1: Created `RunModels.swift` with Bar-prefixed API models (BarCreateRunRequest/Response, BarRunStatusResponse, BarStepSummary, SSE event data models, BarSSEEvent enum). All CodingKeys use snake_case.
- ✅ Task 2: Created `TaskSubmissionService.swift` — POST /v1/runs with error handling for unreachable server, HTTP errors, and parse failures.
- ✅ Task 3: Created `SSEEventClient.swift` — URLSession bytes stream SSE parser with AsyncStream<BarSSEEvent> output. Handles step_started, step_completed, run_completed events.
- ✅ Task 4: Created `RunHistoryService.swift` — fetchHistory(limit:) and fetchRun(runId:) methods.
- ✅ Task 5: Created `QuickRunWindow.swift` — NSPanel + SwiftUI hosting with TextEditor, submit button, connection state validation.
- ✅ Task 6: Created `TaskDetailPanel.swift` — NSWindow + SwiftUI with live SSE log stream, step status display, run summary.
- ✅ Task 7: Created `RunHistoryWindow.swift` — NSWindow with scrollable list of recent runs, status badges, tap-to-detail.
- ✅ Task 8: Updated `StatusBarController.swift` — Added currentRunId, currentTask, currentStep, totalSteps properties; services and window managers; handleRunCompleted with notification; stepProgressText computed property.
- ✅ Task 9: Updated `App.swift` — Enabled menu items, added AppDelegate UNUserNotificationCenter delegate + authorization request, running task section in menu. Updated `MenuBarBuilder.swift` with matching menu items.
- ✅ Task 10: Added `GET /v1/runs` endpoint to `AxionAPI.swift` with `?limit=N` query parameter support. RunTracker.listRuns() already existed.
- ✅ Task 11: Created 4 new test files + updated StatusBarControllerTests. 59 tests pass (0 failures). SSE parsing tested with nonisolated method. All regression tests pass (AxionCoreTests, AxionCLITests, AxionHelperTests: 0 failures).

### Change Log

- 2026-05-15: Story 10.2 implementation complete — task management and realtime panel for AxionBar
- 2026-05-15: Senior Developer Review (AI) — 8 issues found (3 HIGH, 5 MEDIUM), all fixed
  - **[HIGH] Fixed**: Added central SSE monitoring in StatusBarController via `startRunMonitoring()` — task submission now triggers SSE subscription for progress tracking and completion detection. Fixes AC2 (progress display) and AC4 (notifications).
  - **[HIGH] Fixed**: `currentStep`/`totalSteps` now updated from SSE events via monitoring subscription.
  - **[HIGH] Fixed**: Completion notifications now fire via monitoring SSE, not dependent on user opening TaskDetailPanel.
  - **[MEDIUM] Fixed**: SSEEventClient `connect()` cancels previous task before creating new one.
  - **[MEDIUM] Fixed**: `runId` URL-encoded via URLComponents in SSEEventClient and RunHistoryService.
  - **[MEDIUM] Fixed**: `handleRunCompleted()` clears `currentRunId`/`currentTask`.
  - **[MEDIUM] Fixed**: TaskDetailView disconnects SSE on `.onDisappear`.
  - **[MEDIUM] Fixed**: Added `os.log` Logger to all service files.

### File List

**New Files:**
- Sources/AxionBar/Models/RunModels.swift
- Sources/AxionBar/Services/TaskSubmissionService.swift
- Sources/AxionBar/Services/SSEEventClient.swift
- Sources/AxionBar/Services/RunHistoryService.swift
- Sources/AxionBar/Views/QuickRunWindow.swift
- Sources/AxionBar/Views/TaskDetailPanel.swift
- Sources/AxionBar/Views/RunHistoryWindow.swift
- Tests/AxionBarTests/Models/RunModelsTests.swift
- Tests/AxionBarTests/Services/TaskSubmissionServiceTests.swift
- Tests/AxionBarTests/Services/SSEEventClientTests.swift
- Tests/AxionBarTests/Services/RunHistoryServiceTests.swift

**Modified Files:**
- Sources/AxionBar/StatusBarController.swift
- Sources/AxionBar/App.swift
- Sources/AxionBar/MenuBar/MenuBarBuilder.swift
- Sources/AxionCLI/API/AxionAPI.swift
- Tests/AxionBarTests/StatusBar/StatusBarControllerTests.swift
