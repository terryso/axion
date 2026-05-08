import XCTest
@testable import AxionCore
import Foundation

// ATDD Red-Phase Test Scaffolds for Story 1.1
// AC: #1 - SPM Build Success
// AC: #6 - Protocol file locations
// These integration tests verify the SPM project structure compiles
// and that protocol files exist in the correct locations.
// Priority: P0 (foundational - everything depends on this)

final class SPMScaffoldTests: XCTestCase {

    // MARK: - AC1: SPM Build Verification

    // [P0] AxionCore module can be imported (proves it compiles as library target)
    // This test passing means `swift build` succeeded for AxionCore
    func test_axionCore_module_compiles() throws {
        // Given: The AxionCore module
        // When: This test file compiles (it imports @testable import AxionCore)
        // Then: AxionCore library target exists and compiles

        // If we reach this point, AxionCore compiled successfully
        // Verify key types exist
        let _ = Plan(id: UUID(), task: "test", steps: [], stopWhen: [], maxRetries: 0)
        let _ = RunState.planning
        let _ = AxionConfig.default
    }

    // MARK: - AC6: Protocol File Location Verification

    // [P0] PlannerProtocol exists in AxionCore
    func test_plannerProtocol_existsInAxionCore() throws {
        // Given: AxionCore module
        // When: Checking for PlannerProtocol
        // Then: It is accessible from AxionCore
        let _ = PlannerProtocol.self
    }

    // [P0] ExecutorProtocol exists in AxionCore
    func test_executorProtocol_existsInAxionCore() throws {
        let _ = ExecutorProtocol.self
    }

    // [P0] VerifierProtocol exists in AxionCore
    func test_verifierProtocol_existsInAxionCore() throws {
        let _ = VerifierProtocol.self
    }

    // [P0] MCPClientProtocol exists in AxionCore
    func test_mcpClientProtocol_existsInAxionCore() throws {
        let _ = MCPClientProtocol.self
    }

    // [P0] OutputProtocol exists in AxionCore
    func test_outputProtocol_existsInAxionCore() throws {
        let _ = OutputProtocol.self
    }

    // [P1] Constants exist in AxionCore
    func test_toolNamesConstant_existsInAxionCore() throws {
        // Verify ToolNames constant structure exists
        let _ = ToolNames.self
    }

    // [P1] AxionError conforms to Error
    func test_axionError_conformsToError() throws {
        // Given: An AxionError value
        let error = AxionError.mcpError(tool: "test", reason: "test")

        // Then: It conforms to Swift's Error protocol
        let _: any Error = error
    }

    // [P1] RunContext model exists
    func test_runContext_existsInAxionCore() throws {
        // Verify RunContext is accessible
        let _ = RunContext.self
    }

    // [P1] ExecutedStep model exists
    func test_executedStep_existsInAxionCore() throws {
        // Verify ExecutedStep is accessible
        let _ = ExecutedStep.self
    }
}
