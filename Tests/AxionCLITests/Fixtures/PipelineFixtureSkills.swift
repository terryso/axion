import Foundation
import OpenAgentSDK

// MARK: - Story 40.9 Fixture Skills + Pipeline Harness
//
// 确定性 fixture（内存构造，无文件系统 IO、无 LLM、无 MCP、无 Helper 进程），把
// Story 40.3（Agent/Task/Skill 注册）、40.4（discovered registry）、40.5（dry-run/MCP 策略）、
// 40.6（permission/diagnostics）、40.8（child task 输出渲染）的能力串成一条可单元验证的
// pipeline 链。本文件只构造 fixture + 测试 harness，**不**重复实现任何 production 逻辑
// （buildToolProfile / buildSkillToolProfile / diagnoseToolAvailability / 输出格式化均由测试
// 直接调用既有 helper——见 FixturePipelineAcceptanceTests.swift）。
//
// 设计依据（CLAUDE.md 强制约束）：
// - fixture skill 一律通过 `Skill` 的 `public init(...)` 构造（公开字段），**不**依赖私有 SDK 内部
// - fixture **不**读取真实文件系统 skill——全部内存构造（确定性，无 IO 依赖）
// - `resolvePipelineSequence` 用纯字符串扫描提取被引用 step 名（不调 LLM / 子代理执行）

/// Story 40.9 的确定性 pipeline fixture skills + 测试 harness。
///
/// 提供 `pipeline-test` / `step-one` / `step-two` 三个 fixture skill（success 链），以及一个
/// `pipeline-test-broken` 变体（第二步引用**未注册**的 `step-missing`，用于 AC2 失败路径）。
/// 全部通过 SDK `Skill` 的 `public init(...)` 内存构造——无文件系统 IO、无 LLM。
enum PipelineFixtureSkills {

    // MARK: - Fixture Skills

    /// `step-one` fixture skill——pipeline-test 的第一步（success 链）。
    static func stepOne() -> Skill {
        Skill(
            name: "step-one",
            description: "Fixture step one of the pipeline-test fixture (Story 40.9).",
            userInvocable: true,
            promptTemplate: "Step one of the pipeline-test fixture. Echo a deterministic marker and exit.",
            whenToUse: "When pipeline-test needs its first step."
        )
    }

    /// `step-two` fixture skill——pipeline-test 的第二步（success 链）。
    static func stepTwo() -> Skill {
        Skill(
            name: "step-two",
            description: "Fixture step two of the pipeline-test fixture (Story 40.9).",
            userInvocable: true,
            promptTemplate: "Step two of the pipeline-test fixture. Echo a deterministic marker and exit.",
            whenToUse: "When pipeline-test needs its second step."
        )
    }

    /// `pipeline-test` fixture orchestrator skill。
    ///
    /// 其 `promptTemplate` **按文本顺序**先引用 `/step-one` 再引用 `/step-two`（通过 `Task(...)`
    /// 子代理片段），用于 AC1 的顺序断言。引用以 `/<name>` slash 命令形式嵌入，便于
    /// `resolvePipelineSequence` 扫描 + 40.8 `extractSlashSkillCommand` 提取可重试命令。
    static func pipelineTest() -> Skill {
        Skill(
            name: "pipeline-test",
            description: "Deterministic two-step pipeline orchestrator fixture (Story 40.9).",
            userInvocable: true,
            promptTemplate: """
            Pipeline orchestrator fixture (Story 40.9). Execute the steps in order:

            1. Task(subagent_type: "general-purpose", description: "Run step one", prompt: "Execute /step-one demo")
            2. Task(subagent_type: "general-purpose", description: "Run step two", prompt: "Execute /step-two demo")

            Report the combined result.
            """,
            whenToUse: "When verifying the pipeline-test / step-one / step-two fixture chain."
        )
    }

    /// `pipeline-test-broken` fixture 变体（AC2 失败路径）。
    ///
    /// 第二步引用一个**未注册**的 skill `/step-missing`。broken registry 故意不注册 `step-missing`，
    /// 使 `registry.find("step-missing") == nil`——fixture 据此断言 missing skill 被标记为
    /// unmatched，并经 40.8 输出格式化产出 `/step-missing demo` 可重试命令。
    static func pipelineTestBroken() -> Skill {
        Skill(
            name: "pipeline-test-broken",
            description: "Broken pipeline fixture variant whose second step references an unregistered skill (Story 40.9).",
            userInvocable: true,
            promptTemplate: """
            Broken pipeline fixture variant (Story 40.9). Second step references an unregistered skill:

            1. Task(subagent_type: "general-purpose", description: "Run step one", prompt: "Execute /step-one demo")
            2. Task(subagent_type: "general-purpose", description: "Run missing step", prompt: "Execute /step-missing demo")
            """,
            whenToUse: "When verifying the missing-skill failure path of the pipeline fixture."
        )
    }

    // MARK: - Fixture Registries

    /// 构造 success 链测试 registry：注册 `pipeline-test` + `step-one` + `step-two`（AC1）。
    /// 复用 SDK `SkillRegistry()` 空表 + `register`（40.4 discovered registry 的等价最小形态）。
    static func makeSuccessRegistry() -> SkillRegistry {
        let registry = SkillRegistry()
        registry.register(pipelineTest())
        registry.register(stepOne())
        registry.register(stepTwo())
        return registry
    }

    /// 构造 broken registry：只注册 `pipeline-test-broken` + `step-one`，**不**注册 `step-missing`（AC2）。
    /// `registry.find("step-missing")` 因此返回 nil——fixture 据此断言 missing skill unmatched。
    static func makeBrokenRegistry() -> SkillRegistry {
        let registry = SkillRegistry()
        registry.register(pipelineTestBroken())
        registry.register(stepOne())
        // step-missing 故意不注册
        return registry
    }

    // MARK: - Pipeline Resolve Harness

    /// 从一个 pipeline skill 的 `promptTemplate` 中按**文本顺序**提取被引用的 step skill 名。
    ///
    /// 用纯字符串扫描（正则匹配 `/step-<name>` token，按出现顺序收集），**不**调 LLM、**不**
    /// 调 `createSubAgentSpawner` / `executeSkillStream` / 任何会触发真实子代理执行的 SDK 路径。
    /// 这是 fixture harness（测试 helper），**不**重复 production 逻辑——production 的子代理派发
    /// 由 SDK `DefaultSubAgentSpawner` 在 LLM 决策后完成，本 harness 只在「LLM 调用之前的那一层」
    /// 断言引用顺序（AC1）。
    ///
    /// - Parameters:
    ///   - registry: 测试 registry（用于 resolve 出 pipeline skill 的 promptTemplate）。
    ///   - pipelineSkillName: pipeline orchestrator skill 名（如 `pipeline-test` / `pipeline-test-broken`）。
    /// - Returns: 按文本顺序的 step skill 名数组（如 `["step-one", "step-two"]`）；registry 解析
    ///   不到该 pipeline skill 时返回空数组。
    static func resolvePipelineSequence(
        registry: SkillRegistry,
        pipelineSkillName: String
    ) -> [String] {
        guard let skill = registry.find(pipelineSkillName) else { return [] }
        let template = skill.promptTemplate

        // 匹配 /step-<name> token（name 允许字母/数字/下划线/连字符），按文本顺序收集。
        // 仅捕获 step-* 前缀，避免误抓 pipeline-test 自身的名字。
        guard let regex = try? NSRegularExpression(
            pattern: #"/(step-[A-Za-z0-9_-]+)"#,
            options: []
        ) else { return [] }

        let fullRange = NSRange(template.startIndex..., in: template)
        var names: [String] = []
        regex.enumerateMatches(in: template, options: [], range: fullRange) { match, _, _ in
            guard let match, match.numberOfRanges >= 2,
                  let captureRange = Range(match.range(at: 1), in: template) else { return }
            names.append(String(template[captureRange]))
        }
        return names
    }

    /// 返回 pipeline 中**未注册**（`registry.find` 返回 nil）的 step skill 名（AC2 unmatched 标记）。
    ///
    /// 这是「等价 profile 诊断 helper」——把 `resolvePipelineSequence` 的结果逐个交给
    /// `registry.find`，凡返回 nil 者即为 unmatched step。对应 40.6 `diagnoseToolAvailability`
    /// 的 skill 级类比（后者是 tool 级诊断，二者都回答「声明了但不可用」）。
    static func unmatchedSteps(
        registry: SkillRegistry,
        pipelineSkillName: String
    ) -> [String] {
        resolvePipelineSequence(registry: registry, pipelineSkillName: pipelineSkillName)
            .filter { registry.find($0) == nil }
    }
}
