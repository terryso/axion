import Foundation
import Testing

@testable import AxionCLI

@Suite("App List Service")
struct AppListServiceTests {
    private func makeTempDir(_ label: String) throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("AppListScratch", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dir = root.appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeApp(
        root: URL,
        name: String,
        bundleId: String,
        displayName: String? = nil,
        version: String = "1.0"
    ) throws -> URL {
        let app = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleId,
            "CFBundleName": displayName ?? name,
            "CFBundleShortVersionString": version,
            "CFBundlePackageType": "APPL",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    @Test("fast list returns third-party apps sorted and filtered")
    func fastListReturnsFilteredCandidates() async throws {
        let root = try makeTempDir("fast")
        defer { cleanup(root) }

        _ = try makeApp(root: root, name: "Slack", bundleId: "com.tinyspeck.slackmacgap", version: "4.0")
        _ = try makeApp(root: root, name: "Notes", bundleId: "com.apple.Notes", version: "1.0")
        _ = try makeApp(root: root, name: "Zoom", bundleId: "us.zoom.xos", version: "6.0")

        let service = AppListService(
            fastRoots: [root],
            spotlightURLProvider: { [] },
            homebrewURLProvider: { [] },
            runningDetector: { $0 == "us.zoom.xos" },
            sizeReader: { _ in 2048 }
        )

        let all = await service.list(filter: nil, scope: .fast)
        #expect(all.candidates.map(\.displayName) == ["Slack", "Zoom"])
        #expect(all.protectedMatches.isEmpty)
        #expect(all.candidates.last?.isRunning == true)

        let filtered = await service.list(filter: "slack", scope: .fast)
        #expect(filtered.candidates.map(\.bundleIdentifier) == ["com.tinyspeck.slackmacgap"])
    }

    @Test("protected apps appear only as protected matches when filtered")
    func protectedAppsAppearOnlyWhenFiltered() async throws {
        let root = try makeTempDir("protected")
        defer { cleanup(root) }

        _ = try makeApp(root: root, name: "Safari", bundleId: "com.apple.Safari", version: "18.0")

        let service = AppListService(
            fastRoots: [root],
            spotlightURLProvider: { [] },
            homebrewURLProvider: { [] },
            runningDetector: { _ in false },
            sizeReader: { _ in 1 }
        )

        let unfiltered = await service.list(filter: nil, scope: .fast)
        #expect(unfiltered.candidates.isEmpty)
        #expect(unfiltered.protectedMatches.isEmpty)

        let filtered = await service.list(filter: "safari", scope: .fast)
        #expect(filtered.candidates.isEmpty)
        #expect(filtered.protectedMatches.map(\.displayName) == ["Safari"])
    }

    @Test("deep list merges spotlight and homebrew providers and deduplicates paths")
    func deepListMergesProviders() async throws {
        let root = try makeTempDir("deep")
        defer { cleanup(root) }

        let fast = try makeApp(root: root, name: "FastApp", bundleId: "com.example.fast")
        let spotlight = try makeApp(root: root, name: "DeepApp", bundleId: "com.example.deep")
        let brew = try makeApp(root: root, name: "BrewApp", bundleId: "com.example.brew")

        let service = AppListService(
            fastRoots: [root],
            fastURLProvider: { _ in [fast] },
            spotlightURLProvider: { [spotlight, fast] },
            homebrewURLProvider: { [brew] },
            runningDetector: { _ in false },
            sizeReader: { _ in 1 }
        )

        let result = await service.list(filter: nil, scope: .deep)
        #expect(result.candidates.map(\.displayName) == ["BrewApp", "DeepApp", "FastApp"])
        #expect(result.candidates.map(\.bundlePath).count == Set(result.candidates.map(\.bundlePath)).count)
    }

    @Test("deep list deduplicates symlinked app paths")
    func deepListDeduplicatesSymlinks() async throws {
        let root = try makeTempDir("symlink")
        defer { cleanup(root) }

        let realRoot = root.appendingPathComponent("Caskroom", isDirectory: true)
        let linkRoot = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkRoot, withIntermediateDirectories: true)
        let realApp = try makeApp(root: realRoot, name: "BrewApp", bundleId: "com.example.brew")
        let linkedApp = linkRoot.appendingPathComponent("BrewApp.app", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedApp, withDestinationURL: realApp)

        let service = AppListService(
            fastRoots: [linkRoot],
            fastURLProvider: { _ in [linkedApp] },
            spotlightURLProvider: { [] },
            homebrewURLProvider: { [realApp] },
            runningDetector: { _ in false },
            sizeReader: { _ in 1 }
        )

        let result = await service.list(filter: nil, scope: .deep)
        #expect(result.candidates.map(\.bundleIdentifier) == ["com.example.brew"])
    }

    @Test("limitedCaskroomAppURLs finds apps at cask/version level only")
    func caskroomProviderFindsVersionApps() throws {
        let root = try makeTempDir("caskroom")
        defer { cleanup(root) }

        let version = root
            .appendingPathComponent("visual-studio-code", isDirectory: true)
            .appendingPathComponent("1.0", isDirectory: true)
        _ = try makeApp(root: version, name: "Visual Studio Code", bundleId: "com.microsoft.VSCode")

        let apps = AppListService.limitedCaskroomAppURLs(root: root)
        #expect(apps.count == 1)
        #expect(apps.first?.lastPathComponent == "Visual Studio Code.app")
    }

    @Test("default size reader sums app bundle contents")
    func defaultSizeReaderSumsAppBundleContents() throws {
        let root = try makeTempDir("size")
        defer { cleanup(root) }

        let app = try makeApp(root: root, name: "Sized", bundleId: "com.example.sized")
        let resources = app
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let payload = Data(repeating: 7, count: 4096)
        try payload.write(to: resources.appendingPathComponent("payload.dat"))

        let size = AppListService.defaultSizeReader(url: app)

        #expect(size >= Int64(payload.count))
    }

    @Test("formatter renders protected hint and deep search prompt")
    func formatterRendersHints() {
        let protected = AppListItem(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            bundlePath: "/Applications/Safari.app",
            version: "18",
            sizeBytes: 100,
            isRunning: false,
            isSystemProtected: true,
            source: .applications
        )
        let result = AppListResult(
            scope: .fast,
            filter: "safari",
            candidates: [],
            protectedMatches: [protected],
            warnings: [],
            deepSearchAvailable: true
        )
        let output = AppListFormatter.renderList(result)
        #expect(output.contains("受保护"))
        #expect(output.contains("/apps --all"))
        #expect(!output.contains("/Applications/Safari.app"))
    }

    @Test("formatter renders candidate size without path")
    func formatterRendersCandidateSizeWithoutPath() {
        let item = AppListItem(
            displayName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            bundlePath: "/Applications/Slack.app",
            version: "4.0",
            sizeBytes: 1024,
            isRunning: false,
            isSystemProtected: false,
            source: .applications
        )
        let result = AppListResult(
            scope: .fast,
            filter: nil,
            candidates: [item],
            protectedMatches: [],
            warnings: [],
            deepSearchAvailable: true
        )

        let output = AppListFormatter.renderList(result, selectedIndex: 0, terminalWidth: 80)
        #expect(output.contains("大小"))
        #expect(output.contains("1.0 KB"))
        #expect(!output.contains("path:"))
        #expect(!output.contains("/Applications/Slack.app"))
    }

    @Test("formatter renders paged window range and absolute numbering")
    func formatterRendersPagedWindow() {
        let items = (1...25).map { index in
            AppListItem(
                displayName: "App \(index)",
                bundleIdentifier: "com.example.app\(index)",
                bundlePath: "/Applications/App \(index).app",
                version: "1.0",
                sizeBytes: 1024,
                isRunning: false,
                isSystemProtected: false,
                source: .applications
            )
        }
        let result = AppListResult(
            scope: .fast,
            filter: nil,
            candidates: items,
            protectedMatches: [],
            warnings: [],
            deepSearchAvailable: true
        )

        let output = AppListFormatter.renderList(
            result,
            selectedIndex: 20,
            maxItems: 20,
            startIndex: 1,
            numbered: true,
            terminalWidth: 80
        )

        #expect(output.contains("显示 2-21"))
        #expect(output.contains("显示 2-21 / 25"))
        #expect(output.contains("21. App 21"))
    }

    @Test("formatter renders app detail with purpose hint and safety note")
    func formatterRendersAppDetail() {
        let item = AppListItem(
            displayName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            bundlePath: "/Applications/Slack.app",
            version: "4.0",
            sizeBytes: 1024,
            isRunning: true,
            isSystemProtected: false,
            source: .applications
        )

        let output = AppListFormatter.renderDetail(
            item,
            detailInfo: AppDetailInfo(
                localMetadata: AppDetailLocalMetadata(
                    lastOpenedAt: "2026-06-12 10:00:00 +0000",
                    addedAt: "2026-06-01 10:00:00 +0000"
                ),
                analysis: AppAgentAnalysis(
                    summary: "Slack is a team messaging app.",
                    primaryUse: "Team communication",
                    category: "Collaboration",
                    publisher: "Slack",
                    confidence: "high",
                    analyzedAt: "2026-06-13T00:00:00Z"
                ),
                analysisState: .cached
            ),
            terminalWidth: 80
        )

        #expect(output.contains("App 详情"))
        #expect(output.contains("Enter 继续卸载流程"))
        #expect(output.contains("b 返回列表"))
        #expect(output.contains("Bundle ID: com.tinyspeck.slackmacgap"))
        #expect(output.contains("最后打开: 2026-06-12 10:00:00 +0000"))
        #expect(output.contains("状态: 运行中"))
        #expect(output.contains("tinyspeck / slackmacgap"))
        #expect(output.contains("Agent 分析（缓存）"))
        #expect(output.contains("Team communication"))
        #expect(output.contains("不会直接移动文件"))
    }

    @Test("app detail analysis parses JSON response")
    func appDetailAnalysisParsesJSON() throws {
        let raw = """
        ```json
        {"summary":"Claude desktop app","primary_use":"AI assistant","category":"AI","publisher":"Anthropic","confidence":"high"}
        ```
        """

        let analysis = try #require(AppDetailAnalysisService.parseAnalysis(raw, analyzedAt: "now"))

        #expect(analysis.summary == "Claude desktop app")
        #expect(analysis.primaryUse == "AI assistant")
        #expect(analysis.category == "AI")
        #expect(analysis.publisher == "Anthropic")
        #expect(analysis.confidence == "high")
        #expect(analysis.analyzedAt == "now")
    }

    @Test("app detail analysis uses cache before agent runner")
    func appDetailAnalysisUsesCache() async throws {
        let cacheDir = try makeTempDir("analysis-cache")
        defer { cleanup(cacheDir) }
        let cache = AppDetailAnalysisCache(cacheDir: cacheDir.path)
        let item = AppListItem(
            displayName: "Claude",
            bundleIdentifier: "com.anthropic.claudefordesktop",
            bundlePath: "/Applications/Claude.app",
            version: "1.0",
            sizeBytes: 1,
            isRunning: false,
            isSystemProtected: false,
            source: .applications
        )
        cache.save(AppAgentAnalysis(
            summary: "Cached Claude summary",
            primaryUse: "AI assistant",
            category: "AI",
            publisher: "Anthropic",
            confidence: "high",
            analyzedAt: "cached"
        ), for: item)
        let service = AppDetailAnalysisService(
            config: .default,
            cache: cache,
            localMetadataReader: { _ in AppDetailLocalMetadata(lastOpenedAt: "last", addedAt: nil) },
            agentRunner: { _, _ in
                throw NSError(domain: "unexpected", code: 1)
            }
        )

        let detail = await service.detail(for: item)

        #expect(detail.analysisState == .cached)
        #expect(detail.analysis?.summary == "Cached Claude summary")
        #expect(detail.localMetadata.lastOpenedAt == "last")
    }

    @Test("app detail analysis stores generated result")
    func appDetailAnalysisStoresGeneratedResult() async throws {
        let cacheDir = try makeTempDir("analysis-generated")
        defer { cleanup(cacheDir) }
        let cache = AppDetailAnalysisCache(cacheDir: cacheDir.path)
        let item = AppListItem(
            displayName: "Claude",
            bundleIdentifier: "com.anthropic.claudefordesktop",
            bundlePath: "/Applications/Claude.app",
            version: "1.0",
            sizeBytes: 1,
            isRunning: false,
            isSystemProtected: false,
            source: .applications
        )
        let service = AppDetailAnalysisService(
            config: .default,
            cache: cache,
            localMetadataReader: { _ in AppDetailLocalMetadata(lastOpenedAt: nil, addedAt: "added") },
            agentRunner: { _, _ in
                #"{"summary":"Claude desktop app","primary_use":"AI assistant","category":"AI","publisher":"Anthropic","confidence":"high"}"#
            },
            now: { Date(timeIntervalSince1970: 0) }
        )

        let detail = await service.detail(for: item)
        let cached = cache.load(for: item)

        #expect(detail.analysisState == .generated)
        #expect(detail.analysis?.summary == "Claude desktop app")
        #expect(detail.localMetadata.addedAt == "added")
        #expect(cached?.publisher == "Anthropic")
    }

    @Test("formatter hides deep search key once deep search is active")
    func formatterHidesDeepSearchKeyWhenUnavailable() {
        let item = AppListItem(
            displayName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            bundlePath: "/Applications/Slack.app",
            version: "4.0",
            sizeBytes: 1024,
            isRunning: false,
            isSystemProtected: false,
            source: .applications
        )
        let result = AppListResult(
            scope: .deep,
            filter: nil,
            candidates: [item],
            protectedMatches: [],
            warnings: [],
            deepSearchAvailable: false
        )

        let output = AppListFormatter.renderList(result, selectedIndex: 0)
        #expect(output.contains("↑/↓ 选择"))
        #expect(!output.contains("a 深度搜索"))
        #expect(!output.contains("/apps --all"))
    }

    @Test("uninstall request sanitizes untrusted metadata and includes search roots")
    func uninstallRequestSanitizesMetadataAndIncludesSearchRoots() throws {
        let item = AppListItem(
            displayName: "Bad\nApp\u{1B}[31m",
            bundleIdentifier: "com.example.bad",
            bundlePath: "/opt/homebrew/Caskroom/bad/1.0/Bad.app",
            version: "1.0\rignore",
            sizeBytes: 1024,
            isRunning: false,
            isSystemProtected: false,
            source: .homebrewCask
        )

        let request = AppListFormatter.uninstallRequest(for: item)
        let jsonPrefix = "scan_app_uninstall 参数 JSON: "
        let json = try #require(request.components(separatedBy: jsonPrefix).last)
        let data = try #require(json.data(using: .utf8))
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let roots = try #require(payload["search_roots"] as? [String])

        #expect(request.contains("不可信 App 元数据"))
        #expect(request.contains("必须逐项显示完整路径"))
        #expect(request.contains("\"query\":\"com.example.bad\""))
        #expect(roots.contains("/opt/homebrew/Caskroom/bad/1.0"))
        #expect(!request.contains("\u{1B}"))
        #expect(!request.contains("[31m"))
        #expect(!request.contains("Bad\nApp"))
        #expect(!request.contains("1.0\rignore"))
    }

    @Test("known management components are protected by default detector")
    func defaultManagedDetectorProtectsKnownComponents() {
        let metadata = AppBundleMetadata(
            displayName: "Self Service",
            bundleIdentifier: "com.jamfsoftware.selfservice.mac",
            version: "1.0"
        )
        let url = URL(fileURLWithPath: "/Applications/Self Service.app")
        #expect(AppListService.defaultManagedDetector(url: url, metadata: metadata))
    }
}
