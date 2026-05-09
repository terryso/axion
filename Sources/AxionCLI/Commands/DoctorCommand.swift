import ArgumentParser
import Foundation

import AxionCore

// MARK: - Check Models

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

// MARK: - DoctorCommand

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
    static func runDoctor(
        io: DoctorIO,
        configDirectory: String? = nil
    ) -> DoctorReport {
        let dir = configDirectory ?? ConfigManager.defaultConfigDirectory
        let configFilePath = (dir as NSString).appendingPathComponent("config.json")

        io.write("Axion Doctor — 环境检查")
        io.write("")

        var results: [CheckResult] = []

        // Check 1: 配置文件存在性和解析性
        let (configCheck, loadedConfig) = checkConfigFile(at: configFilePath)
        results.append(configCheck)

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

    // MARK: - Private Check Methods

    private static func checkConfigFile(at path: String) -> (result: CheckResult, config: AxionConfig?) {
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
        guard let data = fm.contents(atPath: path),
              let config = try? JSONDecoder().decode(AxionConfig.self, from: data) else {
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

    private static func checkApiKey(from config: AxionConfig?) -> CheckResult {
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
            detail: maskApiKey(key),
            fixHint: nil
        )
    }

    private static func checkMacOSVersion() -> CheckResult {
        let version = SystemChecker.macOSVersion()
        let supported = SystemChecker.isMacOSVersionSupported()
        return CheckResult(
            name: "macOS 版本",
            status: supported ? .ok : .fail,
            detail: version,
            fixHint: supported ? nil : "Axion 需要 macOS 14 (Sonoma) 或更高版本"
        )
    }

    private static func checkAccessibility() -> CheckResult {
        let status = PermissionChecker.checkAccessibility()
        switch status {
        case .granted:
            return CheckResult(
                name: "Accessibility",
                status: .ok,
                detail: "已授权",
                fixHint: nil
            )
        case .notGranted:
            return CheckResult(
                name: "Accessibility",
                status: .fail,
                detail: "未授权",
                fixHint: "打开 系统设置 > 隐私与安全 > 辅助功能，添加 AxionHelper.app"
            )
        case .unknown:
            return CheckResult(
                name: "Accessibility",
                status: .fail,
                detail: "未知状态",
                fixHint: "打开 系统设置 > 隐私与安全 > 辅助功能，添加 AxionHelper.app"
            )
        }
    }

    private static func checkScreenRecording() -> CheckResult {
        let status = PermissionChecker.checkScreenRecording()
        switch status {
        case .granted:
            return CheckResult(
                name: "屏幕录制",
                status: .ok,
                detail: "已授权",
                fixHint: nil
            )
        case .notGranted:
            return CheckResult(
                name: "屏幕录制",
                status: .fail,
                detail: "未授权",
                fixHint: "打开 系统设置 > 隐私与安全 > 屏幕录制，添加 AxionHelper.app"
            )
        case .unknown:
            return CheckResult(
                name: "屏幕录制",
                status: .fail,
                detail: "未知状态",
                fixHint: "打开 系统设置 > 隐私与安全 > 屏幕录制，添加 AxionHelper.app"
            )
        }
    }
}
