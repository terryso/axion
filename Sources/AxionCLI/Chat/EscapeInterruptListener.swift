import Darwin

/// ESC 键中断监听器 — agent streaming 期间并发监听 ESC 按键。
///
/// 当 agent 在 streaming 时，REPL 主线程阻塞在 `for await messageStream`，
/// 无法读取键盘输入。此监听器在独立 Task 中以最小化 raw mode 轮询 stdin，
/// 检测到 ESC (0x1B) 后调用 `agent.interrupt()` 中断执行。
///
/// 生命周期：
/// 1. `init(onEscape:)` → 保存 termios + 进入 raw mode + 启动监听 Task
/// 2. streaming 循环运行中 → Task 轮询 stdin
/// 3. `cancel()` → 停止 Task + 恢复 termios
///
/// 线程安全：`cancel()` 可从任意线程/actor 调用（通过 Task.cancel()）。
final class EscapeInterruptListener: @unchecked Sendable {
    private let originalTermios: termios
    private let storedTermios: Bool
    private let task: Task<Void, Never>

    /// 启动 ESC 监听。
    ///
    /// - Parameter onEscape: 检测到 ESC 时调用的闭包（调用 `agent.interrupt()`）。
    init(onEscape: @escaping @Sendable () -> Void) {
        // 保存当前 termios
        var original = termios()
        let stored = tcgetattr(STDIN_FILENO, &original) == 0
        self.originalTermios = original
        self.storedTermios = stored

        // 进入最小化 raw mode（仅影响输入，保留 OPOST 保证输出正常）
        if stored {
            var raw = original
            raw.c_iflag &= ~UInt(ICRNL | IXON)
            raw.c_lflag &= ~UInt(ECHO | ICANON | ISIG)
            raw.c_cc.16 = 0  // VMIN = 0（非阻塞）
            raw.c_cc.17 = 1  // VTIME = 1（100ms 超时轮询）
            tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        }

        // 启动并发监听 Task
        task = Task<Void, Never> { [stored] in
            guard stored else { return }
            var byte: UInt8 = 0
            while !Task.isCancelled {
                let bytesRead = read(STDIN_FILENO, &byte, 1)
                if bytesRead == 1 && byte == 0x1B {
                    onEscape()
                    return
                }
                // bytesRead == 0 → VTIME 超时，继续轮询
                // bytesRead == -1 → 错误或被取消，退出
                if bytesRead < 0 && errno != EINTR {
                    return
                }
            }
        }
    }

    /// 停止监听并恢复终端设置。
    func cancel() {
        task.cancel()
        if storedTermios {
            var restore = originalTermios
            tcsetattr(STDIN_FILENO, TCSANOW, &restore)
        }
    }
}
