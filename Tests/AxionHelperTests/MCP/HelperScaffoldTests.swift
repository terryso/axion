import Testing
import MCP
import MCPTool
@testable import AxionHelper

@Suite("Helper Scaffold")
struct HelperScaffoldTests {

    // MARK: - Module Import Verification

    @Test("MCP module imports successfully")
    func mcpModuleImportsSuccessfully() {
        let _ = MCPServer.self
    }

    @Test("MCPTool module imports successfully")
    func mcpToolModuleImportsSuccessfully() {
        let _ = Parameter<String>.self
    }

    @Test("AxionHelper target compiles")
    func axionHelperTargetCompiles() {
        #expect(true, "AxionHelper target compiles successfully")
    }

    @Test("ToolRegistrar type exists in AxionHelper")
    func toolRegistrarExistsInAxionHelper() {
        let _ = ToolRegistrar.self
    }
}
