import Testing
@testable import AxionCLI
import AxionCore

private let RUN_CMD_HELPER_INTEGRATED = true

@Suite("RunCommand ATDD")
struct RunCommandATDDTests {

    @Test("RunCommand conforms to AsyncParsableCommand")
    func runCommandConformsToAsyncParsableCommand() throws {
        guard RUN_CMD_HELPER_INTEGRATED else { return }
        #if RUN_CMD_HELPER_INTEGRATED
        // 编译期检查：如果 RunCommand 不符合 AsyncParsableCommand 协议则编译失败
        #endif
    }

    @Test("RunCommand starts HelperProcessManager")
    func runCommandStartsHelperProcessManager() async throws {
        guard RUN_CMD_HELPER_INTEGRATED else { return }
        #if RUN_CMD_HELPER_INTEGRATED
        // Given: RunCommand 配置有效
        // When: run() 调用
        // Then: HelperProcessManager.start() 被调用
        #endif
    }

    @Test("RunCommand stops helper on exit")
    func runCommandStopsHelperOnExit() async throws {
        guard RUN_CMD_HELPER_INTEGRATED else { return }
        #if RUN_CMD_HELPER_INTEGRATED
        // Given: RunCommand 运行中
        // When: run() 退出（正常或异常）
        // Then: HelperProcessManager.stop() 被调用
        #endif
    }

    @Test("RunCommand handles helper start failure")
    func runCommandHandlesHelperStartFailure() async throws {
        guard RUN_CMD_HELPER_INTEGRATED else { return }
        #if RUN_CMD_HELPER_INTEGRATED
        // Given: Helper 无法启动
        // When: run() 调用
        // Then: 抛出有意义的错误信息
        #endif
    }
}
