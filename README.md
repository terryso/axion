# Axion

[![Swift](https://img.shields.io/badge/Swift-6.1-orange)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://developer.apple.com/macos/)
[![CI](https://github.com/terryso/axion/actions/workflows/ci.yml/badge.svg)](https://github.com/terryso/axion/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/terryso/3a3cc01e58819c72bf54eab52dc2a3ff/raw/coverage.json)](https://github.com/terryso/axion/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

macOS desktop automation CLI powered by an LLM-driven Plan-Execute-Verify loop and the MCP tool protocol.

[English](#english) | [中文](./README.zh-CN.md)

---

<a id="english"></a>

## Overview

Axion is a Swift-based macOS desktop automation tool that takes natural language task descriptions and autonomously plans, executes, and verifies desktop operations. It exposes 22 native tools via MCP (Model Context Protocol) that any MCP client can call, or you can use the built-in CLI directly.

## Architecture

```
┌─────────────────────────────────────────────┐
│                  AxionCLI                    │
│  run / setup / doctor                        │
│  Plan → Execute → Verify → Replan Loop       │
├──────────────────┬──────────────────────────┤
│    AxionCore     │      AxionHelper          │
│  Models, Protocols│  MCP Server (stdio)       │
│  Config, Errors  │  22 Native macOS Tools    │
└──────────────────┴──────────────────────────┘
```

- **AxionCLI** — CLI entry point with LLM interaction, task planning, and execution engine
- **AxionCore** — Shared model layer (Plan, Step, RunState) and protocol definitions
- **AxionHelper** — MCP server process providing 22 native macOS automation tools via stdio

## MCP Tools (22)

### App Management
| Tool | Description |
|------|-------------|
| `launch_app` | Launch a macOS app by name |
| `list_apps` | List all running applications |
| `quit_app` | Quit a running application |
| `activate_window` | Activate (bring to front) a specific window |

### Window Management
| Tool | Description |
|------|-------------|
| `list_windows` | List windows (filterable by process ID) |
| `get_window_state` | Get the state of a specific window |
| `move_window` | Move a window to a new position |
| `resize_window` | Resize a window (position and dimensions) |
| `validate_window` | Check if a window exists and is actionable |
| `arrange_windows` | Arrange multiple windows (tile, cascade) |

### Mouse Operations
| Tool | Description |
|------|-------------|
| `click` | Click at specified coordinates |
| `double_click` | Double-click at specified coordinates |
| `right_click` | Right-click at specified coordinates |
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
| `get_file_info` | Get information about a file or directory |

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

# Limit maximum steps
axion run --max-steps 10 "Create a new note in Notes"
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
```

### Use as an MCP Server

AxionHelper can run as a standalone MCP server for any MCP client:

```bash
# Start MCP stdio server
.build/release/AxionHelper
```

Add to your Claude Code MCP configuration:

```json
{
  "mcpServers": {
    "axion": {
      "command": "/path/to/AxionHelper"
    }
  }
}
```

## Plan-Execute-Verify Loop

Axion's execution engine follows this loop:

1. **Planning** — The LLM generates a step plan from the task description
2. **Executing** — Each step in the plan is executed sequentially
3. **Verifying** — Results are checked against expectations
4. **Replanning** — On verification failure, the plan is regenerated automatically (up to 3 retries)

Run states: `planning` → `executing` → `verifying` → `replanning` → `done`

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

Supports Anthropic and OpenAI Compatible providers.

## Development

```bash
# Build
swift build

# Run unit tests
swift test --skip AxionHelperIntegrationTests

# Run integration tests (requires macOS Accessibility permissions)
swift test --filter AxionHelperIntegrationTests

# Run all tests
swift test
```

## Project Structure

```
Sources/
├── AxionCLI/          # CLI entry point and commands
│   ├── Commands/      # run, setup, doctor subcommands
│   ├── Config/        # Configuration management
│   ├── Permissions/   # Permission checks
│   ├── Engine/        # Execution engine (WIP)
│   ├── Planner/       # Planner (WIP)
│   ├── Executor/      # Executor (WIP)
│   ├── Verifier/      # Verifier (WIP)
│   └── Trace/         # Execution tracing (WIP)
├── AxionCore/         # Shared core layer
│   ├── Models/        # Plan, Step, RunState, AxionConfig
│   ├── Protocols/     # Planner, Executor, Verifier protocols
│   ├── Errors/        # Error types
│   └── Constants/     # Constants
└── AxionHelper/       # MCP server
    ├── MCP/           # MCP Server and tool registration
    ├── Services/      # Accessibility engine, screenshots, input simulation, etc.
    ├── Models/        # AppInfo, WindowInfo, AXElement
    └── Protocols/     # Service protocol definitions

Tests/
├── AxionCoreTests/       # Core model unit tests
├── AxionCLITests/        # CLI command tests
├── AxionHelperTests/     # Helper tool and service tests
│   ├── Tools/            # Tool unit tests
│   ├── Models/           # Model tests
│   ├── Services/         # Service tests
│   ├── MCP/              # MCP protocol tests
│   └── Integration/      # Integration tests (requires real macOS environment)
```

## Dependencies

- [open-agent-sdk-swift](https://github.com/terryso/open-agent-sdk-swift) — Agent SDK
- [swift-mcp](https://github.com/terryso/swift-mcp) — MCP protocol implementation
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI argument parsing

## License

MIT
