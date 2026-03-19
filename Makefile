APP_NAME = KeyGlow
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app

.PHONY: build bundle run install clean

build:
	swift build -c release

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	@echo "Built $(APP_BUNDLE)"

install: bundle
	@osascript -e 'tell application "$(APP_NAME)" to quit' 2>/dev/null || true
	rm -rf /Applications/$(APP_BUNDLE)
	cp -r $(APP_BUNDLE) /Applications/
	@echo "Installed $(APP_BUNDLE) to /Applications"
	open /Applications/$(APP_BUNDLE)

run: build
	$(BUILD_DIR)/$(APP_NAME)

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
