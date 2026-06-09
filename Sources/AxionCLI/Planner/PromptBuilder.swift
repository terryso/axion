import Foundation

/// Prompt 加载与模板变量注入 (AC1)
struct PromptBuilder {

    // MARK: - Prompt 文件加载

    /// 从指定目录加载 .md 文件，替换 `{{key}}` 模板变量
    static func load(name: String, variables: [String: String], fromDirectory directory: String) throws -> String {
        let path = (directory as NSString).appendingPathComponent("\(name).md")
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return variables.reduce(content) { $0.replacingOccurrences(of: "{{\($1.key)}}", with: $1.value) }
    }

    // MARK: - Prompt 目录查找

    /// 支持 SPM 资源路径和开发路径两种查找策略
    static func resolvePromptDirectory() -> String {
        // Strategy 1: Relative to Package.swift (development)
        let cwd = FileManager.default.currentDirectoryPath
        let cwdPrompts = (cwd as NSString).appendingPathComponent("Prompts")
        if FileManager.default.fileExists(atPath: cwdPrompts) {
            return cwdPrompts
        }

        // Strategy 2: Relative to executable (installed distribution)
        // Layout: bin/axion + libexec/axion/Prompts/
        if let execURL = Bundle.main.executableURL {
            let execDir = execURL.deletingLastPathComponent()  // bin/
            let installedPrompts = execDir
                .appendingPathComponent("libexec/axion/Prompts").path
            if FileManager.default.fileExists(atPath: installedPrompts) {
                return installedPrompts
            }
            // Also try sibling libexec (Homebrew Cellar layout)
            let cellarPrompts = execDir
                .appendingPathComponent("../libexec/axion/Prompts").path
            let resolved = (cellarPrompts as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: resolved) {
                return resolved
            }
        }

        // Strategy 3: Fallback to CWD Prompts
        return cwdPrompts
    }

    // MARK: - 工具列表格式化

    /// 将工具名列表格式化为 prompt 中可用的工具描述
    static func buildToolListDescription(from tools: [String]) -> String {
        guard !tools.isEmpty else { return "" }
        return tools.joined(separator: ", ")
    }
}

