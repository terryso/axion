---
title: 'Fix /apps Esc Exit'
type: 'bugfix'
created: '2026-06-13'
status: 'done'
route: 'one-shot'
---

# Fix /apps Esc Exit

## Intent

**Problem:** 在交互模式输入 `/apps` 后，应用列表会进入真实按键读取循环；单独按 Esc 时没有响应，因为底层 escape 序列解析会继续阻塞等待后续字节。

**Approach:** 在 `KeyEventReader` 的 escape 解析入口加入短超时输入探测：有后续字节时继续解析方向键/CSI/SS3 序列，没有后续字节时立即返回 `.escape`，让 `AppSelectionPrompt` 现有取消分支生效。

## Suggested Review Order

**Escape handling**

- Entry point: standalone Esc no longer blocks waiting for sequence bytes.
  [`KeyEventReader+EscapeParsing.swift:14`](../../Sources/AxionCLI/Chat/Composer/KeyEventReader+EscapeParsing.swift#L14)

- `poll` gates the second read without changing existing sequence parsing.
  [`KeyEventReader+EscapeParsing.swift:40`](../../Sources/AxionCLI/Chat/Composer/KeyEventReader+EscapeParsing.swift#L40)

- Reader now supports injectable input fds for realistic parser tests.
  [`KeyEventReader.swift:20`](../../Sources/AxionCLI/Chat/Composer/KeyEventReader.swift#L20)

**Regression tests**

- Pipe-backed test covers Esc byte with write side still open.
  [`KeyEventTests.swift:74`](../../Tests/AxionCLITests/Chat/Composer/KeyEventTests.swift#L74)

- CSI arrow test protects `/apps` navigation and other escape sequences.
  [`KeyEventTests.swift:92`](../../Tests/AxionCLITests/Chat/Composer/KeyEventTests.swift#L92)
