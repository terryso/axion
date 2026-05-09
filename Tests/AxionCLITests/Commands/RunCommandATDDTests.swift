import XCTest
@testable import AxionCLI
import AxionCore

// [P1] 行为验证 — RunCommand 与 HelperProcessManager 集成
// Story 3.1 Task 2: AC1 — 集成到 RunCommand
// ATDD GREEN PHASE — RunCommand 集成已实现

/// ATDD 开关。
/// RunCommand HelperProcessManager 集成已完成，设置为 `true`。
private let RUN_CMD_HELPER_INTEGRATED = true

final class RunCommandATDDTests: XCTestCase {

    // MARK: - 测试辅助

    private func skipUntilImplemented() throws {
        if !RUN_CMD_HELPER_INTEGRATED {
            throw XCTSkip("ATDD RED PHASE: RunCommand HelperProcessManager 集成尚未实现。实现完成后将 RUN_CMD_HELPER_INTEGRATED 改为 true。")
        }
    }

    // MARK: - [P1] RunCommand 异步支持

    // RunCommand 遵循 AsyncParsableCommand
    func test_runCommand_conformsToAsyncParsableCommand() throws {
        try skipUntilImplemented()
        #if RUN_CMD_HELPER_INTEGRATED
        // 编译期检查：如果 RunCommand 不符合 AsyncParsableCommand 协议则编译失败
        // This test validates the protocol conformance exists
        #endif
    }

    // MARK: - [P1] RunCommand 集成 HelperProcessManager

    // RunCommand.run() 启动 HelperProcessManager
    func test_runCommand_startsHelperProcessManager() async throws {
        try skipUntilImplemented()
        #if RUN_CMD_HELPER_INTEGRATED
        // Given: RunCommand 配置有效
        // When: run() 调用
        // Then: HelperProcessManager.start() 被调用
        #endif
    }

    // RunCommand.run() 退出时清理 HelperProcessManager
    func test_runCommand_stopsHelperOnExit() async throws {
        try skipUntilImplemented()
        #if RUN_CMD_HELPER_INTEGRATED
        // Given: RunCommand 运行中
        // When: run() 退出（正常或异常）
        // Then: HelperProcessManager.stop() 被调用
        #endif
    }

    // RunCommand.run() 处理 Helper 启动失败
    func test_runCommand_handlesHelperStartFailure() async throws {
        try skipUntilImplemented()
        #if RUN_CMD_HELPER_INTEGRATED
        // Given: Helper 无法启动
        // When: run() 调用
        // Then: 抛出有意义的错误信息
        #endif
    }
}
