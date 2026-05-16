import ArgumentParser
import Foundation

/// Parent command group for `axion memory` subcommands.
///
/// Provides `list` and `clear` subcommands for managing the accumulated
/// App Memory store.
struct MemoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "memory",
        abstract: "管理 App Memory（历史操作经验）",
        subcommands: [MemoryListCommand.self, MemoryClearCommand.self]
    )
}
