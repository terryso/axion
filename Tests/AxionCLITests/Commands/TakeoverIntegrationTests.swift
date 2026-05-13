import XCTest
import OpenAgentSDK

@testable import AxionCLI

/// Story 7.1 Task 2: 测试 RunCommand stream 循环中的 paused 事件处理逻辑。
///
/// 由于 RunCommand.run() 是 async 方法且依赖大量基础设施，
/// 这里通过测试 TakeoverAction 与模拟的消息处理逻辑来验证核心分支。
final class TakeoverIntegrationTests: XCTestCase {

    // MARK: - PausedData 事件解析

    func test_systemMessage_pausedSubtype_containsPausedData() {
        let pausedData = SDKMessage.PausedData(reason: "无法找到按钮")
        let systemData = SDKMessage.SystemData(
            subtype: .paused,
            message: "Agent paused: 无法找到按钮",
            sessionId: "test-session",
            pausedData: pausedData
        )
        let message = SDKMessage.system(systemData)

        if case .system(let data) = message {
            XCTAssertEqual(data.subtype, .paused)
            XCTAssertEqual(data.pausedData?.reason, "无法找到按钮")
        } else {
            XCTFail("Expected .system case")
        }
    }

    func test_systemMessage_pausedTimeoutSubtype() {
        let pausedData = SDKMessage.PausedData(reason: "超时原因", canResume: false)
        let systemData = SDKMessage.SystemData(
            subtype: .pausedTimeout,
            message: "Pause timed out after 300000ms",
            sessionId: "test-session",
            pausedData: pausedData
        )
        let message = SDKMessage.system(systemData)

        if case .system(let data) = message {
            XCTAssertEqual(data.subtype, .pausedTimeout)
            XCTAssertEqual(data.pausedData?.canResume, false)
        } else {
            XCTFail("Expected .system case")
        }
    }

    // MARK: - TakeoverAction 与 SDK 调用映射

    func test_resumeAction_resumeFlow_verifyActionAndOutput() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "" }
        )

        let action = io.displayTakeoverPrompt(reason: "目标不存在", allowForeground: false)
        XCTAssertEqual(action, .resume)

        let combined = output.joined(separator: "\n")
        XCTAssertTrue(combined.contains("目标不存在"))
        XCTAssertTrue(combined.contains("继续执行"))
    }

    func test_skipAction_skipFlow_verifyActionAndOutput() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "skip" }
        )

        let action = io.displayTakeoverPrompt(reason: "无法操作", allowForeground: false)
        XCTAssertEqual(action, .skip)

        let combined = output.joined(separator: "\n")
        XCTAssertTrue(combined.contains("无法操作"))
        XCTAssertTrue(combined.contains("跳过"))
    }

    // MARK: - TakeoverIO 与 system message 的协作

    func test_takeoverIO_paused_resumeFlow() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "" }
        )

        let action = io.displayTakeoverPrompt(reason: "无法找到目标", allowForeground: false)
        XCTAssertEqual(action, .resume)

        let combined = output.joined(separator: "\n")
        XCTAssertTrue(combined.contains("无法找到目标"))
        XCTAssertTrue(combined.contains("继续执行"))
    }

    func test_takeoverIO_pausedTimeout_displaysTimeout() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { nil }
        )

        io.displayTimeoutPrompt()
        let combined = output.joined(separator: "\n")
        XCTAssertTrue(combined.contains("超时"))
        XCTAssertTrue(combined.contains("任务终止"))
    }

    func test_takeoverIO_abortWithSteps_displaysSummary() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "abort" }
        )

        let action = io.displayTakeoverPrompt(
            reason: "无法继续",
            allowForeground: false,
            completedSteps: 3
        )
        XCTAssertEqual(action, .abort)
        let combined = output.joined(separator: "\n")
        XCTAssertTrue(combined.contains("已完成 3 步"))
    }
}
