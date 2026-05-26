import Testing
import Foundation
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

@Suite("Review Config CLI Flags")
struct ReviewConfigTests: ~Copyable {

    private var tempDir: String!
    private var configFilePath: String!

    init() {
        tempDir = NSTemporaryDirectory() + "axion-test-review-config-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        configFilePath = tempDir + "/config.json"
    }

    deinit {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
    }

    private func writeConfigJSON(_ json: String) throws {
        try json.write(
            toFile: configFilePath,
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - 6.1: --no-review skips review/curator

    @Test("RunOrchestrator.RunConfig has noReview field")
    func runConfigHasNoReviewField() {
        let config = RunOrchestrator.RunConfig(
            task: "test", fast: false, dryrun: false, json: false,
            noMemory: false, noVisualDelta: false,
            allowForeground: false, maxSteps: nil,
            config: AxionConfig.default, noReview: true, onReviewCompleted: nil,
            eventBus: nil
        )
        #expect(config.noReview == true)
    }

    @Test("RunOrchestrator.RunConfig noReview defaults to false")
    func runConfigNoReviewDefaultsFalse() {
        let config = RunOrchestrator.RunConfig(
            task: "test", fast: false, dryrun: false, json: false,
            noMemory: false, noVisualDelta: false,
            allowForeground: false, maxSteps: nil,
            config: AxionConfig.default, noReview: false, onReviewCompleted: nil,
            eventBus: nil
        )
        #expect(config.noReview == false)
    }

    // MARK: - 6.2: --review-model overrides config.json via CLIOverrides

    @Test("CLIOverrides has reviewModel field")
    func cliOverridesHasReviewModel() {
        let overrides = CLIOverrides(reviewModel: AxionConfig.defaultReviewModel)
        #expect(overrides.reviewModel == AxionConfig.defaultReviewModel)
    }

    @Test("CLIOverrides reviewModel defaults to nil")
    func cliOverridesReviewModelDefaultsNil() {
        let overrides = CLIOverrides()
        #expect(overrides.reviewModel == nil)
    }

    @Test("--review-model CLI override sets config.reviewModel")
    func reviewModelCLIOverride() async throws {
        try writeConfigJSON("""
        {"apiKey": "sk-test"}
        """)

        let cliOverrides = CLIOverrides(reviewModel: AxionConfig.defaultReviewModel)
        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: cliOverrides,
            environment: [:]
        )

        #expect(config.reviewModel == AxionConfig.defaultReviewModel)
    }

    @Test("--review-model CLI override takes precedence over config.json")
    func reviewModelCLIOverridesConfigFile() async throws {
        try writeConfigJSON("""
        {"apiKey": "sk-test", "reviewModel": "claude-sonnet-4-20250514"}
        """)

        let cliOverrides = CLIOverrides(reviewModel: AxionConfig.defaultReviewModel)
        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: cliOverrides,
            environment: [:]
        )

        #expect(config.reviewModel == AxionConfig.defaultReviewModel)
    }

    // MARK: - 6.3: config.json review fields decode correctly

    @Test("config.json review fields decode correctly")
    func configJsonReviewFieldsDecode() async throws {
        try writeConfigJSON("""
        {
          "apiKey": "sk-test",
          "reviewMemoryInterval": 8,
          "reviewSkillInterval": 10,
          "reviewMinMessages": 6,
          "reviewModel": "\(AxionConfig.defaultReviewModel)"
        }
        """)

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil,
            environment: [:]
        )

        #expect(config.reviewMemoryInterval == 8)
        #expect(config.reviewSkillInterval == 10)
        #expect(config.reviewMinMessages == 6)
        #expect(config.reviewModel == AxionConfig.defaultReviewModel)
    }

    @Test("config.json curator fields decode correctly")
    func configJsonCuratorFieldsDecode() async throws {
        try writeConfigJSON("""
        {
          "apiKey": "sk-test",
          "curatorEnabled": false,
          "curatorDryRun": true,
          "curatorIntervalHours": 336.0,
          "curatorStaleAfterDays": 60,
          "curatorArchiveAfterDays": 180
        }
        """)

        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil,
            environment: [:]
        )

        #expect(config.curatorEnabled == false)
        #expect(config.curatorDryRun == true)
        #expect(config.curatorIntervalHours == 336.0)
        #expect(config.curatorStaleAfterDays == 60)
        #expect(config.curatorArchiveAfterDays == 180)
    }

    // MARK: - 6.4: defaults match SDK defaults when config absent

    @Test("defaults match SDK defaults when config absent")
    func defaultsMatchSdkDefaults() async throws {
        let config = try await ConfigManager.loadConfig(
            configDirectory: tempDir,
            cliOverrides: nil,
            environment: [:]
        )

        // ReviewScheduleConfig defaults
        let scheduleConfig = ReviewScheduleConfig(
            memoryReviewInterval: config.reviewMemoryInterval ?? ReviewScheduleConfig().memoryReviewInterval,
            skillReviewInterval: config.reviewSkillInterval ?? ReviewScheduleConfig().skillReviewInterval,
            minMessagesForReview: config.reviewMinMessages ?? ReviewScheduleConfig().minMessagesForReview,
            reviewModel: config.reviewModel
        )

        #expect(scheduleConfig.memoryReviewInterval == 4)
        #expect(scheduleConfig.skillReviewInterval == 6)
        #expect(scheduleConfig.minMessagesForReview == 4)
        #expect(scheduleConfig.reviewModel == nil)

        // SkillCuratorConfig defaults
        let curatorConfig = SkillCuratorConfig(
            intervalHours: config.curatorIntervalHours ?? 168.0,
            staleAfterDays: config.curatorStaleAfterDays ?? 30,
            archiveAfterDays: config.curatorArchiveAfterDays ?? 90,
            dryRun: config.curatorDryRun ?? false,
            enabled: config.curatorEnabled ?? true
        )
        #expect(curatorConfig.intervalHours == 168.0)
        #expect(curatorConfig.enabled == true)
    }

    // MARK: - 6.5: CuratorCommand subcommands parse correctly

    @Test("CuratorCommand type exists and has subcommands")
    func curatorCommandTypeExists() {
        _ = CuratorCommand.self
        _ = CuratorRunCommand.self
        _ = CuratorStatusCommand.self
    }

    @Test("CuratorCommand configuration has correct command name")
    func curatorCommandConfiguration() {
        #expect(CuratorCommand.configuration.commandName == "curator")
        #expect(CuratorRunCommand.configuration.commandName == "run")
        #expect(CuratorStatusCommand.configuration.commandName == "status")
    }

    // MARK: - Doctor review/curator check

    @Test("doctor includes Review/Curator check")
    func doctorIncludesReviewCuratorCheck() throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir, isServerRunningOverride: { false })

        let reviewCheck = report.results.first { $0.name.contains("Review") }
        #expect(reviewCheck != nil, "应包含 Review/Curator 检查项")
        #expect(reviewCheck?.status == .ok)

        let output = mock.capturedOutput.joined(separator: "\n")
        #expect(output.contains("Review"), "输出应包含 Review 信息")
    }

    @Test("doctor shows review model in output")
    func doctorShowsReviewModelInOutput() throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890", "reviewModel": "\(AxionConfig.defaultReviewModel)"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir, isServerRunningOverride: { false })

        let output = mock.capturedOutput.joined(separator: "\n")
        #expect(output.contains(AxionConfig.defaultReviewModel), "应显示配置的 review model")
    }
}
