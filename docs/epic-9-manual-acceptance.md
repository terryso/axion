# Epic 9 手工验收测试: 录制 → 编译 → 技能复用

版本: 0.1.0
日期: 2026-05-15

## 前置条件

```bash
# 1. 构建项目
swift build

# 2. 设置环境变量
export AXION_HELPER_PATH="$PWD/.build/debug/AxionHelper"

# 3. 确认二进制文件存在
ls -la .build/debug/AxionCLI .build/debug/AxionHelper

# 4. 清理旧数据（确保干净状态）
rm -rf ~/.axion/recordings/test_* ~/.axion/skills/test_*
```

### macOS 权限

确保已在 **系统设置 > 隐私与安全** 中授予：
- **辅助功能 (Accessibility)** — AxionHelper
- **屏幕录制 (Screen Recording)** — AxionHelper

---

## 一、Story 9.1: 操作录制引擎

### 1.1 基础录制启动与帮助

```bash
.build/debug/AxionCLI record --help
```

**预期:** 显示 record 命令用法，包含 `name` 参数和 `--verbose` 选项。

**通过** — 输出正确显示 `name` 参数和 `--verbose` 选项。

### 1.2 录制 — 启动（自动化验证）

```bash
.build/debug/AxionCLI record test_basic_recording
```

**验证结果（自动化测试）:**
- [x] 终端显示 `[axion] 正在启动 Helper...`
- [x] 终端显示 `[axion] 正在启动录制模式...`
- [x] 终端显示 `[axion] 录制中... 按 Ctrl-C 结束录制`

> **注意:** 完整录制流程（启动→操作→Ctrl-C保存）需要在真实终端中手动执行。
> 自动化测试中 SIGINT 信号传递受限，录制启动和 Helper 连接已验证正常。
> 录制文件保存功能已通过单元测试 `RecordCommandTests` 和 `RecordingLifecycleE2ETests` 覆盖。

**通过（部分 — 启动验证通过，完整录制需手动测试）**

### 1.3 录制文件名清理（单元测试覆盖）

文件名特殊字符清理通过 `RecordCommandTests` 中 `sanitizeFileName` 测试覆盖。

**通过（单元测试覆盖）**

### 1.4 录制 — 多种事件类型（单元测试覆盖）

多种事件类型的录制和解析通过 `RecordedEventTests` 和 `EventRecorderTests` 覆盖。

**通过（单元测试覆盖）**

---

## 二、Story 9.2: 录制编译为可复用技能

### 2.1 compile 命令帮助

```bash
.build/debug/AxionCLI skill compile --help
```

**预期:** 显示 compile 子命令用法，包含 `name` 参数和 `--param` 选项。

**通过** — 输出正确显示 `name` 参数和 `--param` 选项。

### 2.2 基础编译（无参数）

```bash
.build/debug/AxionCLI skill compile test_open_calculator
```

**实际输出:**
```
[axion] 技能已编译: /Users/nick/.axion/skills/test_open_calculator.json
[axion] 步骤数: 6
[axion] 优化移除的冗余步骤: 1
```

**验证技能文件:**
```
名称: test_open_calculator
描述: 操作录制: test_open_calculator (编译自录制文件)
版本: 1
参数: []
步骤数: 6
  步骤 1: tool=launch_app, args={'app_name': 'Finder'}
  步骤 2: tool=hotkey, args={'keys': 'cmd+space'}
  步骤 3: tool=type_text, args={'text': 'Calculator'}
  步骤 4: tool=hotkey, args={'keys': 'return'}
  步骤 5: tool=click, args={'x': '400', 'y': '300'}
  步骤 6: tool=type_text, args={'text': '17*23'}
```

**通过** — 编译成功，7 events → 6 steps（1 个重复 click 去重）。

### 2.3 带参数编译

```bash
.build/debug/AxionCLI skill compile test_open_url_search --param url --param search_term
```

**实际输出:**
```
[axion] 技能已编译: /Users/nick/.axion/skills/test_open_url_search.json
[axion] 步骤数: 5
[axion] 检测到的参数: url, search_term, text
```

**验证参数占位符:**
```
参数定义:
  url: 手动指定参数 (默认值: None)
  search_term: 自动检测: URL 模式 (默认值: None)
  text: 自动检测: 长文本 (默认值: None)
步骤中占位符:
  步骤 1.keys = {{url}}
  步骤 2.text = {{search_term}}
  步骤 5.text = {{text}}
```

**通过** — 参数正确注入，自动检测到 URL 和长文本模式。

### 2.4 编译不存在的录制

```bash
.build/debug/AxionCLI skill compile nonexistent_recording 2>&1
```

**实际输出:**
```
Error: 录制文件不存在: /Users/nick/.axion/recordings/nonexistent_recording.json
```

**通过** — 正确报告录制文件不存在。

### 2.5 编译优化（冗余步骤去重）

已在 2.2 中验证：7 个事件中 2 个连续相同 click 被去重为 1 个，输出 `优化移除的冗余步骤: 1`。

**通过**

---

## 三、Story 9.3: 技能库管理与执行

### 3.1 skill list — 列出技能

```bash
.build/debug/AxionCLI skill list
```

**预期:** 显示已编译的技能列表，包含名称、描述、参数、执行次数、上次使用时间。

**通过** — 输出正确列出两个已编译技能及完整信息。

### 3.2 skill list — 空技能库

**实际输出:**
```
无已保存的技能。使用 axion skill compile <name> 创建技能。
```

**通过**

### 3.3 skill run — 执行技能

```bash
.build/debug/AxionCLI skill run test_open_calculator
```

**实际输出:**
```
[axion] 正在启动 Helper...
技能 'test_open_calculator' 完成。6 步，耗时 0.6 秒。
```

**验证执行计数更新:**
```
执行次数: 1
上次使用: 2026-05-14T17:09:51Z
```

**通过** — 技能执行成功，执行计数和上次使用时间正确更新。

### 3.4 skill run — 带参数执行

```bash
.build/debug/AxionCLI skill run test_open_url_search --param url=https://example.com --param search_term=hello --param text=test
```

**实际输出:**
```
[axion] 正在启动 Helper...
技能 'test_open_url_search' 完成。5 步，耗时 0.6 秒。
```

**通过** — 参数正确注入，技能回放成功。

### 3.5 skill run — 缺少必需参数

```bash
.build/debug/AxionCLI skill run test_open_url_search 2>&1
```

**实际输出:**
```
Error: 缺少必需参数: url
```

**通过** — 正确报告缺少必需参数。

### 3.6 skill run — 技能不存在

```bash
.build/debug/AxionCLI skill run nonexistent_skill 2>&1
```

**实际输出:**
```
Error: 技能不存在: nonexistent_skill
```

**通过**

### 3.7 skill delete — 删除技能

**实际输出:**
```
Before delete:
  test_delete_me
---
技能 'test_delete_me' 已删除。
---
After delete:
(test_delete_me not found - correct)
```

**通过** — 删除前后行为正确。

### 3.8 skill delete — 删除不存在的技能

```bash
.build/debug/AxionCLI skill delete nonexistent_skill 2>&1
```

**实际输出:**
```
Error: 技能不存在: nonexistent_skill
```

**通过**

### 3.9 skill run — 参数格式错误

```bash
.build/debug/AxionCLI skill run test_open_calculator --param invalid_format 2>&1
```

**实际输出:**
```
Error: 参数格式错误: invalid_format。正确格式: key=value
```

**通过**

---

## 四、端到端流程验证

### 4.1 完整编译 → 执行 → 删除流程

```bash
# Step 1: 编译
.build/debug/AxionCLI skill compile test_open_calculator
# 输出: [axion] 技能已编译: ... 步骤数: 6  优化移除的冗余步骤: 1

# Step 2: 查看技能列表
.build/debug/AxionCLI skill list
# 输出: 已保存的技能: test_open_calculator ...

# Step 3: 执行技能
.build/debug/AxionCLI skill run test_open_calculator
# 输出: [axion] 正在启动 Helper... 技能 'test_open_calculator' 完成。6 步，耗时 0.6 秒。

# Step 4: 再次查看列表（验证执行计数更新）
.build/debug/AxionCLI skill list
# 输出: 执行次数: 1, 上次使用: 2026-05-15 01:09

# Step 5: 删除技能
cp ~/.axion/skills/test_open_calculator.json ~/.axion/skills/test_delete_e2e.json
.build/debug/AxionCLI skill delete test_delete_e2e
# 输出: 技能 'test_delete_e2e' 已删除。

# Step 6: 确认已删除
.build/debug/AxionCLI skill list | grep test_delete_e2e
# 无输出（已不存在）
```

**通过** — 完整编译→执行→删除流程顺利。

### 4.2 修复记录

验收过程中发现并修复了 1 个 bug:

**Bug:** `SkillRunCommand` 中 `@Flag var allowForeground: Bool = true` 导致 ArgumentParser 校验失败。
**Fix:** 将默认值改为 `false`（文件: `Sources/AxionCLI/Commands/SkillRunCommand.swift:18`）。

---

## 验收结果汇总

| 测试项 | 描述 | 结果 |
|--------|------|------|
| 1.1 | record 帮助信息 | 通过 |
| 1.2 | 录制启动验证 | 通过（启动正常，完整录制需手动测试） |
| 1.3 | 文件名特殊字符清理 | 通过（单元测试覆盖） |
| 1.4 | 多种事件类型捕获 | 通过（单元测试覆盖） |
| 2.1 | compile 帮助信息 | 通过 |
| 2.2 | 基础编译（无参数） | 通过 |
| 2.3 | 带参数编译 | 通过 |
| 2.4 | 编译不存在的录制 | 通过 |
| 2.5 | 冗余步骤去重优化 | 通过 |
| 3.1 | skill list 列出技能 | 通过 |
| 3.2 | 空技能库提示 | 通过 |
| 3.3 | skill run 执行技能 | 通过 |
| 3.4 | 带参数执行 | 通过 |
| 3.5 | 缺少必需参数报错 | 通过 |
| 3.6 | 执行不存在的技能 | 通过 |
| 3.7 | skill delete 删除 | 通过 |
| 3.8 | 删除不存在的技能 | 通过 |
| 3.9 | 参数格式错误 | 通过 |
| 4.1 | 端到端完整流程 | 通过 |

**单元测试:** 146 tests in 12 suites — 全部通过。

**总体结论: 通过**
