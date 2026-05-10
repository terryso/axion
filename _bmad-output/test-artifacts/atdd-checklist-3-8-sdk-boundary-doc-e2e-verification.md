---
stepsCompleted: ['step-01-preflight-and-context', 'step-02-generation-mode', 'step-03-test-strategy', 'step-04-generate-tests']
lastStep: 'step-04-generate-tests'
lastSaved: '2026-05-10'
storyId: '3.8'
storyKey: '3-8-sdk-boundary-doc-e2e-verification'
storyFile: '_bmad-output/implementation-artifacts/stories/3-8-sdk-boundary-doc-e2e-verification.md'
atddChecklistPath: '_bmad-output/test-artifacts/atdd-checklist-3-8-sdk-boundary-doc-e2e-verification.md'
generatedTestFiles:
  - 'Tests/AxionCLITests/Commands/SDKBoundaryAuditTests.swift'
inputDocuments:
  - '_bmad-output/implementation-artifacts/stories/3-8-sdk-boundary-doc-e2e-verification.md'
  - '_bmad-output/project-context.md'
  - '_bmad/tea/config.yaml'
  - '.claude/skills/bmad-testarch-atdd/resources/tea-index.csv'
---

# ATDD Checklist: Story 3.8 - SDK 边界文档与端到端验证

## 项目信息

- **项目**: axion (纯 Swift / SPM)
- **检测技术栈**: backend (Swift Package Manager, XCTest)
- **测试框架**: XCTest (Swift 原生)
- **生成模式**: AI Generation (后端项目，无浏览器录制需求)
- **执行模式**: sequential

## Story 验收标准 -> 测试映射

### AC1: SDK 集成点审查

| ID | 测试场景 | 测试级别 | 优先级 | 状态 |
|----|----------|----------|--------|------|
| 3.8-UNIT-001 | AxionCore 无 `import OpenAgentSDK` | Unit (静态扫描) | P0 | RED |
| 3.8-UNIT-002 | AxionHelper 无 `import OpenAgentSDK` | Unit (静态扫描) | P0 | RED |
| 3.8-UNIT-003 | AxionCLI 不 import AxionHelper | Unit (静态扫描) | P0 | RED |
| 3.8-UNIT-004 | RunCommand 使用 createAgent 公共 API | Unit (结构检查) | P0 | RED |
| 3.8-UNIT-005 | RunCommand 使用 Agent.stream 公共 API | Unit (结构检查) | P1 | RED |
| 3.8-UNIT-006 | RunCommand 使用 McpStdioConfig 配置 Helper | Unit (结构检查) | P1 | RED |
| 3.8-UNIT-007 | RunCommand 使用 HookRegistry preToolUse hook | Unit (结构检查) | P1 | RED |
| 3.8-UNIT-008 | 代码中无直接 Anthropic HTTP 调用 | Unit (静态扫描) | P0 | RED |

### AC2: SDK 边界文档

| ID | 测试场景 | 测试级别 | 优先级 | 状态 |
|----|----------|----------|--------|------|
| 3.8-UNIT-009 | docs/sdk-boundary.md 存在且非空 | Unit (文件检查) | P1 | RED |
| 3.8-UNIT-010 | SDK 边界文档包含边界表章节 | Unit (内容检查) | P1 | RED |
| 3.8-UNIT-011 | SDK 边界文档包含 API 使用清单章节 | Unit (内容检查) | P1 | RED |

### AC3: SDK 短板记录

| ID | 测试场景 | 测试级别 | 优先级 | 状态 |
|----|----------|----------|--------|------|
| 3.8-UNIT-012 | SDK 边界文档包含短板与改进建议章节 | Unit (内容检查) | P2 | RED |

### AC4-AC7: 端到端验证 (手动测试)

> 注：AC4-AC7 是手动端到端验证场景（Calculator, TextEdit, Finder, Safari），
> 需要真实 macOS 桌面环境和 AX 权限。这些不在自动化单元测试范围内，
> 使用手动验收测试清单。

| ID | 测试场景 | 测试级别 | 优先级 | 状态 |
|----|----------|----------|--------|------|
| 3.8-MANUAL-001 | Calculator E2E: 计算 17x23=391 | Manual | P0 | PENDING |
| 3.8-MANUAL-002 | TextEdit E2E: 输入 Hello World | Manual | P0 | PENDING |
| 3.8-MANUAL-003 | Finder E2E: 进入下载目录 | Manual | P1 | PENDING |
| 3.8-MANUAL-004 | Safari E2E: 访问 example.com | Manual | P1 | PENDING |

### Task 8: SDK 边界审计测试

| ID | 测试场景 | 测试级别 | 优先级 | 状态 |
|----|----------|----------|--------|------|
| 3.8-UNIT-013 | ToolNames.allToolNames 包含全部 20 个工具 | Unit | P1 | RED |
| 3.8-UNIT-014 | ToolNames.foregroundToolNames 正确分类 | Unit | P1 | RED |

## 测试文件清单

### 新建文件

1. **`Tests/AxionCLITests/Commands/SDKBoundaryAuditTests.swift`**
   - AC1 import 审计测试 (8 个测试)
   - AC2/AC3 文档存在性测试 (4 个测试)
   - Task 8 工具名审计测试 (2 个测试)
   - 总计: 14 个测试

### 手动验收清单

1. **`_bmad-output/test-artifacts/manual-acceptance-3-8.md`** (新建)
   - AC4-AC7 端到端验证步骤
   - 每个场景的验证清单

## 优先级分布

- **P0 (Critical)**: 5 个自动化 + 2 个手动 = 7
- **P1 (High)**: 7 个自动化 + 2 个手动 = 9
- **P2 (Medium)**: 2 个自动化 = 2
- **P3 (Low)**: 0

## TDD Red Phase 状态

- 所有自动化测试以 RED phase 脚手架生成
- 使用 `XCTSkip` 机制，实现前跳过
- 实现后将对应开关设为 `true`，测试转为 GREEN

## 测试质量检查

- [x] 无硬编码等待
- [x] 无条件分支控制测试流
- [x] 每个测试 < 300 行
- [x] 显式断言
- [x] 并行安全（无共享状态）
- [x] 测试命名遵循 `test_{单元}_{场景}_{预期}` 格式
