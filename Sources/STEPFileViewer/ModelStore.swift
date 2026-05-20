import Foundation
import SwiftUI
import SceneKit
import AppKit
import UniformTypeIdentifiers

@MainActor
final class ModelStore: ObservableObject {
    @Published var scene: SCNScene = ModelStore.makeEmptyScene()
    @Published var statistics: ModelStatistics = .empty
    @Published var fileName: String? = nil
    @Published var errorMessage: String? = nil
    @Published var loadVersion: Int = 0  // bumped on successful load to trigger reframe
    @Published var isLoading: Bool = false
    @Published var wireframe: Bool = false

    /// Color applied to every geometry material. Persisted across launches.
    @Published var objectColor: Color {
        didSet { Self.persistColor(objectColor) }
    }

    private static let colorDefaultsKey = "objectColor.rgba"

    static let defaultObjectColor = Color(.sRGB, red: 0.55, green: 0.57, blue: 0.62, opacity: 1.0)

    init() {
        // Assigning in init does not fire `didSet`, so this load does not re-persist.
        objectColor = Self.loadPersistedColor()
    }

    static func makeEmptyScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = nil
        return scene
    }

    static func loadPersistedColor() -> Color {
        guard let comps = UserDefaults.standard.array(forKey: colorDefaultsKey) as? [Double],
              comps.count == 4 else {
            return defaultObjectColor
        }
        return Color(.sRGB, red: comps[0], green: comps[1], blue: comps[2], opacity: comps[3])
    }

    static func persistColor(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(white: 0.55, alpha: 1)
        UserDefaults.standard.set(
            [Double(ns.redComponent), Double(ns.greenComponent),
             Double(ns.blueComponent), Double(ns.alphaComponent)],
            forKey: colorDefaultsKey
        )
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.message = "Open a 3D model file"
        var types: [UTType] = []
        for ext in ["stl", "obj", "ply", "usdz", "usd", "usda", "usdc", "3mf", "step", "stp", "abc"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        panel.allowedContentTypes = types
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let url = panel.url {
            load(url: url)
        }
    }

    func load(url: URL) {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                let result = try await ModelLoader.loadAsync(url: url)
                let newScene = result.scene
                newScene.background.contents = nil
                self.scene = newScene
                self.statistics = result.statistics
                self.fileName = url.lastPathComponent
                self.loadVersion &+= 1
            } catch {
                self.errorMessage = "Failed to load \(url.lastPathComponent): \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }
}
