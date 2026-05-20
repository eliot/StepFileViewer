import Foundation
import SceneKit
import simd

enum STLLoader {
    static func load(url: URL) throws -> ModelLoadResult {
        let data = try Data(contentsOf: url)
        guard data.count >= 84 else {
            throw ModelLoaderError.parseError("STL file too small")
        }

        // Determine binary vs ASCII. Some binary STLs also start with "solid",
        // so we verify the byte layout: 80 byte header + UInt32 triangle count + 50 * N
        let isBinary = isProbablyBinarySTL(data)

        let vertices: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let indices: [UInt32]
        if isBinary {
            (vertices, normals, indices) = try parseBinary(data)
        } else {
            (vertices, normals, indices) = try parseASCII(data)
        }

        guard !vertices.isEmpty, !indices.isEmpty else {
            throw ModelLoaderError.empty
        }

        let geometry = ModelLoader.makeTriangleGeometry(
            vertices: vertices,
            normals: normals,
            indices: indices
        )
        let node = SCNNode(geometry: geometry)
        let scene = SCNScene()
        scene.rootNode.addChildNode(node)
        ModelLoader.applyDefaultMaterial(to: scene)

        let (bmin, bmax) = ModelLoader.bounds(of: vertices)
        let stats = ModelStatistics.make(
            triangles: indices.count / 3,
            vertices: vertices.count,
            meshes: 1,
            boundsMin: bmin,
            boundsMax: bmax
        )
        return ModelLoadResult(scene: scene, statistics: stats)
    }

    private static func isProbablyBinarySTL(_ data: Data) -> Bool {
        guard data.count >= 84 else { return false }
        // Read triangle count from offset 80 (little-endian UInt32)
        let triCount = data.withUnsafeBytes { raw -> UInt32 in
            let p = raw.baseAddress!.advanced(by: 80)
            return p.loadUnaligned(as: UInt32.self).littleEndian
        }
        let expectedSize = 84 + Int(triCount) * 50
        if expectedSize == data.count { return true }
        // Tiebreaker: if file starts with "solid " and contains "facet", it's ASCII.
        let head = String(data: data.prefix(256), encoding: .ascii)?.lowercased() ?? ""
        if head.hasPrefix("solid") && head.contains("facet") {
            return false
        }
        return expectedSize == data.count
    }

    private static func parseBinary(_ data: Data) throws -> ([SIMD3<Float>], [SIMD3<Float>], [UInt32]) {
        let triCount = data.withUnsafeBytes { raw -> UInt32 in
            let p = raw.baseAddress!.advanced(by: 80)
            return p.loadUnaligned(as: UInt32.self).littleEndian
        }
        let expected = 84 + Int(triCount) * 50
        guard expected <= data.count else {
            throw ModelLoaderError.parseError("STL truncated: expected \(expected), got \(data.count)")
        }

        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        vertices.reserveCapacity(Int(triCount) * 3)
        normals.reserveCapacity(Int(triCount) * 3)
        indices.reserveCapacity(Int(triCount) * 3)

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 84
            for _ in 0..<triCount {
                let nx = raw.loadUnaligned(fromByteOffset: offset, as: Float.self)
                let ny = raw.loadUnaligned(fromByteOffset: offset + 4, as: Float.self)
                let nz = raw.loadUnaligned(fromByteOffset: offset + 8, as: Float.self)
                let n = SIMD3<Float>(nx, ny, nz)
                offset += 12

                for _ in 0..<3 {
                    let x = raw.loadUnaligned(fromByteOffset: offset, as: Float.self)
                    let y = raw.loadUnaligned(fromByteOffset: offset + 4, as: Float.self)
                    let z = raw.loadUnaligned(fromByteOffset: offset + 8, as: Float.self)
                    offset += 12
                    let idx = UInt32(vertices.count)
                    vertices.append(SIMD3<Float>(x, y, z))
                    normals.append(n)
                    indices.append(idx)
                }
                offset += 2 // attribute byte count
            }
        }
        return (vertices, normals, indices)
    }

    private static func parseASCII(_ data: Data) throws -> ([SIMD3<Float>], [SIMD3<Float>], [UInt32]) {
        guard let text = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8) else {
            throw ModelLoaderError.parseError("STL: cannot decode as text")
        }
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        var currentNormal = SIMD3<Float>(0, 0, 0)
        var triVertCount = 0

        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("facet normal") {
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 5,
                   let nx = Float(parts[2]),
                   let ny = Float(parts[3]),
                   let nz = Float(parts[4]) {
                    currentNormal = SIMD3<Float>(nx, ny, nz)
                }
                triVertCount = 0
            } else if trimmed.hasPrefix("vertex") {
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 4,
                   let x = Float(parts[1]),
                   let y = Float(parts[2]),
                   let z = Float(parts[3]) {
                    let idx = UInt32(vertices.count)
                    vertices.append(SIMD3<Float>(x, y, z))
                    normals.append(currentNormal)
                    indices.append(idx)
                    triVertCount += 1
                }
            }
        }
        return (vertices, normals, indices)
    }
}
