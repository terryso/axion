---
baseline_commit: e44ea92
---

# Story 36.2: MarkdownV2 表格支持 — Formatting Pipeline Hermes Parity

Status: done

## Story

As a Axion Telegram 用户,
I want agent 回复中的 Markdown 表格（GFM tables）在 TG 中正确渲染为等宽对齐文本,
So that 我在手机上看到的数据和参数对比信息是结构化可读的，而不是乱码。

## Acceptance Criteria

1. **Given** agent 最终结果包含 GFM 表格（`| col1 | col2 |` 语法，含 separator 行）
   **When** `TGMessageFormatter.format()` 处理该文本
   **Then** 表格被渲染为等宽对齐的 `<pre>` 格式文本（MarkdownV2 模式下）
   **And** 列宽按最宽单元格对齐
   **And** separator 行（`|---|---|`）被移除

2. **Given** agent 结果包含多行表格（超过 1 行数据）
   **When** MarkdownV2 渲染
   **Then** 整个表格作为一个 `<pre>` 块输出，保证字符对齐
   **And** 表格内部字符不需要额外 MarkdownV2 转义（`<pre>` 块内不需要转义）

3. **Given** agent 结果包含表格和普通段落文本的混合
   **When** `TGMessageFormatter` 处理
   **Then** 表格正确识别为连续的多行 `|...|` 块（含 separator）
   **And** 表格前后普通文本正常渲染（heading/list/inline 等）
   **And** 表格渲染与周围文本之间有空行分隔

4. **Given** HTML 渲染模式
   **When** 表格存在
   **Then** 表格渲染为 HTML `<pre><code>` 等宽块（与 MarkdownV2 模式一致的对齐逻辑）

5. **Given** Plain 渲染模式
   **When** 表格存在
   **Then** 表格渲染为缩进的等宽文本（与 MarkdownV2/HTML 一致的对齐逻辑）

6. **Given** 表格渲染后的等宽块超过 4096 UTF-8 字符
   **When** `TGMessageFormatter.split()` 切分
   **Then** 切分保持代码块平衡（`balanceCodeBlocks` 关闭/重开代码围栏）
   **And** 每个 chunk 的代码块正确闭合

7. **Given** 当前已有的 `renderTableRowMarkdownV2` key/value 降级渲染
   **When** 新的表格块渲染就绪
   **Then** 旧的逐行 key/value 降级被新的多行表格块渲染替代
   **And** 现有测试中依赖 key/value 格式的断言更新为新格式

## Tasks / Subtasks

- [x] Task 1: 重构表格检测为多行块识别 (AC: #1, #3)
  - [x] 1.1 在 `renderMarkdownV2` / `renderHTML` / `renderPlain` 中添加多行表格块检测逻辑：连续 `|...|` 行（含 separator）聚合为一个表格块
  - [x] 1.2 新增 `detectTableBlock(lines: startIndex:) -> (rows: [[String]], endIndex: Int)?` 方法，识别连续的 table row 行（跳过 separator 行）
  - [x] 1.3 更新逐行渲染逻辑：在遇到第一行 table row 时，先尝试块级检测；如果是单行表格（无后续行且无 separator），保留当前 key/value 降级行为

- [x] Task 2: 实现等宽表格渲染 (AC: #1, #2)
  - [x] 2.1 新增 `renderTableBlock(rows: [[String]], mode: RenderMode) -> String` 方法
  - [x] 2.2 计算每列最大宽度（基于单元格字符串的 `characterCount`，非 UTF-8 字节）
  - [x] 2.3 按列宽填充空格，生成等宽对齐文本
  - [x] 2.4 MarkdownV2 模式：用 ` ```\n{aligned}\n``` ` 包裹（code block 内不需要转义）
  - [x] 2.5 HTML 模式：用 `<pre><code>{aligned}</code></pre>` 包裹
  - [x] 2.6 Plain 模式：用缩进 4 空格包裹

- [x] Task 3: 更新 Split 逻辑保护表格块完整性 (AC: #6)
  - [x] 3.1 在 `split()` 方法中，检测 chunk 边界是否会切断 `<pre>` / code block 表格
  - [x] 3.2 如果表格块超过 4096 字符，依赖 `balanceCodeBlocks` 关闭/重开代码围栏保持平衡（超大表格场景极少，不做按行拆分+列头重复）

- [x] Task 4: 替换旧的逐行表格渲染方法 (AC: #7)
  - [x] 4.1 将 `renderTableRowMarkdownV2`、`renderTableRowHTML`、`renderTableRowPlain` 中的逐行 key/value 逻辑替换为新的块级渲染调用
  - [x] 4.2 保留 `isTableRow`、`isTableSeparator`、`parseTableRow` 等辅助方法（被新逻辑复用）

- [x] Task 5: 更新现有测试 + 新增测试 (AC: all)
  - [x] 5.1 更新 `formatTableDegrades` 测试：验证表格渲染为等宽块而非 key/value
  - [x] 5.2 新增测试：多行表格等宽对齐
  - [x] 5.3 新增测试：表格前后有普通文本的正确分段
  - [x] 5.4 新增测试：separator 行被移除
  - [x] 5.5 新增测试：单列表格（edge case，回退到 key/value）
  - [x] 5.6 新增测试：表格超长时的 split 行为
  - [x] 5.7 新增测试：HTML 和 Plain 模式的表格渲染
  - [x] 5.8 新增测试：表格内含特殊字符（`|`、`.`、`-`）的正确处理

## Dev Notes

### Architecture Context

This story 改进 Epic 32 Story 32.1 创建的 `TGMessageFormatter`。当前的逐行表格处理将每行 `| key | value |` 转为 `**key**: value` 的 key/value 格式——这对 2 列简单表格够用，但多列表格会丢失对齐信息，变得不可读。

**核心变更：** 将逐行处理升级为块级处理——先检测连续的表格行块，然后整体渲染为等宽对齐文本，包裹在 code block 中。

### Files Being Modified (UPDATE)

| File | Current State | What Changes |
|------|---------------|--------------|
| `TGMessageFormatter.swift` (~550 lines) | `renderMarkdownV2` / `renderHTML` / `renderPlain` 逐行处理，`renderTableRowMarkdownV2` 逐行 key/value | 添加 `detectTableBlock` 块检测；添加 `renderTableBlock` 等宽渲染；更新三个 render 函数支持块级表格；保留逐行 fallback |
| `TGMessageFormatterTests.swift` (241 lines) | `formatTableDegrades` 测试验证 key/value 输出 | 更新现有测试期望值；新增 8+ 测试覆盖块级渲染 |

### Files Being Created (NEW)

无。所有变更在现有文件中完成。

### Key Design Decisions

1. **多行块检测优先于逐行处理。** 当前 `renderLineMarkdownV2` 对每一行独立判断 `isTableRow`。新逻辑在遇到 table row 时，先向前扫描检测是否是多行表格块。如果是，整体渲染；如果只有单行（无后续行且无 separator），保留 key/value 降级。

2. **等宽对齐基于 `characterCount` 而非 `utf8.count`。** Telegram 的 4096 限制是 UTF-8 字节，但等宽字体的列宽在 TG 中按字符显示宽度计算。对于纯 ASCII 表格，两者一致；中文/emoji 可能不等宽，但 TG 的等宽字体对 CJK 字符有统一宽度处理。使用 `characterCount` 是合理的近似。

3. **MarkdownV2 模式用 code block 包裹表格。** `<pre>` 标签在 Telegram MarkdownV2 中没有原生支持（只有 ` ``` ` code block）。Code block 内的内容不需要 MarkdownV2 转义，因此表格内的 `. - |` 等特殊字符不会被破坏。

4. **Separator 行直接丢弃。** `|------|-------|` 这样的行仅用于 Markdown 解析标记列对齐方向，渲染输出不需要。

5. **表格块不切分优先。** `split()` 应尽量将整个表格保持在一个 chunk 中。只有当表格渲染后超过 4096 字符时才考虑按行切分（极端 case）。

### Telegram API Constraints

| Constraint | Value | Impact |
|------------|-------|--------|
| Max message length | 4096 UTF-8 bytes (rendered) | 超长表格需要切分 |
| Code block 内不转义 | ``` 内的文本直接输出 | 表格内特殊字符安全 |
| 等宽字体 | TG code block 使用等宽字体 | 列对齐在等宽环境下生效 |
| MarkdownV2 无原生表格 | 只能通过 code block 降级 | 这是本 story 存在的原因 |

### Table Detection Algorithm

```
Input: lines array + current index pointing to first |...| line

1. Start from currentIndex
2. Collect consecutive lines where:
   - line matches isTableRow(line) OR
   - line matches isTableSeparator(line)
3. Stop at first non-table line or end of lines
4. If collected block has >= 2 non-separator rows → multi-row table block
5. If only 1 row → single-row table, use existing key/value fallback
6. Extract cells from each non-separator row via parseTableRow()
7. Return rows as [[String]] + endIndex
```

### Column Alignment Algorithm

```
Input: [[String]] of table cells (rows x columns)

1. Determine column count = max(rows.map { $0.count })
2. Pad each row to column count with empty strings
3. For each column, compute maxWidth = max(all cells.map { $0.count })
4. For each row, format: "| " + cells.paddedTo(maxWidth).joined(separator: " | ") + " |"
5. Join all rows with "\n"
```

### Testing Standards

- **所有测试使用 Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`)
- **不引入新的 Mock** — `TGMessageFormatter` 是纯函数枚举，无外部依赖
- **测试覆盖三个渲染模式**：MarkdownV2、HTML、Plain 都要验证表格输出
- **Edge cases to test**: 单列表格、空单元格、超长单元格、表格紧跟 heading/list

### Project Structure Notes

- 所有变更在 `Sources/AxionCLI/Services/Telegram/TGMessageFormatter.swift`
- 测试变更在 `Tests/AxionCLITests/Services/Telegram/TGMessageFormatterTests.swift`
- 无跨模块影响 — Telegram 格式化是 AxionCLI 内部的表示层
- 无 AxionCore 变更

### Anti-Pattern Prevention

- **不要引入新的 Swift 文件** — 所有代码加入现有 `TGMessageFormatter.swift`
- **不要在 code block 内做 MarkdownV2 转义** — code block 内容原样输出
- **不要使用 `print()` 调试** — 用 `#expect` 断言
- **不要修改 `TGStreamingController`** — 流式推送不涉及表格渲染
- **不要修改 `TelegramAdapter`** — 适配器只调用 `TGMessageFormatter.format()`，不关心内部实现
- **使用 `_Concurrency.Task` 而非 `Task`** — 但本 story 不涉及并发代码
- **格式化所有权归 Formatter** — Adapter/Controller/Handler 不做格式化（project-context 反模式 #17）

### References

- [Source: _bmad-output/planning-artifacts/prds/prd-tg-enhancement-hermes-parity/prd.md#Epic 36] — PRD: "在 TGMessageFormatter 中增加 GFM 表格检测和渲染——将表格行转为 `<pre>` 格式的等宽文本，避免 MarkdownV2 不支持表格标签导致乱码"
- [Source: Sources/AxionCLI/Services/Telegram/TGMessageFormatter.swift] — 当前实现（~550 行），包含 `renderTableRowMarkdownV2` 逐行 key/value
- [Source: Tests/AxionCLITests/Services/Telegram/TGMessageFormatterTests.swift] — 当前测试（241 行）
- [Source: _bmad-output/implementation-artifacts/32-1-telegram-rich-text-rendering.md] — Story 32.1 原始实现记录，表格部分使用 key/value 降级
- [Source: _bmad-output/project-context.md#反模式] — 反模式规则（#12 不用 JSONEncoder 之外的拼接，#17 格式化所有权归 Adapter/Formatter）

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m]

### Debug Log References

No blocking issues encountered.

### Completion Notes List

- Implemented block-level table detection in all 3 render functions (MarkdownV2, HTML, Plain) by converting from `for line in lines` iteration to index-based `while i < lines.count` loop
- Added `detectTableBlock(lines:startIndex:)` method that scans forward from the first table row to collect contiguous table/separator lines; returns nil if fewer than 2 data rows (single-row fallback preserved)
- Added `renderTableBlock(rows:mode:)` method with column alignment algorithm: computes per-column max width, pads cells with spaces, wraps in mode-appropriate container (``` code block / `<pre><code>` / indented)
- Added `isInsideCodeBlock(at:)` helper to prevent `split()` from cutting inside code blocks
- Added `RenderMode` enum for the 3 rendering modes used by `renderTableBlock`
- Single-row tables (no separator, no subsequent row) retain key/value fallback via existing `renderTableRowMarkdownV2/HTML/Plain`
- All 25 ATDD table block tests pass (was 24 failures in red phase, now 0)
- All 30 existing `TGMessageFormatterTests` pass with no regressions
- Full unit test suite: 1882 tests pass, 0 failures
- ATDD test `[P0][AC6] Oversized table splits by rows` was updated to use wider cells (100 rows of `DataEntryNumber{i}`) to actually exceed 4096 bytes when rendered

### File List

- `Sources/AxionCLI/Services/Telegram/TGMessageFormatter.swift` — Added `RenderMode` enum, `detectTableBlock`, `renderTableBlock`, `isInsideCodeBlock` methods; refactored `renderMarkdownV2`, `renderHTML`, `renderPlain` to use index-based iteration with block table detection; updated `split()` to protect code block integrity
- `Tests/AxionCLITests/Services/Telegram/TGMessageFormatterTableTests.swift` — Updated oversized table test to use wider cells that actually exceed 4096 bytes
