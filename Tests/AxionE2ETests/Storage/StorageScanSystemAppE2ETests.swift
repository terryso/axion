import Testing
import Foundation
import OpenAgentSDK

import AxionCore
@testable import AxionCLI

/// Story 39 E2E —— 扫描真实系统 App（只读，受系统保护）。
///
/// 用真实 `ScanAppUninstallTool`（真实 planBuilder：`AppDiscoveryService` 扫 `/Applications`）扫 Safari，
/// 断言候选受系统保护 + `blockedReasons` 含 `system_protected`。只读工具（`isReadOnly = true`），零副作用。
/// 不同 macOS 版本 Safari 位置/识别有差异：候选为空（`no_match`）时清晰跳过，不硬失败。
@Suite("Storage E2E — System App Scan (read-only)")
struct StorageScanSystemAppE2ETests {

    @Test("扫描系统 App Safari：候选 isSystemProtected + blockedReasons 含 system_protected（只读）")
    func e2e_scan_system_app_is_protected() async throws {
        // 真实 planBuilder（与 AgentBuilder 注册处同构），扫描真实 /Applications。
        let planBuilder = AppUninstallPlanBuilder(
            supportDataScanner: SupportDataScanService(),
            appDiscoverer: AppDiscoveryService(),
            hintReader: ExternalHintReader()
        )
        let tool = ScanAppUninstallTool(planBuilder: planBuilder)

        let result = await tool.call(
            input: ["query": "Safari"] as [String: Any],
            context: StorageE2EFixture.makeContext(cwd: NSHomeDirectory())
        )
        #expect(!result.isError)

        let plan = try JSONDecoder().decode(AppUninstallPlan.self, from: Data(result.content.utf8))

        // 候选为空（不同 macOS 版本识别差异，builder 以 bundlePath="" 占位 + no_match）→ 清晰跳过。
        guard !plan.app.bundlePath.isEmpty else { return }

        #expect(plan.app.isSystemProtected == true, "Safari 应被标记为系统保护")
        #expect(plan.blockedReasons.contains("system_protected"), "blockedReasons 应含 system_protected")
        // SEC：只读工具，零副作用（不卸载、不移动）。
        #expect(tool.isReadOnly == true)
    }
}
