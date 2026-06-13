import Testing
import Foundation
import OpenAgentSDK

import AxionCore
@testable import AxionCLI

@Suite("Storage CLI Feature")
struct StorageFeatureTests {

    private actor MockStorageScanner: StorageScanning {
        private let result: ScanResult
        private var requests: [ScanRequest] = []

        init(result: ScanResult) {
            self.result = result
        }

        func scan(_ request: ScanRequest) async throws -> ScanResult {
            requests.append(request)
            return result
        }

        func lastRequest() -> ScanRequest? {
            requests.last
        }
    }

    private func makeTempDir() throws -> URL {
        let scratchRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("StorageTestScratch", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        let dir = scratchRoot
            .appendingPathComponent("axion-storage-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeFile(_ url: URL, bytes: Int) throws {
        try Data(repeating: 0x61, count: bytes).write(to: url)
    }

    private func makeContext(_ dir: URL) -> ToolContext {
        ToolContext(cwd: dir.path, toolUseId: "storage-test-\(UUID().uuidString)")
    }

    private func jsonObject(from result: ToolResult) throws -> [String: Any] {
        let data = try #require(result.content.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func sampleSignal(path: String, size: Int64 = 10, kind: FileKind = .document) -> FileSignal {
        FileSignal(
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            fileExtension: URL(fileURLWithPath: path).pathExtension,
            sizeBytes: size,
            kind: kind
        )
    }

    @Test("StorageExclusions applies default and user exclusion rules")
    func exclusionsApplyDefaultAndUserRules() {
        let exclusions = StorageExclusions(
            excludedRoots: ["/Users/nick/project"],
            includeHidden: false,
            homeDirectory: "/Users/nick"
        )

        #expect(exclusions.evaluate(path: "/System/Library/CoreServices").included == false)
        #expect(exclusions.evaluate(path: "/Users/nick/Library/Caches").reason == "user_library_protected")
        #expect(exclusions.evaluate(path: "/Users/nick/project/Sources/main.swift").reason == "excluded_by_config")
        #expect(exclusions.evaluate(path: "/Users/nick/Downloads/.git/config").reason == "git_directory")
        #expect(exclusions.evaluate(path: "/Users/nick/Downloads/node_modules/pkg").reason == "developer_cache")
        #expect(exclusions.developerCacheRoot(for: "/Users/nick/Downloads/node_modules/pkg") == "/Users/nick/Downloads/node_modules")
        #expect(exclusions.isDeveloperCacheRoot("/Users/nick/Downloads/node_modules") == true)
        #expect(exclusions.isDeveloperCacheRoot("/Users/nick/Downloads/node_modules/pkg") == false)
        #expect(exclusions.evaluate(path: "/Users/nick/Downloads/.hidden/file").reason == "hidden_entry")
        #expect(exclusions.evaluate(path: "/Users/nick/Downloads/visible.txt").included == true)

        let hiddenAllowed = StorageExclusions(includeHidden: true, homeDirectory: "/Users/nick")
        #expect(hiddenAllowed.evaluate(path: "/Users/nick/Downloads/.hidden/file").included == true)
    }

    @Test("scan() throws CancellationError when cancelled mid-scan (cooperative)")
    func scanCooperativelyCancels() async throws {
        let root = try makeTempDir()
        defer { cleanup(root) }
        // 足量文件确保枚举跨越多个取消检查点（耗时 >1ms），cancel() 落地时扫描仍在进行。
        for i in 0..<2000 {
            try writeFile(root.appendingPathComponent("file_\(i).bin"), bytes: 0)
        }
        let service = StorageScanService(homeDirectory: root.path)
        let request = ScanRequest(roots: [root])

        let task = _Concurrency.Task { try await service.scan(request) }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("scan should throw CancellationError when cancelled, but completed")
        } catch is CancellationError {
            // 协作式取消生效（agent.interrupt() → _streamTask.cancel() → 此处抛出）
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("StorageScanService sorts large files, collapses developer caches, and records symlinks and bundles")
    func scanServiceBuildsSafeSignals() async throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        let small = root.appendingPathComponent("small.txt")
        let big = root.appendingPathComponent("big.zip")
        let hidden = root.appendingPathComponent(".hidden")
        let cache = root.appendingPathComponent("node_modules/pkg")
        let app = root.appendingPathComponent("Demo.app/Contents/MacOS")
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).bin")
        let link = root.appendingPathComponent("outside-link")

        try writeFile(small, bytes: 10)
        try writeFile(big, bytes: 80)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try writeFile(hidden.appendingPathComponent("secret.txt"), bytes: 90)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try writeFile(cache.appendingPathComponent("cache.bin"), bytes: 100)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try writeFile(app.appendingPathComponent("demo"), bytes: 30)
        try writeFile(outside, bytes: 40)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let result = try await StorageScanService(homeDirectory: root.path).scan(ScanRequest(
            roots: [root],
            minSizeBytes: 0,
            includeHidden: false,
            excludedPaths: [],
            maxFilesPerGroup: 3
        ))

        let paths = result.largeFiles.map(\.path)
        #expect(paths.contains(big.path))
        #expect(paths.contains(small.path))
        #expect(paths.contains(link.path))
        #expect(paths.contains { $0.hasSuffix("/Demo.app") })
        #expect(paths.contains { $0.hasSuffix("/node_modules") })
        #expect(!paths.contains { $0.contains("node_modules/pkg") })
        #expect(!paths.contains { $0.contains(".hidden") })
        #expect(!paths.contains(outside.path))
        #expect(!paths.contains { $0.contains("Demo.app/Contents") })
        #expect(result.largeFiles == result.largeFiles.sorted { $0.sizeBytes > $1.sizeBytes })
        #expect(result.largeFiles.first { $0.path == link.path }?.isSymbolicLink == true)
        #expect(result.largeFiles.first { $0.path.hasSuffix("/Demo.app") }?.isBundle == true)
        #expect(result.largeFiles.first { $0.path.hasSuffix("/node_modules") }?.kind == .developerCache)
        #expect(result.groups.contains { $0.label == FileKind.developerCache.rawValue })
        #expect(result.groups.contains { $0.count > 0 })

        let directCacheResult = try await StorageScanService(homeDirectory: root.path).scan(ScanRequest(
            roots: [root.appendingPathComponent("node_modules")],
            minSizeBytes: 0,
            includeHidden: false,
            excludedPaths: [],
            maxFilesPerGroup: 3
        ))
        #expect(directCacheResult.largeFiles.map(\.path).contains(root.appendingPathComponent("node_modules").path))
    }

    @Test("StoragePlanBuilder rejects unsafe proposals and forces safe plan defaults")
    func planBuilderValidatesSourcesAndForcesDefaults() async throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        let keep = root.appendingPathComponent("invoice.pdf")
        let appDir = root.appendingPathComponent("Demo.app/Contents")
        let cacheRoot = root.appendingPathComponent("node_modules")
        let cacheFile = cacheRoot.appendingPathComponent("pkg/cache.bin")
        let excludedDir = root.appendingPathComponent("skip")
        let excludedFile = excludedDir.appendingPathComponent("ignored.txt")
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).txt")
        let symlink = root.appendingPathComponent("linked")

        try writeFile(keep, bytes: 15)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        try writeFile(appDir.appendingPathComponent("demo"), bytes: 5)
        try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeFile(cacheFile, bytes: 12)
        try FileManager.default.createDirectory(at: excludedDir, withIntermediateDirectories: true)
        try writeFile(excludedFile, bytes: 10)
        try writeFile(outside, bytes: 10)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)

        let plan = await StoragePlanBuilder().buildPlan(
            proposals: [
                ProposedItem(source: keep.path, suggestedCategory: "documents", suggestedAction: .move, target: root.appendingPathComponent("Documents/invoice.pdf").path, reason: "receipt", confidence: .high),
                ProposedItem(source: root.appendingPathComponent("Demo.app").path, suggestedCategory: "apps", suggestedAction: .uninstallApp, reason: "unused app", confidence: .medium),
                ProposedItem(source: cacheRoot.path, suggestedCategory: "developer cache", suggestedAction: .trash, reason: "rebuildable dependency cache", confidence: .high),
                ProposedItem(source: cacheFile.path, suggestedCategory: "developer cache child", suggestedAction: .trash, reason: "child should not bypass exclusion", confidence: .high),
                ProposedItem(source: excludedFile.path, suggestedAction: .scanOnly, reason: "excluded"),
                ProposedItem(source: outside.path, suggestedAction: .scanOnly, reason: "outside"),
                ProposedItem(source: symlink.path, suggestedAction: .scanOnly, reason: "link"),
            ],
            scanRoots: [root],
            exclusions: StorageExclusions(excludedRoots: [excludedDir.path], includeHidden: true, homeDirectory: root.path),
            surface: .chat
        )

        #expect(plan.surface == .chat)
        #expect(plan.items.count == 3)
        #expect(plan.items.allSatisfy { $0.approved == false })
        #expect(plan.items.allSatisfy { $0.evidence != nil })
        #expect(plan.items.first { $0.sourcePath == cacheRoot.path }?.dataRisk == .low)
        #expect(plan.items.first { $0.sourcePath == cacheRoot.path }?.action == .trash)
        #expect(plan.requiresConfirmation == true)
        #expect(plan.reversible == true)
        #expect(plan.riskLevel == .high)
        #expect(plan.operationId.hasPrefix("storage-"))
        #expect(plan.excludedNotes?.contains { $0.contains("excluded") } == true)
        #expect(plan.excludedNotes?.contains { $0.contains("outside_scan_roots") } == true)
        #expect(plan.excludedNotes?.contains { $0.contains("symlink_target_not_followed") } == true)
        #expect(plan.excludedNotes?.contains { $0.contains("developer_cache") && $0.contains("cache.bin") } == true)
    }

    @Test("StoragePlanFormatter renders terminal text and snake_case JSON")
    func formatterRendersTextAndJSON() throws {
        let item = StoragePlanItem(
            action: .move,
            sourcePath: "/tmp/a.pdf",
            targetPath: "/tmp/Documents/a.pdf",
            sizeBytes: 2_000,
            reason: "document",
            riskLevel: .medium,
            approved: false,
            evidence: StorageEvidence(rule: "kind:document", source: "agent", confidence: .high),
            dataRisk: .medium
        )
        let plan = StoragePlan(
            operationId: "storage-test",
            surface: .run,
            items: [item],
            riskLevel: .medium,
            summary: "one item",
            createdAt: "2026-06-11T00:00:00Z"
        )

        let text = StoragePlanFormatter.render(plan)
        #expect(text.contains("storage-test"))
        #expect(text.contains("[ ]"))
        #expect(text.contains("[MED]"))
        #expect(text.contains("approved=false"))

        let json = StoragePlanFormatter.renderJSON(plan)
        #expect(json.contains("\"operation_id\""))
        #expect(json.contains("\"source_path\""))
        #expect(!json.contains("\"sourcePath\""))

        let decoded = try JSONDecoder().decode(StoragePlan.self, from: Data(json.utf8))
        #expect(decoded == plan)
    }

    @Test("StoragePlanFormatter renders scan result summary (terminal)")
    func formatterRendersScanResult() {
        let archive = sampleSignal(path: "/tmp/big.zip", size: 5_000_000, kind: .archive)
        let doc = sampleSignal(path: "/tmp/note.txt", size: 200, kind: .document)
        let result = ScanResult(
            groups: [
                FileSignalGroup(label: "archive", count: 1, totalSizeBytes: archive.sizeBytes, files: [archive], commonSignals: ["extensions: zip(1)"]),
                FileSignalGroup(label: "document", count: 1, totalSizeBytes: doc.sizeBytes, files: [doc], commonSignals: []),
            ],
            largeFiles: [archive],
            skippedCount: 3,
            excludedNotes: ["excluded_by_config: skip"]
        )

        let text = StoragePlanFormatter.render(result)
        // Header summarises groups / large files / skipped.
        #expect(text.contains("2 group(s)"))
        #expect(text.contains("1 large file(s)"))
        #expect(text.contains("3 skipped"))
        // Each group lists label + file count + total size.
        #expect(text.contains("archive: 1 file(s)"))
        #expect(text.contains("5.0MB"))
        // Large-file section surfaces the path.
        #expect(text.contains("/tmp/big.zip"))
        // Notes surfaced.
        #expect(text.contains("excluded_by_config: skip"))
    }

    @Test("StorageScanTool uses injected scanner and returns encoded scan response")
    func storageScanToolUsesInjectedScanner() async throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        let signal = sampleSignal(path: root.appendingPathComponent("large.zip").path, size: 2_000_000, kind: .archive)
        let result = ScanResult(
            groups: [FileSignalGroup(label: "archive", count: 1, totalSizeBytes: signal.sizeBytes, files: [signal], commonSignals: ["extensions: zip(1)"])],
            largeFiles: [signal],
            skippedCount: 2,
            excludedNotes: ["excluded_by_config: skip"]
        )
        let scanner = MockStorageScanner(result: result)
        let tool = StorageScanTool(scanner: scanner, config: StorageConfig(
            largeFileThresholdBytes: 1_073_741_824,
            excludedPaths: [root.appendingPathComponent("configured-skip").path],
            maxFilesPerGroup: 7,
            storageOpsDir: "~/.axion/storage-ops/"
        ))

        let toolResult = await tool.call(
            input: [
                "roots": [root.path],
                "min_size_mb": 2,
                "include_hidden": true,
                "exclude_paths": [root.appendingPathComponent("runtime-skip").path],
            ] as [String: Any],
            context: makeContext(root)
        )

        #expect(!toolResult.isError)
        let body = try jsonObject(from: toolResult)
        #expect(body["status"] as? String == "ok")
        #expect((body["large_files"] as? [[String: Any]])?.count == 1)
        #expect(body["skipped_count"] as? Int == 2)
        #expect((body["summary"] as? String)?.contains("2.0MB") == true)

        let request = try #require(await scanner.lastRequest())
        #expect(request.roots.map(\.path) == [root.path])
        #expect(request.minSizeBytes == 2_000_000)
        #expect(request.includeHidden == true)
        #expect(request.maxFilesPerGroup == 7)
        #expect(request.excludedPaths.contains(root.appendingPathComponent("configured-skip").path))
        #expect(request.excludedPaths.contains(root.appendingPathComponent("runtime-skip").path))
    }

    @Test("StorageScanTool returns validation error for non-object input")
    func storageScanToolRejectsInvalidInput() async throws {
        let scanner = MockStorageScanner(result: ScanResult(groups: [], largeFiles: [], skippedCount: 0, excludedNotes: []))
        let tool = StorageScanTool(scanner: scanner)

        let result = await tool.call(input: "bad", context: ToolContext(cwd: "/tmp", toolUseId: "bad-input"))

        #expect(result.isError)
        #expect(result.content.contains("invalid_input"))
    }

    @Test("ProposeStoragePlanTool materializes a safe plan and drops invalid items")
    func proposeStoragePlanToolMaterializesSafePlan() async throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        let source = root.appendingPathComponent("installer.dmg")
        let excludedDir = root.appendingPathComponent("excluded")
        let excludedFile = excludedDir.appendingPathComponent("ignored.txt")
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).txt")

        try writeFile(source, bytes: 32)
        try FileManager.default.createDirectory(at: excludedDir, withIntermediateDirectories: true)
        try writeFile(excludedFile, bytes: 16)
        try writeFile(outside, bytes: 8)
        defer { try? FileManager.default.removeItem(at: outside) }

        let tool = ProposeStoragePlanTool(config: StorageConfig(
            largeFileThresholdBytes: 1_073_741_824,
            excludedPaths: [excludedDir.path],
            maxFilesPerGroup: 50,
            storageOpsDir: "~/.axion/storage-ops/"
        ))

        let result = await tool.call(
            input: [
                "scan_roots": [root.path],
                "surface": "chat",
                "proposals": [
                    [
                        "source": source.path,
                        "suggested_category": "installers",
                        "suggested_action": "trash",
                        "reason": "old installer",
                        "confidence": "high",
                    ],
                    [
                        "source": outside.path,
                        "suggested_action": "scan_only",
                        "reason": "outside",
                    ],
                    [
                        "source": excludedFile.path,
                        "suggested_action": "scan_only",
                        "reason": "excluded",
                    ],
                ],
            ] as [String: Any],
            context: makeContext(root)
        )

        #expect(!result.isError)
        let plan = try JSONDecoder().decode(StoragePlan.self, from: Data(result.content.utf8))
        #expect(plan.surface == .chat)
        #expect(plan.items.count == 1)
        let item = try #require(plan.items.first)
        #expect(item.sourcePath == source.path)
        #expect(item.action == .trash)
        #expect(item.approved == false)
        #expect(item.riskLevel == .medium)
        #expect(item.evidence?.confidence == .high)
        #expect(plan.excludedNotes?.contains { $0.contains("outside_scan_roots") } == true)
        #expect(plan.excludedNotes?.contains { $0.contains("excluded_by_config") } == true)
    }

    @Test("ProposeStoragePlanTool validates required input")
    func proposeStoragePlanToolRejectsMissingRoots() async {
        let tool = ProposeStoragePlanTool()

        let result = await tool.call(
            input: ["proposals": []] as [String: Any],
            context: ToolContext(cwd: "/tmp", toolUseId: "missing-roots")
        )

        #expect(result.isError)
        #expect(result.content.contains("missing_scan_roots"))
    }
}
