import Testing
import ArgumentParser
@testable import AxionCLI

@Suite("ServerCommand")
struct ServerCommandTests {

    @Test("server command default port is 4242")
    func serverCommandDefaultPortIs4242() throws {
        let cmd = try ServerCommand.parse([])
        #expect(cmd.port == 4242, "Default port should be 4242")
    }

    @Test("server command default host is 127.0.0.1")
    func serverCommandDefaultHostIs127_0_0_1() throws {
        let cmd = try ServerCommand.parse([])
        #expect(cmd.host == "127.0.0.1", "Default host should be 127.0.0.1")
    }

    @Test("server command parses custom port")
    func serverCommandParsesCustomPort() throws {
        let cmd = try ServerCommand.parse(["--port", "8080"])
        #expect(cmd.port == 8080)
    }

    @Test("server command parses custom host")
    func serverCommandParsesCustomHost() throws {
        let cmd = try ServerCommand.parse(["--host", "0.0.0.0"])
        #expect(cmd.host == "0.0.0.0")
    }

    @Test("server command parses verbose flag")
    func serverCommandParsesVerboseFlag() throws {
        let cmd = try ServerCommand.parse(["--verbose"])
        #expect(cmd.verbose)
    }

    @Test("server command verbose default is false")
    func serverCommandVerboseDefaultIsFalse() throws {
        let cmd = try ServerCommand.parse([])
        #expect(!cmd.verbose)
    }

    @Test("server command parses all options combined")
    func serverCommandParsesAllOptionsCombined() throws {
        let cmd = try ServerCommand.parse([
            "--port", "9090",
            "--host", "0.0.0.0",
            "--verbose"
        ])
        #expect(cmd.port == 9090)
        #expect(cmd.host == "0.0.0.0")
        #expect(cmd.verbose)
    }

    // MARK: - Story 5.3: --auth-key and --max-concurrent

    @Test("server command authKey default is nil")
    func serverCommandAuthKeyDefaultIsNil() throws {
        let cmd = try ServerCommand.parse([])
        #expect(cmd.authKey == nil, "Default auth-key should be nil")
    }

    @Test("server command parses authKey")
    func serverCommandParsesAuthKey() throws {
        let cmd = try ServerCommand.parse(["--auth-key", "mysecret"])
        #expect(cmd.authKey == "mysecret")
    }

    @Test("server command maxConcurrent default is 10")
    func serverCommandMaxConcurrentDefaultIs10() throws {
        let cmd = try ServerCommand.parse([])
        #expect(cmd.maxConcurrent == 10, "Default max-concurrent should be 10")
    }

    @Test("server command parses maxConcurrent")
    func serverCommandParsesMaxConcurrent() throws {
        let cmd = try ServerCommand.parse(["--max-concurrent", "5"])
        #expect(cmd.maxConcurrent == 5)
    }

    @Test("server command maxConcurrent zero throws error")
    func serverCommandMaxConcurrentZeroThrowsError() {
        #expect(throws: Error.self) {
            _ = try ServerCommand.parse(["--max-concurrent", "0"])
        }
    }

    @Test("server command maxConcurrent negative throws error")
    func serverCommandMaxConcurrentNegativeThrowsError() {
        #expect(throws: Error.self) {
            _ = try ServerCommand.parse(["--max-concurrent", "-1"])
        }
    }

    @Test("server command parses all story 5.3 options")
    func serverCommandParsesAllStory53Options() throws {
        let cmd = try ServerCommand.parse([
            "--port", "4242",
            "--auth-key", "secret123",
            "--max-concurrent", "3"
        ])
        #expect(cmd.port == 4242)
        #expect(cmd.authKey == "secret123")
        #expect(cmd.maxConcurrent == 3)
    }

    // MARK: - AxionCLI integration

    @Test("AxionCLI registers ServerCommand as subcommand")
    func axionCLIRegistersServerSubcommand() {
        #expect(
            AxionCLI.configuration.subcommands.contains(where: { $0 == ServerCommand.self }),
            "AxionCLI should register ServerCommand as a subcommand"
        )
    }
}
