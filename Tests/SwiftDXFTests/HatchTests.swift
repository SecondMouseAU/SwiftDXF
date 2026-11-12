import Foundation
import Testing

@testable import SwiftDXF

/// HATCH, LEADER, line types and the layer table.
///
/// The reference values come from `ezdxf` reading `Fixtures/hatch.dxf` (`tools/hatch_fixtures.py`).
@Suite("Hatch, leader, line types and layers")
struct HatchTests {

    static func fixture() throws -> DXF.Drawing {
        let url = try #require(
            Bundle.module.url(
                forResource: "hatch", withExtension: "dxf", subdirectory: "Fixtures"))
        return try DXF.read(contentsOf: url)
    }

    static func hatches(_ dwg: DXF.Drawing) -> [DXF.Hatch] {
        dwg.entities.compactMap { if case .hatch(let h) = $0 { return h } else { return nil } }
    }

    // MARK: Flattening, to measure what a boundary encloses

    /// Points along one edge, in the direction the edge is drawn.
    static func points(of edge: DXF.Hatch.Edge) -> [DXF.Point2] {
        switch edge {
        case .line(let a, let b): return [a, b]
        case .arc(let c, let r, let s, let e, let ccw):
            var sweep = e - s
            if sweep <= 0 { sweep += 360 }
            let pts = (0...400).map { k -> DXF.Point2 in
                let a = (s + sweep * Double(k) / 400) * .pi / 180
                return DXF.Point2(c.x + r * cos(a), c.y + r * sin(a))
            }
            return ccw ? pts : pts.reversed()
        case .ellipse(let c, let m, let ratio, let s, let e, let ccw):
            var sweep = e - s
            if sweep <= 0 { sweep += 2 * .pi }
            let tilt = atan2(m.y, m.x)
            let a = hypot(m.x, m.y)
            let b = a * ratio
            let pts = (0...400).map { k -> DXF.Point2 in
                let t = s + sweep * Double(k) / 400
                let x = a * cos(t)
                let y = b * sin(t)
                return DXF.Point2(
                    c.x + x * cos(tilt) - y * sin(tilt), c.y + x * sin(tilt) + y * cos(tilt))
            }
            return ccw ? pts : pts.reversed()
        case .spline(let s): return s.flattened(tolerance: 1e-4).map { DXF.Point2($0.x, $0.y) }
        }
    }

    /// The boundary as one polyline, orienting each edge to continue the one before.
    static func chain(_ path: DXF.Hatch.BoundaryPath) -> [DXF.Point2] {
        switch path.geometry {
        case .polyline(let vertices, let closed):
            var pts: [DXF.Point2] = []
            for i in 0..<vertices.count {
                let v = vertices[i]
                let a = DXF.Point2(v.point.x, v.point.y)
                guard closed || i < vertices.count - 1 else {
                    pts.append(a)
                    continue
                }
                let w = vertices[(i + 1) % vertices.count]
                let seg = DXF.Contour.Segment(
                    start: a, end: DXF.Point2(w.point.x, w.point.y), bulge: v.bulge)
                pts += (0..<100).map { seg.point(at: Double($0) / 100) }
            }
            return pts
        case .edges(let edges):
            var pieces = edges.map(points(of:))
            guard var out = pieces.first else { return [] }
            pieces.removeFirst()
            if let next = pieces.first {
                // Orient the first edge so it ends where the second begins.
                let ends = [out.last!, out.first!]
                let starts = [next.first!, next.last!]
                var best = (gap: Double.infinity, flip: false)
                for (i, e) in ends.enumerated() {
                    for s in starts where e.distance(to: s) < best.gap {
                        best = (e.distance(to: s), i == 1)
                    }
                }
                if best.flip { out.reverse() }
            }
            for piece in pieces {
                let forward = out.last!.distance(to: piece.first!)
                let backward = out.last!.distance(to: piece.last!)
                out += forward <= backward ? piece : piece.reversed()
            }
            return out
        }
    }

    static func area(_ pts: [DXF.Point2]) -> Double {
        var sum = 0.0
        for i in pts.indices {
            let p = pts[i]
            let q = pts[(i + 1) % pts.count]
            sum += p.x * q.y - q.x * p.y
        }
        return abs(sum) / 2
    }

    // MARK: Layers and line types

    @Test("the layer table gives colour, line type and the off, frozen and locked flags")
    func layerTable() throws {
        let dwg = try Self.fixture()
        func layer(_ name: String) throws -> DXF.Layer { try #require(dwg.layer(named: name)) }
        let hid = try layer("HID")
        #expect(hid.color == 1 && hid.lineTypeName == "HIDDEN" && hid.isVisible)
        #expect(try layer("CENTRE").lineTypeName == "CENTER")
        let off = try layer("OFFLAYER")
        #expect(off.isOff && !off.isFrozen && !off.isVisible && off.color == 3)
        let frozen = try layer("FROZEN")
        #expect(frozen.isFrozen && !frozen.isOff && !frozen.isVisible)
        let locked = try layer("LOCKED")
        #expect(locked.isLocked && locked.isVisible)
        #expect(try layer("VISIBLE").lineTypeName == "Continuous")
        #expect(dwg.layer(named: "hid")?.name == "HID")
        #expect(dwg.layer(named: "missing") == nil)
    }

    @Test("line type patterns match ezdxf")
    func lineTypePatterns() throws {
        let dwg = try Self.fixture()
        // ezdxf compile() gives lengths without signs: HIDDEN [0.25, 0.125].
        let hidden = try #require(dwg.lineType(named: "hidden"))
        #expect(hidden.pattern == [0.25, -0.125] && hidden.patternLength == 0.375)
        #expect(hidden.description == "Hidden __ __ __" && !hidden.isContinuous)
        // CENTER [3.175, 0.635, 0.635, 0.635]: dash, gap, dash, gap.
        let centre = try #require(dwg.lineType(named: "CENTER"))
        #expect(centre.pattern.map(abs) == [3.175, 0.635, 0.635, 0.635])
        #expect(centre.pattern.map { $0 > 0 } == [true, false, true, false])
        let phantom = try #require(dwg.lineType(named: "PHANTOM"))
        #expect(phantom.pattern.map(abs) == [3.175, 0.635, 0.635, 0.635, 0.635, 0.635])
        #expect(try #require(dwg.lineType(named: "continuous")).isContinuous)
    }

    @Test("BYLAYER, BYBLOCK and absent line types resolve to an effective type")
    func effectiveLineTypes() throws {
        let dwg = try Self.fixture()
        // Five LINEs, as written by ezdxf: [layer, group 6].
        // [HID, none], [VISIBLE, PHANTOM], [HID, ByBlock], [HID, ByLayer], [0, none]
        let written = (0..<5).map { dwg.lineTypeName(ofEntityAt: $0) }
        #expect(written == [nil, "PHANTOM", "ByBlock", "ByLayer", nil])
        #expect(
            (0..<5).map { dwg.effectiveLineType(ofEntityAt: $0) }
                == ["HIDDEN", "PHANTOM", "Continuous", "HIDDEN", "Continuous"])
        #expect(dwg.effectiveLineType(ofEntityAt: 999) == "Continuous")
    }

    @Test("entities on layers that are off or frozen are not visible")
    func visibility() {
        let layers = [
            DXF.Layer(name: "ON", identity: .init(locator: "a")),
            DXF.Layer(name: "OFF", identity: .init(locator: "b"), isOff: true),
            DXF.Layer(name: "ICE", identity: .init(locator: "c"), isFrozen: true),
        ]
        let point: (String) -> DXF.Entity = { .point(at: .init(0, 0), layer: $0, color: 256) }
        let dwg = DXF.Drawing(
            entities: ["ON", "OFF", "ICE", "UNLISTED"].map(point), layers: layers)
        #expect((0..<4).map { dwg.isVisible(entityAt: $0) } == [true, false, false, true])
    }

    // MARK: HATCH

    @Test("a solid hatch reads its polyline boundaries, with bulges and the outer flag")
    func solidPolylineHatch() throws {
        let dwg = try Self.fixture()
        let hatch = try #require(Self.hatches(dwg).first)
        #expect(hatch.patternName == "SOLID" && hatch.isSolid && hatch.layer == "VISIBLE")
        #expect(hatch.paths.count == 2)
        #expect(hatch.paths[0].flags == 3 && hatch.paths[0].isExternal)
        #expect(hatch.paths[1].flags == 2 && !hatch.paths[1].isExternal)
        guard case .polyline(let outer, let closed) = hatch.paths[0].geometry else {
            Issue.record("expected a polyline path")
            return
        }
        #expect(closed)
        #expect(outer.map(\.bulge) == [0, 0, 0.5, 0])
        #expect(outer.map(\.point.y) == [10, 10, 20, 20])
        guard case .polyline(let hole, _) = hatch.paths[1].geometry else { return }
        #expect(hole.count == 4 && hole.allSatisfy { $0.bulge == 0 })
    }

    @Test("a pattern hatch reads line, arc, ellipse and spline edges, and names its pattern")
    func edgePathHatch() throws {
        let dwg = try Self.fixture()
        let hatch = Self.hatches(dwg)[1]
        #expect(hatch.patternName == "ANSI31" && !hatch.isSolid)
        guard case .edges(let edges) = hatch.paths[0].geometry else {
            Issue.record("expected an edge path")
            return
        }
        #expect(edges.count == 5)
        #expect(edges[0] == .line(start: .init(20, 10), end: .init(30, 10)))
        #expect(
            edges[1]
                == .arc(
                    center: .init(30, 12), radius: 2, startDeg: 270, endDeg: 90,
                    counterClockwise: true))
        guard case .ellipse(let c, let m, let ratio, let s, let e, let ccw) = edges[2] else {
            Issue.record("expected an ellipse edge")
            return
        }
        #expect(c == .init(25, 14) && m == .init(3, 0) && ratio == 0.5 && ccw)
        #expect(abs(s) < 1e-12 && abs(e - .pi) < 1e-12)
        guard case .spline(let spline) = edges[3] else {
            Issue.record("expected a spline edge")
            return
        }
        #expect(spline.degree == 2 && spline.knots == [0, 0, 0, 1, 1, 1])
        #expect(spline.controlPoints.map(\.x) == [22, 21, 20] && !spline.isRational)
        #expect(edges[4] == .line(start: .init(20, 12), end: .init(20, 10)))
    }

    @Test("a clockwise arc edge reads as the counter-clockwise angles ezdxf reports")
    func clockwiseArcEdge() throws {
        let dwg = try Self.fixture()
        guard case .edges(let edges) = Self.hatches(dwg)[2].paths[0].geometry else { return }
        #expect(
            edges[1]
                == .arc(
                    center: .init(45, 10), radius: 5, startDeg: 0, endDeg: 180,
                    counterClockwise: false))
    }

    @Test("partial ellipse edges convert stored angles to the parameters ezdxf reports")
    func ellipseEdgeParameters() throws {
        let dwg = try Self.fixture()
        for (index, ccw) in [(3, true), (4, false)] {
            guard case .edges(let edges) = Self.hatches(dwg)[index].paths[0].geometry,
                case .ellipse(_, let m, let ratio, let s, let e, let counterClockwise) = edges[0]
            else {
                Issue.record("expected an ellipse edge in hatch \(index)")
                return
            }
            #expect(m == .init(4, 2) && ratio == 0.4 && counterClockwise == ccw)
            #expect(abs(s - 0.9649052079556502) < 1e-12)
            #expect(abs(e - 4.567816623190014) < 1e-12)
        }
    }

    @Test("a full ellipse edge keeps its full turn")
    func fullEllipseEdge() {
        #expect(abs(DXF.Reader.ellipseParameter(degrees: 360, ratio: 0.5) - 2 * .pi) < 1e-12)
        #expect(DXF.Reader.ellipseParameter(degrees: 0, ratio: 0.5) == 0)
        #expect(abs(DXF.Reader.ellipseParameter(degrees: 90, ratio: 0.3) - .pi / 2) < 1e-12)
        #expect(abs(DXF.Reader.ellipseParameter(degrees: 450, ratio: 1) - 2.5 * .pi) < 1e-12)
    }

    @Test("every boundary closes, and encloses the area ezdxf reports")
    func boundariesCloseIntoEzdxfRegions() throws {
        let dwg = try Self.fixture()
        // ezdxf's flattened area of each boundary path, in hatch order.
        let reference: [[Double]] = [
            [117.47163, 9.0], [50.687913], [39.279917], [16.192157], [16.192157],
        ]
        let hatches = Self.hatches(dwg)
        #expect(hatches.count == reference.count)
        for (hatch, expected) in zip(hatches, reference) {
            #expect(hatch.paths.count == expected.count)
            for (path, want) in zip(hatch.paths, expected) {
                let loop = Self.chain(path)
                let got = Self.area(loop)
                #expect(abs(got - want) <= 1e-3 * want, "area \(got) != \(want)")
            }
        }
        // The mixed edge path closes: the last edge ends where the first begins.
        let mixed = Self.chain(hatches[1].paths[0])
        #expect(mixed.first!.distance(to: mixed.last!) < 1e-6)
    }

    // MARK: LEADER

    @Test("leaders read their vertices, arrowhead and the handle of their annotation")
    func leaders() throws {
        let dwg = try Self.fixture()
        let leaders = dwg.entities.compactMap { e -> DXF.Leader? in
            if case .leader(let l) = e { return l } else { return nil }
        }
        #expect(leaders.count == 2)
        #expect(leaders[0].vertices.map(\.x) == [60, 65, 70] && leaders[0].hasArrowhead)
        #expect(!leaders[0].isSpline && leaders[0].layer == "NOTES")
        #expect(leaders[0].annotationHandle == "9C")
        #expect(leaders[1].hasArrowhead == false && leaders[1].annotationHandle == nil)
        // The handle names an entity in the drawing: the MTEXT the leader points at.
        let target = try #require(dwg.identities.firstIndex { $0.handle == "9C" })
        guard case .text(_, _, _, let string, _, _) = dwg.entities[target] else {
            Issue.record("the annotation is not text")
            return
        }
        #expect(string == "NOTE")
    }

    @Test("counts and bounds include hatches and leaders")
    func countsAndBounds() throws {
        let dwg = try Self.fixture()
        #expect(dwg.counts.hatch == 5 && dwg.counts.leader == 2)
        #expect(dwg.counts.total == dwg.entities.count)
        let bounds = try #require(dwg.bounds)
        #expect(bounds.min.x == 0 && bounds.max.x >= 124)
    }

    @Test("a rational spline edge keeps its weights, and a spline leader is flagged")
    func rationalEdgeAndSplineLeader() throws {
        let hatch = RawDXF.record(
            "HATCH", (8, "0"), (2, "SOLID"), (70, "1"), (91, "1"), (92, "0"), (93, "1"),
            (72, "4"), (94, "2"), (73, "1"), (74, "0"), (95, "6"), (96, "3"),
            (40, "0"), (40, "0"), (40, "0"), (40, "1"), (40, "1"), (40, "1"),
            (10, "1"), (20, "0"), (42, "1"), (10, "1"), (20, "1"), (42, "0.7071067811865476"),
            (10, "0"), (20, "1"), (42, "1"), (97, "0"), (75, "0"), (76, "1"), (98, "0"))
        let leader = RawDXF.record(
            "LEADER", (8, "0"), (72, "1"), (76, "2"), (10, "0"), (20, "0"), (30, "0"),
            (10, "5"), (20, "5"), (30, "0"))
        let dwg = try DXF.read(text: RawDXF.entities([hatch, leader]))
        guard case .edges(let edges)? = Self.hatches(dwg).first?.paths.first?.geometry,
            case .spline(let spline)? = edges.first
        else {
            Issue.record("the path is not a spline edge")
            return
        }
        #expect(spline.degree == 2 && spline.knots == [0, 0, 0, 1, 1, 1])
        #expect(spline.controlPoints.count == 3 && spline.weights.count == 3)
        #expect(abs(spline.weights[1] - 0.7071067811865476) < 1e-12)
        let leaders = dwg.entities.compactMap { entity -> DXF.Leader? in
            if case .leader(let l) = entity { return l } else { return nil }
        }
        #expect(leaders.count == 1 && leaders[0].isSpline && leaders[0].vertices.count == 2)
    }

    @Test("bounds reach a leader and a hatch that lie outside the other geometry")
    func boundsReachHatchesAndLeaders() throws {
        func bounds(_ records: [String]) throws -> (min: DXF.Point, max: DXF.Point) {
            try #require(try DXF.read(text: RawDXF.entities(records)).bounds)
        }
        let line = RawDXF.line(from: (0, 0), to: (1, 1))
        let leader = RawDXF.record(
            "LEADER", (8, "0"), (76, "2"), (10, "0"), (20, "0"), (30, "0"), (10, "30"),
            (20, "20"), (30, "0"))
        let hatch = RawDXF.record(
            "HATCH", (8, "0"), (2, "SOLID"), (70, "1"), (91, "1"), (92, "2"), (72, "0"),
            (73, "1"), (93, "3"), (10, "50"), (20, "-5"), (10, "60"), (20, "-5"),
            (10, "60"), (20, "40"), (97, "0"), (75, "0"), (76, "1"), (98, "0"))
        let withLeader = try bounds([line, leader])
        #expect(withLeader.max.x == 30 && withLeader.max.y == 20)
        let withHatch = try bounds([line, hatch])
        #expect(withHatch.max.x == 60 && withHatch.max.y == 40 && withHatch.min.y == -5)
    }

    // MARK: Malformed input and R12 style records

    @Test("a hatch with wrong counts or missing groups never traps")
    func malformedHatch() throws {
        let body = [
            RawDXF.record(
                "HATCH", (8, "0"), (2, "SOLID"), (70, "1"), (91, "9"),
                (92, "7"), (93, "50"), (72, "1"), (10, "0.0"), (20, "0.0"),
                (92, "1"), (93, "3"), (72, "1"), (10, "0.0"), (72, "9"), (72, "2"), (40, "1.0"),
                (92, "2"), (72, "0"), (73, "1"), (93, "4"), (10, "1.0")),
            RawDXF.record("HATCH", (91, "2")),
            RawDXF.record("LEADER", (76, "3"), (10, "0.0")),
        ]
        let dwg = try DXF.read(text: RawDXF.entities(body))
        #expect(dwg.counts.hatch == 2 && dwg.counts.leader == 1)
        let first = Self.hatches(dwg)[0]
        #expect(first.isSolid && first.paths.count == 3)
        #expect(Self.hatches(dwg)[1].paths.isEmpty)
    }

    @Test("a polyline path stops at its vertex count, and an empty one stays empty")
    func polylinePathBounds() throws {
        let empty = RawDXF.record(
            "HATCH", (8, "0"), (2, "SOLID"), (70, "1"), (91, "1"), (92, "2"), (72, "0"),
            (73, "1"), (93, "0"), (97, "0"), (75, "0"), (76, "1"), (98, "1"), (10, "7.0"),
            (20, "7.0"))
        let two = RawDXF.record(
            "HATCH", (8, "0"), (2, "SOLID"), (70, "1"), (91, "1"), (92, "2"), (72, "0"),
            (73, "1"), (93, "2"), (10, "0.0"), (20, "0.0"), (10, "4.0"), (20, "0.0"),
            (97, "0"), (98, "1"), (10, "7.0"), (20, "7.0"))
        // No group 93 at all: the path owns nothing, and the seed point is not its vertex.
        let unnumbered = RawDXF.record(
            "HATCH", (8, "0"), (2, "SOLID"), (70, "1"), (91, "1"), (92, "2"), (72, "0"),
            (73, "1"), (97, "0"), (75, "0"), (76, "1"), (98, "1"), (10, "7.0"), (20, "7.0"))
        let dwg = try DXF.read(text: RawDXF.entities([empty, two, unnumbered]))
        let found = Self.hatches(dwg)
        #expect(found.count == 3)
        for (hatch, count) in zip(found, [0, 2, 0]) {
            guard case .polyline(let vertices, _) = hatch.paths.first?.geometry else {
                Issue.record("the path is not a polyline")
                continue
            }
            #expect(vertices.count == count)
            #expect(!vertices.contains { $0.point.x == 7 })
        }
    }

    @Test("a closed LTYPE and LAYER table from an old file read as written")
    func oldStyleTables() throws {
        let tables = RawDXF.section(
            "TABLES",
            [
                RawDXF.table(
                    "LTYPE",
                    [
                        RawDXF.record(
                            "LTYPE", (2, "DASHED"), (70, "0"), (3, "Dashed"), (72, "65"),
                            (73, "2"), (40, "0.75"), (49, "0.5"), (49, "-0.25")),
                        RawDXF.record(
                            "LTYPE", (2, "CONTINUOUS"), (70, "0"), (3, "Solid line"), (72, "65"),
                            (73, "0"), (40, "0.0")),
                    ]),
                RawDXF.table(
                    "LAYER",
                    [
                        RawDXF.record("LAYER", (2, "GONE"), (70, "1"), (62, "-3"), (6, "DASHED")),
                        RawDXF.record("LAYER", (2, "PLAIN"), (70, "4"), (62, "5")),
                    ]),
            ])
        let dwg = try DXF.read(text: RawDXF.file([tables, RawDXF.section("ENTITIES", [])]))
        #expect(dwg.lineTypes.map(\.name) == ["DASHED", "CONTINUOUS"])
        #expect(dwg.lineTypes[0].pattern == [0.5, -0.25] && dwg.lineTypes[0].patternLength == 0.75)
        #expect(dwg.lineTypes[1].isContinuous)
        let gone = dwg.layers[0]
        #expect(gone.isOff && gone.isFrozen && gone.color == 3 && gone.lineTypeName == "DASHED")
        let plain = dwg.layers[1]
        #expect(plain.isLocked && !plain.isOff && plain.lineTypeName == "Continuous")
    }

    @Test("a block's entities keep their line type names")
    func blockLineTypes() throws {
        let blocks = RawDXF.section(
            "BLOCKS",
            [
                RawDXF.record("BLOCK", (2, "B")),
                RawDXF.record("LINE", (8, "0"), (6, "HIDDEN"), (10, "0"), (20, "0")),
                RawDXF.record("LINE", (8, "0"), (10, "0"), (20, "0")),
                RawDXF.record("ENDBLK"),
            ])
        let dwg = try DXF.read(text: RawDXF.file([blocks, RawDXF.section("ENTITIES", [])]))
        #expect(dwg.blocks[0].entityLineTypes == ["HIDDEN", nil])
    }
}
