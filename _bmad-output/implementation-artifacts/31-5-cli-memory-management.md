---
baseline_commit: 6ea7536f8723f0d7aee20e6e316bbac676c81327
---

# Story 31.5: CLI 命令扩展 — 记忆管理

Status: done

## Story

As a Axion 用户,
I want 通过 CLI 查看和编辑通用记忆,
So that 我可以审查和纠正 Axion 对我的理解.

## Acceptance Criteria

1. **Given** 用户执行 `axion memory list`
   **When** 命令运行
   **Then** 显示三类记忆：App 操作 facts（现有）、MEMORY.md 条目数、USER.md 条目数
   **And** 每类显示最后更新时间

2. **Given** 用户执行 `axion memory show memory`
   **When** 命令运行
   **Then** 输出 MEMORY.md 的完整内容

3. **Given** 用户执行 `axion memory show user`
   **When** 命令运行
   **Then** 输出 USER.md 的完整内容

4. **Given** 用户执行 `axion memory clear --type user`
   **When** 命令运行
   **Then** 清空 USER.md（保留空文件）

5. **Given** 用户执行 `axion memory clear --type memory`
   **When** 命令运行
   **Then** 清空 MEMORY.md（保留空文件）

6. **Given** 用户执行 `axion memory clear --app com.apple.calculator`
   **When** 命令运行
   **Then** 行为不变（现有 App facts 清除逻辑）

## Tasks / Subtasks

- [x] Task 1: Add `entryCount` and `lastModifiedDate` to UniversalMemoryStore (AC: #1)
  - [x] 1.1 Add `entryCount(target:) -> Int` public method that calls `parseEntries` and returns count
  - [x] 1.2 Add `lastModifiedDate(target:) -> Date?` public method using FileManager.attributesOfItem
  - [x] 1.3 Extract `parseEntries` from private to internal (or add a public `parseEntries(from:) -> [String]` wrapper)

- [x] Task 2: Create `MemoryShowCommand` (AC: #2, #3)
  - [x] 2.1 Create `Sources/AxionCLI/Commands/MemoryShowCommand.swift`
  - [x] 2.2 Accept positional argument `target`: "memory" or "user"
  - [x] 2.3 Use `UniversalMemoryStore.read(target:)` to read file content
  - [x] 2.4 Print raw content (or "No content" if empty)
  - [x] 2.5 Handle invalid target values with error message

- [x] Task 3: Extend `MemoryClearCommand` with `--type` option (AC: #4, #5, #6)
  - [x] 3.1 Add `@Option(name: .long, help: "要清空的通用记忆类型：memory 或 user") var type: String?` to existing `MemoryClearCommand`
  - [x] 3.2 Make both `--app` and `--type` optional but require exactly one (mutual exclusion validation in `run()`)
  - [x] 3.3 When `--type memory` is provided: use `UniversalMemoryStore.write(target: .memory, content: "")` to clear
  - [x] 3.4 When `--type user` is provided: use `UniversalMemoryStore.write(target: .user, content: "")` to clear
  - [x] 3.5 When `--app` is provided: existing behavior unchanged

- [x] Task 4: Extend `MemoryListCommand` to show universal memory summary (AC: #1)
  - [x] 4.1 After existing App Memory listing, add "Universal Memory:" section
  - [x] 4.2 Show MEMORY.md entry count and last modified date
  - [x] 4.3 Show USER.md entry count and last modified date
  - [x] 4.4 Use `UniversalMemoryStore` (init with same `resolveMemoryDir()` path) to read data

- [x] Task 5: Register `MemoryShowCommand` in `MemoryCommand` (AC: #2, #3)
  - [x] 5.1 Add `MemoryShowCommand.self` to `MemoryCommand.subcommands` array

- [x] Task 6: Write unit tests (all ACs)
  - [x] 6.1 Test `UniversalMemoryStore.entryCount()` returns correct count for populated and empty files
  - [x] 6.2 Test `UniversalMemoryStore.lastModifiedDate()` returns date for existing files
  - [x] 6.3 Test `MemoryShowCommand` output for "memory" target with content
  - [x] 6.4 Test `MemoryShowCommand` output for "user" target with content
  - [x] 6.5 Test `MemoryShowCommand` output for empty file shows "No content" message
  - [x] 6.6 Test `MemoryClearCommand --type memory` clears MEMORY.md
  - [x] 6.7 Test `MemoryClearCommand --type user` clears USER.md
  - [x] 6.8 Test `MemoryClearCommand --app` still works unchanged
  - [x] 6.9 Test `MemoryListCommand` output includes universal memory section with entry counts
  - [x] 6.10 Test mutual exclusion: providing both `--app` and `--type` is rejected

## Dev Notes

### What Already Exists

| Component | Status | File |
|-----------|--------|------|
| `MemoryCommand` | Done — parent group with 5 subcommands | `Sources/AxionCLI/Commands/MemoryCommand.swift` |
| `MemoryListCommand` | Done — lists App facts only (no universal memory) | `Sources/AxionCLI/Commands/MemoryListCommand.swift` |
| `MemoryClearCommand` | Done — clears App facts by `--app <domain>` only | `Sources/AxionCLI/Commands/MemoryClearCommand.swift` |
| `MemoryExportCommand` | Done — exports App facts | `Sources/AxionCLI/Commands/MemoryExportCommand.swift` |
| `MemoryImportCommand` | Done — imports App facts | `Sources/AxionCLI/Commands/MemoryImportCommand.swift` |
| `MemoryLearnTakeoverCommand` | Done — learns from takeover | `Sources/AxionCLI/Commands/MemoryLearnTakeoverCommand.swift` |
| `UniversalMemoryStore` | Done — full CRUD + char limits | `Sources/AxionCLI/Memory/UniversalMemoryStore.swift` |
| `MemorySecurityScanner` | Done — write-time + load-time scanning | `Sources/AxionCLI/Memory/MemorySecurityScanner.swift` |
| `MemoryContextProvider` | Done — builds universal memory context for prompt | `Sources/AxionCLI/Memory/MemoryContextProvider.swift` |

**The gap:** CLI has no way to view or clear the new universal memory files (MEMORY.md / USER.md). `MemoryListCommand` only shows App facts. `MemoryClearCommand` only accepts `--app`. There is no `MemoryShowCommand`.

### Architecture

**New files:**
- `Sources/AxionCLI/Commands/MemoryShowCommand.swift` — `axion memory show <memory|user>`

**Modified files:**
- `Sources/AxionCLI/Memory/UniversalMemoryStore.swift` — add `entryCount(target:)` and `lastModifiedDate(target:)` public methods; expose `parseEntries` internally
- `Sources/AxionCLI/Commands/MemoryCommand.swift` — add `MemoryShowCommand.self` to subcommands
- `Sources/AxionCLI/Commands/MemoryClearCommand.swift` — add `--type` option, mutual exclusion with `--app`
- `Sources/AxionCLI/Commands/MemoryListCommand.swift` — append universal memory section after App facts listing

**Files that must NOT change:**
- `MemoryTool.swift` — agent-facing tool, fully functional
- `ReviewSaveUniversalMemoryTool.swift` — review tool, fully functional
- `MemorySecurityScanner.swift` — scanning is not needed for CLI read/clear operations (CLI is user-initiated, trusted)
- `MemoryContextProvider.swift` — prompt injection is separate from CLI display
- `AgentBuilder.swift` — no changes needed

### MemoryShowCommand Design

```swift
struct MemoryShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "显示通用记忆内容"
    )

    @Argument(help: "记忆类型：memory 或 user")
    var target: String

    func run() async throws {
        guard let memTarget = MemoryTarget(rawValue: target == "memory" ? "MEMORY.md" : target == "user" ? "USER.md" : "invalid") else {
            throw ValidationError("无效的目标：'\(target)'。请使用 'memory' 或 'user'")
        }
        let memoryDir = resolveMemoryDir()
        let store = UniversalMemoryStore(memoryDir: memoryDir)
        let content = await store.read(target: memTarget)
        if content.isEmpty {
            print("No content in \(target).")
        } else {
            print(content)
        }
    }
}
```

Note: `MemoryTarget` enum has raw values `"MEMORY.md"` and `"USER.md"`. The CLI arg maps `"memory"` → `.memory` / `"user"` → `.user`.

### MemoryClearCommand Extension

Add `--type` as an alternative to `--app`. Both become optional; validation in `run()` ensures exactly one is provided:

```swift
@Option(name: .long, help: "要清空的通用记忆类型：memory 或 user")
var type: String?

// In run():
guard (app == nil) != (type == nil) else {
    throw ValidationError("必须且只能指定 --app 或 --type 之一")
}
if let type = type {
    // Handle universal memory clear
    guard let target = parseTypeArgument(type) else {
        throw ValidationError("无效的 type：'\(type)'。请使用 'memory' 或 'user'")
    }
    let store = UniversalMemoryStore(memoryDir: resolveMemoryDir())
    await store.write(target: target, content: "")
    print("已清空 \(type) 记忆")
} else {
    // Existing --app logic unchanged
}
```

### MemoryListCommand Extension

After the existing App Memory listing, add a universal memory section:

```
Universal Memory:
  MEMORY.md — 3 entries (last updated: 2026-05-31 14:30)
  USER.md — 1 entry (last updated: 2026-05-30 09:15)
```

Use `UniversalMemoryStore.entryCount(target:)` and `lastModifiedDate(target:)` for this display.

### UniversalMemoryStore Additions

```swift
/// Number of §-delimited entries in the target file.
func entryCount(target: MemoryTarget) -> Int {
    let content = read(target: target)
    return parseEntries(from: content).count
}

/// Last modification date of the target file, or nil if not found.
func lastModifiedDate(target: MemoryTarget) -> Date? {
    let url = fileURL(for: target)
    guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
          let date = attrs[.modificationDate] as? Date else {
        return nil
    }
    return date
}
```

### Testing Strategy

- **Swift Testing framework** (`import Testing`, `@Suite`, `@Test`, `#expect`)
- **Mock-free**: Use real `UniversalMemoryStore` with temp directories
- **New test file**: `Tests/AxionCLITests/Commands/MemoryShowCommandTests.swift`
- **Extend existing tests**:
  - `MemoryClearCommandTests.swift` — add `--type` tests
  - `MemoryListCommandTests.swift` — add universal memory section tests
  - `UniversalMemoryStoreTests.swift` — add `entryCount`/`lastModifiedDate` tests (if not already covered)
- **Run tests**: `swift test --filter "AxionCLITests.Commands.Memory"`

### References

- [Source: docs/epics/epic-31-universal-memory.md — Story 31.5 definition, CLI command specs]
- [Source: Sources/AxionCLI/Memory/UniversalMemoryStore.swift — read/write/add/remove/replace, parseEntries]
- [Source: Sources/AxionCLI/Commands/MemoryCommand.swift — parent command with subcommand list]
- [Source: Sources/AxionCLI/Commands/MemoryListCommand.swift — existing list implementation (App facts only)]
- [Source: Sources/AxionCLI/Commands/MemoryClearCommand.swift — existing clear with --app only]
- [Source: Tests/AxionCLITests/Commands/MemoryListCommandTests.swift — existing list tests pattern]
- [Source: Tests/AxionCLITests/Commands/MemoryClearCommandTests.swift — existing clear tests pattern]

### Previous Story Learnings (31.4)

- **Multiple UniversalMemoryStore instances are safe**: Each actor serializes I/O; use fresh instance per temp dir in tests
- **Security scan integration**: CLI commands are user-initiated and don't need security scanning — scanner is for agent/review writes
- **Temp directory pattern for tests**: `"/tmp/axion-test-memory-\(UUID().uuidString)"` + `defer { try? FileManager.default.removeItem(atPath: tempDir) }`
- **ArgumentParser ValidationError**: Use `throw ValidationError("message")` for invalid CLI arguments — ArgumentParser handles formatting
- **Static API pattern for testability**: Existing commands expose `static func` methods that accept `memoryDir` parameter, keeping `run()` as a thin wrapper. Follow this pattern.

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

None.

### Completion Notes List

- Added `entryCount(target:)`, `lastModifiedDate(target:)`, and public `parseEntries(from:)` to UniversalMemoryStore
- Created `MemoryShowCommand` with `show <memory|user>` subcommand showing file content or "No content" message
- Extended `MemoryClearCommand` with `--type <memory|user>` option alongside existing `--app`, with mutual exclusion validation
- Extended `MemoryListCommand` to append a "Universal Memory:" section showing entry counts and last modified dates
- Registered `MemoryShowCommand` in `MemoryCommand.subcommands`
- All 18 new tests pass; full test suite (1696 tests) passes with no regressions

### File List

**New files:**
- `Sources/AxionCLI/Commands/MemoryShowCommand.swift`
- `Tests/AxionCLITests/Commands/MemoryShowCommandTests.swift`

**Modified files:**
- `Sources/AxionCLI/Memory/UniversalMemoryStore.swift`
- `Sources/AxionCLI/Commands/MemoryCommand.swift`
- `Sources/AxionCLI/Commands/MemoryClearCommand.swift`
- `Sources/AxionCLI/Commands/MemoryListCommand.swift`
- `Tests/AxionCLITests/Memory/UniversalMemoryStoreTests.swift`
- `Tests/AxionCLITests/Commands/MemoryClearCommandTests.swift`
- `Tests/AxionCLITests/Commands/MemoryListCommandTests.swift`

## Change Log

- 2026-05-31: Story 31.5 complete — added CLI commands for universal memory management (`axion memory show`, `axion memory clear --type`, `axion memory list` universal section)
- 2026-05-31: Senior Developer Review (AI) — 2 HIGH, 3 MEDIUM, 1 LOW issues found and auto-fixed:
  - **H1/M3**: Added `summary(target:)` method to coalesce entry count + last modified into single actor hop
  - **H2**: Added `init(readOnlyMemoryDir:)` to prevent `memory list` from creating files as side effect; `MemoryListCommand` now uses read-only init
  - **M1/M2**: Unified all CLI error messages and output to English (was mixed Chinese/English)
  - **L1**: Noted duplicate parseTarget/parseTypeArgument — acceptable for now
  - Added 3 new tests: `summaryReturnsCountAndDate`, `summaryMissingFile`, `readOnlyInitNoSideEffects`
