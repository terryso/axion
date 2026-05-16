# Epic 4–7 手工验收文档

> 生成日期：2026-05-14
> 分支：feature/phase2-growth-features
> 验收环境：macOS 14+，已通过 `axion setup` 完成首次配置

---

## 前置准备

```bash
# 1. 确认当前分支和编译状态
cd /Users/nick/CascadeProjects/axion
git branch --show-current
swift build

# 2. 确认 axion 可执行
.build/debug/axion --version
```

---

## Epic 4: 本地 App Memory — 跨任务学习系统

### 4.1 Story 4.1 — SDK MemoryStore 集成与 App Memory 提取

**AC1: 任务完成后自动提取 App 操作摘要**

```bash
# 运行一次简单任务（需要 Accessibility 和屏幕录制权限）
.build/debug/axion run "打开计算器" --fast
```

验收要点：
- 任务完成后检查 Memory 目录是否创建
- 应生成以 App bundle identifier 命名的 domain 文件

```bash
# 检查 Memory 目录
ls -la ~/.axion/memory/
# 预期：看到 JSON 文件（如 com.apple.calculator.json）
```

**AC2: Memory 按 App domain 组织**

```bash
# 查看 domain 文件内容
cat ~/.axion/memory/com.apple.calculator.json | /opt/homebrew/bin/python3 -m json.tool
# 预期：JSON 数组，每个元素包含 id、content、tags、createdAt 字段
# content 中应包含 App 名称、任务描述、工具序列等信息
```

**AC3: 自动清理过期记录**
> 此项为 SDK 内置行为（maxAge=30天），无法通过手工操作在短期内验证。
> 可通过单元测试覆盖（`MemoryCleanupServiceTests`）。

**AC4: 损坏 Memory 不阻塞任务**

```bash
# 手动创建一个损坏的 domain 文件
echo "not valid json" > ~/.axion/memory/com.test.corrupt.json

# 再次运行任务，应正常完成不被阻塞
.build/debug/axion run "打开计算器" --fast

# 清理测试数据
rm ~/.axion/memory/com.test.corrupt.json
```

**AC5: `axion doctor` 报告 Memory 状态**

```bash
.build/debug/axion doctor
# 预期输出中包含类似：
# [OK] Memory: 1 domains, N entries
# 或（首次使用时）：
# [OK] Memory: 未使用（首次运行后自动创建）
```

---

### 4.2 Story 4.2 — App Profile 自动积累

**AC1: 成功操作后提取 AX tree 结构特征**

```bash
# 运行涉及 AX 操作的任务
.build/debug/axion run "打开计算器，计算 17 乘以 23"

# 检查 Memory 中是否记录了 AX 特征
cat ~/.axion/memory/com.apple.calculator.json | /opt/homebrew/bin/python3 -c "
import json, sys
data = json.load(sys.stdin)
for entry in data:
    if 'AX' in entry.get('content', ''):
        print('AX特征已记录:')
        print(entry['content'][:500])
        break
else:
    print('WARNING: 未找到 AX 特征记录')
"
```

验收要点：
- content 中应包含 `AX特征:` 字段
- 应包含关键控件信息（如 AXButton 角色和标题）

**AC2: 识别高频操作路径**
> 需要同一 App 积累多次运行记录。可通过运行 3 次以上同 App 任务后检查 Profile 条目。

```bash
# 运行多次同 App 任务
.build/debug/axion run "打开计算器" --fast
.build/debug/axion run "打开计算器" --fast
.build/debug/axion run "打开计算器" --fast

# 检查是否有 Profile 条目生成
cat ~/.axion/memory/com.apple.calculator.json | /opt/homebrew/bin/python3 -c "
import json, sys
data = json.load(sys.stdin)
profiles = [e for e in data if 'profile' in e.get('tags', [])]
print(f'Profile 条目数: {len(profiles)}')
for p in profiles:
    print('---')
    print(p['content'][:600])
"
```

**AC3: 标记失败经验**
> 需要触发重规划场景。可通过一个容易部分失败的任务来验证。

```bash
# 检查 Memory 中是否有失败标记
cat ~/.axion/memory/com.apple.calculator.json | /opt/homebrew/bin/python3 -c "
import json, sys
data = json.load(sys.stdin)
failures = [e for e in data if 'failure' in e.get('tags', [])]
print(f'失败记录数: {len(failures)}')
for f in failures:
    if '失败' in f.get('content', ''):
        print('---')
        print(f['content'][:400])
"
```

**AC4: 自动标记已熟悉 App（>= 3 次成功）**

```bash
# 检查 familiar 标记
cat ~/.axion/memory/com.apple.calculator.json | /opt/homebrew/bin/python3 -c "
import json, sys
data = json.load(sys.stdin)
familiar = [e for e in data if 'familiar' in e.get('tags', [])]
print(f'Familiar 标记数: {len(familiar)}')
if familiar:
    print('App 已被标记为已熟悉')
else:
    print('App 尚未达到熟悉阈值（需要 >= 3 次成功操作）')
"
```

---

### 4.3 Story 4.3 — Memory 增强规划

**AC1: 注入 App Memory 上下文到 Planner prompt**

```bash
# 运行带 verbose 的任务，观察 system prompt 中是否注入了 Memory 上下文
.build/debug/axion run "打开计算器，计算 5+3" --verbose 2>&1 | head -50
# 预期：在 trace 或 verbose 输出中可看到 "# App Memory Context" section
```

**AC2: 标注已知不可靠操作路径**
> 同 AC1 验证。在 Memory 上下文中应包含 "已知失败（避免重复）" section。

**AC3: 熟悉 App 使用紧凑规划策略**
> 熟悉 App 在 Memory 上下文中会有 "策略建议: 此 App 已熟悉，可使用紧凑规划" 指令。

**AC4: `--no-memory` 标志禁用 Memory 注入**

```bash
# 运行时禁用 Memory
.build/debug/axion run "打开计算器" --fast --no-memory --verbose 2>&1 | head -50
# 预期：system prompt 中不包含 "# App Memory Context" section
```

**AC5: `axion memory list` 命令**

```bash
.build/debug/axion memory list
# 预期输出格式：
# App Memory:
#   com.apple.calculator — N entries, last used YYYY-MM-DD
# Total: X apps, Y entries
```

**AC6: `axion memory clear --app` 命令**

```bash
# 先查看当前 Memory
.build/debug/axion memory list

# 清除特定 App Memory（用一个测试 domain）
# 注意：这会删除该 App 的所有 Memory 数据
.build/debug/axion memory clear --app com.apple.calculator

# 再次查看，确认已清除
.build/debug/axion memory list
# 预期：com.apple.calculator 不再出现
```

---

## Epic 5: HTTP API Server — 外部集成服务

### 5.1 Story 5.1 — HTTP API 基础与任务管理

**AC1: Server 启动与端口监听**

```bash
# 启动 server（后台运行）
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 2

# 预期终端输出：
# Axion API server running on port 4242
```

**AC6: Health check 端点**

```bash
curl -s http://127.0.0.1:4242/v1/health | /opt/homebrew/bin/python3 -m json.tool
# 预期：
# {
#     "status": "ok",
#     "version": "x.y.z"
# }
```

**AC2: 提交异步任务**

```bash
curl -s -X POST http://127.0.0.1:4242/v1/runs \
  -H "Content-Type: application/json" \
  -d '{"task": "打开计算器"}' | /opt/homebrew/bin/python3 -m json.tool
# 预期：
# {
#     "run_id": "20260514-xxxxxx",
#     "status": "running"
# }
# 记下 run_id 用于后续查询
```

**AC3: 查询运行中任务状态**

```bash
# 用上一步获得的 run_id 替换 {RUN_ID}
RUN_ID="替换为实际的run_id"
curl -s http://127.0.0.1:4242/v1/runs/$RUN_ID | /opt/homebrew/bin/python3 -m json.tool
# 预期：包含 status、task、steps 等字段
```

**AC4: 查询已完成任务结果**

```bash
# 等待任务完成后查询
sleep 15
curl -s http://127.0.0.1:4242/v1/runs/$RUN_ID | /opt/homebrew/bin/python3 -m json.tool
# 预期：status 为 "done" 或 "failed"，包含 total_steps、duration_ms 等
```

**AC5: 请求参数校验**

```bash
curl -s -X POST http://127.0.0.1:4242/v1/runs \
  -H "Content-Type: application/json" \
  -d '{}' | /opt/homebrew/bin/python3 -m json.tool
# 预期：
# {
#     "error": "missing_task",
#     "message": "..."
# }
# HTTP 状态码应为 400
```

**查询不存在的 runId**

```bash
curl -s http://127.0.0.1:4242/v1/runs/nonexistent-id | /opt/homebrew/bin/python3 -m json.tool
# 预期：
# {
#     "error": "run_not_found",
#     "message": "..."
# }
# HTTP 状态码应为 404
```

```bash
# 测试完毕后关闭 server
kill $SERVER_PID
```

---

### 5.2 Story 5.2 — SSE 事件流实时进度

```bash
# 启动 server
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 2
```

**AC1: SSE 连接与实时事件推送**

```bash
# 提交一个任务并获取 run_id
RUN_ID=$(curl -s -X POST http://127.0.0.1:4242/v1/runs \
  -H "Content-Type: application/json" \
  -d '{"task": "打开计算器"}' | /opt/homebrew/bin/python3 -c "import json,sys; print(json.load(sys.stdin)['run_id'])")
echo "Run ID: $RUN_ID"

# 在另一个终端窗口启动 SSE 监听（或使用 timeout 限制）
timeout 30 curl -sN http://127.0.0.1:4242/v1/runs/$RUN_ID/events
# 预期输出格式（SSE 事件流）：
# event: step_started
# data: {"step_index":0,"tool":"launch_app"}
# id: 1
#
# event: step_completed
# data: {"step_index":0,"tool":"launch_app","purpose":"...","success":true,"duration_ms":150}
# id: 2
#
# event: run_completed
# data: {"run_id":"...","final_status":"done","total_steps":N,"duration_ms":X,"replan_count":0}
# id: N
```

**AC4: 已完成任务的重放**

```bash
# 任务完成后再次连接 SSE（应立即收到 run_completed 事件然后关闭）
timeout 10 curl -sN http://127.0.0.1:4242/v1/runs/$RUN_ID/events
# 预期：立即收到 run_completed 事件（重放），然后连接关闭
```

**AC5: 多客户端并发订阅**

```bash
# 提交新任务
RUN_ID2=$(curl -s -X POST http://127.0.0.1:4242/v1/runs \
  -H "Content-Type: application/json" \
  -d '{"task": "打开计算器"}' | /opt/homebrew/bin/python3 -c "import json,sys; print(json.load(sys.stdin)['run_id'])")

# 同时启动两个 SSE 客户端
timeout 30 curl -sN http://127.0.0.1:4242/v1/runs/$RUN_ID2/events > /tmp/sse_client1.txt &
timeout 30 curl -sN http://127.0.0.1:4242/v1/runs/$RUN_ID2/events > /tmp/sse_client2.txt &
sleep 20

# 对比两个客户端收到的事件
echo "Client 1 events:"
cat /tmp/sse_client1.txt | grep "^event:"
echo "---"
echo "Client 2 events:"
cat /tmp/sse_client2.txt | grep "^event:"
# 预期：两个客户端收到相同的事件序列
```

```bash
kill $SERVER_PID
```

---

### 5.3 Story 5.3 — Server 命令与 API 认证

**AC1: Bearer Token 认证 — 未认证请求被拒绝**

```bash
.build/debug/axion server --port 4242 --auth-key mysecret &
SERVER_PID=$!
sleep 2

curl -s http://127.0.0.1:4242/v1/health | /opt/homebrew/bin/python3 -m json.tool
# 预期：health 端点无需认证，返回 {"status":"ok","version":"..."}

curl -s http://127.0.0.1:4242/v1/runs | /opt/homebrew/bin/python3 -m json.tool
# 预期：401 未认证错误
```

**AC2: 合法认证请求通过**

```bash
curl -s -H "Authorization: Bearer mysecret" \
  http://127.0.0.1:4242/v1/runs | /opt/homebrew/bin/python3 -m json.tool
# 预期：正常返回（空数组或任务列表）

curl -s -X POST http://127.0.0.1:4242/v1/runs \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer mysecret" \
  -d '{"task": "打开计算器"}' | /opt/homebrew/bin/python3 -m json.tool
# 预期：正常提交任务
```

**AC4: 并发任务限制**

```bash
kill $SERVER_PID
sleep 1

# 启动限制并发为 2 的 server
.build/debug/axion server --port 4242 --auth-key mysecret --max-concurrent 2 &
SERVER_PID=$!
sleep 2

# 快速提交 3 个任务
for i in 1 2 3; do
  echo "--- 提交任务 $i ---"
  curl -s -X POST http://127.0.0.1:4242/v1/runs \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer mysecret" \
    -d "{\"task\": \"打开计算器\"}" | /opt/homebrew/bin/python3 -m json.tool
done
# 预期：前两个任务 status=running，第三个任务 status=queued, position=1
```

**AC5: 默认绑定 localhost**

```bash
kill $SERVER_PID
sleep 1

# 启动默认配置 server
.build/debug/axion server --port 4242 &
SERVER_PID=$!
sleep 2

# 验证只监听 localhost
lsof -i :4242 | head -5
# 预期：显示绑定在 127.0.0.1:4242（或 localhost:4242）
```

**AC3: 优雅关闭**

```bash
# 提交一个长任务
curl -s -X POST http://127.0.0.1:4242/v1/runs \
  -H "Content-Type: application/json" \
  -d '{"task": "打开 TextEdit，输入一段很长的文字"}' &

# 立即发送 SIGINT（模拟 Ctrl-C）
sleep 1
kill -INT $SERVER_PID
# 预期：server 等待运行中的任务完成（最多 30 秒），然后退出
```

```bash
# 确保清理
kill $SERVER_PID 2>/dev/null
```

---

## Epic 6: MCP Server Mode — Agent 协作

### 6.1 Story 6.1 — 通过 SDK AgentMCPServer 暴露 Axion

**AC1: MCP initialize 响应**

```bash
# 使用 JSON-RPC 手动测试 MCP 握手
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | .build/debug/axion mcp 2>/dev/null
# 预期：输出 MCP initialize 响应 JSON，包含 serverInfo 和 capabilities
```

**AC2: tools/list 返回工具列表**

```bash
# 先 initialize 再 tools/list（用多行输入）
(echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
sleep 1
echo '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
sleep 1) | .build/debug/axion mcp 2>/dev/null
# 预期：返回工具列表，包含 run_task、query_task_status、list_apps 等工具
```

**AC5: 优雅退出（stdin EOF）**

```bash
# 发送 EOF 后 server 应优雅退出
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | .build/debug/axion mcp 2>/tmp/mcp_stderr.txt
# 预期：进程正常退出，stderr 中有启动和停止日志
cat /tmp/mcp_stderr.txt
```

---

### 6.2 Story 6.2 — `axion mcp` 命令与外部 Agent 集成验证

**AC3: --help 用法说明**

```bash
.build/debug/axion mcp --help
# 预期：显示 MCP server 模式用法说明，包含 --verbose 选项
# 可能包含 Claude Code 配置示例
```

**AC4: stdout 纯净**

```bash
# 启动 MCP server，验证 stdout 仅包含 MCP 协议内容
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' \
  | .build/debug/axion mcp 2>/tmp/mcp_stderr.txt > /tmp/mcp_stdout.txt

echo "=== stdout 内容 ==="
cat /tmp/mcp_stdout.txt
echo "=== stderr 内容 ==="
cat /tmp/mcp_stderr.txt

# 预期：
# stdout: 仅 MCP JSON-RPC 响应
# stderr: 启动/停止日志信息
```

**AC1 & AC2: Claude Code MCP 配置（手动集成验证）**

> 如果使用 Claude Code，可在 MCP 配置中添加：
> ```json
> {
>   "mcpServers": {
>     "axion": {
>       "command": "/Users/nick/CascadeProjects/axion/.build/debug/axion",
>       "args": ["mcp"]
>     }
>   }
> }
> ```
> 然后在 Claude Code 中测试调用 Axion 工具。

---

## Epic 7: 执行增强 — Takeover 与 Fast Mode

### 7.1 Story 7.1 — 基于 SDK Pause Protocol 的用户接管机制

**AC1: Takeover 暂停触发**

> Takeover 需要任务受阻场景。可通过指定一个困难或不可能自动完成的任务触发。

```bash
# 运行一个可能触发 blocked/pause 的任务（如操作一个不存在的 UI 元素）
.build/debug/axion run "在计算器中找到并点击一个不存在的神秘按钮"
# 如果任务受阻，预期终端显示类似：
# ⏸ 任务受阻：{阻塞原因}
# 手动完成后按 Enter 继续，或输入 'skip' 跳过，或输入 'abort' 终止
```

**AC2: 用户恢复执行（按 Enter）**

```bash
# 当出现 takeover 提示时：
# 1. 手动在桌面上完成操作
# 2. 回到终端按 Enter
# 预期：任务恢复执行，Agent 继续后续步骤
```

**AC3: 用户跳过步骤（输入 skip）**

```bash
# 当出现 takeover 提示时：
# 输入 skip 然后按 Enter
# 预期：当前步骤标记为 skipped，继续后续步骤
```

**AC4: 用户终止任务（输入 abort）**

```bash
# 当出现 takeover 提示时：
# 输入 abort 然后按 Enter
# 预期：任务以 cancelled 状态结束，显示已完成步骤摘要
```

**AC7: JSON 输出模式兼容**

```bash
# 在 JSON 模式下触发 takeover
.build/debug/axion run "在计算器中点击不存在的按钮" --json
# 预期：paused 事件以 JSON 结构输出到 stdout
```

---

### 7.2 Story 7.2 — `--fast` 模式

**AC1: `--fast` 标志注册**

```bash
.build/debug/axion run --help
# 预期：显示 --fast 选项，说明 "快速模式：简化规划，减少 LLM 调用"
```

**AC2: 轻量规划策略**

```bash
# 运行 fast 模式任务
.build/debug/axion run "打开计算器" --fast
# 预期：
# - 启动更快（减少 LLM 调用）
# - 规划步骤较少（1-3 步）
# - 不请求截图和完整 AX tree 作为输入
```

**AC3: 简化验证**

```bash
# 观察 fast 模式执行过程
# 预期：每步执行后只检查 ToolResult.isError，不额外调用 screenshot
```

**AC4: 失败不重规划**

```bash
# 在 fast 模式下运行一个可能失败的任务
.build/debug/axion run "在桌面上找到一个不存在的应用并点击" --fast
# 预期：失败后不触发重规划，直接报告失败
# 输出包含建议："建议去掉 --fast 重新尝试"
```

**AC5: 完成提示**

```bash
.build/debug/axion run "打开计算器" --fast
# 预期成功输出：
# Fast mode 完成。N 步，耗时 X 秒。
# 如需更精确执行，可去掉 --fast 重试
```

**AC7: JSON 模式兼容**

```bash
.build/debug/axion run "打开计算器" --fast --json 2>/dev/null | /opt/homebrew/bin/python3 -m json.tool
# 预期：JSON 输出包含 "mode": "fast" 字段
```

**AC6: 性能对比（可选）**

```bash
# 标准模式（记录时间和 trace 中的 LLM 调用次数）
time .build/debug/axion run "打开计算器，计算 1+1"

# Fast 模式
time .build/debug/axion run "打开计算器，计算 1+1" --fast

# 对比执行时间和 LLM 调用次数
# 预期：fast 模式显著更快（LLM 调用减少 50%+）
```

---

## 单元测试验证

在手工验收之外，确认所有单元测试通过：

```bash
swift test --filter "AxionHelperTests.Tools" \
           --filter "AxionHelperTests.Models" \
           --filter "AxionHelperTests.MCP" \
           --filter "AxionHelperTests.Services" \
           --filter "AxionCoreTests" \
           --filter "AxionCLITests"
# 预期：所有测试通过，0 failures
```

---

## 验收检查清单汇总

| Epic | Story | 关键命令 | 通过 |
|------|-------|---------|------|
| 4 | 4.1 | `axion run` → Memory 文件生成 | ☐ |
| 4 | 4.1 | `axion doctor` → Memory 状态报告 | ☐ |
| 4 | 4.2 | Memory 中包含 AX 特征和 Profile | ☐ |
| 4 | 4.2 | 3+次成功后标记 familiar | ☐ |
| 4 | 4.3 | `axion run --no-memory` → 无 Memory 注入 | ☐ |
| 4 | 4.3 | `axion memory list` → 显示 domain 列表 | ☐ |
| 4 | 4.3 | `axion memory clear --app xxx` → 清除成功 | ☐ |
| 5 | 5.1 | `axion server` → 监听端口 | ☐ |
| 5 | 5.1 | `POST /v1/runs` → 提交任务 | ☐ |
| 5 | 5.1 | `GET /v1/runs/:id` → 查询状态 | ☐ |
| 5 | 5.1 | `GET /v1/health` → 健康检查 | ☐ |
| 5 | 5.2 | `GET /v1/runs/:id/events` → SSE 事件流 | ☐ |
| 5 | 5.2 | 已完成任务 SSE 重放 | ☐ |
| 5 | 5.3 | `--auth-key` → 未认证请求返回 401 | ☐ |
| 5 | 5.3 | Bearer token → 认证通过 | ☐ |
| 5 | 5.3 | `--max-concurrent` → 排队响应 | ☐ |
| 6 | 6.1 | `axion mcp` → MCP initialize 握手 | ☐ |
| 6 | 6.1 | `tools/list` → 返回工具列表 | ☐ |
| 6 | 6.2 | `axion mcp --help` → 用法说明 | ☐ |
| 6 | 6.2 | stdout 仅 MCP 协议，日志走 stderr | ☐ |
| 7 | 7.1 | Takeover 提示 → 按 Enter 恢复 | ☐ |
| 7 | 7.1 | Takeover → skip 跳过步骤 | ☐ |
| 7 | 7.1 | Takeover → abort 终止任务 | ☐ |
| 7 | 7.2 | `--fast` 模式 → 简化规划执行 | ☐ |
| 7 | 7.2 | `--fast` 失败 → 不重规划 | ☐ |
| 7 | 7.2 | `--fast --json` → 包含 mode: "fast" | ☐ |
