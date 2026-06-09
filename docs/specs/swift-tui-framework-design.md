# SwiftTUI：Swift 声明式终端 UI 框架 — 技术方案

> **状态：提议中**
> **作者：Nick**
> **日期：2026-06-07**
> **灵感来源：** ratatui（Rust）、Bubble Tea（Go）、Textual（Python）、cmux CmuxSwiftRender（Swift IR 架构）

---

## 1. 愿景

**"SwiftUI for Terminal"** — 一个纯 Swift、声明式、跨平台的终端 UI 框架。

让 Swift 开发者用熟悉的 SwiftUI 风格 API 构建 terminal 应用，而不是写 ANSI 转义码和处理 termios。

### 目标用户

- Swift CLI 工具开发者（需要 rich terminal 交互）
- Apple 平台开发者（写内部工具 / DevOps 工具）
- Server-side Swift 开发者（admin dashboard、监控面板）
- Coding Agent CLI 开发者（Axion 等需要对话式交互的 agent）

### 核心差异

| 框架 | 语言 | API 风格 | 渲染模型 |
|------|------|---------|---------|
| ratatui | Rust | 命令式 Widget trait | Buffer diff → ANSI flush |
| Bubble Tea | Go | Elm Architecture（Model-Update-View） | 全量重绘 |
| Textual | Python | 声明式（类 React） | DOM diff |
| **SwiftTUI** | **Swift** | **SwiftUI 声明式（ViewBuilder + Modifier Chain）** | **Buffer diff → ANSI flush** |

SwiftTUI 的独特定位：**Swift 开发者零学习成本的声明式 TUI**。

---

## 2. 架构总览

```
┌─────────────────────────────────────────────────┐
│                  用户代码层                       │
│   @main struct MyApp: TerminalApp { ... }        │
└──────────────────────┬──────────────────────────┘
                       │ 声明式 View 树
┌──────────────────────▼──────────────────────────┐
│               View 抽象层                        │
│   Text / VStack / HStack / List / ...           │
│   .foregroundColor() / .bold() / .frame()       │
└──────────────────────┬──────────────────────────┘
                       │ RenderNode IR（受 cmux 启发）
┌──────────────────────▼──────────────────────────┐
│             Layout 引擎                          │
│   Flexbox 简化版（行/列布局 + 约束求解）          │
└──────────────────────┬──────────────────────────┘
                       │ 定位后的 Cell 矩阵
┌──────────────────────▼──────────────────────────┐
│            Terminal Buffer                       │
│   Cell[row][col] = { char, fg, bg, modifier }   │
│   前帧 vs 后帧 Diff                              │
└──────────────────────┬──────────────────────────┘
                       │ 最小 ANSI 转义序列
┌──────────────────────▼──────────────────────────┐
│          Terminal Backend                        │
│   termios raw mode + ANSI 输出 + 事件读取        │
│   支持：原生终端 / tmux / pipe 降级               │
└─────────────────────────────────────────────────┘
```

**设计灵感：**
- **上层 API**：来自 SwiftUI（声明式 View + Modifier Chain）
- **IR 层**：来自 cmux `CmuxSwiftRender.RenderNode`（中间表示 + 渲染后端解耦）
- **渲染层**：来自 ratatui（Buffer diff + 最小 ANSI flush）
- **事件层**：来自 Bubble Tea（统一 Message 模型）

---

## 3. 核心类型设计

### 3.1 View 协议（SwiftUI 风格）

```swift
/// TUI View 协议 — 所有终端 UI 组件的基础
public protocol TerminalView {
    associatedtype Body: TerminalView
    @ViewBuilder var body: Body { get }
}

/// 空视图
public struct EmptyView: TerminalView {
    public typealias Body = Never
}
```

### 3.2 RenderNode IR（受 cmux 启发）

cmux 的 `RenderNode` 证明了声明式 IR 树的可行性。SwiftTUI 复用同一设计，但后端换为终端 Buffer：

```swift
/// 声明式 UI 的中间表示 — 与渲染后端解耦
public struct RenderNode {
    public enum Kind {
        // 布局
        case vstack, hstack, zstack
        case list, section
        // 基础组件
        case text, button, image
        case spacer, divider
        case progressBar
        // 容器
        case scroll, tabs
        // 自定义
        case canvas  // 自定义绘制（直接操作 Cell）
    }

    public var kind: Kind
    public var content: String?
    public var children: [RenderNode]
    public var modifiers: [RenderModifier]
    public var constraints: Constraints  // 布局约束

    public init(kind: Kind, content: String? = nil,
                children: [RenderNode] = [],
                modifiers: [RenderModifier] = [],
                constraints: Constraints = .none)
}
```

### 3.3 Modifier（链式调用）

```swift
/// 视图修饰符 — 链式 API 风格
public struct RenderModifier {
    public let name: String
    public let args: [ModifierArg]
}

/// 与 SwiftUI 一致的 modifier 链式调用
extension TerminalView {
    public func foregroundColor(_ color: TerminalColor) -> ModifiedContent<Self>
    public func background(_ color: TerminalColor) -> ModifiedContent<Self>
    public func bold() -> ModifiedContent<Self>
    public func dim() -> ModifiedContent<Self>
    public func italic() -> ModifiedContent<Self>
    public func underline() -> ModifiedContent<Self>
    public func frame(width: Int? = nil, height: Int? = nil,
                      alignment: Alignment = .center) -> ModifiedContent<Self>
    public func padding(_ edges: Edge.Set = .all, _ length: Int = 1) -> ModifiedContent<Self>
    public func border(_ style: BorderStyle = .single) -> ModifiedContent<Self>
}
```

### 3.4 TerminalCell（渲染最小单元）

```swift
/// 终端渲染的最小单元 — 对应屏幕上的一个字符位置
public struct Cell: Equatable {
    public var character: Character
    public var foreground: TerminalColor
    public var background: TerminalColor
    public var modifier: CellModifier  // bold, dim, italic, underline, reverse, blink

    public static let empty = Cell(character: " ", foreground: .default, background: .default)
}

public struct CellModifier: OptionSet {
    public let rawValue: UInt8
    public static let bold      = CellModifier(rawValue: 1 << 0)
    public static let dim       = CellModifier(rawValue: 1 << 1)
    public static let italic    = CellModifier(rawValue: 1 << 2)
    public static let underline = CellModifier(rawValue: 1 << 3)
    public static let reverse   = CellModifier(rawValue: 1 << 4)
    public static let blink     = CellModifier(rawValue: 1 << 5)
}
```

---

## 4. 渲染管线

### 4.1 三阶段流水线

```
View 树 → RenderNode IR → Layout 求解 → Cell 矩阵 → Diff → ANSI 输出
```

**Phase 1: View → RenderNode（编译时 + 运行时）**

Swift 的 `@ViewBuilder` 在编译时生成 View 树，运行时遍历树生成 `RenderNode` IR。这与 cmux 的 `SwiftViewInterpreter` 不同——SwiftTUI 用的是编译时泛型特化，不需要运行时解析 Swift 源码。

**Phase 2: RenderNode → Layout**

```
VStack(spacing: 1) {
    Text("Title")         → 高度 1
    Text("Description")   → 高度 1
    List { ... }           → 高度 5（约束）
}
总高度 = 1 + 1(spacing) + 1 + 1(spacing) + 5 = 9 行
```

Layout 引擎是简化的 flexbox：
- 主轴方向：子节点按序排列，`spacing` 分隔
- 交叉轴：对齐（leading / center / trailing / stretch）
- 弹性尺寸：`Spacer()` 占据剩余空间，`frame(height:)` 固定尺寸
- 约束传递：父节点告诉子节点可用空间，子节点返回实际尺寸

**Phase 3: Cell 矩阵 → Diff → ANSI**

```swift
/// 终端 Buffer — 与 ratatui 的 Buffer 概念一致
public struct TerminalBuffer {
    public let width: Int
    public let height: Int
    private var cells: [Cell]  // width * height 扁平数组

    public mutating func set(_ position: Position, _ cell: Cell)
    public func diff(from previous: TerminalBuffer) -> [DiffOp]
}

/// Diff 操作 — 只输出变化的部分
public enum DiffOp {
    case moveCursor(Position)
    case writeCell(Position, Cell)
    case clearLine(Int)
    case clearScreen
}
```

Diff 算法逐 Cell 比较，生成最小 ANSI 转义序列集。典型场景（列表选择上下移动）只输出 2 行变化，而不是全屏重绘。

### 4.2 渲染循环

```
┌──────────────┐
│  Event Loop  │◄──── KeyEvent / ResizeEvent / TimerEvent
└──────┬───────┘
       │ Message
┌──────▼───────┐
│  Update      │ → 更新 State → 触发 re-render
└──────┬───────┘
       │
┌──────▼───────┐
│  Render      │ → View 树 → RenderNode → Layout → Cell 矩阵
└──────┬───────┘
       │
┌──────▼───────┐
│  Diff+Flush  │ → 与前帧 Diff → 最小 ANSI → stdout
└──────────────┘
```

与 Elm Architecture / Bubble Tea 类似的 **Model-Update-View** 模式，但 View 层是 SwiftUI 风格的声明式。

---

## 5. 事件系统

### 5.1 TerminalApp 协议

```swift
/// 终端应用入口 — 类似 SwiftUI 的 App 协议
@main
struct MyTodoApp: TerminalApp {
    var body: some TerminalScene {
        WindowGroup {
            TodoListView()
        }
    }
}

/// 应用协议
public protocol TerminalApp {
    associatedtype Body: TerminalScene
    @TerminalSceneBuilder var body: Body { get }
    static func main()  // @main 入口
}
```

### 5.2 消息驱动更新

```swift
/// 统一事件消息 — 受 Bubble Tea Msg 启发
public protocol TerminalMessage {}

/// 按键事件
public struct KeyPress: TerminalMessage {
    public let key: Key
    public let modifiers: Modifiers
}

public enum Key {
    case character(Character)
    case up, down, left, right
    case enter, escape, tab, backspace, delete
    case home, end, pageUp, pageDown
    case f(Int)  // F1-F12
    case ctrl(Character)
}

/// 窗口大小变化
public struct WindowResized: TerminalMessage {
    public let width: Int
    public let height: Int
}

/// 自定义业务消息
public struct TodoAdded: TerminalMessage {
    public let text: String
}
```

### 5.3 Stateful 组件（类 SwiftUI @State）

```swift
struct TodoListView: TerminalView {
    @State private var items: [String] = []
    @State private var input: String = ""
    @State private var selectedIndex: Int = 0

    var body: some TerminalView {
        VStack(spacing: 1) {
            Text("📝 Todo List").bold().foregroundColor(.cyan)

            // 列表组件
            List(items.enumerated(), selection: $selectedIndex) { index, item in
                Text(item)
            }

            // 输入框
            TextField("Add item...", text: $input)
                .onSubmit { message in
                    items.append(input)
                    input = ""
                }
        }
        .border()
        .padding()
    }
}
```

---

## 6. 组件库（MVP 范围）

### 6.1 基础组件

| 组件 | 说明 | 对应 ratatui | 优先级 |
|------|------|-------------|--------|
| `Text` | 文本显示，支持样式 | `Paragraph` | P0 |
| `TextField` | 单行输入框 | `Input` | P0 |
| `Button` | 可点击按钮 | `Button` | P1 |
| `List` | 可选列表 | `List` | P0 |
| `Table` | 表格 | `Table` | P1 |
| `ProgressBar` | 进度条 | `Gauge` | P1 |
| `Spinner` | 加载指示器 | 自定义 | P0 |

### 6.2 布局组件

| 组件 | 说明 | 优先级 |
|------|------|--------|
| `VStack` | 垂直布局 | P0 |
| `HStack` | 水平布局 | P0 |
| `ZStack` | 叠加布局 | P2 |
| `ScrollView` | 可滚动区域 | P1 |
| `Tabs` | 标签页 | P2 |

### 6.3 装饰组件

| 组件 | 说明 | 优先级 |
|------|------|--------|
| `Block` | 边框 + 标题 + 填充 | P0 |
| `Divider` | 分割线 | P0 |
| `Spacer` | 弹性空白 | P0 |
| `Canvas` | 自定义绘制 | P2 |

### 6.4 Modifier 全集

```swift
// 样式修饰符
.foregroundColor(.blue)    // 前景色
.background(.black)        // 背景色
.bold()                    // 粗体
.dim()                     // 暗淡
.italic()                  // 斜体
.underline()               // 下划线

// 布局修饰符
.frame(width: 20, height: 10)      // 固定尺寸
.frame(maxWidth: .infinity)        // 撑满宽度
.padding(1)                        // 内边距
.padding(.horizontal, 2)           // 方向性内边距
.border()                          // 边框
.border(.double)                   // 双线边框

// 交互修饰符
.onKeyPress(.enter) { ... }        // 按键回调
.focusable()                       // 可聚焦
.focused($focusedField)            // 聚焦绑定

// 条件修饰符
.if(condition) { $0.bold() }       // 条件修饰
```

---

## 7. 颜色与样式系统

### 7.1 颜色适配（受 Codex terminal_palette.rs 启发）

```swift
/// 终端颜色 — 自动降级适配
public enum TerminalColor: Equatable {
    case `default`                                    // 终端默认
    case ansi(ANSIColor)                              // 16 色标准
    case ansi256(UInt8)                               // 256 色扩展
    case rgb(UInt8, UInt8, UInt8)                     // TrueColor
    case adaptive(light: TerminalColor, dark: TerminalColor)  // 自适应亮暗

    /// 根据终端能力降级
    func resolved(for profile: ColorProfile) -> TerminalColor
}

/// 标准 16 色
public enum ANSIColor: UInt8 {
    case black = 0, red, green, yellow, blue, magenta, cyan, white
    case brightBlack, brightRed, brightGreen, brightYellow
    case brightBlue, brightMagenta, brightCyan, brightWhite
}

/// 终端颜色能力探测（复用 Codex 方案）
public enum ColorProfile {
    case trueColor    // 支持 RGB (iTerm2, Alacritty, WezTerm, Windows Terminal)
    case ansi256      // 支持 256 色 (xterm, most terminals)
    case ansi16       // 仅 16 色 (基本终端)
    case mono         // 无颜色 (pipe / dumb terminal)

    /// 启动时探测：检查 COLORTERM、TERM、$TERM_PROGRAM 等环境变量
    public static func detect() -> ColorProfile
}

/// 亮度判断 — ITU-R BT.601（复用 Codex color.rs）
public static func isLight(_ rgb: (UInt8, UInt8, UInt8)) -> Bool {
    let luminance = 0.299 * Double(rgb.0) + 0.587 * Double(rgb.1) + 0.114 * Double(rgb.2)
    return luminance > 128
}
```

### 7.2 Border 样式

```swift
/// 边框样式 — 终端 Unicode box drawing
public enum BorderStyle: String {
    case none      = ""
    case single    = "─│┌┐└┘"     // 单线
    case double    = "═║╔╗╚╝"     // 双线
    case rounded   = "─│╭╮╰╯"     // 圆角
    case thick     = "━┃┏┓┗┛"     // 粗线
    case dashed    = "╌╎┌┐└┘"     // 虚线
}
```

---

## 8. Terminal Backend

### 8.1 后端抽象

```swift
/// 终端后端协议 — 支持 Native / Mock / SSH 多后端
public protocol TerminalBackend {
    /// 终端尺寸
    var size: Size { get async }

    /// 初始化终端（raw mode 等）
    func initialize() throws

    /// 恢复终端（cooked mode）
    func restore()

    /// 写入 ANSI 序列
    func write(_ data: [UInt8])

    /// 读取按键事件（非阻塞）
    func pollEvent(timeout: TimeInterval) -> TerminalEvent?

    /// 刷新输出
    func flush()
}

/// 终端事件
public enum TerminalEvent {
    case keyPress(Key, Modifiers)
    case resize(width: Int, height: Int)
    case mouseClick(position: Position, button: MouseButton)
    case mouseScroll(position: Position, direction: ScrollDirection)
    case paste(String)
    case focusGained
    case focusLost
}
```

### 8.2 Native Backend（macOS / Linux）

```swift
/// 原生终端后端 — 基于 termios + ANSI
public final class NativeTerminalBackend: TerminalBackend {
    private var originalTermios: termios?
    private var stdout: FileHandle
    private var stdin: FileHandle

    public func initialize() throws {
        // 1. 保存原始 termios
        var term = termios()
        tcgetattr(STDIN_FILENO, &term)
        originalTermios = term

        // 2. 设置 raw mode
        cfmakeraw(&term)
        term.c_cc[VMIN] = 0
        term.c_cc[VTIME] = 1  // 100ms read timeout
        tcsetattr(STDIN_FILENO, TCSANOW, &term)

        // 3. 开启鼠标追踪（可选）
        write("\u{1B}[?1000h".data(using: .ascii)!)

        // 4. 开启 bracket paste
        write("\u{1B}[?2004h".data(using: .ascii)!)

        // 5. 查询终端尺寸
        // ioctl(TIOCGWINSZ)
    }

    public func restore() {
        // 关闭鼠标追踪、bracket paste
        write("\u{1B}[?2004l".data(using: .ascii)!)
        write("\u{1B}[?1000l".data(using: .ascii)!)

        // 恢复原始 termios
        if var term = originalTermios {
            tcsetattr(STDIN_FILENO, TCSANOW, &term)
        }
    }
}
```

### 8.3 降级策略

| 场景 | 行为 |
|------|------|
| 正常 TTY | 全功能（raw mode + ANSI + mouse） |
| tmux / screen | 自动检测 `TMUX`/`TERM` 环境变量，禁用部分序列 |
| Pipe 模式（`cmd \| app`） | 降级到 line-oriented 输出（仅渲染最终状态） |
| SSH 到旧系统 | 降级到 ANSI16 颜色 + 基本交互 |
| Windows Terminal | 支持（通过 Windows VT100 序列） |
| dumb terminal | 纯文本输出 |

---

## 9. 完整示例

### 9.1 Hello World

```swift
import SwiftTUI

@main
struct HelloWorld: TerminalApp {
    var body: some TerminalScene {
        WindowGroup {
            VStack(spacing: 1) {
                Text("Hello, Terminal!")
                    .bold()
                    .foregroundColor(.adaptive(light: .rgb(0, 95, 135), dark: .ansi(.cyan)))

                Text("Press q to quit")
                    .dim()
            }
            .border(.rounded)
            .padding(1)
            .onKeyPress(.character("q")) { app in
                app.exit()
            }
        }
    }
}
```

### 9.2 可交互的 Todo 列表

```swift
import SwiftTUI

@main
struct TodoApp: TerminalApp {
    var body: some TerminalScene {
        WindowGroup {
            TodoView()
        }
    }
}

struct TodoView: TerminalView {
    @State private var items: [TodoItem] = []
    @State private var input: String = ""
    @State private var selected: Int = 0
    @State private var showHelp: Bool = false

    struct TodoItem {
        let text: String
        var done: Bool = false
    }

    var body: some TerminalView {
        VStack(spacing: 1) {
            // 标题栏
            HStack {
                Text("📝 Todo").bold().foregroundColor(.cyan)
                Spacer()
                Text("\(items.count) items").dim()
            }

            Divider()

            // 列表
            if items.isEmpty {
                Text("No items. Type to add.").dim()
                    .frame(maxWidth: .infinity)
            } else {
                List(items.enumerated(), selection: $selected) { index, item in
                    HStack {
                        Text(item.done ? "✓" : "○")
                            .foregroundColor(item.done ? .ansi(.green) : .dim)
                        Text(item.text)
                            .if(item.done) { $0.dim().italic() }
                    }
                }
            }

            Divider()

            // 输入区
            HStack {
                Text("> ").foregroundColor(.ansi(.green))
                TextField("Add todo...", text: $input)
                    .onSubmit {
                        guard !input.isEmpty else { return }
                        items.append(TodoItem(text: input))
                        input = ""
                    }
            }
        }
        .border(.rounded, title: "Todo App")
        .padding(1)
        .onKeyPress(.up) { selected = max(0, selected - 1) }
        .onKeyPress(.down) { selected = min(items.count - 1, selected + 1) }
        .onKeyPress(.character("d")) { items[selected].done.toggle() }
        .onKeyPress(.character("?")) { showHelp.toggle() }
    }
}
```

### 9.3 Agent 聊天界面（Axion 用例）

```swift
struct ChatView: TerminalView {
    @State private var messages: [Message] = []
    @State private var input: String = ""
    @State private var isAgentBusy: Bool = false

    var body: some TerminalView {
        VStack(spacing: 0) {
            // 消息区（可滚动）
            ScrollView(.vertical) {
                ForEach(messages) { msg in
                    MessageBubble(message: msg)
                }
            }

            Divider()

            // 状态栏
            HStack {
                if isAgentBusy {
                    Spinner()
                    Text("Thinking...")
                } else {
                    Text("Ready").foregroundColor(.ansi(.green))
                }
                Spacer()
                Text("Ctrl+C cancel | / help").dim()
            }
            .padding(.horizontal, 1)

            // 输入区
            TextField("Message...", text: $input)
                .padding(1)
                .onSubmit { sendMessage() }
        }
    }
}

struct MessageBubble: TerminalView {
    let message: Message

    var body: some TerminalView {
        HStack(spacing: 1) {
            // 角色圆点
            Text("●")
                .foregroundColor(message.role == .user ? .ansi(.blue) : .ansi(.green))

            // 消息内容
            VStack(alignment: .leading, spacing: 0) {
                Text(message.role.rawValue).dim()
                Text(message.content)
            }
        }
    }
}
```

---

## 10. 与 ratatui 的关键差异

| 维度 | ratatui (Rust) | SwiftTUI (Swift) |
|------|----------------|-------------------|
| **API 风格** | 命令式 `impl Widget for MyWidget` | 声明式 `var body: some TerminalView` |
| **状态管理** | 手动 `App` struct + `fn update()` | `@State` 属性包装器（自动 diff） |
| **类型系统** | Widget trait 静态分发 | View 协议 + 泛型（类似 SwiftUI OpaqueReturnType） |
| **布局** | Flexbox（`Layout::split()`） | 简化 Flexbox（`VStack/HStack` 自动求解） |
| **渲染** | `Frame` + `Buffer` + `diff` | `TerminalBuffer` + `diff`（相同思路） |
| **事件** | `crossterm::Event` | `TerminalEvent` + `TerminalMessage` |
| **后端** | crossterm / termion | 自建 `TerminalBackend`（termios 封装） |
| **鼠标支持** | 通过 crossterm | 通过 ANSI X10/X11 序列 |
| **Unicode** | 部分 CJK 支持 | 原生 Swift String（完整 Unicode + grapheme cluster） |

### SwiftTUI 相对 ratatui 的优势

1. **声明式 API** — SwiftUI 开发者零学习成本
2. **完整 Unicode** — Swift String 原生处理 grapheme cluster，CJK 宽度计算更准确
3. **@State 自动更新** — 不需要手动管理状态 diff
4. **async/await 原生支持** — 事件循环用 Swift Concurrency
5. **SPM 分发** — 一行依赖引入

### ratatui 相对 SwiftTUI 的优势

1. **性能** — Rust 零成本抽象，diff 算法极致优化
2. **生态** — 40k star，大量社区 Widget
3. **成熟度** — 5 年迭代，终端兼容性久经考验
4. **跨平台** — Windows/Linux/macOS 全覆盖

---

## 11. MVP 实施计划

### Phase 1: 核心渲染引擎（4 周）

**目标：能渲染一个 `Text("Hello")` 到终端**

| 周 | 交付物 | 说明 |
|----|--------|------|
| W1 | `TerminalBackend` + `NativeTerminalBackend` | termios raw mode、终端尺寸查询、ANSI 输出 |
| W1 | `Cell` + `TerminalBuffer` | 渲染最小单元 + Buffer 结构 |
| W2 | `RenderNode` IR + `RenderModifier` | 中间表示定义（参考 cmux） |
| W2 | `TerminalView` 协议 + `Text` 组件 | 最基础的 View 和 Text |
| W3 | `VStack` / `HStack` + 简化 Layout 引擎 | 行列布局 + flex 分配 |
| W3 | Diff 算法 + ANSI 序列生成 | Buffer diff → 最小 ANSI 输出 |
| W4 | `Block`（边框）+ `Spacer` + `Divider` | 视觉分隔 |
| W4 | 基础事件循环 + `onKeyPress` | 事件驱动渲染循环 |

### Phase 2: 交互组件（3 周）

| 周 | 交付物 |
|----|--------|
| W5 | `List` 组件（选择、高亮、滚动） |
| W5 | `TextField` 组件（光标、编辑、bracket paste） |
| W6 | `Button` + focus 系统 |
| W6 | `ProgressBar` + `Spinner` |
| W7 | `ScrollView`（垂直滚动区域） |
| W7 | `@State` 属性包装器 + 自动 re-render |

### Phase 3: 样式与完善（2 周）

| 周 | 交付物 |
|----|--------|
| W8 | `TerminalColor` + `ColorProfile.detect()` + 颜色降级链 |
| W8 | `BorderStyle`（5 种边框样式） |
| W9 | 鼠标支持（click + scroll） |
| W9 | tmux / screen 兼容性 |

### Phase 4: 发布准备（1 周）

| 周 | 交付物 |
|----|--------|
| W10 | SPM Package 发布 |
| W10 | README + 示例 + 文档 |
| W10 | CI（macOS + Linux） |

**总计：约 10 周（2.5 个月）**

---

## 12. 包结构

```
SwiftTUI/
├── Package.swift
├── Sources/
│   └── SwiftTUI/
│       ├── Core/
│       │   ├── TerminalView.swift          // View 协议
│       │   ├── TerminalApp.swift           // App 入口
│       │   ├── RenderNode.swift            // IR 节点（参考 cmux）
│       │   ├── RenderModifier.swift        // 修饰符（参考 cmux）
│       │   ├── ModifiedContent.swift       // 修饰符容器
│       │   └── ViewBuilder.swift           // @ViewBuilder
│       │
│       ├── Rendering/
│       │   ├── Cell.swift                  // 终端 Cell
│       │   ├── TerminalBuffer.swift        // 渲染 Buffer
│       │   ├── BufferDiff.swift            // Diff 算法
│       │   ├── ANSIEscape.swift            // ANSI 序列生成
│       │   └── RenderPass.swift            // 渲染管线
│       │
│       ├── Layout/
│       │   ├── LayoutEngine.swift          // 简化 Flexbox
│       │   ├── LayoutResult.swift          // 布局结果
│       │   ├── Constraints.swift           // 布局约束
│       │   └── Size.swift                  // 尺寸类型
│       │
│       ├── Widgets/
│       │   ├── Text.swift                  // 文本
│       │   ├── TextField.swift             // 输入框
│       │   ├── Button.swift                // 按钮
│       │   ├── List.swift                  // 列表
│       │   ├── Table.swift                 // 表格
│       │   ├── ProgressBar.swift           // 进度条
│       │   ├── Spinner.swift               // 加载指示
│       │   ├── Block.swift                 // 边框容器
│       │   ├── Divider.swift               // 分割线
│       │   ├── Spacer.swift                // 弹性空白
│       │   ├── ScrollView.swift            // 滚动视图
│       │   └── Canvas.swift                // 自定义绘制
│       │
│       ├── Layouts/
│       │   ├── VStack.swift                // 垂直布局
│       │   ├── HStack.swift                // 水平布局
│       │   └── ZStack.swift                // 叠加布局
│       │
│       ├── Style/
│       │   ├── TerminalColor.swift         // 颜色系统
│       │   ├── ColorProfile.swift          // 颜色探测
│       │   ├── BorderStyle.swift           // 边框样式
│       │   ├── CellModifier.swift          // Cell 样式位掩码
│       │   └── Theme.swift                 // 主题
│       │
│       ├── Terminal/
│       │   ├── TerminalBackend.swift       // 后端协议
│       │   ├── NativeBackend.swift         // 原生终端 (termios)
│       │   ├── MockBackend.swift           // 测试 Mock
│       │   ├── TerminalEvent.swift         // 事件类型
│       │   ├── KeyEvent.swift              // 按键解析
│       │   ├── MouseEvent.swift            // 鼠标事件
│       │   └── TermiosHelper.swift         // termios C 互操作
│       │
│       └── State/
│           ├── State.swift                 // @State
│           ├── Binding.swift               // @Binding
│           ├── ObservedObject.swift         // @ObservedObject
│           └── EventLoop.swift             // 主事件循环
│
├── Tests/
│   └── SwiftTUITests/
│       ├── Core/
│       ├── Rendering/
│       ├── Layout/
│       └── Widgets/
│
└── Examples/
    ├── HelloWorld/
    ├── TodoApp/
    └── ChatUI/
```

---

## 13. 测试策略

### 单元测试（不需要真实终端）

| 测试目标 | 方法 |
|---------|------|
| Layout 引擎 | 给定 RenderNode + 尺寸约束 → 验证 LayoutResult |
| Buffer Diff | 给定前后帧 Buffer → 验证 DiffOp 序列 |
| ANSI 生成 | 给定 DiffOp → 验证 ANSI 字节序列 |
| RenderNode 生成 | 给定 View 树 → 验证 IR 结构 |
| 颜色降级 | 给定 RGB + ColorProfile → 验证降级结果 |
| 事件解析 | 给定输入字节流 → 验证 TerminalEvent |

**关键：所有测试通过 `MockBackend` 运行，不依赖真实终端。**

### 集成测试（需要真实终端）

- 在 iTerm2、Terminal.app、Alacritty、WezTerm 中分别截图对比
- tmux 环境下测试
- SSH 环境下测试

### Snapshot 测试

- 每个组件的期望输出保存为 ANSI snapshot 文件
- CI 中对比实际输出与 snapshot

---

## 14. 风险与缓解

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| Swift 泛型编译速度慢 | 高 | 开发体验差 | 分模块编译、减少泛型嵌套、预编译类型擦除 |
| termios 跨平台差异 | 中 | Linux/Windows 兼容性 | 抽象 `TerminalBackend`，平台特定实现隔离 |
| 终端兼容性无底洞 | 高 | 维护负担重 | MVP 只支持 top 5 终端（iTerm2、Alacritty、WezTerm、Terminal.app、Windows Terminal） |
| `@State` 实现 SwiftUI 不开放 | 中 | 无法复用 SwiftUI 运行时 | 自建简化版 StateManager（不依赖 SwiftUI 私有 API） |
| Unicode 宽度计算 | 中 | CJK/Emoji 对齐错乱 | 使用 `wcwidth()` 或 Swift grapheme cluster + Unicode 属性 |
| 性能（大列表） | 低 | 滚动卡顿 | 虚拟化（只渲染可见行）+ 增量 diff |

---

## 15. 开源策略

### 项目定位

- **名称：** SwiftTUI（Swift Terminal UI）
- **仓库：** 独立 GitHub 仓库（不属于 Axion 项目）
- **许可证：** MIT（最大化采用率）
- **Swift 版本：** 5.9+（Windows/Linux 支持） / 6.0+（strict concurrency）

### 推广路径

1. **Axion 先吃自己的狗粮** — Epic 38 的交互组件用 SwiftTUI 重构
2. **GitHub README 精美动图** — 展示示例应用的交互效果（这是 TUI 框架最重要的营销）
3. **Swift Forums 发帖** — "Announcing SwiftTUI: SwiftUI for Terminal"
4. **Hacker News / Reddit** — "Show HN: A declarative terminal UI framework in Swift"
5. **SwiftConf / try! Swift 演讲** — 技术深度分享

### 与 cmux 的关系

- **灵感来源：** cmux 的 `RenderNode` IR 架构证明了声明式 UI 中间层的可行性
- **不共享代码：** SwiftTUI 是独立项目，不 fork cmux 代码（cmux 是 GPLv3 + 商业应用，SwiftTUI 是 MIT）
- **设计借鉴：** `RenderNode.Kind` 枚举、`RenderModifier` 结构、`Environment` 作用域链

---

## 16. 总结

SwiftTUI 要解决的核心问题：**Swift 没有好用的 TUI 框架，而 Swift 开发者数量庞大且习惯了声明式 UI。**

| 优势 | 劣势 |
|------|------|
| ✅ 零竞争蓝海 | ❌ Swift CLI 生态盘子较小 |
| ✅ SwiftUI API 零学习成本 | ❌ 10 周 MVP 开发投入 |
| ✅ Axion 可作为第一个真实用户 | ❌ 终端兼容性是长期维护负担 |
| ✅ cmux 验证了 IR 架构可行性 | ❌ 需要自建 terminal backend |
| ✅ Swift 原生 Unicode 优势 | ❌ 性能可能不如 ratatui |
| ✅ SPM 一行引入 | ❌ @State 需要自建（不依赖 SwiftUI） |

**建议：先做 4 周 MVP（Phase 1），用 Axion 的一个简单场景验证。如果体验好，继续 Phase 2-4。**
