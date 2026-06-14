import Testing
import Foundation
@testable import AxionCLI
import OpenAgentSDK

// MARK: - Story 40.1 SDK Runtime Readiness Gate
//
// 本测试套件是 Story 40.1 的确定性依赖 gate：证明 Axion resolve 到的
// OpenAgentSDK 版本暴露了后续 Epic 40（skill/subagent 兼容）所需的运行时 API
// （createAgentTool / createTaskTool / createSkillTool），以及 Task/Agent 工具的
// name、schema 等价性、skills/mcpServers 字段、filesystem skill package context 注入点。
//
// Gate 状态说明：
// - Axion Package.swift 声明 `from: "0.10.0"`，Package.resolved pin 到 SDK commit 4285aac。
// - createAgentTool() / createTaskTool() 在 SDK 0.10.0 公开；若依赖回退，本套件会编译失败。
// - 用 Swift Testing 的 `.disabled(...)` 标记的 AC5 测试遵循 story Dev Notes 的降级
//   策略：单测禁止调用真实 Agent / executeSkillStream（API key / 网络副作用）。
//
// 约束遵循（CLAUDE.md）：
// - 仅用 Swift Testing（import Testing / @Suite / @Test / #expect），禁止 XCTest。
// - 单元测试禁止真实外部依赖：createAgentTool() / createTaskTool() /
//   createSkillTool(registry:) 是纯工厂函数，调用本身不触发网络/进程/LLM，可作单测对象。
//   本套件不调用真实 AgentBuilder.build()、不连 MCP、不起 Helper、不发 API key、
//   不调真实 executeSkillStream。
//
// 参考 scaffold 风格：Tests/AxionCLITests/Services/AgentBuilderCodingTests.swift。

@Suite("SDK Runtime Readiness Gate (Story 40.1)")
struct SDKRuntimeReadinessGateTests {

    // MARK: - 辅助：从 ToolInputSchema 提取 properties 键集合
    //
    // ToolInputSchema = [String: Any]，schema 形如
    //   ["type": "object", "properties": [...], "required": [...]]
    // properties 的键即工具接受的所有输入字段名。

    /// 返回工具 inputSchema["properties"] 的字段名集合；缺失时返回空集。
    private func propertyKeys(of tool: ToolProtocol) -> Set<String> {
        guard let properties = tool.inputSchema["properties"] as? [String: Any] else {
            return []
        }
        return Set(properties.keys)
    }

    /// 返回工具 schema 的规范化 JSON 表示，用于比较嵌套字段、required 与类型定义。
    private func canonicalSchemaString(of tool: ToolProtocol) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: tool.inputSchema, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - AC2 / AC3：createAgentTool 可达且 name == "Agent"

    /// AC2：SDK 工厂函数 `createAgentTool()` 在 Axion resolve 的版本里可 import、可调用、
    ///      返回 `ToolProtocol`。
    /// AC3：返回的工具 `.name == "Agent"`。
    ///
    /// Gate 行为：若依赖回退到 SDK 0.8.x，本测试会因缺少 createAgentTool() 编译失败。
    @Test("createAgentTool resolves and returns a tool named 'Agent'")
    func test_createAgentTool_resolvesAndReturnsAgentName() throws {
        // createAgentTool() -> ToolProtocol（纯工厂，无网络/进程/LLM 副作用）。
        let tool: ToolProtocol = createAgentTool()

        #expect(tool.name == "Agent", "createAgentTool().name 必须为 \"Agent\"，实际：\(tool.name)")
    }

    // MARK: - AC2 / AC3：createTaskTool 可达且 name == "Task"

    /// AC2：`createTaskTool()` 可 import、可调用、返回 `ToolProtocol`。
    /// AC3：`.name == "Task"`。
    ///
    /// Gate 行为：若依赖回退到 SDK 0.8.x，本测试会因缺少 createTaskTool() 编译失败。
    @Test("createTaskTool resolves and returns a tool named 'Task'")
    func test_createTaskTool_resolvesAndReturnsTaskName() throws {
        let tool: ToolProtocol = createTaskTool()

        #expect(tool.name == "Task", "createTaskTool().name 必须为 \"Task\"，实际：\(tool.name)")
    }

    // MARK: - AC2：createSkillTool 可达（带 registry）

    /// AC2：`createSkillTool(registry:)` 可 import、可调用、返回 `ToolProtocol`。
    ///      用空 `SkillRegistry()` 构造（不注册真实 skill，不触发文件系统/网络副作用）。
    ///
    /// 注：createSkillTool 在 0.8.x 即存在（Axion 已在用），此 @Test 同时充当
    ///     “升级未破坏既有签名”的回归断言。
    ///
    /// Gate 行为：若 SDK 0.10.0+ 改动既有签名则转红。
    @Test("createSkillTool resolves with an (empty) SkillRegistry and is named 'Skill'")
    func test_createSkillTool_resolvesWithRegistry() throws {
        let registry = SkillRegistry()
        let tool: ToolProtocol = createSkillTool(registry: registry)

        #expect(tool.name == "Skill", "createSkillTool(registry:).name 必须为 \"Skill\"，实际：\(tool.name)")
    }

    // MARK: - AC3：Task / Agent schema 等价（仅 name 不同）

    /// AC3：Task 与 Agent 共享同一内部 launcher factory，输入 schema 等价。
    ///      验证 `createTaskTool()` 与 `createAgentTool()` 的完整 inputSchema 规范化
    ///      JSON 一致；并断言工具 name 不同（"Task" vs "Agent"）。
    ///
    /// 已确认 ToolProtocol.inputSchema: [String: Any] 可读；完整 schema 比对覆盖
    /// properties、required、字段类型与 descriptions，而不仅是字段名集合。
    ///
    /// Gate 行为：0.8.x 无 createAgentTool/createTaskTool，依赖回退时会编译失败。
    @Test("Task and Agent share equivalent input schema (differ only by name)")
    func test_taskAndAgent_shareEquivalentSchema() throws {
        let agentTool = createAgentTool()
        let taskTool = createTaskTool()

        // 仅 name 不同
        #expect(agentTool.name == "Agent")
        #expect(taskTool.name == "Task")
        #expect(agentTool.name != taskTool.name, "Agent 与 Task 工具名必须不同")

        // schema properties 非空，避免反射路径误读为空字典。
        let agentKeys = propertyKeys(of: agentTool)
        let taskKeys = propertyKeys(of: taskTool)

        #expect(!agentKeys.isEmpty, "Agent 工具必须有非空 schema properties（反射到 SDK schema 失败）")
        #expect(!taskKeys.isEmpty, "Task 工具必须有非空 schema properties（反射到 SDK schema 失败）")

        // 完整 inputSchema 等价，确保不仅字段名一致，required/type/description 也一致。
        let agentSchema = try canonicalSchemaString(of: agentTool)
        let taskSchema = try canonicalSchemaString(of: taskTool)
        #expect(agentSchema == taskSchema,
                "Agent 与 Task 的完整输入 schema 必须等价。\nAgent: \(agentSchema)\nTask: \(taskSchema)")
    }

    // MARK: - AC4：Task/Agent schema 包含 skills 与 mcpServers

    /// AC4：`createTaskTool()` / `createAgentTool()` 的输入 schema 必须包含 `skills`
    ///      与 `mcpServers`（或 `mcp_servers`）字段（SDK 0.10.0 wiring）。
    ///      用 schema 反射读取 properties 键集合并断言存在（已确认 ToolInputSchema
    ///      = [String: Any] 可读，无需访问 private 的 AgentToolInput）。
    ///
    /// Gate 行为：0.8.x 无这两个工厂函数，依赖回退时会编译失败。
    @Test("Task and Agent input schema include 'skills' and 'mcpServers' fields")
    func test_taskAndAgent_schemaIncludesSkillsAndMcpServers() throws {
        let agentKeys = propertyKeys(of: createAgentTool())
        let taskKeys = propertyKeys(of: createTaskTool())

        // skills 字段
        #expect(agentKeys.contains("skills"), "Agent schema 必须含 'skills' 字段，实际字段：\(agentKeys.sorted())")
        #expect(taskKeys.contains("skills"), "Task schema 必须含 'skills' 字段，实际字段：\(taskKeys.sorted())")

        // mcpServers 字段（SDK CodingKeys 同时支持 mcpServers / mcp_servers；schema 用 mcpServers）
        let agentHasMcp = agentKeys.contains("mcpServers") || agentKeys.contains("mcp_servers")
        let taskHasMcp = taskKeys.contains("mcpServers") || taskKeys.contains("mcp_servers")

        #expect(agentHasMcp, "Agent schema 必须含 'mcpServers'/'mcp_servers' 字段，实际字段：\(agentKeys.sorted())")
        #expect(taskHasMcp, "Task schema 必须含 'mcpServers'/'mcp_servers' 字段，实际字段：\(taskKeys.sorted())")
    }

    // MARK: - AC5：filesystem skill prompt 含 package context（降级处理）

    /// AC5：SDK `executeSkillStream` 为含 `baseDir` + `supportingFiles` 的 filesystem skill
    ///      注入 `Skill package context:` 块。
    ///
    /// ⚠️ 降级策略（遵循 story Dev Notes 与 CLAUDE.md 单元测试 Mock 规则）：
    /// 单元测试禁止调用真实 `Agent` / `executeSkillStream`（涉及 API key 校验与网络）。
    /// SDK commit 4285aac 的 `Agent.swift:3293-3319`（resolveSkillForExecution /
    /// package-context 注入分支）需要真实 Agent 运行时才能完整触发，无法在隔离单测中
    /// 不带副作用地复现。
    ///
    /// 因此本 AC 在单元测试层标记为 `.disabled`，并作如下处置：
    ///   1. 该行为由 SDK 侧 `SkillExecutionPromptContextTests` 单测覆盖（SDK test-plan）。
    ///   2. Story 40.1 dev 完成时，在 Completion Notes 记录 SDK commit
    ///      `4285aac6535236dae014e945eed694ed7fe6bd4b` 与 prompt 生成代码路径
    ///      （Core/Agent.swift:3293-3319）作为集成点冒烟证据。
    ///   3. 若后续 SDK 暴露纯函数 prompt builder（不实例化 Agent、不发请求），
    ///      dev 可将本测试激活为断言式单测（断言生成的 prompt 含
    ///      "Skill package context:" 与 baseDir 值）。
    ///
    /// 这是合规的降级：单元测试规则禁止真实运行时副作用，AC5 属 SDK 行为验证。
    @Test(
        "filesystem skill prompt includes 'Skill package context' block",
        .disabled("AC5 降级：SDK package-context 注入需真实 Agent 运行时（API key/网络）。由 SDK 单测 SkillExecutionPromptContextTests 覆盖；dev 在 Completion Notes 记录 SDK commit 4285aac 与代码路径作为集成点冒烟证据。")
    )
    func test_filesystemSkill_promptIncludesPackageContext() throws {
        // 预期断言（激活时使用）：
        //   1. 用 Skill(baseDir:supportingFiles:promptTemplate:...) 构造 filesystem skill
        //   2. 调用 SDK 纯函数 prompt builder（若公开）
        //   3. #expect(prompt.contains("Skill package context:"))
        //   4. #expect(prompt.contains(baseDir 值))
        //   5. #expect(prompt.contains("User request:"))
        // 当前因需真实 Agent 运行时，按降级策略 disabled。
        #expect(Bool(false), "占位：激活本测试前需 SDK 暴露无副作用的 prompt builder")
    }
}
