# Story 2.5: Homebrew 私有 Tap 分发与打包

Status: done

## Story

As a 用户,
I want 通过 `brew install terryso/tap/axion` 一键安装 CLI 和 Helper,
so that 我不需要手动编译或配置安装，且无需等待 homebrew-core 审核.

## Acceptance Criteria

1. **AC1: Homebrew formula 推送与安装**
   - Given Homebrew formula 已推送至 github.com/terryso/homebrew-tap
   - When 运行 `brew install terryso/tap/axion`
   - Then 同时安装 axion CLI 到 bin/ 和 AxionHelper.app 到 libexec/axion/

2. **AC2: 安装后版本验证**
   - Given 安装完成
   - When 运行 `axion --version`
   - Then 显示正确的版本号

3. **AC3: Helper 路径发现**
   - Given 安装完成
   - When axion run 需要启动 Helper
   - Then 在 libexec/axion/AxionHelper.app 路径找到并启动 Helper

4. **AC4: Code Signing**
   - Given AxionHelper.app 构建完成
   - When 检查 code signing
   - Then 包含有效的签名和 entitlements

5. **AC5: build-release.sh 完整流程**
   - Given build-release.sh 执行
   - When 构建 + 打包完成
   - Then 生成 axion-{version}.tar.gz（含 axion CLI + AxionHelper.app），并更新 homebrew-tap 仓库中的 formula（sha256 + URL）

6. **AC6: HelperApp 路径解析（关键）**
   - Given CLI 安装在 Homebrew bin/ 目录（符号链接到 Cellar）
   - When CLI 需要启动 Helper
   - Then 通过 `Bundle.main.executableURL` 解析出相对于自身的 `../libexec/axion/AxionHelper.app` 路径

7. **AC7: GitHub Release 自动化**
   - Given build-release.sh 生成 tar.gz 和 formula
   - When 开发者运行发布命令
   - Then 自动创建 GitHub Release 并上传 tar.gz 作为 asset

## Tasks / Subtasks

- [x] Task 1: 完善 HelperApp 路径解析逻辑 (AC: #3, #6)
  - [x] 1.1 创建 `Sources/AxionCLI/Helper/HelperPathResolver.swift`
    - 实现路径解析策略：
      1. 环境变量 `AXION_HELPER_PATH`（CI/测试覆盖）
      2. 相对于可执行文件的路径：`executableDir/../libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper`
      3. 开发模式回退：`PROJECT_ROOT/.build/AxionHelper.app/Contents/MacOS/AxionHelper`（检测 `.build` 目录）
    ```swift
    struct HelperPathResolver {
        static func resolveHelperPath() -> String?
    }
    ```
  - [x] 1.2 编写单元测试 `Tests/AxionCLITests/Helper/HelperPathResolverTests.swift`
    - 测试环境变量覆盖
    - 测试相对路径解析逻辑
    - 测试开发模式回退

- [x] Task 2: 完善 build-release.sh 和 build-helper-app.sh (AC: #1, #4, #5)
  - [x] 2.1 验证 `build-helper-app.sh` 完整流程：编译 → App Bundle 创建 → Info.plist 生成 → 签名
  - [x] 2.2 验证 `build-release.sh` 完整流程：release 编译 → Helper App Bundle → 组装分发目录 → tar.gz → sha256 → formula 生成
  - [x] 2.3 添加 `--sign-identity` 参数支持 Apple Developer 签名（非 ad-hoc）
    ```bash
    # 当前: codesign --force --sign - (ad-hoc)
    # 新增: codesign --force --sign "Developer ID Application: ..." --entitlements AxionHelper.entitlements
    ```
  - [x] 2.4 在 build-helper-app.sh 中嵌入 entitlements 到 App Bundle 签名
  - [x] 2.5 添加架构支持（arm64 + x86_64），支持 `--arch` 参数

- [x] Task 3: 完善 Homebrew Formula (AC: #1, #2)
  - [x] 3.1 审查 `axion.rb.template` 确保字段完整：
    - `desc`, `homepage`, `version`, `url`, `sha256`
    - `depends_on :macos => :sonoma`（macOS 14+）
    - `install` 方法：`bin.install "bin/axion"` + `libexec.install Dir["libexec/*"]`
    - `test` 块：验证 `--version` 输出
  - [x] 3.2 确认 `bin.install` 安装的是名为 `axion` 的二进制（非 `AxionCLI`）
  - [x] 3.3 添加 `caveats` 输出安装后的引导信息：
    ```ruby
    def caveats
      <<~EOS
        Run `axion setup` to configure your API key and permissions.
        Run `axion doctor` to verify your environment.
      EOS
    end
    ```

- [x] Task 4: 创建发布流程脚本 (AC: #5, #7)
  - [x] 4.1 创建 `Distribution/homebrew/publish-release.sh`
    - 调用 build-release.sh 构建打包
    - 使用 `gh release create` 创建 GitHub Release
    - 上传 tar.gz 作为 release asset
    - 更新 homebrew-tap 仓库的 formula（fork + PR 或直接 push）
  - [x] 4.2 创建 `VERSION` 文件管理机制（已存在，内容为 `0.1.0`）

- [x] Task 5: 集成测试 (AC: #1–#7)
  - [x] 5.1 本地测试 build-helper-app.sh（debug 模式）
  - [x] 5.2 本地测试 build-release.sh（release 模式，ad-hoc 签名）
  - [x] 5.3 验证生成的 tar.gz 结构正确：
    ```
    axion-0.1.0/
      bin/axion
      libexec/axion/AxionHelper.app/
        Contents/
          Info.plist
          MacOS/AxionHelper
    ```
  - [x] 5.4 验证 formula 模板生成的 sha256 和 URL 正确
  - [x] 5.5 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` 确认无回归

## Dev Notes

### 核心目标

这是 Epic 2 的最后一个 Story。Story 2.1–2.4（CLI 入口、ConfigManager、setup、doctor）已完成。本 Story 实现构建打包和 Homebrew 分发，使 Axion 可通过 `brew install terryso/tap/axion` 一键安装。

### 已有基础设施（大量复用）

以下文件已存在于 `Distribution/homebrew/` 目录，是 Epic 1（Story 1.6）期间创建的：

| 文件 | 状态 | 说明 |
|------|------|------|
| `build-helper-app.sh` | **已完成** | 编译 AxionHelper → 创建 .app Bundle → 生成 Info.plist → 可选 ad-hoc 签名 |
| `build-release.sh` | **已完成** | 调用 build-helper-app.sh → 组装分发目录 → tar.gz → sha256 → 生成 formula |
| `axion.rb.template` | **已完成** | Homebrew formula 模板，含 VERSION/SHA256/URL 占位符 |
| `Info.plist` | **已完成** | Helper App 的 Info.plist 模板，LSUIElement=true, LSMinimumSystemVersion=13.0 |
| `AxionHelper.entitlements` | **已完成** | com.apple.security.automation.apple-events 权限 |

**关键发现：打包基础设施大部分已就位。** 本 Story 的核心工作是：
1. **HelperApp 路径解析**（代码层 — HelperPathResolver，这是最重要的新代码）
2. **增强签名支持**（Apple Developer 签名，非 ad-hoc）
3. **发布自动化脚本**（publish-release.sh）
4. **Formula 完善**（添加 caveats 等）
5. **端到端验证**（完整构建 → 安装 → 运行流程）

### HelperPathResolver 设计（关键新代码）

CLI 必须在运行时找到 Helper App 的位置。Homebrew 安装后的路径关系：

```
/usr/local/bin/axion                  # symlink -> ../Cellar/axion/0.1.0/bin/axion
/usr/local/Cellar/axion/0.1.0/
  bin/axion                           # 实际 CLI 二进制
  libexec/axion/AxionHelper.app/      # Helper App Bundle
```

**路径解析策略（优先级从高到低）：**

1. **环境变量 `AXION_HELPER_PATH`** — CI/测试/自定义安装场景
2. **相对于可执行文件解析** — `Bundle.main.executableURL` 获取 CLI 路径，然后 `../libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper`
3. **开发模式回退** — 检测可执行文件路径中是否包含 `.build`，如果是则查找 `PROJECT_ROOT/.build/AxionHelper.app`

```swift
struct HelperPathResolver {
    static func resolveHelperPath() -> String? {
        // 1. 环境变量覆盖
        if let envPath = ProcessInfo.processInfo.environment["AXION_HELPER_PATH"] {
            return envPath
        }

        // 2. 相对于可执行文件
        if let execURL = Bundle.main.executableURL {
            let execDir = execURL.deletingLastPathComponent()  // bin/
            let helperPath = execDir
                .deletingLastPathComponent()                   // Cellar/axion/0.1.0/
                .appendingPathComponent("libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper")
            if FileManager.default.fileExists(atPath: helperPath.path) {
                return helperPath.path
            }

            // 3. 开发模式回退
            if execDir.path.contains(".build") {
                let projectRoot = findProjectRoot(from: execDir)
                let devPath = projectRoot?
                    .appendingPathComponent(".build/AxionHelper.app/Contents/MacOS/AxionHelper")
                if let devPath = devPath, FileManager.default.fileExists(atPath: devPath.path) {
                    return devPath.path
                }
            }
        }
        return nil
    }
}
```

**注意：** Story 3.1（Helper Process Manager）将使用此路径启动 Helper。本 Story 只实现路径解析，不实现进程管理。

### 签名策略

**MVP 阶段签名方案：**
- 默认使用 **ad-hoc 签名**（`codesign --force --sign -`），无需 Apple Developer 账号
- ad-hoc 签名足够用于本地测试和开发
- 添加 `--sign-identity <identity>` 参数支持正式签名

**正式发布签名（需要 Apple Developer 账号）：**
```bash
codesign --force --sign "Developer ID Application: Your Name (TEAMID)" \
    --entitlements AxionHelper.entitlements \
    AxionHelper.app
```

**Entitlements 已就绪**（`Distribution/homebrew/AxionHelper.entitlements`）：
- `com.apple.security.automation.apple-events` — 允许发送 Apple Events

**Info.plist 已就绪**（`Distribution/homebrew/Info.plist`）：
- `LSUIElement=true` — 无 Dock 图标，后台运行
- `LSMinimumSystemVersion=13.0`（注意：实际代码要求 macOS 14+，此处保留 13.0 以扩大兼容性声明）
- `CFBundleIdentifier=com.axion.helper`

### build-helper-app.sh 当前行为（已验证）

1. 编译 AxionHelper（debug 或 release）
2. 创建 `.app` Bundle 结构：`Contents/MacOS/AxionHelper` + `Contents/Info.plist`
3. 从模板生成 Info.plist（替换 `{{VERSION}}`）
4. 可选 ad-hoc 签名（`--sign` 参数）

**需要增强：**
- 签名时嵌入 entitlements（`--entitlements AxionHelper.entitlements`）
- 支持 `--sign-identity` 参数指定 Developer ID

### build-release.sh 当前行为（已验证）

1. 调用 `build-helper-app.sh release`
2. 组装分发目录：`bin/axion` + `libexec/axion/AxionHelper.app/`
3. 打包为 `axion-{version}.tar.gz`
4. 计算 sha256
5. 从模板生成 `axion.rb`

**注意：** 当前脚本重命名 `AxionCLI` 为 `axion`（`cp "$BUILD_DIR/AxionCLI" "$DIST_DIR/bin/axion"`），这是正确的。

### Homebrew Tap 仓库结构

需要在 GitHub 上创建 `terryso/homebrew-tap` 仓库，结构如下：

```
homebrew-tap/
  Formula/
    axion.rb        # 由 build-release.sh 从模板生成
```

用户通过以下命令添加 tap 并安装：
```bash
brew tap terryso/tap
brew install axion
# 或一行命令
brew install terryso/tap/axion
```

### 与前后 Story 的关系

- **Story 2.3（axion setup）**：setup 引导的权限检查引用 AxionHelper.app — doctor 中的 fixHint 提到 "添加 AxionHelper.app 到辅助功能"（Story 2.4 review 已 deferred 此问题，本 Story 安装后 Helper 才存在）
- **Story 2.4（axion doctor）**：doctor 的 fixHint 引用 AxionHelper.app，安装后才生效
- **Story 3.1（Helper Process Manager）**：将使用 `HelperPathResolver` 找到并启动 Helper
- **Story 1.6（Helper 集成与打包）**：已创建打包基础设施（build-helper-app.sh 等），本 Story 增强并验证

### 模块依赖规则

```
HelperPathResolver.swift 可以 import:
  - Foundation (系统)
  - ArgumentParser (第三方 — 间接通过 AxionCLI)
  - AxionCore (项目内部)

禁止 import:
  - AxionHelper (进程隔离)
  - OpenAgentSDK (路径解析不需要 Agent 功能)
```

### 目录结构

```
Sources/AxionCLI/
  Helper/
    HelperPathResolver.swift           # 新建：Helper App 路径解析

Distribution/homebrew/
  build-helper-app.sh                  # 已存在：增强签名支持
  build-release.sh                     # 已存在：验证 + 小修改
  publish-release.sh                   # 新建：GitHub Release 发布脚本
  axion.rb.template                    # 已存在：可能需要小修改（caveats）
  Info.plist                           # 已存在：无需修改
  AxionHelper.entitlements             # 已存在：无需修改

Tests/AxionCLITests/
  Helper/
    HelperPathResolverTests.swift      # 新建：路径解析单元测试
```

### 禁止事项（反模式）

- **不得硬编码绝对路径** — 使用相对路径解析 + 环境变量覆盖
- **不得假设 Homebrew 安装路径** — 支持 `/usr/local`（Intel）和 `/opt/homebrew`（Apple Silicon）
- **不得在构建脚本中使用 `sudo`** — Homebrew 不需要 root 权限
- **build-helper-app.sh 不得引用项目外路径** — 所有路径相对于 PROJECT_ROOT
- **HelperPathResolver 不得抛出异常** — 路径未找到返回 nil，由调用方决定如何处理
- **不得将 API Key 或敏感信息包含在 tar.gz 中** — tar.gz 只包含编译产物

### 参考实现（OpenClick）

OpenClick 的 `/Users/nick/CascadeProjects/openclick/src/mac-app.ts` 提供以下参考：
- App Bundle 创建流程（构建产物 → .app 目录结构 → Info.plist + 可执行文件）
- Entitlements 嵌入签名流程
- 版本号注入机制

OpenClick 的 Homebrew 分发：
- 使用 GitHub Releases 托管 tar.gz
- formula 通过 `sha256` 校验
- `depends_on :macos` 声明平台要求

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.5] 原始 Story 定义和 AC
- [Source: _bmad-output/planning-artifacts/architecture.md#项目脚手架评估] SPM 项目结构和 Distribution 目录
- [Source: _bmad-output/planning-artifacts/architecture.md#D8] Helper 进程生命周期（路径解析是进程启动的前置条件）
- [Source: _bmad-output/planning-artifacts/prd.md#FR1] Homebrew 一行命令安装
- [Source: _bmad-output/project-context.md#Helper App 打包细节] LSUIElement, LSMinimumSystemVersion, Entitlements, Homebrew 安装路径
- [Source: _bmad-output/project-context.md#模块依赖] AxionCLI 依赖规则
- [Source: Distribution/homebrew/build-helper-app.sh] 已有的 Helper App Bundle 构建脚本
- [Source: Distribution/homebrew/build-release.sh] 已有的完整发布构建脚本
- [Source: Distribution/homebrew/axion.rb.template] Homebrew formula 模板
- [Source: Distribution/homebrew/Info.plist] Helper App Info.plist（LSUIElement=true）
- [Source: Distribution/homebrew/AxionHelper.entitlements] Entitlements（apple-events 权限）
- [Source: Package.swift] SPM 构建配置（AxionCLI / AxionHelper / AxionCore 三目标）
- [Source: _bmad-output/implementation-artifacts/2-4-axion-doctor-environment-check.md] Story 2.4 完成（Review deferred: fixHint 引用 AxionHelper.app 未安装问题）

### ATDD Artifacts

- Unit tests: Tests/AxionCLITests/Helper/HelperPathResolverTests.swift

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m] (via Claude Code)

### Debug Log References

No issues encountered during implementation.

### Completion Notes List

- Implemented HelperPathResolver with three-tier path resolution: env variable > relative path > dev fallback
- All 16 pre-existing ATDD tests pass (removed XCTSkipIf guards, implementation satisfied all assertions)
- Enhanced build-helper-app.sh: added --sign-identity, --arch params, entitlements embedded in all signing
- Enhanced build-release.sh: added --sign-identity passthrough
- Added caveats section to axion.rb.template with setup/doctor guidance
- Created publish-release.sh for automated GitHub Release + tap formula update
- Full regression suite: 211 tests, 0 failures

### File List

- Sources/AxionCLI/Helper/HelperPathResolver.swift (modified: implemented path resolution)
- Tests/AxionCLITests/Helper/HelperPathResolverTests.swift (modified: removed XCTSkipIf guards)
- Distribution/homebrew/build-helper-app.sh (modified: --sign-identity, --arch, entitlements)
- Distribution/homebrew/build-release.sh (modified: --sign-identity passthrough)
- Distribution/homebrew/axion.rb.template (modified: added caveats section)
- Distribution/homebrew/publish-release.sh (new: GitHub Release + tap update automation)

### Change Log

- 2026-05-09: Story 2-5 implementation complete -- HelperPathResolver (16 tests), build scripts enhanced, formula updated, publish-release.sh created (GLM-5.1[1m])
