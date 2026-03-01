.PHONY: build run clean app dmg release extract-deps test

APP_NAME = Recod
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources
XCFRAMEWORK_DIR = Packages/SherpaOnnx/sherpa-onnx.xcframework
XCFRAMEWORK_ZIP = Packages/SherpaOnnx/sherpa-onnx.xcframework.zip

# Default target
all: run

# Extract heavy dependencies if missing
extract-deps:
	@if [ ! -d "$(XCFRAMEWORK_DIR)" ] && [ -f "$(XCFRAMEWORK_ZIP)" ]; then \
		echo "📦 Extracting sherpa-onnx.xcframework..."; \
		unzip -q "$(XCFRAMEWORK_ZIP)" -d Packages/SherpaOnnx/; \
		echo "✅ Extraction complete."; \
	fi

# Build the project (debug)
build: extract-deps
	swift build

# Build the project (release)
build-release: extract-deps
	swift build -c release

# Run tests with mic entitlement (required for AVAudioEngine hardware capture)
test: extract-deps
	@echo "Building tests..."
	@swift build --build-tests
	@echo "Signing test executable and bundle with audio-input entitlement..."
	@TEST_ARCH=$$(uname -m | sed 's/x86_64/x86_64/' | sed 's/arm64/arm64/'); \
	XCTEST_BUNDLE=".build/$${TEST_ARCH}-apple-macosx/debug/RecodPackageTests.xctest"; \
	TEST_EXE="$${XCTEST_BUNDLE}/Contents/MacOS/RecodPackageTests"; \
	if [ -f "$$TEST_EXE" ]; then \
		codesign -f -s - --entitlements Recod.entitlements "$$TEST_EXE"; \
		echo "  Signed: $$TEST_EXE"; \
	else \
		echo "  WARNING: test executable not found at $$TEST_EXE"; \
		echo "  Falling back to signing bundle..."; \
	fi; \
	codesign -f -s - --entitlements Recod.entitlements "$$XCTEST_BUNDLE"; \
	echo "  Signed: $$XCTEST_BUNDLE"
	@echo "Running AudioEngineGraphTests..."
	@swift test --filter AudioEngineGraphTests --skip-build 2>&1

# Build and run the application
run: build kill
	@echo "Launching Recod..."
	@cp $$(swift build --show-bin-path)/Recod $$(swift build --show-bin-path)/MacAudioEngine
	@$$(swift build --show-bin-path)/MacAudioEngine

# Force kill any running instances
kill:
	@killall Recod 2>/dev/null || true
	@killall MacAudioEngine 2>/dev/null || true
	@echo "Cleaned up old processes (Recod & MacAudioEngine)"

# Build .app bundle for distribution
app: build-release
	@echo "Creating $(APP_NAME).app bundle..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	@mkdir -p $(CONTENTS_DIR)/Frameworks
	@cp $$(swift build -c release --show-bin-path)/$(APP_NAME) $(MACOS_DIR)/$(APP_NAME)
	@cp -R $$(swift build -c release --show-bin-path)/Sparkle.framework $(CONTENTS_DIR)/Frameworks/
	@cp Resources/AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns
	@install_name_tool -add_rpath @executable_path/../Frameworks $(MACOS_DIR)/$(APP_NAME) 2>/dev/null || true
	@sed -e 's/$$(DEVELOPMENT_LANGUAGE)/en/g' \
	     -e 's/$$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/g' \
	     -e 's/$$(MACOSX_DEPLOYMENT_TARGET)/15.0/g' \
	     Info.plist > $(CONTENTS_DIR)/Info.plist
	@echo "Signing $(APP_NAME).app..."
	@codesign --force --sign - $(CONTENTS_DIR)/Frameworks/Sparkle.framework
	@codesign --force --sign - --entitlements Recod.entitlements $(APP_BUNDLE)
	@echo "✅ $(APP_BUNDLE) created and signed successfully!"
	@echo "You can now drag it into /Applications or run: open $(APP_BUNDLE)"

# Create DMG for easy distribution
dmg: app
	@echo "Creating $(APP_NAME).dmg..."
	@rm -f $(BUILD_DIR)/$(APP_NAME).dmg
	@hdiutil create -volname "$(APP_NAME)" \
	    -srcfolder $(APP_BUNDLE) \
	    -ov -format UDZO \
	    $(BUILD_DIR)/$(APP_NAME).dmg
	@echo "✅ $(BUILD_DIR)/$(APP_NAME).dmg created successfully!"

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build
	rm -rf $(BUILD_DIR)
	rm -rf $(XCFRAMEWORK_DIR)

# Remove all downloaded models and logs to start fresh
reset: kill
	rm -rf "/Users/evgeniisergunin/Library/Application Support/recod/Models"
	rm -rf "/Users/evgeniisergunin/Library/Application Support/recod/Logs"
	@echo "All models and logs have been cleared."

# Show current and next version
version:
	@LATEST=$$(git tag -l 'v*' --sort=-creatordate | head -1); \
	if [ -z "$$LATEST" ]; then \
		echo "Текущая версия: нет тегов"; \
		echo "Следующая версия: 1.01"; \
	else \
		echo "Текущая версия: $$LATEST"; \
		MAJOR=$$(echo "$$LATEST" | sed 's/v//' | cut -d. -f1); \
		MINOR=$$(echo "$$LATEST" | sed 's/v//' | cut -d. -f2 | sed 's/^0*//'); \
		MINOR=$${MINOR:-0}; \
		NEXT_MINOR=$$((MINOR + 1)); \
		if [ $$NEXT_MINOR -lt 10 ]; then \
			echo "Следующая версия: v$$MAJOR.0$$NEXT_MINOR"; \
		else \
			echo "Следующая версия: v$$MAJOR.$$NEXT_MINOR"; \
		fi; \
	fi

# Create a new release with auto-incremented version
# Usage:
#   make release              — auto-increment minor (1.01 → 1.02)
#   make release MAJOR=2      — start new major version (2.01)
release:
	@LATEST=$$(git tag -l 'v*' --sort=-creatordate | head -1); \
	if [ -n "$(MAJOR)" ]; then \
		NEW_VERSION="$(MAJOR).01"; \
	elif [ -z "$$LATEST" ]; then \
		NEW_VERSION="1.01"; \
	else \
		MAJOR_NUM=$$(echo "$$LATEST" | sed 's/v//' | cut -d. -f1); \
		MINOR_NUM=$$(echo "$$LATEST" | sed 's/v//' | cut -d. -f2 | sed 's/^0*//'); \
		MINOR_NUM=$${MINOR_NUM:-0}; \
		NEXT=$$((MINOR_NUM + 1)); \
		if [ $$NEXT -gt 99 ]; then \
			echo "⚠️  Minor version exceeded 99! Use: make release MAJOR=$$((MAJOR_NUM + 1))"; \
			exit 1; \
		fi; \
		if [ $$NEXT -lt 10 ]; then \
			NEW_VERSION="$$MAJOR_NUM.0$$NEXT"; \
		else \
			NEW_VERSION="$$MAJOR_NUM.$$NEXT"; \
		fi; \
	fi; \
	echo "🚀 Releasing v$$NEW_VERSION..."; \
	git tag -a "v$$NEW_VERSION" -m "Release v$$NEW_VERSION"; \
	git push origin "v$$NEW_VERSION"; \
	echo "✅ v$$NEW_VERSION released! GitHub Actions will build and publish."
