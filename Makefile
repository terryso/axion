.PHONY: test test-integration test-all build

build:
	swift build

test:
	swift test --skip AxionHelperIntegrationTests --skip AxionCLIIntegrationTests

test-integration:
	AXION_HELPER_PATH="$$(pwd)/.build/AxionHelper.app/Contents/MacOS/AxionHelper" swift test --filter AxionHelperIntegrationTests --filter AxionCLIIntegrationTests

test-all:
	swift test
