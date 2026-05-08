# Story 1.6: Helper 完整集成与 App 打包

Status: done

## Story

As a 用户,
I want Helper 是一个完整的签名 macOS App，所有工具正确注册并可通过 MCP 调用,
So that Axion 可以作为完整产品使用 Helper 的桌面操作能力.

## Acceptance Criteria

1. **AC1: 全部 15 个工具注册可用**
   - Given 所有工具已实现
   - When 调用 tools/list
   - Then 返回全部 15 个工具：launch_app, list_apps, list_windows, get_window_state, click, double_click, right_click, drag, scroll, type_text, press_key, hotkey, screenshot, get_accessibility_tree, open_url

2. **AC2: AxionHelper.app 打包配置正确**
   - Given AxionHelper.app 打包完成
   - When 检查 Info.plist
   - Then 包含 LSUIElement=true（无 Dock 图标）和 LSMinimumSystemVersion=13.0

3. **AC3: Helper MCP 启动就绪性能（NFR2）**
   - Given Helper 启动
   - When 等待 500ms 后发送 MCP 请求
   - Then MCP 连接就绪，可正常响应

4. **AC4: 单操作性能（NFR3）**
   - Given 单个 AX 操作执行
   - When 测量从 MCP 请求到结果返回的耗时
   - Then 不超过 200ms

5. **AC5: Helper 随 CLI 退出**
   - Given Helper 运行中
   - When CLI 进程退出
   - Then Helper 进程随之退出，不残留

## Tasks / Subtasks

- [x] Task 1: 创建 Helper App Bundle 构建脚本 (AC: #2)
  - [x] 1.1 创建 `Distribution/homebrew/build-helper-app.sh` 脚本，将 SPM 编译产物包装为标准 macOS App Bundle（`.app` 目录结构）
  - [x] 1.2 App Bundle 结构：`AxionHelper.app/Contents/MacOS/AxionHelper`（可执行文件）+ `AxionHelper.app/Contents/Info.plist`
  - [x] 1.3 创建 `Distribution/homebrew/Info.plist` 模板文件：CFBundleIdentifier=`com.axion.helper`, CFBundleExecutable=`AxionHelper`, LSUIElement=true, LSMinimumSystemVersion=13.0, NSHighResolutionCapable=true
  - [x] 1.4 创建 `Distribution/homebrew/AxionHelper.entitlements` 文件：`com.apple.security.automation.apple-events=true`
  - [x] 1.5 脚本支持 debug/release 配置，自动检测架构（arm64/x86_64）
  - [x] 1.6 脚本执行 `swift build` 编译 AxionHelper，然后创建 App Bundle 目录结构并复制文件

- [x] Task 2: 创建完整构建发布脚本 (AC: #2, #5)
  - [x] 2.1 创建 `Distribution/homebrew/build-release.sh` 脚本：编译 CLI + Helper App + 打包为 tar.gz
  - [x] 2.2 产出结构：`axion-{version}/bin/axion`（CLI）+ `axion-{version}/libexec/axion/AxionHelper.app`（Helper App）
  - [x] 2.3 支持 `--sign` 参数调用 `codesign` 对 Helper App 签名（Ad-hoc 签名用于本地开发，Apple Developer 签名用于发布）
  - [x] 2.4 生成 sha256 校验和用于 Homebrew formula 更新
  - [x] 2.5 版本号从 `VERSION` 文件或 git tag 读取

- [x] Task 3: 创建 Homebrew Formula 模板 (AC: #2)
  - [x] 3.1 创建 `Distribution/homebrew/axion.rb.template`，定义安装流程：下载 tar.gz → 解压 → bin/axion 到 Homebrew bin → libexec/axion/ 到 Homebrew libexec
  - [x] 3.2 Formula 依赖：无（纯静态编译，无 runtime 依赖）
  - [x] 3.3 支持 sha256 和 URL 占位符，`build-release.sh` 自动替换

- [x] Task 4: 集成验证测试 (AC: #1, #3, #4)
  - [x] 4.1 创建 `Tests/AxionHelperTests/Integration/FullToolRegistrationTests.swift`：通过真实 MCP 连接验证 tools/list 返回全部 15 个工具名
  - [x] 4.2 创建 `Tests/AxionHelperTests/Integration/HelperStartupPerformanceTests.swift`：测量 Helper 进程启动到 MCP 就绪的时间 < 500ms
  - [x] 4.3 创建 `Tests/AxionHelperTests/Integration/SingleOperationPerformanceTests.swift`：测量 list_apps 单操作响应时间 < 200ms
  - [x] 4.4 所有集成测试使用 `try XCTSkipIf()` 在无 AX 权限环境跳过

- [x] Task 5: App Bundle 内容验证单元测试 (AC: #2)
  - [x] 5.1 创建 `Tests/AxionHelperTests/Tools/AppBundleTests.swift`：验证 build-helper-app.sh 脚本产出的 Info.plist 内容（LSUIElement, LSMinimumSystemVersion, CFBundleIdentifier 等）
  - [x] 5.2 验证 App Bundle 目录结构完整性（Contents/MacOS/AxionHelper, Contents/Info.plist）

- [x] Task 6: Helper 进程生命周期冒烟测试增强 (AC: #5)
  - [x] 6.1 更新 `Tests/AxionHelperTests/MCP/HelperProcessSmokeTests.swift`：验证 Helper 进程在 stdin EOF 后确实退出（无残留进程）
  - [x] 6.2 添加测试：启动 Helper → 发送 MCP initialize → 验证成功 → 关闭 stdin → 验证进程退出码

- [x] Task 7: 运行全部单元测试确认无回归 (AC: #1)
  - [x] 7.1 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionCoreTests"` 确认所有现有测试通过
  - [x] 7.2 确认 build-helper-app.sh 脚本可执行（本地验证）

## Dev Notes

### 关键架构约束

**本 Story 是 Epic 1 的收官之作。** Stories 1.1-1.5 已完成全部 15 个 MCP 工具的真实实现。本 Story 的核心目标是：
1. 将 SPM 编译产物包装为标准 macOS App Bundle
2. 创建构建发布脚本和 Homebrew formula
3. 通过集成测试验证完整工具注册和性能指标

**AxionHelper 进程边界不变** -- Helper 仍然通过 MCP stdio 通信。App Bundle 打包只改变分发形式，不改变运行时行为。

### 核心 API -- macOS App Bundle 结构

标准 macOS App Bundle 目录结构：

```
AxionHelper.app/
  Contents/
    Info.plist          # App 元数据
    MacOS/
      AxionHelper       # 可执行文件（SPM 编译产物）
    Resources/          # 可选资源（AxionHelper 不需要）
    _CodeSignature/     # 签名（codesign 自动生成）
```

**Info.plist 关键字段（参考 OpenClick）：**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>AxionHelper</string>
  <key>CFBundleIdentifier</key>
  <string>com.axion.helper</string>
  <key>CFBundleName</key>
  <string>AxionHelper</string>
  <key>CFBundleDisplayName</key>
  <string>AxionHelper</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
```

**Entitlements 文件（参考 OpenClick）：**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.automation.apple-events</key>
  <true/>
</dict>
</plist>
```

### build-helper-app.sh 脚本设计

参考 OpenClick 的 `src/mac-app.ts` 中的 `createAppBundle` 函数，但简化为纯 bash：

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_CONFIG="${1:-debug}"
ARCH="$(uname -m)"

# 1. 编译 AxionHelper
if [ "$BUILD_CONFIG" = "release" ]; then
    swift build -c release --package-path "$PROJECT_ROOT"
    BUILD_DIR="$PROJECT_ROOT/.build/$ARCH-apple-macosx/release"
else
    swift build --package-path "$PROJECT_ROOT"
    BUILD_DIR="$PROJECT_ROOT/.build/$ARCH-apple-macosx/debug"
fi

# 2. 创建 App Bundle 目录结构
APP_NAME="AxionHelper"
APP_BUNDLE="$PROJECT_ROOT/.build/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"

# 3. 复制可执行文件
cp "$BUILD_DIR/AxionHelper" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

# 4. 生成 Info.plist（版本号从项目读取）
VERSION=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "0.1.0")
sed "s/{{VERSION}}/$VERSION/g" "$SCRIPT_DIR/Info.plist" > "$CONTENTS/Info.plist"

# 5. 签名（可选）
if [ "${2:-}" = "--sign" ]; then
    codesign --force --sign - "$APP_BUNDLE"
fi

echo "✅ $APP_BUNDLE created"
```

### build-release.sh 脚本设计

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERSION="${1:-$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "0.1.0")}"
ARCH="$(uname -m)"
DIST_DIR="$PROJECT_ROOT/.build/dist/axion-$VERSION"

# 1. Release 编译
swift build -c release --package-path "$PROJECT_ROOT"
BUILD_DIR="$PROJECT_ROOT/.build/$ARCH-apple-macosx/release"

# 2. 构建 Helper App Bundle（含签名）
"$SCRIPT_DIR/build-helper-app.sh" release --sign

# 3. 组装分发目录
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/bin"
mkdir -p "$DIST_DIR/libexec/axion"

cp "$BUILD_DIR/AxionCLI" "$DIST_DIR/bin/axion"
cp -R "$PROJECT_ROOT/.build/AxionHelper.app" "$DIST_DIR/libexec/axion/"
chmod +x "$DIST_DIR/bin/axion"

# 4. 打包 tar.gz
TAR_PATH="$PROJECT_ROOT/.build/dist/axion-$VERSION.tar.gz"
tar -czf "$TAR_PATH" -C "$DIST_DIR/.." "axion-$VERSION"

# 5. 计算 sha256
SHA256=$(shasum -a 256 "$TAR_PATH" | cut -d' ' -f1)

# 6. 更新 Homebrew formula
sed -e "s/{{VERSION}}/$VERSION/g" \
    -e "s/{{SHA256}}/$SHA256/g" \
    -e "s|{{URL}}|https://github.com/terryso/homebrew-tap/releases/download/v$VERSION/axion-$VERSION.tar.gz|g" \
    "$SCRIPT_DIR/axion.rb.template" > "$SCRIPT_DIR/axion.rb"

echo "✅ Release package: $TAR_PATH"
echo "   SHA256: $SHA256"
```

### Homebrew Formula 模板设计

```ruby
class Axion < Formula
  desc "macOS desktop automation CLI powered by AI"
  homepage "https://github.com/terryso/axion"
  version "{{VERSION}}"
  url "{{URL}}"
  sha256 "{{SHA256}}"

  depends_on :macos => :sonoma

  def install
    bin.install "bin/axion"
    libexec.install Dir["libexec/*"]
  end

  test do
    assert_match(/#{version}/, shell_output("#{bin}/axion --version"))
  end
end
```

### 集成测试设计

**FullToolRegistrationTests** -- 验证 tools/list 返回全部 15 个工具：

```swift
final class FullToolRegistrationTests: XCTestCase {
    /// 启动真实 Helper 进程，通过 MCP 验证全部 15 个工具注册
    func test_toolsList_returnsAll15Tools() async throws {
        try XCTSkipIf(
            AXIsProcessTrustedWithOptions(nil) == false,
            "需要 Accessibility 权限"
        )
        // 启动 Helper 进程
        // 发送 MCP initialize + tools/list
        // 验证返回的工具列表包含全部 15 个工具名
        let expectedTools = [
            "launch_app", "list_apps", "list_windows", "get_window_state",
            "click", "double_click", "right_click", "drag", "scroll",
            "type_text", "press_key", "hotkey",
            "screenshot", "get_accessibility_tree", "open_url"
        ]
        // ... 断言每个工具名都在返回列表中
    }
}
```

**HelperStartupPerformanceTests** -- 验证 NFR2（< 500ms 启动）：

```swift
func test_helperStartup_under500ms() async throws {
    let start = ContinuousClock.now
    // 启动 Helper 进程
    // 发送 MCP initialize，等待响应
    let elapsed = ContinuousClock.now - start
    XCTAssertLessThan(elapsed.components.seconds, 1) // < 1s（含余量）
}
```

**SingleOperationPerformanceTests** -- 验证 NFR3（< 200ms 单操作）：

```swift
func test_listAppsResponse_under200ms() async throws {
    // Helper 已启动，MCP 连接已建立
    let start = ContinuousClock.now
    // 发送 tools/call: list_apps
    let elapsed = ContinuousClock.now - start
    XCTAssertLessThan(elapsed.components.milliseconds, 200)
}
```

### 已注册的全部 15 个工具清单

| # | 工具名 | Story | 实现状态 |
|---|--------|-------|---------|
| 1 | launch_app | 1.3 | 已实现 |
| 2 | list_apps | 1.3 | 已实现 |
| 3 | list_windows | 1.3 | 已实现 |
| 4 | get_window_state | 1.3 | 已实现 |
| 5 | click | 1.4 | 已实现 |
| 6 | double_click | 1.4 | 已实现 |
| 7 | right_click | 1.4 | 已实现 |
| 8 | type_text | 1.4 | 已实现 |
| 9 | press_key | 1.4 | 已实现 |
| 10 | hotkey | 1.4 | 已实现 |
| 11 | scroll | 1.4 | 已实现 |
| 12 | drag | 1.4 | 已实现 |
| 13 | screenshot | 1.5 | 已实现 |
| 14 | get_accessibility_tree | 1.5 | 已实现 |
| 15 | open_url | 1.5 | 已实现 |

### Package.swift 不需要修改

本 Story 不修改 Package.swift。App Bundle 打包是构建后处理步骤，通过 bash 脚本完成。

### VERSION 文件

项目根目录需要创建 `VERSION` 文件用于版本管理：

```
0.1.0
```

### 文件结构

需要创建/修改的文件：

```
Distribution/homebrew/
  build-helper-app.sh       # NEW: App Bundle 构建脚本
  build-release.sh           # NEW: 完整发布构建脚本
  Info.plist                 # NEW: Helper App Info.plist 模板
  AxionHelper.entitlements   # NEW: Helper App entitlements
  axion.rb.template          # NEW: Homebrew formula 模板

VERSION                      # NEW: 项目版本号文件

Tests/AxionHelperTests/Integration/
  FullToolRegistrationTests.swift         # NEW: 工具注册验证
  HelperStartupPerformanceTests.swift     # NEW: 启动性能验证
  SingleOperationPerformanceTests.swift   # NEW: 单操作性能验证

Tests/AxionHelperTests/Tools/
  AppBundleTests.swift        # NEW: App Bundle 内容验证

Tests/AxionHelperTests/MCP/
  HelperProcessSmokeTests.swift  # UPDATE: 添加退出验证测试
```

### 前一个 Story 的经验教训

**Story 1.5 的关键经验：**
- 全部 15 个工具的真实实现已完成，ToolRegistrar 中无 stub 代码
- ServiceContainer 已包含 5 个服务：appLauncher, accessibilityEngine, inputSimulation, screenshotCapture, urlOpener
- 每个工具的错误处理遵循统一模式：`do/catch` 捕获自定义 Error，转换为 `ToolErrorPayload` JSON
- `ToolErrorPayload` 是 ToolRegistrar.swift 中的 `private struct`
- HelperMCPServerTests 中的 stub 测试已删除
- HelperMCPServer.run() 使用 StdioTransport，通过 session.waitUntilCompleted() 阻塞

**Story 1.4 的关键经验：**
- ServiceContainer.shared 使用 `nonisolated(unsafe)` 声明，测试时直接替换
- ServiceContainerFixture.apply() 返回闭包用于恢复原始值
- Mock 使用 `@unchecked Sendable` + 闭包 handler 模式

**Story 1.3 的关键经验：**
- HelperMCPServer 通过 `StdioTransport()` 在 stdio 上运行 MCP JSON-RPC
- `ToolRegistrar.registerAll(to:)` 使用 `server.register { ... }` 块语法注册工具
- Helper 进程从 stdin 接收请求，stdout 返回响应

**Story 1.2 的关键经验：**
- `@Tool` 宏从 Swift 类型自动生成 JSON Schema
- CallTool.Result.Content 使用 `.text(String, annotations:, _meta:)` 元组模式
- Helper 进程的 stdin EOF 触发优雅退出

**Story 1.1 的关键经验：**
- swift-tools-version: 6.1，编译器 6.2.4
- import 顺序：系统 -> 第三方 -> 项目内部
- 测试命名：`test_方法名_场景_预期结果`
- AxionHelperTests 排除 Integration 目录（`exclude: ["Integration"]`）

### 命名规则（必须遵守）

| 类别 | 规则 | 示例 |
|------|------|------|
| Shell 脚本名 | kebab-case | build-helper-app.sh, build-release.sh |
| 目录名 | macOS 标准 | Contents, MacOS, Resources |
| Plist 键名 | Apple 标准大写 | LSUIElement, CFBundleIdentifier |
| Homebrew formula | Ruby 标准 | axion.rb |
| 测试文件 | PascalCase + Tests 后缀 | FullToolRegistrationTests.swift |

### 禁止事项（反模式）

- **不得修改 AxionHelper 的 Swift 源代码**（工具实现已完成）
- **不得在 Helper App 中添加 GUI 元素**（LSUIElement=true 意味着无 Dock 图标无菜单栏）
- **不得使用 Xcode 构建系统**（纯 SPM + bash 脚本）
- **不得硬编码架构**（脚本通过 `uname -m` 检测 arm64/x86_64）
- **不得在 App Bundle 中打包第三方二进制**（Helper 是纯 Swift，无外部运行时依赖）
- **Helper 不得监听网络端口**（NFR11: 仅通过 stdio 本地通信）
- **集成测试不得在 CI 中失败**（使用 `XCTSkipIf` 在无权限环境跳过）
- **不得使用 print() 输出到 stdout**（stdout 被 MCP JSON-RPC 占用）

### 安全分类（供后续 Story 3.3 SafetyChecker 参考）

全部 15 个工具的安全分类（参考 OpenClick BACKGROUND_SAFE_TOOLS）：

**background_safe（10 个）：** launch_app, list_apps, list_windows, get_window_state, screenshot, get_accessibility_tree, open_url, scroll, type_text, press_key

**foreground_required（5 个）：** click, double_click, right_click, drag, hotkey

本 Story 不实现安全策略，只记录分类供后续使用。

### Homebrew 安装路径约定

Homebrew 安装后的目录结构：

```
/opt/homebrew/                         # Homebrew prefix (Apple Silicon)
  bin/
    axion                              # CLI 可执行文件
  libexec/
    axion/
      AxionHelper.app/                 # Helper App Bundle
        Contents/
          MacOS/
            AxionHelper
          Info.plist
```

CLI 在运行时通过 `Process()` 启动 Helper 时，路径为：
```swift
let helperPath: String
if let executablePath = Bundle.main.executablePath {
    // 开发环境：相对于项目 build 目录
    helperPath = executablePath
} else {
    // Homebrew 安装环境
    helperPath = "/opt/homebrew/libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper"
}
```

**注意：** Helper 路径的动态解析将在 Story 3.1（HelperProcessManager）中实现，本 Story 只确保 App Bundle 按正确结构打包。

### 性能目标（NFR 验证）

| NFR | 指标 | 验证方法 |
|-----|------|---------|
| NFR2 | Helper 启动到 MCP 就绪 < 500ms | HelperStartupPerformanceTests |
| NFR3 | 单操作 < 200ms | SingleOperationPerformanceTests |
| NFR4 | Helper 内存 < 20MB | 手动 `ps aux` 验证（非自动化） |

### Project Structure Notes

遵循架构文档定义的目录结构。本 Story 新增文件：
- 构建脚本：`Distribution/homebrew/` 目录下
- 集成测试：`Tests/AxionHelperTests/Integration/` 目录（已存在但被 `exclude` 排除在单元测试外）
- App Bundle 测试：`Tests/AxionHelperTests/Tools/` 目录
- 版本文件：项目根目录 `VERSION`

不创建新的顶级目录。

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Helper App 打包配置] Helper App 打包参考
- [Source: _bmad-output/planning-artifacts/architecture.md#NFR2] Helper 启动 < 500ms
- [Source: _bmad-output/planning-artifacts/architecture.md#NFR3] 单操作 < 200ms
- [Source: _bmad-output/planning-artifacts/architecture.md#NFR4] Helper 内存 < 20MB
- [Source: _bmad-output/planning-artifacts/architecture.md#NFR8] Ctrl-C 正确清理
- [Source: _bmad-output/planning-artifacts/architecture.md#NFR11] Helper 仅本地通信
- [Source: _bmad-output/planning-artifacts/architecture.md#命名模式] MCP 工具命名 snake_case
- [Source: _bmad-output/planning-artifacts/architecture.md#反模式] 必须避免的编码模式
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.6] 原始 Story 定义和 AC
- [Source: _bmad-output/implementation-artifacts/1-5-screenshot-ax-tree-url-open.md] Story 1.5 经验和产出
- [Source: _bmad-output/implementation-artifacts/1-4-mouse-keyboard-operations.md] Story 1.4 经验和产出
- [Source: _bmad-output/implementation-artifacts/1-3-app-launch-window-management.md] Story 1.3 经验和产出
- [Source: _bmad-output/project-context.md#Helper App 打包细节] LSUIElement, Entitlements, 安装路径
- [Source: openclick/mac-app/Sources/OpenclickHelper/Info.plist] OpenClick Info.plist 参考
- [Source: openclick/mac-app/OpenclickHelper.entitlements] OpenClick Entitlements 参考
- [Source: openclick/src/mac-app.ts] OpenClick App Bundle 创建流程参考
- [Source: Sources/AxionHelper/MCP/ToolRegistrar.swift] 已注册的全部 15 个工具
- [Source: Sources/AxionHelper/MCP/HelperMCPServer.swift] MCP Server 入口
- [Source: Sources/AxionHelper/main.swift] Helper 入口
- [Source: Sources/AxionCore/Constants/ToolNames.swift] 工具名常量（注意：包含额外常量如 quitApp, activateWindow, moveWindow, resizeWindow, getFileInfo 这些暂未注册为工具）
- [Source: Package.swift] SPM 清单（AxionHelperTests 排除 Integration 目录）

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (GLM-5.1)

### Debug Log References

- build-helper-app.sh executed successfully: App Bundle created at .build/AxionHelper.app with correct Info.plist (LSUIElement=true, CFBundleIdentifier=com.axion.helper, LSMinimumSystemVersion=13.0)
- Full unit test suite: 167 tests, 0 failures
- AppBundleTests: 5 tests, 0 failures (all Info.plist fields and directory structure verified)
- HelperProcessSmokeTests: 4 tests including new initialize-then-EOF lifecycle test

### Completion Notes List

- Created VERSION file (0.1.0) at project root for version management
- Created Info.plist template with {{VERSION}} placeholder, correctly resolved by build-helper-app.sh
- Created AxionHelper.entitlements with com.apple.security.automation.apple-events permission
- build-helper-app.sh supports debug/release config, auto-detects architecture (arm64/x86_64), optional --sign flag
- build-release.sh builds CLI + Helper App, packages as tar.gz, generates sha256, and renders Homebrew formula from template
- Integration test files (FullToolRegistrationTests, HelperStartupPerformanceTests, SingleOperationPerformanceTests) already existed from previous stories as ATDD red-phase scaffolds — verified they are complete and correct
- AppBundleTests already existed and now pass against the built App Bundle
- Added test_helperProcess_initializeThenEOF_exitsCleanly to HelperProcessSmokeTests for AC5 lifecycle verification

### File List

New files:
- VERSION
- Distribution/homebrew/Info.plist
- Distribution/homebrew/AxionHelper.entitlements
- Distribution/homebrew/build-helper-app.sh
- Distribution/homebrew/build-release.sh
- Distribution/homebrew/axion.rb.template

Modified files:
- Tests/AxionHelperTests/MCP/HelperProcessSmokeTests.swift (added test_helperProcess_initializeThenEOF_exitsCleanly)

Pre-existing files (created in earlier stories, verified in this story):
- Tests/AxionHelperTests/Integration/FullToolRegistrationTests.swift
- Tests/AxionHelperTests/Integration/HelperStartupPerformanceTests.swift
- Tests/AxionHelperTests/Integration/SingleOperationPerformanceTests.swift
- Tests/AxionHelperTests/Tools/AppBundleTests.swift

## Change Log

- 2026-05-08: Story 1.6 implementation complete — Helper App Bundle packaging, build/release scripts, Homebrew formula template, lifecycle test enhancement. 167 unit tests passing, 0 regressions.
