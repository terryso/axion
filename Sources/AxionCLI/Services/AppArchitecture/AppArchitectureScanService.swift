import Foundation

enum AppBinaryArchitecture: String, CaseIterable, Equatable, Hashable, Sendable {
    case x86_64
    case arm64
    case i386
    case arm
    case unknown
}

enum AppArchitectureCategory: String, Equatable, Sendable {
    case intel = "Intel"
    case appleSilicon = "Apple Silicon"
    case universal = "Universal"
    case unknown = "Unknown"

    static func classify(_ architectures: Set<AppBinaryArchitecture>) -> AppArchitectureCategory {
        let hasIntel = architectures.contains(.x86_64) || architectures.contains(.i386)
        let hasARM = architectures.contains(.arm64) || architectures.contains(.arm)
        if hasIntel && hasARM { return .universal }
        if hasIntel { return .intel }
        if hasARM { return .appleSilicon }
        return .unknown
    }
}

enum AppArchitectureSource: String, Equatable, Sendable {
    case application = "Applications"
    case homebrew = "Homebrew"
    case macPorts = "MacPorts"
}

enum AppArchitectureScanScope: Equatable, Sendable {
    case all
    case appsOnly
    case packagesOnly
}

struct AppArchitectureScanOptions: Equatable, Sendable {
    var filter: String?
    var includeSystemApps: Bool
    var includeAllArchitectures: Bool
    var scope: AppArchitectureScanScope
    var limit: Int

    init(
        filter: String? = nil,
        includeSystemApps: Bool = false,
        includeAllArchitectures: Bool = false,
        scope: AppArchitectureScanScope = .all,
        limit: Int = 80
    ) {
        self.filter = filter
        self.includeSystemApps = includeSystemApps
        self.includeAllArchitectures = includeAllArchitectures
        self.scope = scope
        self.limit = limit
    }
}

struct AppArchitectureItem: Equatable, Sendable {
    let name: String
    let displayPath: String
    let executablePath: String?
    let architectures: Set<AppBinaryArchitecture>
    let isSystemApp: Bool
    let source: AppArchitectureSource

    var category: AppArchitectureCategory {
        AppArchitectureCategory.classify(architectures)
    }
}

struct AppArchitectureScanResult: Equatable, Sendable {
    let options: AppArchitectureScanOptions
    let items: [AppArchitectureItem]
    let warnings: [String]

    var totalCount: Int { items.count }
    var intelCount: Int { count(.intel) }
    var appleSiliconCount: Int { count(.appleSilicon) }
    var universalCount: Int { count(.universal) }
    var unknownCount: Int { count(.unknown) }

    func visibleItems() -> [AppArchitectureItem] {
        let filtered = options.includeAllArchitectures
            ? items
            : items.filter { $0.category == .intel }
        guard options.limit > 0 else { return filtered }
        return Array(filtered.prefix(options.limit))
    }

    func visibleTotalCount() -> Int {
        options.includeAllArchitectures
            ? items.count
            : items.filter { $0.category == .intel }.count
    }

    private func count(_ category: AppArchitectureCategory) -> Int {
        items.filter { $0.category == category }.count
    }
}

protocol AppArchitectureScanning: Sendable {
    func scan(options: AppArchitectureScanOptions) async -> AppArchitectureScanResult
}

final class AppArchitectureScanService: AppArchitectureScanning, Sendable {
    typealias ArchitectureReader = @Sendable (String) -> Set<AppBinaryArchitecture>
    typealias AppRootProvider = @Sendable (Bool) -> [(url: URL, isSystem: Bool)]
    typealias DirectoryReader = @Sendable (URL) -> [URL]?
    typealias BundleExecutableReader = @Sendable (URL) -> String?
    typealias PathExists = @Sendable (String) -> Bool

    private let appRootProvider: AppRootProvider
    private let directoryReader: DirectoryReader
    private let bundleExecutableReader: BundleExecutableReader
    private let architectureReader: ArchitectureReader
    private let pathExists: PathExists
    private let homebrewPrefixes: [String]
    private let macPortsRoot: String

    init(
        appRootProvider: @escaping AppRootProvider = { includeSystem in
            AppArchitectureScanService.defaultAppRoots(includeSystem: includeSystem)
        },
        directoryReader: @escaping DirectoryReader = AppArchitectureScanService.defaultDirectoryReader,
        bundleExecutableReader: @escaping BundleExecutableReader = AppArchitectureScanService.defaultBundleExecutableReader,
        architectureReader: @escaping ArchitectureReader = MachOArchitectureReader.architectures,
        pathExists: @escaping PathExists = { FileManager.default.fileExists(atPath: $0) },
        homebrewPrefixes: [String] = ["/opt/homebrew", "/usr/local"],
        macPortsRoot: String = "/opt/local"
    ) {
        self.appRootProvider = appRootProvider
        self.directoryReader = directoryReader
        self.bundleExecutableReader = bundleExecutableReader
        self.architectureReader = architectureReader
        self.pathExists = pathExists
        self.homebrewPrefixes = homebrewPrefixes
        self.macPortsRoot = macPortsRoot
    }

    func scan(options: AppArchitectureScanOptions) async -> AppArchitectureScanResult {
        let normalizedFilter = Self.normalizedFilter(options.filter)
        var effectiveOptions = options
        effectiveOptions.filter = normalizedFilter

        var items: [AppArchitectureItem] = []
        var warnings: [String] = []

        if options.scope != .packagesOnly {
            items.append(contentsOf: scanApps(includeSystem: options.includeSystemApps))
        }

        if !Task.isCancelled, options.scope != .appsOnly {
            for prefix in homebrewPrefixes {
                items.append(contentsOf: scanHomebrew(prefix: prefix))
            }
            items.append(contentsOf: scanMacPorts(root: macPortsRoot))
        }

        if Task.isCancelled {
            warnings.append("扫描已取消，结果可能不完整")
        }

        let filtered = items
            .filter { Self.matches($0, filter: normalizedFilter) }
            .sorted(by: Self.sort)

        return AppArchitectureScanResult(
            options: effectiveOptions,
            items: filtered,
            warnings: warnings
        )
    }

    static func normalizedFilter(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    static func matches(_ item: AppArchitectureItem, filter: String?) -> Bool {
        guard let filter else { return true }
        return item.name.lowercased().contains(filter)
            || item.displayPath.lowercased().contains(filter)
            || (item.executablePath?.lowercased().contains(filter) ?? false)
            || item.source.rawValue.lowercased().contains(filter)
            || item.category.rawValue.lowercased().contains(filter)
            || architectureList(item.architectures).lowercased().contains(filter)
    }

    static func sort(_ lhs: AppArchitectureItem, _ rhs: AppArchitectureItem) -> Bool {
        let categoryCompare = categoryRank(lhs.category) < categoryRank(rhs.category)
        if categoryRank(lhs.category) != categoryRank(rhs.category) { return categoryCompare }

        let sourceCompare = sourceRank(lhs.source) < sourceRank(rhs.source)
        if sourceRank(lhs.source) != sourceRank(rhs.source) { return sourceCompare }

        let nameCompare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameCompare != .orderedSame {
            return nameCompare == .orderedAscending
        }
        return lhs.displayPath < rhs.displayPath
    }

    static func architectureList(_ architectures: Set<AppBinaryArchitecture>) -> String {
        let order: [AppBinaryArchitecture] = [.x86_64, .i386, .arm64, .arm, .unknown]
        let values = order.filter { architectures.contains($0) }
        return values.isEmpty ? "unknown" : values.map(\.rawValue).joined(separator: ",")
    }

    static func defaultAppRoots(home: String = NSHomeDirectory(), includeSystem: Bool) -> [(url: URL, isSystem: Bool)] {
        var roots: [(URL, Bool)] = [
            (URL(fileURLWithPath: "/Applications", isDirectory: true), false),
            (URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Applications", isDirectory: true), false),
        ]
        if includeSystem {
            roots.append((URL(fileURLWithPath: "/System/Applications", isDirectory: true), true))
        }
        return roots
    }

    static func defaultDirectoryReader(url: URL) -> [URL]? {
        try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
    }

    static func defaultBundleExecutableReader(url: URL) -> String? {
        Bundle(url: url)?.executableURL?.path
    }

    private func scanApps(includeSystem: Bool) -> [AppArchitectureItem] {
        var results: [AppArchitectureItem] = []
        var seenPaths = Set<String>()

        for root in appRootProvider(includeSystem) {
            if Task.isCancelled { break }
            guard let entries = directoryReader(root.url) else { continue }
            for appURL in entries where appURL.pathExtension == "app" {
                if Task.isCancelled { break }
                let canonicalPath = appURL.resolvingSymlinksInPath().standardizedFileURL.path
                guard seenPaths.insert(canonicalPath).inserted else { continue }
                guard let executablePath = bundleExecutableReader(appURL) else {
                    results.append(AppArchitectureItem(
                        name: appURL.deletingPathExtension().lastPathComponent,
                        displayPath: appURL.standardizedFileURL.path,
                        executablePath: nil,
                        architectures: [],
                        isSystemApp: root.isSystem,
                        source: .application
                    ))
                    continue
                }

                results.append(AppArchitectureItem(
                    name: appURL.deletingPathExtension().lastPathComponent,
                    displayPath: appURL.standardizedFileURL.path,
                    executablePath: executablePath,
                    architectures: architectureReader(executablePath),
                    isSystemApp: root.isSystem,
                    source: .application
                ))
            }
        }

        return results
    }

    private func scanHomebrew(prefix: String) -> [AppArchitectureItem] {
        let cellarPath = prefix + "/Cellar"
        let binURL = URL(fileURLWithPath: prefix, isDirectory: true).appendingPathComponent("bin", isDirectory: true)
        guard pathExists(cellarPath),
              let entries = directoryReader(binURL)
        else { return [] }

        var seenFormulas = Set<String>()
        var results: [AppArchitectureItem] = []
        let cellarPrefix = cellarPath + "/"

        for entryURL in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if Task.isCancelled { break }
            let entry = entryURL.lastPathComponent
            guard !entry.hasPrefix(".") else { continue }

            let realPath = entryURL.resolvingSymlinksInPath().path
            guard realPath.hasPrefix(cellarPrefix) else { continue }

            let afterCellar = String(realPath.dropFirst(cellarPrefix.count))
            let formulaName = String(afterCellar.prefix { $0 != "/" })
            guard !formulaName.isEmpty,
                  seenFormulas.insert(formulaName).inserted
            else { continue }

            let archs = architectureReader(realPath)
            guard !archs.isEmpty else { continue }
            results.append(AppArchitectureItem(
                name: formulaName,
                displayPath: realPath,
                executablePath: realPath,
                architectures: archs,
                isSystemApp: false,
                source: .homebrew
            ))
        }

        return results
    }

    private func scanMacPorts(root: String) -> [AppArchitectureItem] {
        let binURL = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("bin", isDirectory: true)
        guard pathExists(binURL.appendingPathComponent("port").path),
              let entries = directoryReader(binURL)
        else { return [] }

        var seenRealPaths = Set<String>()
        var results: [AppArchitectureItem] = []

        for entryURL in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if Task.isCancelled { break }
            let name = entryURL.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            let realPath = entryURL.resolvingSymlinksInPath().path
            guard seenRealPaths.insert(realPath).inserted else { continue }

            let archs = architectureReader(realPath)
            guard !archs.isEmpty else { continue }
            results.append(AppArchitectureItem(
                name: name,
                displayPath: realPath,
                executablePath: realPath,
                architectures: archs,
                isSystemApp: false,
                source: .macPorts
            ))
        }

        return results
    }

    private static func categoryRank(_ category: AppArchitectureCategory) -> Int {
        switch category {
        case .intel: return 0
        case .unknown: return 1
        case .universal: return 2
        case .appleSilicon: return 3
        }
    }

    private static func sourceRank(_ source: AppArchitectureSource) -> Int {
        switch source {
        case .application: return 0
        case .homebrew: return 1
        case .macPorts: return 2
        }
    }
}

struct MachOArchitectureReader {
    private static let mhMagic: UInt32 = 0xfeedface
    private static let mhMagic64: UInt32 = 0xfeedfacf
    private static let fatMagic: UInt32 = 0xcafebabe
    private static let fatMagic64: UInt32 = 0xcafebabf

    private static let cpuTypeI386: Int32 = 7
    private static let cpuTypeX8664: Int32 = 0x01000007
    private static let cpuTypeARM: Int32 = 12
    private static let cpuTypeARM64: Int32 = 0x0100000c

    static func architectures(for path: String) -> Set<AppBinaryArchitecture> {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return []
        }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: 4096)
        return architectures(in: data)
    }

    static func architectures(in data: Data) -> Set<AppBinaryArchitecture> {
        guard data.count >= 8 else { return [] }

        let magicLE = readUInt32(data, offset: 0, endian: .little)
        let magicBE = readUInt32(data, offset: 0, endian: .big)

        if magicLE == mhMagic || magicLE == mhMagic64 {
            let cpu = readInt32(data, offset: 4, endian: .little)
            return [architecture(for: cpu)]
        }

        if magicBE == mhMagic || magicBE == mhMagic64 {
            let cpu = readInt32(data, offset: 4, endian: .big)
            return [architecture(for: cpu)]
        }

        if magicBE == fatMagic || magicBE == fatMagic64 {
            return parseFat(data: data, endian: .big, is64Bit: magicBE == fatMagic64)
        }

        if magicLE == fatMagic || magicLE == fatMagic64 {
            return parseFat(data: data, endian: .little, is64Bit: magicLE == fatMagic64)
        }

        return []
    }

    private enum Endian {
        case little
        case big
    }

    private static func parseFat(data: Data, endian: Endian, is64Bit: Bool) -> Set<AppBinaryArchitecture> {
        let nfat = Int(readUInt32(data, offset: 4, endian: endian))
        guard nfat > 0, nfat <= 64 else { return [] }

        let entrySize = is64Bit ? 32 : 20
        var result = Set<AppBinaryArchitecture>()
        for index in 0..<nfat {
            let base = 8 + index * entrySize
            guard base + 4 <= data.count else { break }
            let cpu = readInt32(data, offset: base, endian: endian)
            result.insert(architecture(for: cpu))
        }
        return result
    }

    private static func architecture(for cpu: Int32) -> AppBinaryArchitecture {
        switch cpu {
        case cpuTypeX8664: return .x86_64
        case cpuTypeARM64: return .arm64
        case cpuTypeI386: return .i386
        case cpuTypeARM: return .arm
        default: return .unknown
        }
    }

    private static func readInt32(_ data: Data, offset: Int, endian: Endian) -> Int32 {
        Int32(bitPattern: readUInt32(data, offset: offset, endian: endian))
    }

    private static func readUInt32(_ data: Data, offset: Int, endian: Endian) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])

        switch endian {
        case .little:
            return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        case .big:
            return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        }
    }
}
