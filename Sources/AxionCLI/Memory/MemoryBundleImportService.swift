import Foundation

/// Errors specific to Memory import/export operations.
enum MemoryBundleError: Error, Equatable, LocalizedError {
    case invalidBundle(reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidBundle(let reason):
            return "Invalid memory bundle: \(reason)"
        }
    }
}

/// Summary of an import operation.
struct ImportResult: Equatable {
    let domainsProcessed: Int
    let factsImported: Int
    let factsMerged: Int
    let errors: [String]
}

/// Imports a ``MemoryBundle`` JSON file, applying downgrade and merge logic.
struct MemoryBundleImportService {

    /// Import a bundle from disk, merging with existing facts in the store.
    func importBundle(from url: URL, store: MemoryFactStore) async throws -> ImportResult {
        // Read and decode
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MemoryBundleError.invalidBundle(reason: "file not found at \(url.path)")
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MemoryBundleError.invalidBundle(reason: "cannot read file — \(error.localizedDescription)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let bundle: MemoryBundle
        do {
            bundle = try decoder.decode(MemoryBundle.self, from: data)
        } catch {
            throw MemoryBundleError.invalidBundle(reason: "JSON decode failed — \(error.localizedDescription)")
        }

        guard bundle.schemaVersion == 1 else {
            throw MemoryBundleError.invalidBundle(reason: "unsupported schema_version \(bundle.schemaVersion), expected 1")
        }

        guard !bundle.memories.isEmpty else {
            return ImportResult(domainsProcessed: 0, factsImported: 0, factsMerged: 0, errors: [])
        }

        // Process each domain independently
        var domainsProcessed = 0
        var factsImported = 0
        var factsMerged = 0
        var errors: [String] = []

        for exportedDomain in bundle.memories {
            do {
                let (imported, merged) = try await importDomain(exportedDomain, store: store)
                domainsProcessed += 1
                factsImported += imported
                factsMerged += merged
            } catch {
                errors.append("Domain \(exportedDomain.domain): \(error.localizedDescription)")
                domainsProcessed += 1
            }
        }

        return ImportResult(
            domainsProcessed: domainsProcessed,
            factsImported: factsImported,
            factsMerged: factsMerged,
            errors: errors
        )
    }

    // MARK: - Domain Import

    /// Import a single domain's facts, applying downgrade and merge.
    private func importDomain(_ exported: ExportedDomain, store: MemoryFactStore) async throws -> (imported: Int, merged: Int) {
        let existing = (try? await store.query(domain: exported.domain)) ?? []
        var imported = 0
        var merged = 0

        for rawFact in exported.facts {
            var fact = AppMemoryFact.normalizeFact(rawFact)
            fact = downgradeImportedFact(fact)

            if let match = existing.first(where: { $0.id == fact.id }) {
                let mergedFact = mergeFacts(existing: match, imported: fact)
                try await store.save(domain: exported.domain, fact: mergedFact)
                merged += 1
            } else {
                try await store.save(domain: exported.domain, fact: fact)
                imported += 1
            }
        }

        return (imported, merged)
    }

    // MARK: - Downgrade

    /// Downgrade an imported fact so it enters as candidate with capped confidence.
    func downgradeImportedFact(_ fact: AppMemoryFact) -> AppMemoryFact {
        AppMemoryFact(
            id: fact.id,
            domain: fact.domain,
            kind: fact.kind,
            status: .candidate,
            confidence: min(fact.confidence, 0.55),
            evidenceCount: fact.evidenceCount,
            source: .imported,
            scope: fact.scope,
            cause: fact.cause,
            description: fact.description,
            updatedAt: fact.updatedAt,
            evidence: fact.evidence
        )
    }

    // MARK: - Merge

    /// Merge an imported fact with an existing one.
    func mergeFacts(existing: AppMemoryFact, imported: AppMemoryFact) -> AppMemoryFact {
        let resolvedSource: MemoryFactSource = existing.source == .local ? .local : imported.source

        // Evidence: deduplicate, keep most recent 5
        var allEvidence = existing.evidence
        let importedEvidence = imported.evidence.filter { !allEvidence.contains($0) }
        allEvidence.append(contentsOf: importedEvidence)

        return AppMemoryFact(
            id: existing.id,
            domain: existing.domain,
            kind: existing.kind,
            status: strongerStatus(existing.status, imported.status),
            confidence: max(existing.confidence, imported.confidence),
            evidenceCount: existing.evidenceCount + 1,
            source: resolvedSource,
            scope: existing.scope,
            cause: existing.cause,
            description: existing.description,
            updatedAt: Date(),
            evidence: Array(allEvidence.suffix(5))
        )
    }

    /// Compare two statuses — active > candidate > retired.
    func strongerStatus(_ a: MemoryFactStatus, _ b: MemoryFactStatus) -> MemoryFactStatus {
        let order: [MemoryFactStatus] = [.active, .candidate, .retired]
        let idxA = order.firstIndex(of: a) ?? order.count
        let idxB = order.firstIndex(of: b) ?? order.count
        return idxA <= idxB ? a : b
    }
}
