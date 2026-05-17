import Foundation

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
    static let daemonLabel = "dev.axion.server"
    static let defaultHost = "127.0.0.1"
    static let defaultPort = 4242

    let plistPath: String
    let logDir: String

    private let runLaunchctl: @Sendable ([String]) throws -> String
    private let fileManager: FileManager

    init(
        plistPath: String? = nil,
        runLaunchctl: @escaping @Sendable ([String]) throws -> String = DaemonService.defaultLaunchctl,
        fileManager: FileManager = .default
    ) {
        let home = NSHomeDirectory()
        self.plistPath = plistPath
            ?? (home as NSString).appendingPathComponent("Library/LaunchAgents/dev.axion.server.plist")
        self.logDir = (home as NSString).appendingPathComponent(".axion")
        self.runLaunchctl = runLaunchctl
        self.fileManager = fileManager
    }

    // MARK: - Path Resolution

    static func resolvePlistPath() -> String {
        let home = NSHomeDirectory()
        return (home as NSString).appendingPathComponent("Library/LaunchAgents/dev.axion.server.plist")
    }

    static func resolveLogPath() -> String {
        let home = NSHomeDirectory()
        return (home as NSString).appendingPathComponent(".axion/server.log")
    }

    static func resolveErrorLogPath() -> String {
        let home = NSHomeDirectory()
        return (home as NSString).appendingPathComponent(".axion/server.err.log")
    }

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

    // MARK: - Plist Generation

    func buildPlist(host: String = defaultHost, port: Int = defaultPort, authKey: String? = nil) -> String {
        let binPath = Self.resolveAxionBin()
        let logPath = (logDir as NSString).appendingPathComponent("server.log")
        let errLogPath = (logDir as NSString).appendingPathComponent("server.err.log")

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>\(Self.escapeXML(Self.daemonLabel))</string>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>\(Self.escapeXML(binPath))</string>
        \t\t<string>server</string>
        \t\t<string>--host</string>
        \t\t<string>\(Self.escapeXML(host))</string>
        \t\t<string>--port</string>
        \t\t<string>\(Self.escapeXML(String(port)))</string>
        \t</array>
        """

        if let authKey {
            xml += """
            \n\t<key>EnvironmentVariables</key>
            \t<dict>
            \t\t<key>AXION_AUTH_KEY</key>
            \t\t<string>\(Self.escapeXML(authKey))</string>
            \t</dict>
            """
        }

        xml += """
        \n\t<key>RunAtLoad</key>
        \t<true/>
        \t<key>KeepAlive</key>
        \t<true/>
        \t<key>ThrottleInterval</key>
        \t<integer>10</integer>
        \t<key>StandardOutPath</key>
        \t<string>\(Self.escapeXML(logPath))</string>
        \t<key>StandardErrorPath</key>
        \t<string>\(Self.escapeXML(errLogPath))</string>
        </dict>
        </plist>
        """

        return xml
    }

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
            _ = try runLaunchctl(["kickstart", "-k", "\(domain)/\(Self.daemonLabel)"])
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
            let logPath = (logDir as NSString).appendingPathComponent("server.log")
            let errLogPath = (logDir as NSString).appendingPathComponent("server.err.log")
            try? fileManager.removeItem(atPath: logPath)
            try? fileManager.removeItem(atPath: errLogPath)
        }
    }

    // MARK: - Status

    func status() -> DaemonStatus {
        // Check plist exists
        guard fileManager.fileExists(atPath: plistPath) else {
            return DaemonStatus(
                status: .notInstalled,
                pid: nil,
                port: nil,
                host: nil,
                plistPath: plistPath,
                label: Self.daemonLabel
            )
        }

        let uid = getuid()
        let domain = "gui/\(uid)"
        let servicePath = "\(domain)/\(Self.daemonLabel)"

        // Query launchctl for status
        let output: String
        do {
            output = try runLaunchctl(["print", servicePath])
        } catch {
            return DaemonStatus(
                status: .stopped,
                pid: nil,
                port: nil,
                host: nil,
                plistPath: plistPath,
                label: Self.daemonLabel
            )
        }

        // Parse PID from output
        let pid = parsePID(from: output)

        // Parse host/port from plist
        let (host, port) = parseHostPortFromPlist()

        return DaemonStatus(
            status: pid != nil ? .running : .stopped,
            pid: pid,
            port: port,
            host: host,
            plistPath: plistPath,
            label: Self.daemonLabel
        )
    }

    // MARK: - Helpers

    private func parsePID(from output: String) -> Int? {
        // launchctl print output contains "pid = <number>"
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("pid = ") {
                let value = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
                return Int(value)
            }
        }
        return nil
    }

    private func parseHostPortFromPlist() -> (host: String?, port: Int?) {
        guard let data = fileManager.contents(atPath: plistPath),
              let content = String(data: data, encoding: .utf8) else {
            return (nil, nil)
        }

        var host: String?
        var port: Int?

        // Simple XML parsing for host/port from ProgramArguments
        let lines = content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "<string>--host</string>", index + 1 < lines.count {
                let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if nextLine.hasPrefix("<string>") && nextLine.hasSuffix("</string>") {
                    host = String(nextLine.dropFirst(8).dropLast(9))
                }
            }
            if trimmed == "<string>--port</string>", index + 1 < lines.count {
                let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if nextLine.hasPrefix("<string>") && nextLine.hasSuffix("</string>") {
                    port = Int(nextLine.dropFirst(8).dropLast(9))
                }
            }
        }

        return (host, port)
    }

    static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

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
