# Epic 23 手工验收测试: Review 配置与 Axion 专属适配

版本: 0.7.0
日期: 2026-05-24

## 前置条件

```bash
# 1. 构建项目
swift build

# 2. 确认 API Key 已配置
swift run AxionCLI doctor

# 3. 备份当前配置（如需修改）
cp ~/.config/axion/config.json ~/.config/axion/config.json.bak
```

---

## 一、Story 23.1: Review 配置项与 CLI 标志

验证 review 和 curator 相关的配置项在 config.json 和 CLI 中正确生效。

### 1.1 config.json review 配置项

```bash
# 查看当前配置
cat ~/.config/axion/config.json | python3 -m json.tool 2>/dev/null || cat ~/.config/axion/config.json
```

**验证配置项支持：**

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `reviewMemoryInterval` | Int? | 4 | 每隔多少条消息触发 memory review |
| `reviewSkillInterval` | Int? | 6 | 每隔多少条消息触发 skill review |
| `reviewMinMessages` | Int? | 4 | 最少消息数才触发 review |
| `reviewModel` | String? | claude-haiku-4-5-20251001 | Review agent 使用的模型 |
| `curatorEnabled` | Bool? | true | 是否启用 curator |
| `curatorDryRun` | Bool? | false | Curator 是否干跑模式 |
| `curatorIntervalHours` | Double? | 168.0 | Curator 触发间隔（小时） |
| `curatorStaleAfterDays` | Int? | 30 | 技能过期天数 |
| `curatorArchiveAfterDays` | Int? | 90 | 技能归档天数 |

**通过** — 配置项在 `AxionConfig` 中定义，支持 JSON 解码（单元测试覆盖）。

### 1.2 --no-review CLI 标志

```bash
swift run AxionCLI run --help
```

**预期:** 帮助信息包含 `--no-review` 标志（"禁用 post-run review 和 curator"）。

```bash
swift run AxionCLI run "1+2等于几" --no-review
```

**预期:** 运行正常完成，不触发 review 和 curator。

**通过** — `--no-review` 标志正确显示并生效。

### 1.3 --review-model CLI 标志

```bash
swift run AxionCLI run --help | grep review-model
```

**预期:** 帮助信息包含 `--review-model` 选项（"覆盖 review agent 使用的模型"）。

```bash
swift run AxionCLI run "打开计算器" --review-model claude-haiku-4-5-20251001
```

**预期:** 运行正常，使用指定的 review 模型。不影响主 agent 的模型选择。

**通过** — `--review-model` 正确覆盖 review agent 的模型。

### 1.4 Doctor 命令显示 Review/Curator 状态

```bash
swift run AxionCLI doctor
```

**预期:** 输出包含 `Review/Curator` 检查项，显示：
- review 间隔
- skill review 间隔
- curator 启用/禁用
- review 模型

**通过** — Doctor 正确显示 review/curator 配置状态。

### 1.5 Review 配置项（单元测试覆盖）

```bash
swift test --filter "AxionCLITests.Config.ReviewConfigTests"
```

**预期:** 所有测试通过，覆盖：
- `AxionConfig` 的 review 配置项编解码
- 默认值正确
- CLI override 正确合并

**通过（单元测试覆盖）**

---

## 二、Story 23.2: Review 结果日志与通知

验证 review 和 curator 的结果正确记录到 trace 和终端输出。

### 2.1 Review 结果终端输出

当 review 实际执行并产生变更时，终端输出摘要：

```bash
swift run AxionCLI run "打开计算器，计算 456 * 789，截图确认结果"
```

**预期（如果触发 review 且有变更）:**
- 输出 `[axion] Review: 保存了 N 条记忆, 更新了 M 个技能`
- 如果无变更则无输出（避免噪音）

**通过** — Review 结果以简洁格式输出到终端。

### 2.2 Review 结果写入 trace

```bash
# 运行一个任务
swift run AxionCLI run "打开文本编辑，输入 Review Trace Test"

# 查找最新的 run trace
RUN_DIR=$(ls -td ~/.axion/runs/2* | head -1)
echo "Run directory: $RUN_DIR"
cat "$RUN_DIR/review-trace.jsonl" 2>/dev/null || echo "无 review trace"
```

**预期:** 若触发了 review，`review-trace.jsonl` 包含 JSON-lines 格式的事件：
- `review_completed` 事件含 `review_summary`、`memory_changes`、`skill_changes`
- 或 `review_failed` 事件含 `error` 信息

**通过** — Review 结果正确写入 trace 文件。

### 2.3 Curator 结果终端输出

当 curator 实际执行并产生变更时：

```bash
swift run AxionCLI curator run
```

**预期:** 输出 Markdown 格式的策展报告，包含：
- 机械式策展结果（过期/归档/活跃技能统计）
- LLM 策展结果（合并/精简建议）
- 如有变更，终端可能输出 `[axion] Curator: 合并 N 个技能, 归档 M 个技能`

**通过** — Curator 输出详细报告。

### 2.4 Curator 结果写入 trace

Curator 在 `axion run` 后台触发时，结果写入同一 run 的 trace：

```bash
RUN_DIR=$(ls -td ~/.axion/runs/2* | head -1)
grep curator "$RUN_DIR/review-trace.jsonl" 2>/dev/null || echo "无 curator trace"
```

**预期:** 若 curator 在 run 后触发，trace 包含 `curator_completed` 或 `curator_failed` 事件。

**通过** — Curator 结果写入 trace。

### 2.5 Review Summary（单元测试覆盖）

```bash
swift test --filter "AxionCLITests.API.ReviewSummaryTests"
```

**预期:** 所有测试通过，覆盖：
- `formatReviewSummary` 格式化逻辑
- 无变更时返回 nil（避免噪音）
- `formatCuratorSummary` 格式化逻辑

**通过（单元测试覆盖）**

---

## 三、端到端流程验证

### 3.1 完整 Review 配置 → 运行 → 验证流程

```bash
# Step 1: 查看当前 review 配置
swift run AxionCLI doctor | grep -A1 "Review/Curator"

# Step 2: 使用 --no-review 运行
swift run AxionCLI run "1+1等于几" --no-review
# 无 review 输出

# Step 3: 正常运行（可能触发 review）
swift run AxionCLI run "打开计算器，计算 123 + 456"
# 可能有 [axion] Review: 输出（取决于对话长度）

# Step 4: 查看 trace
RUN_DIR=$(ls -td ~/.axion/runs/2* | head -1)
ls -la "$RUN_DIR/"
cat "$RUN_DIR/review-trace.jsonl" 2>/dev/null || echo "无 review trace"

# Step 5: 手动触发 curator
swift run AxionCLI curator run --dry-run
# 输出策展报告
```

**通过** — 完整配置→运行→验证流程正常。

### 3.2 Curator 状态一致性

```bash
# 查看状态
swift run AxionCLI curator status

# 手动运行 curator
swift run AxionCLI curator run

# 再次查看状态（运行次数应增加）
swift run AxionCLI curator status
```

**预期:** 运行次数正确更新，上次策展时间更新。

**通过** — Curator 状态一致更新。

---

## 验收结果汇总

| 测试项 | 描述 | 结果 |
|--------|------|------|
| 1.1 | config.json review 配置项支持 | 通过 |
| 1.2 | --no-review CLI 标志 | 通过 |
| 1.3 | --review-model CLI 标志 | 通过 |
| 1.4 | Doctor 显示 Review/Curator 状态 | 通过 |
| 1.5 | Review 配置项（单元测试） | 通过（单元测试覆盖） |
| 2.1 | Review 结果终端输出 | 通过 |
| 2.2 | Review 结果写入 trace | 通过 |
| 2.3 | Curator 结果终端输出 | 通过 |
| 2.4 | Curator 结果写入 trace | 通过 |
| 2.5 | Review Summary（单元测试） | 通过（单元测试覆盖） |
| 3.1 | 端到端配置→运行→验证 | 通过 |
| 3.2 | Curator 状态一致性 | 通过 |

**单元测试:** `ReviewConfigTests` (243 行) + `ReviewSummaryTests` (150 行) + `RunOrchestratorReviewTests` (890 行) — 全部通过。

**总体结论: 通过**
