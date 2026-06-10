import Darwin
import Dispatch

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
/// 权限提示期间可调用 `pause()` 暂停 stdin 轮询和恢复 canonical mode，
/// 让 `readLine()` 能正常读取用户输入；权限响应后调用 `resume()` 恢复监听。
///
/// 线程安全：`cancel()` 可从任意线程/actor 调用（通过 Task.cancel()）。
final class EscapeInterruptListener: @unchecked Sendable {
    private let originalTermios: termios
    private let storedTermios: Bool
    private var task: Task<Void, Never>?
    private var isPaused: Bool = false
    private let onEscape: @Sendable () -> Void
    /// 信号量 — 确认 polling Task 已完全退出（解决与 readLine() 的竞争）
    private let taskStopped = DispatchSemaphore(value: 0)

    /// 启动 ESC 监听。
    ///
    /// - Parameter onEscape: 检测到 ESC 时调用的闭包（调用 `agent.interrupt()`）。
    init(onEscape: @escaping @Sendable () -> Void) {
        self.onEscape = onEscape

        // 保存当前 termios
        var original = termios()
        let stored = tcgetattr(STDIN_FILENO, &original) == 0
        self.originalTermios = original
        self.storedTermios = stored

        // 进入最小化 raw mode（仅影响输入，保留 OPOST 保证输出正常）
        if stored {
            applyRawMode()
        }

        // 启动并发监听 Task
        self.task = startPollingTask()
    }

    // MARK: - Pause / Resume（供权限提示使用）

    /// 暂停 ESC 监听：停止 polling Task 并恢复 canonical mode。
    ///
    /// 调用后 `readLine()` 可以正常工作（终端回到 canonical mode，无并发 Task 抢夺 stdin）。
    /// - Returns: `true` 成功暂停；`false` 监听器未激活或已暂停。
    func pause() -> Bool {
        guard !isPaused else { return false }
        guard storedTermios else { return false }

        // 停止 polling Task 并等待其完全退出
        task?.cancel()
        // 解除阻塞中的 read()：设置 VMIN=0, VTIME=0 让 read() 立即返回
        unblockRead()
        _ = taskStopped.wait(timeout: .now() + .milliseconds(200))
        task = nil

        // 恢复 canonical mode
        restoreTermios()

        // 清除残留字节（如方向键 escape sequence 的残余字节 0x5B 0x41 等）
        // 防止后续 readSingleKey() 读到脏数据
        tcflush(STDIN_FILENO, TCIFLUSH)

        isPaused = true
        return true
    }

    /// 恢复 ESC 监听：重新进入 raw mode 并启动 polling Task。
    func resume() {
        guard isPaused else { return }
        guard storedTermios else { return }

        // 重新进入 raw mode
        applyRawMode()

        // 启动新的 polling Task
        task = startPollingTask()

        isPaused = false
    }

    /// 停止监听并恢复终端设置。
    ///
    /// 确保监听 Task 完全退出后才恢复 termios，防止僵尸 Task 吞掉后续 stdin 数据。
    func cancel() {
        if !isPaused {
            task?.cancel()
            // 解除阻塞中的 read()
            unblockRead()
            // 等待 Task 完全退出（最多 200ms）
            _ = taskStopped.wait(timeout: .now() + .milliseconds(200))
        }
        isPaused = false
        task = nil
        // 恢复原始 termios，并丢弃可能被僵尸 Task 部分消费的残留输入
        if storedTermios {
            var restore = originalTermios
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &restore)
        }
    }

    // MARK: - Private

    /// 将终端设为 raw mode（最小化：仅影响输入处理）。
    private func applyRawMode() {
        var raw = originalTermios
        raw.c_iflag &= ~UInt(ICRNL | IXON)
        raw.c_lflag &= ~UInt(ECHO | ICANON | ISIG)
        raw.c_cc.16 = 0  // VMIN = 0（非阻塞）
        raw.c_cc.17 = 1  // VTIME = 1（100ms 超时轮询）
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
    }

    /// 恢复终端到原始设置。
    private func restoreTermios() {
        var restore = originalTermios
        tcsetattr(STDIN_FILENO, TCSANOW, &restore)
    }

    /// 解除阻塞中的 read() — 设置 VMIN=0, VTIME=0 让 read() 立即返回。
    private func unblockRead() {
        guard storedTermios else { return }
        var unblock = originalTermios
        unblock.c_iflag &= ~UInt(ICRNL | IXON)
        unblock.c_lflag &= ~UInt(ECHO | ICANON | ISIG)
        unblock.c_cc.16 = 0  // VMIN = 0
        unblock.c_cc.17 = 0  // VTIME = 0（read() 立即返回）
        tcsetattr(STDIN_FILENO, TCSANOW, &unblock)
    }

    /// 创建 ESC 轮询 Task。
    ///
    /// Task 退出时通过 `taskStopped` 信号量通知调用方（`pause()`/`cancel()`），
    /// 确保在恢复 canonical mode 前已无并发 stdin 读取。
    private func startPollingTask() -> Task<Void, Never> {
        let stopped = taskStopped
        return Task<Void, Never> { [storedTermios, onEscape] in
            guard storedTermios else {
                stopped.signal()
                return
            }
            var byte: UInt8 = 0
            while !Task.isCancelled {
                let bytesRead = read(STDIN_FILENO, &byte, 1)
                if bytesRead == 1 && byte == 0x1B {
                    onEscape()
                    stopped.signal()
                    return
                }
                // bytesRead == 0 → VTIME 超时，继续轮询
                // bytesRead == -1 → 错误或被取消，退出
                if bytesRead < 0 && errno != EINTR {
                    stopped.signal()
                    return
                }
            }
            // Task 被 cancel — 通知可以安全恢复 canonical mode
            stopped.signal()
        }
    }
}

// MARK: - Reference Wrapper

/// EscapeInterruptListener 的引用包装器。
///
/// 用于在 `@Sendable` 闭包（如 `canUseTool`）中共享当前 turn 的 ESC 监听器引用。
/// `canUseTool` 在 REPL 循环前创建一次，但 ESC 监听器每轮 turn 重建，
/// 通过此包装器桥接生命周期差异。
///
/// 模式参照 `SessionAllowListRef`。
final class EscapeInterruptListenerRef: @unchecked Sendable {
    private var _listener: EscapeInterruptListener?

    init() {}

    func set(_ listener: EscapeInterruptListener?) {
        _listener = listener
    }

    /// 暂停当前 ESC 监听器。
    /// - Returns: 是否成功暂停。
    func pause() -> Bool {
        _listener?.pause() ?? false
    }

    /// 恢复当前 ESC 监听器。
    func resume() {
        _listener?.resume()
    }
}
