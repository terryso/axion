.PHONY: test test-integration test-all build

build:
	swift build

test:
	swift test --skip AxionHelperIntegrationTests

test-integration:
	swift test --filter AxionHelperIntegrationTests

test-all:
	swift test
