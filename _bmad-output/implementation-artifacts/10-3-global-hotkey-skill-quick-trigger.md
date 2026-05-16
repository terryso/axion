# Story 10.3: 全局热键与技能快捷触发

Status: done

## Story

As a 用户,
I want 通过全局热键快速触发常用技能,
So that 常用自动化操作可以一键执行，无需打开任何界面.

## Acceptance Criteria

1. **AC1: 全局热键配置**
   Given 菜单栏 App 运行中
   When 用户在设置中配置全局热键
   Then 可以为技能或常用任务绑定全局热键（如 Cmd+Shift+A 触发 "打开计算器" 技能）

2. **AC2: 热键触发执行**
   Given 全局热键已配置
   When 用户按下热键组合
   Then 触发绑定的技能或任务，菜单栏图标显示执行状态

3. **AC3: Accessibility 权限检查**
   Given 菜单栏 App 首次启动
   When 检查 Accessibility 权限
   Then 全局热键需要 Accessibility 权限，未授权时提示用户授权

4. **AC4: 技能列表菜单**
   Given 技能列表中有已编译的技能
   When 用户点击 "技能" 菜单
   Then 显示所有可用技能的列表，每个技能可直接点击执行

5. **AC5: 技能执行一致性**
   Given 运行 `axion skill run open_calculator` 或通过菜单栏触发技能
   When 执行方式不同
   Then 两种方式执行结果一致（技能回放，无 LLM 调用）

## Tasks / Subtasks

- [x] Task 1: 后端技能 API 端点 (AC: #4, #5)
  - [x] 1.1 在 `Sources/AxionCLI/API/AxionAPI.swift` 添加 `GET /v1/skills` 端点 — 返回 `~/.axion/skills/` 目录下所有技能的列表摘要
  - [x] 1.2 添加 `GET /v1/skills/{name}` 端点 — 返回指定技能的完整详情（含步骤和参数）
  - [x] 1.3 添加 `POST /v1/skills/{name}/run` 端点 — 通过 HTTP API 执行技能（参数可选），复用 SkillExecutor 逻辑
  - [x] 1.4 在 `Sources/AxionCLI/API/Models/APITypes.swift` 添加 `SkillSummaryResponse` 和 `SkillDetailResponse` 模型
  - [x] 1.5 端点复用现有 AuthMiddleware 和 ConcurrencyLimiter（如果已配置）

- [x] Task 2: AxionBar 技能 API 模型与服务 (AC: #4, #5)
  - [x] 2.1 创建 `Sources/AxionBar/Models/SkillModels.swift` — `BarSkillSummary`（name, description, parameterCount, lastUsedAt）、`BarSkillDetail`（name, description, parameters, stepCount）
  - [x] 2.2 创建 `Sources/AxionBar/Services/SkillService.swift` — `fetchSkills()` 调用 GET /v1/skills，`fetchSkill(name:)` 调用 GET /v1/skills/{name}，`runSkill(name:params:)` 调用 POST /v1/skills/{name}/run
  - [x] 2.3 所有 CodingKeys 使用 snake_case（与后端 API 一致），`Bar` 前缀命名约定与 RunModels 一致

- [x] Task 3: GlobalHotkeyService — 全局热键监听 (AC: #1, #2, #3)
  - [x] 3.1 创建 `Sources/AxionBar/Services/GlobalHotkeyService.swift`
  - [x] 3.2 使用 `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` 监听全局按键（不需要 CGEvent Tap）
  - [x] 3.3 热键匹配逻辑：比对 modifierFlags + keyCode，支持 Cmd、Option、Shift、Control 组合
  - [x] 3.4 触发时调用 `StatusBarController.submitTask()` 或 `SkillService.runSkill()` 执行绑定操作
  - [x] 3.5 Accessibility 权限检查：调用 `AXIsProcessTrusted()` 检查，未授权时提示用户去系统偏好设置授权
  - [x] 3.6 App 进入前台时使用 `NSEvent.addLocalMonitorForEvents` 补充本地事件监听

- [x] Task 4: HotkeyConfig 模型与持久化 (AC: #1)
  - [x] 4.1 创建 `Sources/AxionBar/Models/HotkeyConfig.swift` — `HotkeyBinding`（id, skillName/taskDescription, modifiers, keyCode）、`HotkeyConfig`（bindings 数组）
  - [x] 4.2 持久化到 `~/.axion/hotkeys.json`，使用 FileManager + Codable
  - [x] 4.3 提供 `HotkeyConfigManager`（@MainActor）：load()、save()、addBinding()、removeBinding()
  - [x] 4.4 默认无热键绑定（用户主动配置）

- [x] Task 5: SettingsWindow — 设置窗口 (AC: #1)
  - [x] 5.1 创建 `Sources/AxionBar/Views/SettingsWindow.swift` — NSWindow + SwiftUI hosting
  - [x] 5.2 SettingsView 包含两个 Tab：技能热键配置、Accessibility 权限状态
  - [x] 5.3 技能热键 Tab：列表显示已绑定热键，每行包含「技能名」+「热键组合」+「删除按钮」
  - [x] 5.4 添加绑定：选择技能（下拉菜单，从 SkillService.fetchSkills() 获取）→ 按下热键组合 → 保存
  - [x] 5.5 Accessibility Tab：显示当前权限状态 + "打开系统偏好设置" 按钮
  - [x] 5.6 调用 `AXIsProcessTrusted()` 检查权限，`AXIsProcessTrustedWithOptions` 提示授权

- [x] Task 6: 启用技能列表菜单 (AC: #4)
  - [x] 6.1 更新 `Sources/AxionBar/MenuBar/MenuBarBuilder.swift` — 技能列表从 disabled placeholder 改为动态加载
  - [x] 6.2 更新 `Sources/AxionBar/App.swift` SwiftUI MenuBuilder — 同步启用技能列表
  - [x] 6.3 连接后从 `SkillService.fetchSkills()` 加载技能列表，每个技能生成可点击的 NSMenuItem
  - [x] 6.4 点击技能菜单项调用 `SkillService.runSkill(name:)`，提交后 StatusBarController 切换到 running 状态
  - [x] 6.5 无技能时显示 "（暂无技能）" 灰色菜单项
  - [x] 6.6 连接断开时技能列表菜单灰显

- [x] Task 7: StatusBarController 集成 (AC: #2)
  - [x] 7.1 添加 `@Published var availableSkills: [BarSkillSummary] = []`
  - [x] 7.2 连接成功后自动加载技能列表（调用 SkillService.fetchSkills()）
  - [x] 7.3 添加 `runSkill(name:)` 方法 — 调用 SkillService.runSkill()，更新 running 状态
  - [x] 7.4 添加 `@Published var hotkeyConfig: HotkeyConfig` — 热键配置
  - [x] 7.5 App 启动时加载热键配置并注册 GlobalHotkeyService
  - [x] 7.6 热键触发时调用 `runSkill()` 或 `submitTask()`

- [x] Task 8: 单元测试 (AC: #1-#5)
  - [x] 8.1 创建 `Tests/AxionBarTests/Models/SkillModelsTests.swift` — Codable round-trip 测试
  - [x] 8.2 创建 `Tests/AxionBarTests/Models/HotkeyConfigTests.swift` — 配置序列化、增删绑定测试
  - [x] 8.3 创建 `Tests/AxionBarTests/Services/SkillServiceTests.swift` — mock URLSession 测试技能列表/详情/执行
  - [x] 8.4 创建 `Tests/AxionBarTests/Services/GlobalHotkeyServiceTests.swift` — 热键匹配逻辑测试
  - [x] 8.5 更新 `Tests/AxionBarTests/StatusBar/StatusBarControllerTests.swift` — 测试技能运行状态
  - [x] 8.6 创建后端 API 测试 `Tests/AxionCLITests/API/SkillAPITests.swift`（如适用）— 测试 GET/POST skill 端点
  - [x] 8.7 确保 `swift test --filter "AxionBarTests"` 全部通过

## Dev Notes

### 与前两个 Story 的关系

**Story 10.1 已完成：**
- AxionBar 基础架构（SPM target、MenuBarExtra、StatusBarController）
- BackendHealthChecker（5 秒轮询 GET /v1/health）
- ServerProcessManager（启动/停止 axion server）
- 下拉菜单结构（"技能列表" 当前灰色禁用 placeholder）
- ConnectionState 枚举（.disconnected / .connected / .running）

**Story 10.2 已完成：**
- 任务提交（TaskSubmissionService — POST /v1/runs）
- SSE 实时事件流（SSEEventClient — GET /v1/runs/{runId}/events）
- 任务详情面板（TaskDetailPanel — 实时日志流）
- 任务历史（RunHistoryService — GET /v1/runs）
- macOS Native Notification（UNUserNotificationCenter）
- StatusBarController running 状态管理（currentRunId, currentTask, stepProgress）

**本 Story：**
- 启用"技能列表"菜单（从 placeholder → 动态加载）
- 添加全局热键服务
- 添加设置窗口
- 后端添加技能相关 API 端点

### 后端技能 API 设计（需新增）

| 端点 | 方法 | 用途 | 请求/响应 |
|------|------|------|-----------|
| `/v1/skills` | GET | 列出所有技能 | → `[SkillSummaryResponse]` |
| `/v1/skills/{name}` | GET | 获取技能详情 | → `SkillDetailResponse` |
| `/v1/skills/{name}/run` | POST | 执行技能 | body: `{"params": {...}}` → `{"run_id": "...", "status": "running"}` |

技能执行端点（`POST /v1/skills/{name}/run`）复用 SkillExecutor 逻辑：
- 从 `~/.axion/skills/{name}.json` 加载技能
- 使用 HelperProcessManager 建立 MCP 连接
- 通过 SkillExecutor 执行步骤
- 结果通过 RunTracker 追踪，SSE 推送事件
- 返回 run_id，AxionBar 可复用现有的 SSE 监听和状态面板

**关键决策：技能执行走现有 RunTracker + EventBroadcaster 管线**，这样 AxionBar 可以复用 SSEEventClient 和 TaskDetailPanel 显示技能执行状态。

### 全局热键实现方案

**使用 NSEvent 全局监听（不需要 CGEvent Tap）：**

```swift
// 监听全局按键（其他 App 中）
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
    // 匹配 modifierFlags + keyCode
}

// 监听本地按键（自己 App 中）
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    // 同样的匹配逻辑
    return event  // 不消费事件
}
```

**为什么不用 CGEvent Tap：**
- CGEvent Tap 需要 Accessibility 权限（硬性依赖），且需要单独的 entitlements
- NSEvent.addGlobalMonitorForEvents 仅需 Accessibility 权限用于"监听"，不需要创建事件
- 如果 Accessibility 权限未授予，global monitor 静默不工作（不崩溃），本地 monitor 仍然工作
- 这是 macOS 菜单栏 App 的标准模式

**热键匹配逻辑：**

```swift
struct HotkeyBinding: Codable {
    let id: UUID
    let action: HotkeyAction       // .skill(name) 或 .task(description)
    let modifiers: NSEvent.ModifierFlags  // .command, .option, .shift, .control
    let keyCode: UInt16
}

func matches(event: NSEvent) -> Bool {
    return event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers
        && event.keyCode == keyCode
}
```

### 热键配置持久化

存储路径：`~/.axion/hotkeys.json`

```json
{
  "bindings": [
    {
      "id": "UUID",
      "action": { "skill": "open_calculator" },
      "modifiers": ["command", "shift"],
      "keyCode": 0
    }
  ]
}
```

- 使用 FileManager + Codable 读写
- 加载时机：App 启动后（`StatusBarController.init()` 或 `AppDelegate`）
- 保存时机：用户在设置窗口添加/删除绑定后立即保存

### SettingsWindow 实现方案

使用 NSWindow + SwiftUI hosting（与 QuickRunWindow、RunHistoryWindow 模式一致）：

```swift
let settingsWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
    styleMask: [.titled, .closable, .resizable, .miniaturizable],
    backing: .buffered, defer: false
)
settingsWindow.contentView = NSHostingView(rootView: SettingsView(...))
```

Tab 1: 技能热键
- 列表显示已绑定热键
- "添加" 按钮：下拉选择技能 → 按键录制 → 保存
- 每行 "删除" 按钮
- 热键冲突检测（同一组合已有绑定时提示）

Tab 2: Accessibility 权限
- 当前状态（已授权/未授权）
- "打开系统偏好设置" 按钮
- 权限说明文字

### Accessibility 权限检查

```swift
import ApplicationServices

func checkAccessibilityPermission() -> Bool {
    return AXIsProcessTrusted()
}

func promptAccessibilityPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}
```

注意：
- `AXIsProcessTrusted()` 不需要导入 ApplicationServices（已在 SDK 中桥接）
- 菜单栏 App（LSUIElement=true）需要在 Info.plist 或 entitlements 中声明辅助功能权限
- 首次启动时检查，未授权时在菜单中显示提示

### 菜单结构变化

```
┌─────────────────────────────────────┐
│ ▶ 快速执行...                       │
│ 技能列表  →                          │ ← 启用！动态加载技能
│   ├ 打开计算器                       │ ← 点击执行技能
│   ├ 打开浏览器                       │
│   └ （暂无技能）                     │ ← 无技能时显示
│─────────────────────────────────────│
│ ▶ 运行中: "技能: 打开计算器" 步骤 1/3│ ← 技能执行也显示
│─────────────────────────────────────│
│ ▶ 任务历史...                       │
│─────────────────────────────────────│
│ 启动服务 / 重启服务                  │
│─────────────────────────────────────│
│ 设置...                             │ ← 打开设置窗口（热键+权限）
│ Axion v1.2.3                        │
│─────────────────────────────────────│
│ 退出 AxionBar                       │
└─────────────────────────────────────┘
```

### NFR 约束

- **NFR32**：菜单栏 App 常驻内存 < 15MB — GlobalHotkeyService 不增加显著内存
- **NFR35**：全局热键响应延迟 < 200ms（从按键到触发动作）— NSEvent 回调在主线程，直接调用方法
- **NFR31**：技能执行响应时间 < 100ms（首步执行延迟）— 后端 SkillExecutor 直接调用 MCP

### 前两 Story 关键学习

1. **AxionBar 依赖边界** — 仅依赖 AxionCore + Foundation + SwiftUI + AppKit，不引入第三方依赖
2. **NSApp.setActivationPolicy(.accessory)** — 已在 AppDelegate 中设置，无 Dock 图标
3. **@MainActor 隔离** — 所有 AxionBar 服务使用 @MainActor 隔离
4. **两套菜单实现** — MenuBarBuilder（NSMenu）和 AxionBarMenuContent（SwiftUI）并存，需要同时更新
5. **健康检查轮询间隔 5 秒** — BackendHealthChecker 已有，不需要修改
6. **URLSession.shared** — 直接使用共享 URLSession，不需要自定义配置
7. **路径使用 FileManager + URL** — 不拼接字符串路径
8. **decodeIfPresent + ?? default** — JSON 解码使用向后兼容模式
9. **os_log/os.Logger** — 日志使用系统日志框架，不使用 print()
10. **stdout 纯净** — AxionBar 不输出到 stdout
11. **Bar 前缀模型** — AxionBar 定义自己的 API 模型（BarXxx），不 import AxionCLI
12. **NSPanel/NSWindow + SwiftUI hosting** — 窗口模式（与 QuickRunWindow/TaskDetailPanel/RunHistoryWindow 一致）

### 需要创建的新文件

1. `Sources/AxionBar/Models/SkillModels.swift` [NEW] — 技能 API 模型
2. `Sources/AxionBar/Models/HotkeyConfig.swift` [NEW] — 热键配置模型
3. `Sources/AxionBar/Services/SkillService.swift` [NEW] — 技能 API 服务
4. `Sources/AxionBar/Services/GlobalHotkeyService.swift` [NEW] — 全局热键监听
5. `Sources/AxionBar/Views/SettingsWindow.swift` [NEW] — 设置窗口
6. `Tests/AxionBarTests/Models/SkillModelsTests.swift` [NEW]
7. `Tests/AxionBarTests/Models/HotkeyConfigTests.swift` [NEW]
8. `Tests/AxionBarTests/Services/SkillServiceTests.swift` [NEW]
9. `Tests/AxionBarTests/Services/GlobalHotkeyServiceTests.swift` [NEW]

### 需要修改的现有文件

1. `Sources/AxionBar/StatusBarController.swift` [UPDATE] — 添加技能列表、热键配置、runSkill 方法
2. `Sources/AxionBar/App.swift` [UPDATE] — 启用技能菜单、添加设置窗口入口、注册热键
3. `Sources/AxionBar/MenuBar/MenuBarBuilder.swift` [UPDATE] — 启用技能列表菜单（动态加载）
4. `Sources/AxionCLI/API/AxionAPI.swift` [UPDATE] — 添加技能 API 端点
5. `Sources/AxionCLI/API/Models/APITypes.swift` [UPDATE] — 添加技能响应模型
6. `Tests/AxionBarTests/StatusBar/StatusBarControllerTests.swift` [UPDATE] — 技能运行测试

### 关键约束

- **不引入新的第三方依赖**：全局热键使用 NSEvent API，不使用第三方热键库
- **AxionBar 不 import AxionCLI**：技能 API 模型在 AxionBar 中本地定义（Bar 前缀）
- **两套菜单同步更新**：MenuBarBuilder 和 AxionBarMenuContent 需要同步变更
- **技能执行复用 RunTracker**：后端 POST /v1/skills/{name}/run 走 RunTracker + EventBroadcaster 管线
- **端口默认 4242**：与前面 Story 一致
- **macOS 14+ 目标**：与项目其他 target 一致
- **ApplicationServices import**：AXIsProcessTrusted/AXIsProcessTrustedWithOptions
- **热键冲突检测**：同一组合键不允许绑定多个技能

### Project Structure Notes

- `Sources/AxionBar/Models/` 扩展（SkillModels.swift, HotkeyConfig.swift）
- `Sources/AxionBar/Services/` 扩展（SkillService.swift, GlobalHotkeyService.swift）
- `Sources/AxionBar/Views/` 扩展（SettingsWindow.swift）
- `Tests/AxionBarTests/` 扩展（新增模型和服务测试文件）

### References

- Story 10.1 实现: `_bmad-output/implementation-artifacts/10-1-menubar-status-service-communication.md`
- Story 10.2 实现: `_bmad-output/implementation-artifacts/10-2-task-management-realtime-panel.md`
- Skill 模型: `Sources/AxionCore/Models/Skill.swift`
- SkillExecutor: `Sources/AxionCLI/Services/SkillExecutor.swift`
- SkillRunCommand: `Sources/AxionCLI/Commands/SkillRunCommand.swift`
- SkillListCommand: `Sources/AxionCLI/Commands/SkillListCommand.swift`
- AxionAPI: `Sources/AxionCLI/API/AxionAPI.swift`
- APITypes: `Sources/AxionCLI/API/Models/APITypes.swift`
- RunTracker: `Sources/AxionCLI/API/RunTracker.swift`
- EventBroadcaster: `Sources/AxionCLI/API/EventBroadcaster.swift`
- StatusBarController: `Sources/AxionBar/StatusBarController.swift`
- App.swift: `Sources/AxionBar/App.swift`
- MenuBarBuilder: `Sources/AxionBar/MenuBar/MenuBarBuilder.swift`
- RunModels: `Sources/AxionBar/Models/RunModels.swift`
- TaskSubmissionService: `Sources/AxionBar/Services/TaskSubmissionService.swift`
- SSEEventClient: `Sources/AxionBar/Services/SSEEventClient.swift`
- NFR32 (内存 < 15MB): `_bmad-output/planning-artifacts/epics.md`
- NFR35 (热键响应 < 200ms): `_bmad-output/planning-artifacts/epics.md`
- NFR31 (技能执行 < 100ms): `_bmad-output/planning-artifacts/epics.md`
- FR59 (全局热键): `_bmad-output/planning-artifacts/epics.md`
- Project Context: `_bmad-output/project-context.md`
- NSEvent.addGlobalMonitorForEvents: Apple AppKit Documentation
- AXIsProcessTrusted: Apple ApplicationServices Documentation
- NSMenu dynamic items: Apple AppKit Documentation

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7

### Debug Log References

### Completion Notes List

- Implemented GET /v1/skills, GET /v1/skills/{name}, POST /v1/skills/{name}/run backend API endpoints in AxionAPI.swift
- Added SkillSummaryResponse, SkillDetailResponse, SkillRunRequest, SkillRunResponse, SkillParameterResponse models to APITypes.swift
- Created SkillAPIRunner.swift for background skill execution through RunTracker + EventBroadcaster SSE pipeline
- Created BarSkillSummary, BarSkillDetail, BarSkillParameter, BarSkillRunRequest, BarSkillRunResponse models in SkillModels.swift
- Created SkillService.swift with fetchSkills(), fetchSkill(name:), runSkill(name:params:) HTTP client methods
- Created GlobalHotkeyService.swift with NSEvent global/local monitor, AXIsProcessTrusted accessibility check
- Created HotkeyConfig.swift with HotkeyBinding, HotkeyAction, HotkeyConfig, HotkeyConfigManager (@MainActor)
- Created SettingsWindow.swift with NSWindow + SwiftUI hosting, two tabs (skill hotkeys, accessibility permission)
- Updated StatusBarController.swift to integrate skill list, hotkey config, skill execution, hotkey triggers
- Updated MenuBarBuilder.swift to dynamically load skills instead of disabled placeholder
- Updated App.swift SwiftUI menu to enable skill list and open settings window
- Updated APITypesTests.swift with 8 new skill API type tests
- Created SkillModelsTests.swift, HotkeyConfigTests.swift, SkillServiceTests.swift, GlobalHotkeyServiceTests.swift
- Updated StatusBarControllerTests.swift with skill management tests
- Updated MenuBarBuilderTests.swift for new skill menu structure
- All 848 unit tests pass with 0 failures

### Senior Developer Review (AI)

**Reviewer:** Claude (adversarial review) on 2026-05-15

**Issues Found:** 1 High, 4 Medium, 2 Low — all auto-fixed

**HIGH (fixed):**
- H1: keyCodeToString had wrong key mappings for codes 28-35 (wrong display characters for -, =, ], O, U, [, ', \). Fixed all mappings to match macOS kVK_* constants.

**MEDIUM (all fixed):**
- M1: SkillService URL not percent-encoded for skill names with special chars. Added addingPercentEncoding.
- M2: AddHotkeySheet discarded addBinding return value — no conflict feedback. Added error message display on conflict.
- M3: SkillAPIRunner duplicated step execution code in retry logic. Extracted executeStep() helper.
- M4: HotkeyConfigManagerTests wrote to real filesystem (~/.axion/hotkeys.json). Added configURL parameter, tests now use temp directories.

**LOW (all fixed):**
- L1: BarSkillRunRequest CodingKeys was identity mapping (unnecessary). Removed.
- L2: SkillServiceError equality ignored associated Error values. Now compares localizedDescription.

### Change Log

- 2026-05-15: Story 10.3 implementation complete — backend skill API endpoints, AxionBar skill service/models, global hotkey service, hotkey config persistence, settings window, dynamic skill list menu, StatusBarController integration, full unit test coverage
- 2026-05-15: Adversarial review — fixed 7 issues: keyCode mapping errors (HIGH), URL encoding, hotkey conflict feedback, code duplication, test filesystem isolation, unnecessary CodingKeys, error equality comparison

### File List

**New Files:**
- Sources/AxionBar/Models/SkillModels.swift
- Sources/AxionBar/Models/HotkeyConfig.swift
- Sources/AxionBar/Services/SkillService.swift
- Sources/AxionBar/Services/GlobalHotkeyService.swift
- Sources/AxionBar/Views/SettingsWindow.swift
- Sources/AxionCLI/API/SkillAPIRunner.swift
- Tests/AxionBarTests/Models/SkillModelsTests.swift
- Tests/AxionBarTests/Models/HotkeyConfigTests.swift
- Tests/AxionBarTests/Services/SkillServiceTests.swift
- Tests/AxionBarTests/Services/GlobalHotkeyServiceTests.swift

**Modified Files:**
- Sources/AxionCLI/API/AxionAPI.swift
- Sources/AxionCLI/API/Models/APITypes.swift
- Sources/AxionBar/StatusBarController.swift
- Sources/AxionBar/App.swift
- Sources/AxionBar/MenuBar/MenuBarBuilder.swift
- Tests/AxionBarTests/StatusBar/StatusBarControllerTests.swift
- Tests/AxionBarTests/MenuBar/MenuBarBuilderTests.swift
- Tests/AxionCLITests/API/APITypesTests.swift
