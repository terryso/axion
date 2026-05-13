import XCTest
import ArgumentParser
@testable import AxionCLI

// [P0] ATDD GREEN-PHASE — Story 6.1 AC1

final class McpCommandTests: XCTestCase {

    // MARK: - AC1: McpCommand registration

    func test_mcpCommand_registeredInAxionCLI() {
        let names = AxionCLI.configuration.subcommands.map { $0.configuration.commandName }
        XCTAssertTrue(names.contains("mcp"), "McpCommand should be registered as a subcommand")
    }

    func test_mcpCommand_defaultVerbose_isFalse() throws {
        let cmd = try McpCommand.parse([])
        XCTAssertFalse(cmd.verbose, "Default verbose should be false")
    }

    func test_mcpCommand_parsesVerbose() throws {
        let cmd = try McpCommand.parse(["--verbose"])
        XCTAssertTrue(cmd.verbose)
    }

    func test_mcpCommand_helpContainsMCPDescription() {
        let helpText = McpCommand.configuration.abstract
        XCTAssertTrue(helpText.contains("MCP"), "Abstract should mention MCP")
    }
}
