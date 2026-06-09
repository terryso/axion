import Foundation
@testable import AxionCLI

/// 测试用 MockKeyReader — 注入预定义 KeyEvent 序列。
///
/// 线程安全：所有状态通过 nonisolated(unsafe) + 串行访问保证。
final class MockKeyReader: KeyReading, Sendable {
    nonisolated(unsafe) private var events: [KeyEvent]
    nonisolated(unsafe) private var index = 0

    init(_ events: [KeyEvent]) {
        self.events = events
    }

    func readNext() -> KeyEvent? {
        guard index < events.count else { return .eof }
        let event = events[index]
        index += 1
        return event
    }
}
