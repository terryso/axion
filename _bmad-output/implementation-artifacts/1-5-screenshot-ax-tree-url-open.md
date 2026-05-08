# Story 1.5: 截图、AX Tree 与 URL 打开

Status: done

## Story

As a CLI 进程,
I want Helper 可以截图、获取无障碍树和打开 URL,
So that 自动化任务可以感知屏幕状态并浏览网页.

## Acceptance Criteria

1. **AC1: screenshot 窗口截图**
   - Given 指定窗口 window_id
   - When 调用 screenshot
   - Then 返回该窗口截图的 base64 编码，大小不超过 5MB

2. **AC2: screenshot 全屏截图**
   - Given 未指定 window_id
   - When 调用 screenshot
   - Then 返回全屏截图的 base64 编码

3. **AC3: get_accessibility_tree 完整树**
   - Given 窗口存在
   - When 调用 get_accessibility_tree
   - Then 返回该窗口的完整 Accessibility tree，节点包含 role / title / value / bounds / children

4. **AC4: get_accessibility_tree 截断**
   - Given AX tree 节点数超过阈值（maxNodes=500）
   - When 调用 get_accessibility_tree
   - Then 按层级截断，返回有限大小的树

5. **AC5: open_url URL 打开**
   - Given URL "https://example.com"
   - When 调用 open_url
   - Then 在默认浏览器中打开该 URL，返回成功

## Tasks / Subtasks

- [ ] Task 1: 实现 ScreenshotService (AC: #1, #2)
  - [ ] 1.1 创建 `Sources/AxionHelper/Protocols/ScreenshotCapturing.swift`：定义 `ScreenshotCapturing` 协议（captureWindow, captureFullScreen 两个方法）
  - [ ] 1.2 创建 `Sources/AxionHelper/Services/ScreenshotService.swift`：使用 `CGWindowListCreateImage` API 实现截图
  - [ ] 1.3 实现 `captureWindow(windowId:)`：使用 `CGWindowListCreateImage` + `kCGWindowListOptionIncludingWindow` 捕获指定窗口截图
  - [ ] 1.4 实现 `captureFullScreen()`：使用 `CGWindowListCreateImage` + `kCGWindowListOptionOnScreenOnly` 捕获全屏截图
  - [ ] 1.5 将截图 `CGImage` 转换为 JPEG/PNG Data，然后 base64 编码
  - [ ] 1.6 添加 5MB 大小限制检查，超过时压缩分辨率后重试

- [ ] Task 2: 实现 URLOpenerService (AC: #5)
  - [ ] 2.1 创建 `Sources/AxionHelper/Protocols/URLOpening.swift`：定义 `URLOpening` 协议（openURL 方法）
  - [ ] 2.2 创建 `Sources/AxionHelper/Services/URLOpenerService.swift`：使用 `NSWorkspace.shared.open()` 打开 URL
  - [ ] 2.3 添加 URL 格式验证（必须是合法的 http/https URL）

- [ ] Task 3: 增强 AccessibilityEngine 的 AX tree 功能 (AC: #3, #4)
  - [ ] 3.1 在 `Sources/AxionHelper/Protocols/WindowManaging.swift` 中添加 `getAXTree(windowId:maxNodes:)` 方法
  - [ ] 3.2 在 `AccessibilityEngineService` 中实现 `getAXTree(windowId:maxNodes:)`，复用现有 `buildAXTree` 方法，传入 maxNodes=500
  - [ ] 3.3 验证截断逻辑正确（`NodeBudget` 已存在于 AccessibilityEngine，maxNodes 参数控制截断）

- [ ] Task 4: 注册新服务到 ServiceContainer (AC: #1-#5)
  - [ ] 4.1 更新 `ServiceContainer.swift`：添加 `screenshotCapture: any ScreenshotCapturing` 和 `urlOpener: any URLOpening` 属性
  - [ ] 4.2 默认初始化为 `ScreenshotService()` 和 `URLOpenerService()`

- [ ] Task 5: 替换 ToolRegistrar 中 Story 1.5 工具的 stub 实现 (AC: #1-#5)
  - [ ] 5.1 更新 `ScreenshotTool.perform()` 调用 ScreenshotService（支持可选 window_id 参数）
  - [ ] 5.2 更新 `GetAccessibilityTreeTool.perform()` 调用 AccessibilityEngine.getAXTree（maxNodes=500）
  - [ ] 5.3 更新 `OpenUrlTool.perform()` 调用 URLOpenerService
  - [ ] 5.4 所有工具返回 JSON 字符串格式结果

- [ ] Task 6: 编写单元测试 (AC: #1-#5)
  - [ ] 6.1 创建 `Tests/AxionHelperTests/Services/ScreenshotServiceTests.swift`：测试截图大小限制、base64 编码格式
  - [ ] 6.2 创建 `Tests/AxionHelperTests/Services/URLOpenerServiceTests.swift`：测试 URL 验证逻辑
  - [ ] 6.3 创建 `Tests/AxionHelperTests/Tools/ScreenshotUrlToolTests.swift`：测试 3 个工具通过 Mock ServiceContainer 的集成
  - [ ] 6.4 更新 `Tests/AxionHelperTests/Mocks/MockServices.swift`：添加 MockScreenshotCapture 和 MockURLOpener
  - [ ] 6.5 更新 `ServiceContainerFixture.apply()` 添加 screenshotCapture 和 urlOpener 参数
  - [ ] 6.6 更新 `HelperMCPServerTests.test_stubTool_perform_returnsNotYetImplemented`（不再有 stub 工具）
  - [ ] 6.7 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Services" --filter "AxionHelperTests.MCP"` 确认所有测试通过

## Dev Notes

### 关键架构约束

**本 Story 将 ToolRegistrar 中最后 3 个工具的 stub 替换为真实实现。** Story 1.3 建立了 AppLauncher 和 AccessibilityEngine，Story 1.4 建立了 InputSimulationService，本 Story 建立 ScreenshotService 和 URLOpenerService，同时增强 AccessibilityEngine 的 AX tree 功能。完成后 **全部 15 个 MCP 工具都有真实实现**，为 Story 1.6（完整集成与 App 打包）做好准备。

**AxionHelper 进程边界不变** -- 本 Story 只在 AxionHelper target 内部工作，不修改 AxionCLI 或 AxionCore 的代码（ToolNames.swift 已包含所有工具名常量，无需修改）。

**NFR3 性能要求：** 截图操作超时 10 秒（比普通工具的 5 秒更长），AX tree 操作也超时 10 秒。截图 base64 不超过 5MB。

### 核心 API -- macOS 截图（CoreGraphics）

使用 `CGWindowListCreateImage` API 截图。**不调用外部 cua-driver 二进制** -- 与 OpenClick 的关键区别，AxionHelper 直接使用 macOS CoreGraphics API。

**指定窗口截图：**

```swift
import CoreGraphics
import ImageIO  // for CGImageDestination

func captureWindow(windowId: Int) throws -> Data {
    let windowIdCG = CGWindowID(windowId)
    let image = CGWindowListCreateImage(
        .null,  // rect: .null = entire window
        .optionIncludingWindow,  // 只截指定窗口
        windowIdCG,
        [.bestResolution]  // 最佳分辨率
    )
    guard let image else {
        throw ScreenshotError.windowCaptureFailed(windowId: windowId)
    }
    return try imageToJPEGData(image)
}
```

**全屏截图：**

```swift
func captureFullScreen() throws -> Data {
    guard let image = CGWindowListCreateImage(
        CGDisplayBounds(CGMainDisplayID()),
        .optionOnScreenOnly,
        kCGNullWindowID,
        [.bestResolution]
    ) else {
        throw ScreenshotError.fullScreenCaptureFailed
    }
    return try imageToJPEGData(image)
}
```

**CGImage -> JPEG Data -> Base64：**

```swift
func imageToJPEGData(_ image: CGImage, compressionQuality: CGFloat = 0.8) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data as CFMutableData, "public.jpeg" as CFString, 1, nil
    ) else {
        throw ScreenshotError.imageConversionFailed
    }
    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: compressionQuality
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw ScreenshotError.imageConversionFailed
    }
    return data as Data
}
```

**5MB 大小限制处理：**

如果 base64 编码后的数据超过 5MB（约 3.75MB 原始数据），需要降低分辨率重试：

```swift
func captureWithSizeLimit(image: CGImage, maxSizeBytes: Int = 5 * 1024 * 1024) throws -> String {
    var quality: CGFloat = 0.8
    var data = try imageToJPEGData(image, compressionQuality: quality)
    let base64Data = data.base64EncodedData()

    if base64Data.count <= maxSizeBytes {
        return data.base64EncodedString()
    }

    // 降低质量重试
    quality = 0.5
    data = try imageToJPEGData(image, compressionQuality: quality)
    if data.base64EncodedData().count <= maxSizeBytes {
        return data.base64EncodedString()
    }

    // 缩小分辨率
    let scale: CGFloat = 0.5
    let newWidth = Int(CGFloat(image.width) * scale)
    let newHeight = Int(CGFloat(image.height) * scale)
    // 使用 CGContext 重绘为更小尺寸
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil, width: newWidth, height: newHeight,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw ScreenshotError.imageConversionFailed
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
    guard let resizedImage = context.makeImage() else {
        throw ScreenshotError.imageConversionFailed
    }
    data = try imageToJPEGData(resizedImage, compressionQuality: 0.6)
    return data.base64EncodedString()
}
```

### Screenshot 错误类型

遵循现有错误模式（`AppLauncherError`, `AccessibilityEngineError`, `InputSimulationError`）：

```swift
enum ScreenshotError: Error, LocalizedError {
    case windowCaptureFailed(windowId: Int)
    case fullScreenCaptureFailed
    case imageConversionFailed
    case screenshotTooLarge(sizeBytes: Int)

    var errorDescription: String? { ... }
    var errorCode: String {
        switch self {
        case .windowCaptureFailed: return "window_capture_failed"
        case .fullScreenCaptureFailed: return "fullscreen_capture_failed"
        case .imageConversionFailed: return "image_conversion_failed"
        case .screenshotTooLarge: return "screenshot_too_large"
        }
    }
    var suggestion: String { ... }
}
```

### ScreenshotCapturing 协议设计

遵循现有协议模式（`AppLaunching`, `WindowManaging`, `InputSimulating`）：

```swift
// Sources/AxionHelper/Protocols/ScreenshotCapturing.swift
import Foundation

protocol ScreenshotCapturing: Sendable {
    func captureWindow(windowId: Int) throws -> String  // returns base64
    func captureFullScreen() throws -> String  // returns base64
}
```

### URL 打开实现

使用 `NSWorkspace.shared.open()` 打开 URL：

```swift
// Sources/AxionHelper/Services/URLOpenerService.swift
import AppKit
import Foundation

struct URLOpenerService: URLOpening {
    func openURL(_ urlString: String) throws {
        guard let url = URL(string: urlString) else {
            throw URLOpenerError.invalidURL(urlString)
        }
        guard let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            throw URLOpenerError.unsupportedScheme(urlString)
        }
        guard NSWorkspace.shared.open(url) else {
            throw URLOpenerError.failedToOpen(urlString)
        }
    }
}
```

**URLOpener 错误类型：**

```swift
enum URLOpenerError: Error, LocalizedError {
    case invalidURL(String)
    case unsupportedScheme(String)
    case failedToOpen(String)

    var errorDescription: String? { ... }
    var errorCode: String { ... }
    var suggestion: String { ... }
}
```

**URLOpening 协议：**

```swift
// Sources/AxionHelper/Protocols/URLOpening.swift
import Foundation

protocol URLOpening: Sendable {
    func openURL(_ urlString: String) throws
}
```

### AX Tree 增强

**现有代码已支持核心功能。** `AccessibilityEngineService` 已有 `buildAXTree(element:maxDepth:maxNodes:)` 方法（第 209 行），`NodeBudget` 类（第 214 行）控制截断。`getWindowState` 内部已调用 `buildAXTree` 并传入 `maxNodes: 300`。

本 Story 需要：
1. 在 `WindowManaging` 协议中添加 `getAXTree(windowId:maxNodes:)` 方法
2. 在 `AccessibilityEngineService` 中实现该方法：
   - 通过 `CGWindowListCopyWindowInfo` 找到窗口对应的 PID
   - 通过 AX API 找到对应的 AXUIElement window
   - 调用 `buildAXTree` 并传入 maxNodes 参数（默认 500）

```swift
// 新增到 WindowManaging 协议
func getAXTree(windowId: Int, maxNodes: Int) throws -> AXElement

// 实现
func getAXTree(windowId: Int, maxNodes: Int = 500) throws -> AXElement {
    let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    guard let cgWindow = windowList.first(where: {
        $0[kCGWindowNumber as String] as? Int == windowId
    }) else {
        throw AccessibilityEngineError.windowNotFound(windowId: windowId)
    }
    guard let ownerPID = cgWindow[kCGWindowOwnerPID as String] as? Int32 else {
        throw AccessibilityEngineError.windowNotFound(windowId: windowId)
    }
    let title = cgWindow[kCGWindowName as String] as? String
    let cgBounds = parseCGBounds(cgWindow["kCGWindowBounds"] as? [String: Any])

    let axApp = AXUIElementCreateApplication(ownerPID)
    var windowsRef: AnyObject?
    AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
    guard let axWindows = windowsRef as? [AXUIElement] else {
        throw AccessibilityEngineError.axTreeBuildFailed(reason: "No AX windows found for pid \(ownerPID)")
    }

    // Match window (reuse existing matching logic from getAXWindowState)
    let matchedWindow = matchAXWindow(axWindows: axWindows, title: title, bounds: cgBounds)
    guard let matchedWindow else {
        throw AccessibilityEngineError.axTreeBuildFailed(reason: "Cannot match AX window for window_id \(windowId)")
    }

    return buildAXTree(element: matchedWindow, maxDepth: 8, maxNodes: maxNodes)
}
```

**注意：** 现有 `getAXWindowState` 中的窗口匹配逻辑（第 151-206 行）应该提取为私有方法供 `getAXTree` 复用，避免代码重复。

### ServiceContainer 更新

```swift
// 更新 ServiceContainer.swift
struct ServiceContainer: Sendable {
    var appLauncher: any AppLaunching
    var accessibilityEngine: any WindowManaging
    var inputSimulation: any InputSimulating
    var screenshotCapture: any ScreenshotCapturing  // NEW
    var urlOpener: any URLOpening                   // NEW

    nonisolated(unsafe) static var shared = ServiceContainer(
        appLauncher: AppLauncherService(),
        accessibilityEngine: AccessibilityEngineService(),
        inputSimulation: InputSimulationService(),
        screenshotCapture: ScreenshotService(),    // NEW
        urlOpener: URLOpenerService()              // NEW
    )
}
```

### ToolRegistrar 工具实现模式

**严格遵循 Story 1.3/1.4 的工具实现模式** -- 不修改 `@Tool` struct 的参数声明，只替换 `perform()` 方法体。

**ScreenshotTool 实现（支持可选 window_id）：**

```swift
@Tool
struct ScreenshotTool {
    static let name = "screenshot"
    static let description = "Capture a screenshot, optionally of a specific window"

    @Parameter(key: "window_id", description: "Window identifier (optional, captures full screen if omitted)")
    var windowId: Int?

    func perform() async throws -> String {
        do {
            let base64: String
            if let windowId {
                base64 = try ServiceContainer.shared.screenshotCapture.captureWindow(windowId: windowId)
            } else {
                base64 = try ServiceContainer.shared.screenshotCapture.captureFullScreen()
            }
            let result = ScreenshotActionResult(success: true, action: "screenshot", imageData: base64)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as ScreenshotError {
            let payload = ToolErrorPayload(error: error.errorCode, message: error.localizedDescription, suggestion: error.suggestion)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}
```

**ScreenshotActionResult 结构体（添加到 ToolRegistrar.swift）：**

```swift
private struct ScreenshotActionResult: Codable {
    let success: Bool
    let action: String
    let imageData: String

    enum CodingKeys: String, CodingKey {
        case success, action
        case imageData = "image_data"
    }
}
```

**GetAccessibilityTreeTool 实现：**

```swift
@Tool
struct GetAccessibilityTreeTool {
    static let name = "get_accessibility_tree"
    static let description = "Get the accessibility tree for a window"

    @Parameter(key: "window_id", description: "Window identifier")
    var windowId: Int

    @Parameter(key: "max_nodes", description: "Maximum number of nodes to return (default: 500)")
    var maxNodes: Int?

    func perform() async throws -> String {
        do {
            let nodes = maxNodes ?? 500
            let axTree = try ServiceContainer.shared.accessibilityEngine.getAXTree(windowId: windowId, maxNodes: nodes)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(axTree)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as AccessibilityEngineError {
            let payload = ToolErrorPayload(error: error.errorCode, message: error.localizedDescription, suggestion: error.suggestion)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}
```

**注意：** `get_accessibility_tree` 工具目前没有 `max_nodes` 参数声明。需要添加一个 `@Parameter(key: "max_nodes", description: "...") var maxNodes: Int?` 参数到 GetAccessibilityTreeTool struct。这属于新增可选参数，不影响现有行为。

**OpenUrlTool 实现：**

```swift
@Tool
struct OpenUrlTool {
    static let name = "open_url"
    static let description = "Open a URL in the default browser"

    @Parameter(description: "URL to open")
    var url: String

    func perform() async throws -> String {
        do {
            try ServiceContainer.shared.urlOpener.openURL(url)
            let result = OpenURLActionResult(success: true, action: "open_url", url: url)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as URLOpenerError {
            let payload = ToolErrorPayload(error: error.errorCode, message: error.localizedDescription, suggestion: error.suggestion)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}
```

**OpenURLActionResult 结构体（添加到 ToolRegistrar.swift）：**

```swift
private struct OpenURLActionResult: Codable {
    let success: Bool
    let action: String
    let url: String
}
```

### MCP 工具返回格式

**成功返回（示例）：**
```json
{"action": "screenshot", "image_data": "/9j/4AAQSkZJRg...", "success": true}
{"action": "get_accessibility_tree", "role": "AXWindow", "title": "Calculator", "children": [...]}
{"action": "open_url", "success": true, "url": "https://example.com"}
```

**错误返回（使用 ToolErrorPayload 格式）：**
```json
{"error": "window_capture_failed", "message": "Failed to capture window 12345", "suggestion": "Use list_windows to get valid window IDs."}
{"error": "invalid_url", "message": "Invalid URL: 'not-a-url'", "suggestion": "Provide a valid http:// or https:// URL."}
```

### HelperMCPServerTests 更新

Story 1.4 已将 stub 测试改为检查 `screenshot` 工具。本 Story 实现后 `screenshot` 不再是 stub，需要删除或更新 `test_stubTool_perform_returnsNotYetImplemented` 测试。建议：**删除此测试**，因为全部 15 个工具都有真实实现后不再需要 stub 验证。

### 文件结构

需要创建/修改的文件：

```
Sources/AxionHelper/
  Protocols/
    ScreenshotCapturing.swift       # NEW: 截图协议
    URLOpening.swift                # NEW: URL 打开协议
    WindowManaging.swift            # UPDATE: 添加 getAXTree(windowId:maxNodes:) 方法
  Services/
    ScreenshotService.swift         # NEW: CGWindowListCreateImage 截图实现
    URLOpenerService.swift          # NEW: NSWorkspace URL 打开实现
    AccessibilityEngine.swift       # UPDATE: 实现 getAXTree 方法，提取窗口匹配逻辑
    ServiceContainer.swift          # UPDATE: 添加 screenshotCapture 和 urlOpener 属性
  MCP/
    ToolRegistrar.swift             # UPDATE: 替换 3 个工具的 stub 实现

Tests/AxionHelperTests/
  Services/
    ScreenshotServiceTests.swift    # NEW: base64 编码、大小限制测试
    URLOpenerServiceTests.swift     # NEW: URL 验证逻辑测试
  Tools/
    ScreenshotUrlToolTests.swift    # NEW: 3 个工具的 Mock 集成测试
  Mocks/
    MockServices.swift              # UPDATE: 添加 MockScreenshotCapture, MockURLOpener, 更新 ServiceContainerFixture
  MCP/
    HelperMCPServerTests.swift      # UPDATE: 删除 stub 测试
```

### Package.swift 不需要修改

本 Story 不需要修改 Package.swift。`CGWindowListCreateImage` 属于 CoreGraphics 框架，`NSWorkspace` 属于 AppKit 框架，macOS 平台默认可用，无需显式声明 SPM 依赖。

### 前一个 Story 的经验教训

**Story 1.4 的关键经验：**
- ServiceContainer 模式：通过协议 + ServiceContainer.shared 实现依赖注入，测试时替换为 Mock
- 工具实现模式：`perform()` 方法内 `do/catch` 捕获自定义 Error 类型，转换为 `ToolErrorPayload` JSON
- `ToolErrorPayload` 是 ToolRegistrar.swift 中的 `private struct`，所有工具共用
- 每个错误类型都需要 `errorCode: String`, `errorDescription: String?`, `suggestion: String` 属性
- MCPServer.run(transport: .stdio) 不阻塞，stdout 被 MCP JSON-RPC 占用
- `@Parameter(key:)` 指定 snake_case JSON 参数名
- 所有 122 个单元测试通过
- ToolNames.swift 已包含本 Story 所有工具名常量

**Story 1.3 的关键经验：**
- AccessibilityEngine 已有 `buildAXTree` 方法和 `NodeBudget` 截断机制
- `getWindowState` 已返回 `axTree: AXElement?` 字段
- 窗口匹配使用 title 精确匹配 -> 模糊匹配 -> 首窗口降级的策略

**Story 1.2 的关键经验：**
- `@Tool` 宏从 Swift 类型自动生成 JSON Schema
- CallTool.Result.Content 使用 `.text(String, annotations:, _meta:)` 元组模式

**Story 1.1 的关键经验：**
- swift-tools-version: 6.1，编译器 6.2.4
- import 顺序：系统 -> 第三方 -> 项目内部
- 测试命名：`test_方法名_场景_预期结果`

### 命名规则（必须遵守）

| 类别 | 规则 | 示例 |
|------|------|------|
| Swift 类型名 | PascalCase | ScreenshotService, ScreenshotError, URLOpenerService |
| Swift 方法名 | camelCase，动词开头 | captureWindow(windowId:), captureFullScreen(), openURL(_:) |
| Swift 属性 | camelCase | screenshotCapture, urlOpener |
| MCP 工具名 | snake_case（不变） | screenshot, get_accessibility_tree, open_url |
| JSON 字段 | snake_case（通过 CodingKeys） | image_data, max_nodes, window_id |
| 文件名 | 与主类型同名 | ScreenshotService.swift, URLOpenerService.swift |
| import 顺序 | 系统 -> 第三方 -> 项目内部 | CoreGraphics, AppKit -> MCP, MCPTool -> AxionCore |

### 禁止事项（反模式）

- **不得修改 AxionCLI 或 AxionCore 的代码**（本 Story 只在 AxionHelper target 内部工作）
- **不得 import AxionCLI**（进程间隔离，仅通过 MCP 通信）
- **不得使用 print() 输出到 stdout**（stdout 被 MCP JSON-RPC 占用）
- **不得在 AxionHelper 中做 LLM 调用**（Helper 只做桌面操作）
- **工具参数 JSON 使用 snake_case**（已通过 `@Parameter(key:)` 设定）
- **不得调用外部 cua-driver 二进制**（AxionHelper 直接使用 macOS CoreGraphics/AppKit API）
- **不得修改已注册工具的参数定义**（@Tool struct 的 @Parameter 声明保持不变，除非添加新的可选参数）
- **不得创建新的错误类型体系**（使用 ScreenshotError 和 URLOpenerError 枚举，遵循 AppLauncherError 模式）
- **截图不得持久化到磁盘**（NFR12: 截图数据仅用于当前任务，内存中处理，用完即弃）
- **不得截取无权限的窗口**（需要屏幕录制权限，错误时给出明确提示）

### 测试策略

**ScreenshotService 测试（核心可测试逻辑）：**

1. **base64 编码格式验证** -- 截图结果是否为合法 base64 字符串
2. **大小限制测试** -- 模拟超过 5MB 的截图，验证压缩逻辑
3. **JPEG 转换测试** -- CGImage -> JPEG Data 转换是否正确
4. **窗口不存在错误** -- 传入无效 windowId 返回 `windowCaptureFailed` 错误
5. **屏幕录制权限测试** -- 使用 `try XCTSkipIf(!CGPreflightScreenCaptureAccess())` 跳过无权限环境

**URLOpenerService 测试（核心可测试逻辑）：**

1. **URL 格式验证** -- "not-a-url" 返回 `invalidURL` 错误
2. **协议限制** -- "ftp://example.com" 返回 `unsupportedScheme` 错误
3. **合法 URL** -- "https://example.com" 不抛出错误（使用 Mock NSWorkspace 或验证 URL 解析逻辑）

**AccessibilityEngine.getAXTree 测试：**

1. **窗口不存在** -- 传入无效 windowId 返回 `windowNotFound` 错误
2. **截断验证** -- 传入 maxNodes=5，验证返回的树节点数不超过 5

**Mock 策略：**

```swift
// MockScreenshotCapture
struct MockScreenshotCapture: @unchecked Sendable, ScreenshotCapturing {
    var captureWindowHandler: @Sendable (Int) throws -> String
    var captureFullScreenHandler: @Sendable () throws -> String

    func captureWindow(windowId: Int) throws -> String {
        try captureWindowHandler(windowId)
    }
    func captureFullScreen() throws -> String {
        try captureFullScreenHandler()
    }
}

// MockURLOpener
struct MockURLOpener: @unchecked Sendable, URLOpening {
    var openURLHandler: @Sendable (String) throws -> Void

    func openURL(_ urlString: String) throws {
        try openURLHandler(urlString)
    }
}
```

**ServiceContainerFixture 更新：**

```swift
static func apply(
    appLauncher: (any AppLaunching)? = nil,
    accessibilityEngine: (any WindowManaging)? = nil,
    inputSimulation: (any InputSimulating)? = nil,
    screenshotCapture: (any ScreenshotCapturing)? = nil,   // NEW
    urlOpener: (any URLOpening)? = nil                      // NEW
) -> @Sendable () -> Void { ... }
```

**AX 权限注意事项：** 截图操作需要屏幕录制权限。在 CI 环境中无法实际截图。测试策略：
- URL 验证和格式解析的测试无需权限（纯逻辑）
- 实际截图调用使用 `try XCTSkipIf(!CGPreflightScreenCaptureAccess())` 跳过
- 工具集成测试使用 Mock，不依赖真实截图

### 安全分类（供后续 Story 3.3 SafetyChecker 参考）

根据 OpenClick 的 `BACKGROUND_SAFE_TOOLS` 列表：
- `screenshot` -- background_safe
- `get_accessibility_tree` -- background_safe
- `open_url` -- background_safe

本 Story 不实现安全策略，只负责实际的截图/AX tree/URL 操作。

### Project Structure Notes

遵循架构文档定义的目录结构。本 Story 新增文件全部在 AxionHelper target 内部：
- 新协议：`Sources/AxionHelper/Protocols/ScreenshotCapturing.swift`, `Sources/AxionHelper/Protocols/URLOpening.swift`
- 新服务：`Sources/AxionHelper/Services/ScreenshotService.swift`, `Sources/AxionHelper/Services/URLOpenerService.swift`
- 更新服务容器：`Sources/AxionHelper/Services/ServiceContainer.swift`
- 更新窗口管理：`Sources/AxionHelper/Protocols/WindowManaging.swift`, `Sources/AxionHelper/Services/AccessibilityEngine.swift`
- 更新工具注册：`Sources/AxionHelper/MCP/ToolRegistrar.swift`
- 新测试：`Tests/AxionHelperTests/Services/`, `Tests/AxionHelperTests/Tools/`
- 更新 Mock：`Tests/AxionHelperTests/Mocks/MockServices.swift`
- 更新 MCP 测试：`Tests/AxionHelperTests/MCP/HelperMCPServerTests.swift`

不创建新的顶级目录。

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#AxionHelper 目录结构] Helper App 目录结构定义
- [Source: _bmad-output/planning-artifacts/architecture.md#FR28] Helper 截取指定窗口截图
- [Source: _bmad-output/planning-artifacts/architecture.md#FR29] Helper 获取窗口 AX tree
- [Source: _bmad-output/planning-artifacts/architecture.md#FR30] Helper 打开 URL
- [Source: _bmad-output/planning-artifacts/architecture.md#NFR3] 单个 AX 操作 < 200ms
- [Source: _bmad-output/planning-artifacts/architecture.md#NFR12] 截图不持久化到磁盘
- [Source: _bmad-output/planning-artifacts/architecture.md#命名模式] MCP 工具命名 snake_case，JSON 字段 snake_case
- [Source: _bmad-output/planning-artifacts/architecture.md#格式模式] MCP 错误返回格式（error/message/suggestion）
- [Source: _bmad-output/planning-artifacts/architecture.md#通信模式] 截图 base64 不超过 5MB
- [Source: _bmad-output/planning-artifacts/architecture.md#反模式] 必须避免的编码模式
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.5] 原始 Story 定义和 AC
- [Source: _bmad-output/implementation-artifacts/1-4-mouse-keyboard-operations.md] Story 1.4 经验和产出
- [Source: _bmad-output/implementation-artifacts/1-3-app-launch-window-management.md] Story 1.3 经验和产出
- [Source: openclick/mac-app/Sources/Recorder/Screenshotter.swift] OpenClick 截图实现参考（注意：OpenClick 使用 cua-driver 外部二进制，Axion 直接使用 CGWindowListCreateImage）
- [Source: openclick/mac-app/Sources/RecorderCore/AXTree.swift] OpenClick AX 数据模型参考
- [Source: openclick/mac-app/Sources/RecorderCore/CuaDriver.swift] OpenClick 窗口状态和 AX tree 获取参考
- [Source: Sources/AxionHelper/MCP/ToolRegistrar.swift] 现有 15 个工具定义（需替换 3 个为真实实现：ScreenshotTool, GetAccessibilityTreeTool, OpenUrlTool）
- [Source: Sources/AxionHelper/Services/ServiceContainer.swift] 服务容器（需添加 screenshotCapture 和 urlOpener）
- [Source: Sources/AxionHelper/Services/AccessibilityEngine.swift] 现有 AX 引擎（已有 buildAXTree 和 NodeBudget，需添加 getAXTree 公共方法）
- [Source: Sources/AxionHelper/Protocols/WindowManaging.swift] 窗口管理协议（需添加 getAXTree 方法）
- [Source: Sources/AxionHelper/Models/AXElement.swift] AX 元素数据模型（已有，无需修改）
- [Source: Sources/AxionHelper/Models/WindowState.swift] 窗口状态模型（已有，无需修改）
- [Source: Sources/AxionCore/Constants/ToolNames.swift] 工具名常量（已包含 screenshot, getAccessibilityTree, openUrl）
- [Source: Tests/AxionHelperTests/Mocks/MockServices.swift] Mock 模式和 ServiceContainerFixture 参考

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
