import Foundation

// MARK: - Status & Parsing Helpers

extension DaemonService {

    func status() -> DaemonStatus {
        // Check plist exists
        guard fileManager.fileExists(atPath: plistPath) else {
            return DaemonStatus(
                status: .notInstalled,
                pid: nil,
                port: nil,
                host: nil,
                plistPath: plistPath,
                label: label
            )
        }

        let uid = getuid()
        let domain = "gui/\(uid)"
        let servicePath = "\(domain)/\(label)"

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
                label: label
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
            label: label
        )
    }

    func parsePID(from output: String) -> Int? {
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

    func parseHostPortFromPlist() -> (host: String?, port: Int?) {
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
}
