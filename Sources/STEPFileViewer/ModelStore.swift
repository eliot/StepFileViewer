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

    static func makeEmptyScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.black
        return scene
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
        do {
            let result = try ModelLoader.load(url: url)
            let newScene = result.scene
            newScene.background.contents = NSColor.black
            self.scene = newScene
            self.statistics = result.statistics
            self.fileName = url.lastPathComponent
            self.loadVersion &+= 1
        } catch {
            self.errorMessage = "Failed to load \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
