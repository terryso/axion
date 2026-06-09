import ArgumentParser
import Foundation

import AxionCore

/// 检查结果状态
enum CheckStatus: Equatable {
    case ok
    case fail
}

/// 单项检查结果
struct CheckResult: Equatable {
    let name: String
    let status: CheckStatus
    let detail: String
    let fixHint: String?
}

/// Doctor 报告汇总
struct DoctorReport: Equatable {
    let results: [CheckResult]

    var allOk: Bool { results.allSatisfy { $0.status == .ok } }

    var failedCount: Int { results.filter { $0.status == .fail }.count }
}

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "检查系统环境和配置状态"
    )

    func run() throws {
        let io = TerminalDoctorIO()
        let _ = Self.runDoctor(io: io, configDirectory: nil)
    }

    /// 可测试的 doctor 入口 -- 注入 IO 和配置目录。
    /// - Parameter isServerRunningOverride: 注入的 server 运行检查（测试中传 `{ false }` 避免调用 Process()）。
    static func runDoctor(
        io: DoctorIO,
        configDirectory: String? = nil,
        isServerRunningOverride: (@Sendable () -> Bool)? = nil
    ) -> DoctorReport {
        let dir = configDirectory ?? ConfigManager.defaultConfigDirectory

        io.write("Axion Doctor — 环境检查")
        io.write("")

        var results: [CheckResult] = []

        // Check 1: 配置文件存在性和解析性
        let (configCheck, fileConfig) = checkConfigFile(in: dir)
        results.append(configCheck)

        // Apply env overrides (e.g., AXION_API_KEY) so doctor reflects actual runtime config
        var loadedConfig = fileConfig
        if loadedConfig != nil {
            ConfigManager.applyEnvOverrides(&loadedConfig!)
        }

        // Check 2: API Key 存在性（从加载的 config 中读取）
        let apiKeyCheck: CheckResult
        if configCheck.status == .ok {
            apiKeyCheck = checkApiKey(from: loadedConfig)
        } else {
            apiKeyCheck = CheckResult(
                name: "API Key",
                status: .fail,
                detail: "未配置",
                fixHint: "运行 axion setup 配置 API Key"
            )
        }
        results.append(apiKeyCheck)

        // Check 3: macOS 版本
        let macOSCheck = checkMacOSVersion()
        results.append(macOSCheck)

        // Check 4: Accessibility 权限
        let axCheck = checkAccessibility()
        results.append(axCheck)

        // Check 5: 屏幕录制权限
        let srCheck = checkScreenRecording()
        results.append(srCheck)

        // Check 6: Memory 状态
        let memoryDir = (dir as NSString).appendingPathComponent("memory")
        let memoryCheck = checkMemory(at: memoryDir)
        results.append(memoryCheck)

        // Check 7: Run lock status
        let lockCheck = checkRunLock(at: dir)
        results.append(lockCheck)

        // Check 8: Settings API accessibility (optional, only when server is running)
        let settingsApiCheck = checkSettingsAPI(isServerRunning: isServerRunningOverride)
        results.append(settingsApiCheck)

        // Check 9: Review & Curator config
        let reviewCheck = checkReviewConfig(from: loadedConfig)
        results.append(reviewCheck)

        // 输出所有检查结果
        for result in results {
            let mark = result.status == .ok ? "[OK]  " : "[FAIL] "
            io.write("  \(mark) \(result.name): \(result.detail)")
            if let hint = result.fixHint {
                io.write("  -> \(hint)")
            }
        }

        // 汇总
        let report = DoctorReport(results: results)
        io.write("")
        if report.allOk {
            io.write("All checks passed!")
        } else {
            io.write("\(report.failedCount) check(s) failed. 运行 axion setup 修复问题。")
        }

        return report
    }

    static func checkConfigFile(in directory: String) -> (result: CheckResult, config: AxionConfig?) {
        let path = ConfigManager.configFilePath(in: directory)
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            return (
                CheckResult(
                    name: "配置文件",
                    status: .fail,
                    detail: "不存在 (\(path))",
                    fixHint: "运行 axion setup 创建配置"
                ),
                nil
            )
        }
        guard let config = ConfigManager.loadRawConfig(from: directory) else {
            return (
                CheckResult(
                    name: "配置文件",
                    status: .fail,
                    detail: "格式损坏 (\(path))",
                    fixHint: "运行 axion setup 重新创建配置"
                ),
                nil
            )
        }
        return (
            CheckResult(
                name: "配置文件",
                status: .ok,
                detail: path,
                fixHint: nil
            ),
            config
        )
    }

    static func checkApiKey(from config: AxionConfig?) -> CheckResult {
        guard let config = config, let key = config.apiKey, !key.isEmpty else {
            return CheckResult(
                name: "API Key",
                status: .fail,
                detail: "未配置",
                fixHint: "运行 axion setup 配置 API Key"
            )
        }
        return CheckResult(
            name: "API Key",
            status: .ok,
            detail: ApiKeyStatusResponse.maskKey(key),
            fixHint: nil
        )
    }

    static func checkReviewConfig(from config: AxionConfig?) -> CheckResult {
        guard let config = config else {
            return CheckResult(
                name: "Review/Curator",
                status: .ok,
                detail: "未配置（使用默认值）",
                fixHint: nil
            )
        }

        let curatorEnabled = config.curatorEnabled ?? true
        let reviewModel = config.reviewModel ?? "继承 parent"
        let memoryInterval = config.reviewMemoryInterval ?? 4
        let skillInterval = config.reviewSkillInterval ?? 6

        var details: [String] = []
        details.append("review: 每 \(memoryInterval) 次消息")
        details.append("skill review: 每 \(skillInterval) 次")
        details.append("curator: \(curatorEnabled ? "启用" : "禁用")")
        details.append("模型: \(reviewModel)")

        return CheckResult(
            name: "Review/Curator",
            status: .ok,
            detail: details.joined(separator: ", "),
            fixHint: nil
        )
    }
}
