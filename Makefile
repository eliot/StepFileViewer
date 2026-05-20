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

# Loader test runner: the non-UI loader sources plus the test harness.
TEST_BIN = $(BUILD_DIR)/loader_tests
TEST_FRAMEWORKS = -framework AppKit -framework SceneKit -framework ModelIO -framework UniformTypeIdentifiers
TEST_SOURCES = \
	Sources/STEPFileViewer/ModelLoader.swift \
	Sources/STEPFileViewer/ModelStatistics.swift \
	Sources/STEPFileViewer/STLLoader.swift \
	Sources/STEPFileViewer/ThreeMFLoader.swift \
	Sources/STEPFileViewer/STEPLoader.swift \
	Sources/STEPFileViewer/FreeCADBridge.swift \
	Tests/test_loaders.swift

.PHONY: all run test clean

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

test: $(TEST_BIN)
	./$(TEST_BIN) Tests/fixtures

$(TEST_BIN): $(TEST_SOURCES)
	@mkdir -p "$(BUILD_DIR)"
	swiftc -parse-as-library -o "$(TEST_BIN)" $(TEST_FRAMEWORKS) $(TEST_SOURCES)

clean:
	rm -rf $(BUILD_DIR)
