import SwiftUI
import SceneKit
import AppKit

struct SceneViewport: NSViewRepresentable {
    @ObservedObject var store: ModelStore

    func makeNSView(context: Context) -> SCNView {
        let view = ChromelessSCNView(frame: .zero)
        view.scene = store.scene
        view.backgroundColor = NSColor.black
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.showsStatistics = false
        context.coordinator.frameScene(view, scene: store.scene)
        context.coordinator.lastVersion = store.loadVersion
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        if nsView.scene !== store.scene {
            nsView.scene = store.scene
        }
        if context.coordinator.lastVersion != store.loadVersion {
            context.coordinator.lastVersion = store.loadVersion
            context.coordinator.frameScene(nsView, scene: store.scene)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastVersion: Int = -1

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

/// SCNView subclass that makes the top edge draggable for the (chrome-less) window
/// while leaving the rest of the surface available for orbit/pan.
final class ChromelessSCNView: SCNView {
    // Top 24pt strip acts as a window-drag handle.
    private let dragHandleHeight: CGFloat = 24

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass through clicks in the top drag area to the window for moving.
        if point.y >= bounds.maxY - dragHandleHeight {
            return nil
        }
        return super.hitTest(point)
    }
}
