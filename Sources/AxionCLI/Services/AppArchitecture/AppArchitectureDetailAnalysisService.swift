import Foundation

import AxionCore

struct AppArchitectureDetailInfo: Equatable, Sendable {
    let analysis: AppAgentAnalysis?
    let analysisState: AppAgentAnalysisState

    static let empty = AppArchitectureDetailInfo(
        analysis: nil,
        analysisState: .notRequested
    )

    static let analyzing = AppArchitectureDetailInfo(
        analysis: nil,
        analysisState: .analyzing
    )
}

protocol AppArchitectureDetailProviding: Sendable {
    func detail(for item: AppArchitectureItem) async -> AppArchitectureDetailInfo
}

struct AppArchitectureDetailAnalysisService: AppArchitectureDetailProviding {
    typealias AgentRunner = @Sendable (String, AxionConfig) async throws -> String

    let config: AxionConfig
    let cache: AppArchitectureDetailAnalysisCache
    let agentRunner: AgentRunner
    let now: @Sendable () -> Date

    init(
        config: AxionConfig,
        cache: AppArchitectureDetailAnalysisCache = AppArchitectureDetailAnalysisCache(),
        agentRunner: @escaping AgentRunner = AppDetailAnalysisService.defaultAgentRunner,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.config = config
        self.cache = cache
        self.agentRunner = agentRunner
        self.now = now
    }

    func detail(for item: AppArchitectureItem) async -> AppArchitectureDetailInfo {
        if let cached = cache.load(for: item) {
            return AppArchitectureDetailInfo(analysis: cached, analysisState: .cached)
        }

        do {
            let raw = try await agentRunner(Self.prompt(for: item), config)
            guard let parsed = AppDetailAnalysisService.parseAnalysis(
                raw,
                analyzedAt: axionISO8601Formatter.string(from: now())
            ) else {
                return AppArchitectureDetailInfo(
                    analysis: nil,
                    analysisState: .failed("模型未返回可解析的 JSON")
                )
            }
            cache.save(parsed, for: item)
            return AppArchitectureDetailInfo(analysis: parsed, analysisState: .generated)
        } catch {
            return AppArchitectureDetailInfo(
                analysis: nil,
                analysisState: .failed(error.localizedDescription)
            )
        }
    }

    static func prompt(for item: AppArchitectureItem) -> String {
        """
        你是 macOS 软件和命令行工具元数据分析器。只根据给定元数据和公开常识判断，不要编造用户私人行为。
        请判断这个 App、命令行工具或类库大概是什么、主要作用是什么、厂商或维护方是谁。
        输出严格 JSON，不要 Markdown，不要代码块。
        JSON schema:
        {"summary":"一句话说明这个软件或类库是什么","primary_use":"主要用途","category":"类别","publisher":"厂商、项目或未知","confidence":"high|medium|low"}

        元数据:
        name: \(AppArchitectureFormatter.sanitize(item.name))
        display_path: \(AppArchitectureFormatter.sanitize(item.displayPath))
        executable_path: \(item.executablePath.map(AppArchitectureFormatter.sanitize) ?? "unknown")
        architectures: \(AppArchitectureScanService.architectureList(item.architectures))
        category: \(item.category.rawValue)
        source: \(item.source.rawValue)
        system_app: \(item.isSystemApp ? "true" : "false")
        """
    }
}

final class AppArchitectureDetailAnalysisCache: Sendable {
    private let cacheDir: String

    init(cacheDir: String = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("arch-analysis")) {
        self.cacheDir = (cacheDir as NSString).expandingTildeInPath
    }

    func load(for item: AppArchitectureItem) -> AppAgentAnalysis? {
        loadDecodableFile(path(for: item), as: AppAgentAnalysis.self, decoder: axionPersistentDecoder)
    }

    func save(_ analysis: AppAgentAnalysis, for item: AppArchitectureItem) {
        do {
            try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
            let data = try axionPrettyEncoder.encode(analysis)
            try data.write(to: URL(fileURLWithPath: path(for: item)), options: .atomic)
        } catch {
            // Analysis cache is an optional UX enhancement; failure should not block /arch detail.
        }
    }

    private func path(for item: AppArchitectureItem) -> String {
        resolveFilePath(name: "\(item.source.rawValue)-\(item.name)-\(item.displayPath)", in: cacheDir)
    }
}
