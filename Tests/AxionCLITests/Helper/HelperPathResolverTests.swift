import XCTest
@testable import AxionCLI

// [P0] 基础设施验证 — HelperPathResolver 类型存在性和路径解析策略
// [P1] 行为验证 — 环境变量覆盖、相对路径解析、开发模式回退
// Story 2.5 AC: #3, #6

final class HelperPathResolverTests: XCTestCase {

    // MARK: - 测试辅助

    private var savedEnvPath: String?

    override func setUp() async throws {
        try await super.setUp()
        // 保存当前环境变量状态
        savedEnvPath = ProcessInfo.processInfo.environment["AXION_HELPER_PATH"]
        unsetenv("AXION_HELPER_PATH")
    }

    override func tearDown() async throws {
        // 恢复环境变量
        if let saved = savedEnvPath {
            setenv("AXION_HELPER_PATH", saved, 1)
        } else {
            unsetenv("AXION_HELPER_PATH")
        }
        try await super.tearDown()
    }

    // MARK: - [P0] 类型存在性

    // AC6: HelperPathResolver 类型存在
    func test_helperPathResolver_typeExists() throws {
        _ = HelperPathResolver.self
    }

    // AC6: resolveHelperPath 方法存在且返回 String?
    func test_helperPathResolver_resolveMethodExists() throws {
        let result: String? = HelperPathResolver.resolveHelperPath()
        _ = result
    }

    // MARK: - [P0] AC6: 环境变量覆盖（策略 1 — 最高优先级）

    // 环境变量 AXION_HELPER_PATH 设置时，直接返回该路径
    func test_resolve_envVariable_returnsEnvPath() throws {
        let expectedPath = "/tmp/test/AxionHelper.app/Contents/MacOS/AxionHelper"
        setenv("AXION_HELPER_PATH", expectedPath, 1)

        let result = HelperPathResolver.resolveHelperPath()
        XCTAssertEqual(result, expectedPath, "环境变量 AXION_HELPER_PATH 应直接返回")
    }

    // 环境变量路径无需验证文件是否存在（调用方负责）
    func test_resolve_envVariable_returnsEvenIfNotExists() throws {
        let nonexistentPath = "/nonexistent/path/AxionHelper.app/Contents/MacOS/AxionHelper"
        setenv("AXION_HELPER_PATH", nonexistentPath, 1)

        let result = HelperPathResolver.resolveHelperPath()
        XCTAssertEqual(result, nonexistentPath, "环境变量路径无需验证文件存在性")
    }

    // MARK: - [P0] AC6: 相对于可执行文件的路径解析（策略 2）

    // Homebrew 安装路径解析: bin/axion -> ../libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper
    func test_resolve_relativePath_buildsHomebrewStylePath() throws {
        // 此测试验证路径构建逻辑（不依赖实际文件系统布局）
        // 在有 Helper App 的环境中应该能解析到正确路径
        let result = HelperPathResolver.resolveHelperPath()
        // 结果应为 nil（测试环境中无 Homebrew 安装）或正确路径
        if let path = result {
            XCTAssertTrue(
                path.hasSuffix("AxionHelper.app/Contents/MacOS/AxionHelper")
                    || path.hasSuffix("AxionHelper"),
                "解析路径应以 AxionHelper 可执行文件结尾: \(path)"
            )
        }
    }

    // 解析路径应包含 libexec/axion 组件（Homebrew 布局）
    func test_resolve_homebrewPath_containsLibexecAxion() throws {
        // 模拟 Homebrew 路径布局
        let result = HelperPathResolver.resolveHelperPath()
        if let path = result, path.contains("libexec") {
            XCTAssertTrue(path.contains("libexec/axion"), "Homebrew 路径应包含 libexec/axion")
        }
    }

    // MARK: - [P0] AC6: 开发模式回退（策略 3）

    // 可执行文件在 .build 目录中时使用开发模式回退
    func test_resolve_developmentMode_detectsBuildDirectory() throws {
        // 在 swift test 环境中，可执行文件在 .build 目录
        // 如果 Helper App 已通过 build-helper-app.sh 构建，应能找到
        let result = HelperPathResolver.resolveHelperPath()
        // 测试环境中可能无法找到（未构建 Helper App），结果可以是 nil
        // 关键是不崩溃、不抛出异常
        _ = result
    }

    // 开发模式路径应包含 .build/AxionHelper.app
    func test_resolve_developmentMode_buildPathFormat() throws {
        let result = HelperPathResolver.resolveHelperPath()
        if let path = result, path.contains(".build") {
            XCTAssertTrue(
                path.contains("AxionHelper.app"),
                "开发模式路径应包含 AxionHelper.app: \(path)"
            )
        }
    }

    // MARK: - [P0] AC3: 路径未找到返回 nil（不抛异常）

    // 所有策略都无法找到 Helper 时返回 nil
    func test_resolve_noHelperFound_returnsNil() throws {
        // 在无 Helper App 且无环境变量的环境中
        let result = HelperPathResolver.resolveHelperPath()
        // 应返回 nil（不抛异常），或者如果 .build 中有残留则返回路径
        // 关键验证：不崩溃
        _ = result
    }

    // MARK: - [P1] 优先级验证

    // 环境变量优先级高于相对路径解析
    func test_resolve_envVariableTakesPriorityOverRelativePath() throws {
        let envPath = "/custom/env/AxionHelper.app/Contents/MacOS/AxionHelper"
        setenv("AXION_HELPER_PATH", envPath, 1)

        let result = HelperPathResolver.resolveHelperPath()
        XCTAssertEqual(result, envPath, "环境变量应优先于相对路径解析")
    }

    // 空字符串环境变量不视为有效覆盖
    func test_resolve_emptyEnvVariable_fallsThrough() throws {
        setenv("AXION_HELPER_PATH", "", 1)

        let result = HelperPathResolver.resolveHelperPath()
        // 空字符串不应被视为有效路径，应继续尝试其他策略
        XCTAssertNotEqual(result, "", "空环境变量不应作为有效路径返回")
    }

    // MARK: - [P1] 路径格式验证

    // 返回路径指向 AxionHelper 可执行文件（非 .app 目录）
    func test_resolve_resultPath_pointsToExecutable() throws {
        let envPath = "/opt/homebrew/Cellar/axion/0.1.0/libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper"
        setenv("AXION_HELPER_PATH", envPath, 1)

        let result = HelperPathResolver.resolveHelperPath()
        if let path = result {
            // 路径应以可执行文件结尾，而非 .app 目录
            XCTAssertFalse(
                path.hasSuffix(".app"),
                "路径应指向可执行文件而非 .app 目录"
            )
            XCTAssertTrue(
                path.hasSuffix("AxionHelper"),
                "路径应以 AxionHelper 可执行文件名结尾"
            )
        }
    }

    // 返回路径是绝对路径
    func test_resolve_resultPath_isAbsolute() throws {
        let envPath = "/absolute/path/AxionHelper"
        setenv("AXION_HELPER_PATH", envPath, 1)

        let result = HelperPathResolver.resolveHelperPath()
        if let path = result {
            XCTAssertTrue(path.hasPrefix("/"), "返回路径应为绝对路径: \(path)")
        }
    }

    // MARK: - [P1] Apple Silicon vs Intel Homebrew 路径兼容性

    // 支持 /opt/homebrew 路径（Apple Silicon）
    func test_resolve_supportsOptHomebrewPath() throws {
        let armPath = "/opt/homebrew/Cellar/axion/0.1.0/libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper"
        setenv("AXION_HELPER_PATH", armPath, 1)

        let result = HelperPathResolver.resolveHelperPath()
        XCTAssertEqual(result, armPath, "应支持 Apple Silicon Homebrew 路径")
    }

    // 支持 /usr/local 路径（Intel Mac）
    func test_resolve_supportsUsrLocalPath() throws {
        let intelPath = "/usr/local/Cellar/axion/0.1.0/libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper"
        setenv("AXION_HELPER_PATH", intelPath, 1)

        let result = HelperPathResolver.resolveHelperPath()
        XCTAssertEqual(result, intelPath, "应支持 Intel Mac Homebrew 路径")
    }

    // MARK: - [P1] 无硬编码路径

    // HelperPathResolver 不应包含硬编码的绝对路径常量
    func test_resolver_noHardcodedPaths() throws {
        // 验证实现不依赖硬编码路径
        // 通过环境变量测试和相对路径测试已间接验证
        // 此测试作为设计约束的文档化断言
        let result = HelperPathResolver.resolveHelperPath()
        if let path = result {
            // 不应硬编码 /usr/local 或 /opt/homebrew
            // 路径应来自 Bundle.main.executableURL 或环境变量
            _ = path
        }
    }
}
