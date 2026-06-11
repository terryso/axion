import Testing
import Foundation

@testable import AxionCLI
import AxionCore

@Suite("Support Data Scan Service")
struct SupportDataScanServiceTests {

    private func makeTempHome(_ label: String) throws -> URL {
        let scratchRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("SupportScanScratch", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        let dir = scratchRoot.appendingPathComponent("home-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// 在 home 下伪造 `Library/<subdirs>/<name>` 结构（目录或文件）。
    private func makeEntry(_ home: URL, subdirs: String, name: String, asFile: Bool = false, bytes: Int = 4) throws {
        let dir = home.appendingPathComponent("Library/\(subdirs)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent(name)
        if asFile {
            try Data(repeating: 0x61, count: bytes).write(to: target)
        } else {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            // 放一个占位文件让目录有体积
            try Data(repeating: 0x61, count: bytes).write(to: target.appendingPathComponent("placeholder"))
        }
    }

    private func app(bundleId: String = "com.example.foo", displayName: String = "Foo", teamId: String? = "ADE12345") -> AppCandidate {
        AppCandidate(
            displayName: displayName,
            bundleIdentifier: bundleId,
            bundlePath: "/Applications/Foo.app",
            version: "1.0",
            teamIdentifier: teamId,
            sizeBytes: 0,
            isRunning: false,
            isSystemProtected: false,
            matchConfidence: .high
        )
    }

    private func item(_ items: [SupportDataItem], category: SupportDataCategory) -> SupportDataItem? {
        items.first { $0.category == category }
    }

    // MARK: - Pure: gradeEvidence

    @Test("gradeEvidence: bundle-id keyed paths are high")
    func gradeEvidenceHigh() {
        let r1 = SupportDataScanService.gradeEvidence(path: "/h/Library/Caches/com.example.foo", bundleId: "com.example.foo", displayName: "Foo")
        #expect(r1.0 == .high)
        #expect(r1.1.rule == "bundle_id_keyed")

        let r2 = SupportDataScanService.gradeEvidence(path: "/h/Library/Preferences/com.example.foo.plist", bundleId: "com.example.foo", displayName: "Foo")
        #expect(r2.0 == .high)

        // ByHost plist: <bundleId>.<host>.plist
        let r3 = SupportDataScanService.gradeEvidence(path: "/h/Library/Preferences/ByHost/com.example.foo.ABC.plist", bundleId: "com.example.foo", displayName: "Foo")
        #expect(r3.0 == .high)
    }

    @Test("gradeEvidence: display-name keyed is medium")
    func gradeEvidenceMedium() {
        let r = SupportDataScanService.gradeEvidence(path: "/h/Library/Logs/Foo", bundleId: "com.example.foo", displayName: "Foo")
        #expect(r.0 == .medium)
        #expect(r.1.rule == "display_name_keyed")
    }

    @Test("gradeEvidence: group container by team id (no bundle id) is low")
    func gradeEvidenceLowGroup() {
        let r = SupportDataScanService.gradeEvidence(path: "/h/Library/Group Containers/ADE12345.shared.group", bundleId: "com.example.foo", displayName: "Foo")
        #expect(r.0 == .low)
        #expect(r.1.rule == "group_container_team_id")
    }

    // MARK: - Pure: categoryToRisk

    @Test("categoryToRisk maps categories to data risk")
    func categoryToRiskMapping() {
        #expect(SupportDataScanService.categoryToRisk(.cache) == .low)
        #expect(SupportDataScanService.categoryToRisk(.logs) == .low)
        #expect(SupportDataScanService.categoryToRisk(.httpStorage) == .medium)
        #expect(SupportDataScanService.categoryToRisk(.preferences) == .medium)
        #expect(SupportDataScanService.categoryToRisk(.savedState) == .medium)
        #expect(SupportDataScanService.categoryToRisk(.applicationSupport) == .high)
        #expect(SupportDataScanService.categoryToRisk(.container) == .high)
        #expect(SupportDataScanService.categoryToRisk(.groupContainer) == .high)
        #expect(SupportDataScanService.categoryToRisk(.launchAgent) == .high)
        #expect(SupportDataScanService.categoryToRisk(.forbidden) == .forbidden)
    }

    // MARK: - Pure: isSharedDirectory

    @Test("isSharedDirectory detects group containers and cloud paths")
    func sharedDirectoryDetection() {
        #expect(SupportDataScanService.isSharedDirectory(path: "/h/Library/Group Containers/ADE.group", category: .groupContainer) == true)
        #expect(SupportDataScanService.isSharedDirectory(path: "/h/Library/Mobile Documents/com~apple~CloudDocs/x", category: .applicationSupport) == true)
        #expect(SupportDataScanService.isSharedDirectory(path: "/h/Library/CloudStorage/Dropbox/x", category: .applicationSupport) == true)
        // vendor parent under Application Support (safety net)
        #expect(SupportDataScanService.isSharedDirectory(path: "/h/Library/Application Support/Google", category: .applicationSupport) == true)
        // bundle-id keyed application support NOT shared
        #expect(SupportDataScanService.isSharedDirectory(path: "/h/Library/Application Support/com.example.foo", category: .applicationSupport) == false)
    }

    // MARK: - assembleItem (defaultSelected / shared rules)

    @Test("assembleItem: low-risk high-confidence cache is default-selected")
    func assembleLowRiskHighConfidence() {
        let item = SupportDataScanService.assembleItem(
            category: .cache,
            path: "/h/Library/Caches/com.example.foo",
            bundleId: "com.example.foo",
            displayName: "Foo"
        )
        #expect(item.matchConfidence == .high)
        #expect(item.dataRisk == .low)
        #expect(item.defaultSelected == true)
        #expect(item.requiresExplicitApproval == false)
    }

    @Test("assembleItem: high-risk container is never default-selected, requires explicit approval")
    func assembleHighRisk() {
        let item = SupportDataScanService.assembleItem(
            category: .container,
            path: "/h/Library/Containers/com.example.foo",
            bundleId: "com.example.foo",
            displayName: "Foo"
        )
        #expect(item.matchConfidence == .high)
        #expect(item.dataRisk == .high)
        #expect(item.defaultSelected == false)
        #expect(item.requiresExplicitApproval == true)
    }

    @Test("assembleItem: shared group container (low confidence) forced high risk, not selected, evidence flagged")
    func assembleSharedGroupContainer() {
        let item = SupportDataScanService.assembleItem(
            category: .groupContainer,
            path: "/h/Library/Group Containers/ADE12345.shared.group",
            bundleId: "com.example.foo",
            displayName: "Foo"
        )
        #expect(item.matchConfidence == .low)
        // shared + can't prove ownership → forced high risk
        #expect(item.dataRisk == .high)
        #expect(item.defaultSelected == false)
        #expect(item.requiresExplicitApproval == true)
        #expect(item.matchEvidence.rule.contains("shared_directory"))
    }

    // MARK: - scan (real temp home, AC #13: precise bundle-id keyed probing)

    @Test("scan discovers bundle-id keyed support data and assigns correct risk/confidence")
    func scanDiscoversKeyedSupportData() async throws {
        let home = try makeTempHome("scan1")
        defer { cleanup(home) }

        try makeEntry(home, subdirs: "Caches", name: "com.example.foo")
        try makeEntry(home, subdirs: "Logs", name: "Foo")  // displayName keyed → medium
        try makeEntry(home, subdirs: "Preferences", name: "com.example.foo.plist", asFile: true)
        try makeEntry(home, subdirs: "Containers", name: "com.example.foo")
        try makeEntry(home, subdirs: "Application Support", name: "com.example.foo")
        try makeEntry(home, subdirs: "Group Containers", name: "ADE12345.shared.group")
        try makeEntry(home, subdirs: "Preferences/ByHost", name: "com.example.foo.ABC123.plist", asFile: true)

        let service = SupportDataScanService()
        let items = await service.scan(for: app(), homeDirectory: home.path)

        // cache: high conf, low risk, selected
        let cache = try #require(item(items, category: .cache))
        #expect(cache.matchConfidence == .high)
        #expect(cache.dataRisk == .low)
        #expect(cache.defaultSelected == true)

        // logs (displayName): medium conf, low risk, selected
        let logs = try #require(item(items, category: .logs))
        #expect(logs.matchConfidence == .medium)
        #expect(logs.dataRisk == .low)
        #expect(logs.defaultSelected == true)

        // preferences plist: high conf, medium risk, NOT selected
        let prefs = try #require(item(items, category: .preferences))
        #expect(prefs.matchConfidence == .high)
        #expect(prefs.dataRisk == .medium)
        #expect(prefs.defaultSelected == false)

        // container: high risk, not selected, requires explicit
        let container = try #require(item(items, category: .container))
        #expect(container.dataRisk == .high)
        #expect(container.defaultSelected == false)
        #expect(container.requiresExplicitApproval == true)

        // application support: high risk
        let appSup = try #require(item(items, category: .applicationSupport))
        #expect(appSup.dataRisk == .high)
        #expect(appSup.defaultSelected == false)

        // group container: low confidence (so builder separates into hint-only), shared → high risk
        let group = try #require(item(items, category: .groupContainer))
        #expect(group.matchConfidence == .low)
        #expect(group.dataRisk == .high)
        #expect(group.matchEvidence.rule.contains("shared_directory"))
    }

    @Test("scan does NOT recurse ~/Library and only finds keyed paths")
    func scanDoesNotRecurseLibrary() async throws {
        let home = try makeTempHome("scan2")
        defer { cleanup(home) }

        // An unrelated cache dir that does NOT match bundle id / displayName must NOT be discovered
        try makeEntry(home, subdirs: "Caches", name: "com.other.unrelated")
        try makeEntry(home, subdirs: "Caches", name: "com.example.foo")  // keyed → found

        let service = SupportDataScanService()
        let items = await service.scan(for: app(), homeDirectory: home.path)

        let caches = items.filter { $0.category == .cache }
        #expect(caches.count == 1)
        #expect(caches.first?.path.hasSuffix("/com.example.foo") == true)
    }
}
