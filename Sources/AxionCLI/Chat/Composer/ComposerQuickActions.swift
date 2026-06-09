
// MARK: - Quick Actions: Input Queue & External Editor (Story 38.5, AC6/AC7)

extension ChatComposer {

    // MARK: External Editor (AC6/AC7)

    /// 处理 Ctrl+G 外部编辑器 — AC6/AC7。
    mutating func handleExternalEditor(prompt: String) {
        // 使用注入的 launcher 或创建 production 实例
        let launcher: ExternalEditorLauncher
        if let injected = injectedEditorLauncher {
            launcher = injected
        } else {
            let keyReader = ownedKeyReader
            launcher = ExternalEditorLauncher.production(
                restoreTerminal: { keyReader?.restore() },
                reEnterRawMode: { keyReader?.reEnterRawMode() }
            )
        }

        // AC6: 检测编辑器
        guard let editor = launcher.resolveEditor() else {
            // AC6: 未设置编辑器 → 显示提示
            writeStderr("[axion] 请设置 VISUAL 或 EDITOR 环境变量以使用外部编辑器\n")
            refreshDisplay(prompt: prompt)
            return
        }

        // AC6: 启动编辑器
        if let content = launcher.launch(editor: editor, initialContent: buffer) {
            // AC6: 成功 → 回填内容
            buffer = content
            cursor = buffer.count
        } else {
            // AC7: 编辑器异常退出或文件读取失败 → 保留原始 buffer
            writeStderr("[axion] 编辑器未能完成编辑\n")
        }

        refreshDisplay(prompt: prompt)
    }

    // MARK: Input Queue (Story 38.5)

    /// Ctrl+E — 弹出最近一条排队消息到 buffer 可编辑（AC3）。
    ///
    /// 仅在 normal 模式 + buffer 为空时触发，队列为空时无操作。
    mutating func handleCtrlE(prompt: String) {
        guard mode.isNormal, buffer.isEmpty else { return }
        guard var queue = inputQueue, let last = queue.removeLast() else { return }
        inputQueue = queue
        buffer = last.text
        cursor = buffer.count
        refreshDisplay(prompt: prompt)
    }

    /// Ctrl+Q — 将当前 buffer 内容入队（Story 38.5）。
    ///
    /// 仅在 normal 模式 + buffer 非空时触发。
    /// 入队后清空 buffer，显示排队反馈。
    mutating func handleCtrlQ(prompt: String) {
        guard mode.isNormal, !buffer.isEmpty else { return }
        guard var queue = inputQueue else { return }

        let text = buffer
        let result = queue.enqueue(text: text)
        inputQueue = queue

        switch result {
        case .success:
            buffer = ""
            cursor = 0
            refreshDisplay(prompt: prompt)
            // AC6: 显示入队反馈
            if let preview = inputQueue?.previewSummary() {
                writeStderr("\r\n\(preview)\r\n")
            }
            // 重新显示 prompt
            writeStdout(prompt)

        case .queueFull(let currentCount):
            // AC4: 队列已满提示
            writeStderr("\r\n排队已满（\(currentCount)/\(queue.maxCapacity)），请等待当前任务完成\r\n")
            writeStdout(prompt)

        case .duplicate:
            // 重复消息 — 静默忽略
            break
        }
    }

    /// 渲染排队预览字符串（AC6）。
    ///
    /// 返回排队预览或 nil（队列为空时）。在 refreshDisplay 后追加。
    func renderQueuePreview() -> String? {
        guard let queue = inputQueue, !queue.isEmpty else { return nil }
        return queue.previewSummary()
    }
}
