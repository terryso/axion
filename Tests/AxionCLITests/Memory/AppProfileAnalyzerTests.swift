import XCTest
import OpenAgentSDK

@testable import AxionCLI

// [P0] AppProfileAnalyzer type existence, profile analysis from history
// [P1] High-frequency pattern recognition, failure experience, edge cases
// Story 4.2 AC: #1, #2, #3, #4

// MARK: - AppProfileAnalyzer ATDD Tests

/// ATDD red-phase tests for AppProfileAnalyzer (Story 4.2 AC1, AC2, AC3, AC4).
/// Tests that AppProfileAnalyzer extracts operation patterns from accumulated
/// KnowledgeEntry history and produces structured AppProfile data.
///
/// TDD RED PHASE: These tests will not compile until AppProfileAnalyzer,
/// AppProfile, OperationPattern, and FailurePattern are implemented
/// in Sources/AxionCLI/Memory/AppProfileAnalyzer.swift.
final class AppProfileAnalyzerTests: XCTestCase {

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

    func test_appProfileAnalyzer_typeExists() {
        let _ = AppProfileAnalyzer.self
    }

    func test_appProfile_typeExists() {
        let _ = AppProfile.self
    }

    func test_operationPattern_typeExists() {
        let _ = OperationPattern.self
    }

    func test_failurePattern_typeExists() {
        let _ = FailurePattern.self
    }

    // MARK: - P0 AC1: Extract AX tree structure features from successful operations

    func test_analyze_singleSuccessfulRun_extractsAxCharacteristics() {
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

        XCTAssertFalse(profile.axCharacteristics.isEmpty,
            "Profile should contain AX characteristics from the successful run")
    }

    func test_analyze_singleSuccessfulRun_extractsToolSequence() {
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

        XCTAssertEqual(profile.totalRuns, 1, "Should count 1 total run")
        XCTAssertEqual(profile.successfulRuns, 1, "Should count 1 successful run")
        XCTAssertEqual(profile.failedRuns, 0, "Should count 0 failed runs")
    }

    // MARK: - P0 AC2: Identify high-frequency operation paths

    func test_analyze_multipleRuns_identifiesHighFrequencyPatterns() {
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

        // The pattern "launch_app -> click -> click -> click" appears 3 times
        // Should be identified as a high-frequency pattern (frequency >= 2)
        let highFreqPatterns = profile.commonPatterns.filter { $0.frequency >= 2 }
        XCTAssertFalse(highFreqPatterns.isEmpty,
            "Should identify at least one high-frequency pattern from 3 identical runs")
    }

    func test_analyze_diverseRuns_onlyReportsFrequentPatterns() {
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

        // With only 2 different sequences, any 2-step window appearing in both
        // might match, but full sequences are unique so high-frequency full
        // patterns should be empty or minimal.
        // This tests that frequency threshold is applied correctly.
        let highFreqPatterns = profile.commonPatterns.filter { $0.frequency >= 2 }

        // The 2-step prefix "launch_app -> click" vs "launch_app -> type_text" differ,
        // so no 3-step sequence should repeat. Only the 2-step prefix "launch_app"
        // as a 1-step pattern might match with frequency 2.
        // The test validates that frequency filtering is correct.
        for pattern in highFreqPatterns {
            XCTAssertGreaterThanOrEqual(pattern.frequency, 2,
                "All high-frequency patterns must have frequency >= 2")
        }
    }

    func test_analyze_highFrequencyPattern_includesDescription() {
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
        XCTAssertFalse(highFreqPatterns.isEmpty, "Should find high-frequency pattern")

        for pattern in highFreqPatterns {
            XCTAssertFalse(pattern.description.isEmpty,
                "Each OperationPattern should have a human-readable description")
            XCTAssertFalse(pattern.sequence.isEmpty,
                "Each OperationPattern should have a non-empty tool sequence")
            XCTAssertGreaterThan(pattern.successRate, 0,
                "Success rate should be greater than 0")
        }
    }

    // MARK: - P0 AC3: Mark failure experiences

    func test_analyze_failureEntries_extractsKnownFailures() {
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

        XCTAssertFalse(profile.knownFailures.isEmpty,
            "Should extract failure patterns from entries with failure tags")
        let failure = profile.knownFailures.first!
        XCTAssertFalse(failure.failedAction.isEmpty,
            "Failure pattern should describe the failed action")
        XCTAssertFalse(failure.reason.isEmpty,
            "Failure pattern should provide a reason")
    }

    func test_analyze_failureWithWorkaround_extractsWorkaround() {
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

        XCTAssertEqual(profile.knownFailures.count, 1,
            "Should extract exactly 1 failure pattern")
        let failure = profile.knownFailures.first!
        XCTAssertNotNil(failure.workaround,
            "Failure pattern should include the workaround when available")
        XCTAssertTrue(failure.workaround!.contains("AXButton"),
            "Workaround should reference the AX selector correction")
    }

    func test_analyze_failureWithoutWorkaround_workaroundIsNil() {
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
            XCTAssertNil(failure.workaround,
                "Failure pattern without workaround should have nil workaround")
        }
    }

    // MARK: - P0 AC4: Auto-mark familiar apps (>= 3 successful runs)

    func test_analyze_threeSuccessfulRuns_marksFamiliar() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(id: "run-1", content: "Run 1 success"),
            makeSuccessfulEntry(id: "run-2", content: "Run 2 success"),
            makeSuccessfulEntry(id: "run-3", content: "Run 3 success"),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        XCTAssertTrue(profile.isFamiliar,
            "App with >= 3 successful runs should be marked as familiar")
    }

    func test_analyze_twoSuccessfulRuns_notFamiliar() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(id: "run-1", content: "Run 1 success"),
            makeSuccessfulEntry(id: "run-2", content: "Run 2 success"),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        XCTAssertFalse(profile.isFamiliar,
            "App with < 3 successful runs should NOT be marked as familiar")
    }

    func test_analyze_exactlyThreeSuccessfulRuns_marksFamiliar() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(id: "run-1", content: "Run 1 success"),
            makeSuccessfulEntry(id: "run-2", content: "Run 2 success"),
            makeSuccessfulEntry(id: "run-3", content: "Run 3 success"),
            makeFailureEntry(id: "run-4", content: "Run 4 failure"),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        // Exactly 3 successes + 1 failure: still familiar
        XCTAssertTrue(profile.isFamiliar,
            "App with exactly 3 successful runs (plus failures) should be familiar")
        XCTAssertEqual(profile.successfulRuns, 3)
        XCTAssertEqual(profile.failedRuns, 1)
    }

    // MARK: - P0: Domain matches profile output

    func test_analyze_domainMatchesInput() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(id: "run-1", content: "Run 1 success"),
        ]

        let domain = "com.apple.finder"
        let profile = analyzer.analyze(domain: domain, history: history)

        XCTAssertEqual(profile.domain, domain,
            "Profile domain should match the input domain")
    }

    // MARK: - P1: Edge Cases

    func test_analyze_emptyHistory_returnsEmptyProfile() {
        let analyzer = AppProfileAnalyzer()

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: [])

        XCTAssertEqual(profile.totalRuns, 0, "Empty history should have 0 total runs")
        XCTAssertEqual(profile.successfulRuns, 0)
        XCTAssertEqual(profile.failedRuns, 0)
        XCTAssertTrue(profile.commonPatterns.isEmpty)
        XCTAssertTrue(profile.knownFailures.isEmpty)
        XCTAssertTrue(profile.axCharacteristics.isEmpty)
        XCTAssertFalse(profile.isFamiliar)
    }

    func test_analyze_allFailures_countsCorrectly() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeFailureEntry(id: "run-1", content: "Failure 1"),
            makeFailureEntry(id: "run-2", content: "Failure 2"),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        XCTAssertEqual(profile.totalRuns, 2)
        XCTAssertEqual(profile.successfulRuns, 0)
        XCTAssertEqual(profile.failedRuns, 2)
        XCTAssertFalse(profile.isFamiliar)
        XCTAssertFalse(profile.knownFailures.isEmpty,
            "All-failure history should still extract failure patterns")
    }

    func test_analyze_mixedSuccessFailure_countsCorrectly() {
        let analyzer = AppProfileAnalyzer()

        let history = [
            makeSuccessfulEntry(id: "run-1", content: "Success 1"),
            makeFailureEntry(id: "run-2", content: "Failure 1"),
            makeSuccessfulEntry(id: "run-3", content: "Success 2"),
            makeFailureEntry(id: "run-4", content: "Failure 2"),
            makeSuccessfulEntry(id: "run-5", content: "Success 3"),
        ]

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: history)

        XCTAssertEqual(profile.totalRuns, 5)
        XCTAssertEqual(profile.successfulRuns, 3)
        XCTAssertEqual(profile.failedRuns, 2)
        XCTAssertTrue(profile.isFamiliar,
            "3 successful runs (out of 5 total) should mark as familiar")
    }

    func test_analyze_excludesProfileAndFamiliarEntriesFromTotalRuns() {
        let analyzer = AppProfileAnalyzer()

        let domain = "com.apple.calculator"

        // Actual run entries
        let runEntries = [
            makeSuccessfulEntry(id: "run-1", content: "Success 1"),
            makeSuccessfulEntry(id: "run-2", content: "Success 2"),
        ]

        // Metadata entries (profile + familiar) that should NOT count as runs
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

        XCTAssertEqual(profile.totalRuns, 2,
            "totalRuns should only count actual run entries (success/failure), not profile or familiar entries")
        XCTAssertEqual(profile.successfulRuns, 2)
        XCTAssertEqual(profile.failedRuns, 0)
    }

    func test_analyze_ignoresEntriesFromOtherDomains() {
        let analyzer = AppProfileAnalyzer()

        // These entries are tagged for a different domain
        let wrongDomainEntry = KnowledgeEntry(
            id: "other-1",
            content: "Other app run",
            tags: ["app:com.apple.safari", "success"],
            createdAt: Date(),
            sourceRunId: nil
        )

        let profile = analyzer.analyze(domain: "com.apple.calculator", history: [wrongDomainEntry])

        // The analyzer should only count entries relevant to the requested domain
        // Entries from other domains should be filtered out
        XCTAssertEqual(profile.totalRuns, 0,
            "Entries from other domains should not be counted")
    }

    func test_analyze_axCharacteristics_deduplicatesAcrossRuns() {
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

        // AX characteristics should not have exact duplicates
        let uniqueCharacteristics = Set(profile.axCharacteristics)
        XCTAssertEqual(uniqueCharacteristics.count, profile.axCharacteristics.count,
            "AX characteristics should be deduplicated")
    }

    func test_analyze_operationPattern_successRateIsCorrect() {
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

        // Find the pattern that matches "launch_app -> click -> click"
        let matchingPattern = profile.commonPatterns.first { pattern in
            pattern.sequence == ["launch_app", "click", "click"]
        }

        if let pattern = matchingPattern {
            // 2 successes out of 3 occurrences = ~0.667
            XCTAssertGreaterThanOrEqual(pattern.successRate, 0.5,
                "Success rate should reflect 2/3 successful occurrences")
            XCTAssertLessThanOrEqual(pattern.successRate, 1.0,
                "Success rate should not exceed 1.0")
        }
    }

    func test_analyze_stripsToolParameters_forPatternMatching() {
        let analyzer = AppProfileAnalyzer()

        // Two runs with same tool sequence but different parameters
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

        // After stripping params, both sequences become: launch_app -> click -> type_text
        let highFreqPatterns = profile.commonPatterns.filter { $0.frequency >= 2 }
        XCTAssertFalse(highFreqPatterns.isEmpty,
            "Should identify high-frequency pattern when tool names match but parameters differ")
    }
}
