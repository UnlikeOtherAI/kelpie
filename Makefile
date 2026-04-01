.PHONY: all cli ios android macos linux linux-headless-docker windows monitor help \
        cli-build cli-link \
        ios-build ios-run \
        android-build android-run \
        macos-build macos-run

REPO_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# ── Android SDK ────────────────────────────────────────────────────────────────
ANDROID_SDK   := $(HOME)/Library/Android/sdk

# ── Xcode ──────────────────────────────────────────────────────────────────────
IOS_SCHEME    := Mollotov
IOS_PROJECT   := apps/ios/Mollotov.xcodeproj

MACOS_SCHEME  := Mollotov
MACOS_PROJECT := apps/macos/Mollotov.xcodeproj

# ── CLI ────────────────────────────────────────────────────────────────────────
CLI_DIR       := packages/cli

# ── CLI-style subcommand forwarding ───────────────────────────────────────────
# Allows:  make ios [list|<udid>]
#          make android [list|non-interactive|<serial>]
# Any word after the primary target is intercepted so make doesn't error on it.

ifeq ($(firstword $(MAKECMDGOALS)),ios)
  _IOS_ARG := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  $(foreach a,$(_IOS_ARG),$(eval $(a):;@:))
endif

ifeq ($(firstword $(MAKECMDGOALS)),android)
  _ANDROID_ARG := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  $(foreach a,$(_ANDROID_ARG),$(eval $(a):;@:))
endif

# ── Targets ────────────────────────────────────────────────────────────────────

help:
	@echo ""
	@echo "  make cli                    Build CLI and link to system"
	@echo "  make ios                    Build + launch iOS (interactive picker)"
	@echo "  make ios list               List available iOS devices/simulators"
	@echo "  make ios <udid>             Build + launch on specific device"
	@echo "  make android                Build + launch Android (picker if multiple)"
	@echo "  make android list           List available Android targets"
	@echo "  make android non-interactive  Auto-select without prompting"
	@echo "  make android <serial|avd>   Build + launch on specific target"
	@echo "  make macos                  Build and launch macOS app"
	@echo "  make linux                  Build Linux app via CMake"
	@echo "  make linux-headless-docker  Build Linux headless Docker image"
	@echo "  make monitor                Start monitoring API + dashboard"
	@echo ""

# ── CLI ────────────────────────────────────────────────────────────────────────

cli: cli-build cli-link

cli-build:
	@echo "→ Building CLI..."
	pnpm --filter @unlikeotherai/mollotov build

cli-link:
	@echo "→ Linking mollotov to system..."
	cd $(CLI_DIR) && pnpm link --global
	@echo "✓ mollotov linked — run 'mollotov --help' to verify"

# ── iOS ────────────────────────────────────────────────────────────────────────

ios:
	@if [ "$(_IOS_ARG)" = "list" ]; then \
		bash scripts/ios-select.sh list; \
	else \
		TARGET_LINE=$$(bash scripts/ios-select.sh $(_IOS_ARG)); \
		IOS_TARGET=$$(echo "$$TARGET_LINE" | cut -f1); \
		IOS_TYPE=$$(echo "$$TARGET_LINE" | cut -f2); \
		$(MAKE) ios-build IOS_TARGET="$$IOS_TARGET" IOS_TYPE="$$IOS_TYPE"; \
		$(MAKE) ios-run   IOS_TARGET="$$IOS_TARGET" IOS_TYPE="$$IOS_TYPE"; \
	fi

ios-build:
	@if [ "$(IOS_TYPE)" = "device" ]; then \
		echo "→ Building iOS app (device $(IOS_TARGET))..."; \
		xcodebuild \
			-project $(IOS_PROJECT) \
			-scheme $(IOS_SCHEME) \
			-destination 'platform=iOS,id=$(IOS_TARGET)' \
			-configuration Debug \
			-derivedDataPath apps/ios/.build \
			build | xcpretty 2>/dev/null || xcodebuild \
			-project $(IOS_PROJECT) \
			-scheme $(IOS_SCHEME) \
			-destination 'platform=iOS,id=$(IOS_TARGET)' \
			-configuration Debug \
			-derivedDataPath apps/ios/.build \
			build; \
	else \
		echo "→ Building iOS app (simulator $(IOS_TARGET))..."; \
		xcodebuild \
			-project $(IOS_PROJECT) \
			-scheme $(IOS_SCHEME) \
			-destination 'platform=iOS Simulator,id=$(IOS_TARGET)' \
			-configuration Debug \
			-derivedDataPath apps/ios/.build \
			build | xcpretty 2>/dev/null || xcodebuild \
			-project $(IOS_PROJECT) \
			-scheme $(IOS_SCHEME) \
			-destination 'platform=iOS Simulator,id=$(IOS_TARGET)' \
			-configuration Debug \
			-derivedDataPath apps/ios/.build \
			build; \
	fi

ios-run:
	@if [ "$(IOS_TYPE)" = "device" ]; then \
		APP_PATH=$$(find apps/ios/.build -name "Mollotov.app" -not -path "*simulator*" 2>/dev/null | head -1); \
		echo "→ Installing on device $(IOS_TARGET) ..."; \
		xcrun devicectl device install app --device $(IOS_TARGET) "$$APP_PATH"; \
		echo "→ Launching..."; \
		xcrun devicectl device process launch --device $(IOS_TARGET) com.unlikeotherai.mollotov; \
	else \
		echo "→ Booting simulator $(IOS_TARGET)..."; \
		xcrun simctl boot $(IOS_TARGET) 2>/dev/null || true; \
		open -a Simulator; \
		APP_PATH=$$(find apps/ios/.build -name "Mollotov.app" -not -path "*iphonesimulator.xcarchive*" 2>/dev/null | head -1); \
		echo "→ Installing $$APP_PATH ..."; \
		xcrun simctl install $(IOS_TARGET) "$$APP_PATH"; \
		echo "→ Launching..."; \
		xcrun simctl launch $(IOS_TARGET) com.unlikeotherai.mollotov; \
	fi

# ── Android ────────────────────────────────────────────────────────────────────

android:
	@if [ "$(_ANDROID_ARG)" = "list" ]; then \
		bash scripts/android-select.sh list; \
	else \
		TARGET_LINE=$$(bash scripts/android-select.sh $(_ANDROID_ARG)); \
		ANDROID_TARGET=$$(echo "$$TARGET_LINE" | cut -f1); \
		ANDROID_TYPE=$$(echo "$$TARGET_LINE" | cut -f2); \
		$(MAKE) android-build; \
		$(MAKE) android-run ANDROID_TARGET="$$ANDROID_TARGET" ANDROID_TYPE="$$ANDROID_TYPE"; \
	fi

android-build:
	@echo "→ Building Android APK (debug)..."
	cd apps/android && ./gradlew assembleDebug

android-run:
	@APK=$$(find apps/android -name "app-debug.apk" | head -1); \
	bash scripts/android-run.sh "$(ANDROID_TARGET)" "$(ANDROID_TYPE)" "$$APK"

# ── macOS ──────────────────────────────────────────────────────────────────────

macos: macos-build macos-run

macos-build:
	@echo "→ Building macOS app..."
	xcodebuild \
		-project $(MACOS_PROJECT) \
		-scheme $(MACOS_SCHEME) \
		-configuration Debug \
		-derivedDataPath apps/macos/.build \
		build | xcpretty 2>/dev/null || xcodebuild \
		-project $(MACOS_PROJECT) \
		-scheme $(MACOS_SCHEME) \
		-configuration Debug \
		-derivedDataPath apps/macos/.build \
		build

macos-run:
	@APP_PATH=$$(find apps/macos/.build -name "Mollotov.app" 2>/dev/null | head -1); \
	echo "→ Launching $$APP_PATH ..."; \
	open "$$APP_PATH"

# ── Linux ──────────────────────────────────────────────────────────────────────

linux:
	@echo "→ Building Linux app via CMake..."
	@if [ ! -f apps/linux/CMakeLists.txt ]; then \
		echo "✗ apps/linux/CMakeLists.txt not found"; \
		exit 1; \
	fi
	cmake -S native -B native/.build-linux -G Ninja
	cmake --build native/.build-linux
	cmake -S apps/linux -B apps/linux/build -G Ninja -DNATIVE_BUILD_DIR=$(REPO_ROOT)native/.build-linux
	cmake --build apps/linux/build

linux-headless-docker:
	@echo "→ Building Linux headless Docker image..."
	docker build -t mollotov-linux-headless -f apps/linux/Dockerfile .

windows:
	@echo "→ Windows cross-compilation from macOS is not configured yet."
	@echo "→ Placeholder target only."

# ── Monitoring ─────────────────────────────────────────────────────────────────

monitor:
	$(MAKE) -C monitoring monitor
