# Epic 22 手工验收测试: Background Review Agent 集成

版本: 0.7.0
日期: 2026-05-24

## 前置条件

```bash
# 1. 构建项目
swift build

# 2. 确认二进制文件存在
ls -la .build/debug/AxionCLI .build/debug/AxionHelper

# 3. 确认 API Key 已配置
swift run AxionCLI doctor
```

### macOS 权限

确保已在 **系统设置 > 隐私与安全** 中授予：
- **辅助功能 (Accessibility)** — AxionHelper
- **屏幕录制 (Screen Recording)** — AxionHelper

---

## 一、Story 22.1: ReviewOrchestrator 接入 RunOrchestrator

验证每次 `axion run` 完成后自动检查是否需要 background review。

### 1.1 Review 自动触发（长对话）

```bash
swift run AxionCLI run "打开计算器，计算 17 * 23，然后截图看看结果"
```

**预期:** 运行完成后，如果对话消息数 >= 4（默认 reviewMinMessages），自动触发 background review。
- 终端可能输出 `[axion] Review: 保存了 N 条记忆` 或无输出（review 在 detached task 中执行，不阻塞终端）
- 检查 trace 文件：

```bash
RUN_DIR=$(ls -td ~/.axion/runs/2* | head -1)
cat "$RUN_DIR/review-trace.jsonl" 2>/dev/null || echo "无 review trace（消息数可能未达阈值）"
```

**预期:** 若触发 review，`review-trace.jsonl` 包含 `review_completed` 或 `review_failed` 事件。

**通过** — Review 在 detached task 中执行，不阻塞终端。trace 文件记录 review 事件。

### 1.2 Review 不触发（短对话）

```bash
swift run AxionCLI run "1+1等于几" --fast
```

**预期:** 快速模式，对话消息数少，不触发 review。运行完成后无 `[axion] Review:` 输出。

**通过** — 短对话不触发 review。

### 1.3 Review 通过 --no-review 禁用

```bash
swift run AxionCLI run "打开计算器" --no-review
```

**预期:** 即使对话足够长也不触发 review。无 `[axion] Review:` 输出，无 `review-trace.jsonl` 文件。

**通过** — `--no-review` 正确禁用 review。

---

## 二、Story 22.2: SkillEvolver 集成

验证 Review Agent 使用 SDK 的 `LLMSkillEvolver` 演化技能。

### 2.1 Skill 演化流程（单元测试覆盖）

SkillEvolver 集成通过单元测试覆盖：
- `RunOrchestratorReviewTests` 验证 review 调用时 `LLMSkillEvolver` 使用正确的 review model
- AgentBuilder 构造 `LLMSkillEvolver(client:evolutionModel:)` 并注入到 `ReviewOrchestrator`

```bash
swift test --filter "AxionCLITests.Services.RunOrchestratorReviewTests"
```

**预期:** 所有测试通过，验证 SkillEvolver 被正确构造和注入。

**通过（单元测试覆盖）**

---

## 三、Story 22.3: ReviewOrchestrator 依赖注入

验证 ReviewOrchestrator 正确注入 FactStore、SkillRegistry 等依赖。

### 3.1 AgentBuilder 注入验证（单元测试覆盖）

依赖注入通过单元测试覆盖：
- `RunOrchestratorReviewTests` 验证 `AgentBuilder.build()` 正确构造 `ReviewOrchestrator` 并注入 `FactStore`、`SkillRegistry`、`SkillEvolver`

```bash
swift test --filter "AxionCLITests.Services.RunOrchestratorReviewTests/testBuildResultContainsReviewOrchestrator"
```

**预期:** 测试通过，验证 `buildResult.reviewOrchestrator` 非 nil。

**通过（单元测试覆盖）**

---

## 四、Story 22.4: IntelligentCurator 接入

验证智能策展（IntelligentCurator）在合适的时机自动触发。

### 4.1 Curator 自动触发条件

Curator 在每次 run 完成后检查是否需要执行（基于间隔时间）。由于默认间隔 168 小时（7天），新安装不会立即自动触发。

验证 curator 存在但不干扰正常执行：

```bash
swift run AxionCLI run "打开文本编辑，输入 Hello Curator"
```

**预期:** 正常完成。无 `[axion] Curator:` 输出（因为默认间隔 168 小时，不会在首次就触发）。

**通过** — Curator 检查间隔条件后跳过，不干扰正常执行。

### 4.2 Curator 手动触发

```bash
swift run AxionCLI curator run --dry-run
```

**预期:** 执行策展（dry-run 模式不实际修改），输出策展报告（Markdown 格式）。

**通过** — 输出策展报告，显示过期/归档技能统计。

### 4.3 Curator 状态查看

```bash
swift run AxionCLI curator status
```

**预期:** 输出策展状态信息：
- 启用/禁用状态
- 间隔时间
- 上次/下次策展时间
- 运行次数
- Review 模型

**通过** — 正确显示策展配置和状态。

---

## 五、Story 22.5: Skill 使用追踪集成

验证 Skill 工具调用自动追踪使用次数。

### 5.1 Skill 使用追踪（单元测试覆盖）

使用追踪通过代码集成验证：
- `RunOrchestrator` 在 `Skill` tool use 时调用 `usageStore.bumpView(skillName:)`
- 技能直接执行路径 (`executeSkillDirectly`) 也调用 `usageStore.bumpView()`
- Review 完成后对 skill changes 调用 `usageStore.bumpManage(skillName:)`

```bash
swift test --filter "AxionCLITests.Services.RunOrchestratorReviewTests"
```

**预期:** 所有测试通过，包含 skill usage tracking 相关断言。

**通过（单元测试覆盖）**

### 5.2 Skill 使用追踪（手工验证）

```bash
# 执行一次包含 Skill 调用的任务
swift run AxionCLI run "截图看看当前桌面"
```

**预期:** 如果触发了内置 skill（如 screenshot-analyze），usage store 记录使用次数。

```bash
# 检查 usage 数据
ls -la ~/.axion/skills/usage/
```

**通过** — Skill 使用数据被记录。

---

## 验收结果汇总

| 测试项 | 描述 | 结果 |
|--------|------|------|
| 1.1 | Review 自动触发（长对话） | 通过 |
| 1.2 | Review 不触发（短对话） | 通过 |
| 1.3 | --no-review 禁用 review | 通过 |
| 2.1 | SkillEvolver 集成（单元测试） | 通过（单元测试覆盖） |
| 3.1 | ReviewOrchestrator 依赖注入（单元测试） | 通过（单元测试覆盖） |
| 4.1 | Curator 自动触发条件 | 通过 |
| 4.2 | Curator 手动触发（dry-run） | 通过 |
| 4.3 | Curator 状态查看 | 通过 |
| 5.1 | Skill 使用追踪（单元测试） | 通过（单元测试覆盖） |
| 5.2 | Skill 使用追踪（手工验证） | 通过 |

**单元测试:** `RunOrchestratorReviewTests` (890 行) — 全部通过。

**总体结论: 通过**
