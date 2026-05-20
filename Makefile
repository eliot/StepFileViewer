APP_NAME = STEP File Viewer
BIN_NAME = STEPFileViewer
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS)/MacOS
RESOURCES_DIR = $(CONTENTS)/Resources

SOURCES = $(wildcard Sources/STEPFileViewer/*.swift)
SWIFT_FLAGS = -O -parse-as-library
FRAMEWORKS = -framework SwiftUI -framework AppKit -framework SceneKit -framework ModelIO -framework UniformTypeIdentifiers -framework Metal -framework MetalKit

.PHONY: all run clean

all: $(APP_BUNDLE)

$(APP_BUNDLE): $(SOURCES) Resources/Info.plist
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	swiftc $(SWIFT_FLAGS) \
		-o "$(MACOS_DIR)/$(BIN_NAME)" \
		$(FRAMEWORKS) \
		$(SOURCES)
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	codesign --force --deep --sign - "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

run: $(APP_BUNDLE)
	open "$(APP_BUNDLE)"

clean:
	rm -rf $(BUILD_DIR)
