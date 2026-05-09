import Foundation

/// SetupIO — 抽象终端 I/O，方便测试 setup 命令。
/// 通过协议注入，测试可以提供 MockSetupIO 预设输入序列。
protocol SetupIO {
    func write(_ line: String)
    func prompt(_ question: String) -> String
    func promptSecret(_ question: String) -> String
    func confirm(_ question: String, defaultAnswer: Bool) -> Bool
}
