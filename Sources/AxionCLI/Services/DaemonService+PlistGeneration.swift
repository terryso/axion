import Foundation

// MARK: - Plist Generation

extension DaemonService {

    func buildPlist(host: String = defaultHost, port: Int = defaultPort, authKey: String? = nil) -> String {
        let binPath = resolveBin()
        let logPath = (logDir as NSString).appendingPathComponent(logFileName)
        let errLogPath = (logDir as NSString).appendingPathComponent(errLogFileName)

        let subcommandParts = subcommand.split(separator: " ").map(String.init)

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>\(Self.escapeXML(label))</string>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>\(Self.escapeXML(binPath))</string>
        """

        for part in subcommandParts {
            xml += "\n\t\t<string>\(Self.escapeXML(part))</string>"
        }

        xml += """
        \n\t\t<string>--host</string>
        \t\t<string>\(Self.escapeXML(host))</string>
        \t\t<string>--port</string>
        \t\t<string>\(Self.escapeXML(String(port)))</string>
        \t</array>
        """

        var envDict: [(String, String)] = []
        if let authKey {
            envDict.append(("AXION_AUTH_KEY", authKey))
        }
        if let environmentVariables {
            for (key, value) in environmentVariables.sorted(by: { $0.key < $1.key }) {
                envDict.append((key, value))
            }
        }

        if !envDict.isEmpty {
            xml += "\n\t<key>EnvironmentVariables</key>\n\t<dict>\n"
            for (key, value) in envDict {
                xml += "\t\t<key>\(Self.escapeXML(key))</key>\n\t\t<string>\(Self.escapeXML(value))</string>\n"
            }
            xml += "\t</dict>\n"
        }

        xml += """
        \t<key>RunAtLoad</key>
        \t<true/>
        \t<key>KeepAlive</key>
        """

        if keepAliveCrashOnly {
            xml += """
            \n\t<dict>
            \t\t<key>Crashed</key>
            \t\t<true/>
            \t</dict>
            """
        } else {
            xml += "\n\t<true/>\n"
        }

        xml += """
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

    static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
