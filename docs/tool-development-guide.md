# OpenAgentSDK 工具开发指南

本指南详细说明如何在 OpenAgentSDK 中开发自定义工具，涵盖 `defineTool` 的四种重载、核心类型定义以及工具命名与 inputSchema 编写的最佳实践。

---

## 1. defineTool 四种重载详解

`defineTool` 是工具注册的工厂函数，根据闭包签名自动推导为不同的内部实现。所有重载共享以下参数：

| 参数 | 类型 | 说明 |
|------|------|------|
| `name` | `String` | 工具唯一标识符 |
| `description` | `String` | 工具功能描述（供 LLM 阅读） |
| `inputSchema` | `ToolInputSchema` (即 `[String: Any]`) | JSON Schema 格式的输入定义 |
| `isReadOnly` | `Bool` | 是否只读，默认 `false` |
| `annotations` | `ToolAnnotations?` | 行为注解，默认 `nil` |

### 1.1 Codable + String 返回

自动将 LLM 原始 JSON 解码为 Swift `Codable` 结构体，闭包返回纯字符串。最常用的重载。

```swift
struct WeatherInput: Codable {
    let city: String
    let unit: String?
}

let weatherTool = defineTool(
    name: "get_weather",
    description: "查询指定城市的当前天气",
    inputSchema: [
        "type": "object",
        "properties": [
            "city": ["type": "string", "description": "城市名称"],
            "unit": ["type": "string", "description": "温度单位"]
        ],
        "required": ["city"]
    ],
    isReadOnly: true
) { (input: WeatherInput, context: ToolContext) async throws -> String in
    let unit = input.unit ?? "celsius"
    return "\(input.city) 当前温度: 25°\(unit == "fahrenheit" ? "F" : "C")"
}
```

内部流程：`[String: Any]` -> `JSONSerialization` -> `JSONDecoder` -> `Input` -> 闭包。任何步骤失败自动返回 `isError: true`。

### 1.2 Codable + ToolExecuteResult 返回

闭包返回 `ToolExecuteResult`，可显式控制 `isError` 和类型化内容。适用于需要区分业务错误（非异常）的场景。

```swift
struct FileInput: Codable {
    let path: String
}

let fileTool = defineTool(
    name: "read_file",
    description: "读取文件内容",
    inputSchema: [
        "type": "object",
        "properties": [
            "path": ["type": "string", "description": "文件路径"]
        ],
        "required": ["path"]
    ],
    isReadOnly: true
) { (input: FileInput, context: ToolContext) async throws -> ToolExecuteResult in
    guard let content = try? String(contentsOfFile: input.path) else {
        return ToolExecuteResult(content: "文件不存在: \(input.path)", isError: true)
    }
    return ToolExecuteResult(content: content, isError: false)
}
```

### 1.3 无输入（No-Input）

适用于不需要结构化输入的工具。闭包只接收 `ToolContext`。

```swift
let listTool = defineTool(
    name: "list_tools",
    description: "列出当前可用工具",
    inputSchema: ["type": "object", "properties": [:] as [String: Any]],
    isReadOnly: true
) { (context: ToolContext) async throws -> String in
    return "可用工具: read_file, write_file, bash, glob"
}
```

### 1.4 原始字典输入（Raw Dict）

跳过 Codable 解码，直接传递 `[String: Any]`。适用于输入字段类型不固定的场景。

```swift
let configTool = defineTool(
    name: "config",
    description: "获取或设置配置值",
    inputSchema: [
        "type": "object",
        "properties": [
            "action": ["type": "string", "enum": ["get", "set", "list"]],
            "key": ["type": "string"],
            "value": ["description": "任意类型的配置值"]
        ] as [String: Any],
        "required": ["action"]
    ]
) { (input: [String: Any], context: ToolContext) async -> ToolExecuteResult in
    guard let action = input["action"] as? String else {
        return ToolExecuteResult(content: "缺少 action", isError: true)
    }
    return ToolExecuteResult(content: "操作 \(action) 完成", isError: false)
}
```

注意：Raw Dict 闭包是 `async`（非 `throws`），错误通过 `ToolExecuteResult(isError: true)` 返回。

---

## 2. ToolProtocol 接口说明

所有工具遵循 `ToolProtocol` 协议，`defineTool` 返回值即为此协议的实现。

### 属性与方法

```swift
public protocol ToolProtocol: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: ToolInputSchema { get }  // [String: Any]
    var isReadOnly: Bool { get }
    var annotations: ToolAnnotations? { get } // 默认 nil

    func call(input: Any, context: ToolContext) async -> ToolResult
}
```

`call()` 由 SDK 内部 `ToolExecutor` 调用，开发者通常不需要直接调用。

### ToolAnnotations

```swift
public struct ToolAnnotations: Sendable, Equatable {
    let readOnlyHint: Bool       // 默认 false
    let destructiveHint: Bool    // 默认 true（保守策略）
    let idempotentHint: Bool     // 默认 false
    let openWorldHint: Bool      // 默认 false
}
```

`destructiveHint` 默认为 `true`，即所有工具默认被视为可能有破坏性。这些注解帮助 LLM 决定何时调用工具。

---

## 3. ToolContext 可用字段和用途

`ToolContext` 在每次工具调用时由 SDK 注入，提供运行时上下文和 Store 访问。

### 核心字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `cwd` | `String` | 当前工作目录，用于解析相对路径 |
| `toolUseId` | `String` | 本次调用的唯一 ID |
| `memoryStore` | `MemoryStoreProtocol?` | 跨运行的知识记忆存储 |
| `hookRegistry` | `HookRegistry?` | 生命周期钩子注册表 |

### Store 字段（按需注入）

| 字段 | 用途 |
|------|------|
| `agentSpawner` | 子 Agent 派生 |
| `mailboxStore` / `teamStore` | Agent 间消息与团队管理 |
| `taskStore` | 任务管理 |
| `worktreeStore` | 工作树管理 |
| `planStore` | 计划管理 |
| `cronStore` | 定时任务 |
| `todoStore` | 待办事项 |

### 其他字段

`permissionMode`（权限模式）、`canUseTool`（权限回调）、`skillRegistry`（Skill 注册表）、`fileCache`（文件缓存）、`sandbox`（沙箱配置）、`env`（环境变量）、`senderName`（Agent 名称）、`mcpConnections`（MCP 连接）等。

路径解析示例：
```swift
let resolved = resolvePath(input.path, cwd: context.cwd)
```

---

## 4. ToolResult 和 ToolExecuteResult 返回类型

### ToolResult

`ToolProtocol.call()` 的最终返回类型：

```swift
public struct ToolResult: Sendable {
    let toolUseId: String            // 调用 ID
    let content: String              // 文本内容（计算属性）
    let typedContent: [ToolContent]? // 类型化内容
    let isError: Bool
}
```

### ToolExecuteResult

工具闭包的返回类型，不含 `toolUseId`（由框架补充）：

```swift
public struct ToolExecuteResult: Sendable {
    let content: String
    let typedContent: [ToolContent]?
    let isError: Bool
}
```

### ToolContent 多模态类型

```swift
public enum ToolContent: Sendable {
    case text(String)
    case image(data: Data, mimeType: String)
    case resource(uri: String, name: String?)
}
```

### String vs ToolExecuteResult 的选择

| 返回类型 | 场景 |
|----------|------|
| `String` | 简单成功；错误通过 `throw` 抛出，SDK 自动捕获 |
| `ToolExecuteResult` | 需显式 `isError`、返回图片/资源，或错误是业务逻辑而非异常 |

---

## 5. 工具命名最佳实践和 inputSchema 编写指南

### 命名规范

- **snake_case**，符合正则 `^[a-z][a-z0-9_]*$`
- **动词 + 名词**：`get_weather`、`list_files`、`click_element`

推荐前缀：`get_`（获取）、`list_`（列表）、`create_`（创建）、`update_`/`edit_`（修改）、`delete_`/`remove_`（删除）、`search_`（搜索）、`run_`（执行）。

反模式：`doStuff`（camelCase）、`get_data`（太笼统）、`ReadFile`（PascalCase）。

### inputSchema 编写

Schema 必须与 Codable Input 类型**精确对应**，包括 CodingKeys 映射。

#### 基本结构

```swift
let schema: ToolInputSchema = [
    "type": "object",
    "properties": [
        "field_name": ["type": "string", "description": "字段说明"]
    ],
    "required": ["field_name"]
]
```

#### CodingKeys 映射

```swift
struct BashInput: Codable {
    let command: String
    let runInBackground: Bool?
    enum CodingKeys: String, CodingKey {
        case command
        case runInBackground = "run_in_background"
    }
}
// schema key 必须使用 "run_in_background"
```

#### 常见模式

```swift
// 枚举
"action": ["type": "string", "enum": ["get", "set"]]

// 数组
"ids": ["type": "array", "items": ["type": "string"]]

// 可选字段：不加入 required，对应 Codable 的 Optional 类型
"required": ["pattern"]  // path 为可选
```

#### 反模式

```swift
// 错误：缺少 type/properties 结构
let bad = ["fields": "name,age"]
// 错误：schema key 与 CodingKeys 映射不一致
```

### 完整注册示例

```swift
struct SearchInput: Codable {
    let query: String
    let maxResults: Int?
    enum CodingKeys: String, CodingKey {
        case query; case maxResults = "max_results"
    }
}

let tool = defineTool(
    name: "search_documents",
    description: "根据关键词搜索文档",
    inputSchema: [
        "type": "object",
        "properties": [
            "query": ["type": "string", "description": "搜索关键词"],
            "max_results": ["type": "integer", "description": "最大返回数量"]
        ],
        "required": ["query"]
    ],
    isReadOnly: true,
    annotations: ToolAnnotations(readOnlyHint: true, destructiveHint: false,
                                  idempotentHint: true, openWorldHint: false)
) { (input: SearchInput, context: ToolContext) async throws -> String in
    let limit = input.maxResults ?? 10
    return "搜索 '\(input.query)'，返回 \(limit) 条结果"
}

// 注册
let options = AgentOptions(apiKey: "sk-...", tools: [tool])
```
