import Foundation
import OpenAgentSDK

import AxionCore

struct AppDetailLocalMetadata: Codable, Equatable, Sendable {
    let lastOpenedAt: String?
    let addedAt: String?
}

struct AppAgentAnalysis: Codable, Equatable, Sendable {
    let summary: String
    let primaryUse: String
    let category: String
    let publisher: String
    let confidence: String
    let analyzedAt: String

    enum CodingKeys: String, CodingKey {
        case summary
        case primaryUse = "primary_use"
        case category
        case publisher
        case confidence
        case analyzedAt = "analyzed_at"
    }
}

enum AppAgentAnalysisState: Equatable, Sendable {
    case notRequested
    case analyzing
    case cached
    case generated
    case failed(String)
}

struct AppDetailInfo: Equatable, Sendable {
    let localMetadata: AppDetailLocalMetadata
    let analysis: AppAgentAnalysis?
    let analysisState: AppAgentAnalysisState

    static let empty = AppDetailInfo(
        localMetadata: AppDetailLocalMetadata(lastOpenedAt: nil, addedAt: nil),
        analysis: nil,
        analysisState: .notRequested
    )

    static let analyzing = AppDetailInfo(
        localMetadata: AppDetailLocalMetadata(lastOpenedAt: nil, addedAt: nil),
        analysis: nil,
        analysisState: .analyzing
    )
}

protocol AppDetailProviding: Sendable {
    func detail(for item: AppListItem) async -> AppDetailInfo
}

struct AppDetailAnalysisService: AppDetailProviding {
    typealias LocalMetadataReader = @Sendable (AppListItem) -> AppDetailLocalMetadata
    typealias AgentRunner = @Sendable (String, AxionConfig) async throws -> String

    let config: AxionConfig
    let cache: AppDetailAnalysisCache
    let localMetadataReader: LocalMetadataReader
    let agentRunner: AgentRunner
    let now: @Sendable () -> Date

    init(
        config: AxionConfig,
        cache: AppDetailAnalysisCache = AppDetailAnalysisCache(),
        localMetadataReader: @escaping LocalMetadataReader = AppDetailAnalysisService.defaultLocalMetadata,
        agentRunner: @escaping AgentRunner = AppDetailAnalysisService.defaultAgentRunner,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.config = config
        self.cache = cache
        self.localMetadataReader = localMetadataReader
        self.agentRunner = agentRunner
        self.now = now
    }

    func detail(for item: AppListItem) async -> AppDetailInfo {
        let localMetadata = localMetadataReader(item)
        if let cached = cache.load(for: item) {
            return AppDetailInfo(localMetadata: localMetadata, analysis: cached, analysisState: .cached)
        }

        do {
            let raw = try await agentRunner(Self.prompt(for: item, localMetadata: localMetadata), config)
            guard let parsed = Self.parseAnalysis(raw, analyzedAt: axionISO8601Formatter.string(from: now())) else {
                return AppDetailInfo(
                    localMetadata: localMetadata,
                    analysis: nil,
                    analysisState: .failed("模型未返回可解析的 JSON")
                )
            }
            cache.save(parsed, for: item)
            return AppDetailInfo(localMetadata: localMetadata, analysis: parsed, analysisState: .generated)
        } catch {
            return AppDetailInfo(
                localMetadata: localMetadata,
                analysis: nil,
                analysisState: .failed(error.localizedDescription)
            )
        }
    }

    static func prompt(for item: AppListItem, localMetadata: AppDetailLocalMetadata) -> String {
        """
        你是 macOS App 元数据分析器。只根据给定元数据和公开常识判断，不要编造用户私人行为。
        请判断这个 App 大概是什么、主要作用是什么、厂商是谁。输出严格 JSON，不要 Markdown，不要代码块。
        JSON schema:
        {"summary":"一句话说明这个 App 是什么","primary_use":"主要用途","category":"类别","publisher":"厂商或未知","confidence":"high|medium|low"}

        元数据:
        display_name: \(AppListFormatter.sanitize(item.displayName))
        bundle_id: \(AppListFormatter.sanitize(item.bundleIdentifier))
        version: \(AppListFormatter.sanitize(item.version))
        path: \(AppListFormatter.sanitize(item.bundlePath))
        source: \(item.source.rawValue)
        running: \(item.isRunning ? "true" : "false")
        last_opened_at: \(localMetadata.lastOpenedAt ?? "unknown")
        added_at: \(localMetadata.addedAt ?? "unknown")
        """
    }

    static func parseAnalysis(_ raw: String, analyzedAt: String) -> AppAgentAnalysis? {
        let trimmed = stripJSONEnvelope(raw)
        guard let data = trimmed.data(using: .utf8),
              let partial = try? JSONDecoder().decode(PartialAgentAnalysis.self, from: data)
        else { return nil }
        return AppAgentAnalysis(
            summary: AppListFormatter.sanitize(partial.summary),
            primaryUse: AppListFormatter.sanitize(partial.primaryUse),
            category: AppListFormatter.sanitize(partial.category),
            publisher: AppListFormatter.sanitize(partial.publisher),
            confidence: AppListFormatter.sanitize(partial.confidence),
            analyzedAt: analyzedAt
        )
    }

    static func defaultLocalMetadata(_ item: AppListItem) -> AppDetailLocalMetadata {
        let values = runMDLS(
            path: item.bundlePath,
            attributes: ["kMDItemLastUsedDate", "kMDItemDateAdded"]
        )
        return AppDetailLocalMetadata(
            lastOpenedAt: normalizeMDLSValue(values["kMDItemLastUsedDate"]),
            addedAt: normalizeMDLSValue(values["kMDItemDateAdded"])
        )
    }

    static func defaultAgentRunner(prompt: String, config: AxionConfig) async throws -> String {
        let apiKey = try AgentBuilder.resolveApiKey(from: config)
        let systemPrompt = "Return one compact JSON object only. No tools. No markdown."
        let options = AgentOptions(
            apiKey: apiKey,
            model: config.model,
            baseURL: config.baseURL,
            systemPrompt: systemPrompt,
            maxTurns: 1,
            maxTokens: 512,
            permissionMode: .bypassPermissions,
            tools: [],
            mcpServers: nil,
            logLevel: .error
        )
        let agent = createAgent(options: options)

        var assistantText = ""
        var partialText = ""
        var resultText = ""
        for await message in agent.stream(prompt) {
            switch message {
            case .assistant(let data):
                assistantText += data.text
            case .partialMessage(let data):
                partialText += data.text
            case .result(let data) where !data.text.isEmpty:
                resultText += data.text
            default:
                break
            }
        }
        try? await agent.close()
        if !assistantText.isEmpty {
            return assistantText
        }
        if !partialText.isEmpty {
            return partialText
        }
        return resultText
    }

    static func runMDLS(path: String, attributes: [String]) -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = attributes.flatMap { ["-raw", "-name", $0] } + [path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return [:]
        }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var values: [String: String] = [:]
        for (idx, attribute) in attributes.enumerated() where idx < lines.count {
            values[attribute] = lines[idx]
        }
        return values
    }

    private static func normalizeMDLSValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "(null)" || trimmed == "null" {
            return nil
        }
        return AppListFormatter.sanitize(trimmed)
    }

    private static func stripJSONEnvelope(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```JSON", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return text
        }
        return String(text[start...end])
    }
}

private struct PartialAgentAnalysis: Decodable {
    let summary: String
    let primaryUse: String
    let category: String
    let publisher: String
    let confidence: String

    enum CodingKeys: String, CodingKey {
        case summary
        case primaryUse = "primary_use"
        case category
        case publisher
        case confidence
    }
}

final class AppDetailAnalysisCache: Sendable {
    private let cacheDir: String

    init(cacheDir: String = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("app-analysis")) {
        self.cacheDir = (cacheDir as NSString).expandingTildeInPath
    }

    func load(for item: AppListItem) -> AppAgentAnalysis? {
        loadDecodableFile(path(for: item), as: AppAgentAnalysis.self, decoder: axionPersistentDecoder)
    }

    func save(_ analysis: AppAgentAnalysis, for item: AppListItem) {
        do {
            try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
            let data = try axionPrettyEncoder.encode(analysis)
            try data.write(to: URL(fileURLWithPath: path(for: item)), options: .atomic)
        } catch {
            // Analysis cache is an optional UX enhancement; failure should not block app selection.
        }
    }

    private func path(for item: AppListItem) -> String {
        resolveFilePath(name: "\(item.bundleIdentifier)-\(item.bundlePath)", in: cacheDir)
    }
}
