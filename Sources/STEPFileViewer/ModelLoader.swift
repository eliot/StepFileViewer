import Foundation
import SceneKit
import ModelIO
import SceneKit.ModelIO
import simd

enum ModelLoaderError: LocalizedError {
    case unreadable(String)
    case unsupported(String)
    case empty
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let s): return "Unreadable file: \(s)"
        case .unsupported(let ext): return "Unsupported format: .\(ext)"
        case .empty: return "No geometry found in file"
        case .parseError(let s): return s
        }
    }
}

struct ModelLoadResult {
    let scene: SCNScene
    let statistics: ModelStatistics
}

enum ModelLoader {
    static func load(url: URL) throws -> ModelLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ModelLoaderError.unreadable(url.lastPathComponent)
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "stl":
            return try STLLoader.load(url: url)
        case "obj", "ply", "abc", "usd", "usda", "usdc", "usdz":
            return try loadViaModelIO(url: url)
        case "3mf":
            return try ThreeMFLoader.load(url: url)
        case "step", "stp":
            return try STEPLoader.load(url: url)
        default:
            // Last-ditch: try ModelIO; if it can sniff it, great.
            return try loadViaModelIO(url: url)
        }
    }

    private static func loadViaModelIO(url: URL) throws -> ModelLoadResult {
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: nil)
        asset.loadTextures()
        guard asset.count > 0 else { throw ModelLoaderError.empty }
        let stats = ModelStatistics.compute(fromAsset: asset)
        let scene = SCNScene(mdlAsset: asset)
        applyDefaultMaterial(to: scene)
        return ModelLoadResult(scene: scene, statistics: stats)
    }

    /// Ensure every geometry has a usable material — many file formats arrive without one.
    static func applyDefaultMaterial(to scene: SCNScene) {
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geom = node.geometry else { return }
            if geom.materials.isEmpty || geom.firstMaterial?.diffuse.contents == nil {
                let m = SCNMaterial()
                m.lightingModel = .physicallyBased
                m.diffuse.contents = NSColor(calibratedRed: 0.78, green: 0.80, blue: 0.85, alpha: 1.0)
                m.metalness.contents = 0.15
                m.roughness.contents = 0.45
                m.isDoubleSided = true
                geom.materials = [m]
            } else {
                geom.firstMaterial?.isDoubleSided = true
            }
        }
    }

    /// Build an SCNGeometry from raw arrays. Used by STL/3MF/STEP loaders.
    static func makeTriangleGeometry(vertices: [SIMD3<Float>],
                                     normals: [SIMD3<Float>]?,
                                     indices: [UInt32]) -> SCNGeometry {
        let vertexData = vertices.withUnsafeBufferPointer { Data(buffer: $0) }
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        var sources: [SCNGeometrySource] = [vertexSource]
        if let normals, normals.count == vertices.count {
            let normalData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
            sources.append(SCNGeometrySource(
                data: normalData,
                semantic: .normal,
                vectorCount: normals.count,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<SIMD3<Float>>.stride
            ))
        }

        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        return SCNGeometry(sources: sources, elements: [element])
    }

    static func makeLineGeometry(vertices: [SIMD3<Float>],
                                 indices: [UInt32]) -> SCNGeometry {
        let vertexData = vertices.withUnsafeBufferPointer { Data(buffer: $0) }
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .line,
            primitiveCount: indices.count / 2,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        return SCNGeometry(sources: [vertexSource], elements: [element])
    }

    static func makePointGeometry(vertices: [SIMD3<Float>]) -> SCNGeometry {
        let vertexData = vertices.withUnsafeBufferPointer { Data(buffer: $0) }
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let indices: [UInt32] = (0..<UInt32(vertices.count)).map { $0 }
        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: vertices.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        element.pointSize = 2.0
        element.minimumPointScreenSpaceRadius = 1.0
        element.maximumPointScreenSpaceRadius = 5.0
        return SCNGeometry(sources: [vertexSource], elements: [element])
    }

    static func bounds(of vertices: [SIMD3<Float>]) -> (SIMD3<Float>, SIMD3<Float>) {
        guard !vertices.isEmpty else { return (.zero, .zero) }
        var mn = vertices[0], mx = vertices[0]
        for v in vertices {
            mn = simd_min(mn, v)
            mx = simd_max(mx, v)
        }
        return (mn, mx)
    }
}
