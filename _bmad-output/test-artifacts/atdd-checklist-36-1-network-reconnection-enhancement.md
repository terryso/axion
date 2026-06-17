---
stepsCompleted:
  - step-01-preflight-and-context
  - step-02-generation-mode
  - step-03-test-strategy
  - step-04-generate-tests
  - step-04c-aggregate
  - step-05-validate-and-complete
lastStep: step-05-validate-and-complete
lastSaved: '2026-06-17'
workflowType: testarch-atdd
storyId: '36.1'
storyKey: '36-1-network-reconnection-enhancement'
storyFile: '_bmad-output/implementation-artifacts/36-1-network-reconnection-enhancement.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-36-1-network-reconnection-enhancement.md'
generatedTestFiles:
  - 'Tests/AxionCLITests/Services/Telegram/TGAPIClientTests.swift'
inputDocuments:
  - '_bmad-output/implementation-artifacts/36-1-network-reconnection-enhancement.md'
  - '_bmad-output/project-context.md'
  - 'Sources/AxionCLI/Services/Telegram/TGAPIClient.swift'
  - 'Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift'
---

# ATDD Checklist - Epic 36, Story 1: 网络重连增强

**Date:** 2026-06-17
**Author:** Nick
**Primary Test Level:** Unit (Swift Testing)
**TDD Phase:** RED

---

## Story Summary

增强 TG API 客户端的错误分类和重试逻辑，支持 429 Retry-After header、401/403 认证失败精确分类、409 Conflict 降级处理，以及 5xx 服务器错误重试。

**As a** Axion Gateway 运维者
**I want** TG 网络中断时自动恢复，而不是崩溃或停止响应
**So that** gateway 在不稳定网络环境下保持可用

---

## Acceptance Criteria

1. **AC #1:** Transient 错误自动重试（最多 3 次，指数退避：1s, 2s, 4s）
2. **AC #2:** 429 读取 Retry-After header，无则默认 5 秒
3. **AC #3:** 401/403 认证失败不重试，记录错误日志
4. **AC #4:** 409 Conflict 检测，graceful degrade（等 30s，连续 3 次停止）

---

## Story Integration Metadata

- **Story ID:** `36.1`
- **Story Key:** `36-1-network-reconnection-enhancement`
- **Story File:** `_bmad-output/implementation-artifacts/36-1-network-reconnection-enhancement.md`
- **Checklist Path:** `_bmad-output/test-artifacts/atdd-checklist-36-1-network-reconnection-enhancement.md`
- **Generated Test Files:** `Tests/AxionCLITests/Services/Telegram/TGAPIClientTests.swift`

---

## Red-Phase Test Scaffolds Created

### Unit Tests — 8 disabled tests + 10 commented scaffolds

**File:** `Tests/AxionCLITests/Services/Telegram/TGAPIClientTests.swift`

#### Active Disabled Tests (`.disabled()` — compile and skip)

| # | Test Name | AC | Status | Verifies |
|---|-----------|-----|--------|----------|
| 1 | `transientErrorRetriesWithExponentialBackoff` | #1 | RED - skipped | Network failure retries 3 times with exponential backoff |
| 2 | `genericNetworkErrorRetries` | #1 | RED - skipped | URLError (non-TGAPIError) retries with exponential backoff |
| 3 | `http5xxClassifiedAsRetryable` | #1 | RED - skipped | 503 classified as `.retryableNetwork`, retries 3 times |
| 4 | `http429WithRetryAfterHeader` | #2 | RED - skipped | 429 with `Retry-After: 10` header parsed correctly |
| 5 | `http429WithoutRetryAfterDefaultsTo5Seconds` | #2 | RED - skipped | 429 without Retry-After defaults to 5s wait |
| 6 | `http401NoRetry` | #3 | RED - skipped | 401 does not retry (permanent error) |
| 7 | `http403NoRetry` | #3 | RED - skipped | 403 does not retry (permanent error) |
| 8 | `http409NoExponentialRetry` | #4 | RED - skipped | 409 does not retry with exponential backoff |

#### Commented Scaffolds (reference not-yet-existing API — uncomment after implementation)

| # | Scaffold Name | AC | Verifies | Activation Requirement |
|---|---------------|-----|----------|----------------------|
| 1 | `authFailedErrorDescription` | #3 | `.authFailed` errorDescription | Add `.authFailed(String)` case |
| 2 | `pollingConflictErrorDescription` | #4 | `.pollingConflict` errorDescription | Add `.pollingConflict(String)` case |
| 3 | `rateLimitedCarriesRetryAfter` | #2 | `.rateLimited` with `retryAfter` associated value | Change `.rateLimited(String)` to `.rateLimited(String, retryAfter: TimeInterval)` |
| 4 | `apiErrorDescriptionNewCases` | #3/#4 | New error cases have localized descriptions | Add both new cases |
| 5 | `http401ClassifiedAsAuthFailed` | #3 | 401 → `.authFailed` classification | Update `classifyHTTPError` |
| 6 | `http403ClassifiedAsAuthFailed` | #3 | 403 → `.authFailed` classification | Update `classifyHTTPError` |
| 7 | `http409ClassifiedAsPollingConflict` | #4 | 409 → `.pollingConflict` classification | Update `classifyHTTPError` |
| 8 | `http429WithRetryAfterHeader` (full) | #2 | 429 with Retry-After parsed to exact value | Add `retryAfter` associated value |
| 9 | `http429WithoutRetryAfterDefaultsTo5Seconds` (full) | #2 | 429 without header defaults to 5s | Add `retryAfter` associated value |

---

## Mock Infrastructure Changes

### MockHTTPErrorURLSession Enhanced

**File:** `Tests/AxionCLITests/Services/Telegram/TGAPIClientTests.swift`

**Change:** Added `headers: [String: String]?` parameter to constructor, passed to `HTTPURLResponse` header fields.

```swift
// BEFORE:
init(statusCode: Int, body: String = "...") { ... }
let httpResp = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!

// AFTER:
init(statusCode: Int, body: String = "...", headers: [String: String]? = nil) { ... }
let httpResp = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
```

This enables testing `Retry-After` header parsing in 429 responses.

---

## Acceptance Criteria Coverage Matrix

| AC | Disabled Tests | Commented Scaffolds | Total Coverage |
|----|---------------|--------------------|----|
| #1 Transient retry + exponential backoff | 3 | 0 | ✅ Full |
| #2 429 Retry-After header | 2 | 3 | ✅ Full |
| #3 401/403 authFailed | 2 | 3 | ✅ Full |
| #4 409 pollingConflict | 1 | 2 | ✅ Full |
| 5xx retryable (bug fix) | 1 | 0 | ✅ Bonus |

---

## Test Execution Evidence

### Initial Scaffold Review

**Command:** `swift test --filter "TGAPIClientTests"`

**Results:**
- Total tests: 43
- Passed: 35 (existing tests)
- Skipped: 8 (new RED phase disabled tests)
- Failed: 0
- Status: ✅ Red-phase scaffolds verified — all existing tests pass, new tests skipped

---

## Implementation Checklist

### Task 1: Add `.authFailed` and `.pollingConflict` cases to `TGAPIError`

**File:** `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift`

**Tasks:**
- [ ] Add `case authFailed(String)` to `TGAPIError` enum
- [ ] Add `case pollingConflict(String)` to `TGAPIError` enum
- [ ] Update `errorDescription` computed property for new cases
- [ ] Change `.rateLimited(String)` to `.rateLimited(String, retryAfter: TimeInterval)`
- [ ] Update all pattern matching sites (search `.rateLimited`)

**Activate tests:**
- Uncomment scaffolds: `authFailedErrorDescription`, `pollingConflictErrorDescription`, `rateLimitedCarriesRetryAfter`, `apiErrorDescriptionNewCases`

---

### Task 2: Update `classifyHTTPError` for 401/403/409/5xx

**File:** `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift`

**Tasks:**
- [ ] Modify `classifyHTTPError` signature to accept `HTTPURLResponse` (for header access)
- [ ] Add 401/403 → `.authFailed` classification
- [ ] Add 409 → `.pollingConflict` classification
- [ ] Add 5xx → `.retryableNetwork` classification
- [ ] Parse `Retry-After` header for 429 → `.rateLimited(body, retryAfter: TimeInterval)`

**Activate tests:**
- Remove `.disabled()` from: `http5xxClassifiedAsRetryable`
- Uncomment scaffolds: `http401ClassifiedAsAuthFailed`, `http403ClassifiedAsAuthFailed`, `http409ClassifiedAsPollingConflict`, `http429WithRetryAfterHeader` (full), `http429WithoutRetryAfterDefaultsTo5Seconds` (full)

---

### Task 3: Update `performRequest` retry switch

**File:** `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift`

**Tasks:**
- [ ] Add `case .authFailed` → throw immediately (no retry)
- [ ] Add `case .pollingConflict` → throw immediately (no retry)
- [ ] Update `case .rateLimited(_, let retryAfter)` → sleep `retryAfter` seconds
- [ ] Remove `.disabled()` from: `http429WithRetryAfterHeader`, `http429WithoutRetryAfterDefaultsTo5Seconds`, `http401NoRetry`, `http403NoRetry`, `http409NoExponentialRetry`
- [ ] Remove `.disabled()` from: `transientErrorRetriesWithExponentialBackoff`, `genericNetworkErrorRetries`

---

### Task 4: Update `TelegramAdapter.pollLoop()` for conflict/auth handling

**File:** `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift`

**Tasks:**
- [ ] Add `consecutiveConflicts` counter
- [ ] Catch `.pollingConflict` → wait 30s, increment conflict counter
- [ ] 3 consecutive conflicts → stop polling (`isRunning = false`)
- [ ] Catch `.authFailed` → stop polling, log auth failure message
- [ ] Reset `consecutiveConflicts = 0` on successful poll

---

### Task 5: Update existing `http403Permanent` test

**File:** `Tests/AxionCLITests/Services/Telegram/TGAPIClientTests.swift`

**Tasks:**
- [ ] Update `http403Permanent` to expect `.authFailed` instead of `.permanentTelegramError`
- [ ] Or replace with `http403ClassifiedAsAuthFailed` scaffold

---

## Running Tests

```bash
# Run all TGAPIClient tests (includes disabled)
swift test --filter "TGAPIClientTests"

# Run only unit tests (no integration)
swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"

# Build test target only
swift build --build-tests
```

---

## Red-Green-Refactor Workflow

### RED Phase (Complete) ✅

- ✅ 8 disabled test scaffolds with `.disabled("RED PHASE: ...")`
- ✅ 10 commented scaffolds for not-yet-existing API
- ✅ MockHTTPErrorURLSession enhanced with header support
- ✅ All existing tests still pass (no regressions)
- ✅ Tests compile cleanly

### GREEN Phase (DEV Team — Next Steps)

1. **Implement Task 1** (add enum cases) → uncomment scaffolds 1-4
2. **Implement Task 2** (classifyHTTPError) → uncomment scaffolds 5-9, remove .disabled from test 3
3. **Implement Task 3** (performRequest) → remove .disabled from tests 1,2,4-8
4. **Implement Task 4** (pollLoop) → integration test (separate)
5. **Implement Task 5** (update existing 403 test) → modify http403Permanent
6. **Run all tests** → verify all pass

### REFACTOR Phase

- Review retry logic for clarity
- Ensure no `Task` vs `_Concurrency.Task` issues
- Verify all `.rateLimited` pattern matching sites updated

---

## Notes

- **Swift Testing `.disabled()` limitation:** Unlike JS `test.skip()`, Swift Testing's `.disabled()` prevents execution but NOT compilation. Tests referencing not-yet-existing API (`.authFailed`, `.pollingConflict`, `.rateLimited(_:retryAfter:)`) must be commented-out scaffolds until the types exist.
- **No new test files created:** All changes in existing `TGAPIClientTests.swift` per story anti-pattern rules.
- **MockHTTPErrorURLSession backward compatible:** New `headers` parameter has default `nil`, existing tests unaffected.
- **5xx retry classification is a bonus bug-fix:** Story Dev Note D4 notes 5xx should be retryable but currently returns `.permanentTelegramError`. Test `http5xxClassifiedAsRetryable` covers this.

---

**Generated by BMad TEA Agent** - 2026-06-17
