import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

@Suite("ConfigManager")
struct ConfigManagerTests: ~Copyable {

    private var tempDir: String!
    private var configFilePath: String!

    init() {
        tempDir = NSTemporaryDirectory() + "axion-test-config-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        configFilePath = tempDir + "/config.json"
    }

    deinit {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
    }

    private func writeConfigJSON(_ json: String) throws {
        try json.write(
            toFile: configFilePath,
            atomically: true,
            encoding: .utf8
        )
    }

    @Test("ConfigManager type exists")
    func configManagerTypeExists() throws {
        _ = ConfigManager.self
    }

    @Test("CLIOverrides type exists")
    func cliOverridesTypeExists() throws {
        _ = CLIOverrides.self
    }

    @Test("apiKey and maxSteps read from config.json")
    func loadConfigApiKeyFromFile() async throws {
        let configJSON = """
        {
          "apiKey": "sk-ant-test-key-12345678",
          "maxSteps": 30
        }
        """
        try writeConfigJSON(configJSON)

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil,
            environment: [:]
        )

        #expect(config.apiKey == "sk-ant-test-key-12345678")
        #expect(config.maxSteps == 30)
    }

    @Test("config.json overrides default values")
    func loadConfigFileOverridesDefault() async throws {
        let configJSON = """
        {
          "maxSteps": 30
        }
        """
        try writeConfigJSON(configJSON)

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil,
            environment: [:]
        )

        #expect(config.maxSteps == 30)
        #expect(config.model == AxionConfig.default.model)
        #expect(config.maxBatches == AxionConfig.default.maxBatches)
    }

    @Test("environment variable AXION_MODEL overrides config.json")
    func loadConfigEnvOverridesFile() async throws {
        let configJSON = """
        {
          "model": "claude-sonnet-4-20250514"
        }
        """
        try writeConfigJSON(configJSON)

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil,
            environment: ["AXION_MODEL": "claude-opus-4"]
        )

        #expect(config.model == "claude-opus-4")
    }

    @Test("environment variable AXION_MAX_STEPS overrides config.json")
    func loadConfigEnvMaxStepsOverridesFile() async throws {
        let configJSON = """
        {
          "maxSteps": 30
        }
        """
        try writeConfigJSON(configJSON)

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil,
            environment: ["AXION_MAX_STEPS": "50"]
        )

        #expect(config.maxSteps == 50)
    }

    @Test("AXION_TRACE_ENABLED=false parsed correctly")
    func loadConfigEnvBoolTraceEnabled() async throws {
        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil,
            environment: ["AXION_TRACE_ENABLED": "false"]
        )

        #expect(!config.traceEnabled)
    }

    @Test("CLI arguments override environment variables")
    func loadConfigCLIOverridesEnv() async throws {
        let cliOverrides = CLIOverrides(
            maxSteps: 10,
            maxBatches: nil
        )

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: cliOverrides,
            environment: ["AXION_MAX_STEPS": "50"]
        )

        #expect(config.maxSteps == 10)
    }

    @Test("CLI arguments override all layers")
    func loadConfigCLIOverridesAllLayers() async throws {
        let configJSON = """
        {
          "maxSteps": 30,
          "maxBatches": 8
        }
        """
        try writeConfigJSON(configJSON)

        let cliOverrides = CLIOverrides(
            maxSteps: 10,
            maxBatches: 2
        )

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: cliOverrides,
            environment: ["AXION_MAX_STEPS": "50"]
        )

        #expect(config.maxSteps == 10)
        #expect(config.maxBatches == 2)
    }

    @Test("no file and no env vars returns defaults")
    func loadConfigNoFileNoEnvReturnsDefault() async throws {
        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil,
            environment: [:]
        )

        #expect(config.model == AxionConfig.default.model)
        #expect(config.maxSteps == AxionConfig.default.maxSteps)
        #expect(config.maxBatches == AxionConfig.default.maxBatches)
        #expect(config.maxReplanRetries == AxionConfig.default.maxReplanRetries)
        #expect(config.traceEnabled == AxionConfig.default.traceEnabled)
        #expect(config.sharedSeatMode == AxionConfig.default.sharedSeatMode)
        #expect(config.apiKey == nil)
    }

    @Test("invalid JSON file falls back to defaults")
    func loadConfigInvalidJsonFileFallsBackToDefault() async throws {
        try writeConfigJSON("}{not valid json")

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil,
            environment: [:]
        )

        #expect(config.maxSteps == AxionConfig.default.maxSteps)
    }

    @Test("AXION_API_KEY env overrides file")
    func loadConfigApiKeyEnvOverridesFile() async throws {
        let configJSON = """
        {
          "apiKey": "sk-ant-from-file"
        }
        """
        try writeConfigJSON(configJSON)

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil,
            environment: ["AXION_API_KEY": "sk-ant-from-env"]
        )

        #expect(config.apiKey == "sk-ant-from-env")
    }

    @Test("saveConfigFile includes apiKey")
    func saveConfigFileIncludesApiKey() async throws {
        var config = AxionConfig.default
        config.apiKey = "sk-ant-test-key"

        try ConfigManager.saveConfigFile(config, toDirectory: tempDir)

        let savedData = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let savedJSON = try JSONSerialization.jsonObject(with: savedData) as! [String: Any]

        #expect(savedJSON["apiKey"] as? String == "sk-ant-test-key")
        #expect(savedJSON["model"] != nil)
        #expect(savedJSON["maxSteps"] != nil)
    }

    @Test("saveConfigFile round-trips with apiKey")
    func saveConfigFileRoundTripWithApiKey() async throws {
        var config = AxionConfig.default
        config.apiKey = "sk-ant-secret"
        config.maxSteps = 42

        try ConfigManager.saveConfigFile(config, toDirectory: tempDir)

        let savedData = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: savedData)

        #expect(decoded.apiKey == "sk-ant-secret")
        #expect(decoded.maxSteps == 42)
    }

    @Test("ensureConfigDirectory creates directory")
    func ensureConfigDirectoryCreatesDirectory() throws {
        let newDir = tempDir + "/subdir/deep"
        try ConfigManager.ensureConfigDirectory(atPath: newDir)

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: newDir, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    @Test("full layer stack: defaults -> file -> env -> CLI")
    func loadConfigFullLayerStack() async throws {
        let configJSON = """
        {
          "model": "file-model",
          "maxSteps": 30,
          "maxBatches": 8,
          "traceEnabled": false
        }
        """
        try writeConfigJSON(configJSON)

        let cliOverrides = CLIOverrides(
            maxSteps: 10,
            maxBatches: nil
        )

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: cliOverrides,
            environment: [
                "AXION_MODEL": "env-model",
                "AXION_MAX_STEPS": "40",
            ]
        )

        #expect(config.maxSteps == 10)
        #expect(config.model == "env-model")
        #expect(config.maxBatches == 8)
        #expect(!config.traceEnabled)
        #expect(config.maxReplanRetries == AxionConfig.default.maxReplanRetries)
        #expect(config.sharedSeatMode == AxionConfig.default.sharedSeatMode)
    }
}
