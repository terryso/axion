import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

@Suite("RunLockService")
struct RunLockServiceTests {

    // MARK: - Helpers

    let tempDir: String

    init() {
        tempDir = NSTemporaryDirectory() + "axion-test-runlock-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
    }

    private func makeService(
        processAlive: @escaping @Sendable (pid_t) -> Bool = { _ in false }
    ) -> RunLockService {
        RunLockService(
            lockDirectory: tempDir,
            processAliveChecker: processAlive
        )
    }

    private var lockFilePath: String {
        (tempDir as NSString).appendingPathComponent("run.lock")
    }

    private func writeLockFile(runId: String, pid: Int32, startedAt: String = "2026-05-17T10:00:00Z") throws {
        let json = """
        {"run_id":"\(runId)","pid":\(pid),"started_at":"\(startedAt)"}
        """
        try json.write(toFile: lockFilePath, atomically: true, encoding: .utf8)
    }

    // MARK: - AC1: First acquire succeeds

    @Test("First acquire succeeds and writes lock file")
    func firstAcquireSucceeds() async throws {
        let service = makeService()
        let result = await service.acquire(runId: "20260517-abc123")
        #expect(result == true)

        let data = try Data(contentsOf: URL(fileURLWithPath: lockFilePath))
        let lock = try JSONDecoder().decode(RunLockData.self, from: data)
        #expect(lock.runId == "20260517-abc123")
        #expect(lock.pid == ProcessInfo.processInfo.processIdentifier)
    }

    // MARK: - AC2: Concurrent live run rejected

    @Test("Acquire rejects when lock exists and process alive")
    func acquireRejectsWhenLockExistsAndProcessAlive() async throws {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        try writeLockFile(runId: "20260517-existing", pid: currentPid)

        let service = makeService(processAlive: { _ in true })
        let result = await service.acquire(runId: "20260517-new")
        #expect(result == false)
    }

    // MARK: - AC3: Stale lock auto cleanup

    @Test("Stale lock (process gone) is cleaned and acquire succeeds")
    func staleLockCleanedAndAcquireSucceeds() async throws {
        try writeLockFile(runId: "20260517-stale", pid: 99999)

        let service = makeService(processAlive: { pid in
            return false
        })

        let result = await service.acquire(runId: "20260517-new")
        #expect(result == true)

        let data = try Data(contentsOf: URL(fileURLWithPath: lockFilePath))
        let lock = try JSONDecoder().decode(RunLockData.self, from: data)
        #expect(lock.runId == "20260517-new")
    }

    // MARK: - AC4: Release deletes lock file

    @Test("Release deletes lock file")
    func releaseDeletesLockFile() async throws {
        try writeLockFile(runId: "20260517-test", pid: 12345)

        let service = makeService()
        await service.release()

        #expect(!FileManager.default.fileExists(atPath: lockFilePath))
    }

    @Test("Release does not error when lock file missing")
    func releaseNoErrorWhenMissing() async {
        let service = makeService()
        await service.release()
        // Should not throw or crash
    }

    // MARK: - Corrupted lock file treated as stale

    @Test("Corrupted lock file treated as stale and cleaned")
    func corruptedLockTreatedAsStale() async throws {
        try "not valid json".write(toFile: lockFilePath, atomically: true, encoding: .utf8)

        let service = makeService()
        let result = await service.acquire(runId: "20260517-new")
        #expect(result == true)

        let data = try Data(contentsOf: URL(fileURLWithPath: lockFilePath))
        let lock = try JSONDecoder().decode(RunLockData.self, from: data)
        #expect(lock.runId == "20260517-new")
    }

    // MARK: - RunLockData model

    @Test("RunLockData Codable roundtrip")
    func runLockDataCodableRoundtrip() throws {
        let original = RunLockData(runId: "20260517-test", pid: 12345, startedAt: "2026-05-17T10:00:00Z")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RunLockData.self, from: data)
        #expect(decoded.runId == original.runId)
        #expect(decoded.pid == original.pid)
        #expect(decoded.startedAt == original.startedAt)
    }

    // MARK: - readExistingLock

    @Test("readExistingLock returns nil when no lock file")
    func readExistingLockReturnsNilWhenNoFile() async {
        let service = makeService()
        let lock = await service.readExistingLock()
        #expect(lock == nil)
    }

    @Test("readExistingLock returns data for valid lock")
    func readExistingLockReturnsDataForValidLock() async throws {
        try writeLockFile(runId: "20260517-existing", pid: 12345)

        let service = makeService()
        let lock = await service.readExistingLock()
        #expect(lock != nil)
        #expect(lock?.runId == "20260517-existing")
        #expect(lock?.pid == 12345)
    }

    // MARK: - AxionError.runLocked

    @Test("AxionError.runLocked error payload")
    func axionErrorRunLockedPayload() {
        let error = AxionError.runLocked(runId: "20260517-abc", pid: 12345)
        let payload = error.errorPayload
        #expect(payload.error == "run_locked")
        #expect(payload.message.contains("20260517-abc"))
        #expect(payload.message.contains("12345"))
    }
}
