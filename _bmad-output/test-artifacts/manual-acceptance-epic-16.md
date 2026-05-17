# Epic 16 手工验收文档（Phase 4 — Daemon 模式与运维便利性）

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

## Story 16.1: launchd Daemon 支持

### AC1: daemon install 创建 plist 并注册服务

```bash
# 确保先卸载已有 daemon（如果存在）
.build/debug/axion daemon uninstall 2>/dev/null

# 安装 daemon
.build/debug/axion daemon install --host 127.0.0.1 --port 4242
# 预期输出：
# [axion] Daemon 已安装并启动
# 或类似成功消息

# 验证 plist 文件已创建
cat ~/Library/LaunchAgents/dev.axion.server.plist
# 预期：XML plist 包含：
# - Label: dev.axion.server
# - ProgramArguments: [axion 路径, server, --host, 127.0.0.1, --port, 4242]
# - RunAtLoad: true
# - KeepAlive/Crashed: true
# - ThrottleInterval: 10
# - StandardOutPath: ~/.axion/server.log
# - StandardErrorPath: ~/.axion/server.err.log
```

### AC2: 开机自启验证

```bash
# 验证 RunAtLoad 设置
grep -A 1 "RunAtLoad" ~/Library/LaunchAgents/dev.axion.server.plist
# 预期：<true/>
```

### AC3: 崩溃自动重启

```bash
# 验证 KeepAlive 和 ThrottleInterval
grep -A 3 "KeepAlive\|ThrottleInterval" ~/Library/LaunchAgents/dev.axion.server.plist
# 预期：
# KeepAlive → Crashed: true
# ThrottleInterval: 10

# 手动测试崩溃重启：杀掉 server 进程
DAEMON_PID=$(pgrep -f "axion server" | head -1)
if [ -n "$DAEMON_PID" ]; then
  echo "杀死进程 PID: $DAEMON_PID"
  kill $DAEMON_PID
  sleep 12
  # 验证进程已重启
  NEW_PID=$(pgrep -f "axion server" | head -1)
  echo "新进程 PID: $NEW_PID"
  # 预期：NEW_PID 不为空，且不同于 DAEMON_PID
fi
```

### AC4: daemon status 显示状态

```bash
.build/debug/axion daemon status
# 预期输出：
# 状态: running
# PID: <数字>
# 端口: 4242
# Plist: ~/Library/LaunchAgents/dev.axion.server.plist
```

### AC5: daemon uninstall 停止并清理

```bash
.build/debug/axion daemon uninstall
# 预期输出：
# [axion] Daemon 已停止并卸载

# 验证 plist 已删除
ls ~/Library/LaunchAgents/dev.axion.server.plist 2>/dev/null
# 预期：文件不存在

# 验证进程已停止
pgrep -f "axion server" || echo "进程已停止"
```

### AC6: --keep-logs 选项

```bash
# 先安装
.build/debug/axion daemon install --port 4242
sleep 2

# 卸载并保留日志
.build/debug/axion daemon uninstall --keep-logs
# 预期：plist 删除但日志保留

# 验证日志存在
ls -la ~/.axion/server.log ~/.axion/server.err.log 2>/dev/null
# 预期：日志文件存在

# 清理日志
rm -f ~/.axion/server.log ~/.axion/server.err.log
```

### AC7: auth-key 环境变量传递

```bash
# 安装带认证的 daemon
.build/debug/axion daemon install --port 4242 --auth-key my-secret-key
sleep 2

# 验证 plist 包含环境变量
grep -A 2 "EnvironmentVariables\|AXION_AUTH_KEY" ~/Library/LaunchAgents/dev.axion.server.plist
# 预期：<key>AXION_AUTH_KEY</key> <string>my-secret-key</string>

# 验证 server 受认证保护
curl -s -o /dev/null -w "%{http_code}" http://localhost:4242/v1/capabilities
# 预期：401

curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer my-secret-key" http://localhost:4242/v1/capabilities
# 预期：200

# 清理
.build/debug/axion daemon uninstall
```

### AC8: 日志文件路径

```bash
.build/debug/axion daemon install --port 4242
sleep 3

# 验证日志写入
ls -la ~/.axion/server.log ~/.axion/server.err.log
# 预期：两个文件存在且非空

# 查看日志内容
tail -5 ~/.axion/server.log
# 预期：包含 server 启动日志

tail -5 ~/.axion/server.err.log || echo "错误日志为空（正常）"

# 清理
.build/debug/axion daemon uninstall
rm -f ~/.axion/server.log ~/.axion/server.err.log
```

---

## Story 16.2: API Server 持久化运行恢复

### AC1: 运行状态持久化写入

```bash
# 启动 server
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 2

# 提交任务
RESP=$(curl -s -X POST http://localhost:4242/v1/runs \
  -H "Content-Type: application/json" \
  -d '{"task":"打开计算器"}')
RUN_ID=$(echo "$RESP" | /opt/homebrew/bin/python3 -c "import json,sys; print(json.load(sys.stdin)['run_id'])")
echo "Run ID: $RUN_ID"

# 等待一下让任务开始运行
sleep 2

# 验证持久化文件已创建
ls ~/.axion/api-runs/$RUN_ID/api-output.json 2>/dev/null
# 预期：文件存在

# 查看内容
cat ~/.axion/api-runs/$RUN_ID/api-output.json | /opt/homebrew/bin/python3 -m json.tool | head -20
# 预期：TrackedRun JSON，包含 run_id、task、status 等

# 等待任务完成
sleep 10
kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null
```

### AC2: SSE 事件持久化

```bash
# 检查事件文件
ls ~/.axion/api-runs/$RUN_ID/api-events.jsonl 2>/dev/null
# 预期：文件存在

# 查看事件内容
cat ~/.axion/api-runs/$RUN_ID/api-events.jsonl | /opt/homebrew/bin/python3 -c "
import json, sys
for line in sys.stdin:
    try:
        event = json.loads(line.strip())
        print(f'event_type: {event.get(\"event_type\", \"?\")}')
    except: pass
" | head -10
# 预期：包含 step_started, step_completed, run_completed 等事件
```

### AC3: Server 启动时加载持久化记录

```bash
# 重新启动 server（不清理持久化文件）
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 3

# 查询之前的 run
curl -s http://localhost:4242/v1/runs | /opt/homebrew/bin/python3 -c "
import json, sys
runs = json.load(sys.stdin)
print(f'已恢复 {len(runs)} 个任务')
for r in runs:
    print(f'  {r[\"run_id\"]}: {r[\"status\"]}')
"
# 预期：之前的任务记录被加载，状态可能为 completed 或 failed
```

### AC4: 运行中任务自动标记为 failed

```bash
# 提交一个任务
RESP=$(curl -s -X POST http://localhost:4242/v1/runs \
  -H "Content-Type: application/json" \
  -d '{"task":"打开计算器然后打开文本编辑器然后打开备忘录"}')
RUN_ID=$(echo "$RESP" | /opt/homebrew/bin/python3 -c "import json,sys; print(json.load(sys.stdin)['run_id'])")
echo "Running Run ID: $RUN_ID"

# 等待任务开始运行
sleep 2

# 检查任务状态
curl -s http://localhost:4242/v1/runs/$RUN_ID | /opt/homebrew/bin/python3 -c "
import json, sys
r = json.load(sys.stdin)
print(f'status: {r[\"status\"]}')"

# 强制杀掉 server（模拟崩溃）
kill -9 $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null
sleep 1

# 重新启动 server
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 3

# 检查被中断的任务状态
curl -s http://localhost:4242/v1/runs/$RUN_ID | /opt/homebrew/bin/python3 -c "
import json, sys
r = json.load(sys.stdin)
print(f'status: {r[\"status\"]}')
print(f'error: {r.get(\"error\", \"none\")}')
"
# 预期：status = "failed", error 包含 "server interrupted"

kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null
```

### AC5: intervention_needed 状态保持

```bash
# 注：此 AC 验证 intervention_needed 状态的任务在恢复后保持不变
# 手动创建一个 intervention_needed 状态的持久化记录来测试

# 创建测试数据目录
TEST_RUN_ID="test-intervention-$(date +%s)"
mkdir -p ~/.axion/api-runs/$TEST_RUN_ID

# 写入 intervention_needed 状态的 TrackedRun
cat > ~/.axion/api-runs/$TEST_RUN_ID/api-output.json << 'EOF'
{
  "runId": "PLACEHOLDER",
  "task": "测试 intervention",
  "status": "intervention_needed",
  "schemaVersion": 1,
  "ok": false,
  "live": true,
  "allowForeground": false,
  "startedAt": "2026-05-17T10:00:00Z",
  "intervention": {
    "reason": "需要用户手动操作",
    "availableActions": ["resume", "abort"],
    "blockingIssue": "登录对话框"
  }
}
EOF

# 替换 runId
/opt/homebrew/bin/python3 -c "
import json
with open('$HOME/.axion/api-runs/$TEST_RUN_ID/api-output.json') as f:
    data = json.load(f)
data['runId'] = '$TEST_RUN_ID'
with open('$HOME/.axion/api-runs/$TEST_RUN_ID/api-output.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# 启动 server
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 3

# 验证 intervention_needed 状态保持
curl -s http://localhost:4242/v1/runs/$TEST_RUN_ID | /opt/homebrew/bin/python3 -c "
import json, sys
r = json.load(sys.stdin)
print(f'status: {r[\"status\"]}')
assert r['status'] == 'intervention_needed', f'Expected intervention_needed, got {r[\"status\"]}'
print('✓ intervention_needed 状态正确保持')
"

kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null

# 清理测试数据
rm -rf ~/.axion/api-runs/$TEST_RUN_ID
```

### AC6: 持久化失败不阻塞主流程

```bash
# 通过单元测试验证
swift test --filter "AxionCLITests.API.RunPersistenceServiceTests.persistFailure" 2>&1 | tail -3
# 预期：测试通过
```

### AC7: SSE 历史事件重放

```bash
# 创建带事件的测试 run
TEST_RUN_ID="test-replay-$(date +%s)"
mkdir -p ~/.axion/api-runs/$TEST_RUN_ID

# 写入 TrackedRun
cat > ~/.axion/api-runs/$TEST_RUN_ID/api-output.json << 'EOF'
{
  "runId": "PLACEHOLDER",
  "task": "测试 SSE replay",
  "status": "completed",
  "schemaVersion": 1,
  "ok": true,
  "live": true,
  "allowForeground": false,
  "startedAt": "2026-05-17T10:00:00Z",
  "endedAt": "2026-05-17T10:01:00Z",
  "result": { "kind": "confirmation", "title": "完成", "body": "操作成功", "createdAt": "2026-05-17T10:01:00Z" }
}
EOF

# 写入 SSE 事件
cat > ~/.axion/api-runs/$TEST_RUN_ID/api-events.jsonl << 'EOF'
{"event_type":"step_started","step_index":0,"step_description":"打开计算器","timestamp":"2026-05-17T10:00:10Z"}
{"event_type":"step_completed","step_index":0,"success":true,"timestamp":"2026-05-17T10:00:30Z"}
{"event_type":"run_completed","status":"completed","timestamp":"2026-05-17T10:01:00Z"}
EOF

# 替换 runId
/opt/homebrew/bin/python3 -c "
import json
with open('$HOME/.axion/api-runs/$TEST_RUN_ID/api-output.json') as f:
    data = json.load(f)
data['runId'] = '$TEST_RUN_ID'
with open('$HOME/.axion/api-runs/$TEST_RUN_ID/api-output.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# 启动 server
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 3

# 连接 SSE 并查看历史事件重放
curl -sN http://localhost:4242/v1/runs/$TEST_RUN_ID/events?timeout=3 2>&1 | head -20
# 预期：看到历史事件重放（step_started, step_completed, run_completed）

kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null

# 清理
rm -rf ~/.axion/api-runs/$TEST_RUN_ID
```

---

## 单元测试验证

```bash
swift test --filter "AxionCLITests.Services.DaemonService" \
           --filter "AxionCLITests.API.RunPersistenceService" \
           --filter "AxionCLITests.API.RunTracker" \
           --filter "AxionCLITests.API.EventBroadcaster" \
           --filter "AxionCoreTests"
# 预期：所有测试通过
```

---

## 验收检查清单汇总

| Story | 关键验证点 | 通过 |
|-------|----------|------|
| 16.1 | `daemon install` 创建 plist 并启动 | ☐ |
| 16.1 | plist 包含 RunAtLoad/KeepAlive/ThrottleInterval | ☐ |
| 16.1 | 崩溃后自动重启 | ☐ |
| 16.1 | `daemon status` 显示 PID/端口/状态 | ☐ |
| 16.1 | `daemon uninstall` 清理 plist 和进程 | ☐ |
| 16.1 | `--keep-logs` 保留日志文件 | ☐ |
| 16.1 | `--auth-key` 写入 plist 环境变量 | ☐ |
| 16.1 | 日志写入 ~/.axion/server.log | ☐ |
| 16.2 | api-output.json 在运行中写入 | ☐ |
| 16.2 | api-events.jsonl SSE 事件追加写入 | ☐ |
| 16.2 | server 重启后加载持久化记录 | ☐ |
| 16.2 | 运行中任务恢复为 failed (server interrupted) | ☐ |
| 16.2 | intervention_needed 状态保持 | ☐ |
| 16.2 | SSE 历史事件从磁盘重放 | ☐ |
| 单元测试 | Daemon/Persistence 测试全部通过 | ☐ |
