import Foundation

// Standalone test runner. Compiled with the same loader sources.
@main
struct LoaderTests {
    static func main() {
        var failures = 0
        failures += run("Binary STL cube", { try testBinarySTL() })
        failures += run("ASCII STL", { try testASCIISTL() })
        failures += run("STEP parser tokenize", { try testSTEPTokenize() })
        failures += run("STEP file end-to-end", { try testSTEPFull() })
        failures += run("STEP solid via FreeCAD", { try testSTEPSolid() })
        failures += run("3MF quad", { try test3MFQuad() })
        failures += run("OBJ via ModelIO", { try testOBJ() })
        if failures > 0 {
            FileHandle.standardError.write("FAILED \(failures) tests\n".data(using: .utf8)!)
            exit(1)
        }
        print("All tests passed.")
    }

    static func run(_ name: String, _ body: () throws -> Void) -> Int {
        do {
            try body()
            print("  ok   \(name)")
            return 0
        } catch {
            print("  FAIL \(name): \(error)")
            return 1
        }
    }

    static func testBinarySTL() throws {
        let url = URL(fileURLWithPath: "/tmp/cube.stl")
        let r = try ModelLoader.load(url: url)
        try expect(r.statistics.triangles == 12, "expected 12 tris, got \(r.statistics.triangles)")
        try expect(r.statistics.vertices == 36, "expected 36 verts, got \(r.statistics.vertices)")
        let sx = r.statistics.sizeX
        try expect(abs(sx - 1.0) < 0.001, "expected sizeX≈1, got \(sx)")
    }

    static func testASCIISTL() throws {
        let url = URL(fileURLWithPath: "/tmp/cube_ascii.stl")
        let r = try ModelLoader.load(url: url)
        try expect(r.statistics.triangles == 2, "expected 2 tris, got \(r.statistics.triangles)")
        try expect(r.statistics.vertices == 6, "expected 6 verts, got \(r.statistics.vertices)")
    }

    static func testSTEPTokenize() throws {
        let src = """
        ISO-10303-21;
        HEADER;
        FILE_DESCRIPTION(('test'),'1');
        ENDSEC;
        DATA;
        #1 = CARTESIAN_POINT('p1', (0.0, 0.0, 0.0));
        #2 = CARTESIAN_POINT('p2', (1.0, 0.0, 0.0));
        #3 = CARTESIAN_POINT('p3', (0.0, 1.0, 0.0));
        #4 = VERTEX_POINT('', #1);
        #5 = VERTEX_POINT('', #2);
        #6 = EDGE_CURVE('', #4, #5, #99, .T.);
        ENDSEC;
        END-ISO-10303-21;
        """
        let ents = STEPTokenizer.tokenize(src)
        try expect(ents.count == 6, "expected 6 entities, got \(ents.count): \(ents.map { $0.type })")
        let types = Set(ents.map { $0.type })
        try expect(types.contains("CARTESIAN_POINT"), "missing CARTESIAN_POINT")
        try expect(types.contains("EDGE_CURVE"), "missing EDGE_CURVE")
    }

    static func testSTEPFull() throws {
        let r = try ModelLoader.load(url: URL(fileURLWithPath: "/tmp/tiny.step"))
        try expect(r.statistics.points == 4, "expected 4 points, got \(r.statistics.points)")
        try expect(r.statistics.lines == 4, "expected 4 edges, got \(r.statistics.lines)")
    }

    static func testSTEPSolid() throws {
        // /tmp/block.step is a real B-Rep solid (box with a cylindrical hole).
        // With FreeCAD installed it must come back as a tessellated mesh.
        let r = try ModelLoader.load(url: URL(fileURLWithPath: "/tmp/block.step"))
        try expect(r.statistics.triangles > 50,
                   "expected a tessellated solid (>50 tris), got \(r.statistics.triangles)")
        try expect(r.statistics.points == 0,
                   "solid path should not emit a point cloud, got \(r.statistics.points)")
    }

    static func testOBJ() throws {
        let r = try ModelLoader.load(url: URL(fileURLWithPath: "/tmp/tri.obj"))
        try expect(r.statistics.triangles >= 1, "expected ≥1 triangle, got \(r.statistics.triangles)")
        try expect(r.statistics.vertices >= 3, "expected ≥3 vertices, got \(r.statistics.vertices)")
    }

    static func test3MFQuad() throws {
        let r = try ModelLoader.load(url: URL(fileURLWithPath: "/tmp/quad.3mf"))
        try expect(r.statistics.triangles == 2, "expected 2 tris, got \(r.statistics.triangles)")
        try expect(r.statistics.vertices == 4, "expected 4 verts, got \(r.statistics.vertices)")
        // The model is a 10×10 quad in the XY plane.
        try expect(abs(r.statistics.sizeX - 10) < 0.01, "sizeX expected 10, got \(r.statistics.sizeX)")
        try expect(abs(r.statistics.sizeY - 10) < 0.01, "sizeY expected 10, got \(r.statistics.sizeY)")
    }
}

struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ msg: String) { self.description = msg }
}

func expect(_ cond: Bool, _ msg: @autoclosure () -> String) throws {
    if !cond { throw TestError(msg()) }
}
