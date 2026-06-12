import Foundation
import AppKit

import AxionCore

enum AppSearchScope: Equatable, Sendable {
    case fast
    case deep
}

struct AppListItem: Equatable, Sendable {
    let displayName: String
    let bundleIdentifier: String
    let bundlePath: String
    let version: String
    let sizeBytes: Int64
    let isRunning: Bool
    let isSystemProtected: Bool
    let source: AppListSource
}

enum AppListSource: String, Equatable, Sendable {
    case applications
    case spotlight
    case homebrewCask
}

struct AppListResult: Equatable, Sendable {
    let scope: AppSearchScope
    let filter: String?
    let candidates: [AppListItem]
    let protectedMatches: [AppListItem]
    let warnings: [String]
    let deepSearchAvailable: Bool
}

protocol AppListing: Sendable {
    func list(filter: String?, scope: AppSearchScope) async -> AppListResult
}

struct AppBundleMetadata: Equatable, Sendable {
    let displayName: String
    let bundleIdentifier: String
    let version: String
}

final class AppListService: AppListing, Sendable {
    typealias FastURLProvider = @Sendable ([URL]) async -> [URL]
    typealias DeepURLProvider = @Sendable () async -> [URL]
    typealias MetadataReader = @Sendable (URL) -> AppBundleMetadata?
    typealias RunningDetector = @Sendable (String) -> Bool
    typealias SizeReader = @Sendable (URL) -> Int64
    typealias ManagedDetector = @Sendable (URL, AppBundleMetadata) -> Bool

    private let fastRoots: [URL]
    private let fastURLProvider: FastURLProvider
    private let spotlightURLProvider: DeepURLProvider
    private let homebrewURLProvider: DeepURLProvider
    private let metadataReader: MetadataReader
    private let runningDetector: RunningDetector
    private let sizeReader: SizeReader
    private let managedDetector: ManagedDetector

    init(
        fastRoots: [URL] = AppListService.defaultFastRoots(),
        fastURLProvider: @escaping FastURLProvider = AppListService.defaultFastAppURLs,
        spotlightURLProvider: @escaping DeepURLProvider = { await AppListService.defaultSpotlightAppURLs() },
        homebrewURLProvider: @escaping DeepURLProvider = { AppListService.defaultHomebrewCaskAppURLs() },
        metadataReader: @escaping MetadataReader = AppListService.defaultMetadataReader,
        runningDetector: @escaping RunningDetector = AppListService.defaultRunningDetector,
        sizeReader: @escaping SizeReader = AppListService.defaultSizeReader,
        managedDetector: @escaping ManagedDetector = AppListService.defaultManagedDetector
    ) {
        self.fastRoots = fastRoots
        self.fastURLProvider = fastURLProvider
        self.spotlightURLProvider = spotlightURLProvider
        self.homebrewURLProvider = homebrewURLProvider
        self.metadataReader = metadataReader
        self.runningDetector = runningDetector
        self.sizeReader = sizeReader
        self.managedDetector = managedDetector
    }

    func list(filter: String?, scope: AppSearchScope) async -> AppListResult {
        let normalizedFilter = Self.normalizedFilter(filter)
        var warnings: [String] = []
        var sources: [(URL, AppListSource)] = []

        let fastURLs = await fastURLProvider(fastRoots)
        sources.append(contentsOf: fastURLs.map { ($0, .applications) })

        if scope == .deep {
            let spotlightURLs = await spotlightURLProvider()
            let homebrewURLs = await homebrewURLProvider()
            if spotlightURLs.isEmpty {
                warnings.append("Spotlight 未返回额外 App，已保留快速搜索结果")
            }
            if homebrewURLs.isEmpty {
                warnings.append("未发现 Homebrew Caskroom 内 App，或 Caskroom 不存在/不可读")
            }
            sources.append(contentsOf: spotlightURLs.map { ($0, .spotlight) })
            sources.append(contentsOf: homebrewURLs.map { ($0, .homebrewCask) })
        }

        var seen = Set<String>()
        var candidates: [AppListItem] = []
        var protectedMatches: [AppListItem] = []

        for (url, source) in sources {
            let canonicalPath = canonicalPath(url)
            let dedupKey = deduplicationKey(url)
            guard seen.insert(dedupKey).inserted else { continue }
            guard let metadata = metadataReader(url) else { continue }

            let isProtected = AppDiscoveryService.isSystemProtected(
                bundlePath: canonicalPath,
                bundleIdentifier: metadata.bundleIdentifier
            ) || managedDetector(url, metadata)

            let item = AppListItem(
                displayName: metadata.displayName,
                bundleIdentifier: metadata.bundleIdentifier,
                bundlePath: canonicalPath,
                version: metadata.version,
                sizeBytes: sizeReader(url),
                isRunning: runningDetector(metadata.bundleIdentifier),
                isSystemProtected: isProtected,
                source: source
            )

            guard Self.matches(item, filter: normalizedFilter) else { continue }
            if item.isSystemProtected {
                if normalizedFilter != nil {
                    protectedMatches.append(item)
                }
            } else {
                candidates.append(item)
            }
        }

        return AppListResult(
            scope: scope,
            filter: normalizedFilter,
            candidates: Self.sort(candidates),
            protectedMatches: Self.sort(protectedMatches),
            warnings: warnings,
            deepSearchAvailable: scope == .fast
        )
    }

    // MARK: - Pure Helpers

    static func normalizedFilter(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    static func matches(_ item: AppListItem, filter: String?) -> Bool {
        guard let filter else { return true }
        return item.displayName.lowercased().contains(filter)
            || item.bundleIdentifier.lowercased().contains(filter)
            || item.bundlePath.lowercased().contains(filter)
    }

    static func sort(_ items: [AppListItem]) -> [AppListItem] {
        items.sorted {
            let nameCompare = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            return $0.bundleIdentifier < $1.bundleIdentifier
        }
    }

    static func defaultFastRoots(home: String = NSHomeDirectory()) -> [URL] {
        ScanAppUninstallTool.defaultSearchRoots
            .map { StorageExclusions.standardize($0, home: home) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func defaultFastAppURLs(searchRoots: [URL]) async -> [URL] {
        let fm = FileManager.default
        var urls: [URL] = []
        for root in searchRoots {
            guard let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            urls.append(contentsOf: entries.filter { $0.pathExtension == "app" })
        }
        return urls
    }

    static func defaultHomebrewCaskAppURLs(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        var rootPaths = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
        if let prefix = environment["HOMEBREW_PREFIX"], !prefix.isEmpty {
            rootPaths.append(URL(fileURLWithPath: prefix).appendingPathComponent("Caskroom").path)
        }
        let roots = Array(Set(rootPaths)).map { URL(fileURLWithPath: $0) }
        return roots.flatMap { limitedCaskroomAppURLs(root: $0) }
    }

    static func limitedCaskroomAppURLs(root: URL, fileManager: FileManager = .default) -> [URL] {
        guard let casks = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var apps: [URL] = []
        for cask in casks {
            if cask.pathExtension == "app" {
                apps.append(cask)
                continue
            }
            guard let versions = try? fileManager.contentsOfDirectory(
                at: cask,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for version in versions {
                if version.pathExtension == "app" {
                    apps.append(version)
                    continue
                }
                guard let entries = try? fileManager.contentsOfDirectory(
                    at: version,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                apps.append(contentsOf: entries.filter { $0.pathExtension == "app" })
            }
        }
        return apps
    }

    static func defaultSpotlightAppURLs(timeoutSeconds: TimeInterval = 3.0) async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runMDFind(timeoutSeconds: timeoutSeconds))
            }
        }
    }

    static func runMDFind(timeoutSeconds: TimeInterval) -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemContentType == 'com.apple.application-bundle'"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        let outputData = LockedDataBuffer()
        let readGroup = DispatchGroup()

        do {
            try process.run()
        } catch {
            return []
        }

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            outputData.append(data)
            readGroup.leave()
        }

        if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            process.waitUntilExit()
            _ = readGroup.wait(timeout: .now() + 1.0)
            return []
        }
        _ = readGroup.wait(timeout: .now() + 1.0)

        let data = outputData.snapshot()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }
            .filter { $0.pathExtension == "app" }
    }

    static func defaultMetadataReader(url: URL) -> AppBundleMetadata? {
        guard let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else { return nil }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? ""

        return AppBundleMetadata(
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            version: version
        )
    }

    static func defaultRunningDetector(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == bundleIdentifier && !app.isTerminated
        }
    }

    static func defaultSizeReader(url: URL) -> Int64 {
        guard let rv = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .totalFileSizeKey,
            .isDirectoryKey,
        ]) else { return 0 }
        let isDirectory = rv.isDirectory ?? false
        if isDirectory {
            return Int64(rv.totalFileSize ?? rv.fileSize ?? 0)
        }
        return Int64(rv.fileSize ?? 0)
    }

    static func defaultManagedDetector(url: URL, metadata: AppBundleMetadata) -> Bool {
        let bundleId = metadata.bundleIdentifier.lowercased()
        let path = url.standardizedFileURL.path.lowercased()
        let protectedBundleIds: Set<String> = [
            "com.jamfsoftware.selfservice.mac",
            "com.jamfsoftware.management.action",
            "com.googlecode.munki.managedsoftwarecenter",
            "com.kandji.selfservice",
            "com.kandji.kandji",
            "com.microsoft.companyportalmac",
            "com.addigy.selfservice",
        ]
        if protectedBundleIds.contains(bundleId) { return true }

        let protectedBundlePrefixes = [
            "com.jamf.",
            "com.jamfsoftware.",
            "com.kandji.",
            "com.addigy.",
        ]
        if protectedBundlePrefixes.contains(where: { bundleId.hasPrefix($0) }) {
            return true
        }

        let protectedPathFragments = [
            "/self service.app",
            "/jamf.app",
            "/managed software center.app",
            "/company portal.app",
            "/kandji self service.app",
            "/addigy self service.app",
        ]
        return protectedPathFragments.contains { path.contains($0) }
    }

    private func canonicalPath(_ url: URL) -> String {
        Self.canonicalPath(url)
    }

    static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func deduplicationKey(_ url: URL) -> String {
        Self.deduplicationKey(url)
    }

    static func deduplicationKey(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let copy = data
        lock.unlock()
        return copy
    }
}
