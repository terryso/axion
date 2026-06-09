import Foundation
import Testing

@testable import AxionCLI

@Suite("DiffFormatter")
struct DiffFormatterTests {

    // MARK: - Format Empty

    @Test("format — 空 diff 返回空字符串")
    func formatEmpty() {
        let result = DiffFormatter.format("", config: nonTTYConfig())
        #expect(result == "")
    }

    // MARK: - Non-TTY Passthrough

    @Test("format — 非 TTY 原样输出（无 ANSI 转义）")
    func formatNonTTYPassthrough() {
        let diff = """
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1,3 +1,4 @@
         line1
        -removed
        +added
        +added2
         context
        """
        let result = DiffFormatter.format(diff, config: nonTTYConfig())
        #expect(result == diff)
    }

    // MARK: - TTY Colored Output

    @Test("format — TTY 添加行有绿色 ANSI 码")
    func formatAddedLinesGreen() {
        let diff = "+hello world\n"
        let result = DiffFormatter.format(diff, config: ttyConfig())
        // 绿色 TrueColor ANSI 码
        #expect(result.contains("\u{1B}[38;2;76;175;80m"))
        #expect(result.contains("hello world"))
    }

    @Test("format — TTY 删除行有红色 ANSI 码")
    func formatRemovedLinesRed() {
        let diff = "-old line\n"
        let result = DiffFormatter.format(diff, config: ttyConfig())
        #expect(result.contains("\u{1B}[38;2;244;67;54m"))
        #expect(result.contains("old line"))
    }

    @Test("format — TTY 文件头有青色 ANSI 码")
    func formatFileHeaderCyan() {
        let diff = "diff --git a/test.swift b/test.swift\n"
        let result = DiffFormatter.format(diff, config: ttyConfig())
        #expect(result.contains("\u{1B}[38;2;129;140;248m"))
        #expect(result.contains("diff --git a/test.swift b/test.swift"))
    }

    @Test("format — TYY hunk 头有 dim 灰色")
    func formatHunkHeaderDim() {
        let diff = "@@ -1,3 +1,4 @@\n"
        let result = DiffFormatter.format(diff, config: ttyConfig())
        #expect(result.contains("\u{1B}[38;2;120;120;140m"))
        #expect(result.contains("@@ -1,3 +1,4 @@"))
    }

    @Test("format — TYY 上下文行有 dim 灰色")
    func formatContextLineDim() {
        let diff = " unchanged text\n"
        let result = DiffFormatter.format(diff, config: ttyConfig())
        #expect(result.contains("\u{1B}[38;2;120;120;140m"))
        #expect(result.contains("unchanged text"))
    }

    // MARK: - Stats Header

    @Test("format — 包含统计摘要头")
    func formatStatsHeader() {
        let diff = """
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1,2 +1,3 @@
        -old
        +new
        +new2
        """
        let result = DiffFormatter.format(diff, config: ttyConfig())
        // 1 file changed, +2, -1
        #expect(result.contains("1 file changed"))
        #expect(result.contains("+2"))
        #expect(result.contains("-1"))
    }

    @Test("format — 多文件 diff 正确统计文件数")
    func formatMultiFileStats() {
        let diff = """
        diff --git a/a.swift b/a.swift
        --- a/a.swift
        +++ b/a.swift
        @@ -1 +1 @@
        -old
        +new
        diff --git a/b.swift b/b.swift
        --- a/b.swift
        +++ b/b.swift
        @@ -1 +1 @@
        -old2
        +new2
        """
        let result = DiffFormatter.format(diff, config: ttyConfig())
        #expect(result.contains("2 files changed"))
    }

    @Test("format — 无添加/删除时统计只显示文件数")
    func formatStatsNoChanges() {
        let diff = "diff --git a/file.swift b/file.swift\n"
        let result = DiffFormatter.format(diff, config: ttyConfig())
        #expect(result.contains("1 file changed"))
    }

    // MARK: - Full Diff Rendering

    @Test("format — 完整 unified diff 正确渲染各段类型")
    func formatFullDiff() {
        let diff = """
        diff --git a/BannerRenderer.swift b/BannerRenderer.swift
        index abc1234..def5678 100644
        --- a/BannerRenderer.swift
        +++ b/BannerRenderer.swift
        @@ -10,7 +10,8 @@ struct BannerRenderer {
             existing line
             another line
        -    let old = "removed"
        +    let new = "added"
        +    let extra = "also added"
             context line
        """
        let result = DiffFormatter.format(diff, config: ttyConfig())

        // 文件头青色
        #expect(result.contains("BannerRenderer.swift"))
        // 删除行红色
        #expect(result.contains("old"))
        // 添加行绿色
        #expect(result.contains("new"))
        #expect(result.contains("extra"))
        // 统计头
        #expect(result.contains("1 file changed"))
        #expect(result.contains("+2"))
        #expect(result.contains("-1"))
    }

    // MARK: - Truncation

    @Test("format — 超过最大行数时截断并显示提示")
    func formatTruncation() {
        // 生成超过 maxLines 的 diff
        var lines: [String] = []
        lines.append("diff --git a/big.swift b/big.swift")
        lines.append("--- a/big.swift")
        lines.append("+++ b/big.swift")
        lines.append("@@ -1,100 +1,100 @@")
        for i in 0..<200 {
            lines.append("+line \(i)")
        }
        let diff = lines.joined(separator: "\n")

        let config = DiffFormatter.Config(maxLines: 50, isTTY: true, profile: .trueColor)
        let result = DiffFormatter.format(diff, config: config)

        // 应该有截断提示
        #expect(result.contains("还有"))
        #expect(result.contains("git diff"))
    }

    @Test("format — maxLines=0 不截断")
    func formatNoTruncation() {
        var lines: [String] = []
        lines.append("diff --git a/big.swift b/big.swift")
        for i in 0..<100 {
            lines.append("+line \(i)")
        }
        let diff = lines.joined(separator: "\n")

        let config = DiffFormatter.Config(maxLines: 0, isTTY: true, profile: .trueColor)
        let result = DiffFormatter.format(diff, config: config)

        #expect(!result.contains("还有"))
        #expect(result.contains("line 99"))
    }

    // MARK: - Binary Files

    @Test("format — 二进制文件 diff 正确处理")
    func formatBinaryFiles() {
        let diff = """
        diff --git a/image.png b/image.png
        Binary files differ
        """
        let result = DiffFormatter.format(diff, config: ttyConfig())
        #expect(result.contains("Binary files differ"))
        #expect(result.contains("1 file changed"))
    }

    // MARK: - Color Profile Degradation

    @Test("format — ANSI256 颜色降级")
    func formatANSI256() {
        let diff = "+added\n-old\n"
        let config = DiffFormatter.Config(maxLines: 300, isTTY: true, profile: .ansi256)
        let result = DiffFormatter.format(diff, config: config)
        // ANSI256 绿色
        #expect(result.contains("\u{1B}[38;5;71m"))
        // ANSI256 红色
        #expect(result.contains("\u{1B}[38;5;160m"))
    }

    @Test("format — ANSI16 颜色降级")
    func formatANSI16() {
        let diff = "+added\n-old\n"
        let config = DiffFormatter.Config(maxLines: 300, isTTY: true, profile: .ansi16)
        let result = DiffFormatter.format(diff, config: config)
        // ANSI16 绿色
        #expect(result.contains("\u{1B}[32m"))
        // ANSI16 红色
        #expect(result.contains("\u{1B}[31m"))
    }

    // MARK: - parseStatsFromStatOutput

    @Test("parseStatsFromStatOutput — 解析 git diff --stat 输出")
    func parseStatsFromStatOutput() {
        let stat = """
         BannerRenderer.swift | 5 +++--
         Tests/Chat/BannerTests.swift | 12 ++++++++++++
         2 files changed, 13 insertions(+), 2 deletions(-)
        """
        let stats = DiffFormatter.parseStatsFromStatOutput(stat)
        #expect(stats.fileCount == 2)
        #expect(stats.insertions == 13)
        #expect(stats.deletions == 2)
    }

    @Test("parseStatsFromStatOutput — 只有插入")
    func parseStatsFromStatOutputOnlyInsertions() {
        let stat = "1 file changed, 5 insertions(+)\n"
        let stats = DiffFormatter.parseStatsFromStatOutput(stat)
        #expect(stats.fileCount == 1)
        #expect(stats.insertions == 5)
        #expect(stats.deletions == 0)
    }

    @Test("parseStatsFromStatOutput — 空输出")
    func parseStatsFromStatOutputEmpty() {
        let stats = DiffFormatter.parseStatsFromStatOutput("")
        #expect(stats.isEmpty)
    }

    // MARK: - DiffStats

    @Test("DiffStats — isEmpty 判断")
    func diffStatsIsEmpty() {
        var stats = DiffFormatter.DiffStats()
        #expect(stats.isEmpty)
        stats.fileCount = 1
        #expect(!stats.isEmpty)
    }

    // MARK: - Edge Cases

    @Test("format — 空行在 diff 中被忽略")
    func formatEmptyLinesIgnored() {
        let diff = "diff --git a/f.swift b/f.swift\n\n\n+added\n"
        let result = DiffFormatter.format(diff, config: ttyConfig())
        #expect(result.contains("added"))
    }

    @Test("format — mode change 行正确处理")
    func formatModeChange() {
        let diff = """
        diff --git a/script.sh b/script.sh
        old mode 100644
        new mode 100755
        """
        let result = DiffFormatter.format(diff, config: ttyConfig())
        #expect(result.contains("old mode 100644"))
        #expect(result.contains("new mode 100755"))
    }

    @Test("format — --- 和 +++ 文件头 dim 显示")
    func formatFileHeaders() {
        let diff = """
        --- a/old.swift
        +++ b/new.swift
        """
        let result = DiffFormatter.format(diff, config: ttyConfig())
        #expect(result.contains("--- a/old.swift"))
        #expect(result.contains("+++ b/new.swift"))
    }

    // MARK: - Helper Configs

    private func nonTTYConfig() -> DiffFormatter.Config {
        DiffFormatter.Config(isTTY: false, profile: .unknown)
    }

    private func ttyConfig() -> DiffFormatter.Config {
        DiffFormatter.Config(isTTY: true, profile: .trueColor)
    }
}
