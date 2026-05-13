import XCTest
import OpenAgentSDK

@testable import AxionCLI

/// Story 7.1 Task 1: 验证 pause_for_human 工具注册到 Agent。
final class PauseToolRegistrationTests: XCTestCase {

    /// 验证 createPauseForHumanTool() 返回有效的 ToolProtocol。
    func test_createPauseForHumanTool_returnsToolProtocol() {
        let tool = createPauseForHumanTool()
        XCTAssertEqual(tool.name, "pause_for_human")
    }

    /// 验证工具可以被放入数组（即兼容 [ToolProtocol]）。
    func test_pauseTool_canBeAddedToToolsArray() {
        let tools: [ToolProtocol] = [createPauseForHumanTool()]
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?.name, "pause_for_human")
    }
}
