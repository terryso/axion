import Foundation
import UniformTypeIdentifiers

import AxionCore

/// 文件系统扫描的默认实现。
///
/// 设计为无状态 `struct` + `async` 入口：每次 `scan(_:)` 从请求构造排除规则，
/// 不持有跨调用的 `ScanResult` 状态。仅读取元数据（不读文件正文，AC #8），
/// 不产生任何副作用（AC #6）。symlink 不跟随（AC #2）；bundle/library 折叠为单条目（AC #3）。
struct StorageScanService: StorageScanning {

    /// 主目录（用于 `~/Downloads` 派生）。默认 `NSHomeDirectory()`，测试可注入。
    let homeDirectory: String

    /// 已知媒体库 / bundle 后缀（即使未被标记为 package 也折叠为单条目）。
    static let libraryExtensions: Set<String> = [
        "photoslibrary", "musiclibrary", "tvlibrary", "aperturelibrary", "maildownload"
    ]

    init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }

    func scan(_ request: ScanRequest) async throws -> ScanResult {
        scanSync(request)
    }

    /// 同步执行枚举（`FileManager` 的同步迭代器不可在 async 上下文使用，故抽出）。
    private func scanSync(_ request: ScanRequest) -> ScanResult {
        let fm = FileManager.default
        let exclusions = StorageExclusions(
            excludedRoots: request.excludedPaths,
            includeHidden: request.includeHidden,
            homeDirectory: homeDirectory
        )
        let downloadsPath = StorageExclusions.standardize("~/Downloads", home: homeDirectory)
        let isoFmt = ISO8601DateFormatter()

        // 受限 URLResourceKey 集合：一次性批量取值，避免逐文件 attributesOfItem。
        let keys: [URLResourceKey] = [
            .fileSizeKey,
            .totalFileSizeKey,
            .isDirectoryKey,
            .isPackageKey,
            .isHiddenKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .creationDateKey,
        ]
        let keySet = Set(keys)

        var signals: [FileSignal] = []
        var skippedCount = 0
        var excludedNotes: [String] = []

        for root in request.roots {
            let rootPath = root.standardizedFileURL.path
            guard fm.fileExists(atPath: rootPath) else {
                excludedNotes.append("scan_root_missing: \(rootPath)")
                continue
            }

            // .skipsPackageDescendants：bundle/package 折叠为单条目（AC #3）。
            // .skipsHiddenFiles：与 includeHidden=false 对齐（受开关控制）。
            var opts: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
            if !request.includeHidden { opts.insert(.skipsHiddenFiles) }

            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: opts
            ) else {
                continue
            }

            // 手动剪枝被排除子树（深度优先序保证 prefix 匹配有效）。
            var skipPrefix: String? = nil
            for case let url as URL in enumerator {
                let path = url.standardizedFileURL.path

                if let prefix = skipPrefix {
                    if path == prefix || path.hasPrefix(prefix + "/") {
                        skippedCount += 1
                        continue
                    } else {
                        skipPrefix = nil
                    }
                }

                let (included, _) = exclusions.evaluate(url: url)
                if !included {
                    skippedCount += 1
                    if let rv = try? url.resourceValues(forKeys: [.isDirectoryKey]), rv.isDirectory == true {
                        skipPrefix = path
                    }
                    continue
                }

                guard let signal = makeSignal(
                    url: url,
                    keySet: keySet,
                    downloadsPath: downloadsPath,
                    isoFmt: isoFmt
                ) else {
                    skippedCount += 1
                    continue
                }
                signals.append(signal)
            }
        }

        // 大文件：sizeBytes >= minSizeBytes，降序（AC #2）。
        let largeFiles: [FileSignal]
        if let threshold = request.minSizeBytes {
            largeFiles = signals
                .filter { $0.sizeBytes >= threshold }
                .sorted { $0.sizeBytes > $1.sizeBytes }
        } else {
            largeFiles = []
        }

        let groups = makeGroups(from: signals, maxFilesPerGroup: request.maxFilesPerGroup)

        return ScanResult(
            groups: groups,
            largeFiles: largeFiles,
            skippedCount: skippedCount,
            excludedNotes: excludedNotes
        )
    }

    // MARK: - Signal Extraction

    private func makeSignal(
        url: URL,
        keySet: Set<URLResourceKey>,
        downloadsPath: String,
        isoFmt: ISO8601DateFormatter
    ) -> FileSignal? {
        let rv: URLResourceValues
        do { rv = try url.resourceValues(forKeys: keySet) }
        catch { return nil }

        let isDirectory = rv.isDirectory ?? false
        let isPackage = rv.isPackage ?? false
        let isSymbolicLink = rv.isSymbolicLink ?? false
        let isHidden = rv.isHidden ?? false
        let typeIdentifier = (try? url.resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier
        let ext = url.pathExtension.lowercased()

        // bundle / library 折叠判定（AC #3）。
        let isLibraryExt = !ext.isEmpty && Self.libraryExtensions.contains(ext)
        let isBundle = isPackage || isLibraryExt || Self.conformsToBundle(typeIdentifier: typeIdentifier)

        // 体积：symlink 取链接自身；目录/package 取递归总量；普通文件取 fileSize。
        let sizeBytes: Int64
        if isSymbolicLink {
            sizeBytes = Int64(rv.fileSize ?? 0)
        } else if isDirectory {
            sizeBytes = Int64(rv.totalFileSize ?? rv.fileSize ?? 0)
        } else {
            sizeBytes = Int64(rv.fileSize ?? 0)
        }

        let modifiedAt = rv.contentModificationDate.map { isoFmt.string(from: $0) }
        let createdAt = rv.creationDate.map { isoFmt.string(from: $0) }

        let standardizedPath = url.standardizedFileURL.path
        let isFromDownloads = !downloadsPath.isEmpty
            && (standardizedPath == downloadsPath || standardizedPath.hasPrefix(downloadsPath + "/"))

        // 底层信号分类（非最终业务分类）。
        let kind = FileKind.derive(
            fileExtension: ext.isEmpty ? nil : ext,
            typeIdentifier: typeIdentifier
        )

        return FileSignal(
            path: standardizedPath,
            name: url.lastPathComponent,
            fileExtension: ext.isEmpty ? nil : ext,
            uti: typeIdentifier,
            sizeBytes: sizeBytes,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            isDirectory: isDirectory,
            isBundle: isBundle,
            isHidden: isHidden,
            isSymbolicLink: isSymbolicLink,
            isFromDownloads: isFromDownloads,
            kind: kind
        )
    }

    private static func conformsToBundle(typeIdentifier: String?) -> Bool {
        guard let id = typeIdentifier, let utt = UTType(id) else { return false }
        return utt.conforms(to: .bundle) || utt.conforms(to: .application)
    }

    // MARK: - Grouping

    private func makeGroups(from signals: [FileSignal], maxFilesPerGroup: Int) -> [FileSignalGroup] {
        let byKind = Dictionary(grouping: signals, by: { $0.kind })
        return byKind.map { (kind, files) -> FileSignalGroup in
            let total = files.reduce(Int64(0)) { $0 + $1.sizeBytes }
            let sorted = files.sorted { $0.sizeBytes > $1.sizeBytes }
            let truncated: [FileSignal]
            if maxFilesPerGroup > 0 {
                truncated = Array(sorted.prefix(maxFilesPerGroup))
            } else {
                truncated = sorted
            }
            return FileSignalGroup(
                label: kind.rawValue,
                count: files.count,
                totalSizeBytes: total,
                files: truncated,
                commonSignals: Self.commonSignals(for: files)
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalSizeBytes != rhs.totalSizeBytes {
                return lhs.totalSizeBytes > rhs.totalSizeBytes
            }
            return lhs.label < rhs.label
        }
    }

    private static func commonSignals(for files: [FileSignal]) -> [String] {
        var out: [String] = []
        let exts = files.compactMap { $0.fileExtension }.filter { !$0.isEmpty }
        let freq = Dictionary(exts.map { ($0, 1) }, uniquingKeysWith: +)
        let top = freq.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key)(\($0.value))" }
        if !top.isEmpty { out.append("extensions: " + top.joined(separator: ", ")) }
        let downloads = files.filter { $0.isFromDownloads }.count
        if downloads > 0 { out.append("from_downloads: \(downloads)") }
        let bundles = files.filter { $0.isBundle }.count
        if bundles > 0 { out.append("bundles: \(bundles)") }
        return out
    }
}
