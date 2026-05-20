import Foundation
import SceneKit
import simd

/// STEP (ISO 10303-21) loader.
///
/// STEP stores B-Rep geometry (parametric curves + surfaces) that must be
/// tessellated into triangles before it can be shaded. When FreeCAD is
/// installed locally we shell out to it (FreeCAD bundles OpenCASCADE) to
/// produce a real solid mesh.
///
/// When FreeCAD is unavailable, `loadWireframe` is used instead — it extracts
/// only the parts of the file we can interpret directly:
///   • CARTESIAN_POINT entities — drawn as a point cloud
///   • VERTEX_POINT and EDGE_CURVE pairs — drawn as a straight-edge wireframe
enum STEPLoader {
    static func load(url: URL) throws -> ModelLoadResult {
        // Prefer a true tessellated solid via FreeCAD / OpenCASCADE.
        if FreeCADBridge.isAvailable {
            if let solid = try? tessellatedSolid(url: url) {
                return solid
            }
        }
        // Fall back to the structural wireframe + point-cloud preview.
        return try loadWireframe(url: url)
    }

    private static func tessellatedSolid(url: URL) throws -> ModelLoadResult {
        let stlURL = try FreeCADBridge.tessellateToSTL(stepURL: url)
        defer { try? FileManager.default.removeItem(at: stlURL) }
        return try STLLoader.load(url: stlURL)
    }

    static func loadWireframe(url: URL) throws -> ModelLoadResult {
        let text: String
        if let raw = try? String(contentsOf: url, encoding: .utf8) {
            text = raw
        } else if let raw = try? String(contentsOf: url, encoding: .isoLatin1) {
            text = raw
        } else {
            throw ModelLoaderError.parseError("STEP: file is not text-decodable")
        }

        guard text.contains("ISO-10303") || text.contains("HEADER") else {
            throw ModelLoaderError.parseError("STEP: not a valid ISO-10303-21 file")
        }

        let entities = STEPTokenizer.tokenize(text)
        if entities.isEmpty {
            throw ModelLoaderError.parseError("STEP: no entities found in DATA section")
        }

        var points: [Int: SIMD3<Float>] = [:]       // entity id -> point
        var vertexToPoint: [Int: Int] = [:]         // VERTEX_POINT id -> CARTESIAN_POINT id
        var edges: [(Int, Int)] = []                // pairs of CARTESIAN_POINT ids

        for ent in entities {
            switch ent.type {
            case "CARTESIAN_POINT":
                if let p = parseCartesianPoint(ent.params) {
                    points[ent.id] = p
                }
            case "VERTEX_POINT":
                if let ref = firstReference(ent.params) {
                    vertexToPoint[ent.id] = ref
                }
            case "EDGE_CURVE", "ORIENTED_EDGE":
                let refs = allReferences(ent.params)
                if refs.count >= 2 {
                    edges.append((refs[0], refs[1]))
                }
            case "LINE":
                let refs = allReferences(ent.params)
                if refs.count >= 1 {
                    // LINE references a point and a vector; we only draw it if we
                    // also have an explicit edge_curve consuming it. Skip here.
                    _ = refs
                }
            default:
                break
            }
        }

        guard !points.isEmpty else {
            throw ModelLoaderError.parseError("STEP: no CARTESIAN_POINT entities found")
        }

        // Resolve edges to point coordinate pairs.
        var lineVerts: [SIMD3<Float>] = []
        var lineIdx: [UInt32] = []
        for (a, b) in edges {
            let pa = points[a] ?? points[vertexToPoint[a] ?? -1]
            let pb = points[b] ?? points[vertexToPoint[b] ?? -1]
            guard let pa, let pb else { continue }
            let ia = UInt32(lineVerts.count); lineVerts.append(pa)
            let ib = UInt32(lineVerts.count); lineVerts.append(pb)
            lineIdx.append(ia); lineIdx.append(ib)
        }

        let allPoints = Array(points.values)
        let (bmin, bmax) = ModelLoader.bounds(of: allPoints)

        let scene = SCNScene()

        // Wireframe (if any edges)
        if !lineIdx.isEmpty {
            let lineGeom = ModelLoader.makeLineGeometry(vertices: lineVerts, indices: lineIdx)
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = NSColor(calibratedRed: 0.16, green: 0.40, blue: 0.80, alpha: 1.0)
            lineGeom.materials = [mat]
            scene.rootNode.addChildNode(SCNNode(geometry: lineGeom))
        }

        // Point cloud
        let ptGeom = ModelLoader.makePointGeometry(vertices: allPoints)
        let pmat = SCNMaterial()
        pmat.lightingModel = .constant
        pmat.diffuse.contents = NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1.0)
        ptGeom.materials = [pmat]
        scene.rootNode.addChildNode(SCNNode(geometry: ptGeom))

        let stats = ModelStatistics.make(
            triangles: 0,
            lines: lineIdx.count / 2,
            points: allPoints.count,
            vertices: allPoints.count,
            meshes: lineIdx.isEmpty ? 1 : 2,
            boundsMin: bmin,
            boundsMax: bmax
        )
        return ModelLoadResult(scene: scene, statistics: stats)
    }

    // MARK: - Parameter helpers

    /// Parse `('label', (x, y, z))` -> (x,y,z).
    private static func parseCartesianPoint(_ params: String) -> SIMD3<Float>? {
        guard let open = params.firstIndex(of: "(") else { return nil }
        let rest = params[params.index(after: open)...]
        // Look for the inner coordinate tuple — first '(' after we skip the label.
        guard let coordStart = rest.firstIndex(of: "(") else { return nil }
        let afterCoordStart = rest.index(after: coordStart)
        guard let coordEnd = rest[afterCoordStart...].firstIndex(of: ")") else { return nil }
        let coordStr = rest[afterCoordStart..<coordEnd]
        let nums = coordStr.split(separator: ",").compactMap {
            Float($0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n")))
        }
        guard nums.count >= 3 else { return nil }
        return SIMD3<Float>(nums[0], nums[1], nums[2])
    }

    /// Return the first `#N` reference in a parameter string.
    private static func firstReference(_ params: String) -> Int? {
        var i = params.startIndex
        while i < params.endIndex {
            if params[i] == "#" {
                let after = params.index(after: i)
                var j = after
                while j < params.endIndex, params[j].isNumber { j = params.index(after: j) }
                if j > after, let n = Int(params[after..<j]) { return n }
            }
            i = params.index(after: i)
        }
        return nil
    }

    /// Return all `#N` references in a parameter string, in order.
    private static func allReferences(_ params: String) -> [Int] {
        var refs: [Int] = []
        var i = params.startIndex
        while i < params.endIndex {
            if params[i] == "#" {
                let after = params.index(after: i)
                var j = after
                while j < params.endIndex, params[j].isNumber { j = params.index(after: j) }
                if j > after, let n = Int(params[after..<j]) { refs.append(n) }
                i = j
            } else {
                i = params.index(after: i)
            }
        }
        return refs
    }
}

// MARK: - Tokenizer

struct STEPEntity {
    let id: Int
    let type: String
    let params: String   // raw parameter string including outer parens
}

enum STEPTokenizer {
    /// Extract entity definitions from the DATA section. Handles multi-line
    /// entities, single-quoted strings (with '' escapes), and nested parens.
    static func tokenize(_ source: String) -> [STEPEntity] {
        guard let dataRange = source.range(of: "DATA;") else { return [] }
        let endRange = source.range(of: "ENDSEC;", range: dataRange.upperBound..<source.endIndex)
        let body = source[dataRange.upperBound..<(endRange?.lowerBound ?? source.endIndex)]

        var entities: [STEPEntity] = []
        let scalars = Array(body.unicodeScalars)
        var i = 0
        let n = scalars.count

        while i < n {
            // Skip whitespace
            while i < n, scalars[i].isWhitespaceOrNewline { i += 1 }
            // Skip comments /* ... */
            if i + 1 < n, scalars[i] == "/" && scalars[i+1] == "*" {
                i += 2
                while i + 1 < n, !(scalars[i] == "*" && scalars[i+1] == "/") { i += 1 }
                i = min(n, i + 2)
                continue
            }
            // Must start with '#'
            guard i < n, scalars[i] == "#" else {
                // skip until next semicolon or newline
                while i < n, scalars[i] != ";" { i += 1 }
                if i < n { i += 1 }
                continue
            }
            i += 1
            // Read entity id
            let idStart = i
            while i < n, scalars[i].isASCIIDigit { i += 1 }
            guard i > idStart, let entityId = Int(String(String.UnicodeScalarView(scalars[idStart..<i]))) else {
                while i < n, scalars[i] != ";" { i += 1 }
                if i < n { i += 1 }
                continue
            }
            // Skip whitespace, '='
            while i < n, scalars[i].isWhitespaceOrNewline { i += 1 }
            guard i < n, scalars[i] == "=" else {
                while i < n, scalars[i] != ";" { i += 1 }
                if i < n { i += 1 }
                continue
            }
            i += 1
            while i < n, scalars[i].isWhitespaceOrNewline { i += 1 }

            // Read entity type (uppercase letters, digits, underscore)
            let typeStart = i
            while i < n, isTypeChar(scalars[i]) { i += 1 }
            guard i > typeStart else {
                while i < n, scalars[i] != ";" { i += 1 }
                if i < n { i += 1 }
                continue
            }
            let typeName = String(String.UnicodeScalarView(scalars[typeStart..<i]))

            // Skip whitespace
            while i < n, scalars[i].isWhitespaceOrNewline { i += 1 }

            // Read balanced parens for parameter list
            guard i < n, scalars[i] == "(" else {
                while i < n, scalars[i] != ";" { i += 1 }
                if i < n { i += 1 }
                continue
            }
            let paramStart = i
            var depth = 0
            var inString = false
            while i < n {
                let c = scalars[i]
                if inString {
                    if c == "'" {
                        // Check escape ''
                        if i + 1 < n && scalars[i+1] == "'" {
                            i += 2
                            continue
                        } else {
                            inString = false
                        }
                    }
                } else {
                    if c == "'" { inString = true }
                    else if c == "(" { depth += 1 }
                    else if c == ")" {
                        depth -= 1
                        if depth == 0 { i += 1; break }
                    }
                }
                i += 1
            }
            let params = String(String.UnicodeScalarView(scalars[paramStart..<i]))

            // Consume up to ';'
            while i < n, scalars[i] != ";" { i += 1 }
            if i < n { i += 1 }

            // Some STEP files declare complex entities as a sequence of subtype params,
            // e.g. #5=(BOUNDED_CURVE() B_SPLINE_CURVE(...) ...). We skip these for now
            // — they have no leading type name.
            if !typeName.isEmpty {
                entities.append(STEPEntity(id: entityId, type: typeName, params: params))
            }
        }
        return entities
    }

    private static func isTypeChar(_ c: Unicode.Scalar) -> Bool {
        return (c >= "A" && c <= "Z")
            || (c >= "a" && c <= "z")
            || (c >= "0" && c <= "9")
            || c == "_"
    }
}

private extension Unicode.Scalar {
    var isWhitespaceOrNewline: Bool {
        return self == " " || self == "\t" || self == "\n" || self == "\r"
    }
    var isASCIIDigit: Bool {
        return self >= "0" && self <= "9"
    }
}
