import Darwin
import Foundation

/// ESC 键中断监听器 — agent streaming 期间并发监听 ESC 按键。
///
/// 当 agent 在 streaming 时，REPL 主线程阻塞在 `for await messageStream`，
/// 无法读取键盘输入。此监听器在独立 Task 中以最小化 raw mode 轮询 stdin，
/// 检测到 ESC (0x1B) 后调用 `agent.interrupt()` 中断执行。
///
/// 生命周期：
/// 1. `init(onEscape:)` → 保存 termios + 进入 raw mode + 启动监听 Task
/// 2. streaming 循环运行中 → Task 轮询 stdin
/// 3. `cancel()` → 停止 Task + **等待 Task 完全退出** + 恢复 termios
///
/// **关键修复**：`cancel()` 必须等待 Task 完全退出后再恢复 termios。
/// 否则 Task 可能仍在阻塞读取 stdin，当 `readInput()` 重新进入 raw mode 时，
/// 僵尸 Task 的 `read()` 解除阻塞并吞掉用户的粘贴首字节（`\e[200~` 的 `\e`），
/// 导致 bracket paste 失效（需 3 次粘贴才能正常工作）。
///
/// 线程安全：`cancel()` 可从任意线程/actor 调用（通过 Task.cancel()）。
final class EscapeInterruptListener: @unchecked Sendable {
    private let originalTermios: termios
    private let storedTermios: Bool
    private let task: Task<Void, Never>

    /// Task 完成信号量 — 确保 cancel() 等待 Task 完全退出。
    /// 使用 @unchecked Sendable 因为 DispatchSemaphore 不是 Sendable，
    /// 但我们只在 cancel() 中等待，不跨线程竞争。
    private let completionSemaphore: DispatchSemaphore

    /// 启动 ESC 监听。
    ///
    /// - Parameter onEscape: 检测到 ESC 时调用的闭包（调用 `agent.interrupt()`）。
    init(onEscape: @escaping @Sendable () -> Void) {
        // 保存当前 termios
        var original = termios()
        let stored = tcgetattr(STDIN_FILENO, &original) == 0
        self.originalTermios = original
        self.storedTermios = stored
        self.completionSemaphore = DispatchSemaphore(value: 0)

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
        // 局部捕获 semaphore 避免 Task 闭包在所有成员初始化前捕获 self
        let semaphore = completionSemaphore
        task = Task<Void, Never> { [stored] in
            defer { semaphore.signal() }
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
    ///
    /// 确保监听 Task 完全退出后才恢复 termios，防止僵尸 Task 吞掉后续 stdin 数据。
    /// 修复粘贴问题：如果不等待 Task 退出，`readInput()` 进入 raw mode 后，
    /// 僵尸 Task 的 `read()` 会解阻塞并消费用户粘贴的首字节。
    func cancel() {
        task.cancel()

        // 如果 Task 的 read() 正在阻塞，需要解除阻塞。
        // 设置 VMIN=0, VTIME=0（立即返回）让阻塞中的 read() 尽快返回，
        // 然后 Task 检查 Task.isCancelled 并退出。
        if storedTermios {
            var unblock = originalTermios
            unblock.c_iflag &= ~UInt(ICRNL | IXON)
            unblock.c_lflag &= ~UInt(ECHO | ICANON | ISIG)
            unblock.c_cc.16 = 0  // VMIN = 0
            unblock.c_cc.17 = 0  // VTIME = 0（read() 立即返回）
            tcsetattr(STDIN_FILENO, TCSANOW, &unblock)
        }

        // 等待 Task 完全退出（最多 200ms）
        _ = completionSemaphore.wait(timeout: DispatchTime.now() + .milliseconds(200))

        // 恢复原始 termios，并丢弃可能被僵尸 Task 部分消费的残留输入
        if storedTermios {
            var restore = originalTermios
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &restore)
        }
    }
}
