# Epic 15 手工验收文档（Phase 4 — Takeover 学习与桌面活动感知）

> 生成日期：2026-05-17
> 分支：feature/phase4-execution-quality
> 验收环境：macOS 14+，已通过 `axion setup` 完成首次配置

---

## 前置准备

```bash
cd /Users/nick/CascadeProjects/axion
git branch --show-current
swift build
.build/debug/axion --version
```

---

## Story 15.1: Takeover 经验自动学习

### AC1: Takeover 恢复后自动记录 Memory

> **注意：** 此 AC 需要实际触发 takeover，即任务执行中遇到阻塞暂停。以下为手工触发流程。

```bash
# 运行一个可能触发 takeover 的任务
# 方法：运行一个需要前台操作的任务（shared-seat 模式下），等待 takeover 提示出现
# 当出现 "━━━ Axion Takeover ━━━" 提示时：
#   1. 在桌面上手动完成操作
#   2. 输入操作描述（如 "使用了 Cmd+Shift+G 输入路径"）
#   3. 按 Enter 恢复

.build/debug/axion run "在 Finder 中导航到一个隐藏文件夹" --max-steps 5
# 如果触发 takeover，恢复后检查记忆：
.build/debug/axion memory list
# 预期：出现 takeover 学习记录
#   ○ [推荐] 当被 ... 阻塞时，用户手动 ... 成功 (confidence: 0.72, evidence: 1)
```

### AC2: CLI 手动记录 takeover 学习

```bash
# 使用 learn-takeover 命令手动记录
.build/debug/axion memory learn-takeover \
  --bundle-id com.apple.finder \
  --issue "文件选择对话框无法通过 AX 定位" \
  --summary "使用 Cmd+Shift+G 直接输入路径" \
  --app-name Finder \
  --task "导航到隐藏文件夹"
# 预期输出：
# [axion] 已保存 takeover 学习到 com.apple.finder

# 验证
.build/debug/axion memory list
# 预期：com.apple.finder domain 下出现 [推荐] 记忆 (confidence: 0.72)
```

### AC3: Takeover 失败记录 avoid

```bash
# 手动记录失败 takeover
.build/debug/axion memory learn-takeover \
  --bundle-id com.apple.safari \
  --issue "登录页面需要 2FA 验证" \
  --summary "手动输入验证码后仍无法继续" \
  --outcome failed
# 预期输出：
# [axion] 已保存 takeover 学习到 com.apple.safari

# 验证
.build/debug/axion memory list
# 预期：com.apple.safari domain 下出现 [警告] 记忆 (confidence: 0.66)
```

### AC4: Takeover 学习注入 Planner prompt

```bash
# 运行相同 App 的任务，验证记忆被注入
.build/debug/axion run "在 Finder 中搜索文件" --max-steps 5 --verbose 2>&1 | grep -i "推荐路径\|soft hints\|takeover" | head -5 || echo "记忆注入在 verbose 模式可见"
# 预期：如果已有 active 的 takeover 学习记忆，Planner prompt 中应注入推荐路径
```

### AC5: --no-memory 标志跳过 takeover 学习

```bash
# 带 --no-memory 运行，验证 takeover 学习不被记录
.build/debug/axion run "在 Finder 中打开文件" --max-steps 3 --no-memory
# 预期：即使触发 takeover，也不会记录学习到 Memory
```

### AC6: Memory 生命周期验证

```bash
# 重复记录相同 takeaway 学习，验证 evidence 累积
.build/debug/axion memory learn-takeover \
  --bundle-id com.apple.finder \
  --issue "文件选择对话框无法通过 AX 定位" \
  --summary "使用 Cmd+Shift+G 直接输入路径"

.build/debug/axion memory list
# 预期：相同事实的 evidenceCount 递增
```

---

## Story 15.2: Takeover 结构化标记

### AC1: Takeover 提示引导用户输入反馈

```bash
# 运行可能触发 takeover 的任务
# 当出现 takeover 提示时，验证提示包含反馈引导语
.build/debug/axion run "在系统设置中修改网络配置" --max-steps 5 --allow-foreground
# 如果触发 takeover，预期提示包含：
# "手动完成后按 Enter 继续。可选：输入反馈描述你的操作..."
# "输入 skip 跳过当前步骤 / abort 终止任务"
```

### AC2: 用户输入反馈纳入 Memory

```bash
# 如果在 takeover 时输入了反馈文本
# 验证 feedback 被记录在 Memory evidence 中
# 方法：查看 Memory 详情

# 手动触发一个带反馈的 takeover 学习
.build/debug/axion memory learn-takeover \
  --bundle-id com.apple.finder \
  --issue "无法通过 AX 定位保存按钮" \
  --summary "使用 Cmd+S 快捷键保存" \
  --task "保存文件"

# 然后检查记忆
.build/debug/axion memory list
```

### AC3: InterventionReason 分类

```bash
# 验证 classifyReason 映射（通过单元测试）
swift test --filter "AxionCLITests.Memory.TakeoverMarkerTests" 2>&1 | grep -E "Test (passed|failed)|classified" | head -20
# 预期：classifyReason 相关测试全部通过
```

### AC4: Takeover 事件记入 trace

```bash
# 运行一个触发 takeover 的任务，检查 trace 文件
# 方法：运行后查看最新 trace
LATEST_TRACE=$(ls -t ~/.axion/runs/*/trace.jsonl 2>/dev/null | head -1)
if [ -n "$LATEST_TRACE" ]; then
  grep "takeover" "$LATEST_TRACE" | /opt/homebrew/bin/python3 -m json.tool | head -20
  # 预期：包含 takeover 事件，含 issue、summary、duration、reason_type 等字段
else
  echo "无 trace 文件（可能未触发 takeover）"
fi
```

### AC5: TakeoverMarker 模型验证

```bash
# 通过单元测试验证 Codable round-trip
swift test --filter "AxionCLITests.Memory.TakeoverMarkerTests.classifyReason\|AxionCLITests.Memory.TakeoverMarkerTests.codable" 2>&1 | tail -5
# 预期：测试通过
```

---

## 单元测试验证

```bash
swift test --filter "AxionCLITests.Memory.TakeoverLearningService" \
           --filter "AxionCLITests.Memory.TakeoverMarker" \
           --filter "AxionCLITests.Commands.MemoryLearnTakeoverCommand" \
           --filter "AxionCLITests.IO.TakeoverIO" \
           --filter "AxionCoreTests"
# 预期：所有 Takeover 相关测试通过
```

---

## 验收检查清单汇总

| Story | 关键验证点 | 通过 |
|-------|----------|------|
| 15.1 | `memory learn-takeover` 命令可用 | ☐ |
| 15.1 | 成功 takeover → affordance (confidence: 0.72) | ☐ |
| 15.1 | 失败 takeover → avoid (confidence: 0.66) | ☐ |
| 15.1 | 重复学习 evidenceCount 累积 | ☐ |
| 15.1 | `--no-memory` 跳过 takeover 学习 | ☐ |
| 15.1 | Takeover 学习注入 Planner prompt | ☐ |
| 15.2 | Takeover 提示包含反馈引导语 | ☐ |
| 15.2 | 用户反馈纳入 Memory evidence | ☐ |
| 15.2 | InterventionReason 分类测试通过 | ☐ |
| 15.2 | Takeover 事件记入 trace | ☐ |
| 15.2 | TakeoverMarker Codable round-trip | ☐ |
| 单元测试 | Takeover 相关测试全部通过 | ☐ |
