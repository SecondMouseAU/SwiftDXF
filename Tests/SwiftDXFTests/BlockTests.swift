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
        #expect(d.references[0].identity.id == "#A1")
        #expect(d.blocks["B"]?.entities.count == 1)
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
        #expect(d.identities[0].via == ["#A1"] && d.identities[0].blocks == ["B"])
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
        #expect(d.identities[0].via == ["#A1", "#B1"])
        #expect(d.identities[0].blocks == ["outer", "inner"])
        #expect(d.identities[0].id == "#A1/#B1/#C1")
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
        #expect(d.identities.map(\.id).contains("#A1[1,1]/#C1"))
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
        #expect(d.lineTypeName(at: 0) == "HIDDEN")
        #expect(d.lineTypeName(at: 2) == "HIDDEN")  // by layer: PARTS is HIDDEN
        #expect(d.lineTypeName(at: 1) == "Continuous")
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
            #expect(m.measurementDirection == DXF.Point2(0, 1))
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

    @Test("the model and paper space blocks are not kept")
    func specialBlocks() throws {
        var b = DXFBuilder()
        b.blocks = [
            ("*Model_Space", (0, 0), []), ("*Paper_Space", (0, 0), []),
            ("REAL", (0, 0), [B.line((0, 0), (1, 0))]),
        ]
        let d = try Self.read(b, expand: false)
        #expect(Array(d.blocks.keys) == ["REAL"])
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

@Suite("Layers, line types, hatches and leaders")
struct DrawingTablesTests {
    typealias B = DXFBuilder

    @Test("the layer and line type tables are read")
    func tables() throws {
        var b = DXFBuilder()
        b.lineTypes = [
            [(2, "Continuous"), (70, "0"), (3, "Solid line"), (72, "65"), (73, "0"), (40, "0.0")],
            [
                (2, "HIDDEN"), (70, "0"), (3, "Hidden __ __"), (72, "65"), (73, "2"),
                (40, "9.525"), (49, "6.35"), (74, "0"), (49, "-3.175"), (74, "0"),
            ],
        ]
        b.layers = [
            [(2, "0"), (70, "0"), (62, "7"), (6, "Continuous")],
            [(2, "HID"), (70, "0"), (62, "1"), (6, "HIDDEN")],
            [(2, "OFF"), (70, "0"), (62, "-3"), (6, "Continuous")],
            [(2, "ICE"), (70, "5"), (62, "2"), (6, "Continuous")],
        ]
        b.entities = [
            B.line((0, 0), (1, 0), layer: "HID"), B.line((0, 0), (2, 0), layer: "0"),
            B.line((0, 0), (3, 0), layer: "0", lineType: "HIDDEN"),
        ]
        let d = try DXF.read(text: b.text())
        #expect(d.layers.count == 4)
        #expect(d.layers["HID"]?.lineType == "HIDDEN" && d.layers["HID"]?.color == 1)
        #expect(d.layers["OFF"]?.isOff == true && d.layers["OFF"]?.color == 3)
        #expect(d.layers["OFF"]?.isVisible == false)
        #expect(d.layers["ICE"]?.isFrozen == true && d.layers["ICE"]?.isLocked == true)
        #expect(d.layers["0"]?.isVisible == true)
        #expect(d.lineTypeTable["HIDDEN"]?.pattern == [6.35, -3.175])
        #expect(d.lineTypeTable["HIDDEN"]?.isContinuous == false)
        #expect(d.lineTypeTable["Continuous"]?.isContinuous == true)

        // The line type of every entity, resolved through the layer when it says by layer.
        #expect(d.lineTypeName(at: 0) == "HIDDEN")
        #expect(d.lineTypeName(at: 1) == "Continuous")
        #expect(d.lineTypeName(at: 2) == "HIDDEN")
        #expect(d.lineType(at: 0)?.pattern.count == 2)
        #expect(d.layer(named: "hid")?.name == "HID")
    }

    @Test("a polyline-path hatch reads its pattern and loop")
    func hatchPolyline() throws {
        var b = DXFBuilder()
        b.entities = [
            [
                (0, "HATCH"), (5, "9A"), (8, "SECTION"), (10, "0"), (20, "0"), (30, "0"),
                (210, "0"), (220, "0"), (230, "1"), (2, "ANSI31"), (70, "0"), (71, "1"),
                (91, "1"), (92, "7"), (72, "0"), (73, "1"), (93, "3"), (10, "0"), (20, "0"),
                (10, "10"), (20, "0"), (10, "10"), (20, "5"), (97, "0"), (75, "0"), (76, "1"),
            ]
        ]
        let d = try DXF.read(text: b.text())
        #expect(d.hatches.count == 1 && d.entities.isEmpty)
        guard let h = d.hatches.first else { return }
        #expect(h.patternName == "ANSI31" && !h.isSolid && h.isAssociative)
        #expect(h.layer == "SECTION" && h.identity.id == "#9A")
        #expect(h.loops.count == 1)
        if case .polyline(let v, let closed) = h.loops[0].content {
            #expect(
                closed && v.map(\.point) == [DXF.Point(0, 0), DXF.Point(10, 0), DXF.Point(10, 5)])
        } else {
            Issue.record("not a polyline loop")
        }
        #expect(h.loops[0].isExternal)
        #expect(d.skipped["HATCH"] == 1)
    }

    @Test("an edge-path hatch reads lines and arcs across two loops, and a solid fill")
    func hatchEdges() throws {
        var b = DXFBuilder()
        b.entities = [
            [
                (0, "HATCH"), (8, "0"), (2, "SOLID"), (70, "1"), (71, "0"), (91, "2"),
                (92, "1"), (93, "2"), (72, "1"), (10, "0"), (20, "0"), (11, "4"), (21, "0"),
                (72, "2"), (10, "2"), (20, "0"), (40, "2"), (50, "0"), (51, "180"), (73, "1"),
                (97, "2"), (330, "AA"), (330, "AB"),
                (92, "16"), (93, "1"), (72, "3"), (10, "1"), (20, "1"), (11, "2"), (21, "0"),
                (40, "0.5"), (50, "0"), (51, "360"), (73, "1"), (97, "0"),
            ]
        ]
        let d = try DXF.read(text: b.text())
        guard let h = d.hatches.first else {
            Issue.record("no hatch")
            return
        }
        #expect(h.isSolid && h.patternName == "SOLID" && h.loops.count == 2)
        if case .edges(let e) = h.loops[0].content {
            #expect(e.count == 2)
            #expect(e[0] == .line(a: DXF.Point2(0, 0), b: DXF.Point2(4, 0)))
            #expect(
                e[1]
                    == .arc(
                        center: DXF.Point2(2, 0), radius: 2, startDeg: 0, endDeg: 180,
                        counterClockwise: true))
        } else {
            Issue.record("not edges")
        }
        if case .edges(let e) = h.loops[1].content,
            case .ellipse(_, _, let ratio, _, let end, _) = e[0]
        {
            #expect(ratio == 0.5 && end == 360)
        } else {
            Issue.record("not an ellipse edge")
        }
        #expect(h.loops[1].isOutermost)
    }

    @Test("a hatch cut short keeps the loops it read")
    func hatchTruncated() throws {
        var b = DXFBuilder()
        b.entities = [
            [
                (0, "HATCH"), (8, "0"), (2, "X"), (70, "0"), (91, "3"), (92, "1"), (93, "1"),
                (72, "9"),
            ]
        ]
        let d = try DXF.read(text: b.text())
        #expect(d.hatches.count == 1 && d.hatches[0].loops.isEmpty)
    }

    @Test("a leader reads its vertices and the handle of its annotation")
    func leader() throws {
        var b = DXFBuilder()
        b.entities = [
            [
                (0, "LEADER"), (5, "3AB"), (8, "0"), (3, "STD"), (71, "1"), (72, "0"), (73, "0"),
                (76, "3"), (10, "1"), (20, "2"), (30, "0"), (10, "3"), (20, "4"), (30, "0"),
                (10, "5"), (20, "4"), (30, "0"), (340, "d1"),
            ]
        ]
        let d = try DXF.read(text: b.text())
        guard let l = d.leaders.first else {
            Issue.record("no leader")
            return
        }
        #expect(l.vertices == [DXF.Point(1, 2), DXF.Point(3, 4), DXF.Point(5, 4)])
        #expect(l.hasArrowhead && !l.isSpline && l.annotation == .text)
        #expect(l.annotationHandle == "D1" && l.styleName == "STD" && l.identity.id == "#3AB")
    }

    @Test("a leader's annotation handle finds the entity it is attached to")
    func annotationLookup() throws {
        var b = DXFBuilder()
        b.entities = [
            B.line((0, 0), (1, 0), handle: "D1"),
            [
                (0, "LEADER"), (8, "0"), (73, "0"), (76, "2"), (10, "0"), (20, "0"), (10, "1"),
                (20, "1"), (340, "D1"),
            ],
        ]
        let d = try DXF.read(text: b.text())
        if let handle = d.leaders.first?.annotationHandle {
            #expect(d.index(ofHandle: handle.lowercased()) == 0)
        } else {
            Issue.record("no annotation handle")
        }
    }

    @Test("a hatch and a leader inside a block come out with the reference")
    func expandedHatchAndLeader() throws {
        var b = DXFBuilder()
        let hatch: DXFBuilder.Record = [
            (0, "HATCH"), (8, "0"), (2, "SOLID"), (70, "1"), (91, "1"), (92, "7"), (72, "0"),
            (73, "1"), (93, "2"), (10, "0"), (20, "0"), (10, "1"), (20, "0"), (97, "0"),
        ]
        let leader: DXFBuilder.Record = [
            (0, "LEADER"), (8, "0"), (73, "3"), (76, "2"), (10, "0"), (20, "0"), (10, "1"),
            (20, "0"),
        ]
        b.blocks = [("B", (0, 0), [hatch, leader])]
        b.entities = [B.insert("B", at: (10, 0), layer: "P", handle: "A1")]
        let d = try DXF.read(text: b.text(), options: .init(expandBlocks: true))
        #expect(d.hatches.count == 1 && d.leaders.count == 1)
        #expect(d.hatches[0].layer == "P" && d.hatches[0].identity.via == ["#A1"])
        #expect(d.leaders[0].vertices[0] == DXF.Point(10, 0))
        if case .polyline(let v, _) = d.hatches[0].loops[0].content {
            #expect(v[0].point == DXF.Point(10, 0))
        }
    }
}
