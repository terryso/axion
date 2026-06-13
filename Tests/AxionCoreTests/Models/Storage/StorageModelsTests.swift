import Testing
import Foundation

@testable import AxionCore

@Suite("Storage Models")
struct StorageModelsTests {

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - FileKind

    @Test("FileKind derive from extension")
    func fileKindDeriveExtension() {
        #expect(FileKind.derive(fileExtension: "dmg", typeIdentifier: nil) == .installer)
        #expect(FileKind.derive(fileExtension: "zip", typeIdentifier: nil) == .archive)
        #expect(FileKind.derive(fileExtension: "PNG", typeIdentifier: nil) == .image)
        #expect(FileKind.derive(fileExtension: "mp4", typeIdentifier: nil) == .video)
        #expect(FileKind.derive(fileExtension: "mp3", typeIdentifier: nil) == .audio)
        #expect(FileKind.derive(fileExtension: "pdf", typeIdentifier: nil) == .document)
        #expect(FileKind.derive(fileExtension: "xyz", typeIdentifier: nil) == .other)
        #expect(FileKind.derive(fileExtension: nil, typeIdentifier: nil) == .other)
    }

    @Test("FileKind derive from type identifier")
    func fileKindDeriveUTI() {
        #expect(FileKind.derive(fileExtension: nil, typeIdentifier: "public.png") == .image)
        #expect(FileKind.derive(fileExtension: nil, typeIdentifier: "public.jpeg") == .image)
        #expect(FileKind.derive(fileExtension: nil, typeIdentifier: "public.mpeg-4") == .video)
        #expect(FileKind.derive(fileExtension: nil, typeIdentifier: "public.pdf") == .document)
        #expect(FileKind.derive(fileExtension: nil, typeIdentifier: "com.apple.application-bundle") == .installer)
    }

    @Test("FileKind Codable round-trip uses snake_case for developer_cache")
    func fileKindRoundTrip() throws {
        #expect(try roundTrip(FileKind.developerCache) == .developerCache)
        #expect(try roundTrip(FileKind.installer) == .installer)
        let data = try JSONEncoder().encode(FileKind.developerCache)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json == "\"developer_cache\"")
    }

    // MARK: - FileSignal

    @Test("FileSignal round-trip preserves snake_case keys")
    func fileSignalRoundTrip() throws {
        let sig = FileSignal(
            path: "/Users/a/Downloads/f.zip",
            name: "f.zip",
            fileExtension: "zip",
            uti: "public.zip-archive",
            sizeBytes: 2048,
            createdAt: "2026-01-01T00:00:00Z",
            modifiedAt: "2026-02-01T00:00:00Z",
            isDirectory: false,
            isBundle: false,
            isHidden: false,
            isSymbolicLink: false,
            isFromDownloads: true,
            kind: .archive
        )
        let decoded = try roundTrip(sig)
        #expect(decoded == sig)
        #expect(decoded.sizeBytes == 2048)
        #expect(decoded.isFromDownloads == true)
    }

    @Test("FileSignal decodes with defaults when fields missing")
    func fileSignalMissingFieldDefaults() throws {
        let json = "{\"path\": \"/x/f.txt\"}".data(using: .utf8)!
        let sig = try JSONDecoder().decode(FileSignal.self, from: json)
        #expect(sig.path == "/x/f.txt")
        #expect(sig.name == "f.txt")  // derived from path
        #expect(sig.sizeBytes == 0)
        #expect(sig.isDirectory == false)
        #expect(sig.kind == .other)
        #expect(sig.isFromDownloads == false)
    }

    // MARK: - FileSignalGroup

    @Test("FileSignalGroup round-trip")
    func groupRoundTrip() throws {
        let g = FileSignalGroup(label: "archive", count: 3, totalSizeBytes: 100, files: [], commonSignals: ["extensions: zip(3)"])
        let decoded = try roundTrip(g)
        #expect(decoded == g)
    }

    // MARK: - StoragePlanItem

    @Test("StoragePlanItem round-trip and approved default false")
    func planItemRoundTrip() throws {
        let item = StoragePlanItem(
            action: .move,
            sourcePath: "/a/b.txt",
            targetPath: "/c/b.txt",
            sizeBytes: 500,
            reason: "large doc",
            riskLevel: .medium,
            approved: false,
            evidence: StorageEvidence(rule: "kind:document", source: "reason", confidence: .high),
            dataRisk: .medium
        )
        let decoded = try roundTrip(item)
        #expect(decoded == item)
        #expect(decoded.approved == false)
    }

    @Test("StoragePlanItem decodes with defaults when fields missing")
    func planItemMissingDefaults() throws {
        let json = "{\"source_path\": \"/x/y.txt\"}".data(using: .utf8)!
        let item = try JSONDecoder().decode(StoragePlanItem.self, from: json)
        #expect(item.sourcePath == "/x/y.txt")
        #expect(item.action == .scanOnly)
        #expect(item.approved == false)
        #expect(item.riskLevel == .low)
        #expect(item.sizeBytes == 0)
    }

    // MARK: - StoragePlan

    @Test("StoragePlan round-trip with excludedNotes")
    func planRoundTrip() throws {
        let plan = StoragePlan(
            operationId: "op-1",
            surface: .run,
            items: [StoragePlanItem(action: .scanOnly, sourcePath: "/a", reason: "r")],
            riskLevel: .medium,
            requiresConfirmation: true,
            reversible: true,
            summary: "summary",
            createdAt: "2026-06-11T00:00:00Z",
            excludedNotes: ["bad: /outside"]
        )
        let decoded = try roundTrip(plan)
        #expect(decoded == plan)
        #expect(decoded.items.first?.approved == false)
        #expect(decoded.excludedNotes == ["bad: /outside"])
    }

    @Test("StoragePlan decodes with defaults when fields missing")
    func planMissingDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let plan = try JSONDecoder().decode(StoragePlan.self, from: json)
        #expect(plan.operationId == "")
        #expect(plan.surface == .run)
        #expect(plan.items == [])
        #expect(plan.riskLevel == .low)
        #expect(plan.requiresConfirmation == true)
        #expect(plan.reversible == true)
        #expect(plan.excludedNotes == nil)
    }

    // MARK: - Enums

    @Test("StorageAction round-trip")
    func actionRoundTrip() throws {
        #expect(StorageAction(rawValue: "scan_only") == .scanOnly)
        #expect(StorageAction(rawValue: "create_directory") == .createDirectory)
        #expect(StorageAction(rawValue: "uninstall_app") == .uninstallApp)
        #expect(try roundTrip(StorageAction.trash) == .trash)
    }

    @Test("RiskLevel.max picks the higher")
    func riskLevelMax() {
        #expect(RiskLevel.max(.low, .high) == .high)
        #expect(RiskLevel.max(.high, .low) == .high)
        #expect(RiskLevel.max(.medium, .medium) == .medium)
        #expect(RiskLevel.max(.low, .low) == .low)
    }

    @Test("StorageSurface / DataRisk / StorageConfidence round-trip")
    func miscEnumsRoundTrip() throws {
        #expect(StorageSurface(rawValue: "telegram") == .telegram)
        #expect(DataRisk(rawValue: "forbidden") == .forbidden)
        #expect(StorageConfidence(rawValue: "high") == .high)
        #expect(try roundTrip(StorageSurface.chat) == .chat)
        #expect(try roundTrip(DataRisk.high) == .high)
    }

    @Test("StorageEvidence defaults confidence to medium")
    func evidenceDefaults() throws {
        let ev = StorageEvidence(rule: "r", source: "s")
        #expect(ev.confidence == .medium)
        let json = "{\"rule\":\"r\",\"source\":\"s\"}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StorageEvidence.self, from: json)
        #expect(decoded.confidence == .medium)
    }

    // MARK: - StorageConfig

    @Test("StorageConfig defaults are 1GB threshold")
    func configDefaults() {
        let d = StorageConfig.default
        #expect(d.largeFileThresholdBytes == 1_073_741_824)
        #expect(d.maxFilesPerGroup == 50)
        #expect(d.excludedPaths == [])
        #expect(d.storageOpsDir.hasPrefix("~/.axion"))
    }

    @Test("StorageConfig partial decode falls back to defaults")
    func configPartialDecode() throws {
        let json = "{\"large_file_threshold_bytes\": 500}".data(using: .utf8)!
        let cfg = try JSONDecoder().decode(StorageConfig.self, from: json)
        #expect(cfg.largeFileThresholdBytes == 500)
        #expect(cfg.maxFilesPerGroup == 50)  // default
        #expect(cfg.excludedPaths == [])  // default
    }
}
