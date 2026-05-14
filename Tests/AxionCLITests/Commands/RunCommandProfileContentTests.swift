import XCTest

@testable import AxionCLI

// [P0] buildProfileContent format validation (Story 4.2 → 4.3 interface contract)
// Story 4.3 Planner parses this format to inject memory context — format regressions
// would silently break memory-enhanced planning.

final class RunCommandProfileContentTests: XCTestCase {

    // MARK: - Helper: Build a profile

    private func makeProfile(
        domain: String = "com.apple.calculator",
        totalRuns: Int = 3,
        successfulRuns: Int = 2,
        failedRuns: Int = 1,
        commonPatterns: [OperationPattern] = [],
        knownFailures: [FailurePattern] = [],
        axCharacteristics: [String] = [],
        isFamiliar: Bool = true
    ) -> AppProfile {
        AppProfile(
            domain: domain,
            totalRuns: totalRuns,
            successfulRuns: successfulRuns,
            failedRuns: failedRuns,
            commonPatterns: commonPatterns,
            knownFailures: knownFailures,
            axCharacteristics: axCharacteristics,
            isFamiliar: isFamiliar
        )
    }

    // MARK: - P0: Basic format structure

    func test_buildProfileContent_includesDomainAndCounts() {
        let profile = makeProfile(
            domain: "com.apple.calculator",
            totalRuns: 5,
            successfulRuns: 3,
            failedRuns: 2,
            isFamiliar: true
        )

        let content = RunCommand.buildProfileContent(profile: profile)

        XCTAssertTrue(content.contains("App Profile: com.apple.calculator"),
            "Should include domain header")
        XCTAssertTrue(content.contains("总运行次数: 5"),
            "Should include total run count")
        XCTAssertTrue(content.contains("成功次数: 3"),
            "Should include success count")
        XCTAssertTrue(content.contains("失败次数: 2"),
            "Should include failure count")
        XCTAssertTrue(content.contains("已熟悉: 是"),
            "Should indicate familiar status")
    }

    func test_buildProfileContent_notFamiliar_showsNo() {
        let profile = makeProfile(isFamiliar: false)

        let content = RunCommand.buildProfileContent(profile: profile)

        XCTAssertTrue(content.contains("已熟悉: 否"),
            "Should indicate not-familiar status")
    }

    // MARK: - P0: AX characteristics line

    func test_buildProfileContent_includesAxCharacteristics() {
        let profile = makeProfile(
            axCharacteristics: ["AXButton", "AXTextField"]
        )

        let content = RunCommand.buildProfileContent(profile: profile)

        XCTAssertTrue(content.contains("AX特征:"),
            "Should include AX characteristics header")
        XCTAssertTrue(content.contains("AXButton"),
            "Should include AX characteristic values")
        XCTAssertTrue(content.contains("AXTextField"),
            "Should include all AX characteristic values")
    }

    func test_buildProfileContent_noAxCharacteristics_omitsLine() {
        let profile = makeProfile(axCharacteristics: [])

        let content = RunCommand.buildProfileContent(profile: profile)

        XCTAssertFalse(content.contains("AX特征:"),
            "Should not include AX characteristics line when empty")
    }

    // MARK: - P0: High-frequency patterns line

    func test_buildProfileContent_includesCommonPatterns() {
        let patterns = [
            OperationPattern(
                sequence: ["launch_app", "click", "type_text"],
                frequency: 3,
                successRate: 1.0,
                description: "Common navigation pattern"
            )
        ]
        let profile = makeProfile(commonPatterns: patterns)

        let content = RunCommand.buildProfileContent(profile: profile)

        XCTAssertTrue(content.contains("高频路径:"),
            "Should include high-frequency patterns header")
        XCTAssertTrue(content.contains("launch_app → click → type_text"),
            "Should include pattern sequence")
        XCTAssertTrue(content.contains("频率:3"),
            "Should include pattern frequency")
        XCTAssertTrue(content.contains("成功率:100%"),
            "Should include success rate")
    }

    func test_buildProfileContent_noPatterns_omitsLine() {
        let profile = makeProfile(commonPatterns: [])

        let content = RunCommand.buildProfileContent(profile: profile)

        XCTAssertFalse(content.contains("高频路径:"),
            "Should not include patterns line when empty")
    }

    // MARK: - P0: Known failures line

    func test_buildProfileContent_includesKnownFailures_withWorkaround() {
        let failures = [
            FailurePattern(
                failedAction: "click(x:300,y:400)",
                reason: "坐标不可靠",
                workaround: "使用 AXButton[title=\"*\"]"
            )
        ]
        let profile = makeProfile(knownFailures: failures)

        let content = RunCommand.buildProfileContent(profile: profile)

        XCTAssertTrue(content.contains("已知失败:"),
            "Should include known failures header")
        XCTAssertTrue(content.contains("click(x:300,y:400)"),
            "Should include failed action")
        XCTAssertTrue(content.contains("坐标不可靠"),
            "Should include failure reason")
        XCTAssertTrue(content.contains("修正:"),
            "Should include workaround when present")
    }

    func test_buildProfileContent_includesKnownFailures_withoutWorkaround() {
        let failures = [
            FailurePattern(
                failedAction: "launch_app",
                reason: "应用未安装",
                workaround: nil
            )
        ]
        let profile = makeProfile(knownFailures: failures)

        let content = RunCommand.buildProfileContent(profile: profile)

        XCTAssertTrue(content.contains("已知失败:"),
            "Should include known failures header")
        XCTAssertFalse(content.contains("修正:"),
            "Should not include workaround section when none exists")
    }

    func test_buildProfileContent_noFailures_omitsLine() {
        let profile = makeProfile(knownFailures: [])

        let content = RunCommand.buildProfileContent(profile: profile)

        XCTAssertFalse(content.contains("已知失败:"),
            "Should not include failures line when empty")
    }

    // MARK: - P0: Minimal profile (zero runs)

    func test_buildProfileContent_zeroRuns_stillProducesValidContent() {
        let profile = makeProfile(
            totalRuns: 0,
            successfulRuns: 0,
            failedRuns: 0,
            isFamiliar: false
        )

        let content = RunCommand.buildProfileContent(profile: profile)

        XCTAssertTrue(content.contains("总运行次数: 0"),
            "Should handle zero runs gracefully")
        XCTAssertFalse(content.contains("AX特征:"),
            "No AX characteristics for zero runs")
        XCTAssertFalse(content.contains("高频路径:"),
            "No patterns for zero runs")
        XCTAssertFalse(content.contains("已知失败:"),
            "No failures for zero runs")
    }

    // MARK: - P0: Multiple patterns and failures

    func test_buildProfileContent_multiplePatterns_separatedBySemicolon() {
        let patterns = [
            OperationPattern(
                sequence: ["launch_app", "click"],
                frequency: 5,
                successRate: 0.8,
                description: "Pattern A"
            ),
            OperationPattern(
                sequence: ["launch_app", "type_text"],
                frequency: 3,
                successRate: 1.0,
                description: "Pattern B"
            )
        ]
        let profile = makeProfile(commonPatterns: patterns)

        let content = RunCommand.buildProfileContent(profile: profile)

        XCTAssertTrue(content.contains(";"),
            "Multiple patterns should be separated by semicolons")
        XCTAssertTrue(content.contains("频率:5"),
            "Should include first pattern frequency")
        XCTAssertTrue(content.contains("频率:3"),
            "Should include second pattern frequency")
    }
}
