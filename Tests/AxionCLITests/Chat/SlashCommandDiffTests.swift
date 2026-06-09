import Foundation
import Testing

@testable import AxionCLI

@Suite("SlashCommand /diff (AC4)")
struct SlashCommandDiffTests {

    // MARK: - handleDiff 输出格式

    @Test("handleDiff — staged/unstaged/untracked 三段输出")
    func handleDiffThreeSections() {
        let mockLauncher: @Sendable (String, [String]) -> String? = { _, args in
            if args.contains("--version") { return "git version 2.x\n" }
            let cmd = args.joined(separator: " ")
            if cmd.contains("rev-parse") { return "true\n" }
            if cmd.contains("--cached") {
                // 返回 unified diff 格式
                return "diff --git a/file.swift b/file.swift\n--- a/file.swift\n+++ b/file.swift\n@@ -1 +1 @@\n-old\n+new\n"
            }
            if cmd.contains("--unified") && !cmd.contains("--cached") {
                return "diff --git a/other.swift b/other.swift\n--- a/other.swift\n+++ b/other.swift\n@@ -1 +1 @@\n-old2\n+new2\n"
            }
            if cmd.contains("ls-files") { return "newfile.swift\nanother.swift\n" }
            return nil
        }
        let output = SlashCommandHandler.handleDiff(cwd: "/tmp", processLauncher: mockLauncher)
        #expect(output.contains("Staged:"))
        #expect(output.contains("Unstaged:"))
        #expect(output.contains("Untracked:"))
        #expect(output.contains("newfile.swift"))
    }

    @Test("handleDiff — 非 git repo 降级提示")
    func handleDiffNonGitRepo() {
        let mockLauncher: @Sendable (String, [String]) -> String? = { _, args in
            if args.contains("--version") { return "git version 2.x\n" }
            if args.contains("rev-parse") { return nil }
            return nil
        }
        let output = SlashCommandHandler.handleDiff(cwd: "/tmp", processLauncher: mockLauncher)
        #expect(output.contains("当前目录不是 git 仓库"))
    }

    @Test("handleDiff — 无变更时显示提示")
    func handleDiffNoChanges() {
        let mockLauncher: @Sendable (String, [String]) -> String? = { _, args in
            if args.contains("--version") { return "git version 2.x\n" }
            if args.contains("rev-parse") { return "true\n" }
            // All git commands return empty output
            return ""
        }
        let output = SlashCommandHandler.handleDiff(cwd: "/tmp", processLauncher: mockLauncher)
        #expect(output.contains("无变更"))
    }

    @Test("handleDiff — 只有 staged 变更")
    func handleDiffStagedOnly() {
        let mockLauncher: @Sendable (String, [String]) -> String? = { _, args in
            if args.contains("--version") { return "git version 2.x\n" }
            if args.contains("rev-parse") { return "true\n" }
            if args.contains("--cached") {
                return "diff --git a/file.swift b/file.swift\n--- a/file.swift\n+++ b/file.swift\n@@ -1 +1 @@\n-old\n+new\n"
            }
            return ""
        }
        let output = SlashCommandHandler.handleDiff(cwd: "/tmp", processLauncher: mockLauncher)
        #expect(output.contains("Staged:"))
        #expect(!output.contains("Unstaged:"))
        #expect(!output.contains("Untracked:"))
    }

    @Test("handleDiff — 只有 untracked 文件")
    func handleDiffUntrackedOnly() {
        let mockLauncher: @Sendable (String, [String]) -> String? = { _, args in
            if args.contains("--version") { return "git version 2.x\n" }
            if args.contains("rev-parse") { return "true\n" }
            if args.contains("ls-files") { return "newfile.swift\n" }
            return ""
        }
        let output = SlashCommandHandler.handleDiff(cwd: "/tmp", processLauncher: mockLauncher)
        #expect(!output.contains("Staged:"))
        #expect(!output.contains("Unstaged:"))
        #expect(output.contains("Untracked:"))
        #expect(output.contains("newfile.swift"))
    }

    @Test("handleDiff — git 不可用时显示提示")
    func handleDiffGitNotAvailable() {
        // git --version 也返回 nil → git 命令不可用
        let mockLauncher: @Sendable (String, [String]) -> String? = { _, _ in nil }
        let output = SlashCommandHandler.handleDiff(cwd: "/tmp", processLauncher: mockLauncher)
        #expect(output.contains("git 命令不可用"))
        #expect(!output.contains("当前目录不是 git 仓库"))
    }

    // MARK: - DiffFormatter 集成

    @Test("handleDiff — staged diff 包含 unified diff 内容")
    func handleDiffStagedFormatted() {
        let mockLauncher: @Sendable (String, [String]) -> String? = { _, args in
            if args.contains("--version") { return "git version 2.x\n" }
            if args.contains("rev-parse") { return "true\n" }
            if args.contains("--cached") {
                return "diff --git a/test.swift b/test.swift\n--- a/test.swift\n+++ b/test.swift\n@@ -1 +1 @@\n-old\n+new\n"
            }
            return ""
        }
        let output = SlashCommandHandler.handleDiff(cwd: "/tmp", processLauncher: mockLauncher)
        // 应包含 Staged 段标题和 unified diff 内容
        // 非 TTY 环境下 DiffFormatter 原样输出，但内容仍然存在
        #expect(output.contains("Staged:"))
        #expect(output.contains("diff --git"))
    }
}
