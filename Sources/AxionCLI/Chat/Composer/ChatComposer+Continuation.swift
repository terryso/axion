import Foundation

// MARK: - Continuation (AC2) & Degraded Path (AC7/AC8)

extension ChatComposer {

    /// Raw mode 续行读取。
    mutating func readContinuationRaw(
        reader: any KeyReading,
        accumulated: String,
        prompt: String
    ) -> String {
        var parts = [accumulated]

        while true {
            buffer = ""
            cursor = 0
            mode = .normal
            writeStdout(prompt)

            // Bracket paste 状态（续行模式也需要支持粘贴）
            var inBracketPaste = false
            var pasteBuffer = ""

            while true {
                guard let event = reader.readNext() else {
                    // EOF：返回已累积内容（含未提交的粘贴）
                    if inBracketPaste, !pasteBuffer.isEmpty {
                        parts.append(pasteBuffer)
                    }
                    return parts.joined(separator: "\n")
                }

                switch event {
                // AC3: Bracket paste — 续行中也支持粘贴
                case .bracketPasteStart:
                    inBracketPaste = true
                    pasteBuffer = ""

                case .bracketPasteEnd:
                    inBracketPaste = false
                    // 粘贴内容作为当前行的输入
                    if !pasteBuffer.isEmpty {
                        if buffer.utf8.count + pasteBuffer.utf8.count <= Self.maxInputLength {
                            buffer += pasteBuffer
                            cursor = buffer.count
                        }
                    }
                    refreshDisplay(prompt: prompt)

                case .printable(let char):
                    if inBracketPaste {
                        pasteBuffer.append(char)
                    } else {
                        if buffer.utf8.count < Self.maxInputLength {
                            insertChar(char)
                            refreshDisplay(prompt: prompt)
                        }
                    }

                case .enter:
                    if inBracketPaste {
                        // Bracket paste 中换行符作为内容
                        pasteBuffer.append("\n")
                        continue
                    }

                    // 空行取消续行
                    if buffer.isEmpty {
                        writeStdout("\r\n")
                        return ""
                    }
                    // 续行：行末有反斜杠
                    if buffer.hasSuffix("\\") {
                        parts.append(String(buffer.dropLast()))
                        writeStdout("\r\n")
                        break
                    }
                    // 正常结束
                    parts.append(buffer)
                    return parts.joined(separator: "\n")

                case .backspace:
                    if !buffer.isEmpty {
                        deleteCharBackward()
                        refreshDisplay(prompt: prompt)
                    }

                case .ctrl("c"):
                    writeStdout("\r\n")
                    return "" // Ctrl+C 在续行中取消

                case .escape:
                    if inBracketPaste {
                        // 粘贴中 Esc 取消粘贴
                        inBracketPaste = false
                        pasteBuffer = ""
                        break
                    }
                    // 续行模式中 Esc 取消续行
                    buffer = ""
                    writeStdout("\r\n")
                    return ""

                case .eof:
                    if inBracketPaste, !pasteBuffer.isEmpty {
                        parts.append(pasteBuffer)
                        return parts.joined(separator: "\n")
                    }
                    if buffer.isEmpty {
                        return parts.joined(separator: "\n")
                    }
                    // 非空 buffer 时也返回已累积内容
                    parts.append(buffer)
                    return parts.joined(separator: "\n")

                default:
                    // 其他键在续行中暂不处理
                    break
                }
            }
        }
    }

    // MARK: - Degraded Path (AC7/AC8)

    /// 降级路径 — 委托给 MultiLineInputReader。
    func readDegraded(prompt: String, continuationPrompt: String) -> String? {
        let reader = MultiLineInputReader(
            isTTY: isTTY,
            readLineFn: readLineFn,
            writeStdout: writeStdout,
            writeStderr: writeStderr,
            cjkEnabledFn: { false }  // 降级路径不使用 CJK raw mode
        )
        return reader.readInput(prompt: prompt, continuationPrompt: continuationPrompt)
    }

}
