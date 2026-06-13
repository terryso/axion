import Testing
import Foundation

@testable import AxionCLI
import AxionCore

@Suite("App Discovery (pure functions)")
struct AppDiscoveryTests {
    private func makeTempDir(_ label: String) throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("AppDiscoveryScratch", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dir = root.appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @discardableResult
    private func makeApp(
        root: URL,
        name: String,
        bundleId: String,
        displayName: String? = nil,
        version: String = "1.0",
        applicationIdentifier: String? = nil
    ) throws -> URL {
        let app = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleId,
            "CFBundleName": displayName ?? name,
            "CFBundleShortVersionString": version,
            "CFBundlePackageType": "APPL",
        ]
        if let applicationIdentifier {
            plist["ApplicationIdentifier"] = applicationIdentifier
        }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    // MARK: - discover

    @Test("discover reads app bundles, filters low matches, and sorts by confidence")
    func discoverReadsBundlesAndSortsByConfidence() async throws {
        let root = try makeTempDir("discover")
        defer { cleanup(root) }

        let highURL = try makeApp(
            root: root,
            name: "High",
            bundleId: "com.example.high",
            displayName: "High",
            version: "2.0",
            applicationIdentifier: "TEAM123.com.example.high"
        )
        try "payload".write(
            to: highURL.appendingPathComponent("Contents").appendingPathComponent("payload.txt"),
            atomically: true,
            encoding: .utf8
        )
        try makeApp(
            root: root,
            name: "Highlighter",
            bundleId: "com.example.highlighter",
            displayName: "Highlighter",
            version: "3.0"
        )
        try makeApp(
            root: root,
            name: "Other",
            bundleId: "com.example.other",
            displayName: "Other"
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Broken.app", isDirectory: true),
            withIntermediateDirectories: true
        )
        let missingRoot = root.appendingPathComponent("Missing", isDirectory: true)

        let candidates = try await AppDiscoveryService().discover(query: "High", searchRoots: [missingRoot, root])

        #expect(candidates.map(\.displayName) == ["High", "Highlighter"])
        #expect(candidates.map(\.matchConfidence) == [.high, .medium])
        #expect(candidates.first?.bundleIdentifier == "com.example.high")
        #expect(candidates.first?.version == "2.0")
        #expect(candidates.first?.teamIdentifier == "TEAM123")
        #expect(candidates.first?.isSystemProtected == false)
    }

    @Test("discover() throws CancellationError when cancelled mid-scan (cooperative)")
    func discoverCooperativelyCancels() async throws {
        let root = try makeTempDir("cancel")
        defer { cleanup(root) }
        // 足量 .app 目录确保遍历跨越多个取消检查点；无需有效 Info.plist（checkpoint 每 app 都跑）。
        for i in 0..<2000 {
            let app = root.appendingPathComponent("App\(i).app", isDirectory: true)
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        }
        let service = AppDiscoveryService()

        let task = _Concurrency.Task { try await service.discover(query: "App", searchRoots: [root]) }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("discover should throw CancellationError when cancelled, but completed")
        } catch is CancellationError {
            // 协作式取消生效（agent.interrupt() → _streamTask.cancel() → 此处抛出）
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    // MARK: - classifyMatch

    @Test("classifyMatch: exact bundle identifier is high")
    func classifyExactBundleId() {
        #expect(AppDiscoveryService.classifyMatch(
            query: "com.example.foo",
            bundleIdentifier: "com.example.foo",
            displayName: "Foo"
        ) == .high)
    }

    @Test("classifyMatch: exact display name (case-insensitive, .app stripped) is high")
    func classifyExactDisplayName() {
        #expect(AppDiscoveryService.classifyMatch(
            query: "Foo",
            bundleIdentifier: "com.example.foo",
            displayName: "Foo"
        ) == .high)
        #expect(AppDiscoveryService.classifyMatch(
            query: "foo",
            bundleIdentifier: "com.example.foo",
            displayName: "FOO"
        ) == .high)
        // query with .app suffix normalized
        #expect(AppDiscoveryService.classifyMatch(
            query: "Foo.app",
            bundleIdentifier: "com.example.foo",
            displayName: "Foo"
        ) == .high)
    }

    @Test("classifyMatch: bundle id prefix or name contains is medium")
    func classifyMedium() {
        // display name contains query
        #expect(AppDiscoveryService.classifyMatch(
            query: "Foo",
            bundleIdentifier: "com.example.foobar",
            displayName: "FooBar Pro"
        ) == .medium)
        // bundle id prefix (dotted reverse-DNS style)
        #expect(AppDiscoveryService.classifyMatch(
            query: "com.example",
            bundleIdentifier: "com.example.foo",
            displayName: "Foo"
        ) == .medium)
    }

    @Test("classifyMatch: unrelated input is low")
    func classifyLow() {
        #expect(AppDiscoveryService.classifyMatch(
            query: "TotallyDifferent",
            bundleIdentifier: "com.example.foo",
            displayName: "Foo"
        ) == .low)
        // empty query → low
        #expect(AppDiscoveryService.classifyMatch(
            query: "   ",
            bundleIdentifier: "com.example.foo",
            displayName: "Foo"
        ) == .low)
    }

    // MARK: - isSystemProtected

    @Test("isSystemProtected: Apple bundle id prefix is protected")
    func systemProtectedAppleBundleId() {
        #expect(AppDiscoveryService.isSystemProtected(
            bundlePath: "/Applications/Calculator.app",
            bundleIdentifier: "com.apple.calculator"
        ) == true)
    }

    @Test("isSystemProtected: system directory paths are protected")
    func systemProtectedSystemDirs() {
        #expect(AppDiscoveryService.isSystemProtected(
            bundlePath: "/System/Applications/Chess.app",
            bundleIdentifier: "com.apple.chess"
        ) == true)
        #expect(AppDiscoveryService.isSystemProtected(
            bundlePath: "/Library/SomeApp.app",
            bundleIdentifier: "com.vendor.someapp"
        ) == true)
        #expect(AppDiscoveryService.isSystemProtected(
            bundlePath: "/usr/local/bin/thing",
            bundleIdentifier: "com.vendor.thing"
        ) == true)
    }

    @Test("isSystemProtected: third-party app under /Applications is not protected")
    func systemNotProtectedThirdParty() {
        #expect(AppDiscoveryService.isSystemProtected(
            bundlePath: "/Applications/Foo.app",
            bundleIdentifier: "com.example.foo"
        ) == false)
        #expect(AppDiscoveryService.isSystemProtected(
            bundlePath: "/Users/nick/Applications/Bar.app",
            bundleIdentifier: "com.other.bar"
        ) == false)
    }
}
