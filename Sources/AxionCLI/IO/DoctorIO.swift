import Foundation

/// DoctorIO -- 抽象终端输出，方便测试 doctor 命令。
/// Doctor 不需要用户输入（只做诊断报告），因此只有 write 方法。
protocol DoctorIO {
    func write(_ line: String)
}
