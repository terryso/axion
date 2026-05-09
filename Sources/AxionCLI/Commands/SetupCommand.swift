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

        // 步骤 1: 检查 API Key 是否已存在 → AC7
        var existingConfig: AxionConfig?
        if let fileData = FileManager.default.contents(atPath: configFilePath),
           let decoded = try? JSONDecoder().decode(AxionConfig.self, from: fileData),
           decoded.apiKey != nil {
            existingConfig = decoded
        }

        var apiKey: String

        if let existing = existingConfig, let existingKey = existing.apiKey {
            // AC7: API Key 已存在，提示用户保留或替换
            io.write("检测到已有 API Key: \(maskApiKey(existingKey))")
            let shouldReplace = io.confirm("API Key 已存在，是否替换？", defaultAnswer: false)
            if shouldReplace {
                apiKey = promptForApiKey(io: io)
            } else {
                apiKey = existingKey
                io.write("保留已有 API Key。")
            }
        } else {
            // AC1: 提示输入 API Key
            apiKey = promptForApiKey(io: io)
        }

        // 步骤 3: 保存配置 → AC2
        var config = existingConfig ?? AxionConfig.default
        config.apiKey = apiKey

        try ConfigManager.ensureConfigDirectory(atPath: dir)
        try ConfigManager.saveConfigFile(config, toDirectory: dir)

        io.write("")
        io.write("API Key 已保存: \(maskApiKey(apiKey))")
        io.write("配置文件: \(configFilePath)")

        // 步骤 4: 检查 Accessibility 权限 → AC3
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

        // 步骤 5: 检查屏幕录制权限 → AC4
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

        // 步骤 6: 完成提示 → AC5
        io.write("")
        io.write("Setup complete! 运行 axion doctor 检查环境")
    }

    // MARK: - Private Helpers

    /// 提示用户输入 API Key，处理空输入重新提示。
    private static func promptForApiKey(io: SetupIO) -> String {
        while true {
            let input = io.promptSecret("Anthropic API Key: ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !input.isEmpty {
                return input
            }
            io.write("API Key 不能为空，请重新输入。")
        }
    }
}

/// API Key 掩码函数 → AC6
/// 格式: sk-ant-***...xyz（显示前 6 字符和后 3 字符，中间用 *** 替代）
/// key 长度 <= 9 时显示 ***
func maskApiKey(_ key: String) -> String {
    if key.isEmpty { return "" }
    if key.count <= 9 { return "***" }
    let prefix = String(key.prefix(6))
    let suffix = String(key.suffix(3))
    return "\(prefix)***...\(suffix)"
}
