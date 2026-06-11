import Foundation

import AxionCore

/// `StorageManifest` 的持久化（`~/.axion/storage-ops/<operationId>.json`）。
///
/// `final class ... : Sendable`：持两个不可变 `let` 字符串（标准化目录 + 主目录），
/// 无可变状态，跨 actor 安全。原子覆写（`data.write(to:options:.atomic)`）复用
/// `AxionFileIO.persistRunRecord` 同模式；load 复用 `loadDecodableFile`；
/// 路径展开复用 `StorageExclusions.standardize`。
///
/// 测试注入临时 `storageOpsDir`（镜像 `MemoryToolTests`/39.1 `StorageFeatureTests` 的
/// `makeTempDir()`/`cleanup()` + `defer` 模式），规避 `~/.axion` sandbox 写入限制。
final class StorageManifestStore: Sendable {

    /// 标准化后的 manifest 存储目录（绝对路径，`~` 已展开）。
    let storageOpsDir: String
    /// 主目录（路径展开用，测试可注入）。
    let homeDirectory: String

    init(storageOpsDir: String, homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
        self.storageOpsDir = StorageExclusions.standardize(storageOpsDir, home: homeDirectory)
    }

    // MARK: - Write

    /// 原子覆写 manifest（确保目录存在）。每次更新（草稿 / 逐项 / 完成 / 撤销）都整体覆写。
    func save(_ manifest: StorageManifest) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: storageOpsDir, withIntermediateDirectories: true)
        let path = resolveManifestPath(manifest.operationId)
        let data = try axionSortedEncoder.encode(manifest)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// 尽力保存：失败不抛（草稿先行路径中，若目录不可写也不应中断后续内存执行）。
    /// 返回是否成功落盘。
    @discardableResult
    func trySave(_ manifest: StorageManifest) -> Bool {
        do {
            try save(manifest)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Read

    /// 加载指定 operationId 的 manifest；缺失 / 解码失败返回 nil（复用 `loadDecodableFile`）。
    func load(operationId: String) -> StorageManifest? {
        loadDecodableFile(resolveManifestPath(operationId))
    }

    /// 列最近的 manifest（按文件修改时间降序），供「撤销最近一次」。
    func listRecent(limit: Int = 20) -> [StorageManifest] {
        let fm = FileManager.default
        guard let fileNames = try? fm.contentsOfDirectory(atPath: storageOpsDir) else { return [] }
        var entries: [(modificationDate: Date, manifest: StorageManifest)] = []
        for fileName in fileNames where fileName.hasSuffix(".json") {
            let path = (storageOpsDir as NSString).appendingPathComponent(fileName)
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let mod = attrs[.modificationDate] as? Date,
                  let manifest = loadDecodableFile(path, as: StorageManifest.self) else { continue }
            entries.append((mod, manifest))
        }
        return entries
            .sorted { $0.modificationDate > $1.modificationDate }
            .prefix(limit)
            .map(\.manifest)
    }

    /// 取最近一次可撤销 manifest：状态为终态（`completed` / `partiallyFailed`）且尚未撤销。
    func mostRecentUndoable() -> StorageManifest? {
        listRecent().first { manifest in
            (manifest.status == .completed || manifest.status == .partiallyFailed)
                && manifest.undoneAt == nil
        }
    }

    // MARK: - Helpers

    /// `<storageOpsDir>/<sanitizeFileName(operationId)>.json`。
    func resolveManifestPath(_ operationId: String) -> String {
        resolveFilePath(name: operationId, extension: "json", in: storageOpsDir)
    }
}
