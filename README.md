# Axion

[![Swift](https://img.shields.io/badge/Swift-6.1-orange)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://developer.apple.com/macos/)
[![CI](https://github.com/terryso/axion/actions/workflows/ci.yml/badge.svg)](https://github.com/terryso/axion/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/terryso/3a3cc01e58819c72bf54eab52dc2a3ff/raw/coverage.json)](https://github.com/terryso/axion/actions)
[![BMAD](https://bmad-badge.vercel.app/terryso/axion.svg)](https://github.com/bmad-code-org/BMAD-METHOD)
[![DeepWiki](https://img.shields.io/badge/DeepWiki-_.svg?style=flat&color=00b0aa&labelColor=000000&logo=data:image/svg%2Bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxNiIgaGVpZ2h0PSIxNiIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IiNmZmYiIHN0cm9rZS13aWR0aD0iMiIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMiAzaDZhMTAgMTAgMCAwIDEgMTAgMTB2MiIvPjxwYXRoIGQ9Ik0yIDEzaDYxMCAxMCAwIDAgMSAxMCAxMHYyIi8+PC9zdmc+)](https://deepwiki.com/terryso/axion)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

macOS AI agent powered by an LLM-driven Plan-Execute-Verify loop, with native desktop automation, cross-run memory, and record-and-replay skills.

[English](#english) | [中文](./README.zh-CN.md)

---

<a id="english"></a>

## Overview

Axion is a Swift-based AI agent for macOS that takes natural language task descriptions and autonomously plans and executes actions. It combines core tools (Bash, file operations, web search) with 21 native desktop automation tools via MCP (Model Context Protocol), plus browser automation via Playwright. Use the built-in CLI directly, or integrate via HTTP API / MCP Server mode.

**Key highlights:**

- **Versatile Tool Selection** — Automatically picks the right tool: Bash for CLI tasks, MCP for GUI interactions, Playwright for browser automation, or Skills for specialized workflows
- **SDK Skill System** — Prompt skills, recorded skills, and built-in desktop skills with dual-track lookup and skill-scoped memory
- **Record & Replay Skills** — Record a workflow once, replay it instantly without LLM calls
- **HTTP API Server** — Integrate with CI/CD and external systems via REST + SSE
- **MCP Server Mode** — Act as a desktop plugin for external agents (Claude Code, Cursor, etc.), while also supporting CLI, file, and web tasks standalone
- **User Takeover** — Pause and resume when automation gets stuck
- **Completion Notifications** — macOS desktop notification with AI-generated summary when tasks finish
- **Self-Evolution** — Background review agent and intelligent curator automatically extract memory, evolve skills, and manage skill lifecycle after each run
- **Runtime Event Layer** — 18 typed events via EventBus with 7 built-in handlers (cost tracking, notifications, visual delta, seat monitoring, tracing, memory, review)

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│                          AxionCLI                          │
│  run / setup / doctor / server / mcp / record / skill     │
│  daemon / resume / sessions                               │
│  Agent Stream Loop · Memory · Takeover                    │
│  Skill System · Built-in Skills · Skill + Memory Context  │
│  Runtime Event Layer · EventBus · EventHandlers (7)       │
├──────────────────────┬────────────────────────────────────┤
│      AxionCore       │           AxionHelper              │
│  Models, Protocols,  │  MCP Server                        │
│  Config, Errors      │  21 Native macOS Automation Tools  │
└──────────────────────┴────────────────────────────────────┘
```

- **AxionCLI** — CLI entry point with agent stream loop, memory, skill system (prompt + recorded + built-in), daemon management, server modes, and completion notifications
- **AxionCore** — Shared model layer (RunConfig, AxionConfig) and protocol definitions
- **AxionHelper** — MCP server process providing 21 native macOS automation tools via stdio

## MCP Tools (21)

### App Management
| Tool | Description |
|------|-------------|
| `launch_app` | Launch a macOS app by name (detects blocking dialogs) |
| `list_apps` | List all running applications |
| `quit_app` | Quit a running application |
| `activate_window` | Activate (bring to front) a specific window |

### Window Management
| Tool | Description |
|------|-------------|
| `list_windows` | List windows (filterable by process ID) |
| `get_window_state` | Get the state of a specific window |
| `move_window` | Move a window to a new position |
| `resize_window` | Move and/or resize a window |
| `validate_window` | Check if a window exists and is actionable |
| `arrange_windows` | Arrange multiple windows (tile, cascade) |

### Mouse Operations
| Tool | Description |
|------|-------------|
| `click` | Click at coordinates or by AX selector |
| `click_element` | Click an element by title/role — no coordinate lookup needed |
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
| `get_file_info` | Get file metadata (size, dates, permissions) |

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

**Homebrew (recommended):**

```bash
brew tap terryso/tap
brew install axion
```

**Build from source:**

```bash
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

# CLI tasks use Bash directly — no GUI needed
axion run "Compress ~/Downloads/video.mp4 using ffmpeg"
axion run "Check disk usage of ~/Documents"
axion run "Search the web for Guangzhou weather today"

# Dry-run mode (generates a plan without executing)
axion run --dryrun "Open Calculator and compute 123 + 456"

# Fast mode — fewer LLM calls for simple tasks
axion run --fast "Open Calculator"

# Limit maximum steps
axion run --max-steps 10 "Create a new note in Notes"

# Disable post-run review and curator
axion run --no-review "Open Calculator"
```

## Core Features

### Completion Notifications

When a task finishes, Axion sends a macOS desktop notification with three lines:

1. **Status** — completed / failed / cancelled
2. **AI Summary** — auto-generated one-line result summary (max 100 chars)
3. **Stats** — elapsed time, LLM calls, estimated cost

If the task involved UI operations (desktop automation), Axion automatically brings the terminal window back to the foreground so you can immediately see the results.

Notifications are skipped in JSON mode for programmatic use.

### User Takeover

When automation gets stuck, Axion pauses and lets you take over manually. Complete the action yourself, then press Enter to resume. Imperfect automation beats no automation.

Available options when paused:
- Press **Enter** — resume after manual fix
- Type **skip** — skip the current step
- Type **abort** — cancel the task
- Type a description — describe what you did (e.g., "used Cmd+Shift+G to enter path")

Takeover experiences are automatically recorded as Memory, helping the Planner avoid similar blocks in the future. You can also manually record experiences:

```bash
axion memory learn-takeover --bundle-id com.apple.finder \
  --issue "file dialog not accessible via AX" \
  --summary "used Cmd+Shift+G to enter path directly"
```

### Cross-run Memory

Axion learns from every task execution. After each run, it automatically extracts app operation patterns (menu paths, control positions, operation sequences) and persists them. On subsequent runs involving the same app, the Planner injects this experience for more accurate plans.

```bash
# Memory is enabled by default — view accumulated knowledge
axion memory list

# Clear memory for a specific app
axion memory clear --app com.apple.calculator

# Disable memory for a single run
axion run --no-memory "Open Calculator"
```

### Self-Evolution (Review & Curator)

After each run, Axion automatically triggers a **background review** that analyzes the conversation, extracts memory, and evolves skills — no user action required.

**Review Agent** — Automatically runs after `axion run` completes:
- Checks if review is needed based on message count and scheduling interval
- Forks a lightweight review agent (Haiku model) that inspects the conversation
- Extracts new memory facts and evolves skill definitions
- Runs in a detached task — does not block the terminal

```bash
# Review is enabled by default. Disable for a single run:
axion run --no-review "Open Calculator"

# Override the model used for review:
axion run --review-model claude-haiku-4-5-20251001 "Open Calculator"
```

**Intelligent Curator** — Periodically manages skill lifecycle:
- **Mechanical curation** — archives stale skills (>30 days unused), transitions skill states
- **LLM curation** — consolidates overlapping skills, prunes redundant ones
- Runs automatically when the configured interval elapses

```bash
# View curator status and next run time
axion curator status

# Force-run curator immediately
axion curator run

# Dry-run (see what would change without modifying)
axion curator run --dry-run
```

**Skill usage tracking** — Every skill invocation via the `Skill` tool is automatically counted, providing data for curator decisions.

Review and curator results appear as trace events in `~/.axion/runs/<run-id>/review-trace.jsonl`.

### HTTP API Server

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
| `GET` | `/v1/skills` | List all skills |
| `GET` | `/v1/skills/{name}` | Get skill detail |
| `POST` | `/v1/skills/{name}/run` | Execute a skill |

### MCP Server Mode

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

### Record and Replay Skills

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

### Multi-window Workflows

Coordinate operations across multiple applications — copy data from browser to spreadsheet, extract attachments from mail to Finder, and chain end-to-end workflows across apps.

```bash
axion run "Copy the page title from Safari and paste it into TextEdit"
axion run "Put Safari and TextEdit side by side, Safari on the left"
```

The `arrange_windows` tool supports layouts: `tile-left-right`, `tile-top-bottom`, `cascade`.

### Third-party SDK Ecosystem

Axion serves as the flagship reference implementation of [OpenAgentSDK](https://github.com/terryso/open-agent-sdk-swift). Third-party developers can:

- Use the project template to scaffold new Agent apps
- Register custom tools via the `@Tool` macro
- Integrate with Axion's desktop capabilities via `axion mcp`
- Build on the same MCP + Agent Loop architecture

### SDK Skill System

Axion integrates with [OpenAgentSDK](https://github.com/terryso/open-agent-sdk-swift)'s Skill system, supporting two types of skills:

- **Prompt Skills** — Discovered from `~/.claude/skills/*/SKILL.md` files, each defining a `promptTemplate`, optional `toolRestrictions`, and `modelOverride`
- **Recorded Skills** — JSON files in `~/.axion/skills/` compiled from user recordings

**Dual-track lookup** — When a skill name is referenced, Axion checks prompt skills first, then falls back to recorded skills. Same-name skills always resolve to the prompt version.

**Explicit triggering** — Type `/skill-name` as the task prefix to invoke a specific skill directly:

```bash
# Trigger a prompt skill directly
axion run "/screenshot-analyze analyze the current screen layout"

# Trigger a recorded skill directly
axion run "/open-calculator"

# Or use the dedicated command
axion skill run open-calculator
```

**Implicit triggering** — Axion injects a curated list of available skills into the system prompt. The LLM can automatically invoke the right skill based on the user's intent without explicit mention.

**Built-in desktop skills** — Three skills are registered in code (no filesystem files needed):

| Skill | Aliases | Description |
|-------|---------|-------------|
| `screenshot-analyze` | `sa`, `analyze`, `screen` | Capture and analyze the current screen |
| `data-extract` | `extract`, `de` | Extract structured data from visible content |
| `form-fill` | `fill`, `ff` | Fill form fields automatically |

```bash
# List all available skills (prompt + recorded + built-in)
axion skill list

# Disable skill system for a single run
axion run --no-skills "Open Calculator"
```

**Skill + Memory integration** — Skills interact with the cross-run memory system:

- Successful skill execution records an `affordance` fact scoped to `skill:{name}`
- Failed execution records an `avoid` fact so the Planner learns from errors
- Before execution, up to 3 relevant skill-scoped memories are injected into the prompt
- Use `--no-memory` to skip both injection and recording

**HTTP API skill endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/skills` | List all skills (merged prompt + recorded, with `type` field) |
| `GET` | `/v1/skills/{name}` | Get skill detail (type, step_count, parameter_count) |
| `POST` | `/v1/skills/{name}/run` | Execute a skill via API (`{"task": "..."}`) |

### Runtime Event Layer

Axion integrates with [OpenAgentSDK](https://github.com/terryso/open-agent-sdk-swift)'s Runtime Event Layer — an `EventBus`-based pub/sub system that decouples agent lifecycle concerns from the core execution loop. 18 typed events across 4 categories are emitted automatically during agent execution.

**Event categories:**

| Category | Events |
|----------|--------|
| **Session** | `SessionCreatedEvent`, `SessionRestoredEvent`, `SessionClosedEvent`, `SessionAutoSavedEvent` |
| **Agent** | `AgentStartedEvent`, `AgentCompletedEvent`, `AgentFailedEvent`, `AgentInterruptedEvent`, `AgentResumedEvent` |
| **Tool** | `ToolStartedEvent`, `ToolStreamingEvent`, `ToolCompletedEvent`, `ToolFailedEvent` |
| **LLM** | `LLMRequestStartedEvent`, `LLMResponseReceivedEvent`, `LLMCostEvent`, `LLMTokenStreamEvent` |

**Built-in event handlers:**

| Handler | Description |
|---------|-------------|
| `CostEventHandler` | Prints LLM usage summary (turns, tokens, cost) to stderr on agent completion/failure/interrupt |
| `NotificationHandler` | Sends macOS desktop notification with AI-generated summary when a task finishes |
| `VisualDeltaHandler` | Detects visual changes via screenshot comparison after tool execution |
| `SeatMonitorHandler` | Monitors for external user activity during long-running tool calls (shared-seat mode) |
| `TraceEventHandler` | Appends structured JSONL event traces to `~/.axion/runs/<run-id>/events.jsonl` |
| `MemoryProcessingHandler` | Triggers post-run memory extraction and skill evolution after agent completion |
| `ReviewHandler` | Launches background review agent after successful task completion |

**Event flow:**

```
Agent SDK  →  EventBus.publish(event)  →  AsyncStream  →  AxionRuntime.dispatchToHandlers()
                                                                   ↓
                                                          EventHandler.handle(event, context)
```

The `AxionRuntime` actor manages the event loop lifecycle:
1. `registerHandler()` — registers event handlers with optional type filtering
2. `startEventLoop()` — subscribes to the EventBus and begins dispatching events
3. `stopEventLoop()` — gracefully unsubscribes and stops dispatching

Handlers are actors — AxionRuntime dispatches events in independent Tasks, and actor isolation guarantees thread-safe mutable state.

**SSE bridge for HTTP API:** `EventBusBridge` forwards all events to SSE clients via `EventBroadcaster`, enabling real-time monitoring of agent execution through the `/v1/runs/{id}/events` endpoint.

**Session resume:** `AxionRuntime` supports resuming interrupted sessions via `resumeSession()`, restoring agent state and reconnecting the event loop. The `SessionListing` protocol exposes `listSessions()` for querying persisted session history.

### Daemon Mode & Crash Recovery

Run Axion as a persistent launchd daemon that survives reboots and auto-restarts on crashes. All running task state is persisted to disk, so in-flight tasks are automatically recovered after an unexpected server termination.

**Daemon management:**

```bash
# Install as a launchd agent (auto-start on login)
axion daemon install --port 4242

# With authentication
axion daemon install --port 4242 --auth-key mysecret

# Check daemon status
axion daemon status

# Uninstall (stops service and removes plist)
axion daemon uninstall

# Uninstall but keep log files
axion daemon uninstall --keep-logs
```

**Key daemon properties:**
- **Auto-start** — `RunAtLoad: true` starts on login
- **Crash recovery** — `KeepAlive: true` restarts on any exit
- **Log files** — stdout → `~/.axion/server.log`, stderr → `~/.axion/server.err.log`
- **ThrottleInterval** — 10s minimum between restart attempts

**Task state persistence:**
- All task state (`api-output.json`) and SSE events (`api-events.jsonl`) are written to `~/.axion/api-runs/` in real-time
- On server restart, `RunRecoveryService` loads all persisted runs and:
  - Marks `running`/`queued`/`resuming`/`userTakeover` tasks as `failed` with error `"server interrupted"`
  - Preserves `intervention_needed`, `completed`, `failed`, and `cancelled` states unchanged
  - Restores SSE event history so late subscribers can replay past events

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
  "maxModelCalls": 50,
  "reviewModel": "claude-haiku-4-5-20251001",
  "reviewMemoryInterval": 10,
  "reviewSkillInterval": 15,
  "reviewMinMessages": 4,
  "curatorEnabled": true,
  "curatorIntervalHours": 168,
  "curatorStaleAfterDays": 30,
  "curatorArchiveAfterDays": 90
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
│   ├── Commands/          # run, setup, doctor, server, mcp, record, skill, daemon, curator subcommands
│   ├── Config/            # Configuration management
│   ├── Checks/            # Environment and permission checks
│   ├── Constants/         # CLI-specific constants
│   ├── IO/                # Output handlers and takeover I/O
│   ├── MCP/               # MCPServerRunner (Agent-as-MCP-Server)
│   ├── API/               # HTTP API server, SSE events
│   ├── Memory/            # MemoryContextProvider, RunMemoryProcessor
│   ├── Planner/           # PromptBuilder
│   ├── Skills/            # SkillRegistry, AxionBuiltInSkills
│   ├── Helper/            # HelperProcessManager (stdio lifecycle)
│   ├── Runtime/           # EventHandlers (Cost, Notification, VisualDelta, SeatMonitor, Trace, Memory, Review)
│   ├── Trace/              # TraceRecorder (review/curator trace events)
│   └── Services/          # RunOrchestrator, AgentBuilder, AxionRuntime, EventBus, shared services
├── AxionCore/             # Shared core layer
│   ├── Models/            # RunConfig, AxionConfig, AppProfile
│   ├── Protocols/         # Service protocols
│   ├── Errors/            # Error types
│   └── Constants/         # ToolNames and shared constants
├── AxionHelper/           # MCP server (Helper process)
│   ├── MCP/               # MCPServer and ToolRegistrar (21 tools)
│   ├── Services/          # AccessibilityEngine, Screenshot, InputSimulation, EventRecorder
│   ├── Models/            # AppInfo, WindowInfo, AXElement, SelectorQuery
│   └── Protocols/         # Service protocol definitions

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

- [open-agent-sdk-swift](https://github.com/terryso/open-agent-sdk-swift) — Agent SDK (Agent Loop, MCP Client, Memory Store, Hooks, Runtime Event Layer)
- [swift-mcp](https://github.com/terryso/swift-mcp) — MCP protocol implementation
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI argument parsing

## License

MIT
