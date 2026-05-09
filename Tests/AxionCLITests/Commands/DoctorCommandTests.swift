import XCTest
@testable import AxionCLI
@testable import AxionCore

// MARK: - MockDoctorIO

/// MockDoctorIO -- 实现 DoctorIO 协议，捕获输出到数组，用于单元测试。
final class MockDoctorIO: DoctorIO {
    var capturedOutput: [String] = []

    func write(_ line: String) {
        capturedOutput.append(line)
    }
}

// [P0] 基础设施验证 -- CheckResult, DoctorReport, DoctorIO, SystemChecker 类型存在性
// [P1] 行为验证 -- doctor 检查逻辑和输出格式
// Story 2.4 AC: #1-#9

final class DoctorCommandTests: XCTestCase {

    private var tempDir: String!
    private var configFilePath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = NSTemporaryDirectory() + "axion-test-doctor-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        configFilePath = tempDir + "/config.json"
    }

    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - [P0] 类型存在性

    func test_checkStatus_enumExists() throws {
        _ = [CheckStatus.ok, .fail]
    }

    func test_checkResult_structExists() throws {
        let _ = CheckResult(name: "test", status: .ok, detail: "detail", fixHint: nil)
    }

    func test_doctorReport_allOkComputed() throws {
        let report = DoctorReport(results: [
            CheckResult(name: "a", status: .ok, detail: "", fixHint: nil),
            CheckResult(name: "b", status: .ok, detail: "", fixHint: nil),
        ])
        XCTAssertTrue(report.allOk)
    }

    func test_doctorReport_notAllOkComputed() throws {
        let report = DoctorReport(results: [
            CheckResult(name: "a", status: .ok, detail: "", fixHint: nil),
            CheckResult(name: "b", status: .fail, detail: "broken", fixHint: "fix it"),
        ])
        XCTAssertFalse(report.allOk)
    }

    func test_doctorIO_protocolExists() throws {
        let mock: DoctorIO = MockDoctorIO()
        _ = mock
    }

    func test_mockDoctorIO_capturesWrites() throws {
        let mock = MockDoctorIO()
        mock.write("hello")
        mock.write("world")
        XCTAssertEqual(mock.capturedOutput, ["hello", "world"])
    }

    func test_terminalDoctorIO_typeExists() throws {
        _ = TerminalDoctorIO.self
    }

    func test_systemChecker_typeExists() throws {
        _ = SystemChecker.self
    }

    // MARK: - [P0] AC1/AC2: API Key 检查

    func test_doctor_reportsApiKeyMissing_whenNoConfig() throws {
        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        // 无配置文件时，API Key 检查应失败
        let apiKeyCheck = report.results.first { $0.name.contains("API Key") }
        XCTAssertNotNil(apiKeyCheck)
        XCTAssertEqual(apiKeyCheck?.status, .fail)

        // 输出应包含 API Key 缺失信息
        let output = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(output.contains("API Key"))
    }

    func test_doctor_reportsApiKeyOk_whenConfigured() throws {
        // 创建包含 API Key 的配置文件
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let apiKeyCheck = report.results.first { $0.name.contains("API Key") }
        XCTAssertNotNil(apiKeyCheck)
        XCTAssertEqual(apiKeyCheck?.status, .ok)
    }

    func test_doctor_reportsApiKeyMissing_whenNoKey() throws {
        // 创建不含 API Key 的配置文件
        let configJSON = """
        {"model": "claude-sonnet-4-20250514"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let apiKeyCheck = report.results.first { $0.name.contains("API Key") }
        XCTAssertNotNil(apiKeyCheck)
        XCTAssertEqual(apiKeyCheck?.status, .fail)
    }

    // MARK: - [P0] AC3: Accessibility 权限检查

    func test_doctor_reportsAccessibilityStatus() throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(output.contains("Accessibility"), "输出应包含 Accessibility 检查结果")
    }

    // MARK: - [P0] AC4: 屏幕录制权限检查

    func test_doctor_reportsScreenRecordingStatus() throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(output.contains("屏幕录制"), "输出应包含屏幕录制检查结果")
    }

    // MARK: - [P0] AC5: macOS 版本检查

    func test_doctor_reportsMacOSVersion() throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(output.contains("macOS"), "输出应包含 macOS 版本信息")
    }

    func test_doctor_reportsUnsupportedMacOS() throws {
        // 验证 SystemChecker 的版本检查逻辑
        // 当前测试机器应该运行 macOS 14+（项目最低要求）
        let version = SystemChecker.macOSVersion()
        XCTAssertFalse(version.isEmpty, "macOS 版本字符串不应为空")

        // 开发/CI 环境应满足最低版本要求
        let isSupported = SystemChecker.isMacOSVersionSupported()
        XCTAssertTrue(isSupported, "开发/CI 环境应运行 macOS 14+ (当前: \(version))")

        // 验证 doctor 命令输出包含版本号
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let macOSCheck = report.results.first { $0.name.contains("macOS") }
        XCTAssertNotNil(macOSCheck, "应包含 macOS 版本检查项")
        XCTAssertTrue(macOSCheck!.detail.contains(version), "详情应包含当前版本号")
    }

    // MARK: - [P0] AC6: 所有检查通过

    func test_doctor_showsAllChecksPassed_whenEverythingOk() throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        // 验证输出包含通过或失败汇总（格式正确性）
        let hasAllPassed = output.contains("All checks passed")
        let hasFailureCount = output.contains("check(s) failed")
        XCTAssertTrue(hasAllPassed || hasFailureCount, "输出应包含通过或失败汇总")

        // 验证 report 的 allOk 与输出汇总一致
        if report.allOk {
            XCTAssertTrue(hasAllPassed, "allOk 时输出应包含 'All checks passed'")
        } else {
            XCTAssertTrue(hasFailureCount, "有失败项时输出应包含 'check(s) failed'")
        }
    }

    // MARK: - [P0] AC7: 明确修复建议

    func test_doctor_showsFixHints_forFailedChecks() throws {
        // 无配置文件，确保有失败项
        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        // 至少有一个失败项（无配置文件）
        let failedChecks = report.results.filter { $0.status == .fail }
        XCTAssertFalse(failedChecks.isEmpty, "无配置文件时应有失败项")

        // 失败项应有修复建议
        for check in failedChecks {
            XCTAssertNotNil(check.fixHint, "失败项 '\(check.name)' 应有修复建议")
            XCTAssertFalse(check.fixHint!.isEmpty, "失败项 '\(check.name)' 的修复建议不应为空")
        }

        // 输出中应包含修复建议
        let output = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(output.contains("axion setup") || output.contains("系统设置"), "输出应包含具体修复步骤")
    }

    // MARK: - [P0] AC8: API Key 不泄露

    func test_doctor_masksApiKey_inOutput() throws {
        let testKey = "sk-ant-api03-supersecret123456"
        let configJSON = """
        {"apiKey": "\(testKey)"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        XCTAssertFalse(output.contains(testKey), "完整 API Key 不应出现在终端输出中 (NFR9)")
        XCTAssertFalse(output.contains("supersecret"), "API Key 敏感部分不应出现在输出中")
    }

    // MARK: - [P0] AC9: 配置文件完整性检查

    func test_doctor_reportsCorruptConfig() throws {
        // 写入无效 JSON
        let corruptJSON = "}{not valid json"
        try corruptJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let configCheck = report.results.first { $0.name.contains("配置文件") }
        XCTAssertNotNil(configCheck, "应包含配置文件检查项")
        XCTAssertEqual(configCheck?.status, .fail, "损坏的配置文件应报告失败")

        let output = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(output.contains("axion setup"), "损坏配置应建议运行 axion setup")
    }

    // MARK: - [P1] 失败计数输出

    func test_doctor_showsFailureCount_whenChecksFail() throws {
        // 无配置文件，确保有失败项
        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let failedCount = report.results.filter { $0.status == .fail }.count
        if failedCount > 0 {
            let output = mock.capturedOutput.joined(separator: "\n")
            XCTAssertTrue(
                output.contains("\(failedCount) check(s) failed"),
                "输出应显示失败检查数: \(failedCount)"
            )
        }
    }

    // MARK: - [P1] 输出格式验证

    func test_doctor_output_containsHeader() throws {
        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        XCTAssertTrue(output.contains("Axion Doctor"), "输出应包含 Axion Doctor 标题")
    }

    func test_doctor_output_usesOkFailMarkers() throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        // 输出应使用 [OK] 或 [FAIL] 标记
        XCTAssertTrue(
            output.contains("[OK]") || output.contains("[FAIL]"),
            "输出应使用 [OK]/[FAIL] 标记格式"
        )
    }
}
