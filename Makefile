.PHONY: test test-integration test-e2e test-e2e-real test-acceptance test-all build

VERSION := $(shell cat VERSION)
HELPER_DEBUG_PATH := $(CURDIR)/.build/debug/AxionHelper
HELPER_APP_PATH := $(CURDIR)/.build/AxionHelper.app/Contents/MacOS/AxionHelper

build:
	swift build
	@PLIST=".build/AxionHelper.app/Contents/Info.plist"; \
		if [ -f "$$PLIST" ]; then \
			/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$$PLIST" 2>/dev/null || true; \
		fi

test:
	swift build --build-tests
	@PLIST=".build/AxionHelper.app/Contents/Info.plist"; \
		if [ -f "$$PLIST" ]; then \
			/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$$PLIST" 2>/dev/null || true; \
		fi
	swift test --no-parallel --skip AxionHelperIntegrationTests --skip AxionCLIIntegrationTests --skip AxionE2ETests

test-integration:
	AXION_HELPER_PATH="$(HELPER_DEBUG_PATH)" swift test --no-parallel --filter AxionHelperIntegrationTests --filter AxionCLIIntegrationTests

test-e2e:
	AXION_HELPER_PATH="$(HELPER_DEBUG_PATH)" swift test --no-parallel --filter AxionE2ETests

test-e2e-real:
	AXION_HELPER_PATH="$(HELPER_DEBUG_PATH)" swift test --no-parallel --filter AxionE2ETests.RealLLME2ETests

test-acceptance:
	bash Distribution/homebrew/build-helper-app.sh
	AXION_HELPER_PATH="$(HELPER_APP_PATH)" swift test --no-parallel --filter AxionE2ETests.AcceptanceE2E

test-all:
	swift test
