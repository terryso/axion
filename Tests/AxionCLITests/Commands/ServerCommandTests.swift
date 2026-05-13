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

    // MARK: - AxionCLI integration

    func test_axionCLI_registersServerSubcommand() {
        XCTAssertTrue(
            AxionCLI.configuration.subcommands.contains(where: { $0 == ServerCommand.self }),
            "AxionCLI should register ServerCommand as a subcommand"
        )
    }
}
