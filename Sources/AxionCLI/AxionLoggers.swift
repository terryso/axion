import os

// MARK: - Shared Loggers

/// Shared loggers for AxionCLI subsystem, avoiding repeated inline Logger creations.
private let axionSubsystem = "com.axion.cli"

let axionSkillUsageLogger = Logger(subsystem: axionSubsystem, category: "SkillUsage")
let axionReviewOrchestratorLogger = Logger(subsystem: axionSubsystem, category: "ReviewOrchestrator")
let axionIntelligentCuratorLogger = Logger(subsystem: axionSubsystem, category: "IntelligentCurator")
let axionCuratorSchedulerLogger = Logger(subsystem: axionSubsystem, category: "CuratorScheduler")
let axionReviewSchedulerLogger = Logger(subsystem: axionSubsystem, category: "ReviewScheduler")
let axionRunLockServiceLogger = Logger(subsystem: axionSubsystem, category: "RunLockService")
