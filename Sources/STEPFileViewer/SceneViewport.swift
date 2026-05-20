import SwiftUI
import SceneKit
import AppKit

struct SceneViewport: NSViewRepresentable {
    @ObservedObject var store: ModelStore

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = store.scene
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.showsStatistics = false
        view.debugOptions = store.wireframe ? [.renderAsWireframe] : []
        context.coordinator.frameScene(view, scene: store.scene)
        context.coordinator.lastVersion = store.loadVersion
        Coordinator.applyObjectColor(store.objectColor, to: store.scene)
        context.coordinator.lastColor = store.objectColor
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        let coord = context.coordinator
        if nsView.scene !== store.scene {
            nsView.scene = store.scene
        }
        let versionChanged = coord.lastVersion != store.loadVersion
        if versionChanged {
            coord.lastVersion = store.loadVersion
            coord.frameScene(nsView, scene: store.scene)
        }
        if versionChanged || coord.lastColor != store.objectColor {
            coord.lastColor = store.objectColor
            Coordinator.applyObjectColor(store.objectColor, to: store.scene)
        }
        let wire: SCNDebugOptions = store.wireframe ? [.renderAsWireframe] : []
        if nsView.debugOptions != wire {
            nsView.debugOptions = wire
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastVersion: Int = -1
        var lastColor: Color? = nil

        /// Recolor every geometry material's diffuse channel.
        static func applyObjectColor(_ color: Color, to scene: SCNScene) {
            let ns = NSColor(color)
            scene.rootNode.enumerateChildNodes { node, _ in
                guard let geom = node.geometry else { return }
                for material in geom.materials {
                    material.diffuse.contents = ns
                }
            }
        }

        /// Position a camera to frame the entire model and configure the orbit target.
        func frameScene(_ view: SCNView, scene: SCNScene) {
            // Remove any pre-existing viewer cameras we previously added
            scene.rootNode.childNodes
                .filter { $0.name == "viewerCamera" }
                .forEach { $0.removeFromParentNode() }

            let (minV, maxV) = scene.rootNode.boundingBox
            let size = SCNVector3(
                CGFloat(maxV.x - minV.x),
                CGFloat(maxV.y - minV.y),
                CGFloat(maxV.z - minV.z)
            )
            let center = SCNVector3(
                CGFloat((minV.x + maxV.x) / 2),
                CGFloat((minV.y + maxV.y) / 2),
                CGFloat((minV.z + maxV.z) / 2)
            )
            let extent = max(max(size.x, size.y), size.z)
            let extentF = max(CGFloat(extent), 0.001)
            let distance = extentF * 2.6

            let cam = SCNCamera()
            cam.fieldOfView = 40
            cam.zNear = Double(extentF) * 0.005
            cam.zFar = Double(extentF) * 50
            cam.wantsHDR = false
            let camNode = SCNNode()
            camNode.name = "viewerCamera"
            camNode.camera = cam
            // Pleasant 3/4 perspective
            let offset = SCNVector3(distance * 0.7, distance * 0.55, distance * 0.85)
            camNode.position = SCNVector3(
                center.x + offset.x,
                center.y + offset.y,
                center.z + offset.z
            )
            camNode.look(at: center)
            scene.rootNode.addChildNode(camNode)
            view.pointOfView = camNode

            // Configure orbit target so click-drag rotates around the model.
            view.defaultCameraController.target = center
            view.defaultCameraController.worldUp = SCNVector3(0, 1, 0)
        }
    }
}
