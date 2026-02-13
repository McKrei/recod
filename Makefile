.PHONY: build run clean

# Default target
all: run

# Build the project
build:
	swift build

# Build and run the application
run: build kill
	@echo "Launching MacAudioEngine..."
	@cp $$(swift build --show-bin-path)/MacAudio2 $$(swift build --show-bin-path)/MacAudioEngine
	@$$(swift build --show-bin-path)/MacAudioEngine

# Force kill any running instances
kill:
	@killall MacAudio2 2>/dev/null || true
	@killall MacAudioEngine 2>/dev/null || true
	@echo "Cleaned up old processes (MacAudio2 & MacAudioEngine)"

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build

# Remove all downloaded models and logs to start fresh
reset: kill
	rm -rf "/Users/evgeniisergunin/Library/Application Support/MacAudio2/Models"
	rm -rf "/Users/evgeniisergunin/Library/Application Support/MacAudio2/Logs"
	@echo "All models and logs have been cleared."
