import Foundation

/// 轻量级语法高亮器 — 受 Codex syntect 高亮启发，使用正则表达式为常见编程语言
/// 提供基本的语法着色（关键字、字符串、注释、数字），在终端代码块中显著提升可读性。
///
/// 设计原则：
/// - 纯静态方法，无状态，线程安全（Sendable）
/// - 不依赖外部语法解析库（tree-sitter/syntect），使用正则表达式模式匹配
/// - 覆盖 coding agent 最常输出的语言：Swift、Python、JS/TS、Bash、JSON、YAML、Rust、Go、Java、C/C++
/// - 完整颜色 profile 降级链（TrueColor → ANSI256 → ANSI16 → unknown 直通）
/// - 非 TTY 环境直接返回原文本
/// - 高亮顺序：注释 → 字符串 → 关键字 → 数字，避免重叠着色
///
/// 高亮 token 类型及颜色：
/// - 关键字（keyword）：紫色/品红（bold）
/// - 字符串（string）：绿色
/// - 注释（comment）：dim 灰色
/// - 数字（number）：黄色
/// - 类型/内建（builtin）：青色
///
/// 受 Codex `highlight.rs` syntect 集成启发，但 Axion 使用轻量正则方案：
/// - 不引入 heavy 语法解析依赖
/// - 流式行级处理（与 StreamingCodeBlockRenderer 匹配）
/// - 对超出安全限制的输入静默回退为纯文本
struct CodeSyntaxHighlighter: Sendable {

    // MARK: - Safety Limits

    /// 单行最大字符数限制 — 超出此长度的行跳过高亮（避免正则回溯爆炸）
    private static let maxLineLength = 10_000

    // MARK: - Token Types

    /// 语法 token 类型 — 决定颜色
    enum TokenType: String, Sendable, Equatable {
        case keyword   // 语言关键字
        case string    // 字符串字面量
        case comment   // 注释
        case number    // 数字字面量
        case builtin   // 内建类型/函数
    }

    // MARK: - Language Support

    /// 支持高亮的语言标识符（含常见别名）
    static let supportedLanguages: Set<String> = [
        "swift", "python", "py", "javascript", "js", "typescript", "ts", "tsx", "jsx",
        "bash", "sh", "shell", "zsh", "json", "yaml", "yml", "toml",
        "rust", "rs", "go", "golang", "java", "c", "cpp", "c++", "objc", "objective-c",
        "ruby", "rb", "php", "sql", "css", "html", "xml", "markdown", "md",
        "kotlin", "kt", "scala", "dart", "r", "perl", "pl", "lua",
    ]

    /// 解析语言标识符为规范化的语言名称（用于选择高亮规则）
    static func normalizeLanguage(_ lang: String) -> String? {
        let lower = lang.lowercased()
        switch lower {
        case "swift": return "swift"
        case "python", "py": return "python"
        case "javascript", "js": return "javascript"
        case "typescript", "ts": return "typescript"
        case "tsx", "jsx": return "javascript"
        case "bash", "sh", "shell", "zsh": return "bash"
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "toml": return "toml"
        case "rust", "rs": return "rust"
        case "go", "golang": return "go"
        case "java": return "java"
        case "c": return "c"
        case "cpp", "c++": return "cpp"
        case "objc", "objective-c": return "objc"
        case "ruby", "rb": return "ruby"
        case "php": return "php"
        case "sql": return "sql"
        case "css": return "css"
        case "html": return "html"
        case "xml": return "xml"
        case "markdown", "md": return "markdown"
        case "kotlin", "kt": return "kotlin"
        case "scala": return "scala"
        case "dart": return "dart"
        case "r": return "r"
        case "perl", "pl": return "perl"
        case "lua": return "lua"
        default: return supportedLanguages.contains(lower) ? lower : nil
        }
    }

    // MARK: - Main Highlight API

    /// 对一行代码应用语法高亮。
    ///
    /// - Parameters:
    ///   - line: 原始代码行（不含末尾换行）
    ///   - language: 语言标识符（如 "swift", "python"）
    ///   - profile: 终端颜色 profile
    ///   - isTTY: 是否为 TTY 环境
    /// - Returns: 带 ANSI 颜色码的行；不支持的语言或非 TTY 返回原始文本
    static func highlight(
        line: String,
        language: String,
        profile: TerminalColorProfile,
        isTTY: Bool
    ) -> String {
        guard isTTY, !line.isEmpty, line.count <= maxLineLength else {
            return line
        }
        guard let normalized = normalizeLanguage(language) else {
            return line
        }

        // JSON 使用特殊的键值高亮
        if normalized == "json" {
            return highlightJSON(line: line, profile: profile)
        }

        let rules = highlightRules(for: normalized)
        guard !rules.isEmpty else { return line }

        return applyHighlightRules(line: line, rules: rules, profile: profile)
    }

    // MARK: - Highlight Rules per Language

    /// 单条高亮规则 — 匹配正则 + token 类型
    struct HighlightRule: Sendable {
        let pattern: String
        let tokenType: TokenType
        let priority: Int  // 较高优先级先匹配（注释 > 字符串 > 关键字 > 数字）
    }

    /// 返回指定语言的高亮规则列表。
    ///
    /// 规则顺序影响匹配优先级：注释最先匹配（一旦匹配则整行不再处理其他规则），
    /// 然后字符串、关键字、数字、内建类型。
    private static func highlightRules(for language: String) -> [HighlightRule] {
        switch language {
        case "swift":
            return swiftRules
        case "python":
            return pythonRules
        case "javascript", "typescript":
            return javascriptRules
        case "bash", "shell", "zsh":
            return bashRules
        case "rust":
            return rustRules
        case "go":
            return goRules
        case "java", "kotlin":
            return javaRules
        case "c", "cpp", "objc":
            return cFamilyRules
        case "ruby":
            return rubyRules
        case "yaml", "toml":
            return yamlRules
        case "css":
            return cssRules
        case "sql":
            return sqlRules
        default:
            return genericRules
        }
    }

    // MARK: - Language-Specific Rules

    // --- Swift ---
    private static let swiftRules: [HighlightRule] = [
        commentRules(lineComment: "//", blockStart: "/*", blockEnd: "*/"),
        stringRules,
        HighlightRule(pattern: #"\b(accessor|associatedtype|async|await|actor|Any|as|borrowing|break|case|catch|class|consume|consuming|continue|convenience|default|defer|deinit|didSet|do|dynamic|else|enum|extension|fallthrough|fileprivate|final|for|func|get|guard|if|import|in|indirect|infix|init|inout|internal|is|lazy|let|macro|mutating|nil|nonisolated|nonmutating|open|operator|optional|override|package|postfix|precedencegroup|prefix|private|protocol|public|repeat|required|rethrows|return|self|Self|set|some|static|struct|subscript|super|switch|throw|throws|try|Type|typealias|unowned|var|weak|where|while|willSet)\b"#, tokenType: .keyword, priority: 5),
        numberRule,
        HighlightRule(pattern: #"\b(Array|Bool|CGFloat|Character|ClosedRange|Data|Date|Dictionary|Double|Float|Int|Int8|Int16|Int32|Int64|Never|Optional|Range|Result|Set|String|UInt|UInt8|UInt16|UInt32|UInt64|URL|Void|print|fatalError|assert|precondition|guard|true|false)\b"#, tokenType: .builtin, priority: 2),
    ]

    // --- Python ---
    private static let pythonRules: [HighlightRule] = [
        commentRules(lineComment: "#"),
        stringRules,
        HighlightRule(pattern: #"\b(and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield|True|False|None)\b"#, tokenType: .keyword, priority: 5),
        numberRule,
        HighlightRule(pattern: #"\b(print|input|len|range|int|str|float|list|dict|set|tuple|type|isinstance|hasattr|getattr|super|self|__init__|__name__|__main__|__all__|object|property|staticmethod|classmethod|enumerate|zip|map|filter|sorted|reversed|any|all|min|max|sum|abs|round|open|Exception|ValueError|TypeError|KeyError|IndexError|AttributeError|RuntimeError|StopIteration)\b"#, tokenType: .builtin, priority: 2),
    ]

    // --- JavaScript / TypeScript ---
    private static let javascriptRules: [HighlightRule] = [
        commentRules(lineComment: "//", blockStart: "/*", blockEnd: "*/"),
        stringRules,
        HighlightRule(pattern: #"\b(as|async|await|break|case|catch|class|const|constructor|continue|debugger|default|delete|do|else|enum|export|extends|finally|for|from|function|if|implements|import|in|instanceof|interface|let|new|of|package|private|protected|public|return|super|switch|this|throw|throws|try|typeof|var|void|while|with|yield)\b"#, tokenType: .keyword, priority: 5),
        numberRule,
        HighlightRule(pattern: #"\b(Array|Boolean|console|Date|Error|Function|JSON|Map|Math|null|Number|Object|Promise|Proxy|Reflect|RegExp|Set|String|Symbol|undefined|WeakMap|WeakSet|true|false|NaN|Infinity|parseInt|parseFloat|isNaN|isFinite|encodeURIComponent|decodeURIComponent|require|module|exports|process|window|document)\b"#, tokenType: .builtin, priority: 2),
    ]

    // --- Bash / Shell ---
    private static let bashRules: [HighlightRule] = [
        commentRules(lineComment: "#"),
        stringRules,
        HighlightRule(pattern: #"\b(if|then|else|elif|fi|for|while|until|do|done|case|esac|in|function|select|time|coproc|return|exit|break|continue|declare|export|local|readonly|typeset|unset|source|alias|unalias|set|shift|trap|eval|exec|true|false|test)\b"#, tokenType: .keyword, priority: 5),
        numberRule,
        HighlightRule(pattern: #"\b(echo|printf|read|cd|pwd|ls|mkdir|rmdir|rm|cp|mv|cat|head|tail|grep|sed|awk|find|sort|uniq|wc|cut|tr|xargs|tee|curl|wget|chmod|chown|chgrp|touch|ln|tar|gzip|gunzip|bash|sh|zsh|sudo|su|apt|brew|npm|pip|git|docker|make|cargo|swift|xcodebuild|which|type|command|hash|builtin)\b"#, tokenType: .builtin, priority: 2),
    ]

    // --- Rust ---
    private static let rustRules: [HighlightRule] = [
        commentRules(lineComment: "//", blockStart: "/*", blockEnd: "*/"),
        stringRules,
        HighlightRule(pattern: #"\b(as|async|await|become|box|break|const|continue|crate|do|dyn|else|enum|extern|false|final|fn|for|if|impl|in|let|loop|macro|match|mod|move|mut|override|priv|pub|ref|return|self|Self|static|struct|super|trait|true|try|type|typeof|unsafe|unsized|use|virtual|where|while|yield)\b"#, tokenType: .keyword, priority: 5),
        numberRule,
        HighlightRule(pattern: #"\b(Option|Result|Some|None|Ok|Err|Vec|String|Box|Rc|Arc|HashMap|HashSet|BTreeMap|BTreeSet|Cow|Fn|FnMut|FnOnce|Send|Sync|Clone|Copy|Debug|Default|Display|From|Into|Iterator|IntoIterator|ToOwned|ToString|i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64|bool|char|str|println|print|eprintln|eprint|panic|assert|assert_eq|assert_ne|todo|unimplemented|unreachable|vec|format|dbg)\b"#, tokenType: .builtin, priority: 2),
    ]

    // --- Go ---
    private static let goRules: [HighlightRule] = [
        commentRules(lineComment: "//", blockStart: "/*", blockEnd: "*/"),
        stringRules,
        HighlightRule(pattern: #"\b(break|case|chan|const|continue|default|defer|else|fallthrough|for|func|go|goto|if|import|interface|map|package|range|return|select|struct|switch|type|var)\b"#, tokenType: .keyword, priority: 5),
        numberRule,
        HighlightRule(pattern: #"\b(true|false|nil|append|cap|close|complex|copy|delete|imag|len|make|new|panic|print|println|real|recover|error|byte|rune|string|int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|float32|float64|complex64|complex128|bool|error|fmt\.Print|fmt\.Printf|fmt\.Println|fmt\.Fprint|log\.Print|log\.Fatal)\b"#, tokenType: .builtin, priority: 2),
    ]

    // --- Java / Kotlin ---
    private static let javaRules: [HighlightRule] = [
        commentRules(lineComment: "//", blockStart: "/*", blockEnd: "*/"),
        stringRules,
        HighlightRule(pattern: #"\b(abstract|annotation|as|break|by|catch|class|companion|const|constructor|continue|data|do|else|enum|expect|external|false|final|finally|for|fun|get|if|import|in|init|inline|inner|interface|internal|is|it|lateinit|native|new|null|object|of|open|operator|out|override|package|private|protected|public|reified|return|sealed|set|super|suspend|tailrec|this|throw|throws|transient|true|try|typealias|typeof|val|value|var|vararg|when|where|while|yield|void|static|default|extends|implements|instanceof|boolean|byte|char|short|int|long|float|double)\b"#, tokenType: .keyword, priority: 5),
        numberRule,
        HighlightRule(pattern: #"\b(String|Integer|Long|Double|Float|Boolean|Byte|Short|Character|List|Map|Set|ArrayList|HashMap|HashSet|LinkedList|TreeMap|TreeSet|Arrays|Collections|System|Math|Exception|RuntimeException|Thread|Runnable|Override|Deprecated|SuppressWarnings|println|printf|print|toString|equals|hashCode|compareTo|valueOf|parseInt|parseLong)\b"#, tokenType: .builtin, priority: 2),
    ]

    // --- C / C++ / ObjC ---
    private static let cFamilyRules: [HighlightRule] = [
        commentRules(lineComment: "//", blockStart: "/*", blockEnd: "*/"),
        stringRules,
        HighlightRule(pattern: #"\b(auto|break|case|char|class|const|continue|default|do|double|else|enum|extern|float|for|goto|if|inline|int|long|mutable|namespace|new|operator|override|private|protected|public|register|return|short|signed|sizeof|static|struct|switch|template|this|throw|typedef|typename|union|unsigned|using|virtual|void|volatile|while|@interface|@implementation|@end|@property|@synthesize|@dynamic|@class|@protocol|@selector|@encode|@try|@catch|@finally|@throw|@optional|@required|@package|@import|@available|@autoreleasepool|nil|Nil|YES|NO|self|super|copy|nonatomic|atomic|strong|weak|retain|assign|unsafe_unretained|readonly|readwrite|getter|setter)\b"#, tokenType: .keyword, priority: 5),
        numberRule,
        HighlightRule(pattern: #"\b(NSObject|NSString|NSArray|NSDictionary|NSSet|NSNumber|NSData|NSDate|NSURL|NSError|NSMutableArray|NSMutableDictionary|NSMutableSet|NSMutableData|NSRange|NSInteger|NSUInteger|CGFloat|CGPoint|CGSize|CGRect|CGSize|UIView|UIViewController|UIColor|UIImage|UILabel|UIButton|UITableView|UICollectionView|UICollectionViewCell|NSLog|objc_msgSend|dispatch_async|dispatch_sync|dispatch_main|calloc|malloc|realloc|free|printf|sprintf|fprintf|scanf|strlen|strcmp|strcpy|memcpy|memset|sizeof|true|false|NULL|nullptr|TRUE|FALSE|BOOL|stdout|stderr|stdin|EOF)\b"#, tokenType: .builtin, priority: 2),
    ]

    // --- Ruby ---
    private static let rubyRules: [HighlightRule] = [
        commentRules(lineComment: "#"),
        stringRules,
        HighlightRule(pattern: #"\b(BEGIN|END|alias|and|begin|break|case|class|def|defined\?|do|else|elsif|end|ensure|false|for|if|in|module|next|nil|not|or|redo|rescue|retry|return|self|super|then|true|undef|unless|until|when|while|yield|__FILE__|__LINE__|__method__|__dir__)\b"#, tokenType: .keyword, priority: 5),
        numberRule,
        HighlightRule(pattern: #"\b(puts|print|gets|chomp|to_s|to_i|to_f|to_a|to_h|new|require|require_relative|include|extend|attr_accessor|attr_reader|attr_writer|raise|fail|catch|throw|loop|each|map|select|reject|collect|reduce|inject|sort|flatten|compact|uniq|join|split|gsub|sub|match|scan|strip|lstrip|rstrip|length|size|empty\?|nil\?|nil|Array|Hash|String|Integer|Float|Symbol|Proc|Lambda|Range|Regexp|File|Dir|IO|ENV|ARGV|STDOUT|STDERR|STDIN)\b"#, tokenType: .builtin, priority: 2),
    ]

    // --- YAML / TOML ---
    private static let yamlRules: [HighlightRule] = [
        commentRules(lineComment: "#"),
        stringRules,
        HighlightRule(pattern: #"\b(true|false|null|yes|no|on|off|True|False|TRUE|FALSE|Null|NULL|Nil|nil)\b"#, tokenType: .keyword, priority: 5),
        numberRule,
        HighlightRule(pattern: #"^[a-zA-Z_][a-zA-Z0-9_-]*:"#, tokenType: .builtin, priority: 3),
    ]

    // --- CSS ---
    private static let cssRules: [HighlightRule] = [
        commentRules(lineComment: nil, blockStart: "/*", blockEnd: "*/"),
        stringRules,
        HighlightRule(pattern: #"#[0-9a-fA-F]{3,8}\b"#, tokenType: .number, priority: 6),
        HighlightRule(pattern: #"\b(align-content|align-items|align-self|animation|background|border|bottom|box-shadow|box-sizing|clear|clip|color|content|cursor|direction|display|filter|flex|float|font|grid|height|justify-content|left|letter-spacing|line-height|list-style|margin|max-height|max-width|min-height|min-width|opacity|order|outline|overflow|padding|perspective|pointer-events|position|resize|right|scroll-behavior|text-align|text-decoration|text-transform|top|transform|transition|user-select|vertical-align|visibility|white-space|width|word-spacing|word-wrap|z-index)\b"#, tokenType: .keyword, priority: 5),
        numberRule,
        HighlightRule(pattern: #"\b(inherit|initial|unset|auto|none|block|inline|inline-block|flex|grid|absolute|relative|fixed|sticky|static|center|left|right|top|bottom|solid|dashed|dotted|hidden|visible|scroll|wrap|nowrap|bold|normal|italic|uppercase|lowercase|capitalize|transparent|currentColor|ease|ease-in|ease-out|ease-in-out|linear| forwards|backwards|both|infinite|alternate|paused|running|pointer|default|not-allowed|hover|focus|active|visited|link|first-child|last-child|nth-child|root)\b"#, tokenType: .builtin, priority: 2),
    ]

    // --- SQL ---
    private static let sqlRules: [HighlightRule] = [
        commentRules(lineComment: "--", blockStart: "/*", blockEnd: "*/"),
        stringRules,
        HighlightRule(pattern: #"\b(SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|INDEX|VIEW|JOIN|INNER|OUTER|LEFT|RIGHT|FULL|CROSS|ON|AND|OR|NOT|IN|EXISTS|BETWEEN|LIKE|IS|NULL|AS|ORDER|BY|GROUP|HAVING|LIMIT|OFFSET|UNION|ALL|DISTINCT|ASC|DESC|CASE|WHEN|THEN|ELSE|END|COUNT|SUM|AVG|MIN|MAX|CAST|COALESCE|IFNULL|ISNULL|PRIMARY|KEY|FOREIGN|REFERENCES|CONSTRAINT|DEFAULT|CHECK|UNIQUE|AUTO_INCREMENT|SERIAL|BEGIN|COMMIT|ROLLBACK|TRANSACTION|GRANT|REVOKE|select|from|where|insert|into|values|update|set|delete|create|table|alter|drop|index|view|join|inner|outer|left|right|full|cross|on|and|or|not|in|exists|between|like|is|null|as|order|by|group|having|limit|offset|union|all|distinct|asc|desc|case|when|then|else|end|count|sum|avg|min|max|cast|coalesce|ifnull|isnull|primary|key|foreign|references|constraint|default|check|unique|begin|commit|rollback|transaction|grant|revoke)\b"#, tokenType: .keyword, priority: 5),
        numberRule,
        HighlightRule(pattern: #"\b(INTEGER|INT|BIGINT|SMALLINT|TINYINT|FLOAT|DOUBLE|REAL|DECIMAL|NUMERIC|CHAR|VARCHAR|TEXT|BLOB|DATE|TIME|DATETIME|TIMESTAMP|BOOLEAN|BOOL|JSON|UUID|SERIAL|BIGSERIAL|integer|int|bigint|smallint|tinyint|float|double|real|decimal|numeric|char|varchar|text|blob|date|time|datetime|timestamp|boolean|bool|json|uuid|serial|bigserial)\b"#, tokenType: .builtin, priority: 2),
    ]

    // --- Generic (fallback) ---
    private static let genericRules: [HighlightRule] = [
        commentRules(lineComment: "//", blockStart: "/*", blockEnd: "*/"),
        stringRules,
        numberRule,
    ]

    // MARK: - Rule Factories

    /// 注释高亮规则（支持行注释和块注释）
    private static func commentRules(
        lineComment: String?,
        blockStart: String? = nil,
        blockEnd: String? = nil
    ) -> HighlightRule {
        var patterns: [String] = []
        if let lc = lineComment {
            patterns.append("\(NSRegularExpression.escapedPattern(for: lc)).*")
        }
        if let bs = blockStart, let be = blockEnd {
            let escapedStart = NSRegularExpression.escapedPattern(for: bs)
            let escapedEnd = NSRegularExpression.escapedPattern(for: be)
            patterns.append("\(escapedStart)[\\s\\S]*?\(escapedEnd)")
        }
        let combined = patterns.joined(separator: "|")
        return HighlightRule(pattern: combined, tokenType: .comment, priority: 10)
    }

    /// 字符串高亮规则 — 单引号、双引号、反引号模板字符串
    private static let stringRules = HighlightRule(
        pattern: #"(?:@?"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`)"#,
        tokenType: .string,
        priority: 8
    )

    /// 数字高亮规则 — 整数、浮点数、十六进制、二进制、八进制
    private static let numberRule = HighlightRule(
        pattern: #"\b(?:0[xX][0-9a-fA-F]+|0[oO][0-7]+|0[bB][01]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)\b"#,
        tokenType: .number,
        priority: 3
    )

    // MARK: - JSON Highlighting (Specialized)

    /// JSON 专用行高亮 — 键（品红）、字符串值（绿色）、数字（黄色）、布尔/null（紫色）
    private static func highlightJSON(line: String, profile: TerminalColorProfile) -> String {
        let keywordColor = colorCode(for: .keyword, profile: profile)
        let stringColor = colorCode(for: .string, profile: profile)
        let numberColor = colorCode(for: .number, profile: profile)
        let reset = resetCode(for: profile)

        // 简单策略：匹配 JSON 键 "key": → 品红色
        // 匹配字符串值 → 绿色
        // 匹配数字 → 黄色
        // 匹配 true/false/null → 紫色

        var result = ""
        var i = line.startIndex

        while i < line.endIndex {
            let char = line[i]

            // 尝试匹配 JSON key: "..." 后跟 :
            if char == "\"" {
                let (endIdx, content) = scanJSONString(from: i, in: line)

                // 检查后面是否跟 : (表示这是一个 key)
                let afterString = line[endIdx...].trimmingCharacters(in: .whitespaces)
                let isKey = afterString.first == ":"

                if isKey {
                    result += "\(keywordColor)\"\(content)\"\(reset)"
                } else {
                    result += "\(stringColor)\"\(content)\"\(reset)"
                }
                i = endIdx
                continue
            }

            // 数字
            if char.isNumber || (char == "-" && i < line.index(before: line.endIndex) && line[line.index(after: i)].isNumber) {
                let numStart = i
                while i < line.endIndex && (line[i].isNumber || line[i] == "." || line[i] == "e" || line[i] == "E" || line[i] == "+" || line[i] == "-") {
                    i = line.index(after: i)
                }
                let numStr = String(line[numStart..<i])
                result += "\(numberColor)\(numStr)\(reset)"
                continue
            }

            // true/false/null
            if char == "t" || char == "f" || char == "n" {
                let remaining = line[i...]
                let keywords = ["true", "false", "null"]
                var matched = false
                for kw in keywords {
                    if remaining.hasPrefix(kw) {
                        result += "\(keywordColor)\(kw)\(reset)"
                        i = line.index(i, offsetBy: kw.count)
                        matched = true
                        break
                    }
                }
                if matched { continue }
            }

            result.append(char)
            i = line.index(after: i)
        }

        return result
    }

    /// 扫描 JSON 字符串内容（处理转义字符）
    private static func scanJSONString(from index: String.Index, in line: String) -> (endIndex: String.Index, content: String) {
        var i = line.index(after: index) // skip opening "
        var content = ""

        while i < line.endIndex {
            let char = line[i]
            if char == "\\" {
                // 转义字符 — 保留下一个字符
                let nextIdx = line.index(after: i)
                if nextIdx < line.endIndex {
                    content.append(char)
                    content.append(line[nextIdx])
                    i = line.index(after: nextIdx)
                } else {
                    content.append(char)
                    i = nextIdx
                }
            } else if char == "\"" {
                // 闭合引号 — 返回引号后的位置
                return (line.index(after: i), content)
            } else {
                content.append(char)
                i = line.index(after: i)
            }
        }

        return (i, content)
    }

    // MARK: - Apply Rules Engine

    /// 对一行应用高亮规则集合。
    ///
    /// 策略：逐字符扫描，在每个位置尝试所有规则（按优先级排序），
    /// 第一个匹配的规则决定该 token 的颜色。
    /// 已着色区域跳过，避免重叠。
    private static func applyHighlightRules(
        line: String,
        rules: [HighlightRule],
        profile: TerminalColorProfile
    ) -> String {
        // 按优先级降序排序（高优先级先匹配）
        let sortedRules = rules.sorted { $0.priority > $1.priority }

        // 为每个字符位置记录 token 类型（nil = 无着色）
        let scalars = Array(line.unicodeScalars)
        let count = scalars.count
        var tokenMap: [TokenType?] = Array(repeating: nil, count: count)

        // 预编译正则表达式
        var compiledRegexes: [(regex: NSRegularExpression, tokenType: TokenType)] = []
        for rule in sortedRules {
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: []) {
                compiledRegexes.append((regex: regex, tokenType: rule.tokenType))
            }
        }

        // 使用 NSString 匹配（与 Swift String 索引兼容）
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        for (regex, tokenType) in compiledRegexes {
            regex.enumerateMatches(in: line, options: [], range: fullRange) { result, _, _ in
                guard let result = result else { return }
                let range = result.range
                // 将 NSRange 映射到 unicodeScalars 索引
                // 使用 String.Index 转换确保正确性
                let startIdx = nsLine.characterOffset(toSwiftIndex: range.location, in: line)
                let endIdx = nsLine.characterOffset(toSwiftIndex: range.location + range.length, in: line)

                for i in startIdx..<min(endIdx, count) {
                    if tokenMap[i] == nil {
                        tokenMap[i] = tokenType
                    }
                }
            }
        }

        // 生成带颜色的输出
        return renderColoredLine(scalars: scalars, tokenMap: tokenMap, profile: profile)
    }

    // MARK: - Color Rendering

    /// 将 token 映射表渲染为带 ANSI 颜色码的字符串。
    ///
    /// 连续相同 token 类型的字符合并为一个颜色段，减少 ANSI 码数量。
    private static func renderColoredLine(
        scalars: [UnicodeScalar],
        tokenMap: [TokenType?],
        profile: TerminalColorProfile
    ) -> String {
        let reset = resetCode(for: profile)
        var result = ""
        var currentTokenType: TokenType? = nil
        var segmentStart = 0

        for i in 0..<scalars.count {
            let token = tokenMap[i]
            if token != currentTokenType {
                // 刷新当前段
                if segmentStart < i {
                    let segment = UnicodeScalarArray(scalars[segmentStart..<i]).stringValue
                    if let tt = currentTokenType {
                        let color = colorCode(for: tt, profile: profile)
                        result += "\(color)\(segment)\(reset)"
                    } else {
                        result += segment
                    }
                }
                currentTokenType = token
                segmentStart = i
            }
        }

        // 刷新最后一段
        if segmentStart < scalars.count {
            let segment = UnicodeScalarArray(scalars[segmentStart..<scalars.count]).stringValue
            if let tt = currentTokenType {
                let color = colorCode(for: tt, profile: profile)
                result += "\(color)\(segment)\(reset)"
            } else {
                result += segment
            }
        }

        return result
    }

    // MARK: - Color Codes

    /// 返回指定 token 类型在给定 profile 下的 ANSI 颜色码。
    static func colorCode(for tokenType: TokenType, profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor:
            return trueColorCode(for: tokenType)
        case .ansi256:
            return ansi256Code(for: tokenType)
        case .ansi16:
            return ansi16Code(for: tokenType)
        case .unknown:
            return ""
        }
    }

    /// reset 码
    static func resetCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .unknown: return ""
        default: return "\u{1B}[0m"
        }
    }

    // TrueColor (24-bit RGB)
    private static func trueColorCode(for tokenType: TokenType) -> String {
        switch tokenType {
        case .keyword:  return "\u{1B}[38;2;198;120;221m"  // 紫色（类似 syntect purple）
        case .string:   return "\u{1B}[38;2;166;226;46m"   // 绿色（类似 monokai green）
        case .comment:  return "\u{1B}[38;2;128;128;128m"  // dim 灰色
        case .number:   return "\u{1B}[38;2;230;219;116m"  // 黄色（类似 monokai yellow）
        case .builtin:  return "\u{1B}[38;2;102;217;239m"  // 青色（类似 monokai cyan）
        }
    }

    // ANSI256
    private static func ansi256Code(for tokenType: TokenType) -> String {
        switch tokenType {
        case .keyword:  return "\u{1B}[38;5;183m"  // purple
        case .string:   return "\u{1B}[38;5;118m"  // green
        case .comment:  return "\u{1B}[38;5;244m"  // gray
        case .number:   return "\u{1B}[38;5;186m"  // yellow
        case .builtin:  return "\u{1B}[38;5;117m"  // cyan
        }
    }

    // ANSI16
    private static func ansi16Code(for tokenType: TokenType) -> String {
        switch tokenType {
        case .keyword:  return "\u{1B}[35m"  // magenta
        case .string:   return "\u{1B}[32m"  // green
        case .comment:  return "\u{1B}[2m"   // dim
        case .number:   return "\u{1B}[33m"   // yellow
        case .builtin:  return "\u{1B}[36m"   // cyan
        }
    }
}

// MARK: - Helper Extensions

/// NSString → unicodeScalar 索引转换辅助
private extension NSString {
    /// 将 NSString 字符偏移量转换为 Swift String 的 unicodeScalar 索引偏移量。
    ///
    /// 处理 UTF-16 surrogate pairs（emoji 等多字节字符）导致的偏移差异。
    func characterOffset(toSwiftIndex nsLocation: Int, in string: String) -> Int {
        let utf16 = string.utf16
        guard nsLocation <= utf16.count else {
            return string.unicodeScalars.count
        }
        let utf16Index = utf16.index(utf16.startIndex, offsetBy: nsLocation)
        let stringIndex = String.Index(utf16Index, within: string) ?? string.endIndex
        return string.unicodeScalars.distance(from: string.unicodeScalars.startIndex, to: stringIndex)
    }
}

/// 从 UnicodeScalar 切片构造 String 的辅助
private struct UnicodeScalarArray {
    let scalars: [UnicodeScalar]
    init(_ slice: ArraySlice<UnicodeScalar>) {
        self.scalars = Array(slice)
    }

    /// 转换为 String
    var stringValue: String {
        String(String.UnicodeScalarView(scalars))
    }
}
