import Foundation

/// SIGINT 信号处理器封装，用于 Chat REPL 的 Ctrl+C 优雅中断。
///
/// 使用 DispatchSource 模式（非 signal() 闭包），线程安全且可取消。
/// 参考同模式：RunOrchestrator.swift:164-170。
final class SignalHandler: Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _source: DispatchSourceSignal?
    private nonisolated(unsafe) static var _count: Int = 0

    /// 安装 SIGINT 处理器。重复调用是安全的（幂等）。
    /// handler 在 DispatchSource 全局队列上执行，应仅调用线程安全方法（如 Agent.interrupt()）。
    static func install(handler: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard _source == nil else { return } // 已安装

        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        source.setEventHandler { [lock] in
            lock.lock()
            _count += 1
            lock.unlock()
            handler()
        }
        source.resume()
        _source = source
    }

    /// 卸载处理器，恢复 SIGINT 默认行为。
    static func uninstall() {
        lock.lock()
        defer { lock.unlock() }
        _source?.cancel()
        _source = nil
        signal(SIGINT, SIG_DFL)
    }

    /// 返回自上次 reset 以来的信号触发次数。
    static func fireCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    /// 重置计数器为 0。
    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        _count = 0
    }

    /// 模拟一次信号触发（仅用于测试）。
    /// 直接递增计数器，不发送真实信号。
    static func simulateFire() {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
    }
}
