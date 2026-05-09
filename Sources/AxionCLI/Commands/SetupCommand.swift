import ApplicationServices
import CoreGraphics
import Foundation

import ArgumentParser

import AxionCore

struct SetupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "首次配置 Axion"
    )

    func run() throws {
        let io = TerminalSetupIO()
        try Self.runSetup(io: io, configDirectory: nil)
    }

    /// 可测试的 setup 入口 — 注入 IO 和配置目录。
    static func runSetup(
        io: SetupIO,
        configDirectory: String? = nil
    ) throws {
        let dir = configDirectory ?? ConfigManager.defaultConfigDirectory
        let configFilePath = (dir as NSString).appendingPathComponent("config.json")

        io.write("🛠  Axion Setup")
        io.write("")

        // 加载已有配置
        var existingConfig: AxionConfig?
        if let fileData = FileManager.default.contents(atPath: configFilePath),
           let decoded = try? JSONDecoder().decode(AxionConfig.self, from: fileData) {
            existingConfig = decoded
        }

        // 步骤 1: 选择 Provider
        let currentProvider = existingConfig?.provider ?? .anthropic
        io.write("选择 LLM Provider:")
        io.write("  1) Anthropic (Claude)")
        io.write("  2) OpenAI Compatible")
        let providerInput = io.prompt("请选择 [1/2，默认 \(currentProvider == .anthropic ? "1" : "2")]: ").trimmingCharacters(in: .whitespacesAndNewlines)
        let provider: LLMProvider
        switch providerInput {
        case "2": provider = .openai
        default: provider = .anthropic
        }

        // 步骤 2: API Key
        var apiKey: String
        if let existing = existingConfig, let existingKey = existing.apiKey {
            io.write("检测到已有 API Key: \(maskApiKey(existingKey))")
            let shouldReplace = io.confirm("API Key 已存在，是否替换？", defaultAnswer: false)
            if shouldReplace {
                apiKey = promptForApiKey(io: io, provider: provider)
            } else {
                apiKey = existingKey
                io.write("保留已有 API Key。")
            }
        } else {
            apiKey = promptForApiKey(io: io, provider: provider)
        }

        // 步骤 3: Base URL（可选）
        let defaultBaseURLHint: String
        switch provider {
        case .anthropic: defaultBaseURLHint = "https://api.anthropic.com"
        case .openai: defaultBaseURLHint = "https://api.openai.com/v1"
        }
        io.write("")
        let baseURLInput = io.prompt("Base URL (留空使用 \(defaultBaseURLHint)): ").trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = baseURLInput.isEmpty ? (existingConfig?.baseURL ?? nil) : baseURLInput

        // 步骤 4: 保存配置
        var config = existingConfig ?? AxionConfig.default
        config.apiKey = apiKey
        config.provider = provider
        config.baseURL = baseURL

        try ConfigManager.ensureConfigDirectory(atPath: dir)
        try ConfigManager.saveConfigFile(config, toDirectory: dir)

        io.write("")
        io.write("配置已保存:")
        io.write("  Provider: \(provider.rawValue)")
        io.write("  API Key:  \(maskApiKey(apiKey))")
        if let baseURL {
            io.write("  Base URL: \(baseURL)")
        }
        io.write("  配置文件: \(configFilePath)")

        // 步骤 5: 检查 Accessibility 权限
        io.write("")
        io.write("检查权限...")
        let axStatus = PermissionChecker.checkAccessibility()
        switch axStatus {
        case .granted:
            io.write("  [OK] Accessibility: 已授权")
        case .notGranted:
            io.write("  [FAIL] Accessibility: 未授权")
            io.write("  -> 打开 系统设置 > 隐私与安全 > 辅助功能，添加 AxionHelper.app")
        case .unknown:
            io.write("  [??] Accessibility: 未知状态")
        }

        // 步骤 6: 检查屏幕录制权限
        let srStatus = PermissionChecker.checkScreenRecording()
        switch srStatus {
        case .granted:
            io.write("  [OK] 屏幕录制: 已授权")
        case .notGranted:
            io.write("  [FAIL] 屏幕录制: 未授权")
            io.write("  -> 打开 系统设置 > 隐私与安全 > 屏幕录制，添加 AxionHelper.app")
        case .unknown:
            io.write("  [??] 屏幕录制: 未知状态")
        }

        // 步骤 7: 完成提示
        io.write("")
        io.write("Setup complete! 运行 axion doctor 检查环境")
    }

    // MARK: - Private Helpers

    private static func promptForApiKey(io: SetupIO, provider: LLMProvider) -> String {
        let label = provider == .anthropic ? "Anthropic" : "OpenAI Compatible"
        while true {
            let input = io.promptSecret("\(label) API Key: ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !input.isEmpty {
                return input
            }
            io.write("API Key 不能为空，请重新输入。")
        }
    }
}

/// API Key 掩码函数
/// key 长度 <= 9 时显示 ***，否则前6后3中间 ***
func maskApiKey(_ key: String) -> String {
    if key.isEmpty { return "" }
    if key.count <= 9 { return "***" }
    let prefix = String(key.prefix(6))
    let suffix = String(key.suffix(3))
    return "\(prefix)***...\(suffix)"
}
