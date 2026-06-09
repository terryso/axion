import Foundation

// MARK: - Permission & System Diagnostic Checks

extension DoctorCommand {

    // MARK: - Permission Checks

    static func checkAccessibility() -> CheckResult {
        checkPermission(
            name: "Accessibility",
            status: PermissionChecker.checkAccessibility(),
            settingsPath: "辅助功能"
        )
    }

    static func checkScreenRecording() -> CheckResult {
        checkPermission(
            name: "屏幕录制",
            status: PermissionChecker.checkScreenRecording(),
            settingsPath: "屏幕录制"
        )
    }

    /// Shared helper for permission status → CheckResult mapping.
    private static func checkPermission(
        name: String,
        status: PermissionStatus,
        settingsPath: String
    ) -> CheckResult {
        let fixHint = "打开 系统设置 > 隐私与安全 > \(settingsPath)，添加 AxionHelper.app"
        switch status {
        case .granted:
            return CheckResult(name: name, status: .ok, detail: "已授权", fixHint: nil)
        case .notGranted:
            return CheckResult(name: name, status: .fail, detail: "未授权", fixHint: fixHint)
        case .unknown:
            return CheckResult(name: name, status: .fail, detail: "未知状态", fixHint: fixHint)
        }
    }

    static func checkMacOSVersion() -> CheckResult {
        let version = SystemChecker.macOSVersion()
        let supported = SystemChecker.isMacOSVersionSupported()
        return CheckResult(
            name: "macOS 版本",
            status: supported ? .ok : .fail,
            detail: version,
            fixHint: supported ? nil : "Axion 需要 macOS 14 (Sonoma) 或更高版本"
        )
    }

    static func checkRunLock(at axionDir: String) -> CheckResult {
        let lockPath = (axionDir as NSString).appendingPathComponent("run.lock")
        let fm = FileManager.default

        guard fm.fileExists(atPath: lockPath) else {
            return CheckResult(
                name: "Run Lock",
                status: .ok,
                detail: "No run lock",
                fixHint: nil
            )
        }

        guard let data = fm.contents(atPath: lockPath),
              let lock = try? JSONDecoder().decode(RunLockData.self, from: data) else {
            return CheckResult(
                name: "Run Lock",
                status: .fail,
                detail: "Stale run.lock（文件格式损坏）",
                fixHint: "删除 ~/.axion/run.lock: rm ~/.axion/run.lock"
            )
        }

        // Check if the process holding the lock is still alive
        let isAlive = Darwin.kill(lock.pid, 0) == 0
        if isAlive {
            return CheckResult(
                name: "Run Lock",
                status: .ok,
                detail: "Active run.lock (run_id: \(lock.runId), pid: \(lock.pid))",
                fixHint: nil
            )
        } else {
            return CheckResult(
                name: "Run Lock",
                status: .fail,
                detail: "Stale run.lock (进程已退出, run_id: \(lock.runId), pid: \(lock.pid))",
                fixHint: "删除 stale lock: rm ~/.axion/run.lock"
            )
        }
    }

    // Intentionally reads raw files instead of using MemoryStoreProtocol —
    // doctor is a diagnostic tool that should work without initializing the SDK store.
    static func checkMemory(at memoryDir: String) -> CheckResult {
        let fm = FileManager.default

        guard fm.fileExists(atPath: memoryDir) else {
            return CheckResult(
                name: "Memory",
                status: .ok,
                detail: "未使用（首次运行后自动创建）",
                fixHint: nil
            )
        }

        // Count domain files and total entries
        var domainCount = 0
        var totalEntries = 0

        guard let files = try? fm.contentsOfDirectory(atPath: memoryDir) else {
            return CheckResult(
                name: "Memory",
                status: .ok,
                detail: "未使用（首次运行后自动创建）",
                fixHint: nil
            )
        }

        for file in files where file.hasSuffix(".json") {
            domainCount += 1
            let filePath = (memoryDir as NSString).appendingPathComponent(file)
            if let data = fm.contents(atPath: filePath),
               let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                totalEntries += jsonArray.count
            }
        }

        if domainCount == 0 {
            return CheckResult(
                name: "Memory",
                status: .ok,
                detail: "未使用（首次运行后自动创建）",
                fixHint: nil
            )
        }

        return CheckResult(
            name: "Memory",
            status: .ok,
            detail: "\(domainCount) domains, \(totalEntries) entries",
            fixHint: nil
        )
    }

    static func checkSettingsAPI(isServerRunning: (@Sendable () -> Bool)?) -> CheckResult {
        // Use injected check or default pgrep-based detection
        let serverRunning: Bool
        if let isServerRunning {
            serverRunning = isServerRunning()
        } else {
            let pipe = Pipe()
            let pgrep = Process()
            pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            pgrep.arguments = ["-f", "axion server"]
            pgrep.standardOutput = pipe
            do {
                try pgrep.run()
                pgrep.waitUntilExit()
                serverRunning = pgrep.terminationStatus == 0
            } catch {
                serverRunning = false
            }
        }

        guard serverRunning else {
            return CheckResult(
                name: "Settings API",
                status: .ok,
                detail: "跳过（server 未运行）",
                fixHint: nil
            )
        }

        // Try to connect to the Settings API
        let defaultPort = 4242
        guard let url = URL(string: "http://localhost:\(defaultPort)/v1/settings/api-key") else {
            return CheckResult(
                name: "Settings API",
                status: .ok,
                detail: "跳过（URL 构造失败）",
                fixHint: nil
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        let sem = DispatchSemaphore(value: 0)
        var checkResult: CheckResult?

        URLSession.shared.dataTask(with: request) { _, response, error in
            if error != nil {
                checkResult = CheckResult(
                    name: "Settings API",
                    status: .ok,
                    detail: "跳过（连接失败）",
                    fixHint: nil
                )
            } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                checkResult = CheckResult(
                    name: "Settings API",
                    status: .ok,
                    detail: "可达 (port \(defaultPort))",
                    fixHint: nil
                )
            } else {
                checkResult = CheckResult(
                    name: "Settings API",
                    status: .ok,
                    detail: "跳过（非预期响应）",
                    fixHint: nil
                )
            }
            sem.signal()
        }.resume()

        _ = sem.wait(timeout: .now() + 5)
        return checkResult ?? CheckResult(
            name: "Settings API",
            status: .ok,
            detail: "跳过（超时）",
            fixHint: nil
        )
    }
}
