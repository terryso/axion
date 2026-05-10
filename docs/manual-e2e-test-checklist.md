# Axion 手工 E2E 验收测试

版本: 0.1.0
日期: 2026-05-11

## 前置条件

```bash
# 1. 构建项目
swift build

# 2. 设置环境变量（开发模式下指向本地 Helper）
export AXION_HELPER_PATH="$PWD/.build/debug/AxionHelper"

# 3. 确认 Helper 可执行
ls -la .build/debug/AxionHelper
```

### macOS 权限

在开始之前，确保已在 **系统设置 > 隐私与安全** 中授予：
- **辅助功能 (Accessibility)** — 添加 AxionHelper
- **屏幕录制 (Screen Recording)** — 添加 AxionHelper（截图功能需要）

---

## 一、基础命令 (Epic 2: Story 2.1, 2.2)

### 1.1 帮助信息

```bash
axion --help
```

**预期:** 显示 `run`、`setup`、`doctor` 三个子命令及其说明。

**通过 / 失败**

### 1.2 版本号

```bash
axion --version
```

**预期:** 输出 `0.1.0`。

**通过 / 失败**

### 1.3 未知命令

```bash
axion unknown-command
```

**预期:** 显示错误提示和帮助信息。

**通过 / 失败**

---

## 二、配置系统 (Epic 2: Story 2.2, 2.3)

### 2.1 axion setup — 首次配置

```bash
axion setup
```

**验收步骤:**
1. 提示选择 Provider（Anthropic / OpenAI Compatible）
2. 输入 API Key（输入时不回显）
3. 可选输入 Base URL（留空使用默认）
4. 保存配置到 `~/.axion/config.json`
5. 检查 Accessibility 和屏幕录制权限
6. 显示 "Setup complete!"

**验证配置文件:**

```bash
cat ~/.axion/config.json
```

**预期:** JSON 文件包含 `apiKey`（脱敏确认）、`provider`、`model` 等字段，文件权限 `600`。

```bash
stat -f "%OLp" ~/.axion/config.json
```

**预期:** 输出 `600`。

**通过 / 失败**

### 2.2 环境变量覆盖

```bash
AXION_API_KEY="sk-test-override" axion doctor
```

**预期:** doctor 报告中 API Key 显示为 `sk-tes***...ide`（使用环境变量的值）。

**通过 / 失败**

### 2.3 API Key 不泄露

```bash
axion run "打开计算器" --verbose 2>&1 | grep -i "sk-ant"
```

**预期:** 无任何匹配输出。API Key 不出现在终端输出中。

**通过 / 失败**

---

## 三、环境检查 (Epic 2: Story 2.4)

### 3.1 axion doctor — 全部通过

```bash
axion doctor
```

**预期输出包含 5 项检查，全部 `[OK]`:**
- `[OK]  配置文件: ~/.axion/config.json`
- `[OK]  API Key: sk-ant-***...xxx`
- `[OK]  macOS 版本: 14.x.x`
- `[OK]  Accessibility: 已授权`
- `[OK]  屏幕录制: 已授权`
- `All checks passed!`

**通过 / 失败**

### 3.2 axion doctor — 部分失败

临时移除 API Key 后运行：

```bash
# 备份配置
cp ~/.axion/config.json ~/.axion/config.json.bak
# 修改配置移除 apiKey
/opt/homebrew/bin/python3 -c "
import json
with open('$HOME/.axion/config.json') as f: c = json.load(f)
c.pop('apiKey', None)
with open('$HOME/.axion/config.json', 'w') as f: json.dump(c, f)
"
axion doctor
# 恢复配置
cp ~/.axion/config.json.bak ~/.axion/config.json
```

**预期:** API Key 行显示 `[FAIL]`，并给出修复建议 `运行 axion setup 配置 API Key`。

**通过 / 失败**

---

## 四、基础桌面操作 (Epic 1: Story 1.3, 1.4, 1.5)

### 4.1 启动应用 + 窗口管理

```bash
axion run "打开计算器"
```

**预期:**
- 终端显示执行步骤（launch_app）
- Calculator.app 打开
- 任务完成，显示汇总信息

**通过 / 失败**

### 4.2 键盘操作 — 计算

```bash
axion run "用计算器计算 17 乘以 23"
```

**预期:**
- Calculator 打开（如未打开）
- 按键操作: 1, 7, ×, 2, 3, =
- 结果显示 391

**通过 / 失败**

### 4.3 文本输入

```bash
axion run "打开 TextEdit，输入 Hello World"
```

**预期:**
- TextEdit 打开
- 文本 "Hello World" 出现在编辑区

**通过 / 失败**

> 测试后清理: 关闭 TextEdit（Cmd+Q），不保存。

### 4.4 URL 打开

```bash
axion run "打开 https://example.com"
```

**预期:** 默认浏览器打开 example.com。

**通过 / 失败**

### 4.5 Finder 导航

```bash
axion run "打开 Finder，进入下载目录"
```

**预期:** Finder 打开并导航到 Downloads 文件夹。

**通过 / 失败**

---

## 五、运行模式与控制 (Epic 3: Story 3.6)

### 5.1 干跑模式

```bash
axion run "打开计算器" --dryrun
```

**预期:**
- 显示任务计划但不实际执行工具调用
- 不会打开任何应用
- 输出包含计划描述后结束

**通过 / 失败**

### 5.2 JSON 输出

```bash
axion run "打开计算器" --json
```

**预期:** 输出合法 JSON，包含 `runId`、`task`、`status`、`steps`、`numTurns` 字段。

验证:

```bash
axion run "打开计算器" --json | /opt/homebrew/bin/python3 -m json.tool
```

**预期:** JSON 格式化成功，无解析错误。

**通过 / 失败**

### 5.3 步数限制

```bash
axion run "打开计算器，计算 1+2+3+4+5+6+7+8+9+10" --max-steps 3
```

**预期:** 执行不超过 3 步后停止，显示步数限制信息。

**通过 / 失败**

### 5.4 详细模式

```bash
axion run "打开计算器" --verbose
```

**预期:** 输出比普通模式更详细的调试信息（SDK 日志等），API Key 仍然不出现。

**通过 / 失败**

### 5.5 Ctrl-C 中断

```bash
axion run "打开 TextEdit，输入一段很长的文章：今天天气很好"
```

**操作:** 任务执行过程中按 `Ctrl-C`。

**预期:**
- 任务立即中断
- Helper 进程被清理（不残留）
- 终端显示 "已取消" 或类似信息

**验证无残留进程:**

```bash
ps aux | grep AxionHelper
```

**预期:** 无 AxionHelper 进程。

**通过 / 失败**

### 5.6 前台模式 vs 共享座椅模式

```bash
# 默认共享座椅模式（sharedSeatMode=true）— 前台操作应被阻止
axion run "点击屏幕坐标 (100, 100)"
```

**预期:** 默认共享座椅模式下，click 等前台操作被阻止或受限。

```bash
# 允许前台操作
axion run "打开计算器" --allow-foreground
```

**预期:** `--allow-foreground` 模式下正常执行前台操作。

**通过 / 失败**

---

## 六、智能行为 (Epic 3: Story 3.2)

### 6.1 纯知识问题 — 不调用工具

```bash
axion run "4+9等于几？"
```

**预期:** 直接回答 "13"，不打开计算器，不调用任何工具。

**通过 / 失败**

### 6.2 多步任务 — 自动规划

```bash
axion run "打开 Safari，访问 github.com"
```

**预期:**
- Agent 自动规划步骤（launch_app → open_url 或直接 open_url）
- Safari 打开 github.com
- 终端显示多步执行过程

**通过 / 失败**

---

## 七、Trace 记录 (Epic 3: Story 3.5)

### 7.1 Trace 文件生成

```bash
axion run "打开计算器"
```

**验证:**

```bash
ls ~/.axion/runs/
```

**预期:** 生成以日期开头的 run 目录（如 `20260511-xxxxxx/`）。

```bash
cat ~/.axion/runs/*/trace.jsonl | head -5
```

**预期:**
- 每行是独立 JSON 对象
- 包含 `ts`（ISO8601 时间戳）和 `event` 字段
- 事件类型包括: `run_start`, `assistant_message`, `tool_use`, `tool_result`, `result`, `run_done`

**通过 / 失败**

---

## 八、错误处理 (Epic 3: Story 3.3, NFR5, NFR7)

### 8.1 不存在的应用

```bash
axion run "打开 NonExistentApp12345"
```

**预期:**
- Agent 尝试后失败
- 显示友好的错误信息（不暴露内部堆栈）
- 任务最终报告失败

**通过 / 失败**

### 8.2 Helper 未找到

```bash
unset AXION_HELPER_PATH
# 确保默认路径也不存在
axion run "打开计算器" 2>&1
```

**预期:** 显示明确的错误信息，提示运行 `axion doctor` 诊断。

> 测试后恢复: `export AXION_HELPER_PATH="$PWD/.build/debug/AxionHelper"`

**通过 / 失败**

### 8.3 API Key 无效

```bash
AXION_API_KEY="sk-ant-invalid-key" axion run "打开计算器" 2>&1
```

**预期:** 显示 API 认证错误，不暴露完整的 API Key。

**通过 / 失败**

---

## 九、端到端综合场景 (Epic 3: Story 3.8)

### 9.1 计算器完整流程

```bash
axion run "打开计算器，计算 391 除以 17"
```

**预期:**
- Calculator 打开
- 按键: 3, 9, 1, ÷, 1, 7, =
- 结果显示 23
- 终端显示完成信息（步数、耗时）

**通过 / 失败**

### 9.2 TextEdit 完整流程

```bash
axion run "打开 TextEdit，新建文档，输入 'Axion E2E Test'，然后全选复制"
```

**预期:**
- TextEdit 打开并新建文档
- 输入文字
- 执行 Cmd+A (全选) + Cmd+C (复制)
- 终端显示任务完成

**通过 / 失败**

> 测试后清理: 关闭 TextEdit（Cmd+Q），不保存。

### 9.3 多应用协同

```bash
axion run "打开计算器计算 25 乘以 4，然后打开 TextEdit 把结果写进去"
```

**预期:**
- Calculator 打开并计算 25×4=100
- TextEdit 打开
- "100" 被输入到 TextEdit

**通过 / 失败**

> 测试后清理: 关闭 Calculator 和 TextEdit。

---

## 十、构建与自动化测试

### 10.1 单元测试

```bash
make test
```

**预期:** 全部通过（跳过集成测试和 e2e 测试）。

**通过 / 失败**

### 10.2 E2E 测试（需要 Helper + AX 权限）

```bash
make test-e2e
```

**预期:** MockLLME2ETests 全部通过。RealLLME2ETests 如有 API Key 且 Helper 可用也通过。

**通过 / 失败**

---

## 验收总结

| 章节 | 测试项数 | 通过 | 失败 |
|------|---------|------|------|
| 一、基础命令 | 3 | | |
| 二、配置系统 | 3 | | |
| 三、环境检查 | 2 | | |
| 四、基础桌面操作 | 5 | | |
| 五、运行模式与控制 | 6 | | |
| 六、智能行为 | 2 | | |
| 七、Trace 记录 | 1 | | |
| 八、错误处理 | 3 | | |
| 九、端到端综合场景 | 3 | | |
| 十、构建与自动化测试 | 2 | | |
| **总计** | **30** | | |

验收人: ________________  日期: ________________

总体结论: 通过 / 不通过
