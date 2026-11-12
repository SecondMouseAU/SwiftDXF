import Foundation
import Testing

@testable import SwiftDXF

@Suite("Block references and expansion")
struct BlockTests {
    typealias B = DXFBuilder

    static func read(_ builder: DXFBuilder, expand: Bool = true) throws -> DXF.Drawing {
        try DXF.read(text: builder.text(), options: .init(expandBlocks: expand))
    }

    static func lines(_ d: DXF.Drawing) -> [(DXF.Point, DXF.Point)] {
        d.entities.compactMap {
            if case .line(let a, let b, _, _) = $0 { return (a, b) }
            return nil
        }
    }

    static func close(_ p: DXF.Point, _ x: Double, _ y: Double) -> Bool {
        abs(p.x - x) < 1e-9 && abs(p.y - y) < 1e-9
    }

    @Test(
        "a reference is recorded and, unexpanded, its geometry stays out and INSERT stays skipped")
    func notExpandedByDefault() throws {
        var b = DXFBuilder()
        b.blocks = [("B", (0, 0), [B.line((0, 0), (1, 0))])]
        b.entities = [B.insert("B", at: (5, 5), handle: "A1"), B.line((0, 0), (9, 9))]
        let d = try Self.read(b, expand: false)
        #expect(d.entities.count == 1)
        #expect(d.skipped["INSERT"] == 1)
        #expect(d.references.count == 1 && d.references[0].name == "B")
        #expect(d.references[0].identity.id == "A1")
        #expect(d.blocks.first { $0.name == "B" }?.entities.count == 1)
    }

    @Test("expansion applies base point, scale and rotation, and drops INSERT from skipped")
    func translateScaleRotate() throws {
        var b = DXFBuilder()
        b.blocks = [("B", (1, 1), [B.line((1, 1), (3, 1))])]
        b.entities = [B.insert("B", at: (10, 10), scale: (2, 2), rotation: 90, handle: "A1")]
        let d = try Self.read(b)
        #expect(d.skipped["INSERT"] == nil)
        let lines = Self.lines(d)
        #expect(lines.count == 1)
        if let l = lines.first {
            #expect(Self.close(l.0, 10, 10) && Self.close(l.1, 10, 14))
        }
        #expect(d.identities.count == 1)
        #expect(d.identities[0].via == ["A1"] && d.identities[0].blocks == ["B"])
    }

    @Test("nested blocks compose, and the identity lists every reference")
    func nested() throws {
        var b = DXFBuilder()
        b.blocks = [
            ("inner", (0, 0), [B.line((0, 0), (1, 0), handle: "C1")]),
            ("outer", (0, 0), [B.insert("inner", at: (5, 0), scale: (2, 2), handle: "B1")]),
        ]
        b.entities = [B.insert("outer", at: (100, 0), handle: "A1")]
        let d = try Self.read(b)
        let lines = Self.lines(d)
        #expect(lines.count == 1)
        if let l = lines.first { #expect(Self.close(l.0, 105, 0) && Self.close(l.1, 107, 0)) }
        #expect(d.identities[0].via == ["A1", "B1"])
        #expect(d.identities[0].blocks == ["outer", "inner"])
        #expect(d.identities[0].id == "A1/B1/C1")
    }

    @Test("an array places every instance, with its own identity")
    func array() throws {
        var b = DXFBuilder()
        b.blocks = [("B", (0, 0), [B.line((0, 0), (1, 0), handle: "C1")])]
        b.entities = [
            B.insert("B", at: (0, 0), handle: "A1", array: (columns: 2, rows: 2, dx: 10, dy: 20))
        ]
        let d = try Self.read(b)
        let lines = Self.lines(d)
        #expect(lines.count == 4)
        let starts = Set(lines.map { "\($0.0.x),\($0.0.y)" })
        #expect(starts == ["0.0,0.0", "10.0,0.0", "0.0,20.0", "10.0,20.0"])
        #expect(Set(d.identities.map(\.id)).count == 4)
        #expect(d.identities.map(\.id).contains("A1[1,1]/C1"))
    }

    @Test("an array follows the rotation")
    func rotatedArray() throws {
        var b = DXFBuilder()
        b.blocks = [("B", (0, 0), [B.line((0, 0), (1, 0))])]
        b.entities = [
            B.insert("B", at: (0, 0), rotation: 90, array: (columns: 2, rows: 1, dx: 10, dy: 0))
        ]
        let d = try Self.read(b)
        let starts = Self.lines(d).map { $0.0 }
        #expect(
            starts.contains { Self.close($0, 0, 0) } && starts.contains { Self.close($0, 0, 10) })
    }

    @Test("layer 0 and BYBLOCK take the reference's layer, colour and line type")
    func inheritance() throws {
        var b = DXFBuilder()
        b.layers = [
            [(2, "PARTS"), (70, "0"), (62, "3"), (6, "HIDDEN")], [(2, "0"), (70, "0"), (62, "7")],
        ]
        b.blocks = [
            (
                "B", (0, 0),
                [
                    B.line((0, 0), (1, 0), layer: "0", color: 0, lineType: "BYBLOCK"),
                    B.line((0, 1), (1, 1), layer: "KEEP", color: 5),
                    B.line((0, 2), (1, 2), layer: "0"),
                ]
            )
        ]
        b.entities = [B.insert("B", at: (0, 0), layer: "PARTS")]
        let d = try Self.read(b)
        #expect(d.entities.map(\.layer) == ["PARTS", "KEEP", "PARTS"])
        #expect(d.entities.map(\.colorIndex) == [3, 5, 256])
        #expect(d.entityLineTypes == ["HIDDEN", nil, nil])
        #expect(d.effectiveLineType(ofEntityAt: 0) == "HIDDEN")
        #expect(d.effectiveLineType(ofEntityAt: 2) == "HIDDEN")  // by layer: PARTS is HIDDEN
        #expect(d.effectiveLineType(ofEntityAt: 1) == "Continuous")
    }

    @Test("mirroring turns an arc around")
    func mirroredArc() throws {
        var b = DXFBuilder()
        b.blocks = [("B", (0, 0), [B.arc((0, 0), 1, 0, 90)])]
        b.entities = [B.insert("B", at: (0, 0), scale: (-1, 1))]
        let d = try Self.read(b)
        if case .arc(let c, let r, let s, let e, _, _) = d.entities[0] {
            #expect(Self.close(c, 0, 0) && abs(r - 1) < 1e-12)
            #expect(abs(s - 90) < 1e-9 && abs(e - 180) < 1e-9)
        } else {
            Issue.record("not an arc")
        }
    }

    @Test("a non-uniform scale turns a circle into an ellipse")
    func nonUniformCircle() throws {
        var b = DXFBuilder()
        b.blocks = [("B", (0, 0), [B.circle((0, 0), 1)])]
        b.entities = [B.insert("B", at: (3, 4), scale: (2, 1))]
        let d = try Self.read(b)
        if case .ellipse(let c, let m, let ratio, let s, let e, _, _) = d.entities[0] {
            #expect(Self.close(c, 3, 4))
            #expect(abs(hypot(m.x, m.y) - 2) < 1e-9 && abs(ratio - 0.5) < 1e-9)
            #expect(abs(e - s - 2 * .pi) < 1e-9)
        } else {
            Issue.record("not an ellipse")
        }
    }

    @Test("an ellipse carried through a rotation keeps its shape")
    func ellipseRotated() throws {
        var b = DXFBuilder()
        b.blocks = [
            (
                "B", (0, 0),
                [
                    [
                        (0, "ELLIPSE"), (8, "0"), (10, "0"), (20, "0"), (30, "0"), (11, "4"),
                        (21, "0"), (31, "0"), (40, "0.5"), (41, "0"), (42, "\(2 * Double.pi)"),
                    ]
                ]
            )
        ]
        b.entities = [B.insert("B", at: (0, 0), rotation: 90)]
        let d = try Self.read(b)
        if case .ellipse(_, let m, let ratio, _, _, _, _) = d.entities[0] {
            #expect(abs(m.x) < 1e-9 && abs(m.y - 4) < 1e-9 && abs(ratio - 0.5) < 1e-9)
        } else {
            Issue.record("not an ellipse")
        }
    }

    @Test("text through a mirroring reference turns round instead of adding the rotation")
    func mirroredText() throws {
        var b = DXFBuilder()
        let text: DXFBuilder.Record = [
            (0, "TEXT"), (8, "0"), (10, "1"), (20, "0"), (30, "0"), (40, "2"), (1, "hi"),
            (50, "30"),
        ]
        b.blocks = [("B", (0, 0), [text])]
        b.entities = [
            B.insert("B", at: (10, 0), scale: (-1, 1)), B.insert("B", at: (0, 5), rotation: 90),
        ]
        let d = try Self.read(b)
        guard case .text(let p, let h, let rotation, _, _, _) = d.entities[0],
            case .text(let q, _, let turned, _, _, _) = d.entities[1]
        else {
            Issue.record("expected two texts")
            return
        }
        #expect(Self.close(p, 9, 0) && abs(h - 2) < 1e-12)
        #expect(abs(rotation - 150) < 1e-9)
        // A plain rotation still adds.
        #expect(Self.close(q, 0, 6) && abs(turned - 120) < 1e-9)
    }

    @Test("a missing block and a cycle are reported, not trapped")
    func missingAndCycle() throws {
        var b = DXFBuilder()
        b.blocks = [("LOOP", (0, 0), [B.line((0, 0), (1, 0)), B.insert("LOOP", at: (1, 0))])]
        b.entities = [B.insert("GONE", at: (0, 0)), B.insert("LOOP", at: (0, 0))]
        let d = try Self.read(b)
        #expect(d.warnings.contains(.missingBlock(name: "GONE", count: 1)))
        #expect(d.warnings.contains(.blockCycle(name: "LOOP")))
        #expect(Self.lines(d).count == 1)
        #expect(d.skipped["INSERT"] == 1)  // only the missing one is still unread
    }

    @Test("a bulged polyline cannot pass a non-uniform scale and is reported")
    func bulgeUnderNonUniformScale() throws {
        var b = DXFBuilder()
        let poly: DXFBuilder.Record = [
            (0, "LWPOLYLINE"), (8, "0"), (70, "0"), (10, "0"), (20, "0"), (42, "1"), (10, "2"),
            (20, "0"),
        ]
        b.blocks = [("B", (0, 0), [poly, B.line((0, 0), (1, 0))])]
        b.entities = [B.insert("B", at: (0, 0), scale: (2, 1))]
        let d = try Self.read(b)
        #expect(d.entities.count == 1)
        #expect(d.warnings.contains(.notTransformed(type: "POLYLINE", count: 1)))
    }

    @Test("a uniformly mirrored bulge flips sign")
    func bulgeMirrored() throws {
        var b = DXFBuilder()
        let poly: DXFBuilder.Record = [
            (0, "LWPOLYLINE"), (8, "0"), (70, "0"), (10, "0"), (20, "0"), (42, "0.5"), (10, "2"),
            (20, "0"),
        ]
        b.blocks = [("B", (0, 0), [poly])]
        b.entities = [B.insert("B", at: (0, 0), scale: (1, -1))]
        let d = try Self.read(b)
        if case .polyline(let v, _, _, _) = d.entities[0] {
            #expect(v[0].bulge == -0.5)
        } else {
            Issue.record("not a polyline")
        }
    }

    @Test("a dimension keeps its value through a rotation and its direction turns")
    func dimensionThroughRotation() throws {
        var b = DXFBuilder()
        let dim: DXFBuilder.Record = [
            (0, "DIMENSION"), (8, "0"), (10, "5"), (20, "2"), (30, "0"), (11, "5"), (21, "2"),
            (31, "0"), (70, "0"), (42, "-1"), (13, "0"), (23, "0"), (33, "0"), (14, "10"),
            (24, "0"), (34, "0"),
        ]
        b.blocks = [("B", (0, 0), [dim])]
        b.entities = [B.insert("B", at: (0, 0), rotation: 90)]
        let d = try Self.read(b)
        if case .dimension(let m) = d.entities[0] {
            #expect(abs((m.rotation ?? -1) - 90) < 1e-9)
            #expect(abs((m.computedMeasurement ?? 0) - 10) < 1e-9)
        } else {
            Issue.record("not a dimension")
        }
    }

    @Test("block contents with no entity form are counted as skipped, per instance")
    func skippedInBlocks() throws {
        var b = DXFBuilder()
        let solid: DXFBuilder.Record = [(0, "SOLID"), (8, "0"), (10, "0"), (20, "0")]
        b.blocks = [("B", (0, 0), [solid, B.line((0, 0), (1, 0))])]
        b.entities = [B.insert("B", at: (0, 0), layer: "P"), B.insert("B", at: (5, 0), layer: "P")]
        let d = try Self.read(b)
        #expect(d.skipped == ["SOLID": 2])
        #expect(d.skippedByLayer["SOLID"] == ["P": 2])
    }

    @Test("an array count that would overflow, and one that is only huge, stop with a warning")
    func hugeArrays() throws {
        var b = DXFBuilder()
        b.blocks = [("B", (0, 0), [B.line((0, 0), (1, 0))])]
        b.entities = [
            B.insert(
                "B", at: (0, 0), array: (columns: Int.max / 2, rows: Int.max / 2, dx: 1, dy: 1))
        ]
        var d = try Self.read(b, expand: false)
        d.expandBlockReferences(limit: 50)
        #expect(d.entities.count <= 51)
        #expect(d.warnings.contains(.expansionTruncated(limit: 50)))
    }

    @Test("a block that holds ten references to the next cannot run away")
    func fanOut() throws {
        var b = DXFBuilder()
        var blocks: [(name: String, base: (Double, Double), body: [DXFBuilder.Record])] = [
            ("L0", (0, 0), [B.line((0, 0), (1, 0))])
        ]
        for level in 1...8 {
            let body = (0..<10).map { B.insert("L\(level - 1)", at: (Double($0), 0)) }
            blocks.append(("L\(level)", (0, 0), body))
        }
        b.blocks = blocks
        b.entities = [B.insert("L8", at: (0, 0))]
        var d = try Self.read(b, expand: false)
        d.expandBlockReferences(limit: 1_000)
        #expect(d.entities.count < 2_000)
        #expect(d.warnings.contains(.expansionTruncated(limit: 1_000)))
        #expect(d.identities.count == d.entities.count)
    }

    @Test("expansion is repeatable")
    func repeatable() throws {
        var b = DXFBuilder()
        b.blocks = [("B", (0, 0), [B.line((0, 0), (1, 0))])]
        b.entities = [B.insert("B", at: (0, 0), array: (columns: 3, rows: 1, dx: 2, dy: 0))]
        let one = try Self.read(b)
        let two = try Self.read(b)
        #expect(one.identities == two.identities)
    }
}

@Suite("Hatches and leaders inside blocks")
struct BlockHatchTests {
    typealias B = DXFBuilder

    static let polylineHatch: DXFBuilder.Record = [
        (0, "HATCH"), (8, "0"), (2, "SOLID"), (70, "1"), (91, "1"), (92, "7"), (72, "0"),
        (73, "1"), (93, "2"), (10, "0"), (20, "0"), (10, "1"), (20, "0"), (97, "0"),
    ]

    @Test("a hatch and a leader inside a block come out with the reference")
    func expandedHatchAndLeader() throws {
        var b = DXFBuilder()
        let leader: DXFBuilder.Record = [
            (0, "LEADER"), (8, "0"), (73, "3"), (76, "2"), (10, "0"), (20, "0"), (10, "1"),
            (20, "0"),
        ]
        b.blocks = [("B", (0, 0), [Self.polylineHatch, leader])]
        b.entities = [B.insert("B", at: (10, 0), layer: "P", handle: "A1")]
        let d = try DXF.read(text: b.text(), options: .init(expandBlocks: true))
        #expect(d.entities.count == 2 && d.counts.hatch == 1 && d.counts.leader == 1)
        #expect(d.identities.map(\.via) == [["A1"], ["A1"]])
        guard case .hatch(let h) = d.entities[0], case .leader(let l) = d.entities[1] else {
            Issue.record("expected a hatch then a leader")
            return
        }
        #expect(h.layer == "P" && l.layer == "P")
        #expect(l.vertices[0] == DXF.Point(10, 0))
        if case .polyline(let v, _) = h.paths[0].geometry {
            #expect(v[0].point == DXF.Point(10, 0))
        } else {
            Issue.record("not a polyline path")
        }
    }

    @Test("a mirrored reference reverses the way a hatch path travels an arc edge")
    func mirroredArcEdge() throws {
        var b = DXFBuilder()
        let hatch: DXFBuilder.Record = [
            (0, "HATCH"), (8, "0"), (2, "SOLID"), (70, "1"), (91, "1"), (92, "1"), (93, "1"),
            (72, "2"), (10, "0"), (20, "0"), (40, "1"), (50, "0"), (51, "90"), (73, "1"),
            (97, "0"),
        ]
        b.blocks = [("B", (0, 0), [hatch])]
        b.entities = [B.insert("B", at: (0, 0), scale: (-1, 1))]
        let d = try DXF.read(text: b.text(), options: .init(expandBlocks: true))
        guard case .hatch(let h) = d.entities[0], case .edges(let edges) = h.paths[0].geometry,
            case .arc(_, let r, let s, let e, let ccw) = edges[0]
        else {
            Issue.record("expected an arc edge")
            return
        }
        // The quarter arc 0 to 90 degrees becomes 90 to 180, travelled the other way.
        #expect(abs(r - 1) < 1e-12 && abs(s - 90) < 1e-9 && abs(e - 180) < 1e-9)
        #expect(!ccw)
    }

    @Test("a non-uniform scale turns an arc edge into an ellipse edge")
    func scaledArcEdge() throws {
        var b = DXFBuilder()
        let hatch: DXFBuilder.Record = [
            (0, "HATCH"), (8, "0"), (2, "SOLID"), (70, "1"), (91, "1"), (92, "1"), (93, "1"),
            (72, "2"), (10, "0"), (20, "0"), (40, "1"), (50, "0"), (51, "360"), (73, "1"),
            (97, "0"),
        ]
        b.blocks = [("B", (0, 0), [hatch])]
        b.entities = [B.insert("B", at: (0, 0), scale: (2, 1))]
        let d = try DXF.read(text: b.text(), options: .init(expandBlocks: true))
        guard case .hatch(let h) = d.entities[0], case .edges(let edges) = h.paths[0].geometry,
            case .ellipse(_, let major, let ratio, let s, let e, _) = edges[0]
        else {
            Issue.record("expected an ellipse edge")
            return
        }
        #expect(abs(hypot(major.x, major.y) - 2) < 1e-9 && abs(ratio - 0.5) < 1e-9)
        #expect(abs(e - s - 2 * .pi) < 1e-9)
    }

    @Test("a bulged hatch path cannot pass a non-uniform scale and is reported")
    func bulgedPath() throws {
        var b = DXFBuilder()
        let hatch: DXFBuilder.Record = [
            (0, "HATCH"), (8, "0"), (2, "SOLID"), (70, "1"), (91, "1"), (92, "7"), (72, "1"),
            (73, "1"), (93, "2"), (10, "0"), (20, "0"), (42, "1"), (10, "2"), (20, "0"),
            (97, "0"),
        ]
        b.blocks = [("B", (0, 0), [hatch, B.line((0, 0), (1, 0))])]
        b.entities = [B.insert("B", at: (0, 0), scale: (2, 1))]
        let d = try DXF.read(text: b.text(), options: .init(expandBlocks: true))
        #expect(d.entities.count == 1)
        #expect(d.warnings.contains(.notTransformed(type: "HATCH", count: 1)))
    }

    @Test("expanded entities keep the counts and the parallel arrays in step")
    func countsFollowExpansion() throws {
        var b = DXFBuilder()
        b.blocks = [("B", (0, 0), [B.line((0, 0), (1, 0)), Self.polylineHatch])]
        b.entities = [
            B.insert("B", at: (0, 0), array: (columns: 3, rows: 1, dx: 2, dy: 0)),
            B.line((0, 0), (9, 9)),
        ]
        let d = try DXF.read(text: b.text(), options: .init(expandBlocks: true))
        #expect(d.counts.line == 4 && d.counts.hatch == 3 && d.counts.total == d.entities.count)
        #expect(d.identities.count == d.entities.count)
        #expect(d.entityLineTypes.count == d.entities.count)
    }
}

@Suite("Block references in a mirrored coordinate system")
struct ExtrusionBlockTests {
    typealias B = DXFBuilder

    @Test("an extrusion of -z mirrors the block's x axis")
    func mirroredOCS() throws {
        var b = DXFBuilder()
        b.blocks = [("B", (0, 0), [B.line((0, 0), (1, 0))])]
        var insert = B.insert("B", at: (10, 0))
        insert += [(210, "0.0"), (220, "0.0"), (230, "-1.0")]
        b.entities = [insert]
        let d = try DXF.read(text: b.text(), options: .init(expandBlocks: true))
        if case .line(let a, let e, _, _) = d.entities[0] {
            #expect(BlockTests.close(a, -10, 0) && BlockTests.close(e, -11, 0))
        } else {
            Issue.record("not a line")
        }
        #expect(d.references[0].extrusion == DXF.Point(0, 0, -1))
        #expect(d.warnings.isEmpty)
    }

    @Test("a tilted extrusion is reported")
    func tilted() throws {
        var b = DXFBuilder()
        b.blocks = [("B", (0, 0), [B.line((0, 0), (1, 0))])]
        var insert = B.insert("B", at: (0, 0))
        insert += [(210, "1.0"), (220, "0.0"), (230, "0.0")]
        b.entities = [insert]
        let d = try DXF.read(text: b.text(), options: .init(expandBlocks: true))
        #expect(d.warnings.contains(.unsupportedExtrusion(count: 1)))
    }
}

@Suite("Paper space")
struct PaperSpaceTests {
    typealias B = DXFBuilder

    static func drawing() -> String {
        var b = DXFBuilder()
        var paper = B.line((0, 0), (5, 5), handle: "P1")
        paper.insert((67, "1"), at: 1)
        b.entities = [B.line((0, 0), (1, 1), handle: "M1"), paper]
        return b.text()
    }

    @Test("paper-space entities are counted, and read unless asked to skip them")
    func countedAndRead() throws {
        let d = try DXF.read(text: Self.drawing())
        #expect(d.paperSpace == ["LINE": 1])
        #expect(d.entities.count == 2)
    }

    @Test("skipPaperSpace leaves them out and keeps the positions of the rest")
    func skipped() throws {
        let d = try DXF.read(text: Self.drawing(), options: .init(skipPaperSpace: true))
        #expect(d.paperSpace == ["LINE": 1])
        #expect(d.entities.count == 1)
        #expect(d.identities.map(\.id) == ["M1"])
    }
}
