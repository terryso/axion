import Foundation

/// SystemChecker -- 系统环境检查服务。
struct SystemChecker {

    /// 获取当前 macOS 版本字符串（major.minor.patch）。
    static func macOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// 检查 macOS 版本是否 >= 14.0（Sonoma）。
    static func isMacOSVersionSupported() -> Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion >= 14
    }
}
