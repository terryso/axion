---
baseline_commit: 29e58cf4942485d24ca82ae07b929a410d135a13
---

# Story 36.1: 网络重连增强

Status: done

## Story

As a Axion Gateway 运维者,
I want TG 网络中断时自动恢复，而不是崩溃或停止响应,
so that gateway 在不稳定网络环境下保持可用。

## Acceptance Criteria

1. **Given** TG API 请求超时或连接被重置
   **When** `TGAPIClient` 检测到 transient 错误
   **Then** 自动重试（最多 3 次，指数退避：1s, 2s, 4s）
   **And** 重试成功后无缝继续，用户无感知

2. **Given** TG API 返回 429 Too Many Requests
   **When** `TGAPIClient` 检测到限流
   **Then** 读取 `Retry-After` header
   **And** 等待指定时间后重试
   **And** 无 `Retry-After` 则默认等待 5 秒

3. **Given** TG API 返回 401/403（认证失败）
   **When** `TGAPIClient` 检测到 permanent 错误
   **Then** 不重试，记录错误日志
   **And** 通知用户 "TG Bot 认证失败，请检查 token 配置"

4. **Given** 多个 gateway 实例同时轮询同一 bot
   **When** TG API 返回 409 Conflict
   **Then** 检测到 polling conflict
   **And** graceful degrade：停止当前轮询，等待 30 秒后重试
   **And** 连续 3 次 conflict 后停止轮询并通知用户

## Tasks / Subtasks

- [x] Task 1: 增强 `TGAPIError` 错误分类 (AC: #1, #2, #3, #4)
  - [x] 1.1 新增 `.authFailed(String)` case — 401/403 permanent 错误，不重试
  - [x] 1.2 新增 `.pollingConflict(String)` case — 409 Conflict，需要特殊降级
  - [x] 1.3 更新 `classifyHTTPError(statusCode:body:)` 识别 401/403 → `.authFailed`，409 → `.pollingConflict`
  - [x] 1.4 在 `performRequest` retry switch 中处理新 case：`.authFailed` 和 `.pollingConflict` 不走指数退避重试

- [x] Task 2: 429 Retry-After header 解析 (AC: #2)
  - [x] 2.1 修改 `performRequest` 方法签名：需要从 `HTTPURLResponse` 提取 header 信息，将 `classifyHTTPError` 扩展为 `classifyHTTPError(statusCode:body:headers:)` 或在 `performRequest` 内联解析
  - [x] 2.2 解析 `Retry-After` header（秒数，如 `"30"`），存入 `TGAPIError.rateLimited` 关联值或新增关联值
  - [x] 2.3 无 `Retry-After` 时使用默认 5 秒等待
  - [x] 2.4 在 retry 逻辑中用解析到的等待时间替代固定 1 秒

- [x] Task 3: 指数退避修正 (AC: #1)
  - [x] 3.1 当前 `retryableNetwork` 的退避为 `pow(2.0, Double(attempt))`（即 1s, 2s, 4s）—验证 attempt=0 时为 1s，符合 AC 要求
  - [x] 3.2 当前 `.rateLimited` 退避为固定 1s —需改为 AC #2 的 Retry-After 逻辑
  - [x] 3.3 确保通用 catch 分支（非 `TGAPIError` 的网络错误如 `URLError`）也走指数退避

- [x] Task 4: 409 Conflict 降级逻辑 — TelegramAdapter (AC: #4)
  - [x] 4.1 在 `pollLoop()` 中捕获 `TGAPIError.pollingConflict`
  - [x] 4.2 维护 `consecutiveConflicts` 计数器（独立于现有 `consecutiveErrors`）
  - [x] 4.3 检测到 conflict → 等待 30 秒后重试
  - [x] 4.4 连续 3 次 conflict → 停止轮询 (`isRunning = false`)，通过 `log()` 通知用户
  - [x] 4.5 成功轮询后重置 `consecutiveConflicts = 0`

- [x] Task 5: 401/403 认证失败用户通知 — TelegramAdapter (AC: #3)
  - [x] 5.1 在 `pollLoop()` 中捕获 `TGAPIError.authFailed`
  - [x] 5.2 通过 `log()` 输出 "TG Bot 认证失败，请检查 token 配置"
  - [x] 5.3 停止轮询 (`isRunning = false`)，设置 `statusValue = "auth_failed"`
  - [x] 5.4 注意：不能通过 TG 发消息通知（因为认证已经失败），只能通过 `log()` 到 stderr

- [x] Task 6: 更新和新增测试 (AC: all)
  - [x] 6.1 更新 `classifyHTTPError` 测试：验证 401 → `.authFailed`，403 → `.authFailed`，409 → `.pollingConflict`
  - [x] 6.2 新增测试：429 带 `Retry-After` header 时等待正确时间后重试
  - [x] 6.3 新增测试：429 无 `Retry-After` 时默认等待 5 秒
  - [x] 6.4 新增测试：401/403 不重试，立即抛出
  - [x] 6.5 新增测试：409 触发 `.pollingConflict` 不走指数退避
  - [x] 6.6 更新 `TGAPIError` 测试：新增 `.authFailed` 和 `.pollingConflict` 的 `errorDescription` 验证

## Dev Notes

### Architecture Context

本 story 增强 `TGAPIClient` 的错误分类和重试逻辑，并在 `TelegramAdapter.pollLoop()` 中添加 conflict 降级和认证失败处理。当前代码已有基础重试框架（`performRequest` + `classifyHTTPError` + `TGAPIError` 枚举），但缺少 409 Conflict 检测、429 Retry-After header 解析、401/403 精确分类。

**核心变更范围：** 两个现有文件（`TGAPIClient.swift` + `TelegramAdapter.swift`），一个测试文件。无新文件。

### Files Being Modified (UPDATE)

| File | Current State | What Changes |
|------|---------------|--------------|
| `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift` (252 lines) | `TGAPIError` 有 4 case（`retryableNetwork`, `rateLimited`, `formatRejected`, `permanentTelegramError`）；`performRequest` 已有 retry 框架；`classifyHTTPError` 处理 429/400/default | 新增 `.authFailed(String)` 和 `.pollingConflict(String)` case；增强 `classifyHTTPError` 识别 401/403/409；修改 `performRequest` 解析 `Retry-After` header；调整 retry switch 处理新 case |
| `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` (284 lines) | `pollLoop()` 有 `consecutiveErrors` 计数器和退避逻辑（`min(5 * errors, 30)` 秒）；所有错误统一走 catch 分支 | 新增 `consecutiveConflicts` 计数器；捕获 `.pollingConflict` → 等 30s 重试，连续 3 次停止；捕获 `.authFailed` → 立即停止轮询 + log 通知 |
| `Tests/AxionCLITests/Services/Telegram/TGAPIClientTests.swift` (823 lines) | 已有 `MockHTTPErrorURLSession`、`MockScriptedURLSession`、`MockFailingURLSession`；已有 429/400/403 测试 | 更新 403 测试期望（`.authFailed` 而非 `.permanentTelegramError`）；新增 401/409/Retry-After 测试；扩展 `MockHTTPErrorURLSession` 支持 header 注入 |

### Files Being Created (NEW)

无。所有变更在现有文件中完成。

### Current `performRequest` Retry Logic (must preserve)

```
performRequest(request, retries: Int):
  for attempt in 0..<retries:
    try session.data(for: request)
    → HTTP error? → classifyHTTPError → throw TGAPIError
    catch TGAPIError.rateLimited → sleep 1s (FIX: use Retry-After), retry
    catch TGAPIError.retryableNetwork → sleep pow(2,attempt)s, retry
    catch TGAPIError.formatRejected → throw immediately
    catch TGAPIError.permanentTelegramError → throw immediately
    catch generic Error → sleep pow(2,attempt)s, retry
  throw lastError
```

**关键：** `classifyHTTPError` 目前对 4xx 统一返回 `.permanentTelegramError`（除 429 和 400 parse error）。401/403 不会被重试（因为 `.permanentTelegramError` 立即抛出），但错误分类不够精确，无法在 `pollLoop` 中区分"认证失败"和"其他永久错误"。

### Required Changes to `performRequest`

当前 `performRequest` 的 HTTP error 处理只传了 `statusCode` 和 `body`：
```swift
if let http = httpResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
    let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
    throw classifyHTTPError(statusCode: http.statusCode, body: body)
}
```

**必须修改为**同时传入 `httpResponse`（或其 `value(forHTTPHeaderField:)` 结果），以便解析 `Retry-After` header。推荐方式：

```swift
// 修改 classifyHTTPError 签名或新增重载
private func classifyHTTPError(statusCode: Int, body: String, httpResponse: HTTPURLResponse) -> TGAPIError {
    switch statusCode {
    case 429:
        let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 5
        return .rateLimited(body, retryAfter: TimeInterval(retryAfter))  // 新增关联值
    case 401, 403:
        return .authFailed(body)
    case 409:
        return .pollingConflict(body)
    case 400:
        if body.contains("can't parse entities") || body.contains("Bad Request") {
            return .formatRejected(body)
        }
        return .permanentTelegramError(body)
    default:
        // 5xx → retryableNetwork (server error, worth retrying)
        if (500...599).contains(statusCode) {
            return .retryableNetwork("HTTP \(statusCode): \(body)")
        }
        return .permanentTelegramError(body)
    }
}
```

### Required Changes to `TGAPIError`

```swift
enum TGAPIError: Error, LocalizedError {
    case retryableNetwork(String)
    case rateLimited(String, retryAfter: TimeInterval)  // 新增 retryAfter 关联值
    case formatRejected(String)
    case authFailed(String)                              // 新增 case (401/403)
    case pollingConflict(String)                         // 新增 case (409)
    case permanentTelegramError(String)

    var errorDescription: String? { ... }
}
```

**Breaking change 注意：** `.rateLimited` 新增关联值会影响现有代码中的 `case .rateLimited:` pattern matching。需要同步更新：
- `performRequest` 中的 `case .rateLimited:` → `case .rateLimited(_, let retryAfter):`
- `TelegramAdapter.editMessage` 中的 `case .rateLimited` → `case .rateLimited:`
- 测试文件中的 `if case .rateLimited = error` → 保持或更新

### Required Changes to `pollLoop`

```swift
private func pollLoop() async {
    var consecutiveErrors = 0
    var consecutiveConflicts = 0          // 新增
    while isRunning {
        do {
            let updates = try await apiClient.getUpdates(offset: lastUpdateId + 1, timeout: 30)
            statusValue = "connected"
            consecutiveErrors = 0
            consecutiveConflicts = 0      // 新增：成功时重置
            await processUpdates(updates)
        } catch let error as TGAPIError {
            switch error {
            case .pollingConflict:
                consecutiveConflicts += 1
                if consecutiveConflicts >= 3 {
                    statusValue = "conflict_stopped"
                    log("[axion] Telegram polling stopped: 3 consecutive 409 conflicts (another instance may be running)")
                    isRunning = false
                    break
                }
                statusValue = "conflict:\(consecutiveConflicts)"
                log("[axion] Telegram 409 conflict, waiting 30s before retry (\(consecutiveConflicts)/3)")
                try? await _Concurrency.Task.sleep(nanoseconds: 30_000_000_000)
            case .authFailed:
                statusValue = "auth_failed"
                log("[axion] TG Bot 认证失败，请检查 token 配置 (AXION_TELEGRAM_BOT_TOKEN)")
                isRunning = false
            default:
                // 既有逻辑
                statusValue = "error:\(error.localizedDescription)"
                log("[axion] Telegram getUpdates failed: \(error.localizedDescription)")
                consecutiveErrors += 1
                let delay = min(5.0 * Double(consecutiveErrors), 30.0)
                try? await _Concurrency.Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        } catch {
            // 既有逻辑（非 TGAPIError 的通用错误）
            statusValue = "error:\(error.localizedDescription)"
            log("[axion] Telegram getUpdates failed: \(error.localizedDescription)")
            consecutiveErrors += 1
            let delay = min(5.0 * Double(consecutiveErrors), 30.0)
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}
```

### Key Design Decisions

1. **`.rateLimited` 关联值携带 `retryAfter`。** 当前 `.rateLimited(String)` 只存储 body 文本。改为 `.rateLimited(String, retryAfter: TimeInterval)` 让 retry 逻辑直接知道等待时间，无需在 retry switch 中再解析。

2. **401/403 统一为 `.authFailed`。** 在 TG 语境下 401（Unauthorized）和 403（Forbidden）都意味着 token 无效或权限不足，处理策略完全相同：不重试、停止轮询、通知用户。

3. **409 Conflict 独立于 `consecutiveErrors`。** Conflict 不是网络错误而是业务状态错误（另一个实例在轮询同一 bot），需要独立的计数器和不同的退避策略（30s 固定，非指数）。

4. **5xx 应标记为 retryable。** 当前 `classifyHTTPError` 的 default 分支返回 `.permanentTelegramError`，导致 500/502/503 等 server error 不重试。这是现有行为的 bug-fix——改为返回 `.retryableNetwork` 让 5xx 走指数退避重试。

5. **认证失败通知只能走 `log()`。** 401/403 意味着 TG API 不可用，不能通过 `sendReply()` 发消息通知用户。只能通过 `log()` 写到 stderr（Gateway 模式下 stderr 被 launchd 捕获到系统日志）。

### Telegram API 409 Conflict Background

TG API 对 `getUpdates` 的 409 Conflict 响应：
```json
{"ok":false,"error_code":409,"description":"Conflict: terminated by other getUpdates request; make sure that only one bot instance is running"}
```

这表示另一个进程/实例正在用同一个 bot token 调用 `getUpdates`。TG 不允许并发 long polling。

### Mock URLSession Enhancement for Testing

现有 `MockHTTPErrorURLSession` 不支持自定义 header。需要扩展以测试 `Retry-After` 解析：

```swift
final class MockHTTPErrorURLSession: URLSessionProtocol, @unchecked Sendable {
    let statusCode: Int
    let body: String
    let headers: [String: String]   // 新增
    var attemptCount = 0

    init(statusCode: Int, body: String = "...", headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        attemptCount += 1
        let url = request.url ?? URL(string: "https://example.com")!
        let httpResp = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (Data(body.utf8), httpResp)
    }
}
```

### Testing Standards

- **所有测试使用 Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`)
- **禁止真实网络调用** — 所有测试通过 `MockURLSessionProtocol` 实现
- **现有 Mock 类型**：`MockFailingURLSession`（网络错误）、`MockHTTPErrorURLSession`（HTTP 错误）、`MockScriptedURLSession`（脚本化响应）、`MockRecordingURLSession`（记录请求）
- **测试命名**：`func retriesOnFailure()` 风格，描述性命名

### Project Structure Notes

- 所有变更在 `Sources/AxionCLI/Services/Telegram/` 目录内
- 测试变更在 `Tests/AxionCLITests/Services/Telegram/TGAPIClientTests.swift`
- 无跨模块影响 — `TGAPIClient` 和 `TelegramAdapter` 都在 AxionCLI 内部
- 无 AxionCore 变更

### Anti-Pattern Prevention

- **不要创建新的 Swift 文件** — 所有代码加入现有 `TGAPIClient.swift` 和 `TelegramAdapter.swift`
- **使用 `_Concurrency.Task` 而非 `Task`** — OpenAgentSDK 有 `Task` 类型名冲突（project-context 反模式 #19）
- **不要在 `performRequest` 中直接 sleep** — 使用 `try? await _Concurrency.Task.sleep(nanoseconds:)`
- **不要修改 `TGMessageFormatter`** — 格式化不涉及网络重连
- **不要修改 `TGStreamingController`** — 流式推送不涉及网络重连
- **不要修改 `MockTGAPIClient`** — 它是 protocol mock，网络重试逻辑在 `TGAPIClient` struct 中
- **`.rateLimited` 关联值变更后，所有 pattern matching 都要更新** — 搜索 `.rateLimited` 确保没有遗漏

### ATDD Artifacts

- **Checklist:** `_bmad-output/test-artifacts/atdd-checklist-36-1-network-reconnection-enhancement.md`
- **Test File:** `Tests/AxionCLITests/Services/Telegram/TGAPIClientTests.swift`
- **RED Phase:** 8 disabled tests + 10 commented scaffolds covering all 4 ACs

### References

- [Source: docs/epics/epic-36-tg-network-markdown.md#Story 36.1] — Epic 权威 AC 和实现参考
- [Source: Sources/AxionCLI/Services/Telegram/TGAPIClient.swift] — 当前实现（252 行），`performRequest` + `classifyHTTPError` + `TGAPIError`
- [Source: Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift#pollLoop] — 当前轮询循环（62-77 行），`consecutiveErrors` 退避逻辑
- [Source: Tests/AxionCLITests/Services/Telegram/TGAPIClientTests.swift] — 当前测试（823 行），含 Mock URLSession 类型
- [Source: _bmad-output/project-context.md#并发模式] — 重试策略：指数退避 1s→2s→4s
- [Source: _bmad-output/project-context.md#反模式] — #19 使用 `_Concurrency.Task`，#15 TG bot token 不写入 config.json

## Dev Agent Record

### Agent Model Used

Claude Sonnet 4.5 (BMAD dev-story workflow, yolo mode)

### Debug Log References

- Build: `swift build --build-tests` — success (38.56s)
- TGAPIClientTests: 50/50 passed (10.327s)
- TelegramAdapterTests: 36/36 passed (0.514s)
- Full unit test suite: 3952/3952 passed (17.326s)

### Completion Notes List

1. **TGAPIError enum enhanced**: Added `.authFailed(String)` for 401/403, `.pollingConflict(String)` for 409, changed `.rateLimited(String)` to `.rateLimited(String, retryAfter: TimeInterval)` for Retry-After header support.

2. **classifyHTTPError upgraded**: Now accepts `HTTPURLResponse` to parse `Retry-After` header. 429 → parses header or defaults to 5s; 401/403 → `.authFailed`; 409 → `.pollingConflict`; 5xx → `.retryableNetwork` (bug fix: was `.permanentTelegramError`).

3. **performRequest retry logic updated**: `.rateLimited` now sleeps `retryAfter` seconds (from header); `.authFailed` and `.pollingConflict` throw immediately (no retry); `.retryableNetwork` and generic errors retain exponential backoff `pow(2, attempt)`.

4. **TelegramAdapter.pollLoop enhanced**: Added `consecutiveConflicts` counter (independent of `consecutiveErrors`). `.pollingConflict` → 30s wait, increment counter, stop after 3 consecutive (status: `conflict_stopped`). `.authFailed` → immediate stop (status: `auth_failed`) with log notification. Success resets both counters.

5. **TelegramAdapter.editMessage**: Updated switch to handle new error cases (`.authFailed`, `.pollingConflict` → return false).

6. **All 8 RED-phase disabled tests activated** + **9 commented scaffolds uncommented**. Existing `http403Permanent` test updated to expect `.authFailed`. Existing `apiErrorDescriptionAllCases` and `editMessageReturnsFalseOnRateLimited` updated for new `.rateLimited` signature.

### File List

- `Sources/AxionCLI/Services/Telegram/TGAPIClient.swift` — MODIFIED: TGAPIError enum (2 new cases + retryAfter), classifyHTTPError (HTTPURLResponse + new status codes), performRequest (retryAfter-based sleep, new case handling)
- `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` — MODIFIED: pollLoop (consecutiveConflicts, .pollingConflict handling, .authFailed handling), editMessage switch (new cases)
- `Tests/AxionCLITests/Services/Telegram/TGAPIClientTests.swift` — MODIFIED: Activated 8 disabled tests, uncommented 9 scaffolds, updated existing tests for new API
- `Tests/AxionCLITests/Services/Telegram/TelegramAdapterTests.swift` — MODIFIED: Updated `.rateLimited` usage to include `retryAfter:` parameter

### Change Log

- 2026-06-17: Implemented network reconnection enhancement (story 36-1). TGAPIError gains `.authFailed`, `.pollingConflict`, and `.rateLimited(_:retryAfter:)`. classifyHTTPError parses Retry-After, classifies 401/403/409/5xx. TelegramAdapter pollLoop handles conflict degradation and auth failure. All 50 TGAPIClient tests + 36 TelegramAdapter tests pass. Zero regressions across 3952 unit tests.

### Review Findings

**Review date:** 2026-06-17 — 3 layers (Blind Hunter + Edge Case Hunter + Acceptance Auditor)

- [x] [Review][Defer] `Retry-After: 0` 或负值会导致 zero/negative sleep [TGAPIClient.swift:195] — deferred, pre-existing risk but low probability from TG API
- [x] [Review][Patch] `consecutiveConflicts` 重置不完整 — `.authFailed` case 不会重置 `consecutiveConflicts`，虽然 `isRunning = false` 会退出循环，但逻辑上应在停止前保持状态一致性 [TelegramAdapter.swift:84-87] — ✅ Fixed
- [ ] [Review][Patch] `Retry-After` HTTP-date 格式未处理 — RFC 7231 允许 HTTP-date 格式，当前 `TimeInterval(_:)` 会 fallback 到 5s，TG API 实际只发秒数所以影响低 [TGAPIClient.swift:223] — Left as-is: TG API only sends seconds
- [x] [Review][Patch] `noRetryOnClientError` 测试名称过时 [TGAPIClientTests.swift:50] — ✅ Fixed: renamed to "does not retry on 401 auth failure"
- [x] [Review][Patch] `apiErrorDescriptionAllCases` 测试不完整 [TGAPIClientTests.swift:74] — ✅ Fixed: added `.authFailed` and `.pollingConflict` assertions

## Status

Status: done
