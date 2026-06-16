import ArgumentParser
import Darwin
import Foundation
import Testing

@testable import AxionCLI

@Suite("ArchitectureCommand", .serialized)
struct ArchitectureCommandTests {
    private struct MockArchitectureScanner: AppArchitectureScanning {
        let result: AppArchitectureScanResult

        func scan(options _: AppArchitectureScanOptions) async -> AppArchitectureScanResult {
            result
        }
    }

    @Test("AxionCLI registers arch command")
    func archCommandRegistered() {
        let names = AxionCLI.configuration.subcommands.map { $0.configuration.commandName }
        #expect(names.contains("arch"))
    }

    @Test("parses scan options")
    func parsesScanOptions() throws {
        let command = try ArchitectureCommand.parse([
            "chrome",
            "--all",
            "--system",
            "--packages-only",
            "--limit",
            "12",
        ])

        let options = command.scanOptions()
        #expect(options.filter == "chrome")
        #expect(options.includeAllArchitectures)
        #expect(options.includeSystemApps)
        #expect(options.scope == .packagesOnly)
        #expect(options.limit == 12)
    }

    @Test("rejects invalid option combinations")
    func rejectsInvalidOptionCombinations() {
        #expect(throws: (any Error).self) {
            _ = try ArchitectureCommand.parse(["--apps-only", "--packages-only"])
        }
        #expect(throws: (any Error).self) {
            _ = try ArchitectureCommand.parse(["--limit", "0"])
        }
    }

    @Test("run renders scanner output without upgrade plan")
    func runRendersScannerOutputWithoutUpgradePlan() async throws {
        let item = AppArchitectureItem(
            name: "legacy",
            displayPath: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy",
            executablePath: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy",
            architectures: [.x86_64],
            isSystemApp: false,
            source: .homebrew
        )
        let result = AppArchitectureScanResult(
            options: AppArchitectureScanOptions(),
            items: [item],
            warnings: []
        )
        ArchitectureCommand.createScanner = {
            MockArchitectureScanner(result: result)
        }
        defer {
            ArchitectureCommand.createScanner = {
                AppArchitectureScanService()
            }
        }

        let command = try ArchitectureCommand.parse([])
        let output = try await captureStdout {
            try await command.run()
        }

        #expect(output.contains("架构扫描"))
        #expect(output.contains("legacy"))
        #expect(!output.contains("升级状态"))
        #expect(!output.contains("brew upgrade"))
    }

    private func captureStdout(_ operation: () async throws -> Void) async throws -> String {
        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        try #require(originalStdout >= 0)
        fflush(stdout)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        do {
            try await operation()
            fflush(stdout)
            dup2(originalStdout, STDOUT_FILENO)
            close(originalStdout)
            pipe.fileHandleForWriting.closeFile()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            fflush(stdout)
            dup2(originalStdout, STDOUT_FILENO)
            close(originalStdout)
            pipe.fileHandleForWriting.closeFile()
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            throw error
        }
    }
}
