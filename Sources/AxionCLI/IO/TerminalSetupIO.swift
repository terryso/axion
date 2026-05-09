import Foundation

/// TerminalSetupIO — 基于 FileHandle.stdin/stdout 的真实终端 I/O 实现。
final class TerminalSetupIO: SetupIO {

    func write(_ line: String) {
        let output = line + "\n"
        guard let data = output.data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
    }

    func prompt(_ question: String) -> String {
        guard let questionData = (question).data(using: .utf8) else { return "" }
        FileHandle.standardOutput.write(questionData)
        guard let line = readLine() else { return "" }
        return line
    }

    func promptSecret(_ question: String) -> String {
        guard let questionData = (question).data(using: .utf8) else { return "" }
        FileHandle.standardOutput.write(questionData)

        // 使用 stty -echo 关闭回显，defer 确保终端始终恢复
        let _ = shell("stty -echo")
        defer { let _ = shell("stty echo") }

        let input = readLine() ?? ""

        // 输出换行（因为 stty -echo 时回车不会换行）
        guard let newline = "\n".data(using: .utf8) else { return input }
        FileHandle.standardOutput.write(newline)

        return input
    }

    func confirm(_ question: String, defaultAnswer: Bool) -> Bool {
        let hint = defaultAnswer ? "[Y/n]" : "[y/N]"
        guard let questionData = "\(question) \(hint) ".data(using: .utf8) else { return defaultAnswer }
        FileHandle.standardOutput.write(questionData)

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return defaultAnswer
        }

        if input.isEmpty { return defaultAnswer }
        return input == "y" || input == "yes"
    }

    // MARK: - Private

    @discardableResult
    private func shell(_ command: String) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]
        task.standardInput = FileHandle.standardInput
        task.standardOutput = FileHandle.standardOutput
        task.standardError = FileHandle.standardError
        do {
            try task.run()
        } catch {
            return 1
        }
        task.waitUntilExit()
        return task.terminationStatus
    }
}
