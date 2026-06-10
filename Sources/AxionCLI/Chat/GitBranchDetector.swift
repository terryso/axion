import Foundation

/// 轻量级 Git 分支检测器 — 纯函数 + DI 模式，无直接 I/O。
///
/// Codex-inspired: Codex 的 `StatusLineGitSummary` 在状态栏中显示当前 git 分支
/// 和分支变更统计（additions/deletions），让用户无需 `git status` 即可感知
/// 仓库状态。Axion 将分支信息显示在交互模式提示符中，作为 coding agent 的
/// 关键上下文信息。
///
/// 设计原则（遵循 project-context.md Epic 37 模式）：
/// - 纯函数 + static 方法，通过 `executeGit` 闭包注入进程执行
/// - 非 TTY 环境下返回 nil（无 ANSI 转义）
/// - Git 不可用或非 git 仓库时静默返回 nil（不报错）
/// - 分支名做安全清理（去除控制字符，防止终端注入）
struct GitBranchDetector {

    /// 检测到的 Git 状态信息。
    struct GitStatus: Sendable, Equatable {
        /// 当前分支名（如 "main"、"feature/auth"）。
        let branch: String
        /// 工作区是否有未提交的变更。
        let isDirty: Bool

        /// 格式化为显示字符串。
        /// - dirty: "main*"（星号表示有未提交变更）
        /// - clean: "main"
        var displayString: String {
            isDirty ? "\(branch)*" : branch
        }
    }

    /// 进程执行闭包类型 — 用于 DI 测试。
    /// 接收参数列表，返回 (stdout, exitCode) 或 nil（执行失败）。
    typealias ExecuteGit = ([String]) -> (output: String, exitCode: Int32)?

    /// 检测当前目录的 Git 分支和工作区状态。
    ///
    /// 使用 `git rev-parse` 和 `git status` 子命令，通过注入的 `executeGit` 闭包执行。
    /// 任何失败（非 git 仓库、git 未安装、权限错误）都静默返回 nil。
    ///
    /// - Parameter executeGit: 进程执行闭包（默认调用 `/usr/bin/env git`）
    /// - Returns: Git 状态信息，或 nil（非 git 仓库 / 执行失败）
    static func detect(executeGit: ExecuteGit = liveExecuteGit) -> GitStatus? {
        // 1. 获取当前分支名
        guard let branchResult = executeGit(["rev-parse", "--abbrev-ref", "HEAD"]),
              branchResult.exitCode == 0 else {
            return nil
        }
        let branch = sanitizeBranch(branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !branch.isEmpty else { return nil }

        // 2. 检测工作区是否 dirty
        let isDirty: Bool
        if let statusResult = executeGit(["status", "--porcelain"]),
           statusResult.exitCode == 0 {
            let trimmed = statusResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            isDirty = !trimmed.isEmpty
        } else {
            // status 失败时假设 clean（保守策略）
            isDirty = false
        }

        return GitStatus(branch: branch, isDirty: isDirty)
    }

    // MARK: - Sanitization

    /// 清理分支名中的不安全字符。
    ///
    /// 移除控制字符（防止终端注入攻击）和多余的空白。
    /// 保留 git 分支名中允许的字符：字母、数字、/、-、_、.。
    static func sanitizeBranch(_ raw: String) -> String {
        var result = String()
        result.reserveCapacity(raw.count)
        for scalar in raw.unicodeScalars {
            // 允许：字母、数字、/、-、_、.、#（用于 GitHub PR 引用）
            if CharacterSet.alphanumerics.contains(scalar)
                || scalar == "/" || scalar == "-" || scalar == "_" || scalar == "." || scalar == "#" {
                result.append(Character(scalar))
            }
        }
        return result
    }

    // MARK: - Live Execution

    /// 默认的 Git 进程执行闭包 — 使用 `/usr/bin/env git` 子进程。
    ///
    /// 遵循 Chat/ 模块的 DI 模式：生产代码使用 `liveExecuteGit`，
    /// 测试注入 mock 闭包。
    nonisolated(unsafe) static let liveExecuteGit: ExecuteGit = { args in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        do {
            try process.run()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }
            let output = String(data: stdoutData, encoding: .utf8) ?? ""
            return (output: output, exitCode: process.terminationStatus)
        } catch {
            return nil
        }
    }
}
