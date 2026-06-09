import Testing
import Foundation
import OpenAgentSDK

@testable import AxionCLI

// MARK: - SystemEventRenderer Tests

@Suite("SystemEventRenderer")
struct SystemEventRendererTests {

    // MARK: - Compaction Event

    @Suite("Compaction Event")
    struct CompactionTests {

        @Test("基础压缩通知 — 包含 token 节省百分比")
        func test_basic_compaction() {
            let metadata = SDKMessage.CompactMetadata(
                trigger: .auto,
                preTokens: 15000,
                postTokens: 5000,
                durationMs: 1200
            )
            let result = SystemEventRenderer.renderCompaction(
                metadata: metadata,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("context compacted"))
            #expect(result!.contains("15K→5.0K"))
            #expect(result!.contains("saved 66%"))
            #expect(result!.contains("[auto]"))
            #expect(result!.contains("1.2s"))
            #expect(result!.contains("📦"))
        }

        @Test("压缩通知 — 仅 pre/post tokens 无 trigger 和 duration")
        func test_compaction_without_optional_fields() {
            let metadata = SDKMessage.CompactMetadata(
                preTokens: 100000,
                postTokens: 30000
            )
            let result = SystemEventRenderer.renderCompaction(
                metadata: metadata,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("100K→30K"))
            #expect(result!.contains("saved 70%"))
            #expect(result!.contains("📦"))
            // 不应包含 trigger 或 duration
            #expect(!result!.contains("[auto]"))
            #expect(!result!.contains("[manual]"))
        }

        @Test("压缩通知 — 手动触发")
        func test_compaction_manual_trigger() {
            let metadata = SDKMessage.CompactMetadata(
                trigger: .manual,
                preTokens: 8000,
                postTokens: 3000,
                durationMs: 500
            )
            let result = SystemEventRenderer.renderCompaction(
                metadata: metadata,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("[manual]"))
            #expect(result!.contains("500ms"))
        }

        @Test("压缩通知 — 大 token 数量格式化")
        func test_compaction_large_token_counts() {
            let metadata = SDKMessage.CompactMetadata(
                preTokens: 1_500_000,
                postTokens: 200_000
            )
            let result = SystemEventRenderer.renderCompaction(
                metadata: metadata,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("1.5M→200K"))
            #expect(result!.contains("saved 86%"))
        }

        @Test("压缩通知 — nil metadata 返回 nil")
        func test_compaction_nil_metadata() {
            let result = SystemEventRenderer.renderCompaction(
                metadata: nil,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result == nil)
        }

        @Test("压缩通知 — 无 pre/post tokens 时只显示基本消息")
        func test_compaction_no_token_info() {
            let metadata = SDKMessage.CompactMetadata()
            let result = SystemEventRenderer.renderCompaction(
                metadata: metadata,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("context compacted"))
            // 不应包含括号中的 token 信息
            #expect(!result!.contains("saved"))
        }

        @Test("压缩通知 — 非 TTY 纯文本格式")
        func test_compaction_non_tty() {
            let metadata = SDKMessage.CompactMetadata(
                trigger: .auto,
                preTokens: 15000,
                postTokens: 5000
            )
            let result = SystemEventRenderer.renderCompaction(
                metadata: metadata,
                isTTY: false,
                colorProfile: .unknown
            )
            #expect(result != nil)
            #expect(result!.contains("📦 context compacted"))
            // 非 TTY 不应有 ANSI 码
            #expect(!result!.contains("\u{1B}["))
        }

        @Test("压缩通知 — ANSI256 颜色 profile")
        func test_compaction_ansi256() {
            let metadata = SDKMessage.CompactMetadata(
                preTokens: 10000,
                postTokens: 3000
            )
            let result = SystemEventRenderer.renderCompaction(
                metadata: metadata,
                isTTY: true,
                colorProfile: .ansi256
            )
            #expect(result != nil)
            // 应包含 dim 码
            #expect(result!.contains("\u{1B}[2m"))
            #expect(result!.contains("\u{1B}[0m"))
        }

        @Test("压缩通知 — ANSI16 颜色 profile")
        func test_compaction_ansi16() {
            let metadata = SDKMessage.CompactMetadata(
                preTokens: 10000,
                postTokens: 3000
            )
            let result = SystemEventRenderer.renderCompaction(
                metadata: metadata,
                isTTY: true,
                colorProfile: .ansi16
            )
            #expect(result != nil)
            #expect(result!.contains("\u{1B}[2m"))
            #expect(result!.contains("\u{1B}[0m"))
        }

        @Test("压缩通知 — unknown profile TTY 仍有 dim")
        func test_compaction_unknown_profile() {
            let metadata = SDKMessage.CompactMetadata(
                preTokens: 10000,
                postTokens: 3000
            )
            let result = SystemEventRenderer.renderCompaction(
                metadata: metadata,
                isTTY: true,
                colorProfile: .unknown
            )
            #expect(result != nil)
            // unknown profile 下无 dim 码
            #expect(!result!.contains("\u{1B}[2m"))
        }
    }

    // MARK: - Status Event

    @Suite("Status Event")
    struct StatusTests {

        @Test("compacting 状态 — 进行中")
        func test_status_compacting_in_progress() {
            let result = SystemEventRenderer.renderStatus(
                statusValue: "compacting",
                compactResult: nil,
                compactError: nil,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("compacting context..."))
            #expect(result!.contains("⏳"))
        }

        @Test("compacting 状态 — 成功")
        func test_status_compacting_success() {
            let result = SystemEventRenderer.renderStatus(
                statusValue: "compacting",
                compactResult: "success",
                compactError: nil,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("context compaction succeeded"))
        }

        @Test("compacting 状态 — 失败带错误信息")
        func test_status_compacting_failed_with_error() {
            let result = SystemEventRenderer.renderStatus(
                statusValue: "compacting",
                compactResult: "failed",
                compactError: "token limit exceeded",
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("context compaction failed"))
            #expect(result!.contains("token limit exceeded"))
        }

        @Test("compacting 状态 — 失败无错误信息")
        func test_status_compacting_failed_no_error() {
            let result = SystemEventRenderer.renderStatus(
                statusValue: "compacting",
                compactResult: "failed",
                compactError: nil,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("context compaction failed"))
            // 不应包含冒号后缀
            let range = result!.range(of: "failed:")
            #expect(range == nil)
        }

        @Test("requesting 状态")
        func test_status_requesting() {
            let result = SystemEventRenderer.renderStatus(
                statusValue: "requesting",
                compactResult: nil,
                compactError: nil,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("requesting API..."))
        }

        @Test("未知状态值")
        func test_status_unknown() {
            let result = SystemEventRenderer.renderStatus(
                statusValue: "custom_status",
                compactResult: nil,
                compactError: nil,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("custom_status..."))
        }

        @Test("nil statusValue 返回 nil")
        func test_status_nil() {
            let result = SystemEventRenderer.renderStatus(
                statusValue: nil,
                compactResult: nil,
                compactError: nil,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result == nil)
        }

        @Test("空 statusValue 返回 nil")
        func test_status_empty() {
            let result = SystemEventRenderer.renderStatus(
                statusValue: "",
                compactResult: nil,
                compactError: nil,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result == nil)
        }

        @Test("状态 — 非 TTY 纯文本")
        func test_status_non_tty() {
            let result = SystemEventRenderer.renderStatus(
                statusValue: "compacting",
                compactResult: nil,
                compactError: nil,
                isTTY: false,
                colorProfile: .unknown
            )
            #expect(result != nil)
            #expect(result!.contains("⏳ compacting context..."))
            #expect(!result!.contains("\u{1B}["))
        }

        @Test("状态 — ANSI256 颜色 profile")
        func test_status_ansi256() {
            let result = SystemEventRenderer.renderStatus(
                statusValue: "requesting",
                compactResult: nil,
                compactError: nil,
                isTTY: true,
                colorProfile: .ansi256
            )
            #expect(result != nil)
            #expect(result!.contains("\u{1B}[2m"))
            #expect(result!.contains("\u{1B}[0m"))
        }
    }

    // MARK: - Rate Limit Event

    @Suite("Rate Limit Event")
    struct RateLimitTests {

        @Test("速率限制 — allowed 状态")
        func test_rate_limit_allowed() {
            let info = SDKMessage.RateLimitInfo(
                status: .allowed,
                rateLimitType: .fiveHour,
                utilization: 0.45
            )
            let result = SystemEventRenderer.renderRateLimit(
                rateLimitInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("rate limit: OK"))
            #expect(result!.contains("45% utilized"))
            #expect(result!.contains("5h window"))
        }

        @Test("速率限制 — warning 状态")
        func test_rate_limit_warning() {
            let info = SDKMessage.RateLimitInfo(
                status: .allowedWarning,
                rateLimitType: .sevenDay,
                utilization: 0.75
            )
            let result = SystemEventRenderer.renderRateLimit(
                rateLimitInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("rate limit warning"))
            #expect(result!.contains("75% utilized"))
            #expect(result!.contains("7d window"))
        }

        @Test("速率限制 — rejected 状态")
        func test_rate_limit_rejected() {
            let info = SDKMessage.RateLimitInfo(
                status: .rejected,
                rateLimitType: .sevenDayOpus
            )
            let result = SystemEventRenderer.renderRateLimit(
                rateLimitInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("rate limit exceeded"))
            #expect(result!.contains("7d opus"))
        }

        @Test("速率限制 — 带重置时间")
        func test_rate_limit_with_resets_at() {
            let resetsAt = Int(Date().timeIntervalSince1970) + 7200  // 2 小时后
            let info = SDKMessage.RateLimitInfo(
                status: .allowedWarning,
                resetsAt: resetsAt,
                utilization: 0.8
            )
            let result = SystemEventRenderer.renderRateLimit(
                rateLimitInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("resets in"))
        }

        @Test("速率限制 — overage 标记")
        func test_rate_limit_overage() {
            let info = SDKMessage.RateLimitInfo(
                status: .allowed,
                isUsingOverage: true
            )
            let result = SystemEventRenderer.renderRateLimit(
                rateLimitInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("(overage)"))
        }

        @Test("速率限制 — nil info 返回 nil")
        func test_rate_limit_nil() {
            let result = SystemEventRenderer.renderRateLimit(
                rateLimitInfo: nil,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result == nil)
        }

        @Test("速率限制 — 非 TTY 纯文本")
        func test_rate_limit_non_tty() {
            let info = SDKMessage.RateLimitInfo(
                status: .rejected,
                utilization: 0.95
            )
            let result = SystemEventRenderer.renderRateLimit(
                rateLimitInfo: info,
                isTTY: false,
                colorProfile: .unknown
            )
            #expect(result != nil)
            #expect(result!.contains("rate limit exceeded"))
            #expect(!result!.contains("\u{1B}["))
        }

        @Test("速率限制 — TrueColor 黄色警告颜色")
        func test_rate_limit_truecolor_yellow() {
            let info = SDKMessage.RateLimitInfo(
                status: .allowedWarning,
                utilization: 0.5
            )
            let result = SystemEventRenderer.renderRateLimit(
                rateLimitInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            // TrueColor 黄色: 38;2;234;179;8
            #expect(result!.contains("38;2;234;179;8"))
            #expect(result!.contains("warning:"))
        }

        @Test("速率限制 — ANSI256 颜色")
        func test_rate_limit_ansi256() {
            let info = SDKMessage.RateLimitInfo(
                status: .allowedWarning,
                utilization: 0.5
            )
            let result = SystemEventRenderer.renderRateLimit(
                rateLimitInfo: info,
                isTTY: true,
                colorProfile: .ansi256
            )
            #expect(result != nil)
            #expect(result!.contains("38;5;220"))
        }

        @Test("速率限制 — ANSI16 颜色")
        func test_rate_limit_ansi16() {
            let info = SDKMessage.RateLimitInfo(
                status: .allowedWarning,
                utilization: 0.5
            )
            let result = SystemEventRenderer.renderRateLimit(
                rateLimitInfo: info,
                isTTY: true,
                colorProfile: .ansi16
            )
            #expect(result != nil)
            #expect(result!.contains("\u{1B}[33m"))
        }

        @Test("速率限制 — sonnet 类型")
        func test_rate_limit_sonnet_type() {
            let info = SDKMessage.RateLimitInfo(
                status: .allowed,
                rateLimitType: .sevenDaySonnet
            )
            let result = SystemEventRenderer.renderRateLimit(
                rateLimitInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("7d sonnet"))
        }
    }

    // MARK: - Task Notification Event

    @Suite("Task Notification Event")
    struct TaskNotificationTests {

        @Test("任务完成通知 — 带使用统计")
        func test_task_completed_with_usage() {
            let usage = SDKMessage.TaskNotificationInfo.TaskUsage(
                totalTokens: 50000,
                toolUses: 12,
                durationMs: 45000
            )
            let info = SDKMessage.TaskNotificationInfo(
                taskId: "task-123",
                status: .completed,
                summary: "Fixed 3 tests",
                usage: usage
            )
            let result = SystemEventRenderer.renderTaskNotification(
                taskInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("✓"))
            #expect(result!.contains("completed"))
            #expect(result!.contains("12 tools"))
            #expect(result!.contains("50K tokens"))
            #expect(result!.contains("Fixed 3 tests"))
        }

        @Test("任务失败通知")
        func test_task_failed() {
            let info = SDKMessage.TaskNotificationInfo(
                taskId: "task-456",
                status: .failed
            )
            let result = SystemEventRenderer.renderTaskNotification(
                taskInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("✗"))
            #expect(result!.contains("failed"))
        }

        @Test("任务停止通知")
        func test_task_stopped() {
            let info = SDKMessage.TaskNotificationInfo(
                taskId: "task-789",
                status: .stopped
            )
            let result = SystemEventRenderer.renderTaskNotification(
                taskInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("■"))
            #expect(result!.contains("stopped"))
        }

        @Test("任务通知 — nil info 返回 nil")
        func test_task_nil() {
            let result = SystemEventRenderer.renderTaskNotification(
                taskInfo: nil,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result == nil)
        }

        @Test("任务通知 — 无 status 无 usage")
        func test_task_minimal() {
            let info = SDKMessage.TaskNotificationInfo(
                taskId: "task-000"
            )
            let result = SystemEventRenderer.renderTaskNotification(
                taskInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("📋 task"))
        }

        @Test("任务通知 — 非 TTY 纯文本")
        func test_task_non_tty() {
            let usage = SDKMessage.TaskNotificationInfo.TaskUsage(
                totalTokens: 10000,
                toolUses: 5,
                durationMs: 3000
            )
            let info = SDKMessage.TaskNotificationInfo(
                taskId: "task-123",
                status: .completed,
                usage: usage
            )
            let result = SystemEventRenderer.renderTaskNotification(
                taskInfo: info,
                isTTY: false,
                colorProfile: .unknown
            )
            #expect(result != nil)
            #expect(result!.contains("✓ task"))
            #expect(!result!.contains("\u{1B}["))
        }
    }

    // MARK: - Token Count Formatting

    @Suite("Token Count Formatting")
    struct TokenCountTests {

        @Test("小数量 — 直接显示数字")
        func test_small_count() {
            #expect(SystemEventRenderer.formatTokenCount(345) == "345")
        }

        @Test("千级 — K 后缀")
        func test_thousand_count() {
            #expect(SystemEventRenderer.formatTokenCount(1200) == "1.2K")
        }

        @Test("万级 — 整数 K")
        func test_ten_thousand_count() {
            #expect(SystemEventRenderer.formatTokenCount(15000) == "15K")
        }

        @Test("百万级 — M 后缀")
        func test_million_count() {
            #expect(SystemEventRenderer.formatTokenCount(1_500_000) == "1.5M")
        }

        @Test("零 tokens")
        func test_zero_tokens() {
            #expect(SystemEventRenderer.formatTokenCount(0) == "0")
        }

        @Test("999 — 不用 K")
        func test_just_under_1000() {
            #expect(SystemEventRenderer.formatTokenCount(999) == "999")
        }

        @Test("1000 — 使用 K")
        func test_exactly_1000() {
            #expect(SystemEventRenderer.formatTokenCount(1000) == "1.0K")
        }

        @Test("9999 — 带小数 K")
        func test_just_under_10000() {
            #expect(SystemEventRenderer.formatTokenCount(9999) == "10.0K")
        }
    }

    // MARK: - Duration Formatting

    @Suite("Duration Formatting")
    struct DurationTests {

        @Test("毫秒级")
        func test_milliseconds() {
            #expect(SystemEventRenderer.formatDurationMs(500) == "500ms")
        }

        @Test("秒级 — 带小数")
        func test_seconds() {
            #expect(SystemEventRenderer.formatDurationMs(3500) == "3.5s")
        }

        @Test("分钟级")
        func test_minutes() {
            #expect(SystemEventRenderer.formatDurationMs(125000) == "2m05s")
        }

        @Test("0ms")
        func test_zero_ms() {
            #expect(SystemEventRenderer.formatDurationMs(0) == "0ms")
        }

        @Test("1ms")
        func test_one_ms() {
            #expect(SystemEventRenderer.formatDurationMs(1) == "1ms")
        }

        @Test("999ms")
        func test_just_under_one_second() {
            #expect(SystemEventRenderer.formatDurationMs(999) == "999ms")
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCaseTests {

        @Test("压缩 — preTokens 为 0 不显示百分比")
        func test_compaction_zero_pre_tokens() {
            let metadata = SDKMessage.CompactMetadata(
                preTokens: 0,
                postTokens: 0
            )
            let result = SystemEventRenderer.renderCompaction(
                metadata: metadata,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("context compacted"))
            // preTokens=0 → 不应触发节省百分比计算（避免除零）
            #expect(!result!.contains("saved"))
        }

        @Test("速率限制 — 仅有 status 无其他字段")
        func test_rate_limit_minimal() {
            let info = SDKMessage.RateLimitInfo(
                status: .allowed
            )
            let result = SystemEventRenderer.renderRateLimit(
                rateLimitInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("rate limit: OK"))
        }

        @Test("速率限制 — 空字段不崩溃")
        func test_rate_limit_empty_fields() {
            let info = SDKMessage.RateLimitInfo()
            let result = SystemEventRenderer.renderRateLimit(
                rateLimitInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            // 无有效字段时返回 nil
            #expect(result == nil)
        }

        @Test("任务通知 — 空 summary 不显示破折号")
        func test_task_empty_summary() {
            let info = SDKMessage.TaskNotificationInfo(
                taskId: "task-123",
                status: .completed,
                summary: ""
            )
            let result = SystemEventRenderer.renderTaskNotification(
                taskInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(!result!.contains("—"))
        }

        @Test("任务通知 — usage 中 zero 值不显示")
        func test_task_zero_usage() {
            let usage = SDKMessage.TaskNotificationInfo.TaskUsage(
                totalTokens: 0,
                toolUses: 0,
                durationMs: 0
            )
            let info = SDKMessage.TaskNotificationInfo(
                taskId: "task-123",
                status: .completed,
                usage: usage
            )
            let result = SystemEventRenderer.renderTaskNotification(
                taskInfo: info,
                isTTY: true,
                colorProfile: .trueColor
            )
            #expect(result != nil)
            #expect(result!.contains("completed"))
            // 0 值不应出现在输出中
            #expect(!result!.contains("0 tools"))
            #expect(!result!.contains("0ms"))
            #expect(!result!.contains("0 tokens"))
        }
    }
}
