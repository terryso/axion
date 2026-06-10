import Foundation
import Testing

@testable import AxionCLI

@Suite("GitBranchDetector")
struct GitBranchDetectorTests {

    // MARK: - sanitizeBranch

    @Test("sanitizeBranch: 保留合法分支名字符")
    func sanitizeBranch_validChars() {
        #expect(GitBranchDetector.sanitizeBranch("main") == "main")
        #expect(GitBranchDetector.sanitizeBranch("feature/auth") == "feature/auth")
        #expect(GitBranchDetector.sanitizeBranch("fix-123") == "fix-123")
        #expect(GitBranchDetector.sanitizeBranch("release_v2.0") == "release_v2.0")
        #expect(GitBranchDetector.sanitizeBranch("pr#42") == "pr#42")
    }

    @Test("sanitizeBranch: 移除控制字符")
    func sanitizeBranch_controlChars() {
        #expect(GitBranchDetector.sanitizeBranch("main\u{07}") == "main")
        #expect(GitBranchDetector.sanitizeBranch("main\u{1B}") == "main")
        #expect(GitBranchDetector.sanitizeBranch("\tmain") == "main")
        #expect(GitBranchDetector.sanitizeBranch("feat\nbranch") == "featbranch")
    }

    @Test("sanitizeBranch: 空字符串保持为空")
    func sanitizeBranch_empty() {
        #expect(GitBranchDetector.sanitizeBranch("") == "")
    }

    @Test("sanitizeBranch: 全部非法字符返回空")
    func sanitizeBranch_allInvalid() {
        #expect(GitBranchDetector.sanitizeBranch("@$%!") == "")
    }

    // MARK: - GitStatus.displayString

    @Test("GitStatus.displayString: clean 分支无星号")
    func gitStatus_clean() {
        let status = GitBranchDetector.GitStatus(branch: "main", isDirty: false)
        #expect(status.displayString() == "main")
    }

    @Test("GitStatus.displayString: dirty 分支带星号")
    func gitStatus_dirty() {
        let status = GitBranchDetector.GitStatus(branch: "feature/auth", isDirty: true)
        #expect(status.displayString() == "feature/auth*")
    }

    @Test("GitStatus.displayString: 短分支名不截断")
    func gitStatus_shortBranch_noTruncation() {
        let status = GitBranchDetector.GitStatus(branch: "main", isDirty: false)
        #expect(status.displayString(maxLength: 15) == "main")
    }

    @Test("GitStatus.displayString: 长分支名截断尾部并加省略号后缀")
    func gitStatus_longBranch_truncated() {
        let status = GitBranchDetector.GitStatus(
            branch: "gnhf/cascadeprojects-code-6ba7a0-1",
            isDirty: false
        )
        let result = status.displayString(maxLength: 15)
        // prefix(14) + "…" = "gnhf/cascadepr…" = 15 chars
        #expect(result.hasSuffix("…"))
        #expect(result.count == 15)
        #expect(result.hasPrefix("gnhf"))
    }

    @Test("GitStatus.displayString: 长分支名 + dirty 星号不计入长度")
    func gitStatus_longBranch_dirtyStarNotCounted() {
        let status = GitBranchDetector.GitStatus(
            branch: "gnhf/cascadeprojects-code-6ba7a0-1",
            isDirty: true
        )
        let result = status.displayString(maxLength: 15)
        // branch part: "gnhf/cascadepr…" (15 chars) + "*" (dirty)
        #expect(result.hasSuffix("…*"))
        #expect(result.count == 16)  // 15 branch chars + 1 star
        #expect(result.hasPrefix("gnhf"))
    }

    @Test("GitStatus.displayString: 恰好等于 maxLength 不截断")
    func gitStatus_exactLength_noTruncation() {
        let branch = "123456789012345"  // exactly 15 chars
        let status = GitBranchDetector.GitStatus(branch: branch, isDirty: false)
        #expect(status.displayString(maxLength: 15) == branch)
    }

    @Test("GitStatus.displayString: maxLength 为 0 时 clamp 到 1 显示首字符+省略号")
    func gitStatus_zeroMaxLength() {
        let status = GitBranchDetector.GitStatus(branch: "main", isDirty: false)
        // maxLength clamped to 1: prefix(0) + "…" = "…"
        #expect(status.displayString(maxLength: 0) == "…")
    }

    // MARK: - detect (mock injection)

    private func makeMockGit(
        branchOutput: String?,
        branchExitCode: Int32 = 0,
        statusOutput: String? = "",
        statusExitCode: Int32 = 0
    ) -> GitBranchDetector.ExecuteGit {
        return { args in
            if args.contains("rev-parse") {
                guard let output = branchOutput, branchExitCode == 0 else { return nil }
                return (output: output, exitCode: branchExitCode)
            }
            if args.contains("status") {
                guard statusExitCode == 0 else { return nil }
                return (output: statusOutput ?? "", exitCode: statusExitCode)
            }
            return nil
        }
    }

    @Test("detect: 正常分支 + clean 工作区")
    func detect_cleanBranch() {
        let result = GitBranchDetector.detect(
            executeGit: makeMockGit(branchOutput: "main", statusOutput: "")
        )
        #expect(result != nil)
        #expect(result?.branch == "main")
        #expect(result?.isDirty == false)
    }

    @Test("detect: 分支名带斜杠 + dirty 工作区")
    func detect_dirtyFeatureBranch() {
        let statusOutput = "M Sources/Foo.swift\n?? Tests/NewTest.swift"
        let result = GitBranchDetector.detect(
            executeGit: makeMockGit(branchOutput: "feature/git-branch", statusOutput: statusOutput)
        )
        #expect(result != nil)
        #expect(result?.branch == "feature/git-branch")
        #expect(result?.isDirty == true)
    }

    @Test("detect: rev-parse 失败返回 nil（非 git 仓库）")
    func detect_notGitRepo() {
        let result = GitBranchDetector.detect(
            executeGit: makeMockGit(branchOutput: nil)
        )
        #expect(result == nil)
    }

    @Test("detect: rev-parse 非零退出码返回 nil")
    func detect_revParseNonZero() {
        let result = GitBranchDetector.detect(
            executeGit: makeMockGit(branchOutput: "main", branchExitCode: 128)
        )
        #expect(result == nil)
    }

    @Test("detect: 空分支名返回 nil")
    func detect_emptyBranch() {
        let result = GitBranchDetector.detect(
            executeGit: makeMockGit(branchOutput: "  \n", statusOutput: "")
        )
        #expect(result == nil)
    }

    @Test("detect: status 失败时保守假设 clean")
    func detect_statusFails_assumeClean() {
        let mock: GitBranchDetector.ExecuteGit = { args in
            if args.contains("rev-parse") {
                return (output: "main\n", exitCode: 0)
            }
            // status fails
            return nil
        }
        let result = GitBranchDetector.detect(executeGit: mock)
        #expect(result != nil)
        #expect(result?.branch == "main")
        #expect(result?.isDirty == false)
    }

    @Test("detect: 分支名含控制字符被清理")
    func detect_branchNameSanitized() {
        let result = GitBranchDetector.detect(
            executeGit: makeMockGit(branchOutput: "main\u{07}suffix", statusOutput: "")
        )
        #expect(result != nil)
        #expect(result?.branch == "mainsuffix")
    }

    // MARK: - detect (HEAD detached)

    @Test("detect: detached HEAD 显示完整 SHA")
    func detect_detachedHead() {
        let result = GitBranchDetector.detect(
            executeGit: makeMockGit(branchOutput: "abc123def456", statusOutput: "")
        )
        #expect(result != nil)
        #expect(result?.branch == "abc123def456")
    }
}
