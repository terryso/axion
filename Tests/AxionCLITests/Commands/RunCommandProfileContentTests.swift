import Testing

@testable import AxionCLI

@Suite("RunCommandProfileContent")
struct RunCommandProfileContentTests {

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

    @Test("buildProfileContent includes domain and counts")
    func buildProfileContentIncludesDomainAndCounts() {
        let profile = makeProfile(
            domain: "com.apple.calculator",
            totalRuns: 5,
            successfulRuns: 3,
            failedRuns: 2,
            isFamiliar: true
        )

        let content = RunCommand.buildProfileContent(profile: profile)

        #expect(content.contains("App Profile: com.apple.calculator"),
            "Should include domain header")
        #expect(content.contains("总运行次数: 5"),
            "Should include total run count")
        #expect(content.contains("成功次数: 3"),
            "Should include success count")
        #expect(content.contains("失败次数: 2"),
            "Should include failure count")
        #expect(content.contains("已熟悉: 是"),
            "Should indicate familiar status")
    }

    @Test("buildProfileContent not familiar shows no")
    func buildProfileContentNotFamiliarShowsNo() {
        let profile = makeProfile(isFamiliar: false)

        let content = RunCommand.buildProfileContent(profile: profile)

        #expect(content.contains("已熟悉: 否"), "Should indicate not-familiar status")
    }

    // MARK: - P0: AX characteristics line

    @Test("buildProfileContent includes AX characteristics")
    func buildProfileContentIncludesAxCharacteristics() {
        let profile = makeProfile(
            axCharacteristics: ["AXButton", "AXTextField"]
        )

        let content = RunCommand.buildProfileContent(profile: profile)

        #expect(content.contains("AX特征:"), "Should include AX characteristics header")
        #expect(content.contains("AXButton"), "Should include AX characteristic values")
        #expect(content.contains("AXTextField"), "Should include all AX characteristic values")
    }

    @Test("buildProfileContent no AX characteristics omits line")
    func buildProfileContentNoAxCharacteristicsOmitsLine() {
        let profile = makeProfile(axCharacteristics: [])

        let content = RunCommand.buildProfileContent(profile: profile)

        #expect(!content.contains("AX特征:"), "Should not include AX characteristics line when empty")
    }

    // MARK: - P0: High-frequency patterns line

    @Test("buildProfileContent includes common patterns")
    func buildProfileContentIncludesCommonPatterns() {
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

        #expect(content.contains("高频路径:"), "Should include high-frequency patterns header")
        #expect(content.contains("launch_app → click → type_text"), "Should include pattern sequence")
        #expect(content.contains("频率:3"), "Should include pattern frequency")
        #expect(content.contains("成功率:100%"), "Should include success rate")
    }

    @Test("buildProfileContent no patterns omits line")
    func buildProfileContentNoPatternsOmitsLine() {
        let profile = makeProfile(commonPatterns: [])

        let content = RunCommand.buildProfileContent(profile: profile)

        #expect(!content.contains("高频路径:"), "Should not include patterns line when empty")
    }

    // MARK: - P0: Known failures line

    @Test("buildProfileContent includes known failures with workaround")
    func buildProfileContentIncludesKnownFailuresWithWorkaround() {
        let failures = [
            FailurePattern(
                failedAction: "click(x:300,y:400)",
                reason: "坐标不可靠",
                workaround: "使用 AXButton[title=\"*\"]"
            )
        ]
        let profile = makeProfile(knownFailures: failures)

        let content = RunCommand.buildProfileContent(profile: profile)

        #expect(content.contains("已知失败:"), "Should include known failures header")
        #expect(content.contains("click(x:300,y:400)"), "Should include failed action")
        #expect(content.contains("坐标不可靠"), "Should include failure reason")
        #expect(content.contains("修正:"), "Should include workaround when present")
    }

    @Test("buildProfileContent includes known failures without workaround")
    func buildProfileContentIncludesKnownFailuresWithoutWorkaround() {
        let failures = [
            FailurePattern(
                failedAction: "launch_app",
                reason: "应用未安装",
                workaround: nil
            )
        ]
        let profile = makeProfile(knownFailures: failures)

        let content = RunCommand.buildProfileContent(profile: profile)

        #expect(content.contains("已知失败:"), "Should include known failures header")
        #expect(!content.contains("修正:"), "Should not include workaround section when none exists")
    }

    @Test("buildProfileContent no failures omits line")
    func buildProfileContentNoFailuresOmitsLine() {
        let profile = makeProfile(knownFailures: [])

        let content = RunCommand.buildProfileContent(profile: profile)

        #expect(!content.contains("已知失败:"), "Should not include failures line when empty")
    }

    // MARK: - P0: Minimal profile (zero runs)

    @Test("buildProfileContent zero runs still produces valid content")
    func buildProfileContentZeroRunsStillProducesValidContent() {
        let profile = makeProfile(
            totalRuns: 0,
            successfulRuns: 0,
            failedRuns: 0,
            isFamiliar: false
        )

        let content = RunCommand.buildProfileContent(profile: profile)

        #expect(content.contains("总运行次数: 0"), "Should handle zero runs gracefully")
        #expect(!content.contains("AX特征:"), "No AX characteristics for zero runs")
        #expect(!content.contains("高频路径:"), "No patterns for zero runs")
        #expect(!content.contains("已知失败:"), "No failures for zero runs")
    }

    // MARK: - P0: Multiple patterns and failures

    @Test("buildProfileContent multiple patterns separated by semicolon")
    func buildProfileContentMultiplePatternsSeparatedBySemicolon() {
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

        #expect(content.contains(";"), "Multiple patterns should be separated by semicolons")
        #expect(content.contains("频率:5"), "Should include first pattern frequency")
        #expect(content.contains("频率:3"), "Should include second pattern frequency")
    }
}
