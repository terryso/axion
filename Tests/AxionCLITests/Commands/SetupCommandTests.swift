import XCTest
@testable import AxionCLI
@testable import AxionCore

// [P0] 基础设施验证 — SetupCommand 类型存在性和协议定义
// [P1] 行为验证 — setup 引导流程、API Key 掩码、权限检查、重复运行处理
// Story 2.3 AC: #1, #2, #3, #4, #5, #6, #7

// MARK: - MockSetupIO

/// MockSetupIO — 实现 SetupIO 协议，预设输入/捕获输出，用于单元测试。
final class MockSetupIO: SetupIO {
    var capturedOutput: [String] = []
    private var inputs: [String]
    private var inputIndex: Int = 0
    private var confirmResults: [Bool]
    private var confirmIndex: Int = 0

    init(inputs: [String], confirmResults: [Bool] = []) {
        self.inputs = inputs
        self.confirmResults = confirmResults
    }

    func write(_ line: String) {
        capturedOutput.append(line)
    }

    func prompt(_ question: String) -> String {
        defer { inputIndex += 1 }
        return inputIndex < inputs.count ? inputs[inputIndex] : ""
    }

    func promptSecret(_ question: String) -> String {
        defer { inputIndex += 1 }
        return inputIndex < inputs.count ? inputs[inputIndex] : ""
    }

    func confirm(_ question: String, defaultAnswer: Bool) -> Bool {
        capturedOutput.append(question)
        defer { confirmIndex += 1 }
        return confirmIndex < confirmResults.count ? confirmResults[confirmIndex] : defaultAnswer
    }
}

// MARK: - 测试类

final class SetupCommandTests: XCTestCase {

    // MARK: - 测试辅助

    /// 临时目录路径（每次测试唯一）
    private var tempDir: String!

    /// 测试用 config.json 路径
    private var configFilePath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = NSTemporaryDirectory() + "axion-test-setup-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        configFilePath = tempDir + "/config.json"
    }

    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - [P0] SetupIO 协议存在性

    // 验证 SetupIO 协议类型存在
    func test_setupIO_protocolExists() throws {
        // SetupIO 协议已在 Sources/AxionCLI/IO/SetupIO.swift 定义
        // MockSetupIO 实现了该协议，编译通过即验证
        let mock: SetupIO = MockSetupIO(inputs: [])
        _ = mock
    }

    // MARK: - [P0] MockSetupIO 捕获输出

    // 验证 MockSetupIO 能捕获 write 调用的输出
    func test_mockSetupIO_capturesWrites() throws {
        let mock = MockSetupIO(inputs: [])
        mock.write("hello")
        XCTAssertTrue(mock.capturedOutput.contains("hello"))
    }

    // 验证 MockSetupIO 能返回预设的输入
    func test_mockSetupIO_returnsPresetInputs() throws {
        let mock = MockSetupIO(inputs: ["input1", "input2"])
        let result1 = mock.prompt("question1")
        let result2 = mock.prompt("question2")
        XCTAssertEqual(result1, "input1")
        XCTAssertEqual(result2, "input2")
    }

    // MARK: - [P0] AC6: maskApiKey 长密钥掩码

    // 验证长 API Key 被正确掩码（显示前缀和后缀）
    func test_maskApiKey_longKey_showsMasked() throws {
        let key = "sk-ant-api03-1234567890abcdef"
        let masked = maskApiKey(key)
        XCTAssertTrue(masked.hasPrefix("sk-ant"))
        XCTAssertTrue(masked.hasSuffix("ef"))
        XCTAssertTrue(masked.contains("***"))
        XCTAssertFalse(masked.contains("1234567890abcd"))
    }

    // MARK: - [P1] AC6: maskApiKey 短密钥掩码

    // 验证短 API Key（<= 9 字符）仅显示 ***
    func test_maskApiKey_shortKey_showsMasked() throws {
        let key = "short123"
        let masked = maskApiKey(key)
        XCTAssertEqual(masked, "***")
    }

    // MARK: - [P1] AC6: maskApiKey 空密钥

    // 验证空 API Key 返回空字符串
    func test_maskApiKey_emptyKey_returnsEmpty() throws {
        let masked = maskApiKey("")
        XCTAssertEqual(masked, "")
    }

    // MARK: - [P0] PermissionChecker 类型存在性

    // 验证 PermissionChecker 类型存在
    func test_permissionChecker_typeExists() throws {
        // PermissionChecker 定义在 Sources/AxionCLI/Permissions/PermissionChecker.swift
        // 编译通过即验证类型存在
        _ = PermissionChecker.self
    }

    // 验证 PermissionStatus 枚举存在且包含所有 case
    func test_permissionStatus_enumExists() throws {
        let granted = PermissionStatus.granted
        let notGranted = PermissionStatus.notGranted
        let unknown = PermissionStatus.unknown
        _ = [granted, notGranted, unknown]
    }

    // MARK: - [P0] AC3: Accessibility 权限检查

    // 验证 checkAccessibility 返回 PermissionStatus
    func test_permissionChecker_checkAccessibility_returnsStatus() throws {
        let status = PermissionChecker.checkAccessibility()
        // 不验证具体值（环境相关），只验证返回类型正确
        _ = status
    }

    // MARK: - [P0] AC4: 屏幕录制权限检查

    // 验证 checkScreenRecording 返回 PermissionStatus
    func test_permissionChecker_checkScreenRecording_returnsStatus() throws {
        let status = PermissionChecker.checkScreenRecording()
        _ = status
    }

    // MARK: - [P0] AC1: 提示输入 API Key

    // 验证无配置时 setup 提示用户输入 API Key
    func test_setup_promptsForApiKey_whenNoConfig() throws {
        let mock = MockSetupIO(inputs: ["sk-ant-test-key-1234567890"])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        // 验证通过 promptSecret 提示输入 API Key
        XCTAssertTrue(mock.capturedOutput.contains(where: { $0.contains("Setup complete") }))
    }

    // MARK: - [P0] AC2: API Key 保存到 config.json

    // 验证 setup 将 API Key 正确保存到 config.json
    func test_setup_savesApiKey_toConfigJson() throws {
        let testKey = "sk-ant-test-key-1234567890"

        let mock = MockSetupIO(inputs: [testKey])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        // 验证文件内容
        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["apiKey"] as? String, testKey)
    }

    // MARK: - [P0] AC2: 自动创建配置目录

    // 验证配置目录不存在时自动创建
    func test_setup_createsConfigDirectory_ifMissing() throws {
        let newDir = tempDir + "/deep/nested/.axion"
        try ConfigManager.ensureConfigDirectory(atPath: newDir)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: newDir, isDirectory: &isDir)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - [P0] AC6: 摘要中 API Key 被掩码

    // 验证 setup 显示的配置摘要中 API Key 被掩码
    func test_setup_showsMaskedApiKey_inSummary() throws {
        let testKey = "sk-ant-api03-supersecret123456"
        let masked = maskApiKey(testKey)
        XCTAssertFalse(masked.contains("supersecret"))
        XCTAssertTrue(masked.contains("***"))

        // 验证 setup 输出中 API Key 被掩码
        let mock = MockSetupIO(inputs: [testKey])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        // 完整 API Key 不应出现在输出中
        let outputText = mock.capturedOutput.joined(separator: " ")
        XCTAssertFalse(outputText.contains(testKey), "完整 API Key 不应出现在终端输出中")
        // 掩码后的 key 应该出现在输出中
        XCTAssertTrue(outputText.contains(masked), "掩码后的 API Key 应出现在输出中")
    }

    // MARK: - [P1] AC3: Accessibility 已授权时的输出

    // 验证 setup 输出包含 Accessibility 权限检查结果
    func test_setup_showsAccessibilityCheckResult() throws {
        let mock = MockSetupIO(inputs: ["sk-ant-test-key-1234567890"])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        // 验证输出包含 Accessibility 检查（OK 或 FAIL 或 ??）
        let outputText = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(
            outputText.contains("Accessibility"),
            "输出应包含 Accessibility 检查结果"
        )
    }

    // MARK: - [P1] AC4: 屏幕录制权限检查输出

    // 验证 setup 输出包含屏幕录制权限检查结果
    func test_setup_showsScreenRecordingCheckResult() throws {
        let mock = MockSetupIO(inputs: ["sk-ant-test-key-1234567890"])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        // 验证输出包含屏幕录制检查
        let outputText = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(
            outputText.contains("屏幕录制"),
            "输出应包含屏幕录制检查结果"
        )
    }

    // MARK: - [P0] AC5: 完成提示

    // 验证 setup 完成后显示正确的完成消息
    func test_setup_showsCompletionMessage() throws {
        let mock = MockSetupIO(inputs: ["sk-ant-test-key-1234567890"])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let outputText = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(
            outputText.contains("Setup complete"),
            "输出应包含 'Setup complete'"
        )
        XCTAssertTrue(
            outputText.contains("axion doctor"),
            "输出应提示运行 'axion doctor'"
        )
    }

    // MARK: - [P0] AC7: 检测已有 API Key

    // 验证 config.json 中已有 API Key 时检测到并提示用户
    func test_setup_detectsExistingApiKey() throws {
        let existingKey = "sk-ant-existing-key-123456"
        let configJSON = """
        {
          "apiKey": "\(existingKey)"
        }
        """
        try configJSON.write(
            toFile: configFilePath,
            atomically: true,
            encoding: .utf8
        )

        // 用户选择不替换
        let mock = MockSetupIO(inputs: [], confirmResults: [false])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        // 验证检测到已有 key
        let outputText = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(
            outputText.contains("已有 API Key"),
            "输出应提示检测到已有 API Key"
        )
        XCTAssertTrue(
            outputText.contains("是否替换"),
            "输出应提供替换选项"
        )
    }

    // MARK: - [P1] AC7: 用户选择保留已有 API Key

    // 验证用户选择不替换时保留已有 API Key
    func test_setup_keepsExistingApiKey_whenUserDeclines() throws {
        let existingKey = "sk-ant-existing-key-123456"
        let configJSON = """
        {
          "apiKey": "\(existingKey)"
        }
        """
        try configJSON.write(
            toFile: configFilePath,
            atomically: true,
            encoding: .utf8
        )

        let mock = MockSetupIO(inputs: [], confirmResults: [false])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        // 验证 apiKey 保持不变
        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["apiKey"] as? String, existingKey, "apiKey 应保持不变")
    }

    // MARK: - [P1] AC7: 用户选择替换 API Key

    // 验证用户确认替换时更新 API Key
    func test_setup_replacesApiKey_whenUserConfirms() throws {
        let existingKey = "sk-ant-old-key-1234567890"
        let newKey = "sk-ant-new-key-1234567890"
        let configJSON = """
        {
          "apiKey": "\(existingKey)"
        }
        """
        try configJSON.write(
            toFile: configFilePath,
            atomically: true,
            encoding: .utf8
        )

        let mock = MockSetupIO(inputs: [newKey], confirmResults: [true])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        // 验证 apiKey 更新为新的 key
        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["apiKey"] as? String, newKey, "apiKey 应更新为新值")
    }

    // MARK: - [P0] AC2: config.json 文件权限 0o600

    // 验证保存的 config.json 文件权限为 0o600
    func test_setup_configFilePermissions_are600() throws {
        var config = AxionConfig.default
        config.apiKey = "sk-ant-test-key"
        try ConfigManager.saveConfigFile(config, toDirectory: tempDir)

        let attrs = try FileManager.default.attributesOfItem(atPath: configFilePath)
        let permissions = attrs[.posixPermissions] as? Int

        XCTAssertEqual(permissions, 0o600, "config.json 文件权限应为 0o600")
    }

    // MARK: - [P1] 空输入重新提示

    // 验证用户输入空 API Key 时重新提示
    func test_setup_rejectsEmptyApiKey_andReprompts() throws {
        // 第一次输入空，第二次输入有效 key
        let mock = MockSetupIO(inputs: ["", "sk-ant-valid-key-1234567890"])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        // 验证提示了重新输入
        XCTAssertTrue(
            mock.capturedOutput.contains(where: { $0.contains("不能为空") }),
            "空输入时应提示重新输入"
        )

        // 验证最终保存了有效的 key
        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["apiKey"] as? String, "sk-ant-valid-key-1234567890")
    }

    // MARK: - [P1] API Key 前后空格被修剪

    // 验证用户输入的 API Key 前后空格被自动修剪
    func test_setup_trimmedApiKey_isSaved() throws {
        let mock = MockSetupIO(inputs: ["  sk-ant-key-with-spaces  "])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["apiKey"] as? String, "sk-ant-key-with-spaces", "API Key 前后空格应被修剪")
    }
}
