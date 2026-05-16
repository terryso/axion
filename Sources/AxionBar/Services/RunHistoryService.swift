import Foundation
import os.log

@MainActor
final class RunHistoryService {
    private let baseURL: String
    private let logger = Logger(subsystem: "com.axion.AxionBar", category: "RunHistoryService")

    init(baseURL: String = "http://127.0.0.1:4242") {
        self.baseURL = baseURL
    }

    func fetchHistory(limit: Int = 20) async throws -> [BarRunStatusResponse] {
        guard let url = URL(string: "\(baseURL)/v1/runs?limit=\(limit)") else {
            throw RunHistoryError.invalidURL
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw RunHistoryError.serverUnreachable(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunHistoryError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw RunHistoryError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode([BarRunStatusResponse].self, from: data)
        } catch {
            throw RunHistoryError.responseParseFailed(error)
        }
    }

    func fetchRun(runId: String) async throws -> BarRunStatusResponse {
        var components = URLComponents(string: "\(baseURL)/v1/runs")!
        components.path += "/\(runId)"

        guard let url = components.url else {
            throw RunHistoryError.invalidURL
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw RunHistoryError.serverUnreachable(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunHistoryError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw RunHistoryError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(BarRunStatusResponse.self, from: data)
        } catch {
            throw RunHistoryError.responseParseFailed(error)
        }
    }
}

enum RunHistoryError: LocalizedError, Equatable {
    case invalidURL
    case serverUnreachable(Error)
    case invalidResponse
    case httpError(statusCode: Int)
    case responseParseFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 API 地址"
        case .serverUnreachable:
            return "无法连接到 Axion 服务"
        case .invalidResponse:
            return "服务返回了无效的响应"
        case .httpError(let statusCode):
            return "服务返回错误: HTTP \(statusCode)"
        case .responseParseFailed:
            return "无法解析服务响应"
        }
    }

    static func == (lhs: RunHistoryError, rhs: RunHistoryError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL): return true
        case (.serverUnreachable, .serverUnreachable): return true
        case (.invalidResponse, .invalidResponse): return true
        case (.httpError(let a), .httpError(let b)): return a == b
        case (.responseParseFailed, .responseParseFailed): return true
        default: return false
        }
    }
}
