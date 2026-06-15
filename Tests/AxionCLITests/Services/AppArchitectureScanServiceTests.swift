import Foundation
import Testing

@testable import AxionCLI

@Suite("App Architecture Scan Service")
struct AppArchitectureScanServiceTests {
    private func makeTempDir(_ label: String) throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("AppArchitectureScratch", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dir = root.appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeApp(root: URL, name: String, executableData: Data) throws -> URL {
        let app = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent(name)
        try executableData.write(to: executable)

        let plist: [String: Any] = [
            "CFBundleExecutable": name,
            "CFBundleIdentifier": "com.example.\(name.lowercased())",
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    @Test("Mach-O reader detects thin Intel and fat universal binaries")
    func machOReaderDetectsArchitectures() {
        #expect(MachOArchitectureReader.architectures(in: thinMachO(cpu: 0x01000007)) == [.x86_64])
        #expect(MachOArchitectureReader.architectures(in: thinMachO(cpu: 0x0100000c)) == [.arm64])
        #expect(MachOArchitectureReader.architectures(in: fatMachO(cpus: [0x01000007, 0x0100000c])) == [.x86_64, .arm64])
        #expect(MachOArchitectureReader.architectures(in: Data(repeating: 0, count: 32)).isEmpty)
    }

    @Test("scanner combines apps, Homebrew packages, and MacPorts packages")
    func scannerCombinesAppsAndPackages() async throws {
        let root = try makeTempDir("combined")
        defer { cleanup(root) }

        let appsRoot = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: appsRoot, withIntermediateDirectories: true)
        _ = try makeApp(root: appsRoot, name: "OldApp", executableData: thinMachO(cpu: 0x01000007))
        _ = try makeApp(root: appsRoot, name: "NativeApp", executableData: thinMachO(cpu: 0x0100000c))
        _ = try makeApp(root: appsRoot, name: "UniversalApp", executableData: fatMachO(cpus: [0x01000007, 0x0100000c]))

        let brewPrefix = root.appendingPathComponent("brew", isDirectory: true)
        let brewBin = brewPrefix.appendingPathComponent("bin", isDirectory: true)
        let brewExecutable = brewPrefix
            .appendingPathComponent("Cellar", isDirectory: true)
            .appendingPathComponent("legacy", isDirectory: true)
            .appendingPathComponent("1.0", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: brewExecutable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: brewBin, withIntermediateDirectories: true)
        try thinMachO(cpu: 0x01000007).write(to: brewExecutable)
        try FileManager.default.createSymbolicLink(
            at: brewBin.appendingPathComponent("legacy"),
            withDestinationURL: brewExecutable
        )

        let portsRoot = root.appendingPathComponent("macports", isDirectory: true)
        let portsBin = portsRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: portsBin, withIntermediateDirectories: true)
        try Data().write(to: portsBin.appendingPathComponent("port"))
        try thinMachO(cpu: 0x01000007).write(to: portsBin.appendingPathComponent("legacy-port"))

        let service = AppArchitectureScanService(
            appRootProvider: { _ in [(appsRoot, false)] },
            homebrewPrefixes: [brewPrefix.path],
            macPortsRoot: portsRoot.path
        )

        let result = await service.scan(options: AppArchitectureScanOptions(includeAllArchitectures: true))

        #expect(result.totalCount == 5)
        #expect(result.intelCount == 3)
        #expect(result.appleSiliconCount == 1)
        #expect(result.universalCount == 1)
        #expect(result.items.map(\.name).contains("legacy"))
        #expect(result.items.map(\.name).contains("legacy-port"))
    }

    @Test("result defaults to visible Intel-only items")
    func resultDefaultsToIntelOnlyVisibleItems() {
        let intel = AppArchitectureItem(
            name: "Old",
            displayPath: "/Applications/Old.app",
            executablePath: "/Applications/Old.app/Contents/MacOS/Old",
            architectures: [.x86_64],
            isSystemApp: false,
            source: .application
        )
        let native = AppArchitectureItem(
            name: "Native",
            displayPath: "/Applications/Native.app",
            executablePath: "/Applications/Native.app/Contents/MacOS/Native",
            architectures: [.arm64],
            isSystemApp: false,
            source: .application
        )
        let result = AppArchitectureScanResult(
            options: AppArchitectureScanOptions(),
            items: [intel, native],
            warnings: []
        )

        #expect(result.visibleItems() == [intel])
        #expect(result.visibleTotalCount() == 1)
    }

    @Test("formatter renders summary and hides non-risk items by default")
    func formatterRendersRiskFocusedOutput() {
        let intel = AppArchitectureItem(
            name: "Old",
            displayPath: "/Applications/Old.app",
            executablePath: "/Applications/Old.app/Contents/MacOS/Old",
            architectures: [.x86_64],
            isSystemApp: false,
            source: .application
        )
        let native = AppArchitectureItem(
            name: "Native",
            displayPath: "/Applications/Native.app",
            executablePath: "/Applications/Native.app/Contents/MacOS/Native",
            architectures: [.arm64],
            isSystemApp: false,
            source: .application
        )
        let result = AppArchitectureScanResult(
            options: AppArchitectureScanOptions(),
            items: [intel, native],
            warnings: []
        )

        let output = AppArchitectureFormatter.render(result)

        #expect(output.contains("Intel-only 1"))
        #expect(output.contains("Old"))
        #expect(!output.contains("Native.app"))
        #expect(output.contains("--all"))
    }

    @Test("slash option parser accepts filter and flags")
    func slashOptionParser() throws {
        let options = try #require(AppArchitectureFormatter.parseOptions(
            argument: "visual studio --all --system --packages-only --limit 12"
        ))

        #expect(options.filter == "visual studio")
        #expect(options.includeAllArchitectures)
        #expect(options.includeSystemApps)
        #expect(options.scope == .packagesOnly)
        #expect(options.limit == 12)
        #expect(AppArchitectureFormatter.parseOptions(argument: "--apps-only --packages-only") == nil)
        #expect(AppArchitectureFormatter.parseOptions(argument: "--unknown") == nil)
    }

    private func thinMachO(cpu: UInt32) -> Data {
        var data = Data()
        appendUInt32LE(0xfeedfacf, to: &data)
        appendUInt32LE(cpu, to: &data)
        data.append(Data(repeating: 0, count: 64))
        return data
    }

    private func fatMachO(cpus: [UInt32]) -> Data {
        var data = Data()
        appendUInt32BE(0xcafebabe, to: &data)
        appendUInt32BE(UInt32(cpus.count), to: &data)
        for cpu in cpus {
            appendUInt32BE(cpu, to: &data)
            appendUInt32BE(0, to: &data)
            appendUInt32BE(0, to: &data)
            appendUInt32BE(0, to: &data)
            appendUInt32BE(0, to: &data)
        }
        return data
    }

    private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }

    private func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }
}
