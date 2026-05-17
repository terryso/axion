# Epic 13 手工验收文档（Phase 4 — 执行安全与成本控制）

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

## Story 13.1: 桌面级运行锁

### AC1: 首次 live run 获取锁成功

```bash
# 清除可能残留的锁文件
rm -f ~/.axion/run.lock

# 启动一个 live run
.build/debug/axion run "打开计算器" --max-steps 2 &
RUN_PID=$!
sleep 2

# 检查锁文件存在
cat ~/.axion/run.lock | /opt/homebrew/bin/python3 -m json.tool
# 预期：
# {
#   "run_id": "...",
#   "pid": ...,
#   "started_at": "2026-05-17T..."
# }

# 等待 run 完成
wait $RUN_PID 2>/dev/null
```

### AC2: 并发 live run 被拒绝

```bash
# 先启动一个长任务
.build/debug/axion run "打开计算器，然后打开文本编辑器" --max-steps 5 &
RUN_PID=$!
sleep 3

# 在另一个终端尝试运行（或同一终端后台）
.build/debug/axion run "打开备忘录" --max-steps 2
# 预期：输出 "另一个 live run 正在执行" 并退出

# 清理
kill $RUN_PID 2>/dev/null; wait $RUN_PID 2>/dev/null
rm -f ~/.axion/run.lock
```

### AC3: Stale lock 自动清理

```bash
# 手动创建 stale lock（PID 指向不存在的进程）
echo '{"run_id":"test-stale","pid":99999,"started_at":"2026-05-17T00:00:00Z"}' > ~/.axion/run.lock

# 新 run 应能自动清理 stale lock 并正常执行
.build/debug/axion run "打开计算器" --max-steps 2 --dryrun
# 预期：正常运行，不报锁冲突

# 清理
rm -f ~/.axion/run.lock
```

### AC4: dryrun 不加锁

```bash
# dryrun 模式不应创建锁文件
rm -f ~/.axion/run.lock
.build/debug/axion run "打开计算器" --max-steps 2 --dryrun

# 检查锁文件不存在
ls ~/.axion/run.lock 2>/dev/null
# 预期：文件不存在
```

### AC5: API server 409 Conflict

```bash
# 启动 API server
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 2

# 提交一个任务
curl -s -X POST http://localhost:4242/v1/runs \
  -H "Content-Type: application/json" \
  -d '{"task":"打开计算器"}' | /opt/homebrew/bin/python3 -m json.tool

# 立即提交第二个任务
curl -s -X POST http://localhost:4242/v1/runs \
  -H "Content-Type: application/json" \
  -d '{"task":"打开文本编辑器"}' | /opt/homebrew/bin/python3 -m json.tool
# 预期：返回 409 Conflict，包含当前运行中的 run_id

# 清理
kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null
```

### AC6: Doctor stale lock 检查

```bash
# 创建 stale lock
echo '{"run_id":"test-stale","pid":99999,"started_at":"2026-05-17T00:00:00Z"}' > ~/.axion/run.lock

.build/debug/axion doctor
# 预期输出包含：
# [FAIL] Stale run.lock（进程已退出）— 建议清理
# 或类似提示

# 清理
rm -f ~/.axion/run.lock
```

---

## Story 13.2: 视觉增量检查

### AC1: --no-visual-delta 标志可用

```bash
# 确认 flag 已注册
.build/debug/axion run --help | grep "no-visual-delta"
# 预期：显示 --no-visual-delta 选项说明
```

### AC2: 视觉增量检查正常工作

```bash
# 运行一个任务，观察 verbose 输出
.build/debug/axion run "打开计算器" --max-steps 3 --verbose 2>&1 | grep -i "visual\|delta\|verifier_skipped" || echo "无 visual delta 相关日志（可能未触发截图比较）"
# 预期：如果任务中有截图步骤，可见 delta 相关日志
```

### AC3: 禁用视觉增量检查

```bash
# 使用 --no-visual-delta 禁用
.build/debug/axion run "打开计算器" --max-steps 2 --no-visual-delta
# 预期：正常运行，无 delta 相关日志
```

---

## Story 13.3: 精细预算控制与成本遥测

### AC1: --max-model-calls 限制

```bash
# 限制模型调用次数为 2
.build/debug/axion run "打开计算器，然后打开文本编辑器，然后打开备忘录" --max-model-calls 2
# 预期：达到上限后停止，输出 "已达到模型调用上限（2次）"
```

### AC2: --max-screenshots 限制

```bash
# 限制截图次数
.build/debug/axion run "打开计算器" --max-screenshots 1 --max-steps 5
# 预期：截图达到上限后，后续使用最后截图或跳过验证
```

### AC3: 成本摘要输出

```bash
# 运行一个任务并观察结尾输出
.build/debug/axion run "打开计算器" --max-steps 3 2>&1 | tail -5
# 预期结尾包含类似：
# LLM 调用: N次, Tokens: ..., 预估成本: $X.XX, 截图: N次
```

### AC4: Config 文件支持预算配置

```bash
# 检查 config 是否支持新字段
cat ~/.axion/config.json | /opt/homebrew/bin/python3 -c "
import json, sys
c = json.load(sys.stdin)
print(f'maxModelCalls: {c.get(\"max_model_calls\", \"(not set)\")}')
print(f'maxScreenshots: {c.get(\"max_screenshots\", \"(not set)\")}')
"
# 预期：字段可识别（即使未设置）
```

### AC5: API 响应包含 cost_telemetry

```bash
# 启动 server 并提交任务
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 2

# 提交任务
RESP=$(curl -s -X POST http://localhost:4242/v1/runs \
  -H "Content-Type: application/json" \
  -d '{"task":"打开计算器"}')
RUN_ID=$(echo $RESP | /opt/homebrew/bin/python3 -c "import json,sys; print(json.load(sys.stdin)['run_id'])")
echo "Run ID: $RUN_ID"

# 等待任务完成
sleep 15

# 查询任务状态
curl -s http://localhost:4242/v1/runs/$RUN_ID | /opt/homebrew/bin/python3 -m json.tool
# 预期：包含 cost_telemetry 字段（model_calls, total_tokens, estimated_cost_usd, screenshot_count）

# 清理
kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null
```

---

## Story 13.4: 桌面活动检测与学习保护

### AC1: 活动检测在 shared-seat 模式下工作

```bash
# 运行任务（shared-seat 模式为默认，未使用 --allow-foreground）
# 运行过程中手动移动鼠标或切换应用
.build/debug/axion run "打开计算器" --max-steps 3 2>&1 | grep -i "外部桌面操作\|外部活动" || echo "无外部活动检测日志"
# 预期：如果运行期间手动操作了桌面，出现警告：
# [axion] 检测到外部桌面操作，本次运行的经验不会被记忆
```

### AC2: Memory 提取被跳过

```bash
# 如果运行中检测到外部活动，验证 Memory 未写入
# 运行前后对比 memory list
.build/debug/axion memory list
# 记录当前记忆条数

# 运行任务期间操作桌面，触发检测
# 完成后再次查看
.build/debug/axion memory list
# 预期：如果触发了外部活动检测，本次运行的记忆不会被新增
```

### AC3: --allow-foreground 模式不检测

```bash
# foreground 模式不创建 SeatActivityMonitor
.build/debug/axion run "打开计算器" --max-steps 2 --allow-foreground 2>&1 | grep -i "外部" || echo "无外部活动检测（符合预期）"
# 预期：无外部活动检测相关输出
```

---

## 单元测试验证

```bash
swift test --filter "AxionCLITests.Services.RunLockService" \
           --filter "AxionCLITests.Verifier.VisualDeltaChecker" \
           --filter "AxionCLITests.Services.CostTracker" \
           --filter "AxionCLITests.Services.SeatActivityMonitor" \
           --filter "AxionCoreTests"
# 预期：所有测试通过
```

---

## 验收检查清单汇总

| Story | 关键验证点 | 通过 |
|-------|----------|------|
| 13.1 | `run.lock` 文件在运行时创建 | ☐ |
| 13.1 | 并发 run 被拒绝 + 错误提示 | ☐ |
| 13.1 | Stale lock 自动清理 | ☐ |
| 13.1 | dryrun 不创建锁文件 | ☐ |
| 13.1 | API server 返回 409 Conflict | ☐ |
| 13.1 | `axion doctor` 检测 stale lock | ☐ |
| 13.2 | `--no-visual-delta` flag 可用 | ☐ |
| 13.2 | 正常运行时 visual delta 检查工作 | ☐ |
| 13.3 | `--max-model-calls` 达上限后停止 | ☐ |
| 13.3 | `--max-screenshots` 达上限后跳过 | ☐ |
| 13.3 | 成本摘要输出（LLM 调用/Tokens/费用/截图） | ☐ |
| 13.3 | API 响应包含 cost_telemetry | ☐ |
| 13.4 | 外部活动检测输出警告 | ☐ |
| 13.4 | 检测后 Memory 提取被跳过 | ☐ |
| 13.4 | `--allow-foreground` 不检测 | ☐ |
| 单元测试 | RunLock/VisualDelta/CostTracker/SeatActivity 测试全部通过 | ☐ |
