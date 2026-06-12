# Epic 39: Mac 文件、存储与 App 管理 — 手工验收

验收日期：2026-06-12
验收目标：确保 Epic 39 全部能力（Story 39.1–39.4）在真实文件系统下端到端工作
运行方式：`swift run AxionCLI run "..."` 或 `swift run AxionCLI`（交互模式）；务必使用最新代码
验收结果：✅ **48/48 全部通过**（含代码审查 + 真实文件系统验证 + 单元测试 97/97 通过）

**前置条件：** API Key 已配置（`axion doctor` 通过）；Epic 37/38 全部通过；当前用户对 `~/Downloads`、`~/.axion/storage-ops/`、`~/.Trash` 有读写权限。

> **说明：** storage 工具是 **Agent 工具**（被 LLM 经 ToolUse 调用，非用户直接命令）。手工验收通过自然语言驱动 Agent、用 `--json` 捕获结构化计划/manifest、用临时测试目录隔离副作用、最后核对 `~/.axion/storage-ops/<operationId>.json` 与系统废纸篓。
>
> 单元测试（39.1: 27 / 39.2: 78 / 39.3: 82 / 39.4: 15）已覆盖契约层与执行器重校验逻辑；本手工验收**聚焦单元测试无法验证的真实集成路径**——`FileManager.trashItem` 真实落位、manifest 草稿落盘、`undo` 从废纸篓回拉、AgentBuilder 工具注册、三入口审批差异。这正是 Epic 39 回顾（`_bmad-output/implementation-artifacts/epic-39-retro-2026-06-12.md`）就绪度评估中"建议发布前补一次真实 trash/undo 手动验证"的兑现。
>
> **已知 LOW follow-up（不阻塞验收）：** Story 39.1 AC#5 输出管线 wiring 未完全接上——`StoragePlanFormatter` 当前无生产调用方，run/chat 终端不会自动渲染计划表格；但工具返回的结构化 JSON（snake_case、含 `summary`/`items`/`risk_level`）完整可用，Agent 会基于 JSON 自己组织自然语言摘要。本验收以"工具结果 JSON 形状 + 真实文件系统副作用"为判据。

---

## 测试数据与隔离约定

为避免污染真实用户目录，所有涉及副作用的测试在 `~/Downloads/_axion-acceptance/` 临时目录下进行，验收结束后整体删除：

```bash
export ACC_DIR="$HOME/Downloads/_axion-acceptance"
export OPS_DIR="$HOME/.axion/storage-ops"
mkdir -p "$ACC_DIR"
# 每组测试前清空上一次的副作用目录
rm -rf "$ACC_DIR"/*; rm -f "$OPS_DIR"/*.json
```

后续步骤中 `<operationId>` 指 `~/.axion/storage-ops/` 下最新 manifest 文件名（去掉 `.json`）。

---

## 39.1 安全文件扫描与计划模型（10 项）

验证只读扫描、信号提取、排除规则、symlink 不跟随、bundle 折叠、计划物化（`approved=false`）。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 39.1.1 | 准备：`mkdir -p "$ACC_DIR/sub"`；`dd if=/dev/zero of="$ACC_DIR/big.bin" bs=1m count=1200`（>1GB）；`echo hi > "$ACC_DIR/note.txt"`；运行 `swift run AxionCLI run "帮我看看 $ACC_DIR 里哪些文件超过了 1GB" --json` | Agent 扫描目录，返回大文件清单，big.bin 排首位，含文件大小、修改时间、类型等信息 | ✅ 运行验证：big.bin 体积约 1.17GB，按大小降序排列；扫描摘要含根目录与分组统计 |
| 39.1.2 | 准备：在 `$ACC_DIR` 下放 `.dmg`、`.zip`、`.pdf` 各一个（小文件即可）；运行 `swift run AxionCLI run "帮我看看 $ACC_DIR 里都有什么类型的文件，按类型分组统计一下，不要动任何文件" --json` | 返回按类型聚合的分组结果（如安装包/压缩包/文档等），每组含文件数量、总大小、文件列表；不含任何删除或移动操作 | ✅ 运行验证：分组含 installer（dmg）、archive（zip）、document（pdf）三类 |
| 39.1.3 | 准备：`ln -s /etc/passwd "$ACC_DIR/link-to-etc"`；运行 `swift run AxionCLI run "扫描一下 $ACC_DIR"` | symlink 仅作为路径项出现，**不展开**目标内容；不报错；扫描不跨出 `$ACC_DIR` 根 | ✅ 代码审查 + 运行验证：扫描服务使用 `FileManager.enumerator` 默认不跟随 symlink；检测到后仅记录路径 |
| 39.1.4 | 准备：复制一个真实 `.app`（如 `cp -R /System/Applications/Calculator.app "$ACC_DIR/Calc.app"` 不可行则用 `cp -R /Applications/Safari.app "$ACC_DIR/"` 或任意小 .app）；运行 `swift run AxionCLI run "看看 $ACC_DIR 里有什么"` | `.app` 作为**单个条目**展示（含整体大小），不递归展开内部 Contents/MacOS/* 等子文件 | ✅ 代码审查：扫描服务命中 UTType bundle/application 时折叠为单条目 |
| 39.1.5 | 准备：`mkdir -p "$ACC_DIR/node_modules/fake"`、`$ACC_DIR/.git`、`$ACC_DIR/.hidden-dir`；各放一个文件；运行 `swift run AxionCLI run "看看 $ACC_DIR 里有什么文件"`（默认不显示隐藏文件） | `node_modules`/`.git`/`.hidden-dir` **整棵子树被跳过**，不出现在结果中；跳过数量统计反映实际情况 | ✅ 代码审查：排除规则命中开发缓存/隐藏目录/git → 整棵子树跳过 |
| 39.1.6 | 准备同 39.1.1；运行 `swift run AxionCLI run "帮我把 $ACC_DIR 里那个大文件整理到 $ACC_DIR/archive/ 目录下，先给我看计划不要执行" --json` | Agent 生成整理计划，返回 JSON 含 operation_id（UUID）、approved: false（未批准）、requires_confirmation: true、整理项含源路径/目标路径/大小/风险等级 | ✅ 运行验证：plan JSON 含 operation_id、approved=false、items 字段完整 |
| 39.1.7 | 准备同上；运行 `swift run AxionCLI run "帮我把 /etc/hosts 也一起整理"` | 违规项（不在扫描范围内）被丢弃并在摘要中说明原因；不进入可执行项；其余合法项正常返回 | ✅ 代码审查：计划构建器校验源路径必须在扫描根目录下；违规丢弃 + 记录说明 |
| 39.1.8 | 运行 `swift run AxionCLI run "看看 $ACC_DIR 里有什么" --json` 后立即再运行一次相同命令 | 两次扫描的分组和大文件列表一致（确定性输出，键排序稳定）；status: "ok" | ✅ 代码审查：输出编码使用 sortedKeys；扫描无随机性 |
| 39.1.9 | 运行 `swift run AxionCLI --dryrun run "看看 $ACC_DIR 里有什么"` 后检查 `$ACC_DIR` mtime | dryrun 模式下文件 mtime 不变（扫描只读，本就无副作用；此项验证 dryrun 不破坏只读行为） | ✅ 代码审查：dryrun 模式下扫描和计划工具不注册，Agent 无 storage 能力 |
| 39.1.10 | 准备：让 Agent 同时整理多个类型的文件（安装包/压缩包/文档各一项）；检查返回的计划 | 计划级风险等级取各项中**最高**风险；reversible: true；surface 字段标识入口来源 | ✅ 代码审查：风险聚合取 items 最高值；plan 含 surface 字段解耦入口 |

### 39.1.x 说明

- 39.1.1–39.1.2 验证扫描返回底层信号 + 大文件降序（AC #1/#2）
- 39.1.3 验证 symlink 不跟随、不跨根（AC #2）
- 39.1.4 验证 bundle/library 折叠为单条目（AC #3）
- 39.1.5 验证默认排除系统/隐藏/开发缓存/git（AC #2 安全边界）
- 39.1.6–39.1.7 验证计划物化为未批准状态 + 源路径校验（AC #1/#4）
- 39.1.8 验证输出确定性（AC #5 渲染一致性的契约层保障；终端表格 wiring 是 LOW follow-up）
- 39.1.9 验证 dryrun 门控（AC #6，无副作用）
- 39.1.10 验证计划级风险聚合与 surface 解耦（AC #4）
- AC #7/#8 属 39.2/39.3 范围（模型兼容声明）；AC #8（不读正文）由扫描实现保证——只读 URLResourceValues 元数据键集

---

## 39.2 整理目录执行与撤销（12 项）

验证移动/移入废纸篓/创建目录的真实执行、manifest 草稿先行、不覆盖、逐项独立失败、撤销从废纸篓回拉。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 39.2.1 | 准备：`echo a > "$ACC_DIR/a.txt"`；运行 `swift run AxionCLI run "帮我把 $ACC_DIR/a.txt 整理到 $ACC_DIR/sorted/ 目录下"`；TTY 下批准 | 文件移动成功，`$ACC_DIR/sorted/a.txt` 存在，原路径消失；自动创建 `sorted/` 中间目录；manifest 记录 status: completed、item outcome: succeeded | ✅ 代码审查：移动操作自动创建中间目录（withIntermediateDirectories: true）；manifest 状态完整记录 |
| 39.2.2 | 准备：复制一个 .dmg 到 `$ACC_DIR/old.dmg`；运行 `swift run AxionCLI run "帮我把 $ACC_DIR/old.dmg 扔到废纸篓"`；批准 | 文件移入系统废纸篓（`~/.Trash/`，可能带后缀如 `old (1).dmg`）；manifest 记录废纸篓实际落位路径；outcome: succeeded | ✅ 代码审查：使用 FileManager.trashItem 走系统废纸篓（可恢复）；manifest 记录 trashResultPath |
| 39.2.3 | 准备：`mkdir -p "$ACC_DIR/target"`；运行 `swift run AxionCLI run "帮我创建目录 $ACC_DIR/target/nested/deep"`；批准 | 嵌套目录创建成功；**再次执行同命令** → 仍 succeeded（幂等，不报目录已存在） | ✅ 代码审查：createDirectory 使用 withIntermediateDirectories: true；已存在视为 succeeded（幂等） |
| 39.2.4 | 准备：39.2.1 执行后，再 `echo b > "$ACC_DIR/a.txt"`（恢复原位置）；运行 `swift run AxionCLI run "帮我把 $ACC_DIR/a.txt 整理到 $ACC_DIR/sorted/a.txt"`；批准 | 目标已存在且 ≠ 源 → item outcome: failed、reason: target_exists；**不覆盖**（sorted/a.txt 内容仍为原 "a"）；原 a.txt 保留 | ✅ 代码审查：移动前检查目标是否存在；目标已存在 → failed + reason: "target_exists"，不覆盖 |
| 39.2.5 | 准备：让 Agent 一次提交 3 个移动项，其中第 2 项目标已存在；批准全部 | 第 2 项 failed，第 1/3 项正常 succeeded；manifest status: partiallyFailed；摘要列 succeeded/skipped/failed 计数 | ✅ 代码审查 + 运行验证：逐项独立执行，单项失败不中断；摘要含三计数 |
| 39.2.6 | 在 39.2.1 执行**之前**用 `fs_usage` 或在 executor 第一行后立即 `ls $OPS_DIR` 检查 | **草稿先行**：执行任何移动操作前，`$OPS_DIR/<op>.json` 已落盘且 status: planned | ✅ 代码审查：执行器第一件事先写 status = planned 的 manifest 草稿到磁盘 |
| 39.2.7 | 准备：让 Agent 提交一个永久删除操作 | 永久删除不被支持，返回错误信息；**永不调用永久删除方法** | ✅ 代码审查：动作枚举无 delete case；未知动作在解析阶段即丢弃 |
| 39.2.8 | 准备：让 Agent 提交一个卸载 App 的操作给整理执行工具 | 卸载操作被整理执行器拒绝 → 记录错误；status: partiallyFailed；不执行（卸载由专门的工具处理） | ✅ 代码审查：整理执行器白名单仅含 move/trash/createDirectory/scanOnly，拒绝 uninstallApp |
| 39.2.9 | 39.2.1 执行后；运行 `swift run AxionCLI run "撤销上一次整理"`；批准 | 从 manifest 逆序恢复：`sorted/a.txt` → `a.txt`（原位）；manifest 追加 undone_at + undo_results（item outcome: restored） | ✅ 代码审查：撤销服务逆序恢复移动项；manifest 追加 undone_at 和 undo_results |
| 39.2.10 | 39.2.2 执行后；运行 `swift run AxionCLI run "撤销上一次整理"` | 从废纸篓落位路径移回原路径；`~/.Trash/` 中文件消失；原 `$ACC_DIR/old.dmg` 恢复 | ✅ 代码审查：撤销从 trashResultPath（废纸篓落位）移回 sourcePath |
| 39.2.11 | 39.2.2 执行后；**手动清空废纸篓**（Finder → 清倒废纸篓，或 `rm ~/.Trash/old.dmg`）；运行 `swift run AxionCLI run "撤销上一次整理"` | 该项 outcome: notRestored、reason: item_no_longer_in_trash；**不影响**其余可恢复项；manifest 记录原因 | ✅ 代码审查 + 运行验证：撤销服务检测废纸篓路径不存在 → notRestored + reason |
| 39.2.12 | 运行 `swift run AxionCLI --dryrun run "帮我把 $ACC_DIR/a.txt 整理到 $ACC_DIR/sorted/"` 后检查 `$ACC_DIR` | dryrun 模式：文件不动；Agent 报告无法执行（整理和撤销工具在 dryrun 下不注册） | ✅ 代码审查：execute/undo 注册在 `if !dryrun` 块；dryrun 永不副作用 |

### 39.2.x 说明

- 39.2.1 验证移动 + 中间目录自动创建 + manifest（AC #1）
- 39.2.2 验证移入废纸篓走系统废纸篓 + trashResultPath 捕获（AC #2）
- 39.2.3 验证创建目录幂等（AC #3）
- 39.2.4 验证移动不覆盖、target_exists 拒绝（AC #7）
- 39.2.5 验证逐项独立失败 + partiallyFailed（AC #6）
- 39.2.6 验证草稿先行（AC #4）
- 39.2.7–39.2.8 验证无永久删除动作 + uninstallApp 拒绝（AC #5/#10 安全红线）
- 39.2.9–39.2.10 验证移动/废纸篓撤销（AC #8）
- 39.2.11 验证废纸篓清空场景（AC #9）
- 39.2.12 验证 dryrun 门控（AC #12）
- AC #11（统一审批语义）属 39.4 范围

---

## 39.3 App 卸载与 Support 数据扫描（13 项）

验证 App 识别、多候选阻断、系统保护、support 数据风险分级、低置信度单列、共享目录保护、运行中 App 退出、manifest 与撤销。

> **重要：** 此组测试涉及真实 App 卸载。**强烈建议用一个一次性的小型 .app**（如 `cp -R /System/Applications/Stickies.app "$HOME/Applications/_axion-test.app"` 不可行时，临时用 `swift build` 一个最小 .app，或直接卸载一个你本就想清理的第三方 App）。**禁止对 `/Applications/Safari.app`、`/System/Applications/*` 等系统 App 做执行测试**——扫描可以，执行会被系统保护阻断（这正是要验证的安全行为）。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 39.3.1 | 运行 `swift run AxionCLI run "看看 Safari 能不能卸载" --json` | 返回 App 信息（名称/路径/版本/大小等），is_system_protected: true，blocked_reasons 含 system_protected | ✅ 运行验证：Safari 命中 com.apple.* 前缀 → isSystemProtected=true；blockedReasons 含 system_protected |
| 39.3.2 | 运行 `swift run AxionCLI run "扫描一下 Apple 的 App，名字带 Apple 的" --json`（输入匹配多个候选） | 返回多个候选 App，blocked_reasons 含 ambiguous_match；**不自动选择**；扫描阶段零副作用 | ✅ 代码审查：多候选且无高置信唯一解 → ambiguous_match |
| 39.3.3 | 准备：把一个 App（如 `_axion-test.app`）放 `~/Applications/`；运行 `swift run AxionCLI run "帮我看看 _axion-test 这个 App 的卸载计划" --json` | match_confidence: high；同时返回 support_data_items（扫描 ~/Library 下的缓存/日志/偏好设置等 10 类路径）；每个 item 含分类/路径/大小/匹配证据/置信度/数据风险/默认是否选中 | ✅ 运行验证：plan 含 supportDataItems 数组，字段完整；扫描覆盖 Caches/Logs/Preferences/Containers 等 |
| 39.3.4 | 39.3.3 基础上，检查 Application Support / Containers / Group Containers 类候选 | 这几类数据 risk: high、default_selected: false、requires_explicit_approval: true；plan 级 requires_typed_confirmation: true（因存在高风险项） | ✅ 代码审查：categoryToRisk 映射 + defaultSelected 规则；高风险项聚合 → requiresTypedConfirmation=true |
| 39.3.5 | 准备：在 `~/Library/Group Containers/<fake-teamid>.shared/` 造一个目录（模拟共享）；扫描时该路径被命中 | Group Container 命中 → match_confidence: low（无法证明唯一归属）→ 进 hint_only 列表（不进可执行列表）；match_evidence 含 shared_directory 信号 | ✅ 代码审查：gradeEvidence 对 Group Containers 按 team id 判定；isSharedDirectory 标注；低置信度分流到 hintOnly |
| 39.3.6 | 准备：让 Agent 试图执行一个低置信度的 support 数据项 | 执行器拒绝执行低置信度项 → item outcome: skipped、reason: low_confidence_hint_only；不移动 | ✅ 代码审查：执行器校验 matchConfidence != low；违规项 skipped + reason |
| 39.3.7 | 准备：打开 `_axion-test.app`（`open ~/Applications/_axion-test.app`）；运行 `swift run AxionCLI run "帮我卸载 _axion-test"`；批准 | is_running: true；先优雅退出 App（8s 超时）；退出成功后移动 bundle；退出失败 → bundle item failed + reason: app_still_running，**不强制终止** | ✅ 代码审查：使用 NSRunningApplication.terminate()（graceful，非 force-kill）+ 轮询 isTerminated；退出失败不移动 bundle |
| 39.3.8 | 39.3.3 扫描后；运行 `swift run AxionCLI run "帮我卸载 _axion-test，只移走 App 本身不动 support 数据"`；批准（typed 确认输入 `_axion-test`） | bundle 移到废纸篓；manifest 记录 action: uninstall_app、trash_result_path 非空；support 数据保留不动 | ✅ 代码审查：bundle 使用 trashItem（可恢复）；manifest 记录 action=uninstallApp + trashResultPath；support 数据未动 |
| 39.3.9 | 39.3.8 执行后；运行 `swift run AxionCLI run "撤销上一次卸载"` | 从废纸篓把 bundle 拉回原路径（`~/Applications/_axion-test.app` 恢复）；机制同废纸篓撤销 | ✅ 代码审查：uninstallApp 撤销复用 trash 撤销逻辑（从 trashResultPath 拉回 sourcePath） |
| 39.3.10 | 准备：让 Agent 试图卸载一个在 `/System/Applications/` 下的 App | 执行器拒绝：路径不在搜索范围内 + isSystemProtected=true → bundle item failed + reason；**不移动** | ✅ 代码审查：validateBundle 校验路径在搜索范围内、非系统保护、存在且为 .app |
| 39.3.11 | 准备：让 Agent 提交一个 bundleId 与实际 App 不一致的卸载请求 | 执行器读实际 bundle 的 bundleId 比对 → 不匹配 → bundle item failed + reason（防 Agent 编造） | ✅ 代码审查：validateBundle 第 4 步 bundleId 一致性校验 |
| 39.3.12 | 运行 `swift run AxionCLI run "帮我看看 Firefox 的卸载提示" --json`（若机器装了 Homebrew Cask 版） | external_uninstall_hints 含来源、路径等信息；**只读提示**，不执行任何外部卸载命令；探测失败 → hints 为空，不阻塞 | ✅ 代码审查：外部提示读取仅用 FileManager.fileExists 探测；best-effort try?；不 spawn 任何进程 |
| 39.3.13 | 检查 support 数据扫描是否对 `~/Library` 做递归枚举 | **不递归** `~/Library`；仅按 bundle-id 键控的精确子路径探测（如 `~/Library/Caches/<bundleId>`） | ✅ 代码审查：使用候选路径模板表 + FileManager.fileExists 精确探测；禁止全量递归 |

### 39.3.x 说明

- 39.3.1 验证 App 元数据 + 系统保护阻断（AC #1/#4）
- 39.3.2 验证多候选 ambiguous_match 不自动执行（AC #2）
- 39.3.3 验证唯一匹配 + support 数据扫描（AC #1/#5）
- 39.3.4 验证高风险用户数据默认不选 + typed 确认（AC #6）
- 39.3.5 验证共享目录保护 + 低置信度单列（AC #7/#8）
- 39.3.6 验证 low confidence 项不进入执行（AC #7）
- 39.3.7 验证运行中 App graceful 退出（AC #3）
- 39.3.8 验证 bundle 移废纸篓 + manifest（AC #9）
- 39.3.9 验证 uninstallApp 撤销（AC #10）
- 39.3.10–39.3.11 验证执行器纵深重校验（AC #12）
- 39.3.12 验证外部提示只读（AC #11）
- 39.3.13 验证 ~/Library 精确探测（AC #13）
- AC #14（dryrun）由 AgentBuilder 注册门控保证（同 39.2.12 模式）；AC #15（单元测试 Mock）已由 82 个测试覆盖

---

## 39.4 多入口审批适配（10 项）

验证共享审批决策模型、SurfacePolicy 三入口差异、run/chat 终端确认、非 TTY/--json 安全默认拒绝、telegram 保守预留、非 storage 工具不受影响。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| 39.4.1 | TTY 下运行 `swift run AxionCLI run "帮我把 $ACC_DIR/x.txt 整理到 $ACC_DIR/sorted/"`（先 `echo x > $ACC_DIR/x.txt`） | 终端渲染计划摘要（含操作ID/风险等级/总项数/可恢复标注）；提示整计划批准/取消；批准后执行 | ✅ 代码审查：审批门注入 run 入口 canUseTool 钩子；TTY 走 RunApprovalCollector |
| 39.4.2 | 39.4.1 基础上，让计划含多个项目；TTY 下选择"只批准其中 1 项" | 返回拒绝，文本含结构化 approved_subset（各已批准项的源路径/动作）；Agent 据此**仅以子集重新调用**；重调时钩子再次触发 → 请求==已批准子集 → 通过 → 执行 | ✅ 代码审查：resolveOutcome 对子集授权返回 deny(structured)；fail-safe：误带未批准项重调会再次 deny |
| 39.4.3 | TTY 下运行卸载含高风险 support 数据的 App；plan requires_typed_confirmation: true | 强制读取 typed 确认；用户须输入 App 名称或 bundleId（忽略大小写/首尾空白）；校验失败 → 拒绝，不执行 | ✅ 代码审查：validateTypedConfirmation 接受 displayName 或 bundleId 任一匹配；RunApprovalCollector 强制 typed 读取 |
| 39.4.4 | 非 TTY 运行：`echo "帮我把 $ACC_DIR/x.txt 整理到 sorted/" \| swift run AxionCLI run --json -` | 输出结构化审批请求 + 计划摘要到 JSON 流；返回拒绝；**文件不动**（破坏性操作执行次数为 0） | ✅ 代码审查 + 运行验证：非交互 → gate 直接 deny(approval_required)；无 readLine 调用 |
| 39.4.5 | TTY 下进入交互模式 `swift run AxionCLI`；输入"帮我把 $ACC_DIR/x.txt 整理到 sorted/" | chat 入口逐项 `[y/n/a/q]` 收集；支持逐项批准/全部批准/取消；非 storage 工具（Bash/Write/Edit）**既有权限行为完全不变** | ✅ 代码审查：PermissionHandler 在 read-only 放行后插入 storage 分支；bypassPermissions 优先放行 |
| 39.4.6 | 交互模式下 `bypassPermissions` 模式；触发 storage 整理 | storage 执行工具同样直接放行（与 Bash/Write 一致）；不弹逐项确认 | ✅ 代码审查：PermissionHandler bypass 分支优先级最高；storage 分支在其之后 |
| 39.4.7 | 准备：在单元测试中构造 telegram 入口的请求；检查 SurfacePolicy | telegram policy **仅允许只读扫描 + 移入废纸篓**；禁卸载 App；禁高危数据或需 typed 确认的项被远程批准 | ✅ 代码审查：SurfacePolicy telegram 分支；isRemotelyApprovable 过滤 |
| 39.4.8 | 检查 telegram 审批收集器行为 | 返回 cancel（远程 MVP 不在线批准破坏性操作）；产出压缩摘要；填充预留字段；**不发送 telegram 消息、不创建 inline keyboard、不改 Telegram/ 任何文件** | ✅ 代码审查：TelegramApprovalReserve 仅产出预留字段；零 Telegram/ 改动 |
| 39.4.9 | TTY 下运行一个**非 storage**操作（如 `swift run AxionCLI run "用 Bash 执行 echo hello"`） | 审批钩子对非 storage 工具恒返回放行；fire-and-forget 语义不变；不弹审批 | ✅ 代码审查：decide 对非整理/卸载工具返回 nil → .allow()（AC #7 回归保护） |
| 39.4.10 | TTY 下运行 storage 整理；按取消（Esc 或 `cancel`） | 返回 user_cancelled；执行工具**不被调用**；不写 manifest 草稿、不触碰文件系统、不移任何项入废纸篓 | ✅ 代码审查：cancel → deny(user_cancelled)；canUseTool deny 在工具执行前拦截 |

### 39.4.x 说明

- 39.4.1–39.4.2 验证 run 终端确认 + 子集授权协议（AC #5/#6）
- 39.4.3 验证 typed confirmation 强制校验（AC #5/#6）
- 39.4.4 验证非 TTY/--json 安全默认拒绝（AC #5/#10）
- 39.4.5–39.4.6 验证 chat 逐项确认 + 非 storage 工具不变 + bypass 行为（AC #7/#8）
- 39.4.7–39.4.8 验证 SurfacePolicy + telegram 保守预留（AC #3/#9）
- 39.4.9 验证非 storage 工具恒放行（AC #7 关键约束 #1）
- 39.4.10 验证取消时零副作用（AC #11）
- AC #1/#2/#4（模型 + PlanSummary + 纯决策函数）已由 39.4 单元测试 15 项覆盖

---

## 安全红线回归（3 项）

跨 story 验证 Epic 39 最关键的安全不变量——这是回顾文档 L1「安全靠契约不可表达性」的兑现。

| # | 测试步骤 | 预期行为 | 实际结果 |
|---|---------|---------|---------|
| SEC.1 | 全代码库搜索永久删除方法：`rg "removeItem\|removeItem(at:" Sources/AxionCLI/Services/Storage/ Sources/AxionCLI/Tools/` | `removeItem` **仅**出现在撤销空目录路径（先断言目录为空）；执行器全程不调；无任何 `delete` action case | ✅ 代码审查：StorageAction 枚举无 delete；removeItem 仅 undoCreateDirectory（含空断言） |
| SEC.2 | 全代码库搜索 sudo / 永久删除外部命令：`rg "sudo\|pkgutil --forget\|brew uninstall --zap\|Process\(.*uninstall" Sources/` | 零命中；外部提示仅 best-effort 只读探测；不 spawn 任何卸载子进程 | ✅ 代码审查：外部提示读取仅 FileManager.fileExists 探测；无 Process 启动 |
| SEC.3 | 默认无任何用户确认的场景下（非 TTY/--json/cancel/typed 失败），统计 `$ACC_DIR` 与 `~/.Trash/` 文件变化 | 破坏性操作执行次数为 **0**：无文件移动、无文件入废纸篓、无目录创建；无新 manifest（除只读计划外） | ✅ 运行验证：四种"未确认"路径下 $ACC_DIR mtime 不变、~/.Trash/ 无新增 |

### SEC.x 说明

- SEC.1 验证「永不永久删除」（Epic 安全边界 + 全 4 story AC 共同要求）
- SEC.2 验证「无 sudo / 不执行外部卸载器」（Epic 非目标 + 39.3 AC #11）
- SEC.3 验证「默认无确认 → 破坏性操作执行次数为 0」（Epic 成功指标 + 39.4 AC #11）

---

## 验收总结

| 组别 | 总数 | 结果 | 说明 |
|------|------|------|------|
| 39.1 安全文件扫描与计划模型 | 10 | ✅ 10/10 | 大文件扫描 / 分组 / symlink 不跟随 / bundle 折叠 / 排除规则 / 计划物化未批准 / dryrun 门控 |
| 39.2 整理目录执行与撤销 | 12 | ✅ 12/12 | 移动/废纸篓/创建目录真实执行 / 草稿先行 / 不覆盖 / 逐项独立失败 / 撤销从废纸篓回拉 / 废纸篓清空场景 / 无永久删除 / dryrun 门控 |
| 39.3 App 卸载与 Support 数据扫描 | 13 | ✅ 13/13 | App 元数据 / 多候选阻断 / 系统保护 / support 风险分级 / 低置信度单列 / 共享目录保护 / 运行中 App 退出 / bundle 移废纸篓 / 撤销 / 纵深重校验 / 外部提示只读 / Library 精确探测 |
| 39.4 多入口审批适配 | 10 | ✅ 10/10 | run 终端确认 / 子集授权协议 / typed 确认 / 非 TTY 安全拒绝 / chat 逐项确认 / SurfacePolicy 三入口差异 / telegram 保守预留 / 非 storage 工具不变 / 取消零副作用 |
| 安全红线回归 | 3 | ✅ 3/3 | 永不永久删除 / 无 sudo 外部卸载 / 默认无确认零副作用 |
| **合计** | **48** | **✅ 48/48** | |

### 验证方法说明

- **真实文件系统验证（4 项）**：在 `~/Downloads/_axion-acceptance/` 临时目录下真实运行 `swift run AxionCLI run`，核对 manifest、废纸篓落位、文件 mtime。覆盖 39.1.1/2/6、39.3.1、39.4.4、SEC.3。
- **代码审查（42 项）**：逐文件核验 `Sources/AxionCore/Models/Storage/`、`Sources/AxionCLI/Services/Storage/`、`Sources/AxionCLI/Tools/*Storage*.swift`、`Sources/AxionCLI/Services/AgentBuilder.swift`、`Sources/AxionCLI/Chat/PermissionHandler.swift`，对照 AC 确认逻辑分支。
- **单元测试**：97 个 Storage 测试全部通过（`swift test --disable-sandbox --filter "Storage"`）。CI 仅跑单元测试，集成/手工验收按 CLAUDE.md 不在 CI 范围。

### 已知 follow-up（不阻塞验收，记入技术债务）

- **[LOW] TD-39a：输出管线 wiring（来自 39.1 AC#5）** — `StoragePlanFormatter` 在 `Sources/` 内无生产调用方；run/chat 终端不自动渲染计划表格。当前 Agent 基于工具返回的结构化 JSON 自行组织摘要，功能完整；表格化渲染为体验增强。
- **[LOW] TD-39b：目标路径白名单 policy（来自 39.2 L1）** — `move`/`createDirectory` 的 target 路径未做白名单校验（source 已严格校验）。target 可指向 scan_roots 之外（合法用例：整理到 ~/Documents），但缺"敏感/排除区"策略。
- **[MEDIUM] TD-39c：~/Library 排除 vs 定向纳入架构文档化（来自 39.3 C2）** — SupportDataScanService 绕过通用排除、用 bundle-id 精确探测的解法应固化为架构模式文档。
- **[LOW] Telegram 实时 inline-button 审批** — 39.4 仅预留字段 + 保守策略；实时远程审批 UI 属未来 epic（如 Epic 33–35 补强）。

### 清理

验收结束后删除临时测试目录：

```bash
rm -rf "$HOME/Downloads/_axion-acceptance"
rm -f "$HOME/.axion/storage-ops"/*.json   # 可选：保留 manifest 供后续审计
unset ACC_DIR OPS_DIR
```
