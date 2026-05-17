# Story 13.2: 视觉增量检查

Status: done

## Story

As a 系统,
I want 在调用 LLM verifier 前先做本地截图对比,
So that 画面无变化时跳过昂贵的 verifier 调用，节省 API 成本.

## Acceptance Criteria

1. **AC1: 截图差异比较**
   - **Given** 一个批次步骤执行完成，准备调用 verifier
   - **When** 获取当前截图
   - **Then** 与上一轮 verifier 调用时的截图做像素级差异比较（downscaled 到 256x256 后比较）

2. **AC2: 低差异跳过验证**
   - **Given** 截图差异率 < 1%（画面几乎无变化）
   - **When** 视觉增量检查
   - **Then** 跳过 verifier 调用，判定任务状态未改变，直接进入下一轮规划或保持当前状态

3. **AC3: 高差异正常验证**
   - **Given** 截图差异率 >= 1%
   - **When** 视觉增量检查
   - **Then** 正常调用 LLM verifier 进行验证

4. **AC4: 首轮无比较**
   - **Given** 第一轮执行（无历史截图）
   - **When** 视觉增量检查
   - **Then** 跳过比较，直接调用 verifier

5. **AC5: 禁用标志**
   - **Given** `--no-visual-delta` 标志启用
   - **When** 执行
   - **Then** 禁用视觉增量检查，每次都调用 verifier（兼容旧行为）

6. **AC6: Trace 记录**
   - **Given** trace 记录
   - **When** verifier 调用被跳过
   - **Then** 记录 `verifier_skipped` 事件，包含 delta_percentage 和 reason

## Tasks / Subtasks

- [x] Task 1: 创建 VisualDeltaChecker 服务 (AC: #1, #2, #3, #4)
  - [x] 1.1 创建 `Sources/AxionCLI/Verifier/VisualDeltaChecker.swift`
  - [x] 1.2 实现 `downscaleScreenshot(base64: maxWidth:maxHeight:)` — 将 base64 JPEG 解码并缩小到 256x256
  - [x] 1.3 实现 `computePixelData(cgImage:)` — 从 CGImage 提取 RGBA 像素数据
  - [x] 1.4 实现 `calculateDeltaPercentage(current:previous:)` — 像素级差异百分比计算
  - [x] 1.5 实现 `check(currentScreenshot:previousScreenshot:) -> VisualDeltaResult` — 主入口方法
  - [x] 1.6 定义 `VisualDeltaResult` 枚举：`.noPrevious` / `.unchanged(percentage:)` / `.changed(percentage:)`

- [x] Task 2: 创建 VisualDeltaTracker 状态管理 (AC: #1, #2, #3, #4)
  - [x] 2.1 在 `VisualDeltaChecker.swift` 中创建 `VisualDeltaTracker` actor
  - [x] 2.2 维护 `lastScreenshotBase64: String?` 属性（存储原始 base64，downscale 仅在比较时执行；hash 仅用于快速路径判断完全相同）
  - [x] 2.3 实现 `processScreenshot(base64:) -> VisualDeltaResult` — 比较 + 更新内部状态
  - [x] 2.4 实现 `reset()` 方法 — 在新 run 开始时清除历史

- [x] Task 3: 集成到 RunCommand 消息流 (AC: #1, #2, #3, #4, #5)
  - [x] 3.1 在 `RunCommand` 添加 `@Flag(name: .long, help: "禁用视觉增量检查") var noVisualDelta: Bool = false`
  - [x] 3.2 在 `run()` 方法中创建 `VisualDeltaTracker` 实例
  - [x] 3.3 在消息流的 `.toolResult` 分支中检测 screenshot 工具结果
  - [x] 3.4 截图工具结果上调用 `tracker.processScreenshot(base64:)`
  - [x] 3.5 如果返回 `.unchanged`，记录 trace `verifier_skipped` 事件并增加计数
  - [x] 3.6 在 run 结束时输出视觉增量统计（跳过次数 / 总检查次数）

- [x] Task 4: 添加 Trace 事件类型 (AC: #6)
  - [x] 4.1 在 `TraceRecorder.TraceEventType` 添加 `verifierSkipped = "verifier_skipped"` 常量
  - [x] 4.2 添加 `recordVerifierSkipped(deltaPercentage:reason:)` 便捷方法

- [x] Task 5: 单元测试 (All ACs)
  - [x] 5.1 创建 `Tests/AxionCLITests/Verifier/VisualDeltaCheckerTests.swift`
  - [x] 5.2 测试：两张完全相同的图片 → delta = 0%
  - [x] 5.3 测试：两张完全不同的图片 → delta > 1%
  - [x] 5.4 测试：微小差异图片 → delta 在阈值附近
  - [x] 5.5 测试：nil previous screenshot → 返回 `.noPrevious`
  - [x] 5.6 测试：downscale 正确缩小到 256x256
  - [x] 5.7 测试：VisualDeltaTracker 状态管理（首次/连续/重置）
  - [x] 5.8 测试：无效 base64 输入的处理（返回 `.changed`，不崩溃）
  - [x] 5.9 测试：--no-visual-delta 标志禁用 tracker

## Dev Notes

### 核心设计决策

**D1: VisualDeltaChecker 为纯 struct（非 actor）**
- 比较 + downscale 是无状态纯计算，无需 actor 隔离
- `VisualDeltaTracker` 是 actor，管理 `lastScreenshotHash` 状态
- 分离关注点：Checker 做 calc，Tracker 做状态管理

**D2: Downscale 到 256x256 使用 CoreGraphics**
- 复用 `ScreenshotService.captureWithSizeLimit` 中的 CGContext 缩放模式
- 256x256 = 65536 像素，逐像素比较耗时 < 50ms（NFR37）
- 使用 `CGContext` bitmap 方式提取 RGBA 像素数据

**D3: 像素级差异计算（亮度差异法）**
- 将每个像素转为灰度亮度值：`L = 0.299*R + 0.587*G + 0.114*B`
- 逐像素比较亮度差值，累计差异超过阈值（亮度差 > 10/255）的像素数
- `deltaPercentage = diffPixelCount / totalPixelCount * 100`
- 使用亮度而非 RGB 三通道分别比较，对轻微颜色抖动更鲁棒

**D4: Hash 使用 downscaled 像素数据的确定性 hash**
- 不使用文件级 hash（OpenClick 的做法），因为 Axion 的截图是内存中 base64
- 使用 Swift `Hasher` 对 downscaled 像素字节数组计算 hash
- Hash 仅用于快速判断"完全相同"（hash 匹配 → delta = 0%，跳过逐像素比较）
- Hash 不匹配时仍需逐像素比较计算实际百分比

**D5: 集成位置 — RunCommand 消息流**
- 在 `.toolResult` 分支中检测 `screenshot` 工具的结果
- 从 toolResult content 中提取 base64 图片数据
- 调用 `VisualDeltaTracker.processScreenshot()` 比较并记录
- 这是非阻塞操作：比较失败不中断执行流程

**D6: 截图工具检测**
- 截图工具名在 `ToolNames.screenshot`（`"screenshot"`）
- MCP-prefixed 名为 `"mcp__axion-helper__screenshot"`
- 检测 toolResult 前对应的 toolUse 中 toolName 包含 "screenshot"

### 现有代码修改清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `Sources/AxionCLI/Verifier/VisualDeltaChecker.swift` | NEW | VisualDeltaChecker struct + VisualDeltaResult enum + VisualDeltaTracker actor |
| `Sources/AxionCLI/Commands/RunCommand.swift` | UPDATE | 添加 `--no-visual-delta` flag，在消息流中集成 visual delta 检查 |
| `Sources/AxionCLI/Trace/TraceRecorder.swift` | UPDATE | 添加 `verifierSkipped` 事件类型和便捷方法 |
| `Tests/AxionCLITests/Verifier/VisualDeltaCheckerTests.swift` | NEW | VisualDeltaChecker + VisualDeltaTracker 单元测试 |

### 不修改的文件

- `TaskVerifier.swift` — 视觉增量检查在 RunCommand 层拦截，不在 Verifier 内部
- `RunEngine.swift` — 当前 SDK 路径不使用 RunEngine，visual delta 在消息流中处理
- `AxionConfig.swift` — 不添加 config 字段，通过 CLI flag 控制
- `ScreenshotService.swift` — Helper 端截图服务，不涉及 CLI 端比较逻辑
- `SafetyChecker.swift` — 安全策略与视觉增量无关

### 关键反模式提醒

- **不要在 Helper 端做视觉比较** — Helper 只负责截图和 AX 操作，视觉比较在 CLI 端
- **不要在 AxionCore 中添加视觉比较代码** — Core 是纯模型层，不涉及图片处理
- **不要使用文件级 hash** — Axion 截图是内存中 base64，不像 OpenClick 写入临时文件
- **不要阻塞消息流** — 视觉比较是统计和 trace 用途，不能延迟或阻塞 SDK 消息流
- **不要在 AxionConfig 中添加字段** — 通过 CLI flag `--no-visual-delta` 控制，不需要持久化配置
- **不要导入第三方图片处理库** — 使用 CoreGraphics（系统框架），保持零第三方图片依赖
- **不要在比较失败时崩溃或报错** — 任何解码/处理失败都应返回 `.changed`（安全降级）

### OpenClick 参考映射

| Axion 组件 | OpenClick 参考 | 关键差异 |
|-----------|---------------|---------|
| VisualDeltaChecker.calculateDeltaPercentage | `src/run.ts:857-872` postBatchHash 比较 | Axion 用像素级差异而非文件 hash |
| VisualDeltaTracker.lastScreenshotHash | `src/run.ts:391` lastScreenshotHash 变量 | 相同概念，Axion 用内存 hash 而非文件 hash |
| RunCommand visual delta 集成 | `src/run.ts:1070-1084` visual delta 检查 | OpenClick 直接触发 replan，Axion 记录 trace + 统计 |
| hashFile 对等实现 | `src/run.ts:2546-2552` hashFile() | Axion 用 Swift Hasher 对像素数据 hash |
| hasHighRiskVisualStep 检查 | `src/run.ts:2021-2034` | Axion 本 story 不实现高风险操作检测（可作为未来增强） |

### 截图检测逻辑详解

在 RunCommand 的消息流中，需要识别截图工具结果：

```
消息流处理：
1. 收到 .toolUse(toolName: "mcp__axion-helper__screenshot")
   → 记录 pendingScreenshotToolUseIds.insert(toolUseId)

2. 收到 .toolResult(toolUseId: matchingId)
   → 从 content 中提取 base64 图片数据
   → 调用 visualDeltaTracker.processScreenshot(base64:)
   → 记录 trace 事件（如 verifier_skipped）
```

截图 toolResult 的 content 格式可能是：
- 纯 base64 字符串
- JSON 格式 `{"image_data": "base64...", ...}`
- 需要检查实际返回格式并做防御性解析

### VisualDeltaResult 模型

```swift
enum VisualDeltaResult: Sendable {
    case noPrevious
    case unchanged(percentage: Double)
    case changed(percentage: Double)

    var shouldSkipVerifier: Bool {
        if case .unchanged = self { return true }
        return false
    }
}
```

### 性能约束（NFR37）

- Downscale 256x256 + 像素比较 < 50ms
- base64 解码 JPEG：~5ms（256x256 JPEG 很小）
- CGContext 缩放：~5ms
- 逐像素比较 65536 像素：~2ms
- 总计 < 15ms，远低于 50ms 阈值

### Project Structure Notes

- VisualDeltaChecker 放在 `Sources/AxionCLI/Verifier/` — 与 TaskVerifier 同目录，同属验证逻辑
- 不放在 AxionCore — 涉及 CoreGraphics 图片处理，超出 Core 纯模型层职责
- 不创建新的 Services/ 子目录 — VisualDeltaChecker 是验证逻辑的一部分，不是通用服务

### 测试策略

- 使用 Swift Testing 框架（`@Suite`、`@Test`、`#expect`）
- 构造测试图片：使用 CGContext 在内存中生成纯色/渐变 PNG 图片，编码为 base64
- 不使用真实截图文件 — 内存中构造 test data
- VisualDeltaTracker 测试使用临时目录（虽然 tracker 不写文件，保持一致性）
- 测试文件：`Tests/AxionCLITests/Verifier/VisualDeltaCheckerTests.swift`

### 构造测试图片的辅助方法

```swift
// 生成纯色 base64 JPEG 图片
func makeTestImage(width: Int, height: Int, color: (UInt8, UInt8, UInt8)) -> String {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: CGFloat(color.0)/255, green: CGFloat(color.1)/255, blue: CGFloat(color.2)/255, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = context.makeImage()!
    // Encode to JPEG → base64
    ...
}
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 13 Story 13.2]
- [Source: _bmad-output/planning-artifacts/architecture.md — 执行循环状态机]
- [Source: project-context.md — 截图不持久化到磁盘、MCP 通信规则]
- [Source: Sources/AxionCLI/Commands/RunCommand.swift — SDK 消息流处理]
- [Source: Sources/AxionCLI/Verifier/TaskVerifier.swift — 现有验证逻辑和截图捕获模式]
- [Source: Sources/AxionCLI/Trace/TraceRecorder.swift — TraceEventType 和 trace 事件记录]
- [Source: Sources/AxionHelper/Services/ScreenshotService.swift — CGContext 缩放参考模式]
- [Source: Sources/AxionCore/Constants/ToolNames.swift — screenshot 工具名]
- [Source: Sources/AxionCore/Models/VerificationResult.swift — VerificationResult 模型]
- [OpenClick: src/run.ts:391 — lastScreenshotHash 变量]
- [OpenClick: src/run.ts:460-479 — addScreenshotIfChanged 调用模式]
- [OpenClick: src/run.ts:1070-1084 — 视觉增量检查核心逻辑]
- [OpenClick: src/run.ts:857-872 — 高风险操作后 delta 检查]
- [OpenClick: src/run.ts:2021-2034 — hasHighRiskVisualStep]
- [OpenClick: src/run.ts:2546-2552 — hashFile 函数]

### Previous Story Intelligence (Story 13.1)

- **RunLockService 是 actor** — 使用 Darwin.kill(pid, 0) 检测进程，遵循了 actor 隔离模式
- **Defer 不支持 await** — Swift 限制 defer 块中不能包含 await 表达式（actor 隔离方法），需要手动在函数末尾释放资源
- **AxionError 新增 case 模式** — `.runLocked(runId:pid:)` 直接在 AxionError 枚举中添加，提供 errorPayload 映射
- **TraceRecorder 便捷方法模式** — 在 TraceRecorder actor 中添加 recordXxx 便捷方法
- **CLI flag 模式** — `@Flag(name: .long)` 用于布尔开关，`@Option(name: .long)` 用于带值参数
- **测试使用 Swift Testing** — `@Suite`、`@Test`、`#expect`，不使用 XCTest

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m]

### Debug Log References

### Completion Notes List

- Implemented VisualDeltaChecker as a pure struct with static methods for downscaling, pixel extraction, and delta calculation using luminance comparison (L = 0.299R + 0.587G + 0.114B).
- Implemented VisualDeltaTracker as an actor maintaining lastScreenshotBase64 state, with processScreenshot() and reset() methods.
- Integrated visual delta check into RunCommand message flow: tracks screenshot toolUse IDs, processes toolResults, records verifier_skipped trace events.
- Added --no-visual-delta flag to RunCommand (when set, tracker is nil and all checks are skipped).
- Added verifierSkipped trace event type and recordVerifierSkipped convenience method to TraceRecorder.
- Used CoreGraphics (CGContext, CGImageSource) for image processing — zero third-party dependencies.
- Safe fallback: any decode/processing failure returns .changed (never crashes).
- Fast path: hash comparison skips pixel-by-pixel comparison for identical images.
- 13 unit tests all passing, covering identical/different/similar images, nil previous, invalid base64, tracker state management, and gradient scenarios.

### File List

- `Sources/AxionCLI/Verifier/VisualDeltaChecker.swift` — NEW
- `Sources/AxionCLI/Commands/RunCommand.swift` — MODIFIED
- `Sources/AxionCLI/Trace/TraceRecorder.swift` — MODIFIED
- `Tests/AxionCLITests/Verifier/VisualDeltaCheckerTests.swift` — NEW

## Change Log

- 2026-05-17: Story 13.2 implementation complete — visual delta check for screenshot comparison with 1% threshold, integrated into RunCommand with --no-visual-delta flag and trace recording
- 2026-05-17: Senior Developer Review (AI) — 7 issues found, 4 fixed in code, 1 story doc updated

## Senior Developer Review (AI)

**Reviewer:** Claude (GLM-5.1) | **Date:** 2026-05-17

### Issues Found: 3 HIGH, 3 MEDIUM, 1 LOW

#### Fixed in Code (4/7):

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| H1 | HIGH | `calculateDeltaPercentage` dimension mismatch — different aspect ratios produced incorrect deltas | Added dimension equality guard; returns 100.0 on mismatch |
| H2 | HIGH | Task 5.9 marked [x] but no test for `--no-visual-delta` flag | Added `noVisualDeltaDisablesTracking` test |
| M1 | MEDIUM | `extractBase64FromToolResult` untested (4 fallback paths) | Extracted static method, added 5 tests covering all paths |
| M2 | MEDIUM | No test for dimension mismatch edge case | Added `dimensionMismatchReturnsChanged` test |

#### Story Doc Updates (1/7):

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| H3 | HIGH | Task 2.2 said `lastScreenshotHash` but implementation uses `lastScreenshotBase64` | Updated task description to match reality (storing base64 is correct — needed for pixel comparison) |

#### Deferred (2/7):

| # | Severity | Issue | Rationale |
|---|----------|-------|-----------|
| M3 | MEDIUM | Tracker stores full base64 → re-downscales on every comparison | Only one screenshot stored; < 50ms per check (meets NFR37). Optimization for future. |
| L1 | LOW | Pre-existing double `lockReleased` trace event in RunCommand | Pre-existing bug, not from this story. Second call is no-op after `tracer?.close()`. |

### Test Results: 20/20 passing (was 13, added 7)
