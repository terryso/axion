# Axion

[![Swift](https://img.shields.io/badge/Swift-6.1-orange)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://developer.apple.com/macos/)
[![CI](https://github.com/terryso/axion/actions/workflows/ci.yml/badge.svg)](https://github.com/terryso/axion/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/terryso/3a3cc01e58819c72bf54eab52dc2a3ff/raw/coverage.json)](https://github.com/terryso/axion/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

macOS desktop automation platform powered by an LLM-driven Plan-Execute-Verify loop, the MCP tool protocol, cross-run memory, and record-and-replay skills.

[English](#english) | [中文](./README.zh-CN.md)

---

<a id="english"></a>

## Overview

Axion is a Swift-based macOS desktop automation platform that takes natural language task descriptions and autonomously plans, executes, and verifies desktop operations. It exposes 21 native tools via MCP (Model Context Protocol) that any MCP client can call, or you can use the built-in CLI directly.

**Key highlights:**

- **Cross-run Memory** — Learns from every task; the more you use it, the smarter it gets
- **Record & Replay Skills** — Record a workflow once, replay it instantly without LLM calls
- **HTTP API Server** — Integrate with CI/CD and external systems via REST + SSE
- **MCP Server Mode** — Act as a desktop plugin for external agents (Claude Code, Cursor, etc.)
- **User Takeover** — Pause and resume when automation gets stuck
- **Menu Bar App** — Native macOS status bar UI with global hotkeys

## Architecture

```
┌───────────────────────────────────────────────────────┐
│                       AxionCLI                         │
│  run / setup / doctor / server / mcp / record / skill  │
│  Plan → Execute → Verify → Replan Loop                 │
│  Memory · Fast Mode · Takeover                         │
├──────────────────┬──────────────────┬─────────────────┤
│    AxionCore     │   AxionHelper    │    AxionBar      │
│  Models, Proto-  │  MCP Server      │  Menu Bar App    │
│  cols, Config,   │  21 Native macOS │  Task Panel      │
│  Errors          │  Tools           │  Global Hotkeys  │
└──────────────────┴──────────────────┴─────────────────┘
```

- **AxionCLI** — CLI entry point with LLM interaction, task planning, execution engine, memory, and server modes
- **AxionCore** — Shared model layer (Plan, Step, RunState) and protocol definitions
- **AxionHelper** — MCP server process providing 21 native macOS automation tools via stdio
- **AxionBar** — Native macOS menu bar app with task panel, skill triggers, and global hotkeys

## MCP Tools (21)

### App Management
| Tool | Description |
|------|-------------|
| `launch_app` | Launch a macOS app by name (detects blocking dialogs) |
| `list_apps` | List all running applications |
| `activate_window` | Activate (bring to front) a specific window |

### Window Management
| Tool | Description |
|------|-------------|
| `list_windows` | List windows (filterable by process ID) |
| `get_window_state` | Get the state of a specific window |
| `resize_window` | Move and/or resize a window |
| `validate_window` | Check if a window exists and is actionable |
| `arrange_windows` | Arrange multiple windows (tile, cascade) |

### Mouse Operations
| Tool | Description |
|------|-------------|
| `click` | Click at coordinates or by AX selector |
| `double_click` | Double-click at coordinates or by AX selector |
| `right_click` | Right-click at coordinates or by AX selector |
| `drag` | Drag from one point to another |
| `scroll` | Scroll by direction and amount |

### Keyboard Operations
| Tool | Description |
|------|-------------|
| `type_text` | Type text at the current cursor position |
| `press_key` | Press a single key |
| `hotkey` | Press a keyboard shortcut combination |

### Screen & Accessibility
| Tool | Description |
|------|-------------|
| `screenshot` | Take a screenshot (full screen or specific window) |
| `get_accessibility_tree` | Get the accessibility tree of a window |
| `open_url` | Open a URL in the default browser |

### Recording
| Tool | Description |
|------|-------------|
| `start_recording` | Start capturing user input events in listen-only mode |
| `stop_recording` | Stop recording and return captured events |

## Quick Start

### Requirements

- macOS 14+
- Xcode 16+ (Swift 6.1)
- Accessibility and Screen Recording permissions

### Install

```bash
# Build from source
git clone https://github.com/terryso/axion.git
cd axion
swift build -c release
```

### Configure

```bash
# Interactive setup (API Key, Provider, etc.)
axion setup

# Check environment status
axion doctor
```

### Usage

```bash
# Execute a task (default — runs live)
axion run "Open Calculator and compute 123 + 456"

# Dry-run mode (generates a plan without executing)
axion run --dryrun "Open Calculator and compute 123 + 456"

# Fast mode — fewer LLM calls for simple tasks
axion run --fast "Open Calculator"

# Limit maximum steps
axion run --max-steps 10 "Create a new note in Notes"
```

## Core Features

### Plan-Execute-Verify Loop

Axion's execution engine follows this loop:

1. **Planning** — The LLM generates a step plan from the task description
2. **Executing** — Each step in the plan is executed sequentially
3. **Verifying** — Results are checked against expectations
4. **Replanning** — On verification failure, the plan is regenerated automatically (up to 3 retries)

Run states: `planning` → `executing` → `verifying` → `replanning` → `done`

### Cross-run Memory (Phase 2)

Axion learns from every task execution. After each run, it automatically extracts app operation patterns (menu paths, control positions, operation sequences) and persists them. On subsequent runs involving the same app, the Planner injects this experience for more accurate plans.

```bash
# Memory is enabled by default — view accumulated knowledge
axion memory list

# Clear memory for a specific app
axion memory clear --app com.apple.calculator

# Disable memory for a single run
axion run --no-memory "Open Calculator"
```

### User Takeover (Phase 2)

When automation gets stuck, Axion pauses and lets you take over manually. Complete the action yourself, then press Enter to resume. Imperfect automation beats no automation.

Available options when paused:
- Press **Enter** — resume after manual fix
- Type **skip** — skip the current step
- Type **abort** — cancel the task

### HTTP API Server (Phase 2)

Run Axion as a service for external integrations:

```bash
# Start API server
axion server --port 4242

# With authentication
axion server --port 4242 --auth-key mysecret

# Limit concurrent tasks
axion server --port 4242 --max-concurrent 3
```

API endpoints:

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/health` | Health check |
| `POST` | `/v1/runs` | Submit a task (`{"task": "..."}`) |
| `GET` | `/v1/runs/{id}` | Query task status |
| `GET` | `/v1/runs/{id}/events` | SSE real-time event stream |

### MCP Server Mode (Phase 2)

Axion can act as an MCP server for external agents:

```bash
# Start as MCP stdio server
axion mcp
```

Add to your Claude Code MCP configuration:

```json
{
  "mcpServers": {
    "axion": {
      "command": "/path/to/axion",
      "args": ["mcp"]
    }
  }
}
```

### Record and Replay Skills (Phase 3)

Record a workflow once, replay it anytime without LLM planning:

```bash
# Record your actions
axion record "open_calculator"
# ... perform desktop operations ...
# Press Ctrl-C to stop recording

# Compile recording into a reusable skill
axion skill compile open_calculator

# Run the skill (no LLM needed — fast and deterministic)
axion skill run open_calculator

# List all saved skills
axion skill list

# Delete a skill
axion skill delete open_calculator
```

Skills are stored as JSON in `~/.axion/skills/` and can be parameterized with `--param`.

### Multi-window Workflows (Phase 3)

Coordinate operations across multiple applications — copy data from browser to spreadsheet, extract attachments from mail to Finder, and chain end-to-end workflows across apps.

```bash
axion run "Copy the page title from Safari and paste it into TextEdit"
axion run "Put Safari and TextEdit side by side, Safari on the left"
```

The `arrange_windows` tool supports layouts: `tile-left-right`, `tile-top-bottom`, `cascade`.

### Menu Bar App (Phase 3)

AxionBar is a native macOS menu bar app that provides quick access to Axion without opening a terminal:

- **Quick Run** — Submit tasks from the menu bar
- **Task Panel** — Real-time execution progress via SSE
- **Skill Triggers** — One-click skill execution
- **Global Hotkeys** — Bind keyboard shortcuts to skills
- **Run History** — View recent task results

AxionBar communicates with the CLI backend via the HTTP API.

### Third-party SDK Ecosystem (Phase 3)

Axion serves as the flagship reference implementation of [OpenAgentSDK](https://github.com/terryso/open-agent-sdk-swift). Third-party developers can:

- Use the project template to scaffold new Agent apps
- Register custom tools via the `@Tool` macro
- Integrate with Axion's desktop capabilities via `axion mcp`
- Build on the same MCP + Agent Loop architecture

## Use as an MCP Server (Standalone Helper)

AxionHelper can run as a standalone MCP server for any MCP client:

```bash
# Start MCP stdio server
.build/release/AxionHelper
```

```json
{
  "mcpServers": {
    "axion": {
      "command": "/path/to/AxionHelper"
    }
  }
}
```

## Configuration

Config file located at `~/.config/axion/config.json`:

```json
{
  "provider": "anthropic",
  "apiKey": "sk-...",
  "model": "claude-sonnet-4-20250514",
  "maxSteps": 20,
  "maxBatches": 6,
  "maxReplanRetries": 3,
  "traceEnabled": true
}
```

Supports Anthropic and OpenAI Compatible providers. Config priority: defaults → config.json → environment variables → CLI flags.

## Development

```bash
# Build
swift build

# Run unit tests (Swift Testing framework)
swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" \
           --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" \
           --filter "AxionCoreTests" --filter "AxionCLITests"

# Run integration tests (requires macOS Accessibility permissions)
swift test --filter AxionHelperIntegrationTests
```

## Project Structure

```
Sources/
├── AxionCLI/              # CLI entry point and commands
│   ├── Commands/          # run, setup, doctor, server, mcp, record, skill subcommands
│   ├── Config/            # Configuration management
│   ├── Permissions/       # Permission checks
│   ├── Engine/            # RunEngine state machine
│   ├── Planner/           # LLMPlanner, PlanParser, PromptBuilder
│   ├── Executor/          # StepExecutor, SafetyChecker, PlaceholderResolver
│   ├── Verifier/          # TaskVerifier, StopConditionEvaluator
│   ├── Memory/            # AppMemoryExtractor, AppProfileAnalyzer, MemoryContextProvider
│   ├── Trace/             # TraceRecorder (JSONL)
│   ├── MCP/               # MCPServerRunner (Agent-as-MCP-Server)
│   ├── API/               # HTTP API server, SSE events
│   ├── Helper/            # HelperProcessManager (stdio lifecycle)
│   └── Services/          # SkillExecutor and shared services
├── AxionCore/             # Shared core layer
│   ├── Models/            # Plan, Step, RunState, AxionConfig
│   ├── Protocols/         # Planner, Executor, Verifier protocols
│   ├── Errors/            # Error types
│   └── Constants/         # Constants
├── AxionHelper/           # MCP server (Helper process)
│   ├── MCP/               # MCPServer and ToolRegistrar (21 tools)
│   ├── Services/          # AccessibilityEngine, Screenshot, InputSimulation, EventRecorder, etc.
│   ├── Models/            # AppInfo, WindowInfo, AXElement, SelectorQuery
│   └── Protocols/         # Service protocol definitions
└── AxionBar/              # macOS menu bar app
    ├── Views/             # QuickRunWindow, TaskDetailPanel, RunHistoryWindow, SettingsWindow
    ├── MenuBar/           # MenuBarBuilder
    ├── Services/          # BackendHealthChecker, SSEEventClient, GlobalHotkeyService, etc.
    └── Models/            # Bar-specific models

Tests/
├── AxionCoreTests/        # Core model unit tests
├── AxionCLITests/         # CLI command tests
├── AxionHelperTests/      # Helper tool and service tests
│   ├── Tools/             # Tool unit tests
│   ├── Models/            # Model tests
│   ├── Services/          # Service tests
│   ├── MCP/               # MCP protocol tests
│   └── Integration/       # Integration tests (requires real macOS environment)
```

## Dependencies

- [open-agent-sdk-swift](https://github.com/terryso/open-agent-sdk-swift) — Agent SDK (Agent Loop, MCP Client, Memory Store, Hooks)
- [swift-mcp](https://github.com/terryso/swift-mcp) — MCP protocol implementation
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI argument parsing

## License

MIT
