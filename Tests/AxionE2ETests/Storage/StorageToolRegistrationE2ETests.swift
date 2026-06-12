import Testing
import Foundation
import OpenAgentSDK

import AxionCore
@testable import AxionCLI

/// Story 39 E2E —— AgentBuilder 工具注册门控（真实 `build()`，非 mock）。
///
/// 单元测试因 `AgentBuilder.build()` 重依赖（helper / prompt / MCP / review infra）而 mock，
/// 从未真实验证 **dryrun 下副作用工具是否真的不注册**。本套件用真实 `build()` 断言
/// `AgentBuildResult.agentOptions.tools` 的工具名集合，验证 dryrun↔非 dryrun 的注册分叉。
/// 符合 SDK「E2E 用真实环境」约定。
@Suite("Storage E2E — Tool Registration Gate")
struct StorageToolRegistrationE2ETests {

    /// 6 个 storage 工具名（与 `AgentBuilder` 注册处一致）。
    private static let storageToolNames: Set<String> = [
        "storage_scan", "propose_storage_plan", "execute_storage_plan",
        "undo_storage_op", "scan_app_uninstall", "execute_app_uninstall",
    ]

    /// 真实 `build()`：dummy apiKey + noMemory/noSkills 精简构建（聚焦工具注册，规避无关 infra）。
    private func build(dryrun: Bool) async throws -> AgentBuildResult {
        let config = AxionConfig(apiKey: "sk-test")
        return try await AgentBuilder.build(
            AgentBuilder.BuildConfig.forCLI(
                config: config,
                task: "storage e2e registration",
                noMemory: true,
                noSkills: true,
                dryrun: dryrun
            )
        )
    }

    // MARK: - 1. dryrun → 不注册任何副作用工具

    @Test("dryrun：不注册 6 个 storage 工具及 Bash/Skill（规划态零副作用）")
    func e2e_dryrun_excludes_side_effect_tools() async throws {
        let result = try await build(dryrun: true)
        let names = Set((result.agentOptions.tools ?? []).map { $0.name })

        // SEC：dryrun（规划态）下 6 个 storage 工具一律不注册。
        for name in Self.storageToolNames {
            #expect(!names.contains(name), "dryrun 不应注册副作用工具 \(name)")
        }
        // Bash / Skill（副作用工具）同样被 dryrun 守卫剔除（AgentBuilder 干跑工具集）。
        #expect(!names.contains("Bash"))
        #expect(!names.contains("Skill"))
    }

    // MARK: - 2. 非 dryrun → 注册全部 6 个 storage 工具（需本地 helper 可解析；否则清晰跳过）

    @Test("非 dryrun：注册全部 6 个 storage 工具")
    func e2e_non_dryrun_registers_storage_tools() async throws {
        // 需本地已安装 AxionHelper.app（resolveHelperPath 可解析）；CI / 无 helper 环境跳过（不硬失败）。
        // 仿 MockLLME2ETests.setUpFixture 的「不可用即 return」跳过范式。
        guard HelperPathResolver.resolveHelperPath() != nil else { return }

        let result = try await build(dryrun: false)
        let names = Set((result.agentOptions.tools ?? []).map { $0.name })

        for name in Self.storageToolNames {
            #expect(names.contains(name), "非 dryrun 应注册 \(name)")
        }
    }
}
