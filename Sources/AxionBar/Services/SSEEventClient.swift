import Foundation
import os.log

@MainActor
final class SSEEventClient {
    private let baseURL: String
    private var currentTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.axion.AxionBar", category: "SSEEventClient")

    init(baseURL: String = "http://127.0.0.1:4242") {
        self.baseURL = baseURL
    }

    func connect(runId: String) -> AsyncStream<BarSSEEvent> {
        currentTask?.cancel()
        currentTask = nil

        return AsyncStream { continuation in
            let task = Task { [logger] in
                var components = URLComponents(string: "\(baseURL)/v1/runs")!
                components.path += "/\(runId)/events"

                guard let url = components.url else {
                    logger.error("Invalid SSE URL for runId: \(runId)")
                    continuation.finish()
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        logger.error("SSE connection rejected for runId: \(runId)")
                        continuation.finish()
                        return
                    }

                    var currentEvent: String?
                    var currentData: String?

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }

                        if line.hasPrefix("event: ") {
                            currentEvent = String(line.dropFirst("event: ".count))
                        } else if line.hasPrefix("data: ") {
                            currentData = String(line.dropFirst("data: ".count))
                        } else if line.isEmpty {
                            if let eventType = currentEvent, let dataString = currentData {
                                if let event = parseSSEEvent(eventType: eventType, dataString: dataString) {
                                    continuation.yield(event)
                                    if case .runCompleted = event {
                                        continuation.finish()
                                        return
                                    }
                                }
                            }
                            currentEvent = nil
                            currentData = nil
                        }
                    }
                } catch {
                    logger.debug("SSE connection ended for runId: \(runId): \(error.localizedDescription)")
                }

                continuation.finish()
            }

            self.currentTask = task

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func disconnect() {
        currentTask?.cancel()
        currentTask = nil
    }

    nonisolated func parseSSEEvent(eventType: String, dataString: String) -> BarSSEEvent? {
        guard let data = dataString.data(using: .utf8) else { return nil }

        switch eventType {
        case "step_started":
            guard let decoded = try? JSONDecoder().decode(BarStepStartedData.self, from: data) else { return nil }
            return .stepStarted(decoded)
        case "step_completed":
            guard let decoded = try? JSONDecoder().decode(BarStepCompletedData.self, from: data) else { return nil }
            return .stepCompleted(decoded)
        case "run_completed":
            guard let decoded = try? JSONDecoder().decode(BarRunCompletedData.self, from: data) else { return nil }
            return .runCompleted(decoded)
        default:
            return nil
        }
    }
}
