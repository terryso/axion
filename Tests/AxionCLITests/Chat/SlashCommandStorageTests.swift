import Testing

@testable import AxionCLI

@Suite("SlashCommand /storage")
struct SlashCommandStorageTests {
    @Test("parse /storage")
    func parseStorage() {
        #expect(SlashCommand.parse("/storage") == .storage)
        #expect(SlashCommand.parse("/Storage") == .storage)
    }

    @Test("/storage accepts args and is unavailable while agent busy")
    func metadata() {
        #expect(SlashCommand.storage.acceptsArgs == true)
        #expect(SlashCommand.storage.availableDuringTask == false)
        #expect(SlashCommand.storage.helpText.contains("存储"))
    }

    @Test("/storage help text includes discoverable subcommands")
    func helpTextIncludesSubcommands() {
        let output = SlashCommandHandler.handleStorageHelp()
        #expect(output.contains("/storage scan [path]"))
        #expect(output.contains("/storage organize [path]"))
        #expect(output.contains("/storage large --home [size]"))
        #expect(output.contains("/storage undo [operation_id]"))
    }

    @Test("/storage without subcommand shows help")
    func emptyArgumentBuildsNoTask() {
        #expect(SlashCommandHandler.buildStorageTask(argument: nil) == nil)
        #expect(SlashCommandHandler.buildStorageTask(argument: "") == nil)
        #expect(SlashCommandHandler.buildStorageTask(argument: "help") == nil)
    }

    @Test("/storage scan builds read-only storage_scan task")
    func scanBuildsReadOnlyTask() throws {
        let task = try #require(SlashCommandHandler.buildStorageTask(argument: "scan ~/Downloads"))
        #expect(task.contains("storage_scan"))
        #expect(task.contains("~/Downloads"))
        #expect(task.contains("只读取文件元数据"))
        #expect(task.contains("developer_cache"))
        #expect(task.contains("node_modules"))
        #expect(task.contains("不调用 `propose_storage_plan`"))
    }

    @Test("/storage organize defaults to Downloads and requires approval flow")
    func organizeDefaultsToDownloads() throws {
        let task = try #require(SlashCommandHandler.buildStorageTask(argument: "organize"))
        #expect(task.contains("~/Downloads"))
        #expect(task.contains("storage_scan"))
        #expect(task.contains("propose_storage_plan"))
        #expect(task.contains("execute_storage_plan"))
        #expect(task.contains("逐项审批"))
        #expect(task.contains("developer_cache"))
        #expect(task.contains("不永久删除"))
    }

    @Test("/storage large without args scans common user directories with default threshold")
    func largeDefaultScope() throws {
        let task = try #require(SlashCommandHandler.buildStorageTask(argument: "large"))
        #expect(task.contains("~/Downloads"))
        #expect(task.contains("~/Movies"))
        #expect(task.contains("~/Applications"))
        #expect(task.contains("不传 `min_size_mb`"))
        #expect(task.contains("本轮只列出候选"))
    }

    @Test("/storage large accepts size without path")
    func largeSizeOnly() throws {
        let task = try #require(SlashCommandHandler.buildStorageTask(argument: "large 500MB"))
        #expect(task.contains("min_size_mb: 500"))
        #expect(task.contains("用户输入阈值：500MB"))
        #expect(task.contains("常用用户目录"))
    }

    @Test("/storage large accepts separated number and unit")
    func largeSeparatedSizeUnit() throws {
        let task = try #require(SlashCommandHandler.buildStorageTask(argument: "large 1 GB"))
        #expect(task.contains("min_size_mb: 1000"))
        #expect(task.contains("用户输入阈值：1GB"))
        #expect(task.contains("常用用户目录"))
    }

    @Test("/storage large accepts path and size")
    func largePathAndSize() throws {
        let task = try #require(SlashCommandHandler.buildStorageTask(argument: "large ~/Projects 200MB"))
        #expect(task.contains("目标范围：~/Projects"))
        #expect(task.contains("min_size_mb: 200"))
    }

    @Test("/storage large --home scans home with exclusions")
    func largeHomeScope() throws {
        let task = try #require(SlashCommandHandler.buildStorageTask(argument: "large --home 1GB"))
        #expect(task.contains("整个用户主目录"))
        #expect(task.contains("min_size_mb: 1000"))
        #expect(task.contains("不要主动放宽 `~/Library`"))
    }

    @Test("/storage large rejects ambiguous home path")
    func largeRejectsAmbiguousHomePath() {
        #expect(SlashCommandHandler.buildStorageTask(argument: "large --home ~/Projects") == nil)
        #expect(SlashCommandHandler.buildStorageTask(argument: "large --all") == nil)
    }

    @Test("/storage undo builds undo_storage_op task")
    func undoBuildsTask() throws {
        let task = try #require(SlashCommandHandler.buildStorageTask(argument: "undo storage-123"))
        #expect(task.contains("undo_storage_op"))
        #expect(task.contains("operation_id: \"storage-123\""))
    }

    @Test("/storage undo without id uses latest operation")
    func undoLatestBuildsTask() throws {
        let task = try #require(SlashCommandHandler.buildStorageTask(argument: "undo"))
        #expect(task.contains("undo_storage_op"))
        #expect(task.contains("不传 `operation_id`"))
    }

    @Test("slash popup includes /storage")
    func slashPopupIncludesStorage() {
        let items = SlashPopup.filter(query: "/sto")
        #expect(items.count == 1)
        #expect(items.first?.kind.displayName == "/storage")
    }
}
