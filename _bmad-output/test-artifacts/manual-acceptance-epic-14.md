# Epic 14 手工验收文档（Phase 4 — API 规范化与集成友好度）

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

## Story 14.1: StandardTaskOutput 契约升级

### AC1: API 返回 StandardTaskOutput 结构

```bash
# 启动 API server
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 2

# 提交任务
RESP=$(curl -s -X POST http://localhost:4242/v1/runs \
  -H "Content-Type: application/json" \
  -d '{"task":"打开计算器"}')
echo "$RESP" | /opt/homebrew/bin/python3 -m json.tool
# 预期返回字段：
# schema_version: 1
# run_id: "..."
# task: "打开计算器"
# status: "running"
# ok: true
# live: true
# allow_foreground: false
# started_at: "..."
```

### AC2: 查询已完成任务的 StandardTaskOutput

```bash
# 提取 run_id
RUN_ID=$(echo "$RESP" | /opt/homebrew/bin/python3 -c "import json,sys; print(json.load(sys.stdin)['run_id'])")
echo "Run ID: $RUN_ID"

# 等待任务完成
sleep 15

# 查询任务状态
curl -s http://localhost:4242/v1/runs/$RUN_ID | /opt/homebrew/bin/python3 -m json.tool
# 预期：
# status: "completed" 或 "failed"
# result.kind: "answer" 或 "confirmation"
# result.body: 包含操作结果或确认信息
# cost_telemetry: { model_calls, total_tokens, estimated_cost_usd, screenshot_count }
```

### AC3: 列出所有任务

```bash
curl -s http://localhost:4242/v1/runs | /opt/homebrew/bin/python3 -m json.tool | head -30
# 预期：返回数组，每个元素为 StandardTaskOutput 格式
```

### AC4: 8 种 APIRunStatus

```bash
# 验证所有支持的 status 值
curl -s http://localhost:4242/v1/capabilities | /opt/homebrew/bin/python3 -c "
import json, sys
cap = json.load(sys.stdin)
statuses = cap['supported_run_statuses']
print(f'状态数: {len(statuses)}')
for s in statuses:
    print(f'  - {s}')
"
# 预期列出 8 种状态：
# queued, running, intervention_needed, user_takeover, resuming, completed, failed, cancelled
```

### AC5: result.kind 推断

```bash
# 测试 answer 类型（信息获取任务）
curl -s -X POST http://localhost:4242/v1/runs \
  -H "Content-Type: application/json" \
  -d '{"task":"查看当前打开的窗口有哪些"}' | /opt/homebrew/bin/python3 -c "
import json, sys
r = json.load(sys.stdin)
print(f'run_id: {r[\"run_id\"]}, status: {r[\"status\"]}')"

# 测试 confirmation 类型（操作任务）
curl -s -X POST http://localhost:4242/v1/runs \
  -H "Content-Type: application/json" \
  -d '{"task":"打开计算器"}' | /opt/homebrew/bin/python3 -c "
import json, sys
r = json.load(sys.stdin)
print(f'run_id: {r[\"run_id\"]}, status: {r[\"status\"]}')"
```

### 清理 server

```bash
kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null
```

---

## Story 14.2: Capabilities 端点

### AC1: GET /v1/capabilities 返回完整能力描述

```bash
# 启动 server
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 2

curl -s http://localhost:4242/v1/capabilities | /opt/homebrew/bin/python3 -m json.tool
# 预期包含：
# version: Axion 版本号
# supported_run_statuses: 8 种状态数组
# supported_result_kinds: ["answer", "confirmation"]
# available_tools: 工具列表（launch_app, click, type_text 等 20+ 个）
# max_concurrent_runs: 10
# features: ["memory", "takeover", "fast_mode", "skills"]
```

### AC2: Cache-Control 头

```bash
curl -sI http://localhost:4242/v1/capabilities | grep -i cache-control
# 预期：Cache-Control: private, max-age=300
```

### AC3: 认证保护

```bash
# 启动带认证的 server
kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null
.build/debug/axion server --port 4242 --auth-key test-secret-key &
SERVER_PID=$!
sleep 2

# 无认证请求
curl -s -o /dev/null -w "%{http_code}" http://localhost:4242/v1/capabilities
# 预期：401

# 有认证请求
curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer test-secret-key" http://localhost:4242/v1/capabilities
# 预期：200

kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null
```

### AC4: Helper 未连接时仍可返回

```bash
# 不启动 Helper，仅启动 server
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 2

curl -s http://localhost:4242/v1/capabilities | /opt/homebrew/bin/python3 -c "
import json, sys
cap = json.load(sys.stdin)
print(f'version: {cap[\"version\"]}')
print(f'tools count: {len(cap[\"available_tools\"])}')
print(f'features: {cap[\"features\"]}')
"
# 预期：version 和 available_tools 正常返回（静态列表，不依赖 Helper）

kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null
```

---

## Story 14.3: Settings API

### AC1: GET /v1/settings/api-key 返回状态

```bash
# 启动 server
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 2

curl -s http://localhost:4242/v1/settings/api-key | /opt/homebrew/bin/python3 -m json.tool
# 预期：
# {
#   "provider": "anthropic",
#   "available": true/false,
#   "source": "config"/"env"/"missing",
#   "masked_key": "sk-ant-****xxxx" 或 ""
# }
```

### AC2: POST /v1/settings/api-key 保存

```bash
# 保存 API Key
curl -s -X POST http://localhost:4242/v1/settings/api-key \
  -H "Content-Type: application/json" \
  -d '{"api_key":"sk-ant-test-key-1234567890abcdef"}' | /opt/homebrew/bin/python3 -m json.tool
# 预期：
# {
#   "provider": "anthropic",
#   "available": true,
#   "source": "...",
#   "masked_key": "sk-ant-****abcdef"
# }
```

### AC3: DELETE /v1/settings/api-key 清除

```bash
curl -s -X DELETE http://localhost:4242/v1/settings/api-key | /opt/homebrew/bin/python3 -m json.tool
# 预期：
# {
#   "provider": "anthropic",
#   "available": false,
#   "source": "missing"
# }
```

### AC4: masked_key 格式验证

```bash
# 重新设置 key 检查掩码格式
curl -s -X POST http://localhost:4242/v1/settings/api-key \
  -H "Content-Type: application/json" \
  -d '{"api_key":"sk-ant-api03-very-long-key-for-testing-1234"}' | /opt/homebrew/bin/python3 -c "
import json, sys
r = json.load(sys.stdin)
key = r['masked_key']
print(f'masked_key: {key}')
assert '****' in key, '缺少掩码标记'
assert not key.endswith('testing-1234'), '完整 key 不应暴露'
print('✓ 掩码格式正确')
"
```

### AC5: 认证保护

```bash
kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null

# 启动带认证的 server
.build/debug/axion server --port 4242 --auth-key secret123 &
SERVER_PID=$!
sleep 2

# 未认证请求
curl -s -o /dev/null -w "%{http_code}" http://localhost:4242/v1/settings/api-key
# 预期：401

# 有认证请求
curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer secret123" http://localhost:4242/v1/settings/api-key
# 预期：200

kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null
```

### AC6: Doctor 集成

```bash
.build/debug/axion doctor
# 预期：包含 API server 可达性检查（如果 server 在运行）
```

---

## 单元测试验证

```bash
swift test --filter "AxionCLITests.API.StandardTaskOutput" \
           --filter "AxionCLITests.API.RunTracker" \
           --filter "AxionCLITests.API.APITypes" \
           --filter "AxionCLITests.API.AxionAPIRoutes" \
           --filter "AxionCoreTests"
# 预期：所有 API 测试通过
```

---

## 验收检查清单汇总

| Story | 关键验证点 | 通过 |
|-------|----------|------|
| 14.1 | POST /v1/runs 返回 StandardTaskOutput | ☐ |
| 14.1 | GET /v1/runs/{id} 包含 result + cost_telemetry | ☐ |
| 14.1 | supported_run_statuses 包含 8 种状态 | ☐ |
| 14.1 | result.kind 为 answer 或 confirmation | ☐ |
| 14.2 | GET /v1/capabilities 返回 version/tools/features | ☐ |
| 14.2 | Cache-Control: private, max-age=300 | ☐ |
| 14.2 | 认证端点受 AuthMiddleware 保护 | ☐ |
| 14.2 | Helper 未连接时 capabilities 正常返回 | ☐ |
| 14.3 | GET /v1/settings/api-key 返回 masked_key | ☐ |
| 14.3 | POST /v1/settings/api-key 保存并返回掩码 | ☐ |
| 14.3 | DELETE /v1/settings/api-key 清除 key | ☐ |
| 14.3 | masked_key 不暴露完整 key | ☐ |
| 14.3 | Settings API 受认证保护 | ☐ |
| 单元测试 | API 相关测试全部通过 | ☐ |
