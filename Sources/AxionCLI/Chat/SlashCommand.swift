
/// 斜杠命令枚举。不依赖 SDK 类型，纯解析层。
///
/// 注意：`/quit` 在 parse() 中映射为 `.exit`，不出现在 allCases 中
/// （allCases 用于 /help 输出，/quit 是 /exit 的别名）。
enum SlashCommand: String, CaseIterable, Equatable {
    case help = "/help"
    case clear = "/clear"
    case compact = "/compact"
    case model = "/model"     // 带可选参数
    case cost = "/cost"
    case resume = "/resume"
    case config = "/config"
    case exit = "/exit"
    case diff = "/diff"       // AC4: git diff 摘要
    case status = "/status"   // AC5: 会话状态卡
    case newSession = "/new"        // AC1: 开始新会话 (38.7)
    case fork = "/fork"             // AC2: 分叉当前会话 (38.7)
    case archive = "/archive"       // AC3: 归档当前会话 (38.7)
    case skills = "/skills"         // 列出可用技能
    case copy = "/copy"             // 复制最后一条 assistant 响应到剪贴板
    case mcp = "/mcp"               // 查看已安装/启用的 MCP server
    case apps = "/apps"             // 列出并选择可卸载 App 候选
    case storage = "/storage"       // 存储扫描、整理、大文件与撤销入口

    /// 解析用户输入为 SlashCommand。非斜杠命令或未知命令返回 nil。
    static func parse(_ input: String) -> SlashCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return nil }
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        let cmd = String(parts[0]).lowercased()
        switch cmd {
        case "/help":    return .help
        case "/clear":   return .clear
        case "/compact": return .compact
        case "/model":   return .model
        case "/cost":    return .cost
        case "/resume":  return .resume
        case "/config":  return .config
        case "/exit", "/quit": return .exit
        case "/diff":    return .diff
        case "/status":  return .status
        case "/new":     return .newSession      // 38.7 AC1
        case "/fork":    return .fork            // 38.7 AC2
        case "/archive": return .archive         // 38.7 AC3
        case "/skills":  return .skills
        case "/copy":    return .copy
        case "/mcp":     return .mcp
        case "/apps":    return .apps
        case "/storage": return .storage
        default: return nil
        }
    }

    /// 提取命令参数（命令名之后的部分，已 trim）。
    static func parseArgument(_ input: String) -> String? {
        let parts = input.split(separator: " ", maxSplits: 1)
        guard parts.count > 1 else { return nil }
        let arg = String(parts[1]).trimmingCharacters(in: .whitespaces)
        return arg.isEmpty ? nil : arg
    }

    /// 用于 /help 显示的简短描述。
    var helpText: String {
        switch self {
        case .help:    return "显示帮助信息"
        case .clear:   return "清除对话上下文"
        case .compact: return "压缩上下文"
        case .model:   return "显示/切换模型（/model [name]）"
        case .cost:    return "显示当前会话 token 用量和成本"
        case .resume:  return "恢复会话（/resume [id]）"
        case .config:  return "显示当前配置"
        case .exit:    return "退出交互模式（/quit 同义）"
        case .diff:       return "显示 git diff 摘要"
        case .status:     return "显示当前会话状态卡"
        case .newSession: return "开始新会话"        // 38.7 AC1
        case .fork:       return "分叉当前会话"      // 38.7 AC2
        case .archive:    return "归档当前会话"      // 38.7 AC3
        case .skills:     return "列出可用技能"
        case .copy:       return "复制最后一条 AI 响应到剪贴板"
        case .mcp:        return "浏览 MCP servers（/mcp [--all]）"
        case .apps:       return "列出可卸载 App 候选（/apps [filter|--all]）"
        case .storage:    return "存储整理入口（/storage help|scan|organize|large|undo）"
        }
    }

    // MARK: - Metadata (AC4)

    /// 命令别名。`/exit` 的别名为 `["quit"]`，其余为空数组。
    /// `/quit` 在 parse() 和面板中均可用，但不出现在 allCases 中。
    var aliases: [String] {
        switch self {
        case .exit:    return ["quit"]
        default:       return []
        }
    }

    /// 是否接受参数。
    /// `.model` 接受模型名，`.resume` 接受会话 ID，部分列表命令接受筛选/选项参数。
    var acceptsArgs: Bool {
        switch self {
        case .model, .resume, .mcp, .apps, .storage:  return true
        default:               return false
        }
    }

    /// agent 正在执行任务时是否可用。
    /// `.resume` 等结构性命令在 agent 忙碌时不可用。
    var availableDuringTask: Bool {
        switch self {
        case .help, .cost, .config, .clear, .copy, .mcp, .exit:  return true
        case .resume, .newSession, .fork, .archive, .skills, .apps, .storage:  return false  // AC6: 38.7
        default:                                     return true
        }
    }

    /// side 会话中是否可用。全部 true — side 会话功能延后到 38.8，预留字段。
    var availableInSide: Bool {
        true
    }

    /// 所有可识别的命令名（rawValue + aliases，均含 `/` 前缀）。
    var allNames: [String] {
        [rawValue] + aliases.map { "/\($0)" }
    }
}
