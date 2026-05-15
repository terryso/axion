.PHONY: test test-integration test-e2e test-e2e-real test-all build

build:
	swift build

test:
	swift test --no-parallel --skip AxionHelperIntegrationTests --skip AxionCLIIntegrationTests --skip AxionE2ETests

test-integration:
	AXION_HELPER_PATH="$$(pwd)/.build/AxionHelper.app/Contents/MacOS/AxionHelper" swift test --filter AxionHelperIntegrationTests --filter AxionCLIIntegrationTests

test-e2e:
	AXION_HELPER_PATH="$$(pwd)/.build/AxionHelper.app/Contents/MacOS/AxionHelper" swift test --filter AxionE2ETests

test-e2e-real:
	AXION_HELPER_PATH="$$(pwd)/.build/AxionHelper.app/Contents/MacOS/AxionHelper" swift test --filter AxionE2ETests.RealLLME2ETests

test-all:
	swift test
