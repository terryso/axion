# Axion

[![Swift](https://img.shields.io/badge/Swift-6.1-orange)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://developer.apple.com/macos/)
[![CI](https://github.com/terryso/axion/actions/workflows/ci.yml/badge.svg)](https://github.com/terryso/axion/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/terryso/3a3cc01e58819c72bf54eab52dc2a3ff/raw/coverage.json)](https://github.com/terryso/axion/actions)
[![BMAD](https://bmad-badge.vercel.app/terryso/axion.svg)](https://github.com/bmad-code-org/BMAD-METHOD)
[![DeepWiki](https://img.shields.io/badge/DeepWiki-_.svg?style=flat&color=00b0aa&labelColor=000000&logo=data:image/svg%2Bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxNiIgaGVpZ2h0PSIxNiIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IiNmZmYiIHN0cm9rZS13aWR0aD0iMiIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMiAzaDZhMTAgMTAgMCAwIDEgMTAgMTB2MiIvPjxwYXRoIGQ9Ik0yIDEzaDYxMCAxMCAwIDAgMSAxMCAxMHYyIi8+PC9zdmc+)](https://deepwiki.com/terryso/axion)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

A full-spectrum AI agent for macOS — interactive coding, file editing, web search, shell commands, safe storage cleanup, app uninstall, and 21 native desktop automation tools. All in one terminal.

[English](#english) | [中文](./README.zh-CN.md) | [Changelog](./CHANGELOG.md)

---

<a id="english"></a>

## Overview

Axion is a Swift-based AI agent that lives in your terminal. Type `axion` and start a conversation — it writes code, edits files, runs shell commands, searches the web, reads documentation, safely organizes local storage, uninstalls macOS apps with reviewable support-data cleanup, and when needed, takes control of desktop apps via native accessibility APIs. Think of it as Claude Code with superpowers for your Mac.

<p align="center">
  <img src="docs/demo.gif" alt="Axion Demo" width="700">
</p>

**Key highlights:**

- **Interactive Coding Agent** — `axion` launches a Claude Code–like REPL with streaming output, 17 slash commands (`/help`, `/clear`, `/diff`, `/model`, `/cost`, `/copy`, `/storage`, `/apps`, …), file edit approval diffs, multiline input with CJK support, and session resume
- **Full Tool Spectrum** — Bash execution, file read/write/edit, code search (Grep/Glob), web search & fetch, LSP code intelligence — plus 21 native macOS desktop tools via MCP when you need GUI
- **Safe Storage & App Cleanup** — Find large files, collapse rebuildable caches such as `node_modules` and `DerivedData`, organize folders through approval-backed plans, uninstall apps with support-data review, and undo storage operations
- **Rich Terminal Rendering** — Streaming Unicode tables, 16-language syntax highlighting, diff-colored code blocks, Markdown extensions (strikethrough, task lists, clickable links, image placeholders), file change summaries, and context progress bars
- **Context-Aware File Editing** — Diff-based approval flow shows exactly what changes before applying. Tracks file modifications per turn with `/diff` summary
- **Cross-run Memory** — Two complementary memory systems: App operation facts (auto-extracted from tool calls) and Universal Memory (environment knowledge + user profile)
- **Cross-session History** — Command history persists across sessions; Up/Down navigation works on past inputs
- **Clipboard Integration** — `/copy` command copies last assistant response to clipboard (pbcopy / OSC 52 / tmux auto-fallback)
- **SDK Skill System** — Prompt skills, recorded skills, and built-in desktop skills with dual-track lookup and skill-scoped memory
- **Record & Replay** — Record a workflow once, replay it instantly without LLM calls
- **HTTP API & MCP Server** — Integrate with CI/CD or let external agents (Claude Code, Cursor) use Axion's tools
- **Telegram Gateway** — Always-on remote control with streaming responses, interactive approval keyboards, and extensible command system
- **Self-Evolution** — Background review agent and intelligent curator automatically extract memory, evolve skills, and manage skill lifecycle after each run
- **Completion Notifications** — macOS desktop notification with AI-generated summary when tasks finish

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                            AxionCLI                            │
│                                                                │
│   Interactive Chat (default)         Desktop Automation       │
│   ├── Streaming Markdown             ├── axion run "task"      │
│   ├── Syntax Highlight (16 langs)    ├── MCP Tools (21)        │
│   ├── Unicode Tables                 ├── Record & Replay       │
│   ├── Slash Commands (17)            └── User Takeover         │
│   ├── File Edit Approval                                       │
│   ├── Clipboard (/copy)                                        │
│   ├── Session Resume + Transcript                               │
│   ├── Cross-session History (↑↓)                               │
│   ├── Prompt Bar (ctx%, cost, git branch, speed)               │
│   └── CJK Input                                                │
│                                                                │
│   Core Tools: Bash · File R/W · Grep/Glob · Web · LSP         │
│   Skill System: Prompt + Recorded + Built-in Skills            │
│   Memory: App Facts + Universal (MEMORY.md / USER.md)         │
│   Runtime: EventBus · 7 EventHandlers · Trace · Self-Evolve   │
│   Server: HTTP API (REST+SSE) · MCP Server · Telegram Gateway │
├──────────────────────┬────────────────────────────────────────┤
│      AxionCore       │            AxionHelper                  │
│  Models, Protocols,  │   MCP Server (stdio)                   │
│  Config, Errors      │   21 Native macOS Automation Tools     │
└──────────────────────┴────────────────────────────────────────┘
```

- **AxionCLI** — The agent you interact with. Default mode is an interactive REPL; `axion run` for single-shot tasks. Includes the full tool suite, memory, skills, event handlers, and server modes
- **AxionCore** — Shared model layer (RunConfig, AxionConfig, Skill) and protocol definitions
- **AxionHelper** — Separate MCP server process providing 21 native macOS automation tools via stdio

## Quick Start

### Requirements

- macOS 14+
- Xcode 16+ (Swift 6.1)

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
# Start interactive chat (default command — just type axion)
axion

# Ask it anything
> analyze the error logs in ~/Logs/app.log
> refactor the UserService to use async/await
> search the web for Swift 6.2 concurrency changes

# It edits files with approval
> fix the memory leak in Sources/App/Cache.swift
# → shows diff, asks for approval before applying

# Need desktop automation? It can do that too
> open Safari and check the weather for tomorrow
> arrange Finder and Terminal side by side

# Clean up local storage and apps safely
> /storage large
> /storage scan ~/Projects
> /storage organize ~/Downloads
> /apps

# Check what changed
> /diff          # git diff summary for this session
> /cost          # token usage and cost breakdown
> /copy          # copy last response to clipboard
> /status        # session state card
```

**Single-shot mode** for scripts and CI:

```bash
# Run one task and exit
axion run "Compress ~/Downloads/video.mp4 using ffmpeg"
axion run "Search the web for Guangzhou weather today"
axion run "Open Calculator and compute 123 + 456"

# Flags
axion run --dryrun "Open Calculator"            # plan only, no execution
axion run --fast "Open Calculator"               # fewer LLM calls for simple tasks
axion run --max-steps 10 "Create a new note"     # limit max steps
axion run --no-review "Open Calculator"          # skip post-run review
```

## Core Capabilities

### Built-in Tools

| Category | Tools | Description |
|----------|-------|-------------|
| **Shell** | `Bash` | Execute any shell command |
| **File** | `Read`, `Write`, `Edit` | Read, create, and make targeted edits to files |
| **Search** | `Grep`, `Glob` | Search file contents (regex) and find files by name patterns |
| **Web** | `WebSearch`, `WebFetch` | Search the web and fetch/read web pages |
| **Code Intelligence** | `LSP` | Go-to-definition, find-references, hover info |
| **Memory** | `memory` | Persist and recall knowledge across sessions |
| **Skills** | `Skill` | Invoke specialized workflow skills |
| **Storage & Cleanup** | `storage_scan`, `propose_storage_plan`, `execute_storage_plan`, `undo_storage_op`, `scan_app_uninstall`, `execute_app_uninstall` | Safely organize folders, find large files, uninstall apps (trash by default, undoable, requires confirmation before acting) |
| **Desktop** | 21 MCP tools | Native macOS automation (see below) |

### Mac Storage & App Cleanup

Axion treats cleanup as a reviewable Mac workflow, not a blind delete command. Scans read file metadata only, plans are shown before execution, cleanup uses the system Trash by default, and storage operations write manifests so they can be undone.

- **Find hidden space usage** — `/storage large` scans common user folders; `/storage large --home 1GB` expands to the home directory with built-in system, cache, hidden, and protected-path exclusions.
- **Clean rebuildable developer caches** — `storage_scan` returns collapsed `developer_cache` roots such as `node_modules`, `.build`, `DerivedData`, `.venv`, `Pods`, and `.gradle` so the agent can suggest safe cleanup without enumerating millions of dependency files.
- **Organize folders interactively** — `/storage organize ~/Downloads` scans, proposes a small high-confidence plan, shows risks, then executes only after explicit approval.
- **Uninstall apps with support-data review** — `/apps` lists uninstall candidates with sizes, filters by app name, shows the app detail before handoff, and uses `scan_app_uninstall` / `execute_app_uninstall` for app bundle plus related support data.

```bash
axion
> /storage help
> /storage large
> /storage large ~/Projects 500MB
> /storage large --home 1GB
> /storage organize ~/Downloads
> /storage undo
> /apps
```

### Desktop Automation (21 MCP Tools)

Axion's unique advantage — when CLI tools aren't enough, it controls macOS GUI apps natively.

#### App Management
| Tool | Description |
|------|-------------|
| `launch_app` | Launch a macOS app by name (detects blocking dialogs) |
| `list_apps` | List all running applications |
| `quit_app` | Quit a running application |
| `activate_window` | Activate (bring to front) a specific window |

#### Window Management
| Tool | Description |
|------|-------------|
| `list_windows` | List windows (filterable by process ID) |
| `get_window_state` | Get the state of a specific window |
| `move_window` | Move a window to a new position |
| `resize_window` | Move and/or resize a window |
| `validate_window` | Check if a window exists and is actionable |
| `arrange_windows` | Arrange multiple windows (tile, cascade) |

#### Mouse Operations
| Tool | Description |
|------|-------------|
| `click` | Click at coordinates or by AX selector |
| `click_element` | Click an element by title/role — no coordinate lookup needed |
| `double_click` | Double-click at coordinates or by AX selector |
| `right_click` | Right-click at coordinates or by AX selector |
| `drag` | Drag from one point to another |
| `scroll` | Scroll by direction and amount |

#### Keyboard Operations
| Tool | Description |
|------|-------------|
| `type_text` | Type text at the current cursor position |
| `press_key` | Press a single key |
| `hotkey` | Press a keyboard shortcut combination |

#### Screen & Accessibility
| Tool | Description |
|------|-------------|
| `screenshot` | Take a screenshot (full screen or specific window) |
| `get_accessibility_tree` | Get the accessibility tree of a window |
| `get_file_info` | Get file metadata (size, dates, permissions) |

#### Recording
| Tool | Description |
|------|-------------|
| `start_recording` | Start capturing user input events in listen-only mode |
| `stop_recording` | Stop recording and return captured events |

### Interactive Chat

The default `axion` command opens a REPL with rich terminal UX:

- **Streaming output** — Markdown, code blocks, and tool results rendered in real time with syntax highlighting for 16 languages
- **Streaming tables** — Markdown pipe tables auto-detected and rendered as Unicode box-drawing aligned tables
- **Diff-aware code blocks** — Unified diff content in code blocks gets syntax-colored (green additions, red deletions, cyan hunk headers)
- **Markdown extensions** — Strikethrough, task lists (☐/☑), clickable OSC 8 hyperlinks, image placeholders, H1/H2 underlines, blockquotes, italic
- **Turn summary** — Context window progress bar (green/yellow/red), per-turn cost estimate, and response speed analytics (TTFT + tok/s)
- **Prompt bar** — Real-time display of context usage %, cumulative cost, turn count, git branch (with `*` for dirty tree), and configurable via `PromptDisplayConfig` in config.json
- **Rich /status dashboard** — Session elapsed time, turn count, tool usage frequency, visual context progress bar, token breakdown, and estimated cost
- **File change summary** — Tree-structured overview of file operations (Created/Edited/Read) at end of each turn
- **System events** — Codex-style rendering for context compression, rate limits, and task completion notifications
- **Context compaction** — Visual before/after progress bars when context is compressed (auto or `/compact`)
- **File edit approval** — Shows a color-coded diff preview before applying changes; approve, reject, or edit
- **17 slash commands** — `/help`, `/clear`, `/compact`, `/model`, `/cost`, `/diff`, `/status`, `/resume`, `/config`, `/new`, `/fork`, `/archive`, `/skills`, `/copy`, `/storage`, `/apps`, `/exit`
- **Slash popup completion** — Type `/` for popup menu with Tab to complete; `@` for file search
- **Multiline input** — Paste or compose multi-line prompts naturally; `\` continuation for manual line breaks
- **Cross-session history** — Up/Down navigation works across sessions; history persisted to `~/.axion/history.jsonl`
- **Session transcript** — Full conversation (user inputs, assistant responses, tool calls) auto-saved to `~/.axion/sessions/`
- **CJK support** — Full Chinese/Japanese/Korean input handling
- **Startup tips** — First-run welcome message; returning users get random feature discovery tips
- **Shimmer spinner** — Cosine-driven flowing highlight animation on status text during model thinking
- **Session persistence** — Conversations auto-saved; resume with `/resume` or `axion resume`
- **Context management** — `/compact` when context gets long, `/clear` to start fresh
- **Permission modes** — `--accept-edits` for auto-approve file edits, `--dangerously-skip-permissions` for full auto

```bash
# Standard interactive mode
axion

# Auto-approve file edits (still confirms destructive operations)
axion --accept-edits

# Resume a previous session
axion resume

# List all sessions
axion sessions
```

### Cross-run Memory

Axion learns from every task execution through two complementary memory systems:

**App Operation Facts** — Automatically extracts app operation patterns (menu paths, control positions, operation sequences) from MCP tool calls. On subsequent runs involving the same app, the Planner injects this experience for more accurate plans.

**Universal Memory** — Dual-track persistent knowledge covering environment knowledge (MEMORY.md) and user profile/preferences (USER.md). Both the agent during task execution and the background review agent can save discovered knowledge to these files.

```bash
# Memory is enabled by default — view accumulated knowledge
axion memory list

# View universal memory content
axion memory show memory    # Environment knowledge (MEMORY.md)
axion memory show user      # User profile/preferences (USER.md)

# Clear memory for a specific app
axion memory clear --app com.apple.calculator

# Disable memory for a single run
axion run --no-memory "Open Calculator"
```

Memory files are stored in `~/.axion/memory/` and scanned for security threats (prompt injection, credential exfiltration) before loading into prompts.

### Self-Evolution (Review & Curator)

After each run, Axion automatically triggers a **background review** that analyzes the conversation, extracts memory, and evolves skills — no user action required.

**Review Agent** — Automatically runs after task completion:
- Checks if review is needed based on message count and scheduling interval
- Forks a lightweight review agent that inspects the conversation
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
axion curator status     # View status and next run time
axion curator run        # Force-run immediately
axion curator run --dry-run  # Preview changes without modifying
```

### Skill System

Axion integrates with [OpenAgentSDK](https://github.com/terryso/open-agent-sdk-swift)'s Skill system, supporting three types:

| Type | Source | Description |
|------|--------|-------------|
| **Prompt Skills** | `~/.claude/skills/*/SKILL.md` | Markdown-defined prompt templates with optional tool restrictions |
| **Recorded Skills** | `~/.axion/skills/` | JSON workflows compiled from user recordings — no LLM needed for replay |
| **Built-in Skills** | Registered in code | `screenshot-analyze`, `data-extract`, `form-fill` — always available |

**Triggering skills:**

```bash
# Explicit — prefix with /
axion run "/screenshot-analyze analyze the current screen layout"

# Implicit — the LLM automatically picks the right skill based on intent
axion run "fill out the form on screen"

# Dedicated command
axion skill run open-calculator
```

**Recording workflows:**

```bash
axion record "open_calculator"    # Start recording
# ... perform desktop operations ...
# Ctrl-C to stop

axion skill compile open_calculator  # Compile into reusable skill
axion skill run open_calculator      # Replay (no LLM — fast & deterministic)
axion skill list                     # List all skills
```

### HTTP API Server

Run Axion as a service for external integrations:

```bash
axion server --port 4242                # Start API server
axion server --port 4242 --auth-key secret  # With authentication
```

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
axion mcp    # Start MCP stdio server
```

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

### Telegram Gateway

Always-on remote control via Telegram bot with streaming responses, interactive approval keyboards, and skill browsing.

```bash
axion setup                              # Configure bot token & allowed users
axion gateway start                      # Start gateway
axion daemon install --port 4242 --gateway  # Auto-start on login
```

| Command | Description |
|---------|-------------|
| `/help` | Getting started guide |
| `/status` | Gateway status |
| `/skills` | Browse available skills (paginated inline keyboard) |
| `/new` | Start a new session |
| `/stop` | Stop current task |

### User Takeover

When automation gets stuck, Axion pauses and lets you take over manually. Complete the action yourself, then press Enter to resume.

- Press **Enter** — resume after manual fix
- Type **skip** — skip the current step
- Type **abort** — cancel the task
- Type a description — describe what you did (recorded as Memory)

### Completion Notifications

When a task finishes, Axion sends a macOS desktop notification with:
1. **Status** — completed / failed / cancelled
2. **AI Summary** — auto-generated one-line result summary
3. **Stats** — elapsed time, LLM calls, estimated cost

### Daemon Mode & Crash Recovery

Run Axion as a persistent launchd daemon that survives reboots and auto-restarts on crashes:

```bash
axion daemon install --port 4242         # Install (auto-start on login)
axion daemon status                      # Check status
axion daemon uninstall                   # Uninstall
```

All running task state is persisted to disk — in-flight tasks are automatically recovered after unexpected termination.

## Use as Standalone MCP Server

AxionHelper can run as a standalone MCP server for any MCP client:

```bash
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
  "curatorArchiveAfterDays": 90,
  "promptDisplay": {
    "showProgressBar": true,
    "showTurnCount": true,
    "showCost": true,
    "showGitBranch": true
  }
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
├── AxionCLI/              # Agent entry point
│   ├── Chat/              # Interactive REPL (streaming, approval, composer, CJK)
│   │   ├── Rendering/     # StreamingMarkdown, StreamingTable, CodeBlock, SyntaxHighlight
│   │   ├── Theme/         # TranscriptRenderer, BannerRenderer, progress bars
│   │   ├── FileChangeTracker  # Per-turn file operation summary
│   │   ├── SystemEventRenderer # Codex-style system event display
│   │   ├── CompactionDisplayFormatter # Context compaction visualization
│   │   ├── ResponseSpeedTracker # TTFT + tok/s analytics
│   │   ├── ToolUsageTracker   # Per-tool invocation counts
│   │   ├── StatusDashboardFormatter # Rich /status dashboard
│   │   ├── ShimmerText    # Cosine-driven flowing highlight animation
│   │   ├── StartupTipProvider # Feature discovery tips
│   │   ├── SessionTranscriptLogger # Session conversation logging
│   │   ├── CommandHistoryStore # Cross-session history persistence
│   │   └── ClipboardService   # /copy command (pbcopy/OSC 52/tmux)
│   ├── Commands/          # CLI subcommands (chat, run, setup, server, mcp, …)
│   ├── Tools/             # Built-in tool implementations
│   ├── Memory/            # Memory context, extraction, security scanner
│   ├── Skills/            # Skill registry and built-in skills
│   ├── Permissions/       # Tool permission system
│   ├── Helper/            # Helper process lifecycle (stdio)
│   ├── Runtime/           # Event handlers (cost, notification, visual delta, …)
│   ├── Services/          # AxionRuntime, AgentBuilder, RunOrchestrator, Gateway
│   └── API/               # HTTP API server, SSE bridge
├── AxionCore/             # Shared core layer
│   ├── Models/            # RunConfig, AxionConfig, Skill
│   ├── Protocols/         # Service protocols
│   ├── Errors/            # Unified AxionError
│   └── Constants/         # ToolNames, Version
├── AxionHelper/           # MCP server (Helper process)
│   ├── MCP/               # MCPServer, ToolRegistrar (21 tools)
│   ├── Services/          # AccessibilityEngine, Screenshot, InputSimulation
│   └── Models/            # AppInfo, WindowInfo, AXElement

Tests/
├── AxionCoreTests/        # Core model unit tests
├── AxionCLITests/         # CLI command and service tests
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

## Star History

<a href="https://www.star-history.com/?repos=terryso%2Faxion&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=terryso/axion&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=terryso/axion&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=terryso/axion&type=date&legend=top-left" />
 </picture>
</a>

## License

MIT
