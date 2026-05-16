import Foundation
import Testing
@testable import AxionCore

// ATDD Red-Phase Test Scaffolds for Story 1.1
// AC: #1 - SPM Build Success
// AC: #6 - Protocol file locations

@Suite("SPM Scaffold")
struct SPMScaffoldTests {

    // MARK: - AC1: SPM Build Verification

    @Test("AxionCore module compiles")
    func axionCoreModuleCompiles() throws {
        let _ = Plan(id: UUID(), task: "test", steps: [], stopWhen: [], maxRetries: 0)
        let _ = RunState.planning
        let _ = AxionConfig.default
    }

    // MARK: - AC6: Protocol File Location Verification

    @Test("PlannerProtocol exists in AxionCore")
    func plannerProtocolExistsInAxionCore() throws {
        let _ = PlannerProtocol.self
    }

    @Test("ExecutorProtocol exists in AxionCore")
    func executorProtocolExistsInAxionCore() throws {
        let _ = ExecutorProtocol.self
    }

    @Test("VerifierProtocol exists in AxionCore")
    func verifierProtocolExistsInAxionCore() throws {
        let _ = VerifierProtocol.self
    }

    @Test("MCPClientProtocol exists in AxionCore")
    func mcpClientProtocolExistsInAxionCore() throws {
        let _ = MCPClientProtocol.self
    }

    @Test("OutputProtocol exists in AxionCore")
    func outputProtocolExistsInAxionCore() throws {
        let _ = OutputProtocol.self
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

    @Test("RunContext model exists in AxionCore")
    func runContextExistsInAxionCore() throws {
        let _ = RunContext.self
    }

    @Test("ExecutedStep model exists in AxionCore")
    func executedStepExistsInAxionCore() throws {
        let _ = ExecutedStep.self
    }
}
