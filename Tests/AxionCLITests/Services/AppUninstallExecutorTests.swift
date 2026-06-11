import Testing
import Foundation

@testable import AxionCLI
import AxionCore

@Suite("App Uninstall Executor")
struct AppUninstallExecutorTests {

    /// Mock App 退出器：固定返回是否退出成功（AC #3 测试注入）。
    final class MockAppQuitter: AppQuitting, @unchecked Sendable {
        let result: Bool
        init(result: Bool) { self.result = result }
        func terminate(bundleIdentifier: String) async -> Bool { result }
    }

    private func makeScratch(_ label: String) throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("AppUninstallScratch", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dir = root.appendingPathComponent("scratch-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// 伪造 `.app` bundle（含 `Contents/Info.plist` 带 CFBundleIdentifier + payload）。
    @discardableResult
    private func makeFakeApp(parent: URL, bundleId: String, displayName: String = "FooApp") throws -> URL {
        let appURL = parent.appendingPathComponent("\(displayName).app", isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleId,
            "CFBundleName": displayName,
            "CFBundleShortVersionString": "1.0",
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 0x61, count: 16).write(to: contents.appendingPathComponent("payload.bin"))
        return appURL
    }

    /// 注入用 TrashPerforming：把 source 移到临时 trash 目录（不污染真实废纸篓），返回新路径。
    private func makeMockTrash(_ trashDir: URL) -> TrashPerforming {
        TrashPerforming { source in
            try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
            let dest = trashDir.appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")
            try FileManager.default.moveItem(at: source, to: dest)
            return dest
        }
    }

    private func makeExecutor(
        opsDir: String, home: String, trashDir: URL,
        quitterResult: Bool = true
    ) -> AppUninstallExecutor {
        AppUninstallExecutor(
            manifestStore: StorageManifestStore(storageOpsDir: opsDir, homeDirectory: home),
            appQuitter: MockAppQuitter(result: quitterResult),
            trashPerformer: makeMockTrash(trashDir)
        )
    }

    // MARK: - 草稿先行 + 空操作

    @Test("draft-first manifest persisted; no-op completes")
    func draftFirstPersisted() async throws {
        let s = try makeScratch("draft")
        defer { cleanup(s) }
        let ops = s.appendingPathComponent("ops", isDirectory: true)
        let trash = s.appendingPathComponent("trash", isDirectory: true)
        let executor = makeExecutor(opsDir: ops.path, home: s.path, trashDir: trash)

        let result = await executor.execute(AppUninstallExecuteRequest(
            operationId: "op-draft", surface: .run, app: makeCandidate(),
            uninstallBundle: false, supportDataItems: [], searchRoots: [s],
            userRequest: nil, homeDirectory: s.path, storageOpsDir: ops.path
        ))

        #expect(result.succeeded == 0)
        #expect(result.failed == 0)
        #expect(result.manifest.status == .completed)
        // 落盘可加载
        let store = StorageManifestStore(storageOpsDir: ops.path, homeDirectory: s.path)
        #expect(store.load(operationId: "op-draft") != nil)
    }

    // MARK: - AC #3：运行中退出失败 → 不移动 bundle

    @Test("app still running after quit failure → bundle not moved, failed")
    func appStillRunningBlocksBundle() async throws {
        let s = try makeScratch("running")
        defer { cleanup(s) }
        let appsDir = s.appendingPathComponent("Apps", isDirectory: true)
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        let appURL = try makeFakeApp(parent: appsDir, bundleId: "com.example.foo")
        let trash = s.appendingPathComponent("trash", isDirectory: true)
        // quit 失败
        let executor = makeExecutor(opsDir: s.appendingPathComponent("ops").path, home: s.path, trashDir: trash, quitterResult: false)

        let app = makeCandidate(bundleId: "com.example.foo", bundlePath: appURL.path, isRunning: true)
        let result = await executor.execute(AppUninstallExecuteRequest(
            operationId: "op-run", surface: .run, app: app,
            uninstallBundle: true, supportDataItems: [], searchRoots: [appsDir],
            userRequest: nil, homeDirectory: s.path, storageOpsDir: s.appendingPathComponent("ops").path
        ))

        #expect(result.failed == 1)
        #expect(result.manifest.status == .partiallyFailed)
        let bundleItem = result.manifest.items.first { $0.action == .uninstallApp }
        #expect(bundleItem?.outcome == .failed)
        #expect(bundleItem?.reason == "app_still_running")
        // bundle 仍在原位（未移动）
        #expect(FileManager.default.fileExists(atPath: appURL.path) == true)
    }

    // MARK: - AC #9：bundle 移入废纸篓

    @Test("bundle trashed on success → uninstallApp manifest item with trash path")
    func bundleTrashedOnSuccess() async throws {
        let s = try makeScratch("success")
        defer { cleanup(s) }
        let appsDir = s.appendingPathComponent("Apps", isDirectory: true)
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        let appURL = try makeFakeApp(parent: appsDir, bundleId: "com.example.foo")
        let trash = s.appendingPathComponent("trash", isDirectory: true)
        let executor = makeExecutor(opsDir: s.appendingPathComponent("ops").path, home: s.path, trashDir: trash)

        let app = makeCandidate(bundleId: "com.example.foo", bundlePath: appURL.path, isRunning: false)
        let result = await executor.execute(AppUninstallExecuteRequest(
            operationId: "op-ok", surface: .run, app: app,
            uninstallBundle: true, supportDataItems: [], searchRoots: [appsDir],
            userRequest: nil, homeDirectory: s.path, storageOpsDir: s.appendingPathComponent("ops").path
        ))

        #expect(result.succeeded == 1)
        #expect(result.manifest.status == .completed)
        let bundleItem = result.manifest.items.first { $0.action == .uninstallApp }
        #expect(bundleItem?.outcome == .succeeded)
        #expect(bundleItem?.trashResultPath?.isEmpty == false)
        // 源消失、trash 落位存在（可恢复，非永久删除）
        #expect(FileManager.default.fileExists(atPath: appURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: bundleItem?.trashResultPath ?? "/nonexistent") == true)
    }

    @Test("running app trashed after graceful quit succeeds")
    func runningAppTrashedAfterQuit() async throws {
        let s = try makeScratch("quitok")
        defer { cleanup(s) }
        let appsDir = s.appendingPathComponent("Apps", isDirectory: true)
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        let appURL = try makeFakeApp(parent: appsDir, bundleId: "com.example.foo")
        let trash = s.appendingPathComponent("trash", isDirectory: true)
        let executor = makeExecutor(opsDir: s.appendingPathComponent("ops").path, home: s.path, trashDir: trash, quitterResult: true)

        let app = makeCandidate(bundleId: "com.example.foo", bundlePath: appURL.path, isRunning: true)
        let result = await executor.execute(AppUninstallExecuteRequest(
            operationId: "op-quitok", surface: .run, app: app,
            uninstallBundle: true, supportDataItems: [], searchRoots: [appsDir],
            userRequest: nil, homeDirectory: s.path, storageOpsDir: s.appendingPathComponent("ops").path
        ))

        let bundleItem = result.manifest.items.first { $0.action == .uninstallApp }
        #expect(bundleItem?.outcome == .succeeded)
        #expect(FileManager.default.fileExists(atPath: appURL.path) == false)
    }

    // MARK: - AC #12：纵深校验拒绝

    @Test("bundle outside search roots → rejected")
    func bundleOutsideRoots() async throws {
        let s = try makeScratch("outside")
        defer { cleanup(s) }
        let otherDir = s.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        let appURL = try makeFakeApp(parent: otherDir, bundleId: "com.example.foo")
        let appsDir = s.appendingPathComponent("Apps", isDirectory: true)  // 不含 appURL
        let trash = s.appendingPathComponent("trash", isDirectory: true)
        let executor = makeExecutor(opsDir: s.appendingPathComponent("ops").path, home: s.path, trashDir: trash)

        let app = makeCandidate(bundleId: "com.example.foo", bundlePath: appURL.path)
        let result = await executor.execute(AppUninstallExecuteRequest(
            operationId: "op-out", surface: .run, app: app,
            uninstallBundle: true, supportDataItems: [], searchRoots: [appsDir],
            userRequest: nil, homeDirectory: s.path, storageOpsDir: s.appendingPathComponent("ops").path
        ))

        let bundleItem = result.manifest.items.first { $0.action == .uninstallApp }
        #expect(bundleItem?.outcome == .failed)
        #expect(bundleItem?.reason?.hasPrefix("outside_applications_dirs") == true)
        #expect(FileManager.default.fileExists(atPath: appURL.path) == true)
    }

    @Test("bundle id mismatch → rejected")
    func bundleIdMismatch() async throws {
        let s = try makeScratch("mismatch")
        defer { cleanup(s) }
        let appsDir = s.appendingPathComponent("Apps", isDirectory: true)
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        // 实际 bundle id 与传入 app 的不同
        let appURL = try makeFakeApp(parent: appsDir, bundleId: "com.real.id")
        let trash = s.appendingPathComponent("trash", isDirectory: true)
        let executor = makeExecutor(opsDir: s.appendingPathComponent("ops").path, home: s.path, trashDir: trash)

        let app = makeCandidate(bundleId: "com.example.foo", bundlePath: appURL.path)
        let result = await executor.execute(AppUninstallExecuteRequest(
            operationId: "op-mismatch", surface: .run, app: app,
            uninstallBundle: true, supportDataItems: [], searchRoots: [appsDir],
            userRequest: nil, homeDirectory: s.path, storageOpsDir: s.appendingPathComponent("ops").path
        ))

        let bundleItem = result.manifest.items.first { $0.action == .uninstallApp }
        #expect(bundleItem?.outcome == .failed)
        #expect(bundleItem?.reason?.hasPrefix("bundle_id_mismatch") == true)
    }

    @Test("missing bundle path → rejected")
    func bundleMissing() async throws {
        let s = try makeScratch("missing")
        defer { cleanup(s) }
        let appsDir = s.appendingPathComponent("Apps", isDirectory: true)
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        let trash = s.appendingPathComponent("trash", isDirectory: true)
        let executor = makeExecutor(opsDir: s.appendingPathComponent("ops").path, home: s.path, trashDir: trash)

        let app = makeCandidate(bundleId: "com.example.foo", bundlePath: appsDir.appendingPathComponent("Ghost.app").path)
        let result = await executor.execute(AppUninstallExecuteRequest(
            operationId: "op-missing", surface: .run, app: app,
            uninstallBundle: true, supportDataItems: [], searchRoots: [appsDir],
            userRequest: nil, homeDirectory: s.path, storageOpsDir: s.appendingPathComponent("ops").path
        ))

        let bundleItem = result.manifest.items.first { $0.action == .uninstallApp }
        #expect(bundleItem?.outcome == .failed)
        #expect(bundleItem?.reason?.hasPrefix("bundle_missing") == true)
    }

    // MARK: - AC #9 support 数据 + AC #7/#8 校验

    @Test("valid support item trashed; low-confidence and shared-not-approved skipped")
    func supportItemsHandling() async throws {
        let s = try makeScratch("support")
        defer { cleanup(s) }
        let appsDir = s.appendingPathComponent("Apps", isDirectory: true)
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        // 三个 support 数据目录
        let cachePath = s.appendingPathComponent("Library/Caches/com.example.foo", isDirectory: true)
        try FileManager.default.createDirectory(at: cachePath, withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: 8).write(to: cachePath.appendingPathComponent("f"))

        let trash = s.appendingPathComponent("trash", isDirectory: true)
        let executor = makeExecutor(opsDir: s.appendingPathComponent("ops").path, home: s.path, trashDir: trash)

        let valid = makeSupportItem(category: .cache, path: cachePath.path, matchConfidence: .high, dataRisk: .low)
        let lowConf = makeSupportItem(category: .groupContainer, path: "/tmp/whatever", matchConfidence: .low, dataRisk: .high)
        let sharedNotApproved = makeSupportItem(category: .groupContainer, path: "/tmp/whatever2",
                                               matchConfidence: .medium, dataRisk: .high,
                                               defaultSelected: false, requiresExplicitApproval: true)
        let app = makeCandidate(bundleId: "com.example.foo", bundlePath: appsDir.appendingPathComponent("None.app").path)
        let result = await executor.execute(AppUninstallExecuteRequest(
            operationId: "op-support", surface: .run, app: app,
            uninstallBundle: false,
            supportDataItems: [valid, lowConf, sharedNotApproved],
            searchRoots: [appsDir],
            userRequest: nil, homeDirectory: s.path, storageOpsDir: s.appendingPathComponent("ops").path
        ))

        #expect(result.succeeded == 1)
        #expect(result.skipped == 2)
        let trashItem = result.manifest.items.first { $0.action == .trash && $0.outcome == .succeeded }
        #expect(trashItem != nil)
        #expect(FileManager.default.fileExists(atPath: cachePath.path) == false)

        let reasons = result.manifest.items.compactMap { $0.reason }
        #expect(reasons.contains { $0.hasPrefix("low_confidence_hint_only") } == true)
        #expect(reasons.contains { $0.hasPrefix("shared_directory_not_approved") } == true)
    }

    // MARK: - 纵深防御：support 路径必须位于 ~/Library 之下

    @Test("support item outside ~/Library is rejected even with benign flags")
    func supportItemOutsideLibraryRejected() async throws {
        let s = try makeScratch("outside-lib")
        defer { cleanup(s) }
        let appsDir = s.appendingPathComponent("Apps", isDirectory: true)
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        // 一个真实存在于 ~/Library 之外的「重要文件」（伪造请求即便带低风险标志也应被拒）
        let outsidePath = s.appendingPathComponent("Documents/important.doc", isDirectory: false)
        try FileManager.default.createDirectory(at: outsidePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: 8).write(to: outsidePath)
        let trash = s.appendingPathComponent("trash", isDirectory: true)
        let executor = makeExecutor(opsDir: s.appendingPathComponent("ops").path, home: s.path, trashDir: trash)

        // 伪装成低风险高置信度已批准项——路径越界应被拒
        let crafted = makeSupportItem(category: .cache, path: outsidePath.path,
                                      matchConfidence: .high, dataRisk: .low,
                                      defaultSelected: true, requiresExplicitApproval: false)
        let app = makeCandidate(bundleId: "com.example.foo", bundlePath: appsDir.appendingPathComponent("None.app").path)
        let result = await executor.execute(AppUninstallExecuteRequest(
            operationId: "op-outside-lib", surface: .run, app: app,
            uninstallBundle: false, supportDataItems: [crafted], searchRoots: [appsDir],
            userRequest: nil, homeDirectory: s.path, storageOpsDir: s.appendingPathComponent("ops").path
        ))

        #expect(result.succeeded == 0)
        #expect(result.skipped == 1)
        #expect(result.manifest.status == .partiallyFailed)
        let reason = result.manifest.items.first { $0.action == .trash }?.reason ?? ""
        #expect(reason.hasPrefix("outside_user_library") == true)
        // 文件未被移动（仍在原位）
        #expect(FileManager.default.fileExists(atPath: outsidePath.path) == true)
    }

    // MARK: - 终态 partiallyFailed

    @Test("partial failure → partiallyFailed status")
    func partialFailureStatus() async throws {
        let s = try makeScratch("partial")
        defer { cleanup(s) }
        let appsDir = s.appendingPathComponent("Apps", isDirectory: true)
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        let cachePath = s.appendingPathComponent("Library/Caches/com.example.foo", isDirectory: true)
        try FileManager.default.createDirectory(at: cachePath, withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: 8).write(to: cachePath.appendingPathComponent("f"))

        let trash = s.appendingPathComponent("trash", isDirectory: true)
        let executor = makeExecutor(opsDir: s.appendingPathComponent("ops").path, home: s.path, trashDir: trash)

        let valid = makeSupportItem(category: .cache, path: cachePath.path, matchConfidence: .high, dataRisk: .low)
        // 这条会因为 source_missing 失败（路径在 ~/Library 之下但不存在）
        let missing = makeSupportItem(category: .logs, path: s.appendingPathComponent("Library/Logs/nope-missing").path,
                                      matchConfidence: .high, dataRisk: .low)
        let app = makeCandidate(bundleId: "com.example.foo", bundlePath: appsDir.appendingPathComponent("None.app").path)
        let result = await executor.execute(AppUninstallExecuteRequest(
            operationId: "op-partial", surface: .run, app: app,
            uninstallBundle: false, supportDataItems: [valid, missing], searchRoots: [appsDir],
            userRequest: nil, homeDirectory: s.path, storageOpsDir: s.appendingPathComponent("ops").path
        ))

        // valid → source_missing 的项被校验拒绝记 errors → partiallyFailed
        #expect(result.manifest.status == .partiallyFailed)
        #expect(result.succeeded == 1)
        #expect(result.manifest.errors.isEmpty == false)
    }
}
