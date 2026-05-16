import Testing
import OpenAgentSDK

@testable import AxionCLI

@Suite("PauseToolRegistration")
struct PauseToolRegistrationTests {

    @Test("createPauseForHumanTool returns tool protocol")
    func createPauseForHumanToolReturnsToolProtocol() {
        let tool = createPauseForHumanTool()
        #expect(tool.name == "pause_for_human")
    }

    @Test("pause tool can be added to tools array")
    func pauseToolCanBeAddedToToolsArray() {
        let tools: [ToolProtocol] = [createPauseForHumanTool()]
        #expect(tools.count == 1)
        #expect(tools.first?.name == "pause_for_human")
    }
}
