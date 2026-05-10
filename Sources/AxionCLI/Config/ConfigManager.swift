import Foundation

import AxionCore

/// CLI 参数覆盖值（从 RunCommand 映射）
struct CLIOverrides: Sendable {
    var maxSteps: Int?
    var maxBatches: Int?
}

/// ConfigManager — 分层配置加载器
/// 加载优先级（后者覆盖前者）：
/// 1. AxionConfig.default（默认值）
/// 2. config.json（文件覆盖默认值）
/// 3. 环境变量 AXION_*（覆盖 config.json）
/// 4. CLI 参数（最高优先级）
enum ConfigManager {

    // MARK: - Public API

    /// 分层加载配置。
    /// - Parameters:
    ///   - configDirectory: 配置文件所在目录。为 nil 时使用默认 `~/.axion/`。
    ///   - cliOverrides: 从 RunCommand 解析的 CLI 参数覆盖值。
    /// - Returns: 合并后的完整配置（含 API Key）。
    static func loadConfig(
        configDirectory: String? = nil,
        cliOverrides: CLIOverrides? = nil
    ) async throws -> AxionConfig {
        // 第 1-2 层：config.json（部分 JSON 由 AxionConfig.init(from:) 处理默认值回退）
        let dir = configDirectory ?? defaultConfigDirectory
        let filePath = (dir as NSString).appendingPathComponent("config.json")

        var config: AxionConfig
        if let fileData = FileManager.default.contents(atPath: filePath),
           let fileConfig = try? JSONDecoder().decode(AxionConfig.self, from: fileData) {
            config = fileConfig
        } else {
            config = AxionConfig.default
        }

        // 第 3 层：环境变量
        applyEnvOverrides(&config)

        // 第 4 层：CLI 参数
        if let cli = cliOverrides {
            applyCLIOverrides(&config, from: cli)
        }

        return config
    }

    /// 将配置保存到指定目录的 config.json 文件中。
    static func saveConfigFile(_ config: AxionConfig, toDirectory directory: String) throws {
        let filePath = (directory as NSString).appendingPathComponent("config.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(config)

        // 文件权限 0o600（仅用户可读写）
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        FileManager.default.createFile(
            atPath: filePath,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        )
    }

    /// 确保配置目录存在（含中间目录）。
    static func ensureConfigDirectory(atPath path: String) throws {
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
    }

    // MARK: - Private

    static var defaultConfigDirectory: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".axion")
    }

    /// 应用环境变量覆盖。
    static func applyEnvOverrides(_ config: inout AxionConfig) {
        let env = ProcessInfo.processInfo.environment

        if let v = env["AXION_API_KEY"], !v.isEmpty {
            config.apiKey = v
        }
        if let v = env["AXION_MODEL"], !v.isEmpty {
            config.model = v
        }
        if let v = env["AXION_MAX_STEPS"], let i = Int(v) {
            config.maxSteps = i
        }
        if let v = env["AXION_MAX_BATCHES"], let i = Int(v) {
            config.maxBatches = i
        }
        if let v = env["AXION_MAX_REPLAN_RETRIES"], let i = Int(v) {
            config.maxReplanRetries = i
        }
        if let v = env["AXION_TRACE_ENABLED"] {
            config.traceEnabled = (v.lowercased() == "true")
        }
        if let v = env["AXION_SHARED_SEAT_MODE"] {
            config.sharedSeatMode = (v.lowercased() == "true")
        }
    }

    /// 应用 CLI 参数覆盖。
    private static func applyCLIOverrides(_ config: inout AxionConfig, from cli: CLIOverrides) {
        if let v = cli.maxSteps { config.maxSteps = v }
        if let v = cli.maxBatches { config.maxBatches = v }
    }
}
