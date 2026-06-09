import Foundation

/// 文本微光动画渲染器 — 对文本施加余弦扫描高光带效果。
///
/// Codex-inspired (shimmer.rs): 使用余弦函数驱动的滑动高光带扫过文本字符，
/// 在"思考中"等状态标签上产生微妙的流动光效，增强视觉反馈。
///
/// 色彩降级链：
/// - TrueColor: RGB 渐变 (暗灰 → 亮蓝白)
/// - ANSI256: 灰色与亮紫灰交替
/// - ANSI16: Bold/Dim 交替
/// - Unknown: 无效果（纯文本直通）
///
/// 纯 struct，无状态，线程安全（可从 DispatchSourceTimer 回调安全调用）。
struct ShimmerText {

    // MARK: - Configuration

    /// 高光扫描周期（毫秒）— 与 Codex 的 2 秒周期一致。
    static let shimmerPeriodMs: Int = 2000

    /// 高光带宽度占文本长度的比例（0.3 = 30%）。
    static let bandWidthRatio: Double = 0.3

    // MARK: - TrueColor 颜色端点

    /// 基础色（暗灰）— 未被高光覆盖时的文本颜色。
    private static let baseRGB = (r: 100, g: 116, b: 139)   // slate-500

    /// 高光色（亮蓝白）— 高光带中心颜色。
    private static let highlightRGB = (r: 199, g: 210, b: 254) // indigo-200

    // MARK: - Public API

    /// 对文本施加微光动画效果。
    ///
    /// 根据经过时间计算高光带位置，对每个字符按距离高光中心的远近混合基础色与高光色。
    ///
    /// - Parameters:
    ///   - text: 待渲染的文本
    ///   - elapsedMs: 动画已运行的毫秒数（用于计算高光位置）
    ///   - isTTY: 是否连接到 TTY（非 TTY 跳过动画）
    ///   - profile: 终端颜色能力
    /// - Returns: 带 ANSI 颜色码的微光文本
    static func render(
        text: String,
        elapsedMs: Int,
        isTTY: Bool = isatty(STDERR_FILENO) != 0,
        profile: TerminalColorProfile = .detect()
    ) -> String {
        guard isTTY, !text.isEmpty else { return text }
        // unknown profile 无颜色支持，跳过微光效果
        guard profile != .unknown else { return text }

        let chars = Array(text)
        let count = chars.count
        guard count > 0 else { return text }

        // 计算扫描相位 (0.0 → 1.0 循环)
        let phase = Double(elapsedMs % shimmerPeriodMs) / Double(shimmerPeriodMs)

        let reset = "\u{1B}[0m"
        var result = ""

        for (i, char) in chars.enumerated() {
            // 字符在文本中的归一化位置 (0.0 → 1.0)
            let charPos = count > 1 ? Double(i) / Double(count - 1) : 0.5

            // 高光强度 (0.0 = 无高光, 1.0 = 完全高光)
            let intensity = computeIntensity(charPos: charPos, phase: phase)

            let colorCode = shimmerColor(intensity: intensity, profile: profile)
            result += "\(colorCode)\(char)"
        }

        return result + reset
    }

    // MARK: - Intensity Computation

    /// 计算字符在当前相位下的高光强度。
    ///
    /// 使用环形距离确保高光带在文本两端之间平滑过渡（wrap-around），
    /// 避免到达边缘时突然消失。
    ///
    /// - Parameters:
    ///   - charPos: 字符归一化位置 (0.0-1.0)
    ///   - phase: 当前扫描相位 (0.0-1.0)
    /// - Returns: 高光强度 (0.0-1.0)
    static func computeIntensity(charPos: Double, phase: Double) -> Double {
        let rawDistance = abs(charPos - phase)
        // 环形距离：取直线路径和环绕路径的较短者
        let wrapDistance = min(rawDistance, 1.0 - rawDistance)
        let halfBand = bandWidthRatio / 2.0
        // 高斯式衰减：距离高光中心越远，强度越低
        guard halfBand > 0 else { return 0 }
        let normalized = wrapDistance / halfBand
        guard normalized < 1.0 else { return 0 }
        // 余弦平滑过渡 (1.0 at center → 0.0 at band edge)
        return 0.5 * (1.0 + cos(.pi * normalized))
    }

    // MARK: - Color Generation

    /// 根据高光强度生成 ANSI 颜色码。
    ///
    /// - Parameters:
    ///   - intensity: 高光强度 (0.0-1.0)
    ///   - profile: 终端颜色能力
    /// - Returns: ANSI 前景色转义序列
    static func shimmerColor(intensity: Double, profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor:
            return trueColorBlend(intensity: intensity)
        case .ansi256:
            return ansi256Blend(intensity: intensity)
        case .ansi16:
            return ansi16Blend(intensity: intensity)
        case .unknown:
            return ""
        }
    }

    /// TrueColor: RGB 线性混合 (基础色 ↔ 高光色)。
    private static func trueColorBlend(intensity: Double) -> String {
        let r = Int(Double(baseRGB.r) + intensity * Double(highlightRGB.r - baseRGB.r))
        let g = Int(Double(baseRGB.g) + intensity * Double(highlightRGB.g - baseRGB.g))
        let b = Int(Double(baseRGB.b) + intensity * Double(highlightRGB.b - baseRGB.b))
        return "\u{1B}[38;2;\(r);\(g);\(b)m"
    }

    /// ANSI256: 使用两个固定色码交替（灰 245 ↔ 亮紫灰 189）。
    private static func ansi256Blend(intensity: Double) -> String {
        // 阈值切换：避免每帧生成过多不同色码导致终端渲染抖动
        if intensity > 0.5 {
            return "\u{1B}[38;5;189m"   // 亮紫灰 (高光)
        } else if intensity > 0.1 {
            return "\u{1B}[38;5;252m"   // 亮灰 (过渡)
        }
        return "\u{1B}[38;5;245m"       // 中灰 (基础)
    }

    /// ANSI16: Bold/Dim 交替 — 有限颜色下的最佳效果。
    private static func ansi16Blend(intensity: Double) -> String {
        if intensity > 0.4 {
            return "\u{1B}[1m"   // bold (高光)
        }
        return "\u{1B}[2m"       // dim (基础)
    }
}
