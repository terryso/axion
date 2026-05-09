import XCTest
@testable import AxionCLI
@testable import AxionCore

// [P0] 基础设施验证 — ConfigManager 存在性和类型签名
// [P1] 行为验证 — 分层配置加载优先级
// Story 2.2 AC: #1, #2, #3, #4, #5, #6

final class ConfigManagerTests: XCTestCase {

    // MARK: - 测试辅助

    /// 临时目录路径（每次测试唯一）
    private var tempDir: String!

    /// 测试用 config.json 路径
    private var configFilePath: String!

    override func setUp() async throws {
        try await super.setUp()
        // 创建隔离的临时目录
        tempDir = NSTemporaryDirectory() + "axion-test-config-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        configFilePath = tempDir + "/config.json"
    }

    override func tearDown() async throws {
        // 清理临时目录
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
        // 清理可能残留的环境变量
        cleanTestEnvVars()
        try await super.tearDown()
    }

    private func cleanTestEnvVars() {
        unsetenv("AXION_API_KEY")
        unsetenv("AXION_MODEL")
        unsetenv("AXION_MAX_STEPS")
        unsetenv("AXION_MAX_BATCHES")
        unsetenv("AXION_MAX_REPLAN_RETRIES")
        unsetenv("AXION_TRACE_ENABLED")
        unsetenv("AXION_SHARED_SEAT_MODE")
    }

    private func writeConfigJSON(_ json: String) throws {
        try json.write(
            toFile: configFilePath,
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - [P0] ConfigManager 类型存在性

    // 验证 ConfigManager 类型存在
    func test_configManager_typeExists() throws {
        _ = ConfigManager.self
    }

    // 验证 CLIOverrides 类型存在
    func test_cliOverrides_typeExists() throws {
        _ = CLIOverrides.self
    }

    // MARK: - [P0] AC1: config.json 读写（含 API Key）

    // 验证 config.json 中的 apiKey 和 maxSteps 正确读取
    func test_loadConfig_apiKeyFromFile() async throws {
        let configJSON = """
        {
          "apiKey": "sk-ant-test-key-12345678",
          "maxSteps": 30
        }
        """
        try writeConfigJSON(configJSON)

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil
        )

        XCTAssertEqual(config.apiKey, "sk-ant-test-key-12345678", "apiKey 应从 config.json 读取")
        XCTAssertEqual(config.maxSteps, 30, "maxSteps 应从 config.json 读取")
    }

    // MARK: - [P0] AC2: 配置文件覆盖默认值

    // 验证 config.json 中的 maxSteps 覆盖默认值 20
    func test_loadConfig_fileOverridesDefault() async throws {
        let configJSON = """
        {
          "maxSteps": 30
        }
        """
        try writeConfigJSON(configJSON)

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil
        )

        XCTAssertEqual(config.maxSteps, 30, "config.json 中的 maxSteps 应覆盖默认值 20")
        XCTAssertEqual(config.model, AxionConfig.default.model, "未覆盖的字段应保持默认值")
        XCTAssertEqual(config.maxBatches, AxionConfig.default.maxBatches, "未覆盖的字段应保持默认值")
    }

    // MARK: - [P0] AC3: 环境变量覆盖配置文件

    // 验证环境变量 AXION_MODEL 覆盖 config.json 中的 model
    func test_loadConfig_envOverridesFile() async throws {
        let configJSON = """
        {
          "model": "claude-sonnet-4-20250514"
        }
        """
        try writeConfigJSON(configJSON)
        setenv("AXION_MODEL", "claude-opus-4", 1)

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil
        )

        XCTAssertEqual(config.model, "claude-opus-4", "环境变量 AXION_MODEL 应覆盖 config.json")
    }

    // 验证环境变量 AXION_MAX_STEPS 覆盖 config.json
    func test_loadConfig_envMaxStepsOverridesFile() async throws {
        let configJSON = """
        {
          "maxSteps": 30
        }
        """
        try writeConfigJSON(configJSON)
        setenv("AXION_MAX_STEPS", "50", 1)

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil
        )

        XCTAssertEqual(config.maxSteps, 50, "环境变量 AXION_MAX_STEPS 应覆盖 config.json")
    }

    // 验证布尔型环境变量 AXION_TRACE_ENABLED 正确解析
    func test_loadConfig_envBoolTraceEnabled() async throws {
        setenv("AXION_TRACE_ENABLED", "false", 1)

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil
        )

        XCTAssertFalse(config.traceEnabled, "AXION_TRACE_ENABLED=false 应覆盖默认值 true")
    }

    // MARK: - [P0] AC4: CLI 参数优先级最高

    // 验证 CLI 参数覆盖环境变量
    func test_loadConfig_cliOverridesEnv() async throws {
        setenv("AXION_MAX_STEPS", "50", 1)

        let cliOverrides = CLIOverrides(
            maxSteps: 10,
            maxBatches: nil
        )

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: cliOverrides
        )

        XCTAssertEqual(config.maxSteps, 10, "CLI 参数应覆盖环境变量")
    }

    // 验证 CLI 参数覆盖 config.json 和默认值
    func test_loadConfig_cliOverridesAllLayers() async throws {
        let configJSON = """
        {
          "maxSteps": 30,
          "maxBatches": 8
        }
        """
        try writeConfigJSON(configJSON)
        setenv("AXION_MAX_STEPS", "50", 1)

        let cliOverrides = CLIOverrides(
            maxSteps: 10,
            maxBatches: 2
        )

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: cliOverrides
        )

        XCTAssertEqual(config.maxSteps, 10, "CLI maxSteps 应覆盖环境变量和文件")
        XCTAssertEqual(config.maxBatches, 2, "CLI maxBatches 应覆盖文件")
    }

    // MARK: - [P0] AC2 无文件无环境变量返回默认值

    // 验证无 config.json、无环境变量时返回全部默认值
    func test_loadConfig_noFileNoEnv_returnsDefault() async throws {
        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil
        )

        XCTAssertEqual(config.model, AxionConfig.default.model)
        XCTAssertEqual(config.maxSteps, AxionConfig.default.maxSteps)
        XCTAssertEqual(config.maxBatches, AxionConfig.default.maxBatches)
        XCTAssertEqual(config.maxReplanRetries, AxionConfig.default.maxReplanRetries)
        XCTAssertEqual(config.traceEnabled, AxionConfig.default.traceEnabled)
        XCTAssertEqual(config.sharedSeatMode, AxionConfig.default.sharedSeatMode)
        XCTAssertNil(config.apiKey, "无环境变量无文件时 apiKey 应为 nil")
    }

    // MARK: - [P1] 无效 JSON 文件回退到默认值

    // 验证无效 JSON 文件不崩溃，回退到默认值
    func test_loadConfig_invalidJsonFile_fallsBackToDefault() async throws {
        try writeConfigJSON("}{not valid json")

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil
        )

        XCTAssertEqual(config.maxSteps, AxionConfig.default.maxSteps, "无效 JSON 应回退到默认值")
    }

    // MARK: - [P0] AC6: 环境变量 AXION_API_KEY 覆盖文件

    // 验证环境变量 AXION_API_KEY 覆盖 config.json 中的 apiKey
    func test_loadConfig_apiKeyEnvOverridesFile() async throws {
        let configJSON = """
        {
          "apiKey": "sk-ant-from-file"
        }
        """
        try writeConfigJSON(configJSON)
        setenv("AXION_API_KEY", "sk-ant-from-env", 1)

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil
        )

        XCTAssertEqual(config.apiKey, "sk-ant-from-env", "环境变量应优先于 config.json")
    }

    // MARK: - [P0] AC5: 保存配置文件包含 apiKey

    // 验证 saveConfigFile 包含 apiKey
    func test_saveConfigFile_includesApiKey() async throws {
        var config = AxionConfig.default
        config.apiKey = "sk-ant-test-key"

        try ConfigManager.saveConfigFile(config, toDirectory: tempDir)

        let savedData = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let savedJSON = try JSONSerialization.jsonObject(with: savedData) as! [String: Any]

        XCTAssertEqual(savedJSON["apiKey"] as? String, "sk-ant-test-key", "保存的配置文件应包含 apiKey")
        XCTAssertNotNil(savedJSON["model"], "保存的配置文件应包含 model 字段")
        XCTAssertNotNil(savedJSON["maxSteps"], "保存的配置文件应包含 maxSteps 字段")
    }

    // 验证保存的 JSON 可被正确解码回 AxionConfig（含 apiKey）
    func test_saveConfigFile_roundTripWithApiKey() async throws {
        var config = AxionConfig.default
        config.apiKey = "sk-ant-secret"
        config.maxSteps = 42

        try ConfigManager.saveConfigFile(config, toDirectory: tempDir)

        let savedData = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: savedData)

        XCTAssertEqual(decoded.apiKey, "sk-ant-secret", "解码后 apiKey 应与保存值一致")
        XCTAssertEqual(decoded.maxSteps, 42, "解码后 maxSteps 应与保存值一致")
    }

    // MARK: - [P1] 配置目录创建

    // 验证 ensureConfigDirectory 创建目录
    func test_ensureConfigDirectory_createsDirectory() throws {
        let newDir = tempDir + "/subdir/deep"
        try ConfigManager.ensureConfigDirectory(atPath: newDir)

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: newDir, isDirectory: &isDir)
        XCTAssertTrue(exists, "ensureConfigDirectory 应创建目录")
        XCTAssertTrue(isDir.boolValue, "路径应为目录")
    }

    // MARK: - [P1] 完整分层加载验证

    // 验证完整分层加载链：默认值 -> 文件 -> 环境变量 -> CLI
    func test_loadConfig_fullLayerStack() async throws {
        // 第 2 层：config.json 覆盖部分默认值
        let configJSON = """
        {
          "model": "file-model",
          "maxSteps": 30,
          "maxBatches": 8,
          "traceEnabled": false
        }
        """
        try writeConfigJSON(configJSON)

        // 第 3 层：环境变量覆盖文件部分值
        setenv("AXION_MODEL", "env-model", 1)
        setenv("AXION_MAX_STEPS", "40", 1)

        // 第 4 层：CLI 参数覆盖环境变量部分值
        let cliOverrides = CLIOverrides(
            maxSteps: 10,
            maxBatches: nil
        )

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: cliOverrides
        )

        // CLI 覆盖环境变量
        XCTAssertEqual(config.maxSteps, 10, "CLI maxSteps=10 应覆盖环境变量 40")
        // 环境变量覆盖文件
        XCTAssertEqual(config.model, "env-model", "AXION_MODEL 应覆盖文件值")
        // 文件覆盖默认值
        XCTAssertEqual(config.maxBatches, 8, "文件 maxBatches=8 应覆盖默认值 6")
        // 文件覆盖默认布尔值
        XCTAssertFalse(config.traceEnabled, "文件 traceEnabled=false 应覆盖默认值 true")
        // 未被覆盖保持默认值
        XCTAssertEqual(config.maxReplanRetries, AxionConfig.default.maxReplanRetries, "未被覆盖的字段保持默认值")
        XCTAssertEqual(config.sharedSeatMode, AxionConfig.default.sharedSeatMode, "未被覆盖的字段保持默认值")
    }
}
