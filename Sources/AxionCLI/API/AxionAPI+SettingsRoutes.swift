import Foundation
import Hummingbird
import NIOCore

import AxionCore

extension AxionAPI {

    // MARK: - Settings Route Registration

    /// Register settings API routes (GET/POST/DELETE /v1/settings/api-key).
    static func registerSettingsRoutes(
        on router: RouterGroup<BasicRequestContext>,
        config: AxionConfig,
        resolvedConfigDir: String
    ) {
        // GET /v1/settings/api-key — get API key status
        router.get("settings/api-key") { _, _ in
            let (source, effectiveKey, available) = Self.resolveApiKeySource(config: config)

            return EditedResponse(
                headers: [
                    .contentType: "application/json",
                    .cacheControl: "private, max-age=300",
                ],
                response: ApiKeyStatusResponse(
                    provider: config.provider.rawValue,
                    available: available,
                    source: source,
                    maskedKey: ApiKeyStatusResponse.maskKey(effectiveKey)
                )
            )
        }

        // POST /v1/settings/api-key — save API key
        router.post("settings/api-key") { request, context in
            let buffer: ByteBuffer
            do {
                buffer = try await request.body.collect(upTo: context.maxUploadSize)
            } catch {
                throw AxionAPIError.apiError(status: .badRequest, error: "invalid_request", message: "Failed to read request body.")
            }

            let data = Data(buffer: buffer)
            let saveRequest: SaveApiKeyRequest
            do {
                saveRequest = try JSONDecoder().decode(SaveApiKeyRequest.self, from: data)
            } catch {
                throw AxionAPIError.apiError(status: .badRequest, error: "invalid_request", message: "Failed to parse request body. Expected {\"api_key\": \"...\"}.")
            }

            guard !saveRequest.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AxionAPIError.apiError(status: .badRequest, error: "missing_api_key", message: "Request body must include a non-empty 'api_key' field.")
            }

            // Load current config from file, update apiKey, save back
            var fileConfig: AxionConfig
            if let decoded = ConfigManager.loadRawConfig(from: resolvedConfigDir) {
                fileConfig = decoded
            } else {
                fileConfig = config
            }
            fileConfig.apiKey = saveRequest.apiKey
            try ConfigManager.saveConfigFile(fileConfig, toDirectory: resolvedConfigDir)

            // Return status based on effective key (env may override)
            let env = ProcessInfo.processInfo.environment
            let source: String
            let maskedKey: String
            let available = true
            if let envKey = env["AXION_API_KEY"], !envKey.isEmpty {
                source = "env"
                maskedKey = ApiKeyStatusResponse.maskKey(envKey)
            } else {
                source = "config"
                maskedKey = ApiKeyStatusResponse.maskKey(saveRequest.apiKey)
            }

            return EditedResponse(
                headers: [.contentType: "application/json"],
                response: ApiKeyStatusResponse(
                    provider: config.provider.rawValue,
                    available: available,
                    source: source,
                    maskedKey: maskedKey
                )
            )
        }

        // DELETE /v1/settings/api-key — clear API key
        router.delete("settings/api-key") { _, _ in
            // Load current config from file, clear apiKey, save back
            var fileConfig: AxionConfig
            if let decoded = ConfigManager.loadRawConfig(from: resolvedConfigDir) {
                fileConfig = decoded
            } else {
                fileConfig = config
            }
            fileConfig.apiKey = nil
            try ConfigManager.saveConfigFile(fileConfig, toDirectory: resolvedConfigDir)

            let (source, _, available) = Self.resolveApiKeySource(config: fileConfig)

            return EditedResponse(
                headers: [.contentType: "application/json"],
                response: DeleteApiKeyResponse(
                    provider: config.provider.rawValue,
                    available: available,
                    source: source
                )
            )
        }
    }

    // MARK: - Settings Helpers

    /// Determine the effective API key source.
    /// Returns (source, effectiveKey, available).
    static func resolveApiKeySource(config: AxionConfig) -> (String, String, Bool) {
        let env = ProcessInfo.processInfo.environment
        if let envKey = env["AXION_API_KEY"], !envKey.isEmpty {
            return ("env", envKey, true)
        }
        if let configKey = config.apiKey, !configKey.isEmpty {
            return ("config", configKey, true)
        }
        return ("missing", "", false)
    }
}
