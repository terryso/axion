import Foundation
import Testing
@testable import AxionCLI
@testable import AxionCore

// MARK: - MockSetupIO

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

@Suite("SetupCommand")
struct SetupCommandTests {

    let tempDir: String
    let configFilePath: String

    init() {
        tempDir = NSTemporaryDirectory() + "axion-test-setup-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        configFilePath = tempDir + "/config.json"
    }

    // MARK: - [P0] SetupIO 协议存在性

    @Test("SetupIO protocol exists")
    func setupIOProtocolExists() {
        let mock: SetupIO = MockSetupIO(inputs: [])
        _ = mock
    }

    @Test("MockSetupIO captures writes")
    func mockSetupIOCapturesWrites() {
        let mock = MockSetupIO(inputs: [])
        mock.write("hello")
        #expect(mock.capturedOutput.contains("hello"))
    }

    @Test("MockSetupIO returns preset inputs")
    func mockSetupIOReturnsPresetInputs() {
        let mock = MockSetupIO(inputs: ["input1", "input2"])
        #expect(mock.prompt("q1") == "input1")
        #expect(mock.prompt("q2") == "input2")
    }

    // MARK: - [P0] maskApiKey

    @Test("maskApiKey long key shows masked")
    func maskApiKeyLongKeyShowsMasked() {
        let key = "sk-ant-api03-1234567890abcdef"
        let masked = maskApiKey(key)
        #expect(masked.hasPrefix("sk-ant"))
        #expect(masked.hasSuffix("ef"))
        #expect(masked.contains("***"))
        #expect(!masked.contains("1234567890abcd"))
    }

    @Test("maskApiKey short key shows masked")
    func maskApiKeyShortKeyShowsMasked() {
        #expect(maskApiKey("short123") == "***")
    }

    @Test("maskApiKey empty key returns empty")
    func maskApiKeyEmptyKeyReturnsEmpty() {
        #expect(maskApiKey("") == "")
    }

    // MARK: - [P0] PermissionChecker

    @Test("PermissionChecker type exists")
    func permissionCheckerTypeExists() {
        _ = PermissionChecker.self
    }

    @Test("PermissionStatus enum exists")
    func permissionStatusEnumExists() {
        _ = [PermissionStatus.granted, .notGranted, .unknown]
    }

    @Test("PermissionChecker checkAccessibility returns status")
    func permissionCheckerCheckAccessibilityReturnsStatus() {
        _ = PermissionChecker.checkAccessibility()
    }

    @Test("PermissionChecker checkScreenRecording returns status")
    func permissionCheckerCheckScreenRecordingReturnsStatus() {
        _ = PermissionChecker.checkScreenRecording()
    }

    // MARK: - [P0] 默认 Anthropic provider + API Key 保存

    @Test("setup saves Anthropic API key")
    func setupSavesAnthropicApiKey() throws {
        let testKey = "sk-ant-test-key-1234567890"
        let mock = MockSetupIO(inputs: ["", testKey, ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["apiKey"] as? String == testKey)
        #expect(json["provider"] as? String == "anthropic")
    }

    // MARK: - [P0] OpenAI provider

    @Test("setup saves OpenAI provider")
    func setupSavesOpenAIProvider() throws {
        let testKey = "sk-openai-key-1234567890"
        let mock = MockSetupIO(inputs: ["2", testKey, ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["provider"] as? String == "openai")
        #expect(json["apiKey"] as? String == testKey)
    }

    // MARK: - [P0] 自定义 baseURL

    @Test("setup saves custom baseURL")
    func setupSavesCustomBaseURL() throws {
        let testKey = "sk-ant-test-key-1234567890"
        let customURL = "https://my-proxy.example.com/v1"
        let mock = MockSetupIO(inputs: ["", testKey, customURL])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["baseURL"] as? String == customURL)
    }

    // MARK: - [P0] 留空 baseURL 不写入

    @Test("setup empty baseURL saves nil")
    func setupEmptyBaseURLSavesNil() throws {
        let testKey = "sk-ant-test-key-1234567890"
        let mock = MockSetupIO(inputs: ["", testKey, ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["baseURL"] == nil, "留空时 baseURL 不应写入 config")
    }

    // MARK: - [P0] 自动创建配置目录

    @Test("setup creates config directory if missing")
    func setupCreatesConfigDirectoryIfMissing() throws {
        let newDir = tempDir + "/deep/nested/.axion"
        try ConfigManager.ensureConfigDirectory(atPath: newDir)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: newDir, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    // MARK: - [P0] API Key 掩码

    @Test("setup shows masked API key in summary")
    func setupShowsMaskedApiKeyInSummary() throws {
        let testKey = "sk-ant-api03-supersecret123456"
        let masked = maskApiKey(testKey)
        #expect(!masked.contains("supersecret"))
        #expect(masked.contains("***"))

        let mock = MockSetupIO(inputs: ["", testKey, ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let outputText = mock.capturedOutput.joined(separator: " ")
        #expect(!outputText.contains(testKey), "完整 API Key 不应出现在终端输出中")
        #expect(outputText.contains(masked), "掩码后的 API Key 应出现在输出中")
    }

    // MARK: - [P0] 权限检查输出

    @Test("setup shows accessibility check result")
    func setupShowsAccessibilityCheckResult() throws {
        let mock = MockSetupIO(inputs: ["", "sk-ant-test-key-1234567890", ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let outputText = mock.capturedOutput.joined(separator: "\n")
        #expect(outputText.contains("Accessibility"), "输出应包含 Accessibility 检查结果")
    }

    @Test("setup shows screen recording check result")
    func setupShowsScreenRecordingCheckResult() throws {
        let mock = MockSetupIO(inputs: ["", "sk-ant-test-key-1234567890", ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let outputText = mock.capturedOutput.joined(separator: "\n")
        #expect(outputText.contains("屏幕录制"), "输出应包含屏幕录制检查结果")
    }

    // MARK: - [P0] 完成提示

    @Test("setup shows completion message")
    func setupShowsCompletionMessage() throws {
        let mock = MockSetupIO(inputs: ["", "sk-ant-test-key-1234567890", ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let outputText = mock.capturedOutput.joined(separator: "\n")
        #expect(outputText.contains("Setup complete"))
        #expect(outputText.contains("axion doctor"))
    }

    // MARK: - [P0] 检测已有 API Key

    @Test("setup detects existing API key")
    func setupDetectsExistingApiKey() throws {
        let existingKey = "sk-ant-existing-key-123456"
        let configJSON = "{\"apiKey\":\"\(existingKey)\"}"
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockSetupIO(inputs: ["", ""], confirmResults: [false])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let outputText = mock.capturedOutput.joined(separator: "\n")
        #expect(outputText.contains("已有 API Key"))
        #expect(outputText.contains("是否替换"))
    }

    // MARK: - [P1] 保留已有 API Key

    @Test("setup keeps existing API key when user declines")
    func setupKeepsExistingApiKeyWhenUserDeclines() throws {
        let existingKey = "sk-ant-existing-key-123456"
        let configJSON = "{\"apiKey\":\"\(existingKey)\"}"
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockSetupIO(inputs: ["", ""], confirmResults: [false])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["apiKey"] as? String == existingKey)
    }

    // MARK: - [P1] 替换 API Key

    @Test("setup replaces API key when user confirms")
    func setupReplacesApiKeyWhenUserConfirms() throws {
        let existingKey = "sk-ant-old-key-1234567890"
        let newKey = "sk-ant-new-key-1234567890"
        let configJSON = "{\"apiKey\":\"\(existingKey)\"}"
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockSetupIO(inputs: ["", newKey, ""], confirmResults: [true])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["apiKey"] as? String == newKey)
    }

    // MARK: - [P0] config.json 文件权限 0o600

    @Test("setup config file permissions are 600")
    func setupConfigFilePermissionsAre600() throws {
        var config = AxionConfig.default
        config.apiKey = "sk-ant-test-key"
        try ConfigManager.saveConfigFile(config, toDirectory: tempDir)

        let attrs = try FileManager.default.attributesOfItem(atPath: configFilePath)
        let permissions = attrs[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    // MARK: - [P1] 空输入重新提示

    @Test("setup rejects empty API key and reprompts")
    func setupRejectsEmptyApiKeyAndReprompts() throws {
        let mock = MockSetupIO(inputs: ["", "", "sk-ant-valid-key-1234567890", ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        #expect(mock.capturedOutput.contains(where: { $0.contains("不能为空") }))

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["apiKey"] as? String == "sk-ant-valid-key-1234567890")
    }

    // MARK: - [P1] API Key 前后空格被修剪

    @Test("setup trimmed API key is saved")
    func setupTrimmedApiKeyIsSaved() throws {
        let mock = MockSetupIO(inputs: ["", "  sk-ant-key-with-spaces  ", ""])
        try SetupCommand.runSetup(io: mock, configDirectory: tempDir)

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["apiKey"] as? String == "sk-ant-key-with-spaces")
    }

    // MARK: - [P1] LLMProvider enum

    @Test("LLMProvider has expected cases")
    func llmProviderHasExpectedCases() {
        #expect(LLMProvider.anthropic.rawValue == "anthropic")
        #expect(LLMProvider.openai.rawValue == "openai")
    }
}
