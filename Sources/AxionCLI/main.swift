import Foundation
import ArgumentParser

@main
struct AxionCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "axion",
        abstract: "Axion — macOS 桌面自动化 CLI"
    )

    func run() throws {
        print("Axion CLI placeholder")
    }
}
