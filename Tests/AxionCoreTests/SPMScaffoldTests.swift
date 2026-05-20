import Foundation
import Testing
@testable import AxionCore

@Suite("SPM Scaffold")
struct SPMScaffoldTests {

    @Test("AxionCore module compiles")
    func axionCoreModuleCompiles() throws {
        let _ = AxionConfig.default
    }

    @Test("MCPClientProtocol exists in AxionCore")
    func mcpClientProtocolExistsInAxionCore() throws {
        let _ = MCPClientProtocol.self
    }

    @Test("ToolNames constant exists in AxionCore")
    func toolNamesConstantExistsInAxionCore() throws {
        let _ = ToolNames.self
    }

    @Test("AxionError conforms to Error")
    func axionErrorConformsToError() throws {
        let error = AxionError.mcpError(tool: "test", reason: "test")
        let _: any Error = error
    }

    @Test("Value type exists in AxionCore")
    func valueTypeExistsInAxionCore() throws {
        let _ = Value.self
    }

    @Test("Skill model exists in AxionCore")
    func skillModelExistsInAxionCore() throws {
        let _ = Skill.self
    }
}
