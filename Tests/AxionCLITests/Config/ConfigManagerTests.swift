import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

/// Serializes env var access to prevent parallel test races.
actor EnvGate {
    static let shared = EnvGate()

    func withSavedEnv(_ keys: [String], body: @Sendable () async throws -> Void) async throws {
        let saved = keys.reduce(into: [String: String?]()) { result, key in
            result[key] = ProcessInfo.processInfo.environment[key]
        }
        for key in keys { unsetenv(key) }
        defer {
            for (key, value) in saved {
                if let value { setenv(key, value, 1) } else { unsetenv(key) }
            }
        }
        try await body()
    }
}

@Suite("ConfigManager")
struct ConfigManagerTests: ~Copyable {

    private var tempDir: String!
    private var configFilePath: String!

    private let envKeys = [
        "AXION_API_KEY", "AXION_MODEL", "AXION_MAX_STEPS", "AXION_MAX_BATCHES",
        "AXION_MAX_REPLAN_RETRIES", "AXION_TRACE_ENABLED", "AXION_SHARED_SEAT_MODE"
    ]

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

    private func withCleanEnv(_ body: @Sendable () async throws -> Void) async throws {
        try await EnvGate.shared.withSavedEnv(envKeys, body: body)
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
        try await withCleanEnv {
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

            #expect(config.apiKey == "sk-ant-test-key-12345678")
            #expect(config.maxSteps == 30)
        }
    }

    @Test("config.json overrides default values")
    func loadConfigFileOverridesDefault() async throws {
        try await withCleanEnv {
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

            #expect(config.maxSteps == 30)
            #expect(config.model == AxionConfig.default.model)
            #expect(config.maxBatches == AxionConfig.default.maxBatches)
        }
    }

    @Test("environment variable AXION_MODEL overrides config.json")
    func loadConfigEnvOverridesFile() async throws {
        try await withCleanEnv {
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

            #expect(config.model == "claude-opus-4")
        }
    }

    @Test("environment variable AXION_MAX_STEPS overrides config.json")
    func loadConfigEnvMaxStepsOverridesFile() async throws {
        try await withCleanEnv {
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

            #expect(config.maxSteps == 50)
        }
    }

    @Test("AXION_TRACE_ENABLED=false parsed correctly")
    func loadConfigEnvBoolTraceEnabled() async throws {
        try await withCleanEnv {
            setenv("AXION_TRACE_ENABLED", "false", 1)

            let config = try await ConfigManager.loadConfig(
                configDirectory: tempDir,
                cliOverrides: nil
            )

            #expect(!config.traceEnabled)
        }
    }

    @Test("CLI arguments override environment variables")
    func loadConfigCLIOverridesEnv() async throws {
        try await withCleanEnv {
            setenv("AXION_MAX_STEPS", "50", 1)

            let cliOverrides = CLIOverrides(
                maxSteps: 10,
                maxBatches: nil
            )

            let config = try await ConfigManager.loadConfig(
                configDirectory: tempDir,
                cliOverrides: cliOverrides
            )

            #expect(config.maxSteps == 10)
        }
    }

    @Test("CLI arguments override all layers")
    func loadConfigCLIOverridesAllLayers() async throws {
        try await withCleanEnv {
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

            #expect(config.maxSteps == 10)
            #expect(config.maxBatches == 2)
        }
    }

    @Test("no file and no env vars returns defaults")
    func loadConfigNoFileNoEnvReturnsDefault() async throws {
        try await withCleanEnv {
            let config = try await ConfigManager.loadConfig(
                configDirectory: tempDir,
                cliOverrides: nil
            )

            #expect(config.model == AxionConfig.default.model)
            #expect(config.maxSteps == AxionConfig.default.maxSteps)
            #expect(config.maxBatches == AxionConfig.default.maxBatches)
            #expect(config.maxReplanRetries == AxionConfig.default.maxReplanRetries)
            #expect(config.traceEnabled == AxionConfig.default.traceEnabled)
            #expect(config.sharedSeatMode == AxionConfig.default.sharedSeatMode)
            #expect(config.apiKey == nil)
        }
    }

    @Test("invalid JSON file falls back to defaults")
    func loadConfigInvalidJsonFileFallsBackToDefault() async throws {
        try await withCleanEnv {
            try writeConfigJSON("}{not valid json")

            let config = try await ConfigManager.loadConfig(
                configDirectory: tempDir,
                cliOverrides: nil
            )

            #expect(config.maxSteps == AxionConfig.default.maxSteps)
        }
    }

    @Test("AXION_API_KEY env overrides file")
    func loadConfigApiKeyEnvOverridesFile() async throws {
        try await withCleanEnv {
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

            #expect(config.apiKey == "sk-ant-from-env")
        }
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
        try await withCleanEnv {
            let configJSON = """
            {
              "model": "file-model",
              "maxSteps": 30,
              "maxBatches": 8,
              "traceEnabled": false
            }
            """
            try writeConfigJSON(configJSON)

            setenv("AXION_MODEL", "env-model", 1)
            setenv("AXION_MAX_STEPS", "40", 1)

            let cliOverrides = CLIOverrides(
                maxSteps: 10,
                maxBatches: nil
            )

            let config = try await ConfigManager.loadConfig(
                configDirectory: tempDir,
                cliOverrides: cliOverrides
            )

            #expect(config.maxSteps == 10)
            #expect(config.model == "env-model")
            #expect(config.maxBatches == 8)
            #expect(!config.traceEnabled)
            #expect(config.maxReplanRetries == AxionConfig.default.maxReplanRetries)
            #expect(config.sharedSeatMode == AxionConfig.default.sharedSeatMode)
        }
    }
}
