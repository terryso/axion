import Testing
import Foundation
import OpenAgentSDK

import AxionCore
@testable import AxionCLI

@Suite("Scan App Uninstall Tool")
struct ScanAppUninstallToolTests {

    /// 捕获 query/searchRoots 的发现器（验证工具默认根 + 透传参数）。
    private final class CapturingDiscoverer: AppDiscovering, @unchecked Sendable {
        private(set) var lastQuery: String = ""
        private(set) var lastRoots: [URL] = []
        let candidates: [AppCandidate]
        init(candidates: [AppCandidate]) { self.candidates = candidates }
        func discover(query: String, searchRoots: [URL]) async -> [AppCandidate] {
            lastQuery = query
            lastRoots = searchRoots
            return candidates
        }
    }

    private func makeContext() -> ToolContext {
        ToolContext(cwd: "/tmp", toolUseId: "scan-app-\(UUID().uuidString)")
    }

    private func makeTool(discoverer: AppDiscovering, items: [SupportDataItem] = [], hints: [ExternalUninstallHint] = []) -> ScanAppUninstallTool {
        ScanAppUninstallTool(planBuilder: AppUninstallPlanBuilder(
            supportDataScanner: MockSupportDataScanner(items: items),
            appDiscoverer: discoverer,
            hintReader: MockExternalHintReader(hints: hints)
        ))
    }

    @Test("tool scans and returns a plan for a valid query")
    func toolScansAndReturnsPlan() async throws {
        let discoverer = CapturingDiscoverer(candidates: [makeCandidate()])
        let tool = makeTool(
            discoverer: discoverer,
            items: [makeSupportItem(category: .cache, matchConfidence: .high, dataRisk: .low)]
        )

        let result = await tool.call(
            input: ["query": "com.example.foo"] as [String: Any],
            context: makeContext()
        )

        #expect(!result.isError)
        let plan = try JSONDecoder().decode(AppUninstallPlan.self, from: Data(result.content.utf8))
        #expect(plan.app.bundleIdentifier == "com.example.foo")
        #expect(plan.uninstallMode == .uninstallWithSupportReview)  // 默认模式
        #expect(plan.supportDataItems.count == 1)
        #expect(discoverer.lastQuery == "com.example.foo")
    }

    @Test("tool rejects missing query")
    func toolRejectsMissingQuery() async throws {
        let tool = makeTool(discoverer: CapturingDiscoverer(candidates: []))
        let result = await tool.call(input: ["mode": "scan_only"] as [String: Any], context: makeContext())
        #expect(result.isError)
        #expect(result.content.contains("missing_query"))
    }

    @Test("tool rejects non-object input")
    func toolRejectsNonObjectInput() async throws {
        let tool = makeTool(discoverer: CapturingDiscoverer(candidates: []))
        let result = await tool.call(input: "bad", context: makeContext())
        #expect(result.isError)
        #expect(result.content.contains("invalid_input"))
    }

    @Test("tool uses default search roots when omitted")
    func toolUsesDefaultSearchRoots() async throws {
        let discoverer = CapturingDiscoverer(candidates: [])
        let tool = makeTool(discoverer: discoverer)

        _ = await tool.call(input: ["query": "ghost"] as [String: Any], context: makeContext())

        // 默认根 ["/Applications", "~/Applications"] 展开 ~ 后透传给发现器（两个、均以 /Applications 结尾）。
        let rootPaths = discoverer.lastRoots.map(\.path)
        #expect(rootPaths.count == 2)
        #expect(rootPaths.contains("/Applications"))
        // 另一个是用户主目录下的 ~/Applications（展开后 ≠ /System 的 /Applications）
        let userApps = rootPaths.first { $0 != "/Applications" }
        #expect(userApps?.hasSuffix("/Applications") == true)
    }

    @Test("tool passes through explicit mode and search roots")
    func toolPassesThroughExplicitModeAndRoots() async throws {
        let discoverer = CapturingDiscoverer(candidates: [makeCandidate()])
        let tool = makeTool(discoverer: discoverer)

        let result = await tool.call(
            input: [
                "query": "Foo",
                "mode": "scan_only",
                "search_roots": ["/Custom/Apps"],
            ] as [String: Any],
            context: makeContext()
        )

        #expect(!result.isError)
        let plan = try JSONDecoder().decode(AppUninstallPlan.self, from: Data(result.content.utf8))
        #expect(plan.uninstallMode == .scanOnly)
        #expect(discoverer.lastRoots.map(\.path) == ["/Custom/Apps"])
    }

    @Test("tool surfaces blocked reasons for ambiguous match")
    func toolSurfacesAmbiguousMatch() async throws {
        let discoverer = CapturingDiscoverer(candidates: [
            makeCandidate(bundleId: "com.example.foo1", displayName: "Foo One", matchConfidence: .medium),
            makeCandidate(bundleId: "com.example.foo2", displayName: "Foo Two", matchConfidence: .medium),
        ])
        let tool = makeTool(discoverer: discoverer)

        let result = await tool.call(input: ["query": "foo"] as [String: Any], context: makeContext())
        #expect(!result.isError)
        let plan = try JSONDecoder().decode(AppUninstallPlan.self, from: Data(result.content.utf8))
        #expect(plan.blockedReasons.contains("ambiguous_match") == true)
    }

    @Test("default search roots constant")
    func defaultSearchRootsConstant() {
        #expect(ScanAppUninstallTool.defaultSearchRoots == ["/Applications", "~/Applications"])
    }
}
