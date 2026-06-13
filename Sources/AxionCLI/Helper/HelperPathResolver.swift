import Foundation

/// HelperPathResolver -- 定位 AxionHelper.app 可执行文件路径。
///
/// 路径解析策略（优先级从高到低）：
/// 1. 环境变量 `AXION_HELPER_PATH`（CI/测试/自定义安装场景）
/// 2. 相对于可执行文件的路径：`executableDir/../libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper`
/// 3. 开发模式回退：检测 `.build` 目录，查找 `PROJECT_ROOT/.build/AxionHelper.app`
struct HelperPathResolver {
    /// 解析 AxionHelper 可执行文件的绝对路径。
    ///
    /// 三策略依次尝试，首个匹配即返回。所有策略均未命中时返回 `nil`。
    /// 不抛异常 -- 路径未找到由调用方决定如何处理。
    ///
    /// - Returns: AxionHelper 可执行文件的绝对路径，或 `nil`（未找到）。
    static func resolveHelperPath() -> String? {
        // 策略 1: 环境变量覆盖
        if let envPath = ProcessInfo.processInfo.environment["AXION_HELPER_PATH"],
           !envPath.isEmpty {
            return envPath
        }

        // 策略 2: 相对于可执行文件解析（Homebrew 安装布局）
        if let execPath = resolveExecutablePath() {
            let execDir = URL(fileURLWithPath: execPath).deletingLastPathComponent()
            let helperPath = execDir
                .deletingLastPathComponent()
                .appendingPathComponent("libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper")

            if FileManager.default.fileExists(atPath: helperPath.path) {
                return helperPath.path
            }

            if let projectRoot = findProjectRoot(from: URL(fileURLWithPath: execPath)),
               let helperPath = resolveDevelopmentBuildPath(projectRoot: projectRoot) {
                return helperPath
            }
        }

        // 策略 3: 开发/测试模式回退。swift test 的 Bundle.main 可执行路径在
        // 不同 SwiftPM/Xcode 版本下不稳定，当前工作目录通常更可靠。
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if let projectRoot = findProjectRoot(from: cwd),
           let helperPath = resolveDevelopmentBuildPath(projectRoot: projectRoot) {
            return helperPath
        }

        return nil
    }

    /// 获取当前可执行文件的绝对路径。
    /// Bundle.main.executableURL 对 SPM 裸二进制可能返回 nil，
    /// 回退到 /proc/self/exe (Linux) 或 _NSGetExecutablePath (macOS)。
    private static func resolveExecutablePath() -> String? {
        let rawPath: String?
        if let url = Bundle.main.executableURL {
            rawPath = url.path
        } else {
            // Fallback: _NSGetExecutablePath
            var size = UInt32(PATH_MAX)
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
            if _NSGetExecutablePath(&buffer, &size) == 0 {
                rawPath = String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8($0) }, as: UTF8.self)
            } else {
                rawPath = nil
            }
        }

        guard let path = rawPath, !path.isEmpty else { return nil }

        // Resolve symlinks (Homebrew installs bin/axion as symlink to Cellar)
        if let resolved = realpath(path, nil) {
            return String(cString: resolved)
        }
        return path
    }

    /// 从当前路径向上查找项目根目录（包含 `Package.swift` 的目录）。
    ///
    /// - Parameter url: 起始查找路径。
    /// - Returns: 项目根目录 URL，未找到时返回 `nil`。
    private static func findProjectRoot(from url: URL) -> URL? {
        var current = url
        // 从可执行文件路径向上遍历，最多 10 层
        for _ in 0..<10 {
            let packageSwift = current.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageSwift.path) {
                return current
            }
            // 如果已经是根目录，停止
            if current.path == "/" { break }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    private static func resolveDevelopmentBuildPath(projectRoot: URL) -> String? {
        let directCandidates = [
            ".build/debug/AxionHelper",
            ".build/release/AxionHelper",
            ".build/AxionHelper.app/Contents/MacOS/AxionHelper",
        ]

        for relativePath in directCandidates {
            let candidate = projectRoot.appendingPathComponent(relativePath)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.path
            }
        }

        let buildRoot = projectRoot.appendingPathComponent(".build")
        guard let triples = try? FileManager.default.contentsOfDirectory(
            at: buildRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for triple in triples.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? triple.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            for configuration in ["debug", "release"] {
                let candidate = triple
                    .appendingPathComponent(configuration, isDirectory: true)
                    .appendingPathComponent("AxionHelper")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate.path
                }
            }
        }

        return nil
    }
}
