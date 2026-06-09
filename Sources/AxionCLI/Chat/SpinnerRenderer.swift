import Foundation

/// 进度 Spinner — 在 stderr 显示动态 spinner 动画。
/// 使用 DispatchSourceTimer 定时刷新，非 async/await。
/// 非 TTY 环境自动静默跳过。
/// 支持延迟启动（delayMs > 500ms 时不立即显示 spinner）。
final class SpinnerRenderer {
    private let frames = Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
    private var animationTimer: DispatchSourceTimer?
    private var delayTimer: DispatchSourceTimer?
    private let isTTY: Bool
    private let writeStderr: (String) -> Void

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
        if isTTY && hadAnimation {
            writeStderr("\r\033[K")
        }
    }

    // MARK: - Private

    /// 立即启动 spinner 动画（每 80ms 刷新一帧）。
    private func startAnimation(message: String) {
        let queue = DispatchQueue(label: "axion.spinner", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(80))

        let frames = self.frames
        var index = 0
        let writer = self.writeStderr

        timer.setEventHandler {
            let frame = frames[index % frames.count]
            writer("\r\("⏳") \(message) \(frame) ")
            index += 1
        }
        timer.resume()
        animationTimer = timer
    }
}
