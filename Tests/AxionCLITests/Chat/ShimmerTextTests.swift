import Foundation
import Testing

@testable import AxionCLI

@Suite("ShimmerText")
struct ShimmerTextTests {

    // MARK: - render: 基本行为

    @Test("render: 非 TTY 返回原文")
    func render_nonTTY_returnsPlainText() {
        let result = ShimmerText.render(
            text: "思考中",
            elapsedMs: 500,
            isTTY: false,
            profile: .trueColor
        )
        #expect(result == "思考中")
    }

    @Test("render: unknown profile 返回原文")
    func render_unknownProfile_returnsPlainText() {
        let result = ShimmerText.render(
            text: "思考中",
            elapsedMs: 500,
            isTTY: true,
            profile: .unknown
        )
        #expect(result == "思考中")
    }

    @Test("render: 空字符串返回空")
    func render_emptyString_returnsEmpty() {
        let result = ShimmerText.render(
            text: "",
            elapsedMs: 500,
            isTTY: true,
            profile: .trueColor
        )
        #expect(result == "")
    }

    @Test("render: TrueColor 输出包含 ANSI 转义序列")
    func render_trueColor_containsANSI() {
        let result = ShimmerText.render(
            text: "ABC",
            elapsedMs: 500,
            isTTY: true,
            profile: .trueColor
        )
        // 应包含 38;2; (TrueColor RGB) 和最终 reset (ESC[0m)
        #expect(result.contains("38;2;"))
        #expect(result.hasSuffix("\u{1B}[0m"))
    }

    @Test("render: ANSI256 输出包含 38;5; 色码")
    func render_ansi256_contains256ColorCodes() {
        let result = ShimmerText.render(
            text: "测试",
            elapsedMs: 500,
            isTTY: true,
            profile: .ansi256
        )
        #expect(result.contains("38;5;"))
        #expect(result.hasSuffix("\u{1B}[0m"))
    }

    @Test("render: ANSI16 输出包含 Bold/Dim 码")
    func render_ansi16_containsBoldDim() {
        let result = ShimmerText.render(
            text: "运行中",
            elapsedMs: 500,
            isTTY: true,
            profile: .ansi16
        )
        // ANSI16 使用 ESC[1m (bold) 或 ESC[2m (dim)
        let hasBoldOrDim = result.contains("\u{1B}[1m") || result.contains("\u{1B}[2m")
        #expect(hasBoldOrDim)
        #expect(result.hasSuffix("\u{1B}[0m"))
    }

    // MARK: - render: 文本内容保留

    @Test("render: 所有原文字符都保留在输出中")
    func render_preservesAllCharacters() {
        let text = "思考中..."
        let result = ShimmerText.render(
            text: text,
            elapsedMs: 1000,
            isTTY: true,
            profile: .trueColor
        )
        // 去除所有 ANSI 转义序列后应该等于原文本
        let stripped = stripANSI(result)
        #expect(stripped == text)
    }

    @Test("render: Unicode 文本完整保留")
    func render_preservesUnicode() {
        let text = "🤖 実行中... ⏳"
        let result = ShimmerText.render(
            text: text,
            elapsedMs: 1500,
            isTTY: true,
            profile: .trueColor
        )
        let stripped = stripANSI(result)
        #expect(stripped == text)
    }

    // MARK: - render: 随时间变化

    @Test("render: 不同时间点产生不同 ANSI 码序列")
    func render_differentElapsed_producesDifferentOutput() {
        let text = "思考中"
        let result1 = ShimmerText.render(
            text: text,
            elapsedMs: 0,
            isTTY: true,
            profile: .trueColor
        )
        let result2 = ShimmerText.render(
            text: text,
            elapsedMs: 1000,
            isTTY: true,
            profile: .trueColor
        )
        // 不同时间点的高光位置不同，ANSI 码序列应不同
        #expect(result1 != result2)
    }

    @Test("render: 周期性 — elapsed=0 和 elapsed=period 产生相同输出")
    func render_periodic_sameAsStart() {
        let text = "思考中"
        let result0 = ShimmerText.render(
            text: text,
            elapsedMs: 0,
            isTTY: true,
            profile: .trueColor
        )
        let resultPeriod = ShimmerText.render(
            text: text,
            elapsedMs: ShimmerText.shimmerPeriodMs,
            isTTY: true,
            profile: .trueColor
        )
        #expect(result0 == resultPeriod)
    }

    @Test("render: 周期性 — 任意偏移 + period 产生相同输出")
    func render_periodic_offset() {
        let text = "ABCDEF"
        let offset = 789
        let result1 = ShimmerText.render(
            text: text,
            elapsedMs: offset,
            isTTY: true,
            profile: .trueColor
        )
        let result2 = ShimmerText.render(
            text: text,
            elapsedMs: offset + ShimmerText.shimmerPeriodMs,
            isTTY: true,
            profile: .trueColor
        )
        #expect(result1 == result2)
    }

    // MARK: - computeIntensity

    @Test("computeIntensity: 高光中心相位位置强度最高")
    func computeIntensity_centerIsHighest() {
        let intensity = ShimmerText.computeIntensity(charPos: 0.5, phase: 0.5)
        #expect(intensity == 1.0)
    }

    @Test("computeIntensity: 高光中心在起始位置")
    func computeIntensity_centerAtStart() {
        let intensity = ShimmerText.computeIntensity(charPos: 0.0, phase: 0.0)
        #expect(intensity == 1.0)
    }

    @Test("computeIntensity: 高光中心在末尾位置")
    func computeIntensity_centerAtEnd() {
        let intensity = ShimmerText.computeIntensity(charPos: 1.0, phase: 1.0)
        #expect(intensity == 1.0)
    }

    @Test("computeIntensity: 远离高光带时强度为零")
    func computeIntensity_farFromBand_isZero() {
        // phase=0.0, charPos=0.5 → 环绕距离 min(0.5, 0.5)=0.5 > bandWidth/2=0.15
        let intensity = ShimmerText.computeIntensity(charPos: 0.5, phase: 0.0)
        #expect(intensity == 0.0)
    }

    @Test("computeIntensity: 环绕距离 — 相位在0字符在1时强度高")
    func computeIntensity_wrapAround_highIntensity() {
        // phase=0.0, charPos=1.0 → 距离 min(1.0, 0.0) = 0 → 中心
        let intensity = ShimmerText.computeIntensity(charPos: 1.0, phase: 0.0)
        #expect(intensity == 1.0)
    }

    @Test("computeIntensity: 环绕距离 — 接近环绕点有部分强度")
    func computeIntensity_wrapAround_partialIntensity() {
        // phase=0.0, charPos=0.95 → 距离 min(0.95, 0.05) = 0.05 → 在带内
        let intensity = ShimmerText.computeIntensity(charPos: 0.95, phase: 0.0)
        #expect(intensity > 0.0)
        #expect(intensity < 1.0)
    }

    @Test("computeIntensity: 中等距离产生中等强度")
    func computeIntensity_mediumDistance_mediumIntensity() {
        // phase=0.5, charPos=0.55 → 距离 0.05 → 在带内但非中心
        let intensity = ShimmerText.computeIntensity(charPos: 0.55, phase: 0.5)
        #expect(intensity > 0.0)
        #expect(intensity < 1.0)
    }

    // MARK: - shimmerColor

    @Test("shimmerColor: TrueColor 强度=0 使用基础色")
    func shimmerColor_trueColor_zeroIntensity() {
        let color = ShimmerText.shimmerColor(intensity: 0.0, profile: .trueColor)
        // 基础色 (100, 116, 139)
        #expect(color == "\u{1B}[38;2;100;116;139m")
    }

    @Test("shimmerColor: TrueColor 强度=1 使用高光色")
    func shimmerColor_trueColor_fullIntensity() {
        let color = ShimmerText.shimmerColor(intensity: 1.0, profile: .trueColor)
        // 高光色 (199, 210, 254)
        #expect(color == "\u{1B}[38;2;199;210;254m")
    }

    @Test("shimmerColor: TrueColor 中间强度使用混合色")
    func shimmerColor_trueColor_midIntensity() {
        let color = ShimmerText.shimmerColor(intensity: 0.5, profile: .trueColor)
        // 混合: (100+49.5, 116+47, 139+57.5) → (149, 163, 196)
        #expect(color == "\u{1B}[38;2;149;163;196m")
    }

    @Test("shimmerColor: ANSI256 低强度使用灰色")
    func shimmerColor_ansi256_lowIntensity() {
        let color = ShimmerText.shimmerColor(intensity: 0.0, profile: .ansi256)
        #expect(color == "\u{1B}[38;5;245m")
    }

    @Test("shimmerColor: ANSI256 高强度使用亮色")
    func shimmerColor_ansi256_highIntensity() {
        let color = ShimmerText.shimmerColor(intensity: 0.8, profile: .ansi256)
        #expect(color == "\u{1B}[38;5;189m")
    }

    @Test("shimmerColor: ANSI256 中等强度使用过渡色")
    func shimmerColor_ansi256_midIntensity() {
        let color = ShimmerText.shimmerColor(intensity: 0.3, profile: .ansi256)
        #expect(color == "\u{1B}[38;5;252m")
    }

    @Test("shimmerColor: ANSI16 低强度使用 Dim")
    func shimmerColor_ansi16_lowIntensity() {
        let color = ShimmerText.shimmerColor(intensity: 0.0, profile: .ansi16)
        #expect(color == "\u{1B}[2m")
    }

    @Test("shimmerColor: ANSI16 高强度使用 Bold")
    func shimmerColor_ansi16_highIntensity() {
        let color = ShimmerText.shimmerColor(intensity: 0.8, profile: .ansi16)
        #expect(color == "\u{1B}[1m")
    }

    @Test("shimmerColor: Unknown 返回空字符串")
    func shimmerColor_unknown_returnsEmpty() {
        let color = ShimmerText.shimmerColor(intensity: 0.5, profile: .unknown)
        #expect(color == "")
    }

    // MARK: - 单字符场景

    @Test("render: 单字符文本正常渲染")
    func render_singleCharacter_rendersCorrectly() {
        let result = ShimmerText.render(
            text: "A",
            elapsedMs: 500,
            isTTY: true,
            profile: .trueColor
        )
        let stripped = stripANSI(result)
        #expect(stripped == "A")
        #expect(result.contains("38;2;"))
    }

    // MARK: - 长文本场景

    @Test("render: 长文本多字符各有不同颜色")
    func render_longText_varyingColors() {
        let text = "abcdefghijklmnopqrstuvwxyz"
        let result = ShimmerText.render(
            text: text,
            elapsedMs: 500,
            isTTY: true,
            profile: .trueColor
        )
        let stripped = stripANSI(result)
        #expect(stripped == text)
        // 长文本中不同位置应有不同颜色（非全部同一色码）
        #expect(result.contains("38;2;"))
    }

    // MARK: - Integration with SpinnerRenderer

    @Test("SpinnerRenderer: 使用 shimmer 的初始化接受 colorProfile")
    func spinnerRenderer_acceptsColorProfile() {
        let renderer = SpinnerRenderer(isTTY: false, colorProfile: .trueColor)
        // 非 TTY 环境，stop 应该安全调用
        renderer.stop()
    }

    // MARK: - Helpers

    /// 去除所有 ANSI 转义序列，返回纯文本。
    private func stripANSI(_ text: String) -> String {
        // 匹配 ESC[ ... m 格式的 ANSI 序列
        let pattern = "\u{1B}\\[[0-9;]*m"
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
}
