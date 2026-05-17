# Epic 12 手工验收文档（Phase 4 — Memory 生命周期与质量控制）

> 生成日期：2026-05-17
> 分支：feature/phase4-execution-quality
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

## Story 12.1: Memory Fact 模型升级

### AC1: 新记忆以 candidate 状态写入

```bash
# 运行一个简单任务产生记忆
.build/debug/axion run "打开计算器" --max-steps 3

# 验证：检查记忆文件已创建
ls ~/.axion/memory/*-facts.json 2>/dev/null
# 预期：存在至少一个 *-facts.json 文件
```

### AC2: 记忆状态和字段验证

```bash
# 查看记忆内容
.build/debug/axion memory list
# 预期输出格式：
# [domain]
#   ○ [备注] ... (confidence: 0.7, evidence: 1)
# 状态图标：○ candidate / ✓ active / ✗ retired
```

### AC3: 确定性 factId（djb2 hash）

```bash
# 运行相同 App 的任务两次，验证 fact 合并（evidenceCount 递增）
.build/debug/axion run "打开计算器" --max-steps 3
.build/debug/axion run "打开计算器" --max-steps 3

# 再次查看记忆
.build/debug/axion memory list
# 预期：某些记忆的 evidence >= 2，且可能已提升为 active（✓）
```

### AC4: 惰性迁移兼容旧数据

```bash
# 检查旧格式文件（如果存在）
ls ~/.axion/memory/*.json 2>/dev/null | grep -v facts
# 旧格式文件（无 -facts 后缀）仍可被读取
# 读取时自动升级为 AppMemoryFact 写入新文件
```

### AC5: MemoryLifecycleService 替代旧服务

```bash
# 验证 30 天降级（运行后检查 memory list）
# 注：实际降级需等待 30 天，此处验证服务可正常启动
.build/debug/axion run "打开文本编辑器" --max-steps 2 --dryrun
# 预期：正常运行，无 Memory 服务相关报错
```

---

## Story 12.2: 三类记忆分类

### AC1: Affordance 分类（成功路径发现）

```bash
# 运行一个简短的成功任务（直接操作为主）
.build/debug/axion run "打开计算器" --max-steps 3

# 验证分类
.build/debug/axion memory list
# 预期：如果操作以 click/hotkey 为主（步骤 <= 5），出现：
#   ○ [推荐] ... (confidence: 0.72, evidence: 1)
```

### AC2: Avoid 分类（失败经验）

```bash
# 运行一个可能失败的任务
.build/debug/axion run "在不存在的应用中搜索" --max-steps 3

# 验证 avoid 分类
.build/debug/axion memory list
# 预期：可能出现：
#   ○ [警告] ... (confidence: 0.5, evidence: 1)
```

### AC3: Memory 上下文注入 Planner prompt

```bash
# 运行相同 App 的任务，验证记忆被注入
.build/debug/axion run "打开计算器并计算 1+1" --max-steps 5 --verbose 2>&1 | grep -i "推荐路径\|注意事项\|环境备注\|soft hints"
# 预期：如果已有 active 记忆，在 verbose 输出中可见记忆上下文注入
```

### AC4: 列表展示分类信息

```bash
.build/debug/axion memory list
# 预期输出包含：
# - 状态图标（✓ active / ○ candidate / ✗ retired）
# - 类型标签（推荐/警告/备注）
# - confidence 和 evidence_count
```

---

## Story 12.3: Memory 导入/导出

### AC1: 全量导出 Memory Bundle

```bash
# 先确保有记忆数据
.build/debug/axion memory list

# 全量导出
.build/debug/axion memory export /tmp/axion-memory-test.json
# 预期输出：
# [axion] 导出完成: N 个 domain, M 条记忆

# 验证导出文件格式
cat /tmp/axion-memory-test.json | /opt/homebrew/bin/python3 -m json.tool | head -20
# 预期：
# {
#   "schema_version": 1,
#   "exported_at": "2026-05-17T...",
#   "memories": [
#     { "domain": "...", "facts": [...] }
#   ]
# }
```

### AC2: 按 App 过滤导出

```bash
# 按 domain 过滤导出（替换为实际存在的 domain）
DOMAIN=$(cat /tmp/axion-memory-test.json | /opt/homebrew/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(d['memories'][0]['domain']) if d['memories'] else print('none')")
echo "导出 domain: $DOMAIN"

if [ "$DOMAIN" != "none" ]; then
  .build/debug/axion memory export --app "$DOMAIN" /tmp/axion-memory-filtered.json
  # 验证只包含指定 domain
  cat /tmp/axion-memory-filtered.json | /opt/homebrew/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(f'domains: {len(d[\"memories\"])}')"
  # 预期：domains: 1
fi
```

### AC3: 全量导入 Memory Bundle

```bash
# 导入之前导出的文件
.build/debug/axion memory import /tmp/axion-memory-test.json
# 预期输出：
# [axion] 导入完成: N 个 domain, M 条导入, K 条合并

# 验证导入后记忆不覆盖已有 active
.build/debug/axion memory list
# 预期：已有记忆不受影响（本地 active 优先于导入的 candidate）
```

### AC4: 导入错误处理

```bash
# 导入空文件
echo "" > /tmp/bad-memory.json
.build/debug/axion memory import /tmp/bad-memory.json
# 预期：报错 "Invalid memory bundle" + 非零退出码
echo "Exit code: $?"

# 导入格式错误文件
echo '{"bad": "data"}' > /tmp/bad-memory2.json
.build/debug/axion memory import /tmp/bad-memory2.json
# 预期：报错
echo "Exit code: $?"
```

### AC5: 空记忆导出/导入 round-trip

```bash
# 清除记忆后导出
.build/debug/axion memory clear --confirm
.build/debug/axion memory export /tmp/axion-memory-empty.json
# 预期：memories 为空数组

# 导入空 bundle
.build/debug/axion memory import /tmp/axion-memory-empty.json
# 预期：无报错，空操作
```

### 清理

```bash
rm -f /tmp/axion-memory-test.json /tmp/axion-memory-filtered.json /tmp/axion-memory-empty.json /tmp/bad-memory.json /tmp/bad-memory2.json
```

---

## 单元测试验证

```bash
swift test --filter "AxionCLITests.Memory" --filter "AxionCoreTests"
# 预期：所有 Memory 相关测试通过（AppMemoryFactTests, MemoryLifecycleServiceTests,
#       MemoryFactStoreTests, AppMemoryExtractorTests, MemoryContextProviderTests,
#       MemoryListCommandTests, MemoryBundleTests, MemoryBundleExportServiceTests,
#       MemoryBundleImportServiceTests, TakeoverLearningServiceTests, TakeoverMarkerTests）
```

---

## 验收检查清单汇总

| Story | 关键验证点 | 通过 |
|-------|----------|------|
| 12.1 | `memory list` 显示状态图标和 confidence | ☐ |
| 12.1 | 新记忆以 candidate (○) 状态写入 | ☐ |
| 12.1 | 重复观察 evidenceCount 递增 → active 提升 | ☐ |
| 12.2 | `memory list` 显示三类分类（推荐/警告/备注） | ☐ |
| 12.2 | 成功短任务 → affordance (confidence: 0.72) | ☐ |
| 12.2 | 失败任务 → avoid (confidence: 0.5) | ☐ |
| 12.3 | `memory export` → 生成含 schema_version 的 JSON | ☐ |
| 12.3 | `memory export --app` → 只含指定 domain | ☐ |
| 12.3 | `memory import` → 降级为 candidate + imported | ☐ |
| 12.3 | 导入空/错误文件 → 报错 + 非零退出码 | ☐ |
| 12.3 | 空 bundle round-trip 无报错 | ☐ |
| 单元测试 | Memory 测试全部通过 | ☐ |
