import Foundation

import AxionCore

/// Lock file data stored at `~/.axion/run.lock`.
struct RunLockData: Codable, Sendable {
    let runId: String
    let pid: Int32
    let startedAt: String

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case pid
        case startedAt = "started_at"
    }
}

/// Manages a desktop-level run lock to ensure only one live run controls the desktop at a time.
///
/// Lock file path: `~/.axion/run.lock` (JSON format).
/// Uses actor isolation for atomic acquire/release operations.
actor RunLockService {

    // MARK: - Properties

    private let lockDirectory: String
    private let processAliveChecker: @Sendable (pid_t) -> Bool
    private let fileManager = FileManager.default

    private var lockFilePath: String {
        (lockDirectory as NSString).appendingPathComponent("run.lock")
    }

    // MARK: - Initialization

    init(
        lockDirectory: String? = nil,
        processAliveChecker: (@Sendable (pid_t) -> Bool)? = nil
    ) {
        let dir = lockDirectory
            ?? ConfigManager.defaultConfigDirectory
        self.lockDirectory = dir
        self.processAliveChecker = processAliveChecker ?? Self.defaultProcessAliveChecker
    }

    /// Default process alive check using `kill(pid, 0)`.
    /// Returns `true` if the process exists, `false` otherwise (ESRCH).
    private static func defaultProcessAliveChecker(pid: pid_t) -> Bool {
        let result = Darwin.kill(pid, 0)
        return result == 0
    }

    // MARK: - Acquire

    /// Attempts to acquire the run lock for the given run.
    /// - Returns: `true` if lock acquired successfully, `false` if another live run holds the lock.
    func acquire(runId: String) -> Bool {
        let lockPath = lockFilePath

        // Check existing lock
        if fileManager.fileExists(atPath: lockPath) {
            if let existingLock = readExistingLockSync(at: lockPath) {
                // Check if the process holding the lock is still alive
                if processAliveChecker(existingLock.pid) {
                    return false // Active lock held by another process
                }
                // Stale lock — clean up
            }
            // Corrupted or stale lock file — remove it
            try? fileManager.removeItem(atPath: lockPath)
        }

        // Write new lock
        let lockData = RunLockData(
            runId: runId,
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: ISO8601DateFormatter().string(from: Date())
        )

        guard let data = try? JSONEncoder().encode(lockData) else {
            return false
        }

        do {
            try fileManager.createDirectory(
                atPath: lockDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            try data.write(to: URL(fileURLWithPath: lockPath), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Release

    /// Best-effort release of the run lock. Silently ignores failures.
    func release() {
        try? fileManager.removeItem(atPath: lockFilePath)
    }

    // MARK: - Read Existing Lock

    /// Reads and parses the existing lock file, if present.
    /// Returns `nil` if the file doesn't exist or is corrupted.
    func readExistingLock() -> RunLockData? {
        readExistingLockSync(at: lockFilePath)
    }

    private func readExistingLockSync(at path: String) -> RunLockData? {
        guard let data = fileManager.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(RunLockData.self, from: data)
    }
}
