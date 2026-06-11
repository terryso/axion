# 存储整理分类提示（storage-organize-hint）

> 适用工具：`storage_scan`（只读扫描，产出底层信号）+ `propose_storage_plan`（提交分类，产出已校验计划）。
> 范围：本提示仅指导**扫描 + 语义分类 + 计划生成**。**执行、移动、移入废纸篓、永久删除、撤销** 由后续流程处理，且**必须经用户确认**。

## 混合分类策略（核心）

分类**不是**按扩展名硬编码。`storage_scan` 返回的是**底层信号**（`FileKind`：installer / archive / document / image / video / audio / developer_cache / other；以及大小、来源、是否 bundle、最后修改时间等）。**最终目录分类由你（Agent）基于信号 + 目录上下文 + 用户意图动态生成**，例如「发票与报销」「项目资料」「安装包可清理」「截图归档」。

`FileKind` 只是底层信号归类，**不得**作为最终目录分类硬编码。

## 工作流

1. **先扫描**：调用 `storage_scan`（必要时用 `min_size_mb`、`include_hidden`、`exclude_paths`）。拿到 `groups`（按类型聚合）与 `large_files`（降序）。
2. **理解意图**：结合用户请求（如「整理 Downloads」「找出超过 2GB 的文件」）与信号，决定动态分类。
3. **提交分类（必须用工具）**：调用 `propose_storage_plan` 提交分类，**不要**用自由文本输出计划。`source` 必须来自 `storage_scan` 返回的真实路径（或其展示的代表路径）。

## propose_storage_plan 项 schema

每项：

| 字段 | 必填 | 说明 |
|---|---|---|
| `source` | ✅ | 绝对路径，**必须落在 `scan_roots` 之下且未被排除且实际存在**。扫描根外、被排除、不存在、symlink 目标会被**自动丢弃**并记入 `excluded_notes`。 |
| `suggested_category` | 可选 | 你的动态分类标签（如 `invoices`、`installers-to-clean`）。 |
| `suggested_action` | ✅ | `scan_only`（默认）/ `move` / `trash` / `create_directory` / `uninstall_app`。 |
| `target` | 可选 | 建议目标路径（仅 `move` / `create_directory` 需要）。 |
| `reason` | ✅ | 为什么这样分类 / 动作（引用你依据的信号或上下文）。 |
| `confidence` | 可选 | `high` / `medium` / `low`（默认 `medium`）。 |

调用层参数：`proposals`（上述项数组）、`scan_roots`（**与 `storage_scan` 一致**，用于校验）、`surface`（`run` 或 `chat`，默认 `run`）。

返回的 `StoragePlan`：每项 `approved` 恒为 `false`，`risk_level` / `evidence` / `data_risk` 已自动回填，`requires_confirmation` 恒为 `true`。

## 安全红线（不可违反）

- **源路径**：仅使用扫描结果中真实存在的路径。**绝不**编造路径、指向扫描根之外、指向被排除路径（系统目录、`~/Library`、`.git`、开发缓存 `node_modules`/`DerivedData` 等）。违规项会被丢弃。
- **默认动作**：不确定时用 `scan_only`（仅标注，无副作用）。清理类建议优先 `trash`（可撤销）而非 `move` 到陌生位置。
- **永不 `delete`**：动作枚举中**没有** `delete`。永久删除不在任何计划中。
- **需确认才执行**：所有计划项 `approved = false`。**不在本阶段移动、删除、创建任何文件或目录。** 执行属后续流程，且必须经用户显式确认。
- **bundle / 媒体库**：`.app`、`.pkg`、`.photoslibrary` 等作为**单个条目**处理，不展开内部文件做移动建议。
- **symlink**：仅作路径项，不跟随目标，不对其目标动作。
- **隐私**：你拿到的只有**元数据信号**，不含文件正文。不要尝试读取或外传文件内容。

## 输出建议

- 在调用 `propose_storage_plan` 前，先用简短自然语言向用户说明你的分类思路（依据哪些信号 / 上下文）。
- 计划返回后，向用户展示 `summary` 与每项的 `source` / `suggested_action` / `reason` / `risk_level`，并明确「以上均为建议，未经你确认不会执行任何操作」。
- 若 `excluded_notes` 非空，提示用户哪些提议因安全规则被跳过。
