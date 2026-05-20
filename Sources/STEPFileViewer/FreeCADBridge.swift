import Foundation

/// Bridges to a locally-installed FreeCAD to tessellate STEP B-Rep geometry
/// into a triangle mesh. FreeCAD bundles OpenCASCADE, which is what actually
/// evaluates the parametric surfaces. When FreeCAD is not installed, callers
/// fall back to the wireframe preview.
enum FreeCADBridge {
    /// Known locations of the FreeCAD command-line executable.
    private static let candidatePaths = [
        "/Applications/FreeCAD.app/Contents/Resources/bin/freecadcmd",
        "/Applications/FreeCAD.app/Contents/MacOS/FreeCADCmd",
        "/opt/homebrew/bin/freecadcmd",
        "/usr/local/bin/freecadcmd",
    ]

    static func executableURL() -> URL? {
        let fm = FileManager.default
        for path in candidatePaths where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static var isAvailable: Bool { executableURL() != nil }

    /// Tessellate a STEP file into a temporary binary STL. The caller owns the
    /// returned file and is responsible for deleting it.
    static func tessellateToSTL(stepURL: URL) throws -> URL {
        guard let freecad = executableURL() else {
            throw ModelLoaderError.parseError("FreeCAD is not installed")
        }
        let tmp = FileManager.default.temporaryDirectory
        let token = UUID().uuidString
        let scriptURL = tmp.appendingPathComponent("sfv-\(token).py")
        let outURL = tmp.appendingPathComponent("sfv-\(token).stl")
        try conversionScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let task = Process()
        task.executableURL = freecad
        task.arguments = [scriptURL.path, stepURL.path, outURL.path]
        let errPipe = Pipe()
        task.standardError = errPipe
        task.standardOutput = Pipe()
        do {
            try task.run()
        } catch {
            throw ModelLoaderError.parseError("Could not launch FreeCAD: \(error.localizedDescription)")
        }
        task.waitUntilExit()

        guard task.terminationStatus == 0,
              FileManager.default.fileExists(atPath: outURL.path) else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            throw ModelLoaderError.parseError("FreeCAD could not tessellate the file. \(err.prefix(160))")
        }
        return outURL
    }

    /// Python run by `freecadcmd`. Reads a STEP file, meshes it with a
    /// deflection scaled to the model size, and writes a binary STL.
    private static let conversionScript = """
    import sys, Part, MeshPart
    src, dst = sys.argv[-2], sys.argv[-1]
    shape = Part.Shape()
    shape.read(src)
    diag = shape.BoundBox.DiagonalLength
    deflection = max(diag * 0.002, 1e-4)
    mesh = MeshPart.meshFromShape(Shape=shape,
                                  LinearDeflection=deflection,
                                  AngularDeflection=0.35,
                                  Relative=False)
    if mesh.CountFacets == 0:
        sys.exit(2)
    mesh.write(dst)
    """
}
