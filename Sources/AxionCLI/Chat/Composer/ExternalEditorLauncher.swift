import Foundation

/// 外部编辑器启动器 — 管理编辑器解析、进程启动和临时文件。
///
/// 所有 I/O 通过注入闭包实现，测试中可 Mock 替换。
/// 生产环境使用 `ExternalEditorLauncher.production()` 创建实例。
struct ExternalEditorLauncher {

    // MARK: - DI Closures

    /// 获取环境变量值
    let envVar: (String) -> String?
    /// 创建临时文件并写入内容。返回文件路径，失败返回 nil。
    let createTempFile: (String) -> String?
    /// 读取文件内容。返回文件文本，失败返回 nil。
    let readFile: (String) -> String?
    /// 删除文件
    let deleteFile: (String) -> Void
    /// 启动进程并等待退出。返回退出码。
    let launchProcess: (String, [String]) -> Int32?
    /// 恢复终端到 normal mode
    let restoreTerminal: () -> Void
    /// 重新进入 raw mode
    let reEnterRawMode: () -> Void

    // MARK: - Factory

    /// 创建生产环境实例（使用真实 I/O）。
    static func production(
        restoreTerminal: @escaping () -> Void,
        reEnterRawMode: @escaping () -> Void
    ) -> ExternalEditorLauncher {
        ExternalEditorLauncher(
            envVar: { getenv($0).map { String(cString: $0) } },
            createTempFile: { content in
                let tempDir = NSTemporaryDirectory()
                let path = tempDir + "axion-composer-\(UUID().uuidString).md"
                do {
                    try content.write(toFile: path, atomically: true, encoding: .utf8)
                    return path
                } catch {
                    return nil
                }
            },
            readFile: { path in
                try? String(contentsOfFile: path, encoding: .utf8)
            },
            deleteFile: { path in
                try? FileManager.default.removeItem(atPath: path)
            },
            launchProcess: { executable, arguments in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardInput = FileHandle.standardInput
                process.standardOutput = FileHandle.standardOutput
                process.standardError = FileHandle.standardError
                do {
                    try process.run()
                    process.waitUntilExit()
                    return process.terminationStatus
                } catch {
                    return nil
                }
            },
            restoreTerminal: restoreTerminal,
            reEnterRawMode: reEnterRawMode
        )
    }

    // MARK: - Public API

    /// 检测外部编辑器 — 优先级：$VISUAL → $EDITOR。
    /// - Returns: 编辑器路径（nil 表示未设置）
    func resolveEditor() -> String? {
        if let visual = envVar("VISUAL"), !visual.isEmpty {
            return visual
        }
        if let editor = envVar("EDITOR"), !editor.isEmpty {
            return editor
        }
        return nil
    }

    /// 启动外部编辑器编辑内容。
    ///
    /// 流程：
    /// 1. 创建临时文件并写入当前内容
    /// 2. 恢复终端到 normal mode
    /// 3. 启动编辑器子进程
    /// 4. 等待编辑器退出
    /// 5. 恢复 raw mode
    /// 6. 读取编辑后内容
    /// 7. 删除临时文件
    ///
    /// - Parameters:
    ///   - editor: 编辑器路径（通过 `resolveEditor()` 获取）
    ///   - initialContent: 初始内容（当前 buffer）
    /// - Returns: 编辑后的内容（nil 表示失败）
    func launch(editor: String, initialContent: String) -> String? {
        // AC6: 创建临时文件
        guard let tempPath = createTempFile(initialContent) else {
            // AC7: 临时文件创建失败 → 返回 nil（不崩溃）
            return nil
        }

        // AC6: 恢复终端到 normal mode
        restoreTerminal()

        // AC6: 启动编辑器
        let exitCode = launchProcess(editor, [tempPath])

        // AC7: 无论退出码如何，都恢复 raw mode
        reEnterRawMode()

        // AC7: 编辑器非零退出 → 返回 nil
        guard let code = exitCode, code == 0 else {
            deleteFile(tempPath)
            return nil
        }

        // AC6: 读取编辑后内容
        let content = readFile(tempPath)

        // 清理临时文件
        deleteFile(tempPath)

        return content
    }
}
