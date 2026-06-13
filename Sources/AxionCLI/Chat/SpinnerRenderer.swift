import Foundation

/// 进度 Spinner — 在 stderr 显示动态 spinner 动画。
///
/// 使用**专用 `Thread`**（非 GCD `DispatchSourceTimer`）驱动每 100ms 刷新：raw OS 线程由
/// 内核抢占式调度，不受 GCD 线程池上限 / cooperative 池阻塞检测影响，在 `storage_scan` 等
/// 阻塞型工具执行期间也能稳定刷新。
///
/// 历史：早期用 `DispatchSourceTimer` + `.utility` GCD 队列，在 `storage_scan` 期间被饿死
/// （仅第一帧渲染出 `0.0s`，之后 100ms 重复帧拿不到线程）。提升到 `.userInitiated` 仍未根治
/// ——根因是扫描里漫长的阻塞 `resourceValues` 调用（尤指目录的 `totalFileSizeKey` 递归求和）
/// 在 cooperative 池上触发 Swift 阻塞检测 → GCD 线程膨胀 → 无可用线程调度 spinner 定时器。
/// 改用专用 `Thread`（`.userInteractive` 优先级）后，内核直接调度，彻底免疫。
///
/// 非 TTY 环境自动静默跳过。支持延迟启动（`delayMs > 0` 时不立即显示）。
///
/// 显示实时耗时：`⏳ 思考中 2.3s ⠙` — 受 Codex StatusIndicatorWidget 启发。
///
/// Codex-inspired shimmer: 消息文本施加余弦扫描微光效果，
/// 使"思考中"等状态文字产生流动光效，增强活跃工作状态的视觉反馈。
final class SpinnerRenderer {
    private let frames = Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
    private let isTTY: Bool
    private let colorProfile: TerminalColorProfile
    private let writeStderr: @Sendable (String) -> Void

    /// 当前动画线程（start() 创建、stop() 清空）。线程退出由其专属 stopFlag 驱动，
    /// 释放 `thread` 引用不会杀死线程——线程在下一次 stopFlag 轮询后自行退出。
    private var thread: Thread?

    /// 当前动画的停止标记。**每次 start() 新建一个**，避免新动画把仍在收尾的旧线程"复活"
    /// （旧线程持有的是旧 flag，stop()/下一次 start() 置位旧 flag → 旧线程退出，互不干扰）。
    private var currentStopFlag: SpinnerStopFlag?

    init(isTTY: Bool = isatty(STDERR_FILENO) != 0,
         colorProfile: TerminalColorProfile = .detect(),
         writeStderr: @escaping @Sendable (String) -> Void = { fputs($0, stderr); fflush(stderr) }) {
        self.isTTY = isTTY
        self.colorProfile = colorProfile
        self.writeStderr = writeStderr
    }

    /// 在 stderr 开始显示 spinner。
    /// - Parameters:
    ///   - message: spinner 旁显示的文字（如工具名或"思考中"）
    ///   - delayMs: 延迟启动毫秒数（0 = 立即启动，用于 LLM 等待 >500ms 阈值）
    func start(message: String, delayMs: Int = 0) {
        guard isTTY else { return }
        stop()  // 置位旧 flag + 清空旧线程引用（旧线程随后自行退出）

        let flag = SpinnerStopFlag()
        currentStopFlag = flag
        flag.isStopped = false

        let config = SpinnerAnimationConfig(
            message: message,
            startTime: DispatchTime.now(),
            initialDelayMs: delayMs,
            frames: frames,
            writer: writeStderr,
            isTTY: isTTY,
            colorProfile: colorProfile,
            stopFlag: flag
        )
        let t = Thread { SpinnerRenderer.runAnimation(config: config) }
        // .userInteractive：spinner 是用户正在等待的实时 UI 反馈，须在密集工具执行期间也能抢占调度。
        t.qualityOfService = .userInteractive
        t.start()
        thread = t
    }

    /// 停止 spinner 并清除行（仅当动画已渲染过帧时才输出清除码；延迟期内未渲染则不清行）。
    func stop() {
        let flag = currentStopFlag
        flag?.isStopped = true
        let didRender = flag?.didRender ?? false
        thread = nil
        currentStopFlag = nil
        if isTTY && didRender {
            writeStderr("\r\033[K")
        }
    }

    // MARK: - Animation (runs on a dedicated Thread)

    /// 专用线程上的动画循环。仅接收纯 Sendable `config`，**不捕获 self**（满足 `@Sendable`）。
    private static func runAnimation(config: SpinnerAnimationConfig) {
        // 延迟启动：分段睡眠以便及时响应 stop。
        if config.initialDelayMs > 0 {
            let totalUs = config.initialDelayMs * 1000
            var slept = 0
            while slept < totalUs && !config.stopFlag.isStopped {
                let chunk = min(10_000, totalUs - slept)
                usleep(UInt32(chunk))
                slept += chunk
            }
        }

        var index = 0
        // 主循环：每 ~100ms 渲染一帧；分段睡眠以便 stop() 后及时退出（最迟 10ms）。
        while !config.stopFlag.isStopped {
            let frame = config.frames[index % config.frames.count]
            let elapsedNs = DispatchTime.now().uptimeNanoseconds - config.startTime.uptimeNanoseconds
            let elapsedMs = Int(elapsedNs / 1_000_000)
            let elapsedStr = Self.formatElapsedMs(elapsedMs)
            // 写入前再确认一次未停止，缩小 stop() 清行与最后一帧之间的竞态窗口。
            guard !config.stopFlag.isStopped else { return }
            // Codex-inspired shimmer: 消息文本施加流动微光效果
            let shimmeredMessage = ShimmerText.render(
                text: config.message,
                elapsedMs: elapsedMs,
                isTTY: config.isTTY,
                profile: config.colorProfile
            )
            config.writer("\r\("⏳") \(shimmeredMessage) \(elapsedStr) \(frame) ")
            config.stopFlag.markRendered()
            index += 1

            var slept = 0
            while slept < 100_000 && !config.stopFlag.isStopped {
                let chunk = min(10_000, 100_000 - slept)
                usleep(UInt32(chunk))
                slept += chunk
            }
        }
    }

    /// 格式化毫秒为紧凑的耗时字符串。
    ///
    /// - < 1s → "0.3s"
    /// - ≥ 1s → "1.2s", "12.3s"
    /// - ≥ 60s → "1m 02s"
    /// - ≥ 1h → "1h 02m 03s"
    static func formatElapsedMs(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        if totalSeconds < 60 {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
        }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        }
        return String(format: "%dm %02ds", minutes, seconds)
    }
}

/// 动画线程捕获的纯 Sendable 配置（不捕获 self，规避 Thread block 的 `@Sendable` 要求）。
private struct SpinnerAnimationConfig: Sendable {
    let message: String
    let startTime: DispatchTime
    let initialDelayMs: Int
    let frames: [Character]
    let writer: @Sendable (String) -> Void
    let isTTY: Bool
    let colorProfile: TerminalColorProfile
    let stopFlag: SpinnerStopFlag
}

/// 线程安全停止标记：`stop()`（任意线程）置位，动画线程（专用 Thread）轮询后退出。
/// `didRender`：动画是否已真正渲染过帧（用于决定 stop() 是否输出清行码——延迟期内未渲染
/// 则无需清行，与旧 `DispatchSourceTimer` 行为一致）。
final class SpinnerStopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _stopped = true
    private var _didRender = false
    var isStopped: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _stopped }
        set { lock.lock(); _stopped = newValue; lock.unlock() }
    }
    var didRender: Bool { lock.lock(); defer { lock.unlock() }; return _didRender }
    func markRendered() { lock.lock(); _didRender = true; lock.unlock() }
}
