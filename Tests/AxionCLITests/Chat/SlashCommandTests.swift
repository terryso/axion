import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

@Suite("SlashCommand")
struct SlashCommandTests {

    // MARK: - parse() 精确匹配

    @Test("parse /help → .help")
    func parseHelp() {
        #expect(SlashCommand.parse("/help") == .help)
    }

    @Test("parse /clear → .clear")
    func parseClear() {
        #expect(SlashCommand.parse("/clear") == .clear)
    }

    @Test("parse /compact → .compact")
    func parseCompact() {
        #expect(SlashCommand.parse("/compact") == .compact)
    }

    @Test("parse /model → .model")
    func parseModel() {
        #expect(SlashCommand.parse("/model") == .model)
    }

    @Test("parse /cost → .cost")
    func parseCost() {
        #expect(SlashCommand.parse("/cost") == .cost)
    }

    @Test("parse /resume → .resume")
    func parseResume() {
        #expect(SlashCommand.parse("/resume") == .resume)
    }

    @Test("parse /config → .config")
    func parseConfig() {
        #expect(SlashCommand.parse("/config") == .config)
    }

    @Test("parse /exit → .exit")
    func parseExit() {
        #expect(SlashCommand.parse("/exit") == .exit)
    }

    @Test("parse /quit → .exit")
    func parseQuit() {
        #expect(SlashCommand.parse("/quit") == .exit)
    }

    @Test("parse /storage → .storage")
    func parseStorage() {
        #expect(SlashCommand.parse("/storage") == .storage)
    }

    // MARK: - parse() 未知命令和非斜杠

    @Test("parse /foo → nil (未知命令)")
    func parseUnknown() {
        #expect(SlashCommand.parse("/foo") == nil)
    }

    @Test("parse hello → nil (非斜杠)")
    func parseNonSlash() {
        #expect(SlashCommand.parse("hello") == nil)
    }

    @Test("parse 空字符串 → nil")
    func parseEmpty() {
        #expect(SlashCommand.parse("") == nil)
    }

    @Test("parse 纯空白 → nil")
    func parseWhitespace() {
        #expect(SlashCommand.parse("   ") == nil)
    }

    // MARK: - parse() 大小写不敏感

    @Test("parse /Help → .help (大小写不敏感)")
    func parseHelpCaseInsensitive() {
        #expect(SlashCommand.parse("/Help") == .help)
    }

    @Test("parse /CLEAR → .clear (大小写不敏感)")
    func parseClearCaseInsensitive() {
        #expect(SlashCommand.parse("/CLEAR") == .clear)
    }

    @Test("parse /Model → .model (大小写不敏感)")
    func parseModelCaseInsensitive() {
        #expect(SlashCommand.parse("/Model") == .model)
    }

    // MARK: - parse() 尾部空白

    @Test("parse /help (尾部空白) → .help")
    func parseHelpTrailingSpaces() {
        #expect(SlashCommand.parse("/help   ") == .help)
    }

    @Test("parse /model (尾部空白) → .model (无参数)")
    func parseModelTrailingSpaces() {
        #expect(SlashCommand.parse("/model ") == .model)
    }

    // MARK: - parseArgument()

    @Test("parseArgument /model gpt-4o → gpt-4o")
    func parseArgumentModelWithArg() {
        #expect(SlashCommand.parseArgument("/model gpt-4o") == "gpt-4o")
    }

    @Test("parseArgument /help → nil (无参数)")
    func parseArgumentNoArg() {
        #expect(SlashCommand.parseArgument("/help") == nil)
    }

    @Test("parseArgument /model (空白参数) → nil")
    func parseArgumentWhitespaceOnly() {
        #expect(SlashCommand.parseArgument("/model   ") == nil)
    }

    @Test("parseArgument /model claude-opus-4 → claude-opus-4")
    func parseArgumentModelWithComplexArg() {
        #expect(SlashCommand.parseArgument("/model claude-opus-4") == "claude-opus-4")
    }

    // MARK: - allCases + helpText

    @Test("allCases count == 17")
    func allCasesCount() {
        #expect(SlashCommand.allCases.count == 17)
    }

    @Test("每个 helpText 非空且唯一")
    func helpTextsNonEmptyAndUnique() {
        let texts = SlashCommand.allCases.map(\.helpText)
        // 全部非空
        for text in texts {
            #expect(!text.isEmpty)
        }
        // 全部唯一
        #expect(Set(texts).count == texts.count)
    }

    // MARK: - SlashCommandHandler.handleHelp()

    @Test("handleHelp 输出包含所有 8 个命令名和描述")
    func handleHelpOutput() {
        let output = SlashCommandHandler.handleHelp()
        for cmd in SlashCommand.allCases {
            #expect(output.contains(cmd.rawValue))
            #expect(output.contains(cmd.helpText))
        }
    }

    // MARK: - SlashCommandHandler.handleCost()

    @Test("handleCost 输出包含 input/output/total 数字")
    func handleCostOutput() {
        let usage = TokenUsage(
            inputTokens: 1000,
            outputTokens: 500,
            cacheCreationInputTokens: 200,
            cacheReadInputTokens: 300
        )
        let output = SlashCommandHandler.handleCost(usage: usage, model: "claude-sonnet-4-20250514")
        #expect(output.contains("1000"))
        #expect(output.contains("500"))
        #expect(output.contains("1500"))  // total
        #expect(output.contains("$"))
    }

    @Test("handleCost 零值输出正确")
    func handleCostZero() {
        let usage = TokenUsage(inputTokens: 0, outputTokens: 0)
        let output = SlashCommandHandler.handleCost(usage: usage, model: "claude-sonnet-4-20250514")
        #expect(output.contains("0"))
        #expect(output.contains("$0.0000"))
    }

    // MARK: - SlashCommandHandler.handleConfig()

    @Test("handleConfig 输出包含关键配置字段")
    func handleConfigOutput() {
        let output = SlashCommandHandler.handleConfig(
            model: "claude-sonnet-4-20250514",
            maxTokens: 131_072,
            maxSteps: 20,
            noMemory: false,
            noSkills: false,
            permissionMode: "bypassPermissions"
        )
        #expect(output.contains("claude-sonnet-4-20250514"))
        #expect(output.contains("131072"))
        #expect(output.contains("20"))
        #expect(output.contains("bypassPermissions"))
    }

    // MARK: - SlashCommandHandler.handleUnknown()

    @Test("handleUnknown 输出包含 /help 建议")
    func handleUnknownOutput() {
        let output = SlashCommandHandler.handleUnknown("/foo")
        #expect(output.contains("/help"))
    }

    // MARK: - SlashCommandHandler.handleCompact() / handleResume()

    @Test("handleCompact 输出包含上下文状态")
    func handleCompactOutput() {
        let output = SlashCommandHandler.handleCompact()
        #expect(output.contains("当前上下文"))
    }

    @Test("handleCompactNow 无 session 时降级显示上下文状态")
    func handleCompactNowOutput() async {
        let agent = Agent(options: AgentOptions(apiKey: "test"))
        let output = await SlashCommandHandler.handleCompactNow(
            agent: agent,
            contextTokens: 12_000,
            contextWindow: 200_000
        )
        #expect(output.contains("当前上下文"))
    }

    @Test("handleResume 无参数返回 .none")
    func handleResumeNoArgument() {
        let action = SlashCommandHandler.handleResume(argument: nil)
        #expect(action == .none)
    }

    @Test("handleResume 有参数返回 .resumeSession")
    func handleResumeWithArgument() {
        let action = SlashCommandHandler.handleResume(argument: "chat-a1b2c3d4")
        #expect(action == .resumeSession("chat-a1b2c3d4"))
    }

    @Test("handleResume 空字符串参数返回 .none")
    func handleResumeEmptyArgument() {
        let action = SlashCommandHandler.handleResume(argument: "")
        #expect(action == .none)
    }

    // MARK: - handleModelDisplay()

    @Test("handleModelDisplay 输出包含模型名称")
    func handleModelDisplayOutput() {
        let output = SlashCommandHandler.handleModelDisplay(model: "claude-sonnet-4-20250514")
        #expect(output.contains("claude-sonnet-4-20250514"))
        #expect(output.contains("当前模型"))
    }

    @Test("handleModelSwitchSuccess 输出包含新模型名称")
    func handleModelSwitchSuccessOutput() {
        let output = SlashCommandHandler.handleModelSwitchSuccess("gpt-4o")
        #expect(output.contains("gpt-4o"))
        #expect(output.contains("已切换"))
    }

    @Test("handleModelSwitchError 输出包含错误信息")
    func handleModelSwitchErrorOutput() {
        let error = NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "model not found"
        ])
        let output = SlashCommandHandler.handleModelSwitchError(error)
        #expect(output.contains("切换失败"))
        #expect(output.contains("model not found"))
    }

    // MARK: - 未知斜杠命令拦截逻辑验证

    @Test("未知斜杠命令 parse 返回 nil + hasPrefix 检测")
    func unknownSlashCommandDetection() {
        let input = "/foobar"
        // parse 返回 nil（不是已知命令）
        #expect(SlashCommand.parse(input) == nil)
        // 但输入以 / 开头，应该被识别为未知斜杠命令
        #expect(input.hasPrefix("/"))
        // handleUnknown 应该输出 /help 建议
        let output = SlashCommandHandler.handleUnknown(input)
        #expect(output.contains("/help"))
        #expect(output.contains("未知命令"))
    }

    @Test("非斜杠输入不被误判为未知命令")
    func nonSlashNotUnknown() {
        let input = "hello world"
        #expect(SlashCommand.parse(input) == nil)
        #expect(!input.hasPrefix("/"))
    }
}
