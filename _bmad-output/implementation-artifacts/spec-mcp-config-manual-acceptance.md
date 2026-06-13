---
title: 'MCP Server 用户可配置化 — 手工验收'
type: 'manual-acceptance'
created: '2026-06-13'
spec: './spec-mcp-config.md'
implementation_commit: 'dfdad53'
status: 'draft'
---

# MCP Server 用户可配置化 — 手工验收

## 验收目标

验证 `~/.axion/config.json` 的 `mcpServers` 能进入 Axion 作为 MCP client 的运行时配置，并覆盖以下用户可见语义：

- 合法自定义 stdio MCP server 会被加载并尝试连接。
- `axion-helper` 是保留 key，用户配置会被忽略并输出 warning。
- 自定义 `playwright` stdio 会替代自动 Playwright 探测。
- `playwright` 配成 `sse`/`http` 时会被 warning 忽略，且不回退自动探测。
- 任一 `mcpServers` 条目解码失败时，整个 `mcpServers` 字段降级为 nil。
- `--dryrun` 不加载 MCP server。

## 前置条件

| 项目 | 要求 |
|------|------|
| 仓库 | `/Users/nick/CascadeProjects/axion` |
| 实现提交 | `dfdad53` 或之后 |
| Python | 所有命令使用 `/Users/nick/.browser-use-env/bin/python3` |
| API key | 不需要真实 key；本验收使用假 key 和不可达 `baseURL`，只验收 MCP 装配发生在模型调用前 |
| 测试范围 | 只跑单元/配置/烟测，不跑 `Integration` 或 `AxionE2ETests` |

## 安全准备

这些步骤会临时替换 `~/.axion/config.json`。先备份真实配置，验收完成后按“恢复环境”还原。

```bash
cd /Users/nick/CascadeProjects/axion
swift build

BIN="$PWD/.build/debug/AxionCLI"
WORKDIR="/tmp/axion-mcp-config-acceptance"
CONFIG_DIR="$HOME/.axion"
CONFIG="$CONFIG_DIR/config.json"
BACKUP="$WORKDIR/config.json.before"

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR" "$CONFIG_DIR"
if [ -f "$CONFIG" ]; then
  cp "$CONFIG" "$BACKUP"
fi
```

## 准备探针 MCP Server

探针 server 只实现 `initialize`、`tools/list`、`tools/call` 和 `ping`，并把收到的方法写到日志。Axion 后续模型调用会因为假 `baseURL` 失败，这是预期结果；验收只看 MCP 连接和 warning。

```bash
cat > "$WORKDIR/probe_mcp.py" <<'PY'
import json
import os
import sys

LOG_PATH = os.environ.get("AXION_MCP_ACCEPTANCE_LOG", "/tmp/axion-mcp-config-acceptance/probe.log")


def log(message):
    with open(LOG_PATH, "a", encoding="utf-8") as handle:
        handle.write(message + "\n")
        handle.flush()


def send(payload):
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()
    log("sent " + json.dumps(payload, sort_keys=True))


for raw_line in sys.stdin:
    raw_line = raw_line.strip()
    if not raw_line:
        continue

    log("received " + raw_line)
    try:
        request = json.loads(raw_line)
    except Exception as error:
        log("invalid-json " + str(error))
        continue

    method = request.get("method")
    request_id = request.get("id")
    log("method " + str(method))

    if method == "initialize":
        params = request.get("params") or {}
        send({
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "protocolVersion": params.get("protocolVersion", "2024-11-05"),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "acceptance-probe", "version": "0.1.0"}
            }
        })
    elif method == "notifications/initialized":
        continue
    elif method == "tools/list":
        send({
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "tools": [{
                    "name": "acceptance_ping",
                    "description": "Manual acceptance probe tool",
                    "inputSchema": {
                        "type": "object",
                        "properties": {},
                        "additionalProperties": False
                    }
                }]
            }
        })
    elif method == "tools/call":
        send({
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "content": [{"type": "text", "text": "pong"}],
                "isError": False
            }
        })
    elif method == "ping":
        send({"jsonrpc": "2.0", "id": request_id, "result": {}})
    elif request_id is not None:
        send({
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {"code": -32601, "message": "Method not found"}
        })
PY
```

## A0. 自动化基线

```bash
swift test --filter "AxionMcpServerConfigTests"
swift test --filter "MCPConfigResolver" --filter "AxionConfig"
```

**期望：** 两个命令均通过。

## A1. 合法 stdio server 会进入运行时并连接

```bash
cat > "$CONFIG" <<JSON
{
  "apiKey": "fake-key-for-mcp-manual-smoke",
  "baseURL": "http://127.0.0.1:9/v1",
  "model": "gpt-4o-mini",
  "maxSteps": 1,
  "mcpServers": {
    "acceptance-probe": {
      "type": "stdio",
      "command": "/Users/nick/.browser-use-env/bin/python3",
      "args": ["$WORKDIR/probe_mcp.py"],
      "env": {
        "AXION_MCP_ACCEPTANCE_LOG": "$WORKDIR/probe.log"
      }
    }
  }
}
JSON

rm -f "$WORKDIR/probe.log" "$WORKDIR/stdout.json" "$WORKDIR/stderr.log"
"$BIN" run "manual MCP config smoke" \
  --json --max-steps 1 --no-review --no-memory --no-skills --no-visual-delta \
  > "$WORKDIR/stdout.json" 2> "$WORKDIR/stderr.log" || true

grep -F "Connecting to 'acceptance-probe' via stdio" "$WORKDIR/stderr.log"
grep -F "method initialize" "$WORKDIR/probe.log"
grep -F "method tools/list" "$WORKDIR/probe.log"
```

**期望：**

- stderr 中出现 `Connecting to 'acceptance-probe' via stdio`。
- `probe.log` 中出现 `method initialize` 和 `method tools/list`。
- 命令最终可能因为假 `baseURL` 返回模型连接错误；只要 MCP 日志已出现，该用例仍为 PASS。

## A2. `axion-helper` 保留 key 被忽略并 warning

```bash
cat > "$CONFIG" <<JSON
{
  "apiKey": "fake-key-for-mcp-manual-smoke",
  "baseURL": "http://127.0.0.1:9/v1",
  "model": "gpt-4o-mini",
  "maxSteps": 1,
  "mcpServers": {
    "axion-helper": {
      "type": "stdio",
      "command": "/usr/bin/false"
    },
    "acceptance-probe": {
      "type": "stdio",
      "command": "/Users/nick/.browser-use-env/bin/python3",
      "args": ["$WORKDIR/probe_mcp.py"],
      "env": {
        "AXION_MCP_ACCEPTANCE_LOG": "$WORKDIR/probe.log"
      }
    }
  }
}
JSON

rm -f "$WORKDIR/probe.log" "$WORKDIR/stdout.json" "$WORKDIR/stderr.log"
"$BIN" run "manual MCP reserved key smoke" \
  --json --max-steps 1 --no-review --no-memory --no-skills --no-visual-delta \
  > "$WORKDIR/stdout.json" 2> "$WORKDIR/stderr.log" || true

grep -F "mcpServers.axion-helper is reserved and was ignored" "$WORKDIR/stderr.log"
grep -F "Connecting to 'acceptance-probe' via stdio" "$WORKDIR/stderr.log"
```

**期望：**

- stderr 中出现 reserved key warning。
- `acceptance-probe` 仍会被连接。
- 不要求 `/usr/bin/false` 被执行；用户声明的 `axion-helper` 必须被忽略。

## A3. 自定义 Playwright stdio 替代自动探测

```bash
cat > "$CONFIG" <<JSON
{
  "apiKey": "fake-key-for-mcp-manual-smoke",
  "baseURL": "http://127.0.0.1:9/v1",
  "model": "gpt-4o-mini",
  "maxSteps": 1,
  "mcpServers": {
    "playwright": {
      "type": "stdio",
      "command": "/usr/bin/false"
    }
  }
}
JSON

rm -f "$WORKDIR/stdout.json" "$WORKDIR/stderr.log"
"$BIN" run "manual MCP custom playwright smoke" \
  --json --max-steps 1 --no-review --no-memory --no-skills --no-visual-delta \
  > "$WORKDIR/stdout.json" 2> "$WORKDIR/stderr.log" || true

grep -F "Connecting to 'playwright' via stdio: /usr/bin/false" "$WORKDIR/stderr.log"
```

**期望：**

- stderr 中的 Playwright command 是 `/usr/bin/false`。
- 不应出现 nvm 自动探测出的 `@playwright/mcp/cli.js` 路径。

## A4. Playwright 非 stdio 被忽略且不回退自动探测

```bash
cat > "$CONFIG" <<JSON
{
  "apiKey": "fake-key-for-mcp-manual-smoke",
  "baseURL": "http://127.0.0.1:9/v1",
  "model": "gpt-4o-mini",
  "maxSteps": 1,
  "mcpServers": {
    "playwright": {
      "type": "sse",
      "url": "http://127.0.0.1:9/sse"
    }
  }
}
JSON

rm -f "$WORKDIR/stdout.json" "$WORKDIR/stderr.log"
"$BIN" run "manual MCP invalid playwright smoke" \
  --json --max-steps 1 --no-review --no-memory --no-skills --no-visual-delta \
  > "$WORKDIR/stdout.json" 2> "$WORKDIR/stderr.log" || true

grep -F "mcpServers.playwright must use type \"stdio\" and was ignored" "$WORKDIR/stderr.log"
if grep -F "Connecting to 'playwright'" "$WORKDIR/stderr.log"; then
  echo "FAIL: playwright should not be connected"
  exit 1
fi
```

**期望：**

- stderr 中出现 Playwright type warning。
- stderr 中没有任何 `Connecting to 'playwright'`。

## A5. 任一 server 解码失败时整个 `mcpServers` 字段降级

```bash
cat > "$CONFIG" <<JSON
{
  "apiKey": "fake-key-for-mcp-manual-smoke",
  "baseURL": "http://127.0.0.1:9/v1",
  "model": "gpt-4o-mini",
  "maxSteps": 1,
  "mcpServers": {
    "acceptance-probe": {
      "type": "stdio",
      "command": "/Users/nick/.browser-use-env/bin/python3",
      "args": ["$WORKDIR/probe_mcp.py"],
      "env": {
        "AXION_MCP_ACCEPTANCE_LOG": "$WORKDIR/probe.log"
      }
    },
    "broken": {
      "type": "stdio"
    }
  }
}
JSON

rm -f "$WORKDIR/probe.log" "$WORKDIR/stdout.json" "$WORKDIR/stderr.log"
"$BIN" run "manual MCP bad config fallback smoke" \
  --json --max-steps 1 --no-review --no-memory --no-skills --no-visual-delta \
  > "$WORKDIR/stdout.json" 2> "$WORKDIR/stderr.log" || true

grep -F "mcpServers 解析失败已忽略" "$WORKDIR/stderr.log"
if grep -F "Connecting to 'acceptance-probe'" "$WORKDIR/stderr.log"; then
  echo "FAIL: acceptance-probe should not be connected after whole-field fallback"
  exit 1
fi
```

**期望：**

- stderr 中出现 `mcpServers 解析失败已忽略`。
- `acceptance-probe` 不会被连接，证明整个 `mcpServers` 字段已降级为 nil。
- 其他 config 字段仍被保留；模型连接失败来自假 `baseURL`，不是 config 文件整体损坏。

## A6. `--dryrun` 不加载 MCP server

```bash
cat > "$CONFIG" <<JSON
{
  "apiKey": "fake-key-for-mcp-manual-smoke",
  "baseURL": "http://127.0.0.1:9/v1",
  "model": "gpt-4o-mini",
  "maxSteps": 1,
  "mcpServers": {
    "acceptance-probe": {
      "type": "stdio",
      "command": "/Users/nick/.browser-use-env/bin/python3",
      "args": ["$WORKDIR/probe_mcp.py"],
      "env": {
        "AXION_MCP_ACCEPTANCE_LOG": "$WORKDIR/probe.log"
      }
    }
  }
}
JSON

rm -f "$WORKDIR/probe.log" "$WORKDIR/stdout.json" "$WORKDIR/stderr.log"
"$BIN" run "manual MCP dryrun smoke" \
  --dryrun --json --max-steps 1 --no-review --no-memory --no-skills --no-visual-delta \
  > "$WORKDIR/stdout.json" 2> "$WORKDIR/stderr.log" || true

if grep -F "MCPClientManager" "$WORKDIR/stderr.log"; then
  echo "FAIL: dryrun should not connect MCP servers"
  exit 1
fi
if [ -f "$WORKDIR/probe.log" ]; then
  echo "FAIL: probe should not start in dryrun"
  exit 1
fi
```

**期望：**

- stderr 中没有 `MCPClientManager`。
- `probe.log` 不存在。

## A7. Skill 执行路径

`buildSkillAgent()` 必须保持 `mcpServers: nil`。当前没有稳定、低副作用的手工入口能直接观察该内部字段；此项以单元测试作为验收依据：

```bash
swift test \
  --filter "AxionHelperTests.Tools" \
  --filter "AxionHelperTests.Models" \
  --filter "AxionHelperTests.MCP" \
  --filter "AxionHelperTests.Services" \
  --filter "AxionCoreTests" \
  --filter "AxionCLITests"
```

**期望：** 项目单元测试集合通过；不单独运行 `Integration` 或 `AxionE2ETests`。

## 恢复环境

```bash
if [ -f "$BACKUP" ]; then
  cp "$BACKUP" "$CONFIG"
else
  rm -f "$CONFIG"
fi
rm -rf "$WORKDIR"
```

## 通过标准

手工验收通过需要满足：

- A0 通过。
- A1 到 A6 的 grep/negative grep 全部符合期望。
- A7 的自动化覆盖通过，或在验收记录中明确说明未执行原因。
- 验收后真实 `~/.axion/config.json` 已恢复。
