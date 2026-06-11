import Testing
import Foundation

@testable import AxionCLI
import AxionCore

@Suite("App Uninstall Plan Builder")
struct AppUninstallPlanBuilderTests {

    private let appsRoots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: NSString("~/Applications").expandingTildeInPath)]

    private func makeBuilder(
        candidates: [AppCandidate],
        items: [SupportDataItem] = [],
        hints: [ExternalUninstallHint] = []
    ) -> AppUninstallPlanBuilder {
        AppUninstallPlanBuilder(
            supportDataScanner: MockSupportDataScanner(items: items),
            appDiscoverer: MockAppDiscoverer(candidates: candidates),
            hintReader: MockExternalHintReader(hints: hints)
        )
    }

    // MARK: - AC #2: 多候选不自动执行

    @Test("multiple candidates with no unique high-confidence match → ambiguous_match blocked")
    func ambiguousMatchBlocks() async {
        // 两个 medium 候选，无 high 唯一解
        let builder = makeBuilder(candidates: [
            makeCandidate(bundleId: "com.example.foo1", displayName: "Foo One", matchConfidence: .medium),
            makeCandidate(bundleId: "com.example.foo2", displayName: "Foo Two", matchConfidence: .medium),
        ])
        let plan = await builder.build(query: "foo", mode: .uninstallWithSupportReview, homeDirectory: "/tmp", searchRoots: appsRoots)

        #expect(plan.blockedReasons.contains("ambiguous_match") == true)
        #expect(plan.candidates.count == 2)
        // app 取最高置信度占位（首位，medium）
        #expect(plan.app.bundleIdentifier == "com.example.foo1")
    }

    @Test("single high-confidence candidate is not ambiguous")
    func singleHighConfidenceNotBlocked() async {
        let builder = makeBuilder(candidates: [
            makeCandidate(matchConfidence: .high),
        ])
        let plan = await builder.build(query: "com.example.foo", mode: .uninstallWithSupportReview, homeDirectory: "/tmp", searchRoots: appsRoots)

        #expect(plan.blockedReasons.contains("ambiguous_match") == false)
        #expect(plan.blockedReasons.isEmpty == true)
    }

    @Test("no candidates → no_match blocked")
    func noMatchBlocked() async {
        let builder = makeBuilder(candidates: [])
        let plan = await builder.build(query: "ghost", mode: .uninstallWithSupportReview, homeDirectory: "/tmp", searchRoots: appsRoots)

        #expect(plan.blockedReasons.contains("no_match") == true)
        #expect(plan.app.bundleIdentifier == "")
    }

    // MARK: - AC #4: 系统保护 / outside_applications_dirs

    @Test("system-protected app → system_protected blocked")
    func systemProtectedBlocks() async {
        let builder = makeBuilder(candidates: [makeCandidate(isSystemProtected: true)])
        let plan = await builder.build(query: "com.apple.foo", mode: .uninstallWithSupportReview, homeDirectory: "/tmp", searchRoots: appsRoots)

        #expect(plan.blockedReasons.contains("system_protected") == true)
    }

    @Test("bundle outside applications dirs → outside_applications_dirs blocked")
    func outsideApplicationsDirsBlocks() async {
        let builder = makeBuilder(candidates: [
            makeCandidate(bundlePath: "/Users/nick/Downloads/Foo.app"),
        ])
        let plan = await builder.build(query: "Foo", mode: .uninstallWithSupportReview, homeDirectory: "/tmp", searchRoots: appsRoots)

        #expect(plan.blockedReasons.contains("outside_applications_dirs") == true)
        #expect(plan.blockedReasons.contains("system_protected") == false)
    }

    // MARK: - AC #7: 低置信度分流到 hintOnly

    @Test("low-confidence support items routed to hintOnly, medium/high to executable set")
    func lowConfidenceRoutedToHintOnly() async {
        let items = [
            makeSupportItem(category: .cache, matchConfidence: .high, dataRisk: .low),
            makeSupportItem(category: .groupContainer, matchConfidence: .low, dataRisk: .high),
        ]
        let builder = makeBuilder(candidates: [makeCandidate()], items: items)
        let plan = await builder.build(query: "Foo", mode: .uninstallWithSupportReview, homeDirectory: "/tmp", searchRoots: appsRoots)

        #expect(plan.supportDataItems.count == 1)
        #expect(plan.supportDataItems.first?.matchConfidence == .high)
        #expect(plan.hintOnlySupportDataItems.count == 1)
        #expect(plan.hintOnlySupportDataItems.first?.matchConfidence == .low)
    }

    // MARK: - AC #6: 高风险 → defaultSelected=false + requiresTypedConfirmation

    @Test("high-risk item → defaultSelected false, requiresTypedConfirmation true, dataLossRisk high")
    func highRiskSetsTypedConfirmation() async {
        let items = [
            makeSupportItem(category: .container, matchConfidence: .high, dataRisk: .high,
                            defaultSelected: false, requiresExplicitApproval: true),
        ]
        let builder = makeBuilder(candidates: [makeCandidate()], items: items)
        let plan = await builder.build(query: "Foo", mode: .uninstallWithSupportReview, homeDirectory: "/tmp", searchRoots: appsRoots)

        #expect(plan.supportDataItems.first?.defaultSelected == false)
        #expect(plan.dataLossRisk == .high)
        #expect(plan.requiresTypedConfirmation == true)
    }

    @Test("shared-directory-derived item (medium conf, high risk, not selected) upgrades plan risk")
    func sharedDirectoryUpgradesRisk() async {
        // 模拟 assembleItem 对共享目录升级后的产物：medium 置信度但 dataRisk 被强制 high、不默认选
        let items = [
            makeSupportItem(category: .groupContainer, matchConfidence: .medium, dataRisk: .high,
                            defaultSelected: false, requiresExplicitApproval: true),
        ]
        let builder = makeBuilder(candidates: [makeCandidate()], items: items)
        let plan = await builder.build(query: "Foo", mode: .uninstallWithSupportReview, homeDirectory: "/tmp", searchRoots: appsRoots)

        #expect(plan.dataLossRisk == .high)
        #expect(plan.requiresTypedConfirmation == true)
    }

    @Test("low-risk only plan → no typed confirmation")
    func lowRiskNoConfirmation() async {
        let items = [
            makeSupportItem(category: .cache, matchConfidence: .high, dataRisk: .low, defaultSelected: true),
        ]
        let builder = makeBuilder(candidates: [makeCandidate()], items: items)
        let plan = await builder.build(query: "Foo", mode: .uninstallWithSupportReview, homeDirectory: "/tmp", searchRoots: appsRoots)

        #expect(plan.dataLossRisk == .low)
        #expect(plan.requiresTypedConfirmation == false)
    }

    // MARK: - dataLossRisk 聚合

    @Test("dataLossRisk aggregates to the highest risk level")
    func dataLossRiskAggregation() async {
        // low + medium → medium
        var builder = makeBuilder(candidates: [makeCandidate()], items: [
            makeSupportItem(matchConfidence: .high, dataRisk: .low),
            makeSupportItem(matchConfidence: .high, dataRisk: .medium),
        ])
        var plan = await builder.build(query: "Foo", mode: .uninstallWithSupportReview, homeDirectory: "/tmp", searchRoots: appsRoots)
        #expect(plan.dataLossRisk == .medium)

        // empty → none
        builder = makeBuilder(candidates: [makeCandidate()], items: [])
        plan = await builder.build(query: "Foo", mode: .uninstallWithSupportReview, homeDirectory: "/tmp", searchRoots: appsRoots)
        #expect(plan.dataLossRisk == .none)
    }

    // MARK: - AC #11: 外部提示只读，不改风险

    @Test("external hints passed through, do not change risk strategy")
    func externalHintsReadOnly() async {
        let hints = [
            ExternalUninstallHint(source: "pkg_receipt", detail: "r1", paths: ["/var/db/receipts/com.example.foo.plist"]),
            ExternalUninstallHint(source: "homebrew_cask", detail: "cask", paths: ["/opt/homebrew/Caskroom/foo"]),
        ]
        let builder = makeBuilder(candidates: [makeCandidate()], items: [
            makeSupportItem(matchConfidence: .high, dataRisk: .low),
        ], hints: hints)
        let plan = await builder.build(query: "Foo", mode: .uninstallWithSupportReview, homeDirectory: "/tmp", searchRoots: appsRoots)

        #expect(plan.externalUninstallHints.count == 2)
        // hints 不影响风险策略
        #expect(plan.dataLossRisk == .low)
        #expect(plan.requiresTypedConfirmation == false)
    }

    // MARK: - isInside pure helper

    @Test("isInside detects bundle under search roots")
    func isInsideRoots() {
        let roots = [URL(fileURLWithPath: "/Applications")]
        #expect(AppUninstallPlanBuilder.isInside("/Applications/Foo.app", roots) == true)
        #expect(AppUninstallPlanBuilder.isInside("/Applications", roots) == true)
        #expect(AppUninstallPlanBuilder.isInside("/Users/x/Downloads/Foo.app", roots) == false)
        // 不应误判前缀子串（/Application 不应匹配 /Applications）
        #expect(AppUninstallPlanBuilder.isInside("/ApplicationFoo", roots) == false)
    }
}
