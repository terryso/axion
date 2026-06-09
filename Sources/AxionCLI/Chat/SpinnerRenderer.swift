import Foundation

/// 进度 Spinner — 在 stderr 显示动态 spinner 动画。
/// 使用 DispatchSourceTimer 定时刷新，非 async/await。
/// 非 TTY 环境自动静默跳过。
/// 支持延迟启动（delayMs > 500ms 时不立即显示 spinner）。
///
/// 显示实时耗时：`⏳ 思考中 2.3s ⠙` — 受 Codex StatusIndicatorWidget 启发。
final class SpinnerRenderer {
    private let frames = Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
    private var animationTimer: DispatchSourceTimer?
    private var delayTimer: DispatchSourceTimer?
    private let isTTY: Bool
    private let writeStderr: (String) -> Void

    /// 动画开始时刻，用于计算实时耗时。
    private var animationStartTime: DispatchTime?

    init(isTTY: Bool = isatty(STDERR_FILENO) != 0,
         writeStderr: @escaping (String) -> Void = { fputs($0, stderr); fflush(stderr) }) {
        self.isTTY = isTTY
        self.writeStderr = writeStderr
    }

    /// 在 stderr 开始显示 spinner。
    /// - Parameters:
    ///   - message: spinner 旁显示的文字（如工具名或"思考中"）
    ///   - delayMs: 延迟启动毫秒数（0 = 立即启动，用于 LLM 等待 >500ms 阈值）
    func start(message: String, delayMs: Int = 0) {
        guard isTTY else { return }
        stop()  // 清理已有的 timer

        if delayMs > 0 {
            let queue = DispatchQueue(label: "axion.spinner-delay", qos: .utility)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .milliseconds(delayMs), repeating: .never)
            let renderer = self
            timer.setEventHandler {
                renderer.startAnimation(message: message)
            }
            timer.resume()
            delayTimer = timer
        } else {
            startAnimation(message: message)
        }
    }

    /// 停止 spinner 并清除行（仅当动画曾启动时才输出清除码）。
    func stop() {
        let hadAnimation = animationTimer != nil
        animationTimer?.cancel()
        animationTimer = nil
        delayTimer?.cancel()
        delayTimer = nil
        animationStartTime = nil
        if isTTY && hadAnimation {
            writeStderr("\r\033[K")
        }
    }

    // MARK: - Private

    /// 立即启动 spinner 动画（每 100ms 刷新一帧）。
    private func startAnimation(message: String) {
        let startTime = DispatchTime.now()
        animationStartTime = startTime

        let queue = DispatchQueue(label: "axion.spinner", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // 100ms 刷新间隔 — 平衡流畅度与 CPU 开销
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))

        let frames = self.frames
        var index = 0
        let writer = self.writeStderr

        timer.setEventHandler {
            let frame = frames[index % frames.count]
            let elapsedNs = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
            let elapsedMs = Int(elapsedNs / 1_000_000)
            let elapsedStr = Self.formatElapsedMs(elapsedMs)
            writer("\r\("⏳") \(message) \(elapsedStr) \(frame) ")
            index += 1
        }
        timer.resume()
        animationTimer = timer
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
