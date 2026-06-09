import Foundation

extension SlashCommandHandler {

    // MARK: - /diff (AC4)

    /// 默认 Process 启动器 — 生产环境使用。
    static let defaultProcessLauncher: @Sendable (String, [String]) -> String? = { cwd, args in
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)
            return (process.terminationStatus == 0) ? output : nil
        } catch {
            return nil
        }
    }

    /// 执行 git diff 并格式化彩色 unified diff 输出。AC4。
    ///
    /// Codex 启发：Codex 的 `TurnDiffTracker` 和 `scrollable_diff.rs` 展示实际的
    /// unified diff 而非仅 --stat 摘要。Axion 使用 `DiffFormatter` 将 `git diff`
    /// 输出渲染为带 ANSI 颜色的终端输出（绿/红/青/灰），大幅提升变更审查体验。
    ///
    /// 通过 `processLauncher` 闭包注入 Process 调用（测试可 Mock）。
    static func handleDiff(
        cwd: String,
        processLauncher: @Sendable (String, [String]) -> String? = defaultProcessLauncher
    ) -> String {
        // 检查 git 是否可用
        guard processLauncher(cwd, ["git", "--version"]) != nil else {
            return "git 命令不可用\n"
        }
        // 检查是否在 git repo 中
        guard processLauncher(cwd, ["git", "rev-parse", "--is-inside-work-tree"]) != nil else {
            return "当前目录不是 git 仓库\n"
        }

        var output = ""

        // --- Staged changes (unified diff) ---
        if let stagedDiff = processLauncher(cwd, ["git", "diff", "--unified=3", "--cached"]),
           !stagedDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output += "Staged:\n"
            output += DiffFormatter.format(stagedDiff)
        }

        // --- Unstaged changes (unified diff) ---
        if let unstagedDiff = processLauncher(cwd, ["git", "diff", "--unified=3"]),
           !unstagedDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output += "Unstaged:\n"
            output += DiffFormatter.format(unstagedDiff)
        }

        // --- Untracked files ---
        if let untracked = processLauncher(cwd, ["git", "ls-files", "--others", "--exclude-standard"]),
           !untracked.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let files = untracked.split(separator: "\n").map(String.init)
            output += "Untracked:\n  " + files.joined(separator: "\n  ") + "\n"
        }

        return output.isEmpty ? "无变更\n" : output
    }
}
