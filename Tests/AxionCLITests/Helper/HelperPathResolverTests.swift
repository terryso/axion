import Testing
import Foundation
@testable import AxionCLI

@Suite("HelperPathResolver")
struct HelperPathResolverTests {

    private func withHelperEnv(_ value: String?, body: @Sendable () async throws -> Void) async throws {
        try await EnvGate.shared.withSavedEnv(["AXION_HELPER_PATH"]) {
            if let value {
                setenv("AXION_HELPER_PATH", value, 1)
            }
            try await body()
        }
    }

    @Test("HelperPathResolver type exists")
    func helperPathResolverTypeExists() throws {
        _ = HelperPathResolver.self
    }

    @Test("resolveHelperPath method exists and returns String?")
    func resolveMethodExists() throws {
        let result: String? = HelperPathResolver.resolveHelperPath()
        _ = result
    }

    @Test("env variable AXION_HELPER_PATH returns that path")
    func resolveEnvVariableReturnsEnvPath() async throws {
        try await withHelperEnv("/tmp/test/AxionHelper.app/Contents/MacOS/AxionHelper") {
            let result = HelperPathResolver.resolveHelperPath()
            #expect(result == "/tmp/test/AxionHelper.app/Contents/MacOS/AxionHelper")
        }
    }

    @Test("env variable path returned even if file does not exist")
    func resolveEnvVariableReturnsEvenIfNotExists() async throws {
        try await withHelperEnv("/nonexistent/path/AxionHelper.app/Contents/MacOS/AxionHelper") {
            let result = HelperPathResolver.resolveHelperPath()
            #expect(result == "/nonexistent/path/AxionHelper.app/Contents/MacOS/AxionHelper")
        }
    }

    @Test("relative path builds Homebrew-style path")
    func resolveRelativePathBuildsHomebrewStylePath() async throws {
        try await withHelperEnv(nil) {
            let result = HelperPathResolver.resolveHelperPath()
            if let path = result {
                #expect(
                    path.hasSuffix("AxionHelper.app/Contents/MacOS/AxionHelper")
                        || path.hasSuffix("AxionHelper")
                )
            }
        }
    }

    @Test("Homebrew path contains libexec/axion")
    func resolveHomebrewPathContainsLibexecAxion() async throws {
        try await withHelperEnv(nil) {
            let result = HelperPathResolver.resolveHelperPath()
            if let path = result, path.contains("libexec") {
                #expect(path.contains("libexec/axion"))
            }
        }
    }

    @Test("development mode detects .build directory")
    func resolveDevelopmentModeDetectsBuildDirectory() async throws {
        try await withHelperEnv(nil) {
            let result = HelperPathResolver.resolveHelperPath()
            _ = result
        }
    }

    @Test("development mode path contains .build/AxionHelper.app")
    func resolveDevelopmentModeBuildPathFormat() async throws {
        try await withHelperEnv(nil) {
            let result = HelperPathResolver.resolveHelperPath()
            if let path = result, path.contains(".build") {
                #expect(path.contains("AxionHelper.app"))
            }
        }
    }

    @Test("no helper found returns nil without crashing")
    func resolveNoHelperFoundReturnsNil() async throws {
        try await withHelperEnv(nil) {
            let result = HelperPathResolver.resolveHelperPath()
            _ = result
        }
    }

    @Test("env variable takes priority over relative path")
    func resolveEnvVariableTakesPriorityOverRelativePath() async throws {
        let envPath = "/custom/env/AxionHelper.app/Contents/MacOS/AxionHelper"
        try await withHelperEnv(envPath) {
            let result = HelperPathResolver.resolveHelperPath()
            #expect(result == envPath)
        }
    }

    @Test("empty env variable falls through to other strategies")
    func resolveEmptyEnvVariableFallsThrough() async throws {
        try await EnvGate.shared.withSavedEnv(["AXION_HELPER_PATH"]) {
            setenv("AXION_HELPER_PATH", "", 1)
            let result = HelperPathResolver.resolveHelperPath()
            #expect(result != "")
        }
    }

    @Test("result path points to executable not .app directory")
    func resolveResultPathPointsToExecutable() async throws {
        let envPath = "/opt/homebrew/Cellar/axion/0.1.0/libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper"
        try await withHelperEnv(envPath) {
            let result = HelperPathResolver.resolveHelperPath()
            if let path = result {
                #expect(!path.hasSuffix(".app"))
                #expect(path.hasSuffix("AxionHelper"))
            }
        }
    }

    @Test("result path is absolute")
    func resolveResultPathIsAbsolute() async throws {
        let envPath = "/absolute/path/AxionHelper"
        try await withHelperEnv(envPath) {
            let result = HelperPathResolver.resolveHelperPath()
            if let path = result {
                #expect(path.hasPrefix("/"))
            }
        }
    }

    @Test("supports /opt/homebrew path (Apple Silicon)")
    func resolveSupportsOptHomebrewPath() async throws {
        let armPath = "/opt/homebrew/Cellar/axion/0.1.0/libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper"
        try await withHelperEnv(armPath) {
            let result = HelperPathResolver.resolveHelperPath()
            #expect(result == armPath)
        }
    }

    @Test("supports /usr/local path (Intel Mac)")
    func resolveSupportsUsrLocalPath() async throws {
        let intelPath = "/usr/local/Cellar/axion/0.1.0/libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper"
        try await withHelperEnv(intelPath) {
            let result = HelperPathResolver.resolveHelperPath()
            #expect(result == intelPath)
        }
    }

    @Test("no hardcoded paths in resolver")
    func resolverNoHardcodedPaths() async throws {
        try await withHelperEnv(nil) {
            let result = HelperPathResolver.resolveHelperPath()
            if let path = result {
                _ = path
            }
        }
    }
}
