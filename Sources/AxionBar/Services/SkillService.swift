import Foundation
import os.log

@MainActor
final class SkillService {
    private let baseURL: String
    private let logger = Logger(subsystem: "com.axion.AxionBar", category: "SkillService")

    init(baseURL: String = "http://127.0.0.1:4242") {
        self.baseURL = baseURL
    }

    func fetchSkills() async throws -> [BarSkillSummary] {
        guard let url = URL(string: "\(baseURL)/v1/skills") else {
            throw SkillServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SkillServiceError.serverUnreachable(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SkillServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw SkillServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode([BarSkillSummary].self, from: data)
        } catch {
            throw SkillServiceError.responseParseFailed(error)
        }
    }

    func fetchSkill(name: String) async throws -> BarSkillDetail {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = URL(string: "\(baseURL)/v1/skills/\(encoded)") else {
            throw SkillServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SkillServiceError.serverUnreachable(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SkillServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw SkillServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(BarSkillDetail.self, from: data)
        } catch {
            throw SkillServiceError.responseParseFailed(error)
        }
    }

    func runSkill(name: String, params: [String: String]? = nil) async throws -> BarSkillRunResponse {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = URL(string: "\(baseURL)/v1/skills/\(encoded)/run") else {
            throw SkillServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = BarSkillRunRequest(params: params)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SkillServiceError.serverUnreachable(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SkillServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 202 || httpResponse.statusCode == 200 else {
            throw SkillServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(BarSkillRunResponse.self, from: data)
        } catch {
            throw SkillServiceError.responseParseFailed(error)
        }
    }
}

enum SkillServiceError: LocalizedError, Equatable {
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

    static func == (lhs: SkillServiceError, rhs: SkillServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL): return true
        case (.serverUnreachable(let a), .serverUnreachable(let b)):
            return a.localizedDescription == b.localizedDescription
        case (.invalidResponse, .invalidResponse): return true
        case (.httpError(let a), .httpError(let b)): return a == b
        case (.responseParseFailed(let a), .responseParseFailed(let b)):
            return a.localizedDescription == b.localizedDescription
        default: return false
        }
    }
}
