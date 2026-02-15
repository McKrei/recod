.PHONY: build run clean app dmg

APP_NAME = Recod
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

# Default target
all: run

# Build the project (debug)
build:
	swift build

# Build the project (release)
build-release:
	swift build -c release

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
	@cp $$(swift build -c release --show-bin-path)/$(APP_NAME) $(MACOS_DIR)/$(APP_NAME)
	@sed -e 's/$$(DEVELOPMENT_LANGUAGE)/en/g' \
	     -e 's/$$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/g' \
	     -e 's/$$(MACOSX_DEPLOYMENT_TARGET)/15.0/g' \
	     Info.plist > $(CONTENTS_DIR)/Info.plist
	@echo "✅ $(APP_BUNDLE) created successfully!"
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

# Remove all downloaded models and logs to start fresh
reset: kill
	rm -rf "/Users/evgeniisergunin/Library/Application Support/recod/Models"
	rm -rf "/Users/evgeniisergunin/Library/Application Support/recod/Logs"
	@echo "All models and logs have been cleared."
