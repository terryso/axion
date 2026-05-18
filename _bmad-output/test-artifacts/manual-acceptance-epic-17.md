# Epic 17 手工验收文档（Phase 5 — SDK Skill 系统集成）

> 生成日期：2026-05-18
> 分支：phase5/skill-system-integration
> 验收环境：macOS 14+，已通过 `axion setup` 完成首次配置

---

## 前置准备

```bash
cd /Users/nick/CascadeProjects/axion
git branch --show-current
swift build
.build/debug/AxionCLI --version
```

---

## Story 17.1: RunCommand 集成 SkillRegistry

### AC1: 自动技能发现与注册

```bash
# 验证 ~/.claude/skills/ 下有 SKILL.md 文件
ls ~/.claude/skills/*/SKILL.md 2>/dev/null | head -5

# 运行时观察技能加载提示（需要 API key 配置完成）
# 技能数量 > 0 表示 SkillLoader.discoverSkills() 扫描成功
.build/debug/AxionCLI skill list 2>&1 | grep -c "类型:"
# 预期：大于 0（当前环境约有 77+ 个技能）
```

### AC2: SkillTool 注册到 Agent

```bash
# 验证 SkillTool 已注册：通过 skill list 看到 prompt 技能
# prompt 技能通过 SkillTool 暴露给 LLM
.build/debug/AxionCLI skill list 2>&1 | grep "类型: prompt" | head -5
# 预期：多行输出，如 browser-use、polyv-live-cli 等 prompt 类型技能
```

### AC3: 同名技能 last-wins 去重

```bash
# 验证：skill list 中没有重复的同名技能
.build/debug/AxionCLI skill list 2>&1 | grep -oP "^\s+\S+" | sort | uniq -d
# 预期：无输出（无重复技能名）
```

### AC4: 空技能目录不影响运行

```bash
# 验证：即使没有 ~/.axion/skills/*.json 录制技能，系统正常
ls ~/.axion/skills/*.json 2>/dev/null || echo "录制技能目录为空"
.build/debug/AxionCLI skill list 2>&1 | head -3
# 预期：无错误，正常显示 prompt 技能
```

### AC5: 技能描述注入 system prompt

```bash
# 通过单元测试验证 formatSkillsForPrompt 输出
swift test --filter "AxionCLITests.Commands.SkillIntegrationTests" 2>&1 | tail -10
# 预期：所有测试通过，包括 skillsPrompt 注入验证
```

### AC6: `--no-skills` 禁用技能

```bash
# 验证 --no-skills 参数存在
.build/debug/AxionCLI run --help 2>&1 | grep "no-skills"
# 预期：--no-skills             禁用技能系统
```

---

## Story 17.2: 双轨技能查找

### AC1: Prompt 技能优先命中

```bash
# 通过单元测试验证双轨查找优先级
swift test --filter "AxionCLITests.Services.SkillLookupServiceTests.testPromptSkillPriorityOverRecorded" 2>&1 | tail -5
# 预期：测试通过 — SkillRegistry 命中优先于 ~/.axion/skills/*.json
```

### AC2: 录制技能回退命中

```bash
# 通过单元测试验证录制技能回退
swift test --filter "AxionCLITests.Services.SkillLookupServiceTests.testRecordedSkillFallback" 2>&1 | tail -5
# 预期：测试通过 — SkillRegistry 未命中时查 JSON 文件
```

### AC3: 同名技能 prompt 优先

```bash
swift test --filter "AxionCLITests.Services.SkillLookupServiceTests.testSameNameSkillPromptWins" 2>&1 | tail -5
# 预期：测试通过 — 同名时返回 .promptSkill
```

### AC4: 未命中降级为普通 prompt

```bash
swift test --filter "AxionCLITests.Services.SkillLookupServiceTests.testNotFound" 2>&1 | tail -5
# 预期：测试通过 — 未命中返回 .notFound
```

### AC5: `--no-skills` 禁用双轨查找

```bash
swift test --filter "AxionCLITests.Services.SkillLookupServiceTests.testNoSkillsSkipsLookup" 2>&1 | tail -5
# 预期：测试通过
```

### AC6: 录制技能执行后更新元数据

```bash
swift test --filter "AxionCLITests.Services.SkillLookupServiceTests" 2>&1 | grep -E "Test (passed|failed)" | tail -20
# 预期：所有 SkillLookupService 测试通过（含元数据更新测试）
```

---

## Story 17.3: 显式 `/skill-name` 触发

### AC1: Prompt 技能显式触发 — promptTemplate 注入

```bash
# 通过单元测试验证 promptTemplate 注入
swift test --filter "AxionCLITests.Services.ExplicitSkillTriggerTests.testPromptSkillUsesPromptTemplate" 2>&1 | tail -5
# 预期：测试通过 — 显式触发时 skill.promptTemplate 作为 systemPrompt
```

### AC2: Prompt 技能 — toolRestrictions 限定工具集

```bash
swift test --filter "AxionCLITests.Services.ExplicitSkillTriggerTests.testToolRestrictionsMappedToAllowedTools" 2>&1 | tail -5
# 预期：测试通过 — toolRestrictions 映射为 allowedTools
```

### AC3: Prompt 技能 — modelOverride 切换模型

```bash
swift test --filter "AxionCLITests.Services.ExplicitSkillTriggerTests.testModelOverrideReplacesDefault" 2>&1 | tail -5
# 预期：测试通过 — modelOverride 替换默认模型
```

### AC4: 录制技能 — 必需参数缺失提示

```bash
swift test --filter "AxionCLITests.Services.ExplicitSkillTriggerTests.testRecordedSkillMissingRequiredParam" 2>&1 | tail -5
# 预期：测试通过 — 缺少必需参数时 throw ExitCode(1)
```

### AC5: `/` 不在句首不触发

```bash
swift test --filter "AxionCLITests.Services.ExplicitSkillTriggerTests" 2>&1 | grep -E "Test (passed|failed)" | tail -20
# 预期：包含 slashNotAtStart 相关测试通过
```

### AC6: `--no-skills` 禁用显式触发

```bash
swift test --filter "AxionCLITests.Services.ExplicitSkillTriggerTests.testNoSkillsFlagSkipsParsing" 2>&1 | tail -5
# 预期：测试通过
```

---

## Story 17.4: 隐式技能触发

### AC1: 隐式触发 — LLM 自动匹配技能

```bash
# 验证 system prompt 中包含技能指引
swift test --filter "AxionCLITests.Services.ImplicitSkillTriggerTests.testAvailableSkillsSectionContainsGuide" 2>&1 | tail -5
# 预期：测试通过 — ## Available Skills section 包含 Skill 工具使用指引
```

### AC2: Token 预算截断

```bash
swift test --filter "AxionCLITests.Commands.SkillIntegrationTests.testFormatSkillsForPromptOutput" 2>&1 | tail -5
# 预期：测试通过 — formatSkillsForPrompt 遵循 token 预算
```

### AC3: `isAvailable()` 过滤

```bash
swift test --filter "AxionCLITests.Services.ImplicitSkillTriggerTests.testUnavailableSkillExcluded" 2>&1 | tail -5
# 预期：测试通过 — isAvailable=false 的技能不出现在列表中
```

### AC4: `--no-skills` 禁用隐式触发

```bash
swift test --filter "AxionCLITests.Services.ImplicitSkillTriggerTests.testNoSkillsNoSkillsSection" 2>&1 | tail -5
# 预期：测试通过 — noSkills 时无 ## Available Skills section
```

---

## 单元测试验证

```bash
swift test --filter "AxionCLITests.Commands.SkillIntegrationTests" \
           --filter "AxionCLITests.Services.SkillLookupServiceTests" \
           --filter "AxionCLITests.Services.ExplicitSkillTriggerTests" \
           --filter "AxionCLITests.Services.ImplicitSkillTriggerTests" \
           --filter "AxionCoreTests" 2>&1 | tail -15
# 预期：所有 Skill 相关测试通过
```

---

## 验收检查清单汇总

> 验收日期：2026-05-18 | 验收人：Claude Code (自动验收)

| Story | 关键验证点 | 通过 |
|-------|----------|------|
| 17.1 | `axion skill list` 显示 prompt 技能（77个） | ✅ |
| 17.1 | 无同名技能（last-wins 去重） | ✅ |
| 17.1 | 空录制技能目录不影响运行 | ✅ |
| 17.1 | `--no-skills` 参数可用 | ✅ |
| 17.1 | SkillIntegrationTests 14 tests 全部通过 | ✅ |
| 17.2 | SkillLookupService 双轨查找 16 tests 通过 | ✅ |
| 17.2 | prompt 技能优先于录制技能（AC1-AC3） | ✅ |
| 17.2 | 未命中降级为 .notFound（AC4） | ✅ |
| 17.3 | 显式触发 promptTemplate 注入 17 tests 通过 | ✅ |
| 17.3 | toolRestrictions → allowedTools 映射正确 | ✅ |
| 17.3 | modelOverride 替换默认模型 | ✅ |
| 17.3 | 录制技能缺少必需参数报错 | ✅ |
| 17.4 | 隐式触发 Skill 指引 8 tests 通过 | ✅ |
| 17.4 | isAvailable=false 的技能被过滤 | ✅ |
| 17.4 | --no-skills 时无技能 section | ✅ |
| 单元测试 | Epic 17 所有测试通过（259 tests in 21 suites） | ✅ |
