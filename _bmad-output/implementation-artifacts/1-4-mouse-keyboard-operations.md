# Story 1.4: 鼠标与键盘操作

Status: review

## Story

As a CLI 进程,
I want Helper 可以执行鼠标和键盘操作,
So that 自动化任务可以与桌面 UI 交互.

## Acceptance Criteria

1. **AC1: click 单击操作**
   - Given 屏幕坐标 (x, y) 在有效范围内
   - When 调用 click
   - Then 在指定位置执行单击操作，返回成功

2. **AC2: double_click 双击操作**
   - Given 屏幕坐标 (x, y) 在有效范围内
   - When 调用 double_click
   - Then 在指定位置执行双击操作，返回成功

3. **AC3: right_click 右键点击操作**
   - Given 屏幕坐标 (x, y) 在有效范围内
   - When 调用 right_click
   - Then 在指定位置执行右键点击操作，返回成功

4. **AC4: type_text 文本输入**
   - Given 文本光标在输入框中
   - When 调用 type_text 传入 "Hello World"
   - Then 输入框中出现 "Hello World" 文本

5. **AC5: press_key 按键**
   - Given 文本光标活跃
   - When 调用 press_key 传入 "return"
   - Then 按下回车键

6. **AC6: hotkey 组合键**
   - Given 组合键参数 "cmd+c"
   - When 调用 hotkey
   - Then 执行 Command+C 快捷键

7. **AC7: scroll 滚动**
   - Given 滚动参数（direction: "down", amount: 3）
   - When 调用 scroll
   - Then 在指定方向滚动指定量

8. **AC8: drag 拖拽**
   - Given 拖拽起止坐标
   - When 调用 drag
   - Then 执行从起点到终点的拖拽操作

## Tasks / Subtasks

- [x] Task 1: 实现 InputSimulation 服务 — 鼠标操作 (AC: #1, #2, #3, #7, #8)
  - [x] 1.1 创建 `Sources/AxionHelper/Protocols/InputSimulating.swift`：定义 `InputSimulating` 协议（click, doubleClick, rightClick, scroll, drag 五个方法）
  - [x] 1.2 创建 `Sources/AxionHelper/Services/InputSimulationService.swift`：使用 `CGEvent` API 实现鼠标操作
  - [x] 1.3 实现 `click(x:y:)`：`CGEventCreateMouseEvent` + `kCGEventLeftMouseDown` / `kCGEventLeftMouseUp` 序列
  - [x] 1.4 实现 `doubleClick(x:y:)`：连续两次 click 事件，间隔适当延迟
  - [x] 1.5 实现 `rightClick(x:y:)`：`kCGEventRightMouseDown` / `kCGEventRightMouseUp`
  - [x] 1.6 实现 `scroll(direction:amount:)`：`CGEventCreateScrollWheelEvent` + `kCGScrollEventUnitPixel`
  - [x] 1.7 实现 `drag(fromX:fromY:toX:toY:)`：mouseDown → mouseMove → mouseUp 序列，带平滑插值
  - [x] 1.8 添加坐标范围验证（超出屏幕尺寸返回错误）

- [x] Task 2: 实现 InputSimulation 服务 — 键盘操作 (AC: #4, #5, #6)
  - [x] 2.1 在 `InputSimulationService` 中实现键盘方法
  - [x] 2.2 实现 `typeText(text:)`：逐字符 `CGEventCreateKeyboardEvent`，处理 Unicode 字符
  - [x] 2.3 实现 `pressKey(key:)`：将 key 名称映射为 `CGKeyCode`，发送 keyDown + keyUp
  - [x] 2.4 实现 `hotkey(keys:)`：解析 "cmd+c" 格式，同时按下修饰键 + 主键，然后释放
  - [x] 2.5 实现 key name → CGKeyCode 映射表（return, tab, escape, delete, space, arrow keys, F-keys 等）
  - [x] 2.6 实现 modifier key 解析（cmd, shift, ctrl, alt/option 及组合如 "cmd+shift+s"）

- [x] Task 3: 注册 InputSimulation 服务到 ServiceContainer (AC: #1-#8)
  - [x] 3.1 更新 `Sources/AxionHelper/Services/ServiceContainer.swift`：添加 `inputSimulation: any InputSimulating` 属性
  - [x] 3.2 默认初始化为 `InputSimulationService()`

- [x] Task 4: 替换 ToolRegistrar 中 Story 1.4 工具的 stub 实现 (AC: #1-#8)
  - [x] 4.1 更新 `ClickTool.perform()` 调用 InputSimulationService.click
  - [x] 4.2 更新 `DoubleClickTool.perform()` 调用 InputSimulationService.doubleClick
  - [x] 4.3 更新 `RightClickTool.perform()` 调用 InputSimulationService.rightClick
  - [x] 4.4 更新 `TypeTextTool.perform()` 调用 InputSimulationService.typeText
  - [x] 4.5 更新 `PressKeyTool.perform()` 调用 InputSimulationService.pressKey
  - [x] 4.6 更新 `HotkeyTool.perform()` 调用 InputSimulationService.hotkey
  - [x] 4.7 更新 `ScrollTool.perform()` 调用 InputSimulationService.scroll
  - [x] 4.8 更新 `DragTool.perform()` 调用 InputSimulationService.drag
  - [x] 4.9 所有工具返回 JSON 字符串格式结果

- [x] Task 5: 编写单元测试 (AC: #1-#8)
  - [x] 5.1 创建 `Tests/AxionHelperTests/Services/InputSimulationServiceTests.swift`
  - [x] 5.2 创建 `Tests/AxionHelperTests/Tools/MouseKeyboardToolTests.swift`
  - [x] 5.3 测试 key name → CGKeyCode 映射（pressKey 的核心逻辑）
  - [x] 5.4 测试 hotkey 解析（"cmd+c" → flags + keyCode）
  - [x] 5.5 测试 scroll direction 解析（"up"/"down"/"left"/"right"）
  - [x] 5.6 测试坐标验证（负数、超出屏幕返回错误）
  - [x] 5.7 测试所有 8 个工具通过 ServiceContainer 调用的集成（使用 Mock）
  - [x] 5.8 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Services"` 确认所有测试通过

## Dev Notes

### 关键架构约束

**本 Story 将 ToolRegistrar 中 8 个工具的 stub 替换为真实实现。** Story 1.3 建立了 AppLauncher 和 AccessibilityEngine，本 Story 建立 InputSimulationService。剩余 3 个工具仍保持 stub 状态（Story 1.5 实现截图/AX tree/URL）。

**AxionHelper 进程边界不变** — 本 Story 只在 AxionHelper target 内部工作，不修改 AxionCLI 或 AxionCore 的代码。

**NFR3 性能要求：** 单个 AX 操作（点击、输入）从 MCP 请求到结果返回 < 200ms。这意味着 InputSimulationService 的每次调用必须高效，CGEvent 操作本身是微秒级的，可以满足要求。

### 核心 API — macOS CGEvent（CoreGraphics）

鼠标和键盘操作使用 `CGEvent` API（CoreGraphics 框架）。**不调用外部 cua-driver 二进制** — 与 OpenClick 的关键区别，AxionHelper 直接使用 macOS CGEvent API。

**鼠标操作：**

```swift
import CoreGraphics

// 单击
let downEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                        mouseCursorPosition: CGPoint(x: CGFloat(x), y: CGFloat(y)),
                        mouseButton: .left)
downEvent?.post(tap: .cghidEventTap)
let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                      mouseCursorPosition: CGPoint(x: CGFloat(x), y: CGFloat(y)),
                      mouseButton: .left)
upEvent?.post(tap: .cghidEventTap)

// 右键点击：使用 .rightMouseDown / .rightMouseUp + .right

// 双击：设置 clickState
let downEvent = CGEvent(...)
downEvent?.setIntegerValueField(.mouseEventClickState, value: 2)
downEvent?.post(tap: .cghidEventTap)

// 滚动
let scrollEvent = CGEvent(scrollWheelEvent2: nil, units: .pixel,
                           wheelCount: 1, value1: Int32(amount), value2: 0)
scrollEvent?.post(tap: .cghidEventTap)

// 拖拽：leftMouseDown → leftMouseDragged → leftMouseUp
```

**键盘操作：**

```swift
// 按键（pressKey）
let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
keyDownEvent?.post(tap: .cghidEventTap)
let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
keyUpEvent?.post(tap: .cghidEventTap)

// 文本输入（typeText）— 使用 Unicode 字符注入
let source = CGEventSource(stateID: .hidSystemState)
for char in text {
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
    // 使用 Unicode 字符设置
    keyDown?.keyboardSetUnicodeString(string: String(char))
    keyDown?.post(tap: .cghidEventTap)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    keyUp?.keyboardSetUnicodeString(string: String(char))
    keyUp?.post(tap: .cghidEventTap)
}

// 组合键（hotkey）— 先按修饰键，再按主键，然后释放
let source = CGEventSource(stateID: .hidSystemState)
let flags: CGEventFlags = parseModifiers("cmd+shift")  // .maskCommand | .maskShift
let keyCode = keyCodeFor("s")

let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
keyDown?.flags = flags
keyDown?.post(tap: .cghidEventTap)

let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
keyUp?.flags = flags
keyUp?.post(tap: .cghidEventTap)
```

**关键注意：** `CGEvent` 需要 Accessibility 权限（`AXIsProcessTrusted()` 返回 true）。AxionHelper 已在 `axion setup` 中引导用户授权此权限。

### Key Name → CGKeyCode 映射

`pressKey` 工具接收 key 名称字符串（如 "return", "tab"），需要映射到 macOS virtual key code。核心映射表：

```swift
static let keyMap: [String: CGKeyCode] = [
    "return": 0x24,       // 36
    "enter": 0x24,        // alias
    "tab": 0x30,          // 48
    "space": 0x31,        // 49
    "escape": 0x35,       // 53
    "esc": 0x35,          // alias
    "delete": 0x33,       // 51 (Backspace)
    "backspace": 0x33,    // alias
    "forwarddelete": 0x75, // 117
    "home": 0x73,         // 115
    "end": 0x77,          // 119
    "pageup": 0x74,       // 116
    "pagedown": 0x79,     // 121
    "left": 0x7B,         // 123
    "right": 0x7C,        // 124
    "down": 0x7D,         // 125
    "up": 0x7E,           // 126
    "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
    "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
    "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
    // 单字符按键 a-z
    "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
    "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
    "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
    "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
    "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10,
    "z": 0x06,
]
```

### Modifier Key 解析（hotkey 工具）

`hotkey` 工具接收 "cmd+c", "cmd+shift+s", "ctrl+alt+delete" 等格式。解析规则：

1. 按 "+" 分割字符串
2. 最后一个元素是主键，前面都是修饰键
3. 修饰键映射到 `CGEventFlags`：
   - `cmd` / `command` → `.maskCommand`
   - `shift` → `.maskShift`
   - `ctrl` / `control` → `.maskControl`
   - `alt` / `option` → `.maskAlternate`

```swift
func parseHotkey(_ keys: String) -> (flags: CGEventFlags, keyCode: CGKeyCode)? {
    let parts = keys.lowercased().split(separator: "+").map(String.init)
    guard parts.count >= 2 else { return nil }

    var flags: CGEventFlags = []
    for part in parts.dropLast() {
        switch part.trimmingCharacters(in: .whitespaces) {
        case "cmd", "command": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "ctrl", "control": flags.insert(.maskControl)
        case "alt", "option": flags.insert(.maskAlternate)
        default: return nil  // 未知修饰键
        }
    }

    let mainKey = parts.last!.trimmingCharacters(in: .whitespaces)
    guard let keyCode = keyMap[mainKey] else { return nil }
    return (flags, keyCode)
}
```

### Scroll Direction 处理

```swift
func scroll(direction: String, amount: Int) throws {
    let scrollValue: Int32
    switch direction.lowercased() {
    case "up":
        scrollValue = Int32(amount)   // 正值 = 向上
    case "down":
        scrollValue = Int32(-amount)  // 负值 = 向下
    case "left", "right":
        // 水平滚动需要 wheelCount: 2
        let event = CGEvent(scrollWheelEvent2: nil, units: .pixel,
                           wheelCount: 2,
                           value1: 0,  // 垂直
                           value2: direction == "right" ? Int32(amount) : Int32(-amount))
        event?.post(tap: .cghidEventTap)
        return
    default:
        throw InputSimulationError.invalidDirection(direction)
    }
    let event = CGEvent(scrollWheelEvent: nil, units: .pixel, wheelCount: 1, value1: scrollValue)
    event?.post(tap: .cghidEventTap)
}
```

### InputSimulation 错误类型

遵循 Story 1.3 的错误模式（`AppLauncherError`, `AccessibilityEngineError`），创建 `InputSimulationError`：

```swift
enum InputSimulationError: Error, LocalizedError {
    case coordinatesOutOfBounds(x: Int, y: Int)
    case invalidKeyName(String)
    case invalidHotkeyFormat(String)
    case invalidDirection(String)

    var errorDescription: String? { ... }
    var errorCode: String {
        switch self {
        case .coordinatesOutOfBounds: return "coordinates_out_of_bounds"
        case .invalidKeyName: return "invalid_key_name"
        case .invalidHotkeyFormat: return "invalid_hotkey_format"
        case .invalidDirection: return "invalid_direction"
        }
    }
    var suggestion: String { ... }
}
```

### InputSimulating 协议设计

遵循现有协议模式（`AppLaunching`, `WindowManaging`），在 `Sources/AxionHelper/Protocols/` 创建新协议：

```swift
// Sources/AxionHelper/Protocols/InputSimulating.swift
import CoreGraphics
import Foundation

protocol InputSimulating: Sendable {
    func click(x: Int, y: Int) throws
    func doubleClick(x: Int, y: Int) throws
    func rightClick(x: Int, y: Int) throws
    func scroll(direction: String, amount: Int) throws
    func drag(fromX: Int, fromY: Int, toX: Int, toY: Int) throws
    func typeText(_ text: String) throws
    func pressKey(_ key: String) throws
    func hotkey(_ keys: String) throws
}
```

### ServiceContainer 更新

```swift
// 更新 ServiceContainer.swift
struct ServiceContainer: Sendable {
    var appLauncher: any AppLaunching
    var accessibilityEngine: any WindowManaging
    var inputSimulation: any InputSimulating  // NEW

    nonisolated(unsafe) static var shared = ServiceContainer(
        appLauncher: AppLauncherService(),
        accessibilityEngine: AccessibilityEngineService(),
        inputSimulation: InputSimulationService()  // NEW
    )
}
```

### ToolRegistrar 工具实现模式

**严格遵循 Story 1.3 的工具实现模式** — 不修改 `@Tool` struct 的参数声明，只替换 `perform()` 方法体。错误返回 JSON 格式的 `ToolErrorPayload`，而非抛出 MCPError。

```swift
// 以 ClickTool 为例：
@Tool
struct ClickTool {
    static let name = "click"
    static let description = "Perform a single click at the specified coordinates"

    @Parameter(description: "X coordinate")
    var x: Int

    @Parameter(description: "Y coordinate")
    var y: Int

    func perform() async throws -> String {
        do {
            try ServiceContainer.shared.inputSimulation.click(x: x, y: y)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let result = ["success": true, "action": "click", "x": x, "y": y]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as InputSimulationError {
            let payload = ToolErrorPayload(
                error: error.errorCode,
                message: error.localizedDescription,
                suggestion: error.suggestion
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}
```

**注意：** `ToolErrorPayload` 是 `ToolRegistrar.swift` 中的 `private struct`。所有工具共用它，不需要在文件外重新定义。确保工具的 `perform()` 方法中用 `catch let error as InputSimulationError` 捕获自定义错误类型。

### MCP 工具返回格式

**成功返回（示例）：**
```json
{"action": "click", "success": true, "x": 100, "y": 200}
{"action": "type_text", "success": true, "text": "Hello World"}
{"action": "hotkey", "success": true, "keys": "cmd+c"}
{"action": "scroll", "amount": 3, "direction": "down", "success": true}
```

**错误返回（使用 ToolErrorPayload 格式）：**
```json
{"error": "coordinates_out_of_bounds", "message": "Coordinates (9999, 9999) are outside screen bounds", "suggestion": "Use screen coordinates within the display bounds."}
{"error": "invalid_key_name", "message": "Unknown key: 'foo'", "suggestion": "Use standard key names: return, tab, escape, space, a-z, 0-9, f1-f12, etc."}
```

### 拖拽实现细节

拖拽操作需要从起点到终点的平滑移动。推荐实现：

```swift
func drag(fromX: Int, fromY: Int, toX: Int, toY: Int) throws {
    let start = CGPoint(x: CGFloat(fromX), y: CGFloat(fromY))
    let end = CGPoint(x: CGFloat(toX), y: CGFloat(toY))

    // 移动到起点
    let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMove,
                            mouseCursorPosition: start, mouseButton: .left)
    moveEvent?.post(tap: .cghidEventTap)

    // 按下
    let downEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                            mouseCursorPosition: start, mouseButton: .left)
    downEvent?.post(tap: .cghidEventTap)

    // 平滑拖动（插值多个中间点）
    let steps = max(10, Int(hypot(end.x - start.x, end.y - start.y) / 20))
    for i in 1...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let x = start.x + (end.x - start.x) * t
        let y = start.y + (end.y - start.y) * t
        let dragEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                                mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
        dragEvent?.setIntegerValueField(.mouseEventDeltaX, value: Int64(x - (start.x + (end.x - start.x) * CGFloat(i - 1) / CGFloat(steps))))
        dragEvent?.setIntegerValueField(.mouseEventDeltaY, value: Int64(y - (start.y + (end.y - start.y) * CGFloat(i - 1) / CGFloat(steps))))
        dragEvent?.post(tap: .cghidEventTap)
    }

    // 释放
    let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                          mouseCursorPosition: end, mouseButton: .left)
    upEvent?.post(tap: .cghidEventTap)
}
```

### 屏幕尺寸获取

坐标验证需要知道屏幕尺寸：

```swift
var mainScreenSize: CGSize {
    guard let screen = NSScreen.main else { return CGSize(width: 1920, height: 1080) }
    return screen.frame.size
}
```

**注意：** macOS 的屏幕坐标系原点在左上角（CGEvent 使用）还是左下角（Cocoa 使用）？CGEvent 使用的是**主显示器左上角为原点**的全局坐标系（和 Quartz Display Services 一致）。NSScreen 的 frame 使用左下角原点。验证坐标时使用 CGDisplayBounds 获取实际屏幕范围。

```swift
var screenBounds: CGRect {
    CGDisplayBounds(CGMainDisplayID())
}
```

### 文件结构

需要创建/修改的文件：

```
Sources/AxionHelper/
  Protocols/
    InputSimulating.swift         # NEW: 鼠标/键盘操作协议
  Services/
    InputSimulationService.swift  # NEW: CGEvent 实现
    ServiceContainer.swift        # UPDATE: 添加 inputSimulation 属性
  MCP/
    ToolRegistrar.swift           # UPDATE: 替换 8 个工具的 stub 实现

Tests/AxionHelperTests/
  Services/
    InputSimulationServiceTests.swift  # NEW: 按键映射、hotkey 解析等测试
  Tools/
    MouseKeyboardToolTests.swift       # NEW: 8 个工具的 Mock 集成测试
  Mocks/
    MockServices.swift                 # UPDATE: 添加 MockInputSimulation
```

### Package.swift 不需要修改

本 Story 不需要修改 Package.swift。`CGEvent` 和 `CGEventSource` 属于 CoreGraphics 框架，macOS 平台默认可用，无需显式声明 SPM 依赖。

### 前一个 Story 的经验教训

**Story 1.3 的关键经验：**
- ServiceContainer 模式：通过协议 + ServiceContainer.shared 实现依赖注入，测试时替换为 Mock
- 工具实现模式：`perform()` 方法内 `do/catch` 捕获自定义 Error 类型，转换为 `ToolErrorPayload` JSON
- `ToolErrorPayload` 是 ToolRegistrar.swift 中的 `private struct`，所有工具共用
- MCPServer.run(transport: .stdio) 不阻塞，stdout 被 MCP JSON-RPC 占用
- `@Parameter(key:)` 指定 snake_case JSON 参数名
- 所有 70 个测试通过（54 Core/Helper + 16 ATDD red phase）
- ToolNames.swift 已包含本 Story 所有工具名常量

**Story 1.2 的关键经验：**
- `@Tool` 宏从 Swift 类型自动生成 JSON Schema
- CallTool.Result.Content 使用 `.text(String, annotations:, _meta:)` 元组模式

**Story 1.1 的关键经验：**
- swift-tools-version: 6.1，编译器 6.2.4
- import 顺序：系统 → 第三方 → 项目内部
- 测试命名：`test_方法名_场景_预期结果`

### 命名规则（必须遵守）

| 类别 | 规则 | 示例 |
|------|------|------|
| Swift 类型名 | PascalCase | InputSimulationService, InputSimulationError |
| Swift 方法名 | camelCase，动词开头 | click(x:y:), typeText(_:), pressKey(_:) |
| Swift 属性 | camelCase | inputSimulation |
| MCP 工具名 | snake_case（不变） | click, type_text, press_key, hotkey, scroll, drag |
| JSON 字段 | snake_case（通过 CodingKeys） | 在 ToolRegistrar 中返回 JSON 时使用 |
| 文件名 | 与主类型同名 | InputSimulationService.swift, InputSimulating.swift |
| import 顺序 | 系统 → 第三方 → 项目内部 | CoreGraphics, AppKit → MCP, MCPTool → AxionCore |

### 禁止事项（反模式）

- **不得在 AxionHelper 中实现截图、URL 打开**（本 Story 只做鼠标/键盘操作，其余留给 Story 1.5）
- **不得 import AxionCLI**（进程间隔离，仅通过 MCP 通信）
- **不得使用 print() 输出到 stdout**（stdout 被 MCP JSON-RPC 占用）
- **不得在 AxionHelper 中做 LLM 调用**（Helper 只做桌面操作）
- **工具参数 JSON 使用 snake_case**（已通过 `@Parameter(key:)` 设定）
- **不得调用外部 cua-driver 二进制**（AxionHelper 直接使用 macOS CGEvent API，这是与 OpenClick 的关键区别）
- **不得修改已注册工具的参数定义**（@Tool struct 的 @Parameter 声明保持不变）
- **不得创建新的错误类型体系**（使用 InputSimulationError 枚举，遵循 AppLauncherError/AccessibilityEngineError 模式）

### 测试策略

**InputSimulationService 测试（核心可测试逻辑）：**

1. **Key name 映射测试** — 验证 "return" → 0x24, "tab" → 0x30, "a" → 0x00 等映射
2. **Hotkey 解析测试** — "cmd+c" → (.maskCommand, 0x08), "cmd+shift+s" → (.maskCommand | .maskShift, 0x01)
3. **Scroll direction 解析** — "up" 为正值, "down" 为负值, "left"/"right" 水平
4. **坐标验证** — 负数、超屏幕范围返回 `coordinatesOutOfBounds` 错误
5. **无效 key 名称** — "foo" 返回 `invalidKeyName` 错误
6. **无效 hotkey 格式** — "xyz"（无修饰键）返回 `invalidHotkeyFormat` 错误

**Mock 策略：**

```swift
// MockInputSimulation — 遵循 MockAppLauncher / MockAccessibilityEngine 的模式
struct MockInputSimulation: @unchecked Sendable, InputSimulating {
    var clickHandler: @Sendable (Int, Int) throws -> Void
    var doubleClickHandler: @Sendable (Int, Int) throws -> Void
    var rightClickHandler: @Sendable (Int, Int) throws -> Void
    var scrollHandler: @Sendable (String, Int) throws -> Void
    var dragHandler: @Sendable (Int, Int, Int, Int) throws -> Void
    var typeTextHandler: @Sendable (String) throws -> Void
    var pressKeyHandler: @Sendable (String) throws -> Void
    var hotkeyHandler: @Sendable (String) throws -> Void

    // 实现各方法调用对应 handler
}
```

**ServiceContainerFixture 更新：**

```swift
// 更新 MockServices.swift 中的 ServiceContainerFixture
static func apply(
    appLauncher: (any AppLaunching)? = nil,
    accessibilityEngine: (any WindowManaging)? = nil,
    inputSimulation: (any InputSimulating)? = nil  // NEW
) -> @Sendable () -> Void { ... }
```

**AX 权限注意事项：** CGEvent 合成操作需要 Accessibility 权限。在 CI 环境中无法实际执行鼠标/键盘操作。测试策略：
- 映射和解析逻辑的测试无需 AX 权限（纯逻辑）
- 实际 CGEvent 调用的集成测试使用 `try XCTSkipIf(!AXIsProcessTrusted())` 跳过

### 安全分类（供后续 Story 3.3 SafetyChecker 参考）

根据 OpenClick 的 `BACKGROUND_SAFE_TOOLS` 列表，本 Story 的所有工具（click, double_click, right_click, type_text, press_key, hotkey, scroll, drag）都属于 **background_safe** 类别。但注意，这些工具在共享座椅模式下仍需安全检查（Story 3.3 的 SafetyChecker 实现）。本 Story 不实现安全策略，只负责实际的输入模拟。

### Project Structure Notes

遵循架构文档定义的目录结构。本 Story 新增文件全部在 AxionHelper target 内部：
- 新协议：`Sources/AxionHelper/Protocols/InputSimulating.swift`
- 新服务：`Sources/AxionHelper/Services/InputSimulationService.swift`
- 更新服务容器：`Sources/AxionHelper/Services/ServiceContainer.swift`
- 更新工具注册：`Sources/AxionHelper/MCP/ToolRegistrar.swift`
- 新测试：`Tests/AxionHelperTests/Services/` 和 `Tests/AxionHelperTests/Tools/`
- 更新 Mock：`Tests/AxionHelperTests/Mocks/MockServices.swift`

不创建新的顶级目录。

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#AxionHelper 目录结构] Helper App 目录结构定义
- [Source: _bmad-output/planning-artifacts/architecture.md#FR26] Helper 执行鼠标操作
- [Source: _bmad-output/planning-artifacts/architecture.md#FR27] Helper 执行键盘操作
- [Source: _bmad-output/planning-artifacts/architecture.md#NFR3] 单个 AX 操作 < 200ms
- [Source: _bmad-output/planning-artifacts/architecture.md#命名模式] MCP 工具命名 snake_case，JSON 字段 snake_case
- [Source: _bmad-output/planning-artifacts/architecture.md#格式模式] MCP 错误返回格式（error/message/suggestion）
- [Source: _bmad-output/planning-artifacts/architecture.md#反模式] 必须避免的编码模式
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.4] 原始 Story 定义和 AC
- [Source: _bmad-output/project-context.md#Shifted Key 映射] 符号键到基础键的映射（供 Planner prompt 使用）
- [Source: _bmad-output/implementation-artifacts/1-3-app-launch-window-management.md] Story 1.3 经验和产出
- [Source: openclick/src/executor.ts:160-190] BACKGROUND_SAFE_TOOLS 工具分类列表
- [Source: Sources/AxionHelper/MCP/ToolRegistrar.swift] 现有 15 个工具定义（需替换 8 个为真实实现）
- [Source: Sources/AxionHelper/Services/ServiceContainer.swift] 服务容器（需添加 inputSimulation）
- [Source: Sources/AxionHelper/Protocols/AppLaunching.swift] 协议设计参考
- [Source: Sources/AxionHelper/Services/AppLauncher.swift] 服务实现模式参考（错误类型、ServiceContainer 注册模式）
- [Source: Tests/AxionHelperTests/Mocks/MockServices.swift] Mock 模式和 ServiceContainerFixture 参考

## Dev Agent Record

### Agent Model Used

Claude GLM-5.1[1m]

### Debug Log References

- Fixed `CGEventType.mouseMove` -> `.mouseMoved` (SDK naming difference)
- Fixed `scrollWheelEvent2:` -> `scrollWheelEvent2Source:` (Swift API label)
- Fixed scroll wheel parameters: `value1/value2` -> `wheel1/wheel2/wheel3`
- Fixed `keyboardSetUnicodeString` to use `(stringLength:unicodeString:)` instead of `(string:)`
- Updated `HelperMCPServerTests.test_stubTool_perform_returnsNotYetImplemented` to test `screenshot` instead of `click` (since click now has real implementation)

### Completion Notes List

- Implemented all 8 CGEvent-based input operations (click, double_click, right_click, type_text, press_key, hotkey, scroll, drag)
- All 8 MCP tools now return structured JSON responses (success with action details, or error with error/message/suggestion)
- Key name mapping covers: return, tab, escape, space, delete, backspace, forwarddelete, home, end, pageup, pagedown, arrow keys, F1-F12, a-z
- Hotkey parsing supports: cmd/command, shift, ctrl/control, alt/option modifiers in any combination
- Scroll supports 4 directions: up, down, left, right
- Drag uses smooth interpolation with distance-based step count
- Coordinate validation uses CGDisplayBounds for screen bounds checking
- Removed all XCTSkipIf from Story 1.4 tests (45 tests now active)
- Updated existing HelperMCPServerTests stub test to check screenshot instead of click
- All 122 unit tests pass (0 failures)

### File List

- `Sources/AxionHelper/Services/InputSimulationService.swift` — Updated: replaced stub methods with real CGEvent implementations
- `Sources/AxionHelper/MCP/ToolRegistrar.swift` — Updated: replaced 8 tool stub perform() methods with real InputSimulationService calls
- `Tests/AxionHelperTests/Services/InputSimulationServiceTests.swift` — Updated: removed XCTSkipIf from all 25 tests
- `Tests/AxionHelperTests/Tools/MouseKeyboardToolTests.swift` — Updated: removed XCTSkipIf from all 20 tests
- `Tests/AxionHelperTests/MCP/HelperMCPServerTests.swift` — Updated: changed stub test from click to screenshot tool
