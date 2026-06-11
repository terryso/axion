import Testing
import Foundation

@testable import AxionCore

@Suite("Storage Manifest Models")
struct StorageManifestTests {

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - StorageOpStatus

    @Test("StorageOpStatus raw values and round-trip")
    func opStatusRawValues() throws {
        #expect(StorageOpStatus(rawValue: "planned") == .planned)
        #expect(StorageOpStatus(rawValue: "executing") == .executing)
        #expect(StorageOpStatus(rawValue: "completed") == .completed)
        #expect(StorageOpStatus(rawValue: "partially_failed") == .partiallyFailed)
        #expect(StorageOpStatus(rawValue: "cancelled") == .cancelled)
        #expect(try roundTrip(StorageOpStatus.partiallyFailed) == .partiallyFailed)
    }

    // MARK: - Outcomes

    @Test("StorageItemOutcome / StorageUndoOutcome round-trip")
    func outcomesRoundTrip() throws {
        #expect(try roundTrip(StorageItemOutcome.succeeded) == .succeeded)
        #expect(try roundTrip(StorageItemOutcome.failed) == .failed)
        #expect(try roundTrip(StorageItemOutcome.skipped) == .skipped)
        #expect(StorageUndoOutcome(rawValue: "not_restored") == .notRestored)
        #expect(StorageUndoOutcome(rawValue: "restored") == .restored)
        #expect(try roundTrip(StorageUndoOutcome.notRestored) == .notRestored)
    }

    // MARK: - StorageManifestItem

    @Test("StorageManifestItem round-trip preserves snake_case keys")
    func itemRoundTrip() throws {
        let item = StorageManifestItem(
            action: .move,
            sourcePath: "/a/b.txt",
            targetPath: "/c/b.txt",
            trashResultPath: nil,
            sizeBytes: 500,
            outcome: .succeeded,
            reason: nil,
            evidence: StorageEvidence(rule: "kind:document", source: "agent", confidence: .high),
            approvedAt: "2026-06-11T00:00:00Z"
        )
        let decoded = try roundTrip(item)
        #expect(decoded == item)
        #expect(decoded.targetPath == "/c/b.txt")
        #expect(decoded.sizeBytes == 500)

        // snake_case on the wire
        let data = try JSONEncoder().encode(item)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"source_path\""))
        #expect(json.contains("\"target_path\""))
        #expect(json.contains("\"size_bytes\""))
        #expect(json.contains("\"approved_at\""))
        #expect(!json.contains("\"sourcePath\""))
    }

    @Test("StorageManifestItem decodes with defaults when fields missing")
    func itemMissingDefaults() throws {
        let json = "{\"source_path\": \"/x/y.txt\", \"action\": \"trash\"}".data(using: .utf8)!
        let item = try JSONDecoder().decode(StorageManifestItem.self, from: json)
        #expect(item.sourcePath == "/x/y.txt")
        #expect(item.action == .trash)
        #expect(item.outcome == .skipped)  // decode default
        #expect(item.sizeBytes == 0)
        #expect(item.targetPath == nil)
        #expect(item.trashResultPath == nil)
        #expect(item.reason == nil)
    }

    // MARK: - StorageUndoResult

    @Test("StorageUndoResult round-trip")
    func undoResultRoundTrip() throws {
        let r = StorageUndoResult(
            sourcePath: "/a/b.txt",
            action: .trash,
            outcome: .notRestored,
            reason: "item_no_longer_in_trash"
        )
        let decoded = try roundTrip(r)
        #expect(decoded == r)
        let data = try JSONEncoder().encode(r)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"source_path\""))
        #expect(json.contains("\"not_restored\""))
    }

    // MARK: - StorageManifest

    @Test("StorageManifest round-trip preserves snake_case and nested items")
    func manifestRoundTrip() throws {
        let manifest = StorageManifest(
            operationId: "op-1",
            createdAt: "2026-06-11T00:00:00Z",
            surface: .run,
            userRequest: "clean downloads",
            approvedByUser: "2 item(s) approved via run",
            items: [
                StorageManifestItem(action: .move, sourcePath: "/a", targetPath: "/b", outcome: .succeeded),
                StorageManifestItem(action: .trash, sourcePath: "/c", trashResultPath: "/Trash/c", outcome: .failed, reason: "trash_failed"),
            ],
            status: .partiallyFailed,
            errors: ["outside_scan_roots: /outside"]
        )
        let decoded = try roundTrip(manifest)
        #expect(decoded == manifest)
        #expect(decoded.items.count == 2)
        #expect(decoded.status == .partiallyFailed)
        #expect(decoded.errors == ["outside_scan_roots: /outside"])

        let data = try JSONEncoder().encode(manifest)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"operation_id\""))
        #expect(json.contains("\"created_at\""))
        #expect(json.contains("\"approved_by_user\""))
        #expect(json.contains("\"user_request\""))
        #expect(!json.contains("\"operationId\""))
    }

    @Test("StorageManifest decodes with defaults when fields missing")
    func manifestMissingDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let m = try JSONDecoder().decode(StorageManifest.self, from: json)
        #expect(m.operationId == "")
        #expect(m.surface == .run)
        #expect(m.status == .planned)
        #expect(m.items == [])
        #expect(m.errors == [])
        #expect(m.completedAt == nil)
        #expect(m.undoneAt == nil)
        #expect(m.undoResults == nil)
    }

    @Test("StorageManifest with undo results round-trips")
    func manifestWithUndoRoundTrip() throws {
        var manifest = StorageManifest(
            operationId: "op-2",
            createdAt: "2026-06-11T00:00:00Z",
            surface: .chat,
            items: [StorageManifestItem(action: .move, sourcePath: "/a", targetPath: "/b", outcome: .succeeded)],
            status: .completed,
            errors: []
        )
        manifest.undoneAt = "2026-06-11T01:00:00Z"
        manifest.undoResults = [StorageUndoResult(sourcePath: "/a", action: .move, outcome: .restored)]
        let decoded = try roundTrip(manifest)
        #expect(decoded == manifest)
        #expect(decoded.undoResults?.first?.outcome == .restored)
        #expect(decoded.undoneAt == "2026-06-11T01:00:00Z")
    }
}
