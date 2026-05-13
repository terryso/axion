import XCTest
import ArgumentParser
@testable import AxionCLI

// [P0] ATDD GREEN-PHASE — Story 5.1 AC1

final class ServerCommandTests: XCTestCase {

    // MARK: - AC1: Server command skeleton and parameter parsing

    func test_serverCommand_defaultPort_is4242() throws {
        let cmd = try ServerCommand.parse([])
        XCTAssertEqual(cmd.port, 4242, "Default port should be 4242")
    }

    func test_serverCommand_defaultHost_is127_0_0_1() throws {
        let cmd = try ServerCommand.parse([])
        XCTAssertEqual(cmd.host, "127.0.0.1", "Default host should be 127.0.0.1")
    }

    func test_serverCommand_parsesCustomPort() throws {
        let cmd = try ServerCommand.parse(["--port", "8080"])
        XCTAssertEqual(cmd.port, 8080)
    }

    func test_serverCommand_parsesCustomHost() throws {
        let cmd = try ServerCommand.parse(["--host", "0.0.0.0"])
        XCTAssertEqual(cmd.host, "0.0.0.0")
    }

    func test_serverCommand_parsesVerboseFlag() throws {
        let cmd = try ServerCommand.parse(["--verbose"])
        XCTAssertTrue(cmd.verbose)
    }

    func test_serverCommand_verboseDefaultIsFalse() throws {
        let cmd = try ServerCommand.parse([])
        XCTAssertFalse(cmd.verbose)
    }

    func test_serverCommand_parsesAllOptionsCombined() throws {
        let cmd = try ServerCommand.parse([
            "--port", "9090",
            "--host", "0.0.0.0",
            "--verbose"
        ])
        XCTAssertEqual(cmd.port, 9090)
        XCTAssertEqual(cmd.host, "0.0.0.0")
        XCTAssertTrue(cmd.verbose)
    }

    // MARK: - Story 5.3: --auth-key and --max-concurrent

    func test_serverCommand_authKey_defaultIsNil() throws {
        let cmd = try ServerCommand.parse([])
        XCTAssertNil(cmd.authKey, "Default auth-key should be nil")
    }

    func test_serverCommand_parsesAuthKey() throws {
        let cmd = try ServerCommand.parse(["--auth-key", "mysecret"])
        XCTAssertEqual(cmd.authKey, "mysecret")
    }

    func test_serverCommand_maxConcurrent_defaultIs10() throws {
        let cmd = try ServerCommand.parse([])
        XCTAssertEqual(cmd.maxConcurrent, 10, "Default max-concurrent should be 10")
    }

    func test_serverCommand_parsesMaxConcurrent() throws {
        let cmd = try ServerCommand.parse(["--max-concurrent", "5"])
        XCTAssertEqual(cmd.maxConcurrent, 5)
    }

    func test_serverCommand_maxConcurrent_zero_throwsError() {
        XCTAssertThrowsError(try ServerCommand.parse(["--max-concurrent", "0"]))
    }

    func test_serverCommand_maxConcurrent_negative_throwsError() {
        XCTAssertThrowsError(try ServerCommand.parse(["--max-concurrent", "-1"]))
    }

    func test_serverCommand_parsesAllStory53Options() throws {
        let cmd = try ServerCommand.parse([
            "--port", "4242",
            "--auth-key", "secret123",
            "--max-concurrent", "3"
        ])
        XCTAssertEqual(cmd.port, 4242)
        XCTAssertEqual(cmd.authKey, "secret123")
        XCTAssertEqual(cmd.maxConcurrent, 3)
    }

    // MARK: - AxionCLI integration

    func test_axionCLI_registersServerSubcommand() {
        XCTAssertTrue(
            AxionCLI.configuration.subcommands.contains(where: { $0 == ServerCommand.self }),
            "AxionCLI should register ServerCommand as a subcommand"
        )
    }
}
