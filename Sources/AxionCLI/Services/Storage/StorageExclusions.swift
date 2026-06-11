import Foundation

import AxionCore

/// 扫描排除规则（纯函数，无 I/O，便于单测）。
///
/// 决定给定路径是否纳入扫描，以及被排除时的原因。内置默认排除集来自
/// Epic「安全边界」与扫描范围表：系统根级目录（`/System`、`/Library`、`/bin`、
/// `/sbin`、`/usr`、`/private`）、`~/Library`（整目录清理禁止）、`.git`、隐藏条目
/// 与开发缓存目录（`node_modules`、`.build`、`DerivedData` 等）。额外的绝对路径排除
/// （用户配置 + 当前工作目录项目源码根）通过 `excludedRoots` 传入。
///
/// 判定为纯函数：不读取文件系统，不发起网络请求，相同输入恒定输出。
struct StorageExclusions: Sendable, Equatable {

    /// 系统根级目录前缀（绝对路径，命中其下即排除整棵子树）。
    static let systemRoots: [String] = ["/System", "/Library", "/bin", "/sbin", "/usr", "/private"]

    /// 开发缓存目录名（路径中任一匹配段即排除整棵子树）。
    static let developerCacheNames: Set<String> = [
        "node_modules", ".build", "DerivedData", ".swiftpm",
        "Pods", ".gradle", "__pycache__", ".venv"
    ]

    /// 用户额外排除根（绝对路径，已标准化）。命中其自身或其下即排除。
    let excludedRoots: [String]

    /// 是否纳入隐藏条目（以 `.` 开头的路径段）。默认 `false`（排除）。
    /// 此开关与扫描服务的 `includeHidden` 对齐：扫描服务构造时透传。
    let includeHidden: Bool

    /// 主目录（用于 `~/Library` 解析与 `~` 展开）。默认 `NSHomeDirectory()`，
    /// 测试可注入伪主目录以保证确定性。
    let homeDirectory: String

    /// 从 `AxionConfig.storage` 构造排除规则：内置集 + 用户 `excludedPaths`。
    init(
        excludedRoots: [String] = [],
        includeHidden: Bool = false,
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.excludedRoots = excludedRoots.map { StorageExclusions.standardize($0, home: homeDirectory) }
        self.includeHidden = includeHidden
        self.homeDirectory = homeDirectory
    }

    /// 从 `StorageConfig` + 运行期上下文构造（合并内置集与用户配置，叠加 cwd 项目根）。
    init(_ config: StorageConfig, includeHidden: Bool = false, cwd: String? = nil, homeDirectory: String = NSHomeDirectory()) {
        var roots = config.excludedPaths
        if let cwd, !cwd.isEmpty {
            roots.append(cwd)
        }
        self.init(excludedRoots: roots, includeHidden: includeHidden, homeDirectory: homeDirectory)
    }

    /// 判定路径是否纳入扫描（纯函数）。
    func evaluate(path rawPath: String) -> (included: Bool, reason: String?) {
        let path = StorageExclusions.standardize(rawPath, home: homeDirectory)
        let segments = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        // 1. 系统根级目录（恒定排除，安全边界）
        for root in Self.systemRoots {
            if path == root || path.hasPrefix(root + "/") {
                return (false, "system_directory")
            }
        }

        // 2. ~/Library 整目录清理禁止（恒定排除；39.3 support 扫描由其入口逐项确认，不走此默认集）
        let homeLibrary = homeLibraryPath()
        if !homeLibrary.isEmpty, path == homeLibrary || path.hasPrefix(homeLibrary + "/") {
            return (false, "user_library_protected")
        }

        // 3. 用户额外排除根（配置 + cwd 项目源码根）
        for root in excludedRoots {
            if path == root || path.hasPrefix(root + "/") {
                return (false, "excluded_by_config")
            }
        }

        // 4. 路径分段规则（恒定）：.git、开发缓存
        for seg in segments {
            if seg == ".git" {
                return (false, "git_directory")
            }
            if Self.developerCacheNames.contains(seg) {
                return (false, "developer_cache")
            }
        }

        // 5. 隐藏条目（受 includeHidden 开关控制）
        if !includeHidden {
            for seg in segments where seg.hasPrefix(".") {
                return (false, "hidden_entry")
            }
        }

        return (true, nil)
    }

    /// `URL` 重载：取 `.path` 后委托给字符串版本。
    func evaluate(url: URL) -> (included: Bool, reason: String?) {
        evaluate(path: url.path)
    }

    // MARK: - Helpers

    /// `~/Library` 标准化绝对路径。
    func homeLibraryPath() -> String {
        guard !homeDirectory.isEmpty else { return "" }
        return StorageExclusions.standardize(homeDirectory + "/Library", home: homeDirectory)
    }

    /// 标准化路径：展开 `~`、折叠 `..`/`.`、去除多余分隔符与结尾 `/`。
    /// **纯字符串操作**：不解析符号链接、不访问文件系统。
    static func standardize(_ path: String, home: String) -> String {
        let expanded: String
        if path == "~" {
            expanded = home
        } else if path.hasPrefix("~/") {
            expanded = home + String(path.dropFirst())  // 保留 "/…"
        } else {
            expanded = path
        }
        var result = URL(fileURLWithPath: expanded).standardizedFileURL.path
        if result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
