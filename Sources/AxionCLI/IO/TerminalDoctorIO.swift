import Foundation

/// TerminalDoctorIO -- 基于 FileHandle.stdout 的真实终端输出实现。
final class TerminalDoctorIO: DoctorIO {

    func write(_ line: String) {
        let output = line + "\n"
        guard let data = output.data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
    }
}
