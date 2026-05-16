import Foundation
import os.log

@MainActor
final class TaskSubmissionService {
    private let baseURL: String
    private let logger = Logger(subsystem: "com.axion.AxionBar", category: "TaskSubmissionService")

    init(baseURL: String = "http://127.0.0.1:4242") {
        self.baseURL = baseURL
    }

    func submit(task: String) async throws -> BarCreateRunResponse {
        guard let url = URL(string: "\(baseURL)/v1/runs") else {
            throw TaskSubmissionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = BarCreateRunRequest(task: task)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TaskSubmissionError.serverUnreachable(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TaskSubmissionError.invalidResponse
        }

        guard httpResponse.statusCode == 202 || httpResponse.statusCode == 200 else {
            throw TaskSubmissionError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(BarCreateRunResponse.self, from: data)
        } catch {
            throw TaskSubmissionError.responseParseFailed(error)
        }
    }
}

enum TaskSubmissionError: LocalizedError, Equatable {
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

    static func == (lhs: TaskSubmissionError, rhs: TaskSubmissionError) -> Bool {
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
