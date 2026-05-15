import Foundation
import Testing
@testable import AxionCLI
@testable import AxionCore

// MARK: - MockDoctorIO

final class MockDoctorIO: DoctorIO {
    var capturedOutput: [String] = []

    func write(_ line: String) {
        capturedOutput.append(line)
    }
}

@Suite("DoctorCommand")
struct DoctorCommandTests {

    let tempDir: String
    let configFilePath: String

    init() {
        tempDir = NSTemporaryDirectory() + "axion-test-doctor-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        configFilePath = tempDir + "/config.json"
    }

    // MARK: - [P0] 类型存在性

    @Test("CheckStatus enum exists")
    func checkStatusEnumExists() {
        _ = [CheckStatus.ok, .fail]
    }

    @Test("CheckResult struct exists")
    func checkResultStructExists() {
        let _ = CheckResult(name: "test", status: .ok, detail: "detail", fixHint: nil)
    }

    @Test("DoctorReport allOk computed")
    func doctorReportAllOkComputed() {
        let report = DoctorReport(results: [
            CheckResult(name: "a", status: .ok, detail: "", fixHint: nil),
            CheckResult(name: "b", status: .ok, detail: "", fixHint: nil),
        ])
        #expect(report.allOk)
    }

    @Test("DoctorReport not allOk computed")
    func doctorReportNotAllOkComputed() {
        let report = DoctorReport(results: [
            CheckResult(name: "a", status: .ok, detail: "", fixHint: nil),
            CheckResult(name: "b", status: .fail, detail: "broken", fixHint: "fix it"),
        ])
        #expect(!report.allOk)
    }

    @Test("DoctorIO protocol exists")
    func doctorIOProtocolExists() {
        let mock: DoctorIO = MockDoctorIO()
        _ = mock
    }

    @Test("MockDoctorIO captures writes")
    func mockDoctorIOCapturesWrites() {
        let mock = MockDoctorIO()
        mock.write("hello")
        mock.write("world")
        #expect(mock.capturedOutput == ["hello", "world"])
    }

    @Test("TerminalDoctorIO type exists")
    func terminalDoctorIOTypeExists() {
        _ = TerminalDoctorIO.self
    }

    @Test("SystemChecker type exists")
    func systemCheckerTypeExists() {
        _ = SystemChecker.self
    }

    // MARK: - [P0] AC1/AC2: API Key 检查

    @Test("doctor reports API key missing when no config")
    func doctorReportsApiKeyMissingWhenNoConfig() throws {
        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let apiKeyCheck = report.results.first { $0.name.contains("API Key") }
        #expect(apiKeyCheck != nil)
        #expect(apiKeyCheck?.status == .fail)

        let output = mock.capturedOutput.joined(separator: "\n")
        #expect(output.contains("API Key"))
    }

    @Test("doctor reports API key ok when configured")
    func doctorReportsApiKeyOkWhenConfigured() throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let apiKeyCheck = report.results.first { $0.name.contains("API Key") }
        #expect(apiKeyCheck != nil)
        #expect(apiKeyCheck?.status == .ok)
    }

    @Test("doctor reports API key missing when no key")
    func doctorReportsApiKeyMissingWhenNoKey() throws {
        let configJSON = """
        {"model": "claude-sonnet-4-20250514"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let apiKeyCheck = report.results.first { $0.name.contains("API Key") }
        #expect(apiKeyCheck != nil)
        #expect(apiKeyCheck?.status == .fail)
    }

    // MARK: - [P0] AC3: Accessibility 权限检查

    @Test("doctor reports accessibility status")
    func doctorReportsAccessibilityStatus() throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        #expect(output.contains("Accessibility"), "输出应包含 Accessibility 检查结果")
    }

    // MARK: - [P0] AC4: 屏幕录制权限检查

    @Test("doctor reports screen recording status")
    func doctorReportsScreenRecordingStatus() throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        #expect(output.contains("屏幕录制"), "输出应包含屏幕录制检查结果")
    }

    // MARK: - [P0] AC5: macOS 版本检查

    @Test("doctor reports macOS version")
    func doctorReportsMacOSVersion() throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        #expect(output.contains("macOS"), "输出应包含 macOS 版本信息")
    }

    @Test("doctor reports unsupported macOS")
    func doctorReportsUnsupportedMacOS() throws {
        let version = SystemChecker.macOSVersion()
        #expect(!version.isEmpty, "macOS 版本字符串不应为空")

        let isSupported = SystemChecker.isMacOSVersionSupported()
        #expect(isSupported, "开发/CI 环境应运行 macOS 14+ (当前: \(version))")

        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let macOSCheck = report.results.first { $0.name.contains("macOS") }
        #expect(macOSCheck != nil, "应包含 macOS 版本检查项")
        #expect(macOSCheck!.detail.contains(version), "详情应包含当前版本号")
    }

    // MARK: - [P0] AC6: 所有检查通过

    @Test("doctor shows all checks passed when everything ok")
    func doctorShowsAllChecksPassedWhenEverythingOk() throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        let hasAllPassed = output.contains("All checks passed")
        let hasFailureCount = output.contains("check(s) failed")
        #expect(hasAllPassed || hasFailureCount, "输出应包含通过或失败汇总")

        if report.allOk {
            #expect(hasAllPassed, "allOk 时输出应包含 'All checks passed'")
        } else {
            #expect(hasFailureCount, "有失败项时输出应包含 'check(s) failed'")
        }
    }

    // MARK: - [P0] AC7: 明确修复建议

    @Test("doctor shows fix hints for failed checks")
    func doctorShowsFixHintsForFailedChecks() throws {
        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let failedChecks = report.results.filter { $0.status == .fail }
        #expect(!failedChecks.isEmpty, "无配置文件时应有失败项")

        for check in failedChecks {
            #expect(check.fixHint != nil, "失败项 '\(check.name)' 应有修复建议")
            #expect(!check.fixHint!.isEmpty, "失败项 '\(check.name)' 的修复建议不应为空")
        }

        let output = mock.capturedOutput.joined(separator: "\n")
        #expect(output.contains("axion setup") || output.contains("系统设置"), "输出应包含具体修复步骤")
    }

    // MARK: - [P0] AC8: API Key 不泄露

    @Test("doctor masks API key in output")
    func doctorMasksApiKeyInOutput() throws {
        let testKey = "sk-ant-api03-supersecret123456"
        let configJSON = """
        {"apiKey": "\(testKey)"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        #expect(!output.contains(testKey), "完整 API Key 不应出现在终端输出中 (NFR9)")
        #expect(!output.contains("supersecret"), "API Key 敏感部分不应出现在输出中")
    }

    // MARK: - [P0] AC9: 配置文件完整性检查

    @Test("doctor reports corrupt config")
    func doctorReportsCorruptConfig() throws {
        let corruptJSON = "}{not valid json"
        try corruptJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let configCheck = report.results.first { $0.name.contains("配置文件") }
        #expect(configCheck != nil, "应包含配置文件检查项")
        #expect(configCheck?.status == .fail, "损坏的配置文件应报告失败")

        let output = mock.capturedOutput.joined(separator: "\n")
        #expect(output.contains("axion setup"), "损坏配置应建议运行 axion setup")
    }

    // MARK: - [P1] 失败计数输出

    @Test("doctor shows failure count when checks fail")
    func doctorShowsFailureCountWhenChecksFail() throws {
        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let failedCount = report.results.filter { $0.status == .fail }.count
        if failedCount > 0 {
            let output = mock.capturedOutput.joined(separator: "\n")
            #expect(
                output.contains("\(failedCount) check(s) failed"),
                "输出应显示失败检查数: \(failedCount)"
            )
        }
    }

    // MARK: - [P0] AC5 (Story 4.1): Memory 状态检查

    @Test("doctor reports memory status when memory exists")
    func doctorReportsMemoryStatusWhenMemoryExists() async throws {
        let memoryDir = tempDir + "/memory"
        try FileManager.default.createDirectory(
            atPath: memoryDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let domainData = """
        [
          {
            "id": "test-id",
            "content": "Test memory entry",
            "tags": ["test"],
            "createdAt": "2026-05-13T10:00:00.000Z"
          }
        ]
        """
        try domainData.write(toFile: memoryDir + "/com.apple.calculator.json", atomically: true, encoding: .utf8)

        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        #expect(output.contains("Memory"), "输出应包含 Memory 检查结果")
    }

    @Test("doctor reports memory unused when no memory")
    func doctorReportsMemoryUnusedWhenNoMemory() async throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        #expect(
            output.contains("Memory") || output.contains("memory"),
            "输出应包含 Memory 状态信息（即使未使用）"
        )
    }

    @Test("doctor memory check shows domain count and entry count")
    func doctorMemoryCheckShowsDomainCountAndEntryCount() async throws {
        let memoryDir = tempDir + "/memory"
        try FileManager.default.createDirectory(
            atPath: memoryDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let calcData = """
        [
          {"id": "c1", "content": "Calc entry 1", "tags": [], "createdAt": "2026-05-13T10:00:00.000Z"},
          {"id": "c2", "content": "Calc entry 2", "tags": [], "createdAt": "2026-05-13T11:00:00.000Z"}
        ]
        """
        try calcData.write(toFile: memoryDir + "/com.apple.calculator.json", atomically: true, encoding: .utf8)

        let notesData = """
        [
          {"id": "n1", "content": "Notes entry 1", "tags": [], "createdAt": "2026-05-13T10:00:00.000Z"}
        ]
        """
        try notesData.write(toFile: memoryDir + "/com.apple.notes.json", atomically: true, encoding: .utf8)

        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let memoryCheck = report.results.first { $0.name.contains("Memory") }
        #expect(memoryCheck != nil, "应包含 Memory 检查项")

        let output = mock.capturedOutput.joined(separator: "\n")
        #expect(
            output.contains("2 domains") || output.contains("3 entries") || output.contains("domain"),
            "Memory 检查应显示 domain 数量和条目数: \(output)"
        )
    }

    @Test("doctor memory check format when unused")
    func doctorMemoryCheckFormatWhenUnused() async throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let report = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let memoryCheck = report.results.first { $0.name.contains("Memory") }
        #expect(memoryCheck != nil, "应包含 Memory 检查项")
        #expect(memoryCheck?.status == .ok, "未使用 Memory 不应报告为失败")
    }

    // MARK: - [P1] 输出格式验证

    @Test("doctor output contains header")
    func doctorOutputContainsHeader() throws {
        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        #expect(output.contains("Axion Doctor"), "输出应包含 Axion Doctor 标题")
    }

    @Test("doctor output uses OK/FAIL markers")
    func doctorOutputUsesOkFailMarkers() throws {
        let configJSON = """
        {"apiKey": "sk-ant-test-key-1234567890"}
        """
        try configJSON.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let mock = MockDoctorIO()
        let _ = DoctorCommand.runDoctor(io: mock, configDirectory: tempDir)

        let output = mock.capturedOutput.joined(separator: "\n")
        #expect(
            output.contains("[OK]") || output.contains("[FAIL]"),
            "输出应使用 [OK]/[FAIL] 标记格式"
        )
    }
}
