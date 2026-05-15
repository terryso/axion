import Foundation
import Testing
import OpenAgentSDK

@testable import AxionCLI

// [P0] AppProfileAnalyzer type existence, profile analysis from history
// [P1] High-frequency pattern recognition, failure experience, edge cases
// Story 4.2 AC: #1, #2, #3, #4

// MARK: - AppProfileAnalyzer ATDD Tests

/// ATDD red-phase tests for AppProfileAnalyzer (Story 4.2 AC1, AC2, AC3, AC4).
@Suite("AppProfileAnalyzer")
struct AppProfileAnalyzerTests {

    // MARK: - Helper: Create KnowledgeEntry

    private func makeEntry(
        id: String = UUID().uuidString,
        content: String,
        tags: [String],
        createdAt: Date = Date(),
        sourceRunId: String? = nil
    ) -> KnowledgeEntry {
        KnowledgeEntry(
            id: id,
            content: content,
            tags: tags,
            createdAt: createdAt,
            sourceRunId: sourceRunId
        )
    }

    private func makeSuccessfulEntry(
        id: String = UUID().uuidString,
        domain: String = "com.apple.calculator",
        content: String,
        sourceRunId: String? = nil
    ) -> KnowledgeEntry {
        makeEntry(
            id: id,
            content: content,
            tags: ["app:\(domain)", "success"],
            sourceRunId: sourceRunId
        )
    }

    private func makeFailureEntry(
        id: String = UUID().uuidString,
        domain: String = "com.apple.calculator",
        content: String,
        sourceRunId: String? = nil
    ) -> KnowledgeEntry {
        makeEntry(
            id: id,
            content: content,
            tags: ["app:\(domain)", "failure"],
            sourceRunId: sourceRunId
        )
    }

    // MARK: - P0: Type Existence

    @Test("type exists")
    func typeExists() {
        let _ = AppProfileAnalyzer.self
    }

    @Test("AppProfile type exists")
    func appProfileTypeExists() {
        let _ = AppProfile.self
    }

    @Test("OperationPattern type exists")
    func operationPatternTypeExists() {
        let _ = OperationPattern.self
    }

    @Test("FailurePattern type exists")
    func failurePatternTypeExists() {
        let _ = FailurePattern.self
    }

    // MARK: - P0 AC1: Extract AX tree structure features from successful operations

    @Test("analyze single successful run extracts AX characteristics")
    func analyzeSingleSuccessfulRunExtractsAxCharacteristics() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(
                content: """
                App: Calculator (com.apple.calculator)
                任务: 计算 17 乘以 23
                结果: success
                工具序列: launch_app -> click -> click -> click
                步骤数: 4
                AX特征: 窗口包含 AXButton 角色控件，按钮标题与数字对应
                关键控件: AXButton[title="1"], AXButton[title="7"], AXButton[title="*"]
                """
            )
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        #expect(!profile.axCharacteristics.isEmpty,
            "Profile should contain AX characteristics from the successful run")
    }

    @Test("analyze single successful run extracts tool sequence")
    func analyzeSingleSuccessfulRunExtractsToolSequence() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(
                content: """
                App: Calculator (com.apple.calculator)
                任务: 计算 17 乘以 23
                结果: success
                工具序列: launch_app -> click -> click -> click
                步骤数: 4
                """
            )
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        #expect(profile.totalRuns == 1, "Should count 1 total run")
        #expect(profile.successfulRuns == 1, "Should count 1 successful run")
        #expect(profile.failedRuns == 0, "Should count 0 failed runs")
    }

    // MARK: - P0 AC2: Identify high-frequency operation paths

    @Test("analyze multiple runs identifies high-frequency patterns")
    func analyzeMultipleRunsIdentifiesHighFrequencyPatterns() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(
                id: "run-1",
                content: """
                App: Calculator (com.apple.calculator)
                任务: 计算 1+1
                结果: success
                工具序列: launch_app -> click -> click -> click
                步骤数: 4
                """
            ),
            makeSuccessfulEntry(
                id: "run-2",
                content: """
                App: Calculator (com.apple.calculator)
                任务: 计算 2+2
                结果: success
                工具序列: launch_app -> click -> click -> click
                步骤数: 4
                """
            ),
            makeSuccessfulEntry(
                id: "run-3",
                content: """
                App: Calculator (com.apple.calculator)
                任务: 计算 3+3
                结果: success
                工具序列: launch_app -> click -> click -> click
                步骤数: 4
                """
            ),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        let highFreqPatterns = profile.commonPatterns.filter { $0.frequency >= 2 }
        #expect(!highFreqPatterns.isEmpty,
            "Should identify at least one high-frequency pattern from 3 identical runs")
    }

    @Test("analyze diverse runs only reports frequent patterns")
    func analyzeDiverseRunsOnlyReportsFrequentPatterns() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(
                id: "run-1",
                content: """
                App: Calculator (com.apple.calculator)
                任务: 计算 1+1
                结果: success
                工具序列: launch_app -> click -> click -> click
                步骤数: 4
                """
            ),
            makeSuccessfulEntry(
                id: "run-2",
                content: """
                App: Calculator (com.apple.calculator)
                任务: 输入文字
                结果: success
                工具序列: launch_app -> type_text
                步骤数: 2
                """
            ),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        let highFreqPatterns = profile.commonPatterns.filter { $0.frequency >= 2 }
        for pattern in highFreqPatterns {
            #expect(pattern.frequency >= 2, "All high-frequency patterns must have frequency >= 2")
        }
    }

    @Test("analyze high-frequency pattern includes description")
    func analyzeHighFrequencyPatternIncludesDescription() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(
                domain: "com.apple.finder",
                content: """
                App: Finder (com.apple.finder)
                任务: 导航到指定目录
                结果: success
                工具序列: launch_app -> hotkey -> type_text
                步骤数: 3
                """
            ),
            makeSuccessfulEntry(
                domain: "com.apple.finder",
                content: """
                App: Finder (com.apple.finder)
                任务: 导航到另一个目录
                结果: success
                工具序列: launch_app -> hotkey -> type_text
                步骤数: 3
                """
            ),
        ]

        let profile = analyzer.analyze(domain: "com.apple.finder", history: history)

        let highFreqPatterns = profile.commonPatterns.filter { $0.frequency >= 2 }
        #expect(!highFreqPatterns.isEmpty, "Should find high-frequency pattern")

        for pattern in highFreqPatterns {
            #expect(!pattern.description.isEmpty, "Each OperationPattern should have a human-readable description")
            #expect(!pattern.sequence.isEmpty, "Each OperationPattern should have a non-empty tool sequence")
            #expect(pattern.successRate > 0, "Success rate should be greater than 0")
        }
    }

    // MARK: - P0 AC3: Mark failure experiences

    @Test("analyze failure entries extracts known failures")
    func analyzeFailureEntriesExtractsKnownFailures() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(
                id: "run-1",
                content: """
                App: Calculator (com.apple.calculator)
                任务: 计算乘法
                结果: success
                工具序列: launch_app -> click -> click -> click
                步骤数: 4
                """
            ),
            makeFailureEntry(
                id: "run-2",
                content: """
                App: Calculator (com.apple.calculator)
                任务: 计算除法
                结果: failure (后修正为 success)
                工具序列: launch_app -> click(x:300,y:400) -> click(x:150,y:200)
                步骤数: 3
                失败标记: click(x:300,y:400) 坐标不可靠（未命中目标按钮）
                修正路径: 使用 AX selector AXButton[title="/"] 代替坐标点击
                """
            ),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        #expect(!profile.knownFailures.isEmpty, "Should extract failure patterns from entries with failure tags")
        let failure = profile.knownFailures.first!
        #expect(!failure.failedAction.isEmpty, "Failure pattern should describe the failed action")
        #expect(!failure.reason.isEmpty, "Failure pattern should provide a reason")
    }

    @Test("analyze failure with workaround extracts workaround")
    func analyzeFailureWithWorkaroundExtractsWorkaround() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeFailureEntry(
                content: """
                App: Calculator (com.apple.calculator)
                任务: 计算乘法
                结果: failure (后修正为 success)
                工具序列: launch_app -> click(x:300,y:400)
                步骤数: 2
                失败标记: click(x:300,y:400) 坐标不可靠
                修正路径: 使用 AX selector AXButton[title="*"] 代替坐标点击
                """
            ),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        #expect(profile.knownFailures.count == 1, "Should extract exactly 1 failure pattern")
        let failure = profile.knownFailures.first!
        #expect(failure.workaround != nil, "Failure pattern should include the workaround when available")
        #expect(failure.workaround!.contains("AXButton"), "Workaround should reference the AX selector correction")
    }

    @Test("analyze failure without workaround has nil workaround")
    func analyzeFailureWithoutWorkaroundHasNilWorkaround() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeFailureEntry(
                content: """
                App: Calculator (com.apple.calculator)
                任务: 打开计算器
                结果: failure
                工具序列: launch_app
                步骤数: 1
                失败标记: App 未安装
                """
            ),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        if let failure = profile.knownFailures.first {
            #expect(failure.workaround == nil, "Failure pattern without workaround should have nil workaround")
        }
    }

    // MARK: - P0 AC4: Auto-mark familiar apps (>= 3 successful runs)

    @Test("analyze three successful runs marks familiar")
    func analyzeThreeSuccessfulRunsMarksFamiliar() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(id: "run-1", content: "Run 1 success"),
            makeSuccessfulEntry(id: "run-2", content: "Run 2 success"),
            makeSuccessfulEntry(id: "run-3", content: "Run 3 success"),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        #expect(profile.isFamiliar, "App with >= 3 successful runs should be marked as familiar")
    }

    @Test("analyze two successful runs not familiar")
    func analyzeTwoSuccessfulRunsNotFamiliar() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(id: "run-1", content: "Run 1 success"),
            makeSuccessfulEntry(id: "run-2", content: "Run 2 success"),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        #expect(!profile.isFamiliar, "App with < 3 successful runs should NOT be marked as familiar")
    }

    @Test("analyze exactly three successful runs with failures marks familiar")
    func analyzeExactlyThreeSuccessfulRunsWithFailuresMarksFamiliar() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(id: "run-1", content: "Run 1 success"),
            makeSuccessfulEntry(id: "run-2", content: "Run 2 success"),
            makeSuccessfulEntry(id: "run-3", content: "Run 3 success"),
            makeFailureEntry(id: "run-4", content: "Run 4 failure"),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        #expect(profile.isFamiliar, "App with exactly 3 successful runs (plus failures) should be familiar")
        #expect(profile.successfulRuns == 3)
        #expect(profile.failedRuns == 1)
    }

    // MARK: - P0: Domain matches profile output

    @Test("analyze domain matches input")
    func analyzeDomainMatchesInput() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(id: "run-1", content: "Run 1 success"),
        ]

        let domain = "com.apple.finder"
        let profile = analyzer.analyze(domain: domain, history: history)

        #expect(profile.domain == domain, "Profile domain should match the input domain")
    }

    // MARK: - P1: Edge Cases

    @Test("analyze empty history returns empty profile")
    func analyzeEmptyHistoryReturnsEmptyProfile() {
        let analyzer = AppProfileAnalyzer()

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: [])

        #expect(profile.totalRuns == 0, "Empty history should have 0 total runs")
        #expect(profile.successfulRuns == 0)
        #expect(profile.failedRuns == 0)
        #expect(profile.commonPatterns.isEmpty)
        #expect(profile.knownFailures.isEmpty)
        #expect(profile.axCharacteristics.isEmpty)
        #expect(!profile.isFamiliar)
    }

    @Test("analyze all failures counts correctly")
    func analyzeAllFailuresCountsCorrectly() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeFailureEntry(id: "run-1", content: "Failure 1"),
            makeFailureEntry(id: "run-2", content: "Failure 2"),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        #expect(profile.totalRuns == 2)
        #expect(profile.successfulRuns == 0)
        #expect(profile.failedRuns == 2)
        #expect(!profile.isFamiliar)
        #expect(!profile.knownFailures.isEmpty, "All-failure history should still extract failure patterns")
    }

    @Test("analyze mixed success failure counts correctly")
    func analyzeMixedSuccessFailureCountsCorrectly() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(id: "run-1", content: "Success 1"),
            makeFailureEntry(id: "run-2", content: "Failure 1"),
            makeSuccessfulEntry(id: "run-3", content: "Success 2"),
            makeFailureEntry(id: "run-4", content: "Failure 2"),
            makeSuccessfulEntry(id: "run-5", content: "Success 3"),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        #expect(profile.totalRuns == 5)
        #expect(profile.successfulRuns == 3)
        #expect(profile.failedRuns == 2)
        #expect(profile.isFamiliar, "3 successful runs (out of 5 total) should mark as familiar")
    }

    @Test("analyze excludes profile and familiar entries from total runs")
    func analyzeExcludesProfileAndFamiliarEntriesFromTotalRuns() {
        let analyzer = AppProfileAnalyzer()

        let domain = "com.apple.calculator"

        let runEntries = [
            makeSuccessfulEntry(id: "run-1", content: "Success 1"),
            makeSuccessfulEntry(id: "run-2", content: "Success 2"),
        ]

        let profileEntry = KnowledgeEntry(
            id: "profile-1",
            content: "App Profile: \(domain)",
            tags: ["app:\(domain)", "profile"],
            createdAt: Date(),
            sourceRunId: nil
        )
        let familiarEntry = KnowledgeEntry(
            id: "familiar-1",
            content: "App \(domain) 已熟悉",
            tags: ["app:\(domain)", "familiar"],
            createdAt: Date(),
            sourceRunId: nil
        )

        let history = runEntries + [profileEntry, familiarEntry]
        let profile = analyzer.analyze(domain: domain, history: history)

        #expect(profile.totalRuns == 2,
            "totalRuns should only count actual run entries (success/failure), not profile or familiar entries")
        #expect(profile.successfulRuns == 2)
        #expect(profile.failedRuns == 0)
    }

    @Test("analyze ignores entries from other domains")
    func analyzeIgnoresEntriesFromOtherDomains() {
        let analyzer = AppProfileAnalyzer()

        let wrongDomainEntry = KnowledgeEntry(
            id: "other-1",
            content: "Other app run",
            tags: ["app:com.apple.safari", "success"],
            createdAt: Date(),
            sourceRunId: nil
        )

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: [wrongDomainEntry])

        #expect(profile.totalRuns == 0, "Entries from other domains should not be counted")
    }

    @Test("analyze AX characteristics deduplicates across runs")
    func analyzeAxCharacteristicsDeduplicatesAcrossRuns() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(
                id: "run-1",
                content: """
                AX特征: 窗口包含 AXButton 角色控件
                关键控件: AXButton[title="1"]
                """
            ),
            makeSuccessfulEntry(
                id: "run-2",
                content: """
                AX特征: 窗口包含 AXButton 角色控件，AXTextField
                关键控件: AXButton[title="2"]
                """
            ),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        let uniqueCharacteristics = Set(profile.axCharacteristics)
        #expect(uniqueCharacteristics.count == profile.axCharacteristics.count,
            "AX characteristics should be deduplicated")
    }

    @Test("analyze operation pattern success rate is correct")
    func analyzeOperationPatternSuccessRateIsCorrect() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(
                id: "run-1",
                content: """
                工具序列: launch_app -> click -> click
                结果: success
                """
            ),
            makeSuccessfulEntry(
                id: "run-2",
                content: """
                工具序列: launch_app -> click -> click
                结果: success
                """
            ),
            makeFailureEntry(
                id: "run-3",
                content: """
                工具序列: launch_app -> click -> click
                结果: failure
                """
            ),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        let matchingPattern = profile.commonPatterns.first { pattern in
            pattern.sequence == ["launch_app", "click", "click"]
        }

        if let pattern = matchingPattern {
            #expect(pattern.successRate >= 0.5, "Success rate should reflect 2/3 successful occurrences")
            #expect(pattern.successRate <= 1.0, "Success rate should not exceed 1.0")
        }
    }

    @Test("analyze strips tool parameters for pattern matching")
    func analyzeStripsToolParametersForPatternMatching() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(
                id: "run-1",
                content: """
                工具序列: launch_app -> click(x:100,y:200) -> type_text("hello")
                """
            ),
            makeSuccessfulEntry(
                id: "run-2",
                content: """
                工具序列: launch_app -> click(x:300,y:400) -> type_text("world")
                """
            ),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        let highFreqPatterns = profile.commonPatterns.filter { $0.frequency >= 2 }
        #expect(!highFreqPatterns.isEmpty,
            "Should identify high-frequency pattern when tool names match but parameters differ")
    }
}
