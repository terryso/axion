import Testing
import OpenAgentSDK

@testable import AxionCLI

@Suite("TakeoverIntegration")
struct TakeoverIntegrationTests {

    // MARK: - PausedData 事件解析

    @Test("system message paused subtype contains paused data")
    func systemMessagePausedSubtypeContainsPausedData() {
        let pausedData = SDKMessage.PausedData(reason: "无法找到按钮")
        let systemData = SDKMessage.SystemData(
            subtype: .paused,
            message: "Agent paused: 无法找到按钮",
            sessionId: "test-session",
            pausedData: pausedData
        )
        let message = SDKMessage.system(systemData)

        if case .system(let data) = message {
            #expect(data.subtype == .paused)
            #expect(data.pausedData?.reason == "无法找到按钮")
        } else {
            Issue.record("Expected .system case")
        }
    }

    @Test("system message pausedTimeout subtype")
    func systemMessagePausedTimeoutSubtype() {
        let pausedData = SDKMessage.PausedData(reason: "超时原因", canResume: false)
        let systemData = SDKMessage.SystemData(
            subtype: .pausedTimeout,
            message: "Pause timed out after 300000ms",
            sessionId: "test-session",
            pausedData: pausedData
        )
        let message = SDKMessage.system(systemData)

        if case .system(let data) = message {
            #expect(data.subtype == .pausedTimeout)
            #expect(data.pausedData?.canResume == false)
        } else {
            Issue.record("Expected .system case")
        }
    }

    // MARK: - TakeoverAction 与 SDK 调用映射

    @Test("resume action resume flow verify action and output")
    func resumeActionResumeFlowVerifyActionAndOutput() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "" }
        )

        let action = io.displayTakeoverPrompt(reason: "目标不存在", allowForeground: false)
        #expect(action == .resume)

        let combined = output.joined(separator: "\n")
        #expect(combined.contains("目标不存在"))
        #expect(combined.contains("继续执行"))
    }

    @Test("skip action skip flow verify action and output")
    func skipActionSkipFlowVerifyActionAndOutput() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "skip" }
        )

        let action = io.displayTakeoverPrompt(reason: "无法操作", allowForeground: false)
        #expect(action == .skip)

        let combined = output.joined(separator: "\n")
        #expect(combined.contains("无法操作"))
        #expect(combined.contains("跳过"))
    }

    // MARK: - TakeoverIO 与 system message 的协作

    @Test("takeoverIO paused resume flow")
    func takeoverIOPausedResumeFlow() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { "" }
        )

        let action = io.displayTakeoverPrompt(reason: "无法找到目标", allowForeground: false)
        #expect(action == .resume)

        let combined = output.joined(separator: "\n")
        #expect(combined.contains("无法找到目标"))
        #expect(combined.contains("继续执行"))
    }

    @Test("takeoverIO pausedTimeout displays timeout")
    func takeoverIOPausedTimeoutDisplaysTimeout() {
        var output: [String] = []
        let io = TakeoverIO(
            write: { output.append($0) },
            readLine: { nil }
        )

        io.displayTimeoutPrompt()
        let combined = output.joined(separator: "\n")
        #expect(combined.contains("超时"))
        #expect(combined.contains("任务终止"))
    }

    @Test("takeoverIO abort with steps displays summary")
    func takeoverIOAbortWithStepsDisplaysSummary() {
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
        #expect(action == .abort)
        let combined = output.joined(separator: "\n")
        #expect(combined.contains("已完成 3 步"))
    }
}
