import XCTest
@testable import AxionCLI
@testable import AxionCore

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

/// 输入序列约定：[provider, apiKey, baseURL]
/// provider: "" = 默认 anthropic, "2" = openai
/// baseURL: "" = 留空使用默认
final class SetupCommandTests: XCTestCase {

    private var tempDir: String!
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

    func test_setupIO_protocolExists() throws {
        let mock: SetupIO = MockSetupIO(inputs: [])
        _ = mock
    }

    func test_mockSetupIO_capturesWrites() throws {
        let mock = MockSetupIO(inputs: [])
        mock.write("hello")
        XCTAssertTrue(mock.capturedOutput.contains("hello"))
    }

    func test_mockSetupIO_returnsPresetInputs() throws {
        let mock = MockSetupIO(inputs: ["input1", "input2"])
        XCTAssertEqual(mock.prompt("q1"), "input1")
        XCTAssertEqual(mock.prompt("q2"), "input2")
    }

    // MARK: - [P0] maskApiKey

    func test_maskApiKey_longKey_showsMasked() throws {
        let key = "sk-ant-api03-1234567890abcdef"
        let masked = maskApiKey(key)
        XCTAssertTrue(masked.hasPrefix("sk-ant"))
        XCTAssertTrue(masked.hasSuffix("ef"))
        XCTAssertTrue(masked.contains("***"))
        XCTAssertFalse(masked.contains("1234567890abcd"))
    }

    func test_maskApiKey_shortKey_showsMasked() throws {
        XCTAssertEqual(maskApiKey("short123"), "***")
    }

    func test_maskApiKey_emptyKey_returnsEmpty() throws {
        XCTAssertEqual(maskApiKey(""), "")
    }

    // MARK: - [P0] PermissionChecker

    func test_permissionChecker_typeExists() throws {
        _ = PermissionChecker.self
    }

    func test_permissionStatus_enumExists() throws {
        _ = [PermissionStatus.granted, .notGranted, .unknown]
    }

    func test_permissionChecker_checkAccessibility_returnsStatus() throws {
        _ = PermissionChecker.checkAccessibility()
    }

    func test_permissionChecker_checkScreenRecording_returnsStatus() throws {
        _ = PermissionChecker.checkScreenRecording()
    }

    // MARK: - [P0] 默认 Anthropic provider + API Key 保存

    func test_setup_savesAnthropicApiKey() throws {
        let testKey = "sk-ant-test-key-1234567890"
        // inputs: [provider="", apiKey, baseURL=""]
        let mock = MockSetupIO(inputs: ["", testKey, ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["apiKey"] as? String, testKey)
        XCTAssertEqual(json["provider"] as? String, "anthropic")
    }

    // MARK: - [P0] OpenAI provider

    func test_setup_savesOpenAIProvider() throws {
        let testKey = "sk-openai-key-1234567890"
        // inputs: [provider="2", apiKey, baseURL=""]
        let mock = MockSetupIO(inputs: ["2", testKey, ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["provider"] as? String, "openai")
        XCTAssertEqual(json["apiKey"] as? String, testKey)
    }

    // MARK: - [P0] 自定义 baseURL

    func test_setup_savesCustomBaseURL() throws {
        let testKey = "sk-ant-test-key-1234567890"
        let customURL = "https://my-proxy.example.com/v1"
        // inputs: [provider="", apiKey, baseURL=customURL]
        let mock = MockSetupIO(inputs: ["", testKey, customURL])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["baseURL"] as? String, customURL)
    }

    // MARK: - [P0] 留空 baseURL 不写入

    func test_setup_emptyBaseURL_savesNil() throws {
        let testKey = "sk-ant-test-key-1234567890"
        let mock = MockSetupIO(inputs: ["", testKey, ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(json["baseURL"], "留空时 baseURL 不应写入 config")
    }

    // MARK: - [P0] 自动创建配置目录

    func test_setup_createsConfigDirectory_ifMissing() throws {
        let newDir = tempDir + "/deep/nested/.axion"
        try ConfigManager.ensureConfigDirectory(atPath: newDir)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: newDir, isDirectory: &isDir)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - [P0] API Key 掩码

    func test_setup_showsMaskedApiKey_inSummary() throws {
        let testKey = "sk-ant-api03-supersecret123456"
        let masked = maskApiKey(testKey)
        XCTAssertFalse(masked.contains("supersecret"))
        XCTAssertTrue(masked.contains("***"))

        let mock = MockSetupIO(inputs: ["", testKey, ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let outputText = mock.capturedOutput.joined(separator: " ")
        XCTAssertFalse(outputText.contains(testKey), "完整 API Key 不应出现在终端输出中")
        XCTAssertTrue(outputText.contains(masked), "掩码后的 API Key 应出现在输出中")
    }

    // MARK: - [P0] 权限检查输出

    func test_setup_showsAccessibilityCheckResult() throws {
        let mock = MockSetupIO(inputs: ["", "sk-ant-test-key-1234567890", ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let outputText = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(outputText.contains("Accessibility"), "输出应包含 Accessibility 检查结果")
    }

    func test_setup_showsScreenRecordingCheckResult() throws {
        let mock = MockSetupIO(inputs: ["", "sk-ant-test-key-1234567890", ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let outputText = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(outputText.contains("屏幕录制"), "输出应包含屏幕录制检查结果")
    }

    // MARK: - [P0] 完成提示

    func test_setup_showsCompletionMessage() throws {
        let mock = MockSetupIO(inputs: ["", "sk-ant-test-key-1234567890", ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let outputText = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(outputText.contains("Setup complete"))
        XCTAssertTrue(outputText.contains("axion doctor"))
    }

    // MARK: - [P0] 检测已有 API Key

    func test_setup_detectsExistingApiKey() throws {
        let existingKey = "sk-ant-existing-key-123456"
        let configJSON = "{\"apiKey\":\"\(existingKey)\"}"
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        // inputs: [provider="", confirm(no)=不需要apiKey输入, baseURL=""]
        let mock = MockSetupIO(inputs: ["", ""], confirmResults: [false])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let outputText = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(outputText.contains("已有 API Key"))
        XCTAssertTrue(outputText.contains("是否替换"))
    }

    // MARK: - [P1] 保留已有 API Key

    func test_setup_keepsExistingApiKey_whenUserDeclines() throws {
        let existingKey = "sk-ant-existing-key-123456"
        let configJSON = "{\"apiKey\":\"\(existingKey)\"}"
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockSetupIO(inputs: ["", ""], confirmResults: [false])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["apiKey"] as? String, existingKey)
    }

    // MARK: - [P1] 替换 API Key

    func test_setup_replacesApiKey_whenUserConfirms() throws {
        let existingKey = "sk-ant-old-key-1234567890"
        let newKey = "sk-ant-new-key-1234567890"
        let configJSON = "{\"apiKey\":\"\(existingKey)\"}"
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        // inputs: [provider="", apiKey(new), baseURL=""]
        let mock = MockSetupIO(inputs: ["", newKey, ""], confirmResults: [true])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["apiKey"] as? String, newKey)
    }

    // MARK: - [P0] config.json 文件权限 0o600

    func test_setup_configFilePermissions_are600() throws {
        var config = AxionConfig.default
        config.apiKey = "sk-ant-test-key"
        try ConfigManager.saveConfigFile(config, toDirectory: tempDir)

        let attrs = try FileManager.default.attributesOfItem(atPath: configFilePath)
        let permissions = attrs[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    // MARK: - [P1] 空输入重新提示

    func test_setup_rejectsEmptyApiKey_andReprompts() throws {
        // inputs: [provider="", apiKey(empty), apiKey(valid), baseURL=""]
        let mock = MockSetupIO(inputs: ["", "", "sk-ant-valid-key-1234567890", ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        XCTAssertTrue(mock.capturedOutput.contains(where: { $0.contains("不能为空") }))

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["apiKey"] as? String, "sk-ant-valid-key-1234567890")
    }

    // MARK: - [P1] API Key 前后空格被修剪

    func test_setup_trimmedApiKey_isSaved() throws {
        let mock = MockSetupIO(inputs: ["", "  sk-ant-key-with-spaces  ", ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["apiKey"] as? String, "sk-ant-key-with-spaces")
    }

    // MARK: - [P1] LLMProvider enum

    func test_llmProvider_hasExpectedCases() throws {
        XCTAssertEqual(LLMProvider.anthropic.rawValue, "anthropic")
        XCTAssertEqual(LLMProvider.openai.rawValue, "openai")
    }
}
