import Foundation
import OpenAgentSDK

@main
struct AgentHTTPServerExample {
    static func main() async throws {
        let dotEnv = loadDotEnv()
        let apiKey = getEnv("ANTHROPIC_API_KEY", from: dotEnv)
        let model = getEnv("CODEANY_MODEL", from: dotEnv) ?? "claude-sonnet-4-6"

        let agent = createAgent(options: AgentOptions(
            apiKey: apiKey,
            model: model
        ))

        let server = AgentHTTPServer(
            agent: agent,
            host: "127.0.0.1",
            port: 4242,
            authKey: "demo-secret-key",
            maxConcurrentRuns: 5
        )

        print("╔══════════════════════════════════════════════════════════════╗")
        print("║  AgentHTTPServer Example                                    ║")
        print("╚══════════════════════════════════════════════════════════════╝")
        print()
        print("Starting server on http://127.0.0.1:4242")
        print()
        print("Try these curl commands:")
        print()
        print("# Health check (no auth required)")
        print("  curl http://127.0.0.1:4242/v1/health")
        print()
        print("# Submit a new run")
        print("  curl -X POST http://127.0.0.1:4242/v1/runs \\")
        print("    -H 'Authorization: Bearer demo-secret-key' \\")
        print("    -H 'Content-Type: application/json' \\")
        print("    -d '{\"task\": \"List files in the current directory\"}'")
        print()
        print("# List all runs")
        print("  curl http://127.0.0.1:4242/v1/runs \\")
        print("    -H 'Authorization: Bearer demo-secret-key'")
        print()
        print("# Get run status (replace {run_id})")
        print("  curl http://127.0.0.1:4242/v1/runs/{run_id} \\")
        print("    -H 'Authorization: Bearer demo-secret-key'")
        print()
        print("# Stream run events via SSE")
        print("  curl -N http://127.0.0.1:4242/v1/runs/{run_id}/events \\")
        print("    -H 'Authorization: Bearer demo-secret-key'")
        print()

        try await server.start()
    }
}
