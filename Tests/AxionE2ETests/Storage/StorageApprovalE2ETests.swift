import Testing
import Foundation
import OpenAgentSDK

import AxionCore
@testable import AxionCLI

/// Story 39 E2E —— 审批门真实拦截 + 零副作用真实断言。
///
/// 用真实 `ExecuteStoragePlanTool`（真实 executor）+ 真实 `RunApprovalCollector`
/// （其 `writeStdout` / `readLine` 闭包是设计好的注入缝，**非 mock**）+ `StorageApprovalGate.makeRunCanUseTool`。
/// 单元测试只断言 gate 返回值；本套件进一步断言 **deny 后文件真没动、无 manifest 落盘**（真实零副作用），
/// 且 **approve 后真实执行**（文件移动 + manifest completed）。符合 SDK「E2E 用真实环境」约定。
@Suite("Storage E2E — Approval Gate (zero side-effect)")
struct StorageApprovalE2ETests {

    private func scratch(_ label: String) throws -> URL {
        try StorageE2EFixture.makeScratch(label)
    }
    private func cleanup(_ url: URL) { StorageE2EFixture.cleanup(url) }
    private func writeFile(_ url: URL, bytes: Int = 8) throws {
        try StorageE2EFixture.writeFile(url, bytes: bytes)
    }
    private func context(_ cwd: String) -> ToolContext { StorageE2EFixture.makeContext(cwd: cwd) }

    /// 真实 execute 工具 + 隔离 store/trash（deny 时确保零副作用可断言：executor 无人调用即不动）。
    private func makeExecute(store: StorageManifestStore, trash: URL) -> ExecuteStoragePlanTool {
        let executor = StorageExecutor(
            manifestStore: store,
            trashPerformer: StorageE2EFixture.makeIsolatedTrash(trash)
        )
        return ExecuteStoragePlanTool(executor: executor)
    }

    /// 可被审批门解析的 execute_storage_plan 入参（items 非空、可 parse，过 `StorageApprovalInput.build`）。
    private func executeInput(opId: String, scanRoot: String, file: URL, target: URL) -> [String: Any] {
        [
            "operation_id": opId,
            "scan_roots": [scanRoot],
            "items": [["action": "move", "source": file.path, "target": target.path]],
        ]
    }

    // MARK: - 1. 非 TTY → deny(approval_required) + 零副作用

    @Test("非交互 TTY：审批门 deny(approval_required)，且零副作用（文件未动、无 manifest）")
    func e2e_non_tty_denies_zero_side_effect() async throws {
        let root = try scratch("ap-nontty")
        defer { cleanup(root) }
        let ops = root.appendingPathComponent("ops", isDirectory: true)
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        let store = StorageE2EFixture.makeStore(opsDir: ops, home: root.path)
        let executeTool = makeExecute(store: store, trash: trash)

        let scanRoot = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        let file = scanRoot.appendingPathComponent("a.txt")
        let target = scanRoot.appendingPathComponent("out/a.txt")
        try writeFile(file, bytes: 8)

        // isInteractive:false → 门在到达 collector 前即 deny；readLine 不应被触达（给个值仅为防御）。
        let collector = RunApprovalCollector(writeStdout: { _ in }, readLine: { "a" })
        let gate = StorageApprovalGate.makeRunCanUseTool(
            collector: collector, isInteractiveFn: { false }, jsonOutput: false
        )
        let result = await gate(
            executeTool,
            executeInput(opId: "op-nontty", scanRoot: scanRoot.path, file: file, target: target),
            context(scanRoot.path)
        )

        #expect(result?.behavior == .deny)
        // 真实零副作用：门仅决策，executor 从未被调用 → 文件仍在、无 manifest 落盘。
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(store.load(operationId: "op-nontty") == nil)
    }

    // MARK: - 2. cancel → deny(user_cancelled) + 零副作用

    @Test("用户取消：审批门 deny(user_cancelled)，且零副作用")
    func e2e_cancel_denies_zero_side_effect() async throws {
        let root = try scratch("ap-cancel")
        defer { cleanup(root) }
        let ops = root.appendingPathComponent("ops", isDirectory: true)
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        let store = StorageE2EFixture.makeStore(opsDir: ops, home: root.path)
        let executeTool = makeExecute(store: store, trash: trash)

        let scanRoot = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        let file = scanRoot.appendingPathComponent("b.txt")
        let target = scanRoot.appendingPathComponent("out/b.txt")
        try writeFile(file, bytes: 8)

        // 任意非批准键（"n"）→ collector 返回 cancel → deny(user_cancelled)。
        let collector = RunApprovalCollector(writeStdout: { _ in }, readLine: { "n" })
        let gate = StorageApprovalGate.makeRunCanUseTool(
            collector: collector, isInteractiveFn: { true }, jsonOutput: false
        )
        let result = await gate(
            executeTool,
            executeInput(opId: "op-cancel", scanRoot: scanRoot.path, file: file, target: target),
            context(scanRoot.path)
        )

        #expect(result?.behavior == .deny)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(store.load(operationId: "op-cancel") == nil)
    }

    // MARK: - 3. approve → allow；随后真实执行 → 文件移动 + manifest completed

    @Test("用户批准：审批门 allow，随后真实执行移动 + manifest completed")
    func e2e_approve_executes_and_moves() async throws {
        let root = try scratch("ap-approve")
        defer { cleanup(root) }
        let ops = root.appendingPathComponent("ops", isDirectory: true)
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        let store = StorageE2EFixture.makeStore(opsDir: ops, home: root.path)
        let executeTool = makeExecute(store: store, trash: trash)

        let scanRoot = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        let file = scanRoot.appendingPathComponent("c.txt")
        let target = scanRoot.appendingPathComponent("out/c.txt")
        try writeFile(file, bytes: 8)

        let collector = RunApprovalCollector(writeStdout: { _ in }, readLine: { "a" })  // "a" → 批准全部
        let gate = StorageApprovalGate.makeRunCanUseTool(
            collector: collector, isInteractiveFn: { true }, jsonOutput: false
        )
        let input = executeInput(opId: "op-approve", scanRoot: scanRoot.path, file: file, target: target)
        let result = await gate(executeTool, input, context(scanRoot.path))
        #expect(result?.behavior == .allow)

        // 与生产 SDK 流程一致：canUseTool allow → tool.call 真实执行。
        let execResult = await executeTool.call(input: input, context: context(scanRoot.path))
        let manifest = try StorageE2EFixture.decodeManifest(execResult)
        #expect(manifest.status == .completed)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    // MARK: - 4. 非 storage execute 工具恒放行（storage_scan 只读、不在门内）

    @Test("非 storage execute 工具（storage_scan）恒放行")
    func e2e_non_storage_tool_always_allowed() async throws {
        let root = try scratch("ap-nongated")
        defer { cleanup(root) }
        let scanRoot = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)

        // storage_scan 不在门内（仅 execute_storage_plan / execute_app_uninstall 走门）。
        let scanTool = StorageScanTool(scanner: StorageScanService(homeDirectory: root.path))
        let collector = RunApprovalCollector(writeStdout: { _ in }, readLine: { nil })  // 不会被触达
        let gate = StorageApprovalGate.makeRunCanUseTool(
            collector: collector, isInteractiveFn: { true }, jsonOutput: false
        )
        let result = await gate(
            scanTool,
            ["roots": [scanRoot.path], "min_size_mb": 0] as [String: Any],
            context(scanRoot.path)
        )
        // decide 对非门工具返回 nil → 门回退 .allow()（恒放行）。
        #expect(result?.behavior == .allow)
    }
}
