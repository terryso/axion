import XCTest
import ArgumentParser
@testable import AxionCLI

// [P0] 基础设施验证 — CLI 根命令与子命令骨架
// [P1] 行为验证 — 参数解析、版本输出、帮助输出

final class AxionCommandTests: XCTestCase {

    // MARK: - AC1: `axion --help` 显示根命令帮助

    // 验证 --help 输出包含 "run" 子命令
    func test_axionHelp_showsRunSubcommand() {
        let helpText = AxionCLI.helpMessage(for: AxionCLI.self)
        XCTAssertTrue(
            helpText.contains("run"),
            "'--help' output should contain 'run' subcommand. Got:\n\(helpText)"
        )
    }

    // 验证 --help 输出包含 "setup" 子命令
    func test_axionHelp_showsSetupSubcommand() {
        let helpText = AxionCLI.helpMessage(for: AxionCLI.self)
        XCTAssertTrue(
            helpText.contains("setup"),
            "'--help' output should contain 'setup' subcommand. Got:\n\(helpText)"
        )
    }

    // 验证 --help 输出包含 "doctor" 子命令
    func test_axionHelp_showsDoctorSubcommand() {
        let helpText = AxionCLI.helpMessage(for: AxionCLI.self)
        XCTAssertTrue(
            helpText.contains("doctor"),
            "'--help' output should contain 'doctor' subcommand. Got:\n\(helpText)"
        )
    }

    // MARK: - AC2: `axion --version` 显示版本号

    // 验证 AxionCLI CommandConfiguration 包含版本号
    func test_axionVersion_configurationHasVersion() {
        let version = AxionCLI.configuration.version
        XCTAssertTrue(
            version.contains("0.1.0"),
            "Version should contain '0.1.0', got: \(version)"
        )
    }

    // MARK: - AC3: 未知子命令显示错误提示

    // 验证未知子命令返回解析错误
    func test_unknownSubcommand_throwsParseError() throws {
        XCTAssertThrowsError(try AxionCLI.parse(["unknown"])) { error in
            // 未知子命令不应是 CleanExit（如 helpRequest 或 message）
            if let cleanExit = error as? CleanExit {
                XCTFail(
                    "Unknown subcommand should produce a parse error, not CleanExit. Got: \(cleanExit)"
                )
            }
        }
    }

    // MARK: - RunCommand 参数解析

    // 验证 RunCommand 正确解析 task 必填参数
    func test_runCommandParsesTaskArgument() throws {
        let cmd = try RunCommand.parse(["打开计算器"])
        XCTAssertEqual(cmd.task, "打开计算器")
    }

    // 验证 RunCommand 正确解析 --dryrun flag
    func test_runCommandParsesDryrunFlag() throws {
        let cmd = try RunCommand.parse(["打开计算器", "--dryrun"])
        XCTAssertTrue(cmd.dryrun)
    }

    // 验证 RunCommand 默认 dryrun=false（实际执行模式）
    func test_runCommandDryrunDefaultIsFalse() throws {
        let cmd = try RunCommand.parse(["打开计算器"])
        XCTAssertFalse(cmd.dryrun)
    }

    // 验证 RunCommand 正确解析 --max-steps 选项
    func test_runCommandParsesMaxSteps() throws {
        let cmd = try RunCommand.parse(["打开计算器", "--max-steps", "5"])
        XCTAssertEqual(cmd.maxSteps, 5)
    }

    // 验证 RunCommand 默认 maxSteps=nil
    func test_runCommandMaxStepsDefaultIsNil() throws {
        let cmd = try RunCommand.parse(["打开计算器"])
        XCTAssertNil(cmd.maxSteps)
    }

    // 验证 RunCommand 正确解析 --max-batches 选项
    func test_runCommandParsesMaxBatches() throws {
        let cmd = try RunCommand.parse(["打开计算器", "--max-batches", "3"])
        XCTAssertEqual(cmd.maxBatches, 3)
    }

    // 验证 RunCommand 默认 maxBatches=nil
    func test_runCommandMaxBatchesDefaultIsNil() throws {
        let cmd = try RunCommand.parse(["打开计算器"])
        XCTAssertNil(cmd.maxBatches)
    }

    // 验证 RunCommand 正确解析 --allow-foreground flag
    func test_runCommandParsesAllowForeground() throws {
        let cmd = try RunCommand.parse(["打开计算器", "--allow-foreground"])
        XCTAssertTrue(cmd.allowForeground)
    }

    // 验证 RunCommand 正确解析 --verbose flag
    func test_runCommandParsesVerbose() throws {
        let cmd = try RunCommand.parse(["打开计算器", "--verbose"])
        XCTAssertTrue(cmd.verbose)
    }

    // 验证 RunCommand 正确解析 --json flag
    func test_runCommandParsesJson() throws {
        let cmd = try RunCommand.parse(["打开计算器", "--json"])
        XCTAssertTrue(cmd.json)
    }

    // 验证 RunCommand 缺少 task 参数时报错
    func test_runCommandRequiresTaskArgument() throws {
        XCTAssertThrowsError(try RunCommand.parse([])) { error in
            XCTAssertNotNil(error, "Missing 'task' argument should throw an error")
        }
    }

    // 验证 RunCommand 解析所有参数组合
    func test_runCommandParsesAllArgumentsCombined() throws {
        let cmd = try RunCommand.parse([
            "打开计算器并输入1+1",
            "--dryrun",
            "--max-steps", "10",
            "--max-batches", "4",
            "--allow-foreground",
            "--verbose",
            "--json"
        ])
        XCTAssertEqual(cmd.task, "打开计算器并输入1+1")
        XCTAssertTrue(cmd.dryrun)
        XCTAssertEqual(cmd.maxSteps, 10)
        XCTAssertEqual(cmd.maxBatches, 4)
        XCTAssertTrue(cmd.allowForeground)
        XCTAssertTrue(cmd.verbose)
        XCTAssertTrue(cmd.json)
    }

    // MARK: - SetupCommand 骨架验证

    // 验证 SetupCommand 存在且可解析
    func test_setupCommandExists() throws {
        let cmd = try SetupCommand.parse([])
        XCTAssertNotNil(cmd)
    }

    // MARK: - DoctorCommand 骨架验证

    // 验证 DoctorCommand 存在且可解析
    func test_doctorCommandExists() throws {
        let cmd = try DoctorCommand.parse([])
        XCTAssertNotNil(cmd)
    }

    // MARK: - AxionVersion 验证

    // 验证 AxionVersion.current 返回有效版本字符串
    func test_axionVersion_currentIsNotEmpty() {
        XCTAssertFalse(
            AxionVersion.current.isEmpty,
            "AxionVersion.current should not be empty"
        )
    }

    // 验证 AxionVersion.current 与 VERSION 文件一致
    func test_axionVersion_matchesVersionFile() {
        XCTAssertEqual(
            AxionVersion.current,
            "0.1.0",
            "AxionVersion.current should match VERSION file content"
        )
    }
}
