
// MARK: - AC3/AC4: 会话允许列表

/// 前缀匹配规则 — 按命令前 N 个 token 匹配。
///
/// 不使用 `hasPrefix()` 避免误匹配（如 `git` 前缀会匹配 `git push --force`）。
/// 精确比对 token 数组，确保语义上的前缀匹配。
struct PrefixRule: Equatable, Sendable {
    /// 命令前 N 个 token（用于匹配）
    let tokens: [String]
    /// 原始命令字符串（用于显示）
    let rawCommand: String
}

/// 会话允许列表 — 存储本会话已允许的命令。
///
/// 维护两个集合：
/// - `exactMatches`: 精确匹配命令全文
/// - `prefixRules`: 前缀匹配（按 token 边界拆分）
///
/// 纯 struct，零 I/O，线程安全由调用方保证。
/// 会话结束时列表自动清除（不持久化）。
struct SessionAllowList: Equatable, Sendable {
    /// 精确匹配集合 — 存储完整命令字符串
    private(set) var exactMatches: Set<String>

    /// 前缀匹配规则列表
    private(set) var prefixRules: [PrefixRule]

    init(exactMatches: Set<String> = [], prefixRules: [PrefixRule] = []) {
        self.exactMatches = exactMatches
        self.prefixRules = prefixRules
    }

    // MARK: - 查询 (AC3)

    /// 检查命令是否在允许列表中。
    ///
    /// 先查精确匹配，再查前缀匹配。
    /// - Parameter command: 要检查的完整命令字符串
    /// - Returns: 是否已允许
    func isAllowed(command: String) -> Bool {
        // 1. 精确匹配
        if exactMatches.contains(command) {
            return true
        }

        // 2. 前缀匹配 — 按 token 边界比对
        let commandTokens = ApprovalOption.tokenize(command)
        for rule in prefixRules {
            // 命令 token 数必须 >= 规则 token 数才能匹配
            guard commandTokens.count >= rule.tokens.count else { continue }

            // 精确比对前 N 个 token
            let commandPrefix = Array(commandTokens.prefix(rule.tokens.count))
            if commandPrefix == rule.tokens {
                return true
            }
        }

        return false
    }

    // MARK: - 注册 (AC3)

    /// 注册精确匹配 — 允许该命令的完整字符串。
    ///
    /// - Parameter command: 完整命令字符串
    mutating func addExact(_ command: String) {
        exactMatches.insert(command)
    }

    // MARK: - 前缀注册 (AC4)

    /// 按前缀注册允许规则。
    ///
    /// 将命令按 token 边界拆分，取前 N 个 token 注册为前缀规则。
    /// 单 token 命令等同于精确匹配（不注册前缀规则）。
    /// 至少需要 2 个 token 才会注册前缀规则。
    ///
    /// - Parameter command: 完整命令字符串
    mutating func addPrefix(for command: String) {
        let tokens = ApprovalOption.tokenize(command)
        guard tokens.count >= 2 else {
            // 单 token 命令 → 退化为精确匹配
            exactMatches.insert(command)
            return
        }

        // 取前 2 个 token 作为前缀规则
        let prefixTokens = Array(tokens.prefix(2))
        let rule = PrefixRule(tokens: prefixTokens, rawCommand: command)

        // 避免重复注册相同的前缀规则
        if !prefixRules.contains(where: { $0.tokens == prefixTokens }) {
            prefixRules.append(rule)
        }
    }

    // MARK: - 前缀预览 (AC4)

    /// 返回前缀允许的预览文本。
    ///
    /// - Parameter command: 完整命令字符串
    /// - Returns: 前缀预览文本（如 `git commit*`）
    func prefixPreview(for command: String) -> String {
        return ApprovalOption.prefixPreview(for: command)
    }
}

// MARK: - Reference Wrapper

/// SessionAllowList 的引用包装器。
///
/// 用于在 `@Sendable` 闭包中共享可变状态。
/// REPL 单线程使用，线程安全由调用方保证。
final class SessionAllowListRef: @unchecked Sendable {
    private var _list = SessionAllowList()

    init(list: SessionAllowList = SessionAllowList()) {
        self._list = list
    }

    /// 当前允许列表快照（用于测试断言）
    var list: SessionAllowList {
        _list
    }

    func isAllowed(command: String) -> Bool {
        _list.isAllowed(command: command)
    }

    func addExact(_ command: String) {
        _list.addExact(command)
    }

    func addPrefix(for command: String) {
        _list.addPrefix(for: command)
    }

    func prefixPreview(for command: String) -> String {
        _list.prefixPreview(for: command)
    }
}
