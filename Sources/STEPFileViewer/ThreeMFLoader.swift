import Foundation
import SceneKit
import simd

/// Minimal 3MF (3D Manufacturing Format) loader.
/// A 3MF file is a ZIP archive; the geometry lives in an XML part — usually
/// `3D/3dmodel.model`. We extract that part via the system `unzip` tool and
/// parse it with Foundation's XMLParser.
enum ThreeMFLoader {
    static func load(url: URL) throws -> ModelLoadResult {
        let xmlData = try extractModelXML(from: url)
        let parser = ThreeMFXMLParser()
        let (objects, build) = try parser.parse(data: xmlData)

        // Build a scene with one node per build item (applying its transform).
        let scene = SCNScene()
        var totalTris = 0
        var totalVerts = 0
        var totalMeshes = 0
        var bbMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var bbMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var anyGeometry = false

        let buildItems = build.isEmpty
            ? objects.keys.map { ThreeMFBuildItem(objectId: $0, transform: matrix_identity_float4x4) }
            : build

        for item in buildItems {
            guard let obj = objects[item.objectId] else { continue }
            for (verts, tris) in flattenObject(id: item.objectId, objects: objects, transform: item.transform, accumulated: []) {
                _ = obj
                if verts.isEmpty || tris.isEmpty { continue }
                anyGeometry = true
                let indices: [UInt32] = tris.flatMap { [$0.0, $0.1, $0.2] }
                let geom = ModelLoader.makeTriangleGeometry(
                    vertices: verts,
                    normals: nil,
                    indices: indices
                )
                let node = SCNNode(geometry: geom)
                scene.rootNode.addChildNode(node)
                totalTris += tris.count
                totalVerts += verts.count
                totalMeshes += 1
                for v in verts {
                    bbMin = simd_min(bbMin, v)
                    bbMax = simd_max(bbMax, v)
                }
            }
        }

        if !anyGeometry {
            throw ModelLoaderError.empty
        }

        ModelLoader.applyDefaultMaterial(to: scene)
        let stats = ModelStatistics.make(
            triangles: totalTris,
            vertices: totalVerts,
            meshes: totalMeshes,
            boundsMin: bbMin,
            boundsMax: bbMax
        )
        return ModelLoadResult(scene: scene, statistics: stats)
    }

    /// Flatten an object (mesh or assembly of components) into a list of
    /// (vertices, triangles) tuples in world coordinates.
    private static func flattenObject(
        id: Int,
        objects: [Int: ThreeMFObject],
        transform: simd_float4x4,
        accumulated: [Int]
    ) -> [([SIMD3<Float>], [(UInt32, UInt32, UInt32)])] {
        guard !accumulated.contains(id), let obj = objects[id] else { return [] }
        var results: [([SIMD3<Float>], [(UInt32, UInt32, UInt32)])] = []

        if !obj.vertices.isEmpty && !obj.triangles.isEmpty {
            let xformed = obj.vertices.map { applyTransform(transform, to: $0) }
            results.append((xformed, obj.triangles))
        }
        for comp in obj.components {
            let combined = transform * comp.transform
            results.append(contentsOf: flattenObject(
                id: comp.objectId,
                objects: objects,
                transform: combined,
                accumulated: accumulated + [id]
            ))
        }
        return results
    }

    private static func applyTransform(_ m: simd_float4x4, to v: SIMD3<Float>) -> SIMD3<Float> {
        let v4 = SIMD4<Float>(v.x, v.y, v.z, 1)
        let r = m * v4
        return SIMD3<Float>(r.x, r.y, r.z)
    }

    // MARK: – ZIP extraction (via /usr/bin/unzip)

    private static func extractModelXML(from url: URL) throws -> Data {
        let candidates = ["3D/3dmodel.model", "3d/3dmodel.model"]
        for name in candidates {
            if let data = try? runUnzip(archive: url, member: name) {
                return data
            }
        }
        // Fall back: list contents and find first *.model file
        if let list = try? runUnzipList(archive: url) {
            if let modelEntry = list.first(where: { $0.hasSuffix(".model") }) {
                return try runUnzip(archive: url, member: modelEntry)
            }
        }
        throw ModelLoaderError.parseError("3MF: could not locate model part inside archive")
    }

    private static func runUnzip(archive: URL, member: String) throws -> Data {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-p", archive.path, member]
        let pipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errPipe
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if task.terminationStatus != 0 || data.isEmpty {
            throw ModelLoaderError.parseError("unzip failed for \(member)")
        }
        return data
    }

    private static func runUnzipList(archive: URL) throws -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-Z1", archive.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map { String($0) }
    }
}

// MARK: - Data structures

struct ThreeMFObject {
    var vertices: [SIMD3<Float>] = []
    var triangles: [(UInt32, UInt32, UInt32)] = []
    var components: [ThreeMFComponent] = []
}

struct ThreeMFComponent {
    var objectId: Int
    var transform: simd_float4x4
}

struct ThreeMFBuildItem {
    var objectId: Int
    var transform: simd_float4x4
}

// MARK: - XML parser

private final class ThreeMFXMLParser: NSObject, XMLParserDelegate {
    private var objects: [Int: ThreeMFObject] = [:]
    private var buildItems: [ThreeMFBuildItem] = []

    private var currentObjectId: Int?
    private var currentObject: ThreeMFObject?
    private var insideMesh = false
    private var parseError: Error?

    func parse(data: Data) throws -> ([Int: ThreeMFObject], [ThreeMFBuildItem]) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        if !parser.parse() {
            if let err = parser.parserError {
                throw ModelLoaderError.parseError("3MF XML: \(err.localizedDescription)")
            }
        }
        if let e = parseError { throw e }
        return (objects, buildItems)
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        switch name {
        case "object":
            if let idStr = attributeDict["id"], let id = Int(idStr) {
                currentObjectId = id
                currentObject = ThreeMFObject()
            }
        case "mesh":
            insideMesh = true
        case "vertex":
            if insideMesh,
               let xs = attributeDict["x"], let ys = attributeDict["y"], let zs = attributeDict["z"],
               let x = Float(xs), let y = Float(ys), let z = Float(zs) {
                currentObject?.vertices.append(SIMD3<Float>(x, y, z))
            }
        case "triangle":
            if insideMesh,
               let v1s = attributeDict["v1"], let v2s = attributeDict["v2"], let v3s = attributeDict["v3"],
               let v1 = UInt32(v1s), let v2 = UInt32(v2s), let v3 = UInt32(v3s) {
                currentObject?.triangles.append((v1, v2, v3))
            }
        case "component":
            if let objStr = attributeDict["objectid"], let oid = Int(objStr) {
                let xform = parseTransform(attributeDict["transform"])
                currentObject?.components.append(ThreeMFComponent(objectId: oid, transform: xform))
            }
        case "item":
            if let objStr = attributeDict["objectid"], let oid = Int(objStr) {
                let xform = parseTransform(attributeDict["transform"])
                buildItems.append(ThreeMFBuildItem(objectId: oid, transform: xform))
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if name == "mesh" { insideMesh = false }
        if name == "object" {
            if let id = currentObjectId, let obj = currentObject {
                objects[id] = obj
            }
            currentObjectId = nil
            currentObject = nil
        }
    }

    /// 3MF transforms are row-major 4×3 matrices (12 floats), representing the
    /// upper rows of a 4×4 homogeneous transform with implicit [0,0,0,1] last column.
    private func parseTransform(_ str: String?) -> simd_float4x4 {
        guard let str else { return matrix_identity_float4x4 }
        let parts = str.split(separator: " ").compactMap { Float($0) }
        guard parts.count == 12 else { return matrix_identity_float4x4 }
        // Layout: m00 m01 m02 m10 m11 m12 m20 m21 m22 m30 m31 m32
        // simd_float4x4 is column-major; build columns.
        let c0 = SIMD4<Float>(parts[0], parts[1], parts[2], 0)
        let c1 = SIMD4<Float>(parts[3], parts[4], parts[5], 0)
        let c2 = SIMD4<Float>(parts[6], parts[7], parts[8], 0)
        let c3 = SIMD4<Float>(parts[9], parts[10], parts[11], 1)
        return simd_float4x4(columns: (c0, c1, c2, c3))
    }
}
