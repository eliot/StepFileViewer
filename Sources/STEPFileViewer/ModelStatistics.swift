import Foundation
import SceneKit
import ModelIO
import simd

struct ModelStatistics: Equatable {
    var triangles: Int = 0
    var quads: Int = 0
    var ngons: Int = 0          // faces with > 4 vertices
    var lines: Int = 0
    var points: Int = 0
    var vertices: Int = 0
    var meshes: Int = 0
    var boundsMin: SIMD3<Float> = .zero
    var boundsMax: SIMD3<Float> = .zero

    static let empty = ModelStatistics()

    var totalFaces: Int { triangles + quads + ngons }
    var hasGeometry: Bool { vertices > 0 || totalFaces > 0 || lines > 0 || points > 0 }

    var sizeX: Float { boundsMax.x - boundsMin.x }
    var sizeY: Float { boundsMax.y - boundsMin.y }
    var sizeZ: Float { boundsMax.z - boundsMin.z }
}

extension ModelStatistics {
    /// Accumulate statistics by inspecting an MDLAsset before SceneKit conversion.
    /// This is the only reliable way to distinguish quads from triangles, because
    /// SCNGeometry triangulates everything on import.
    static func compute(fromAsset asset: MDLAsset) -> ModelStatistics {
        var stats = ModelStatistics()
        var first = true
        var bbMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var bbMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        for i in 0..<asset.count {
            let obj = asset.object(at: i)
            walk(obj, stats: &stats, bbMin: &bbMin, bbMax: &bbMax, first: &first)
        }

        if !first {
            stats.boundsMin = bbMin
            stats.boundsMax = bbMax
        }
        return stats
    }

    private static func walk(_ obj: MDLObject,
                             stats: inout ModelStatistics,
                             bbMin: inout SIMD3<Float>,
                             bbMax: inout SIMD3<Float>,
                             first: inout Bool) {
        if let mesh = obj as? MDLMesh {
            stats.meshes += 1
            stats.vertices += mesh.vertexCount
            let bb = mesh.boundingBox
            let mn = SIMD3<Float>(bb.minBounds.x, bb.minBounds.y, bb.minBounds.z)
            let mx = SIMD3<Float>(bb.maxBounds.x, bb.maxBounds.y, bb.maxBounds.z)
            if first {
                bbMin = mn; bbMax = mx; first = false
            } else {
                bbMin = simd_min(bbMin, mn)
                bbMax = simd_max(bbMax, mx)
            }
            if let submeshes = mesh.submeshes as? [MDLSubmesh] {
                for sm in submeshes {
                    addSubmesh(sm, to: &stats)
                }
            }
        }
        for child in obj.children.objects {
            walk(child, stats: &stats, bbMin: &bbMin, bbMax: &bbMax, first: &first)
        }
    }

    private static func addSubmesh(_ sm: MDLSubmesh, to stats: inout ModelStatistics) {
        // indexCount / primitivesPerFace tells us the face count for the submesh.
        switch sm.geometryType {
        case .triangles:
            stats.triangles += sm.indexCount / 3
        case .quads:
            stats.quads += sm.indexCount / 4
        case .lines:
            stats.lines += sm.indexCount / 2
        case .points:
            stats.points += sm.indexCount
        case .triangleStrips:
            // N strip indices -> N-2 triangles
            stats.triangles += max(0, sm.indexCount - 2)
        case .variableTopology:
            stats.ngons += 1  // best-effort; per-face counts not directly exposed
        @unknown default:
            stats.triangles += sm.indexCount / 3
        }
    }

    /// Build statistics directly when a loader has authoritative counts (e.g. STL, 3MF, STEP).
    static func make(triangles: Int,
                     quads: Int = 0,
                     ngons: Int = 0,
                     lines: Int = 0,
                     points: Int = 0,
                     vertices: Int,
                     meshes: Int = 1,
                     boundsMin: SIMD3<Float>,
                     boundsMax: SIMD3<Float>) -> ModelStatistics {
        var s = ModelStatistics()
        s.triangles = triangles
        s.quads = quads
        s.ngons = ngons
        s.lines = lines
        s.points = points
        s.vertices = vertices
        s.meshes = meshes
        s.boundsMin = boundsMin
        s.boundsMax = boundsMax
        return s
    }
}
