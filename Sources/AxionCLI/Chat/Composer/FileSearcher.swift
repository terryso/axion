import Foundation

/// 文件搜索结果 — 包含截断后的结果列表和截断前的总匹配数。
struct FileSearchResult: Equatable {
    /// 截断后的匹配路径列表（按路径长度升序）。
    let results: [String]
    /// 截断前的总匹配数（用于显示 "显示前 N 条，共 M 个匹配"）。
    let totalMatches: Int
}

/// 文件搜索 Protocol — 抽象文件搜索逻辑（测试注入 Mock）。AC1/AC6/AC7。
protocol FileSearching: Sendable {
    /// 同步搜索文件，返回搜索结果（含总匹配数）。
    /// - Parameters:
    ///   - query: 搜索关键词（空字符串返回空结果）
    ///   - directory: 搜索根目录
    ///   - maxResults: 最大返回数量（默认 20）
    /// - Returns: FileSearchResult（results 为截断后路径列表，totalMatches 为截断前总数）
    func search(query: String, in directory: String, maxResults: Int) -> FileSearchResult
}

/// 同步文件搜索器 — AC1/AC2/AC6/AC7。
///
/// 使用 `FileManager.enumerator` 递归扫描目录，大小写不敏感子串匹配，
/// 结果按路径长度升序排列。忽略 `.git/`、`.build/`、`node_modules/`、
/// `DerivedData/`、`.swiftpm/` 目录。超时 100ms 截断结果。
struct FileSearcher: FileSearching {

    /// 忽略的目录名集合（AC6）。
    static let ignoredDirectories: Set<String> = [
        ".git", ".build", "node_modules", "DerivedData", ".swiftpm"
    ]

    /// 搜索超时（秒）。AC6: 100ms。
    static let timeoutInterval: TimeInterval = 0.1

    // MARK: - FileSearching

    func search(query: String, in directory: String, maxResults: Int = 20) -> FileSearchResult {
        // AC2: 空查询返回空结果
        guard !query.isEmpty else {
            return FileSearchResult(results: [], totalMatches: 0)
        }

        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: directory)

        // 验证目录可访问
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directory, isDirectory: &isDir),
              isDir.boolValue else {
            return FileSearchResult(results: [], totalMatches: 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in false }  // AC7: 权限拒绝跳过
        ) else {
            return FileSearchResult(results: [], totalMatches: 0)
        }

        let lowerQuery = query.lowercased()
        let deadline = Date().addingTimeInterval(Self.timeoutInterval)
        var results: [String] = []

        for case let itemURL as URL in enumerator {
            // AC6: 超时截断
            if Date() > deadline { break }

            // 跳过忽略目录
            let dirName = itemURL.lastPathComponent
            if Self.ignoredDirectories.contains(dirName) {
                enumerator.skipDescendants()
                continue
            }

            // 只包含普通文件（跳过目录）— AC1: 搜索文件，不含目录
            guard let resourceValues = try? itemURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            // 获取相对路径
            let relativePath = String(itemURL.path.dropFirst(directory.count))
            // 去掉前导 /
            let cleanPath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath

            // 大小写不敏感子串匹配（AC6）
            if cleanPath.lowercased().contains(lowerQuery) {
                results.append(cleanPath)
            }
        }

        // AC2: 按路径长度升序排列
        results.sort { $0.count < $1.count }

        // AC2: 截断到 maxResults，保留总数
        let totalMatches = results.count
        if results.count > maxResults {
            results = Array(results.prefix(maxResults))
        }

        return FileSearchResult(results: results, totalMatches: totalMatches)
    }
}
