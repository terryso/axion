import Foundation
import AxionCore

// MARK: - Models

struct DaemonStatus: Codable, Equatable {
    enum Status: String, Codable {
        case running
        case stopped
        case notInstalled
    }

    let status: Status
    let pid: Int?
    let port: Int?
    let host: String?
    let plistPath: String
    let label: String
}

// MARK: - Errors

enum DaemonError: Error, CustomStringConvertible {
    case plistWriteFailed(String)
    case launchctlFailed(String, Int32)
    case notInstalled
    case bootstrapFailed(String, Int32)

    var description: String {
        switch self {
        case .plistWriteFailed(let path):
            return "Failed to write plist to \(path)"
        case .launchctlFailed(let args, let code):
            return "launchctl \(args) failed with exit code \(code)"
        case .notInstalled:
            return "Daemon is not installed"
        case .bootstrapFailed(let domain, let code):
            return "launchctl bootstrap \(domain) failed with exit code \(code)"
        }
    }
}

// MARK: - DaemonService

final class DaemonService {
    static let defaultHost = "127.0.0.1"
    static let defaultPort = 4242

    let label: String
    let plistPath: String
    let logDir: String

    let subcommand: String
    let logFileName: String
    let errLogFileName: String
    let keepAliveCrashOnly: Bool
    let environmentVariables: [String: String]?
    let runLaunchctl: @Sendable ([String]) throws -> String
    let fileManager: FileManager
    let resolveBin: () -> String

    init(
        label: String = "dev.axion.server",
        subcommand: String = "server",
        logFileName: String = "server.log",
        errLogFileName: String = "server.err.log",
        keepAliveCrashOnly: Bool = false,
        environmentVariables: [String: String]? = nil,
        plistPath: String? = nil,
        runLaunchctl: @escaping @Sendable ([String]) throws -> String = DaemonService.defaultLaunchctl,
        fileManager: FileManager = .default,
        resolveBin: @escaping @Sendable () -> String = { DaemonService.resolveAxionBin() }
    ) {
        self.label = label
        self.subcommand = subcommand
        self.logFileName = logFileName
        self.errLogFileName = errLogFileName
        self.keepAliveCrashOnly = keepAliveCrashOnly
        self.environmentVariables = environmentVariables
        self.plistPath = plistPath
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents/\(label).plist")
        self.logDir = ConfigManager.defaultConfigDirectory
        self.runLaunchctl = runLaunchctl
        self.fileManager = fileManager
        self.resolveBin = resolveBin
    }

    // MARK: - Path Resolution

    static func resolveAxionBin() -> String {
        // 1. Environment variable override
        if let envBin = ProcessInfo.processInfo.environment["AXION_BIN"] {
            return NSString(string: envBin).standardizingPath
        }
        // 2. Current process path (resolve relative paths against cwd)
        let execPath = CommandLine.arguments[0]
        let resolved = NSString(string: execPath).standardizingPath
        if resolved.hasPrefix("/") { return resolved }
        let absolute = NSString(string: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(execPath)
        let absResolved = NSString(string: absolute).standardizingPath
        if absResolved.hasPrefix("/") { return absResolved }
        // 3. which axion
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["axion"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        if let data = try? pipe.fileHandleForReading.readToEnd(),
           let path = String(data: data, encoding: .utf8)?
           .trimmingCharacters(in: .whitespacesAndNewlines),
           path.hasPrefix("/")
        {
            return path
        }
        // 4. fallback
        return "axion"
    }

    // MARK: - Plist Generation (see DaemonService+PlistGeneration.swift)

    // MARK: - Install

    func install(host: String = defaultHost, port: Int = defaultPort, authKey: String? = nil) throws -> String {
        // Ensure ~/.axion/ directory exists
        try fileManager.createDirectory(
            atPath: logDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )

        // Ensure parent directory of plist exists (e.g. ~/Library/LaunchAgents/)
        let agentsDir = (plistPath as NSString).deletingLastPathComponent
        try fileManager.createDirectory(
            atPath: agentsDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Generate and write plist
        let plistContent = buildPlist(host: host, port: port, authKey: authKey)
        guard let data = plistContent.data(using: .utf8) else {
            throw DaemonError.plistWriteFailed(plistPath)
        }
        try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plistPath)

        // Bootstrap + kickstart
        let uid = getuid()
        let domain = "gui/\(uid)"

        do {
            _ = try runLaunchctl(["bootstrap", domain, plistPath])
        } catch {
            // Rollback: remove plist on bootstrap failure
            try? fileManager.removeItem(atPath: plistPath)
            throw error
        }

        do {
            _ = try runLaunchctl(["kickstart", "-k", "\(domain)/\(label)"])
        } catch {
            // Rollback: bootout + remove plist on kickstart failure
            _ = try? runLaunchctl(["bootout", domain, plistPath])
            try? fileManager.removeItem(atPath: plistPath)
            throw error
        }

        return plistPath
    }

    // MARK: - Uninstall

    func uninstall(keepLogs: Bool = false) throws {
        let uid = getuid()
        let domain = "gui/\(uid)"

        // Try bootout (ignore error if not running)
        _ = try? runLaunchctl(["bootout", domain, plistPath])

        // Remove plist
        if fileManager.fileExists(atPath: plistPath) {
            try fileManager.removeItem(atPath: plistPath)
        }

        // Optionally remove logs
        if !keepLogs {
            let logPath = (logDir as NSString).appendingPathComponent(logFileName)
            let errLogPath = (logDir as NSString).appendingPathComponent(errLogFileName)
            try? fileManager.removeItem(atPath: logPath)
            try? fileManager.removeItem(atPath: errLogPath)
        }
    }

    // MARK: - Status & Parsing (see DaemonService+Status.swift)

    // MARK: - Default launchctl runner

    private static func defaultLaunchctl(args: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        let errPipe = Pipe()
        task.standardError = errPipe
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if task.terminationStatus != 0 {
            throw DaemonError.launchctlFailed(args.joined(separator: " "), task.terminationStatus)
        }
        return output
    }
}
