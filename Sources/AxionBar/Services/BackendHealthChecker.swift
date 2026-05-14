import Foundation
import Combine

@MainActor
final class BackendHealthChecker: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var serverVersion: String?

    private let baseURL = "http://127.0.0.1:4242"
    let checkInterval: TimeInterval = 5.0
    private var isChecking = false

    func startChecking() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            while isChecking {
                await checkHealth()
                try? await Task.sleep(for: .seconds(checkInterval))
            }
        }
    }

    func stopChecking() {
        isChecking = false
    }

    func checkOnce() async -> Bool {
        await checkHealth()
        return connectionState == .connected
    }

    private func checkHealth() async {
        guard let url = URL(string: "\(baseURL)/v1/health") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                self.connectionState = .disconnected
                return
            }
            let health = try JSONDecoder().decode(HealthCheckResponse.self, from: data)
            self.connectionState = .connected
            self.serverVersion = health.version
        } catch {
            self.connectionState = .disconnected
        }
    }
}
