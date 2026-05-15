# 打包和分发指南

本文档介绍如何将基于 OpenAgentSDK 的 Agent 项目打包、签名和分发给最终用户。

## 1. SPM Package 结构最佳实践

### 标准项目结构

```
MyAgent/
├── Package.swift
├── Sources/
│   ├── MyAgent/           # 可执行目标（CLI 入口）
│   │   └── main.swift
│   └── MyAgentCore/       # 库目标（共享逻辑）
│       └── AgentConfig.swift
├── Resources/
│   └── Prompts/           # Prompt 模板文件
│       └── system.md
└── Tests/
    └── MyAgentTests/
```

### Package.swift 配置

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MyAgent",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/terryso/open-agent-sdk-swift.git", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyAgent",
            dependencies: ["MyAgentCore", "OpenAgentSDK"],
            resources: [.copy("Prompts/")]
        ),
        .library(name: "MyAgentCore", dependencies: []),
        .testTarget(name: "MyAgentTests", dependencies: ["MyAgentCore"]),
    ]
)
```

**最佳实践：**
- 使用 `platforms: [.macOS(.v14)]` 确保最低版本要求
- 将 Prompt 文件放在 `Resources/Prompts/` 并通过 `.copy()` 嵌入
- 库目标（`MyAgentCore`）放共享逻辑，可被多个 executable 复用
- 依赖使用语义化版本（`from: "0.1.0"`），不锁定具体 commit

## 2. Helper App 打包和代码签名流程

如果你的 Agent 包含需要 Accessibility 权限的 Helper App（类似 Axion 的 AxionHelper），需要遵循以下流程。

### Info.plist 配置

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MyHelper</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
```

**关键字段：**
- `LSUIElement=true` — 无 Dock 图标，后台运行
- `LSMinimumSystemVersion` — 系统最低版本要求

### Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

### 签名流程

```bash
# 1. 编译 Helper.app
swift build -c release --product MyHelper

# 2. 用 Apple Developer 证书签名
codesign --force --options runtime \
    --entitlements MyHelper.entitlements \
    --sign "Developer ID Application: Your Name (TEAMID)" \
    build/release/MyHelper.app

# 3. 验证签名
codesign --verify --deep --strict build/release/MyHelper.app
```

### 分发目录结构（参考 Axion）

```
my-agent/
├── bin/
│   └── my-agent          # CLI 可执行文件
└── libexec/
    └── my-agent/
        └── MyHelper.app  # Helper App
```

### 引导用户授予 Accessibility 权限

Helper App 需要 macOS Accessibility 权限才能操控 UI 元素。分发后需引导用户手动授权：

1. **首次启动检测**：运行时调用 `AXIsProcessTrusted()` 检测权限状态
2. **自动打开系统设置**：调用 `AXIsProcessTrustedWithOptions(["kAXTrustedCheckOptionPrompt": true])` 弹出授权弹窗
3. **CLI 提示**：在 CLI 输出中提示用户操作步骤：

```
⚠️ AxionHelper 需要 Accessibility 权限：
  1. 打开 系统设置 → 隐私与安全性 → 辅助功能
  2. 点击左下角锁图标并输入密码
  3. 勾选 MyHelper
  4. 重启 my-agent
```

4. **`axion doctor` 式诊断**：提供诊断命令让用户排查权限问题

> **注意：** Accessibility 权限需要用户在系统设置中手动操作，无法通过命令行或脚本自动完成。建议在 README 和首次运行提示中明确说明。
        └── MyHelper.app  # Helper App
```

## 3. Homebrew Formula 编写指南

### Formula 示例

```ruby
class MyAgent < Formula
  desc "macOS 桌面自动化 Agent"
  homepage "https://github.com/your-org/my-agent"
  url "https://github.com/your-org/my-agent/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "..."
  version "0.1.0"

  depends_on :macos => :sonoma

  def install
    # 构建 CLI
    system "swift", "build", "-c", "release", "--product", "MyAgent"
    bin.install "build/release/MyAgent" => "my-agent"

    # 构建 Helper App
    system "swift", "build", "-c", "release", "--product", "MyHelper"
    (libexec/"my-agent").install Dir["build/release/MyHelper.app"]
  end

  test do
    system bin/"my-agent", "--version"
  end
end
```

### Cask vs Formula

| 场景 | 使用 | 原因 |
|------|------|------|
| 纯 CLI 工具 | Formula | 无需 .app bundle |
| 包含 .app | Formula | 如果可以分离 CLI 和 .app |
| 需要 DMG 安装 | Cask | 用户体验更好 |

**Axion 使用 Formula**：CLI 二进制放 `bin/`，Helper.app 放 `libexec/axion/`，通过公式统一安装。

## 4. CI/CD 集成建议

### GitHub Actions 工作流

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: swift build -c release

      - name: Run tests
        run: swift test

      - name: Archive binary
        if: startsWith(github.ref, 'refs/tags/')
        run: |
          tar -czf my-agent-${{ github.ref_name }}.tar.gz \
            -C build/release MyAgent

      - name: Create Release
        if: startsWith(github.ref, 'refs/tags/')
        uses: softprops/action-gh-release@v1
        with:
          files: my-agent-*.tar.gz
```

### CI 签名（可选）

如果需要在 CI 中签名 Helper App：

1. 将 Apple Developer 证书导出为 `.p12` 文件
2. 存储为 GitHub Secrets（`DEVELOPER_ID_CERT`、`DEVELOPER_ID_PASSWORD`）
3. 在 CI 中导入钥匙串并签名

```yaml
- name: Import signing certificate
  run: |
    security create-keychain -p actions temp.keychain
    security import cert.p12 -k temp.keychain -P ${{ secrets.CERT_PASSWORD }}
    security set-key-partition-list -S apple-tool:,apple: -k actions temp.keychain
```
