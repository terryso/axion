import Testing
import ArgumentParser
@testable import AxionCLI

@Suite("McpCommand")
struct McpCommandTests {

    @Test("mcpCommand registered in AxionCLI")
    func mcpCommandRegisteredInAxionCLI() {
        let names = AxionCLI.configuration.subcommands.map { $0.configuration.commandName }
        #expect(names.contains("mcp"), "McpCommand should be registered as a subcommand")
    }

    @Test("mcpCommand default verbose is false")
    func mcpCommandDefaultVerboseIsFalse() throws {
        let cmd = try McpCommand.parse([])
        #expect(!cmd.verbose, "Default verbose should be false")
    }

    @Test("mcpCommand parses verbose")
    func mcpCommandParsesVerbose() throws {
        let cmd = try McpCommand.parse(["--verbose"])
        #expect(cmd.verbose)
    }

    @Test("mcpCommand help contains MCP description")
    func mcpCommandHelpContainsMCPDescription() {
        let helpText = McpCommand.configuration.abstract
        #expect(helpText.contains("MCP"), "Abstract should mention MCP")
    }
}
