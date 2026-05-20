# STEP File Viewer

A basic native macOS app to previews 3D model files, like `.step` files.

Supported formats:

| Format | Notes                                                              |
| ------ | ------------------------------------------------------------------ |
| STL    | Binary + ASCII, parsed directly                                    |
| OBJ    | ModelIO                                                            |
| PLY    | ModelIO                                                            |
| USDZ / USD / USDA / USDC | ModelIO                                          |
| 3MF    | Custom: unzipped via `/usr/bin/unzip`, XML parsed with XMLParser   |
| STEP / STP | **Wireframe preview only** — see caveat below                  |

## STEP support caveat

True STEP rendering requires tessellating B-Rep geometry (parametric curves
and surfaces), which realistically depends on OpenCASCADE. This viewer ships
a minimal STEP parser that extracts `CARTESIAN_POINT`, `VERTEX_POINT`, and
`EDGE_CURVE` entities and renders them as a point cloud plus straight-edge
wireframe. Curved edges appear as chords. The HUD reports point and line
counts. For full shaded STEP previews, integrate OpenCASCADE.

## Build & run

```
make           # builds build/STEP File Viewer.app
make run       # builds and opens the app
make clean
```

Requirements: macOS 13+, Xcode command-line tools (`swiftc`). No Xcode
project — the Makefile drives `swiftc` against the sources in
`Sources/STEPFileViewer/` and assembles a code-signed `.app` bundle.

## Controls

| Action                | Input                                |
| --------------------- | ------------------------------------ |
| Orbit camera          | Click + drag in viewport             |
| Pan                   | Option + click + drag                |
| Zoom                  | Two-finger scroll / pinch            |
| Move window           | Click + drag in top 24 pt strip      |
| Open file             | ⌘O, or drag-and-drop onto window     |
| Close window          | ⌘W                                   |
| Quit                  | ⌘Q                                   |

The window has no title bar, no traffic-light buttons, and no toolbar — only
the 3D viewport and a small statistics HUD docked bottom-right. The top
24 pt of the window is reserved as a transparent drag handle so the window
can still be moved.

## Statistics HUD

Bottom-right overlay shows:

- `tris`, `quads`, `ngons` — face counts by topology (quads are only
  preserved when the source file declared them, e.g. OBJ; SceneKit
  triangulates everything on import, so we tally counts at MDLAsset level)
- `lines`, `points` — non-mesh primitives (used by STEP wireframe preview)
- `verts` — vertex count
- `meshes` — submesh count when > 1
- `x`, `y`, `z` — bounding box dimensions in source units

## Project layout

```
Sources/STEPFileViewer/
  App.swift              # @main, AppDelegate, NSWindow chrome stripping
  ContentView.swift      # Root SwiftUI view — viewport + HUD + drop target
  SceneViewport.swift    # SCNView wrapper with orbit camera + framing
  ModelStore.swift       # Observable model state + file picker
  ModelLoader.swift      # Format dispatch + SCNGeometry builders
  ModelStatistics.swift  # Face / vertex / bounds accounting
  StatisticsHUD.swift    # Bottom-right statistics overlay
  STLLoader.swift        # Binary + ASCII STL
  ThreeMFLoader.swift    # 3MF (ZIP + XML)
  STEPLoader.swift       # ISO-10303-21 parser (wireframe-only)
Tests/
  test_loaders.swift     # Standalone CLI test runner for loaders
Resources/
  Info.plist             # Bundle metadata + document type associations
Makefile                 # swiftc → .app bundle + codesign
```

## Running the loader tests

```
swiftc -parse-as-library -o build/loader_tests \
  -framework AppKit -framework SceneKit -framework ModelIO -framework UniformTypeIdentifiers \
  Sources/STEPFileViewer/ModelLoader.swift \
  Sources/STEPFileViewer/ModelStatistics.swift \
  Sources/STEPFileViewer/STLLoader.swift \
  Sources/STEPFileViewer/ThreeMFLoader.swift \
  Sources/STEPFileViewer/STEPLoader.swift \
  Tests/test_loaders.swift
./build/loader_tests
```

The test runner expects sample files at `/tmp/cube.stl`,
`/tmp/cube_ascii.stl`, `/tmp/tri.obj`, `/tmp/quad.3mf`, `/tmp/tiny.step` —
the build helpers in the original session generate these from a few lines
of Python and `cat << EOF`.
