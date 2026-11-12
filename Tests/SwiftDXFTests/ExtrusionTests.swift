import Foundation
import Testing

@testable import SwiftDXF

/// Entities written in an object coordinate system (OCS), read as world coordinates.
///
/// The reference values come from `ezdxf` reading `Fixtures/ocs.dxf` (`tools/ocs_fixtures.py`):
/// `ezdxf.upright` for ARC, CIRCLE, LWPOLYLINE, POLYLINE, ELLIPSE and HATCH, `ocs.to_wcs` for TEXT
/// and DIMENSION.
@Suite("Extrusion: the object coordinate system")
struct ExtrusionTests {
    static func fixture(options: DXF.ReadOptions = .init()) throws -> DXF.Drawing {
        let url = try #require(
            Bundle.module.url(forResource: "ocs", withExtension: "dxf", subdirectory: "Fixtures"))
        return try DXF.read(contentsOf: url, options: options)
    }

    static func close(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool {
        abs(a - b) <= tolerance
    }

    static func close(_ p: DXF.Point, _ x: Double, _ y: Double, _ z: Double = 0) -> Bool {
        close(p.x, x) && close(p.y, y) && close(p.z, z)
    }

    /// Entities in file order: ARC, CIRCLE, LWPOLYLINE, POLYLINE, ELLIPSE, TEXT, HATCH, DIMENSION
    /// (all with an extrusion of -z), then an ARC and an LWPOLYLINE with the default extrusion and
    /// an ARC with a tilted one.
    @Test("the fixture reads the entities it was built from, in order")
    func order() throws {
        let kinds = try Self.fixture().entities.map(\.typeName)
        #expect(
            kinds == [
                "ARC", "CIRCLE", "POLYLINE", "POLYLINE", "ELLIPSE", "TEXT", "HATCH", "DIMENSION",
                "ARC", "POLYLINE", "ARC",
            ])
    }

    @Test("an arc and a circle on a -z plane are mirrored, as ezdxf upright gives them")
    func arcAndCircle() throws {
        let d = try Self.fixture()
        guard case .arc(let c, let r, let s, let e, _, _) = d.entities[0] else {
            Issue.record("not an arc")
            return
        }
        // ezdxf: center (-3, 4, -1), 70 to 160 degrees.
        #expect(Self.close(c, -3, 4, -1) && Self.close(r, 5))
        #expect(Self.close(s, 70) && Self.close(e, 160))
        guard case .circle(let cc, let cr, _, _) = d.entities[1] else {
            Issue.record("not a circle")
            return
        }
        #expect(Self.close(cc, -2, 3, -1) && Self.close(cr, 1.5))
    }

    @Test("a polyline on a -z plane mirrors its vertices, flips its bulges and keeps its elevation")
    func polylines() throws {
        let d = try Self.fixture()
        guard case .polyline(let v, _, _, _) = d.entities[2] else {
            Issue.record("not a polyline")
            return
        }
        // ezdxf: elevation -2, points (-0, 0, -0.5), (-4, 0, 0), (-4, 3, 0.25).
        #expect(v.count == 3)
        #expect(Self.close(v[0].point, 0, 0, -2) && Self.close(v[0].bulge, -0.5))
        #expect(Self.close(v[1].point, -4, 0, -2) && Self.close(v[1].bulge, 0))
        #expect(Self.close(v[2].point, -4, 3, -2) && Self.close(v[2].bulge, 0.25))
        guard case .polyline(let old, _, _, _) = d.entities[3] else {
            Issue.record("not a polyline")
            return
        }
        // ezdxf: (-1, 1, -0.5), (-5, 1, 0), (-5, 4, 0).
        #expect(Self.close(old[0].point, -1, 1) && Self.close(old[0].bulge, -0.5))
        #expect(Self.close(old[1].point, -5, 1) && Self.close(old[2].point, -5, 4))
    }

    @Test("an ellipse on a -z plane keeps its centre and axis and runs its parameter the other way")
    func ellipse() throws {
        let d = try Self.fixture()
        guard case .ellipse(let c, let m, let ratio, let s, let e, _, _) = d.entities[4] else {
            Issue.record("not an ellipse")
            return
        }
        // ezdxf: centre (1, 2), major (4, 0), ratio 0.5, parameter -2.0 to -0.3 (counter-clockwise).
        #expect(Self.close(c, 1, 2) && Self.close(m, 4, 0) && Self.close(ratio, 0.5))
        let turn = 2 * Double.pi
        #expect(Self.close(s, turn - 2.0) && Self.close(e, turn - 0.3))
    }

    @Test("text on a -z plane moves to the world and turns round")
    func text() throws {
        let d = try Self.fixture()
        guard case .text(let p, let h, let rotation, _, _, _) = d.entities[5] else {
            Issue.record("not text")
            return
        }
        // ezdxf: insert (-5, 1, 0), rotation 150.
        #expect(Self.close(p, -5, 1) && Self.close(h, 2.5) && Self.close(rotation, 150))
    }

    @Test("a hatch on a -z plane is mirrored, and its path travels the arc the other way")
    func hatch() throws {
        let d = try Self.fixture()
        guard case .hatch(let h) = d.entities[6] else {
            Issue.record("not a hatch")
            return
        }
        #expect(h.paths.count == 2)
        guard case .polyline(let v, _) = h.paths[0].geometry else {
            Issue.record("not a polyline path")
            return
        }
        // ezdxf: (-0, 0), (-4, 0), (-4, 3), (-0, 3).
        #expect(v.map { [$0.point.x, $0.point.y] } == [[0, 0], [-4, 0], [-4, 3], [0, 3]])
        guard case .edges(let edges) = h.paths[1].geometry, edges.count == 2,
            case .line(let a, let b) = edges[0],
            case .arc(let c, let r, let s, let e, let ccw) = edges[1]
        else {
            Issue.record("not an edge path of a line and an arc")
            return
        }
        // ezdxf: line (-10, 0) to (-14, 0); arc centre (-12, 0), radius 2, 0 to 180, clockwise.
        #expect(a == DXF.Point2(-10, 0) && b == DXF.Point2(-14, 0))
        #expect(c == DXF.Point2(-12, 0) && Self.close(r, 2))
        #expect(Self.close(s, 0) && Self.close(e, 180) && !ccw)
    }

    @Test("a dimension on a -z plane moves its text point, and leaves its world definition points")
    func dimension() throws {
        let d = try Self.fixture()
        guard case .dimension(let m) = d.entities[7] else {
            Issue.record("not a dimension")
            return
        }
        // ezdxf: text point (2, 3, -0.5). The points 10, 13 and 14 are world coordinates.
        #expect(Self.close(m.textPosition, 2, 3, -0.5))
        #expect(Self.close(m.computedMeasurement ?? 0, 4))
    }

    @Test("a default extrusion leaves entities alone, but a polyline's elevation becomes its z")
    func upright() throws {
        let d = try Self.fixture()
        guard case .arc(let c, _, let s, let e, _, _) = d.entities[8] else {
            Issue.record("not an arc")
            return
        }
        #expect(Self.close(c, 3, 4, 1) && Self.close(s, 20) && Self.close(e, 110))
        guard case .polyline(let v, _, _, _) = d.entities[9] else {
            Issue.record("not a polyline")
            return
        }
        #expect(v.allSatisfy { Self.close($0.point.z, 5) })
    }

    @Test("a tilted extrusion is left as written and reported")
    func tilted() throws {
        let d = try Self.fixture()
        guard case .arc(let c, let r, let s, let e, _, _) = d.entities[10] else {
            Issue.record("not an arc")
            return
        }
        #expect(Self.close(c, 1, 1) && Self.close(r, 2) && Self.close(s, 0) && Self.close(e, 90))
        #expect(d.warnings == [.extrusionNotApplied(type: "ARC", count: 1)])
        #expect(
            d.warnings[0].description
                == "1 ARC entities have an extrusion not along z, read as if it were")
    }

    @Test("a block's flipped arc is read in the world, and expands to where it is drawn")
    func block() throws {
        let plain = try Self.fixture()
        let block = try #require(plain.blocks.first { $0.name == "FLIPPED" })
        // ezdxf: centre (-1, 0), 90 to 180.
        guard case .arc(let c, _, let s, let e, _, _) = block.entities[0] else {
            Issue.record("not an arc")
            return
        }
        #expect(Self.close(c, -1, 0) && Self.close(s, 90) && Self.close(e, 180))

        let expanded = try Self.fixture(options: .init(expandBlocks: true))
        // The reference sits at (20, 10), so the arc centre is at (19, 10).
        guard case .arc(let ec, _, let es, let ee, _, _) = expanded.entities.last else {
            Issue.record("the expanded arc is missing")
            return
        }
        #expect(Self.close(ec, 19, 10) && Self.close(es, 90) && Self.close(ee, 180))
    }
}

/// The plane an extrusion direction puts an object coordinate system in.
@Suite("Extrusion: the object plane")
struct ObjectPlaneTests {
    @Test(
        "the normal's direction decides the plane, not its length",
        arguments: [
            ((0.0, 0.0, 1.0), DXF.ObjectPlane.up), ((0.0, 0.0, -1.0), .down),
            ((0.0, 0.0, -2.5), .down), ((0.0, 0.0, 0.0), .up), ((1e-12, 0.0, -1.0), .down),
            ((0.5, 0.0, -0.8), .tilted), ((1.0, 0.0, 0.0), .tilted),
            ((0.0, 1e-3, 1.0), .tilted),
        ])
    func planes(normal: (Double, Double, Double), expected: DXF.ObjectPlane) {
        let plane = DXF.ObjectPlane(extrusion: DXF.Point(normal.0, normal.1, normal.2))
        #expect(plane == expected)
    }

    @Test("a non-finite normal is not trusted to be tilted")
    func nonFinite() {
        #expect(DXF.ObjectPlane(extrusion: DXF.Point(.nan, 0, -1)) == .up)
        #expect(DXF.ObjectPlane(extrusion: DXF.Point(0, 0, .infinity)) == .up)
    }

    @Test("the mirror turns x and z round and leaves y")
    func mirror() {
        let p = DXF.ObjectPlane.mirror.apply(DXF.Point(3, 4, 5))
        #expect(p == DXF.Point(-3, 4, -5))
    }

    @Test(
        "the reversed ellipse range is counter-clockwise, starts in one turn, and keeps its sweep")
    func ellipseRange() {
        let turn = 2 * Double.pi
        let (s, e) = DXF.Reader.mirroredEllipseRange(start: 0.3, end: 2.0)
        #expect(abs(s - (turn - 2.0)) < 1e-12 && abs(e - (turn - 0.3)) < 1e-12)
        let (fs, fe) = DXF.Reader.mirroredEllipseRange(start: 0, end: turn)
        #expect(abs(fs) < 1e-12 && abs(fe - turn) < 1e-12)
    }
}

/// What the conversion means for the people reading a drawing.
@Suite("Extrusion in practice")
struct ExtrusionPracticeTests {
    static let down: [(Int, String)] = [(210, "0.0"), (220, "0.0"), (230, "-1.0")]

    static func read(_ records: [String]) throws -> DXF.Drawing {
        try DXF.read(text: RawDXF.entities(records))
    }

    /// A quarter disc.
    ///
    /// Two lines on the axes and an arc written in a -z coordinate system, whose x axis runs the
    /// other way. Only the mirrored arc closes the loop.
    @Test("a mirrored arc closes the loop it was drawn to close")
    func contour() throws {
        let arc = RawDXF.record(
            "ARC",
            [
                (8, "0"), (10, "0.0"), (20, "0.0"), (30, "0.0"), (40, "4.0"), (50, "90.0"),
                (51, "180.0"),
            ] + Self.down)
        let d = try Self.read([
            RawDXF.line(from: (0, 0), to: (4, 0)), RawDXF.line(from: (0, 0), to: (0, 4)), arc,
        ])
        let result = d.contours(.init(units: .millimetre))
        let shape = try #require(result.shapes.first)
        #expect(result.shapes.count == 1 && result.openChains.isEmpty)
        #expect(abs(shape.area - 4 * .pi) < 1e-6)
    }

    @Test("a normal that is not a unit vector still gives the plane")
    func scaledNormal() throws {
        let arc = RawDXF.record(
            "CIRCLE",
            [
                (8, "0"), (10, "2.0"), (20, "3.0"), (30, "0.0"), (40, "1.0"), (210, "0.0"),
                (220, "0.0"), (230, "-2.5"),
            ])
        let d = try Self.read([arc])
        guard case .circle(let c, _, _, _) = d.entities[0] else {
            Issue.record("not a circle")
            return
        }
        #expect(c == DXF.Point(-2, 3, 0))
    }

    @Test("a 3D polyline, a point and MTEXT hold world coordinates and are not mirrored")
    func worldCoordinates() throws {
        let polyline = RawDXF.record(
            "POLYLINE", [(8, "0"), (70, "8"), (10, "0.0"), (20, "0.0"), (30, "0.0")] + Self.down)
        let vertex = RawDXF.record(
            "VERTEX", (8, "0"), (10, "3.0"), (20, "4.0"), (30, "5.0"), (70, "32"))
        let point = RawDXF.record(
            "POINT", [(8, "0"), (10, "6.0"), (20, "7.0"), (30, "0.0")] + Self.down)
        let mtext = RawDXF.record(
            "MTEXT",
            [(8, "0"), (10, "8.0"), (20, "9.0"), (30, "0.0"), (40, "2.0"), (1, "note")]
                + Self.down)
        let d = try Self.read([polyline, vertex, RawDXF.record("SEQEND"), point, mtext])
        guard case .polyline(let v, _, _, _) = d.entities[0],
            case .point(let p, _, _) = d.entities[1],
            case .text(let t, _, _, _, _, _) = d.entities[2]
        else {
            Issue.record("expected a polyline, a point and text")
            return
        }
        #expect(v[0].point == DXF.Point(3, 4, 5))
        #expect(p == DXF.Point(6, 7, 0) && t == DXF.Point(8, 9, 0))
        #expect(d.warnings.isEmpty)
    }

    @Test("tilted records are counted by type, in the model space and in blocks")
    func tiltedCounts() throws {
        let tilted: [(Int, String)] = [(210, "1.0"), (220, "0.0"), (230, "0.0")]
        let arc = RawDXF.record(
            "ARC",
            [
                (8, "0"), (10, "0.0"), (20, "0.0"), (30, "0.0"), (40, "1.0"), (50, "0.0"),
                (51, "90.0"),
            ] + tilted)
        let circle = RawDXF.record(
            "CIRCLE", [(8, "0"), (10, "0.0"), (20, "0.0"), (30, "0.0"), (40, "1.0")] + tilted)
        let blocks = RawDXF.section(
            "BLOCKS",
            [
                RawDXF.record("BLOCK", (8, "0"), (2, "B"), (70, "0"), (10, "0"), (20, "0")),
                arc, RawDXF.record("ENDBLK"),
            ])
        let text = RawDXF.file([blocks, RawDXF.section("ENTITIES", [arc, circle])])
        let d = try DXF.read(text: text)
        #expect(
            d.warnings == [
                .extrusionNotApplied(type: "ARC", count: 2),
                .extrusionNotApplied(type: "CIRCLE", count: 1),
            ])
    }

    @Test("a drawing with no tilted record has no warning")
    func quiet() throws {
        let d = try Self.read([RawDXF.line()])
        #expect(d.warnings.isEmpty)
    }
}
