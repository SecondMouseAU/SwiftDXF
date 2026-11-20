import Foundation
import Testing

@testable import SwiftDXF

/// SOLID, 3DFACE and WIPEOUT.
///
/// The reference values come from `ezdxf` reading `Fixtures/solids.dxf` (`tools/solid_fixtures.py`):
/// `Solid.vertices()` after `upright`, the stored corners of a 3DFACE, and `boundary_path_wcs()`.
@Suite("SOLID, 3DFACE and WIPEOUT")
struct SolidTests {

    static func fixture() throws -> DXF.Drawing {
        let url = try #require(
            Bundle.module.url(
                forResource: "solids", withExtension: "dxf", subdirectory: "Fixtures"))
        return try DXF.read(contentsOf: url)
    }

    static func solids(_ dwg: DXF.Drawing) -> [DXF.Solid] {
        dwg.entities.compactMap { if case .solid(let s) = $0 { return s } else { return nil } }
    }

    static func faces(_ dwg: DXF.Drawing) -> [DXF.Face3D] {
        dwg.entities.compactMap { if case .face3D(let f) = $0 { return f } else { return nil } }
    }

    static func wipeouts(_ dwg: DXF.Drawing) -> [DXF.Wipeout] {
        dwg.entities.compactMap { if case .wipeout(let w) = $0 { return w } else { return nil } }
    }

    static func read(_ records: [String]) throws -> DXF.Drawing {
        try DXF.read(text: RawDXF.entities(records))
    }

    /// `corners` as points, to compare with the reference values.
    static func points(_ values: [[Double]]) -> [DXF.Point] {
        values.map { DXF.Point($0[0], $0[1], $0[2]) }
    }

    static func expectEqual(
        _ a: [DXF.Point], _ b: [DXF.Point], accuracy: Double = 1e-9,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(a.count == b.count, sourceLocation: sourceLocation)
        for (p, q) in zip(a, b) {
            #expect(
                abs(p.x - q.x) < accuracy && abs(p.y - q.y) < accuracy && abs(p.z - q.z) < accuracy,
                "\(p) is not \(q)", sourceLocation: sourceLocation)
        }
    }

    // MARK: Nothing is skipped

    @Test("none of the four types is skipped, and each is counted")
    func counted() throws {
        let dwg = try Self.fixture()
        #expect(dwg.skipped.isEmpty && dwg.skippedByLayer.isEmpty)
        #expect(dwg.counts.solid == 5 && dwg.counts.face3D == 2 && dwg.counts.wipeout == 3)
        #expect(dwg.counts.tolerance == 4 && dwg.counts.total == dwg.entities.count)
        #expect(dwg.entities.count == 14)
    }

    // MARK: SOLID

    @Test("a triangle has three corners, and the file's repeated third corner is dropped")
    func solidTriangle() throws {
        let solid = try #require(Self.solids(try Self.fixture()).first)
        #expect(solid.isTriangle)
        // ezdxf: Solid.vertices() is [(0, 0), (4, 0), (2, 3)].
        #expect(solid.corners == Self.points([[0, 0, 0], [4, 0, 0], [2, 3, 0]]))
        #expect(solid.layer == "FILL" && solid.color == 1)
    }

    @Test("a quadrilateral is in outline order: the file's third and fourth corners are swapped")
    func solidQuadrilateral() throws {
        let solids = Self.solids(try Self.fixture())
        // The file lists (0, 0), (5, 0), (1, 4), (6, 4): walking the outline gives
        // (0, 0), (5, 0), (6, 4), (1, 4), as ezdxf's Solid.vertices() does.
        #expect(solids[1].corners == Self.points([[0, 0, 0], [5, 0, 0], [6, 4, 0], [1, 4, 0]]))
        #expect(!solids[1].isTriangle && solids[1].layer == "FILL" && solids[1].color == 256)
        // The signed area of that walk is the parallelogram's, 5 x 4 = 20, counter-clockwise.
        let c = solids[1].corners
        var area = 0.0
        for i in 0..<c.count {
            let j = (i + 1) % c.count
            area += c[i].x * c[j].y - c[j].x * c[i].y
        }
        #expect(abs(area / 2 - 20) < 1e-12)
    }

    @Test("a SOLID keeps its z")
    func solidElevation() throws {
        let solid = Self.solids(try Self.fixture())[2]
        #expect(
            solid.corners
                == Self.points([[10, 0, 2.5], [14, 0, 2.5], [14, 2, 2.5], [10, 2, 2.5]]))
    }

    @Test("a SOLID on a -z plane is read as its world geometry, as ezdxf's upright reads it")
    func solidFlipped() throws {
        let dwg = try Self.fixture()
        // upright: (x, y, z) becomes (-x, y, -z), and the outline order is kept.
        let flipped = Self.solids(dwg)[3].corners
        Self.expectEqual(
            flipped, Self.points([[-1, 1, -2.5], [-3, 1, -2.5], [-3, 2, -2.5], [-1, 2, -2.5]]))
        #expect(flipped.allSatisfy { $0.z == -2.5 })
        // A tilted plane is read as written, and reported, as for the other entities in an OCS.
        #expect(
            Self.solids(dwg)[4].corners
                == Self.points([[0, 0, 0], [2, 0, 0], [2, 2, 0], [0, 2, 0]]))
        #expect(dwg.warnings == [.extrusionNotApplied(type: "SOLID", count: 1)])
    }

    @Test("a record with no fourth corner is a triangle")
    func solidWithoutFourthCorner() throws {
        let dwg = try Self.read([
            RawDXF.record(
                "SOLID", (8, "0"), (10, "0"), (20, "0"), (30, "0"), (11, "1"), (21, "0"),
                (31, "0"), (12, "0"), (22, "1"), (32, "0"))
        ])
        let solid = try #require(Self.solids(dwg).first)
        #expect(solid.isTriangle)
        #expect(solid.corners == Self.points([[0, 0, 0], [1, 0, 0], [0, 1, 0]]))
    }

    @Test("a quadrilateral whose fourth corner is the third is a triangle")
    func solidWithRepeatedCorner() throws {
        let dwg = try Self.read([
            RawDXF.record(
                "SOLID", (10, "0"), (20, "0"), (30, "0"), (11, "3"), (21, "0"), (31, "0"),
                (12, "0"), (22, "3"), (32, "0"), (13, "0"), (23, "3"), (33, "0"))
        ])
        #expect(Self.solids(dwg).first?.corners.count == 3)
    }

    // MARK: 3DFACE

    @Test("a 3DFACE has four corners in file order, its z, and its invisible edges")
    func face() throws {
        let faces = Self.faces(try Self.fixture())
        #expect(faces[0].corners == Self.points([[0, 0, 0], [1, 0, 1], [1, 1, 2], [0, 1, 1]]))
        #expect(!faces[0].isTriangle && faces[0].invisibleEdges == 5)
        // ezdxf: get_edges_visibility() is [False, True, False, True].
        #expect((0..<4).map(faces[0].isEdgeVisible) == [false, true, false, true])
        #expect(!faces[0].isEdgeVisible(4) && !faces[0].isEdgeVisible(-1))
    }

    @Test("a triangular 3DFACE repeats its third corner")
    func triangularFace() throws {
        let face = Self.faces(try Self.fixture())[1]
        #expect(face.isTriangle && face.invisibleEdges == 0)
        #expect(face.corners == Self.points([[5, 5, 1], [6, 5, 1], [5.5, 6, 3], [5.5, 6, 3]]))
        #expect((0..<4).allSatisfy(face.isEdgeVisible))
    }

    @Test(
        "a 3DFACE is not read through an extrusion, and a record with no fourth corner is a triangle"
    )
    func faceInTheWorld() throws {
        let dwg = try Self.read([
            RawDXF.record(
                "3DFACE", (10, "1"), (20, "2"), (30, "3"), (11, "4"), (21, "5"), (31, "6"),
                (12, "7"), (22, "8"), (32, "9"), (210, "0"), (220, "0"), (230, "-1"))
        ])
        let face = try #require(Self.faces(dwg).first)
        #expect(face.corners.count == 4 && face.isTriangle)
        #expect(face.corners[0] == DXF.Point(1, 2, 3) && face.corners[2] == DXF.Point(7, 8, 9))
        #expect(dwg.warnings.isEmpty)
    }

    // MARK: WIPEOUT

    @Test("a polygonal WIPEOUT is its clip boundary in the world, without the closing vertex")
    func wipeoutPolygon() throws {
        Self.expectEqual(
            Self.wipeouts(try Self.fixture())[0].boundary,
            Self.points([[10, 10, 0], [20, 10, 0], [20, 15, 0], [15, 20, 0], [10, 15, 0]]))
    }

    @Test("a rectangular WIPEOUT, two opposite corners in the file, is four corners")
    func wipeoutRectangle() throws {
        Self.expectEqual(
            Self.wipeouts(try Self.fixture())[1].boundary,
            Self.points([[0, 0, 0], [8, 0, 0], [8, 6, 0], [0, 6, 0]]))
    }

    @Test("a WIPEOUT on a rotated, scaled grid of pixels is placed as ezdxf places it")
    func wipeoutRotatedGrid() throws {
        // ezdxf: boundary_path_wcs() of a 200 x 100 pixel grid of 0.1, turned by 30 degrees.
        Self.expectEqual(
            Self.wipeouts(try Self.fixture())[2].boundary,
            Self.points([
                [5.000000000000001, 28.66025403784439, 1.0],
                [14.22855530803361, 32.77592736387073, 1.0],
                [22.058682326955804, 29.213749537379655, 1.0],
                [11.300352077758099, 21.847724133595214, 1.0],
            ]))
    }

    /// A WIPEOUT record with the given clip, in the layout AutoCAD writes it.
    static func wipeoutRecord(
        insertion: (Double, Double) = (0, 0), u: (Double, Double) = (1, 0),
        v: (Double, Double) = (0, 1), size: (Double, Double) = (1, 1),
        clip: [(Double, Double)]
    ) -> String {
        var tags: [(Int, String)] = [
            (8, "0"), (10, "\(insertion.0)"), (20, "\(insertion.1)"), (30, "0"),
            (11, "\(u.0)"), (21, "\(u.1)"), (31, "0"), (12, "\(v.0)"), (22, "\(v.1)"),
            (32, "0"), (13, "\(size.0)"), (23, "\(size.1)"), (91, "\(clip.count)"),
        ]
        for point in clip { tags += [(14, "\(point.0)"), (24, "\(point.1)")] }
        return RawDXF.record("WIPEOUT", tags)
    }

    @Test("a polygon is the same open or closed, and two points are a rectangle")
    func wipeoutClosure() throws {
        let rectangle = try Self.read([
            Self.wipeoutRecord(insertion: (2, 3), clip: [(-0.5, -0.5), (0.5, 0.5)])
        ])
        #expect(
            Self.wipeouts(rectangle).first?.boundary == [
                DXF.Point(2, 4, 0), DXF.Point(3, 4, 0), DXF.Point(3, 3, 0), DXF.Point(2, 3, 0),
            ])
        let open = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5)]
        let closed = open + [(-0.5, -0.5)]
        let a = try Self.read([Self.wipeoutRecord(insertion: (2, 3), clip: open)])
        let b = try Self.read([Self.wipeoutRecord(insertion: (2, 3), clip: closed)])
        #expect(Self.wipeouts(a).first?.boundary == Self.wipeouts(b).first?.boundary)
        #expect(Self.wipeouts(a).first?.boundary.count == 3)
        // The pixel at the top left of a 1 x 1 image is at the top left of its square.
        #expect(
            Self.wipeouts(a).first?.boundary
                == [DXF.Point(2, 4, 0), DXF.Point(3, 4, 0), DXF.Point(3, 3, 0)])
    }

    @Test("a WIPEOUT with no usable clip is its whole image")
    func wipeoutWithoutClip() throws {
        let dwg = try Self.read([
            Self.wipeoutRecord(insertion: (1, 1), u: (0.5, 0), v: (0, 0.5), size: (10, 4), clip: [])
        ])
        // Pixels (-0.5, -0.5) to (9.5, 3.5): the image is 10 x 4 pixels of 0.5, from (1, 1).
        #expect(
            Self.wipeouts(dwg).first?.boundary == [
                DXF.Point(1, 3, 0), DXF.Point(6, 3, 0), DXF.Point(6, 1, 0), DXF.Point(1, 1, 0),
            ])
    }

    // MARK: Entities around them

    @Test("the extent takes in every corner, boundary vertex and insertion point")
    func bounds() throws {
        let dwg = try Self.read([
            RawDXF.record(
                "SOLID", (10, "0"), (20, "0"), (30, "0"), (11, "4"), (21, "0"), (31, "0"),
                (12, "0"), (22, "5"), (32, "0"), (13, "4"), (23, "5"), (33, "0")),
            RawDXF.record(
                "3DFACE", (10, "0"), (20, "0"), (30, "-2"), (11, "1"), (21, "0"), (31, "0"),
                (12, "1"), (22, "1"), (32, "7"), (13, "0"), (23, "1"), (33, "0")),
            Self.wipeoutRecord(
                insertion: (-3, 0), u: (2, 0), v: (0, 2), clip: [(-0.5, -0.5), (0.5, 0.5)]),
            RawDXF.record("TOLERANCE", (10, "9"), (20, "-6"), (30, "0"), (1, "{\\Fgdt;c}%%v0.1")),
        ])
        let b = try #require(dwg.bounds)
        #expect(b.min == DXF.Point(-3, -6, -2) && b.max == DXF.Point(9, 5, 7))
    }

    @Test("the contour layer reads none of them as an outline, and says it ignored them")
    func contoursIgnoreThem() throws {
        let dwg = try Self.fixture()
        let result = dwg.contours()
        #expect(result.shapes.isEmpty && result.openChains.isEmpty)
        let ignored = result.warnings.compactMap { warning -> String? in
            if case .ignoredEntities(let type, let count) = warning { return "\(type) \(count)" }
            return nil
        }
        #expect(ignored == ["3DFACE 2", "SOLID 5", "TOLERANCE 4", "WIPEOUT 3"])
        #expect(
            DXF.Contour.Warning.ignoredEntities(type: "SOLID", count: 2).description
                == "2 SOLID entities ignored")
        #expect(
            !result.warnings.contains {
                if case .skippedEntities = $0 { return true } else { return false }
            })
    }

    @Test("a layer filter leaves out the ignored entities of other layers")
    func contoursFilterLayers() throws {
        let result = try Self.fixture().contours(.init(layers: ["FILL"]))
        let ignored = result.warnings.filter {
            if case .ignoredEntities = $0 { return true } else { return false }
        }
        #expect(ignored == [.ignoredEntities(type: "SOLID", count: 2)])
    }

    // MARK: Blocks

    static func solidRecord(_ corners: [(Double, Double)], layer: String = "0") -> DXFBuilder.Record
    {
        var r: DXFBuilder.Record = [(0, "SOLID"), (8, layer)]
        for (i, c) in corners.enumerated() {
            r += [(10 + i, "\(c.0)"), (20 + i, "\(c.1)"), (30 + i, "0.0")]
        }
        return r
    }

    @Test("a block expansion carries them through the reference")
    func expansion() throws {
        var b = DXFBuilder()
        b.blocks = [
            (
                "FILLS", (0, 0),
                [
                    Self.solidRecord([(0, 0), (1, 0), (0, 1), (1, 1)], layer: "MARK"),
                    [
                        (0, "3DFACE"), (8, "0"), (10, "0"), (20, "0"), (30, "1"), (11, "1"),
                        (21, "0"), (31, "2"), (12, "1"), (22, "1"), (32, "3"), (13, "0"),
                        (23, "1"), (33, "4"), (70, "2"),
                    ],
                    [
                        (0, "WIPEOUT"), (8, "0"), (10, "0"), (20, "0"), (30, "0"), (11, "1"),
                        (21, "0"), (31, "0"), (12, "0"), (22, "1"), (32, "0"), (13, "1"),
                        (23, "1"), (14, "-0.5"), (24, "-0.5"), (14, "0.5"), (24, "0.5"),
                    ],
                ]
            )
        ]
        b.entities = [
            DXFBuilder.insert(
                "FILLS", at: (10, 20), scale: (2, 2), rotation: 90, layer: "SHEET", color: 5)
        ]
        let dwg = try DXF.read(text: b.text(), options: .init(expandBlocks: true))
        #expect(dwg.skipped.isEmpty)
        #expect(dwg.counts.solid == 1 && dwg.counts.face3D == 1 && dwg.counts.wipeout == 1)
        // Turned by 90 degrees and doubled about (10, 20): (x, y) goes to (10 - 2y, 20 + 2x).
        let solid = try #require(Self.solids(dwg).first)
        #expect(
            solid.corners == [
                DXF.Point(10, 20, 0), DXF.Point(10, 22, 0), DXF.Point(8, 22, 0),
                DXF.Point(8, 20, 0),
            ])
        #expect(solid.layer == "MARK" && solid.color == 256)
        // What is on layer 0 or BYBLOCK takes the reference's layer and colour.
        let face = try #require(Self.faces(dwg).first)
        #expect(face.layer == "SHEET")
        #expect(face.corners[1].x == 10 && abs(face.corners[1].y - 22) < 1e-9)
        #expect(face.corners.map(\.z) == [1, 2, 3, 4] && face.invisibleEdges == 2)
        // The block's boundary is (0, 1), (1, 1), (1, 0), (0, 0) before the reference moves it.
        let wipeout = try #require(Self.wipeouts(dwg).first)
        #expect(wipeout.layer == "SHEET")
        Self.expectEqual(
            wipeout.boundary,
            Self.points([[8, 20, 0], [8, 22, 0], [10, 22, 0], [10, 20, 0]]), accuracy: 1e-9)
    }
}
