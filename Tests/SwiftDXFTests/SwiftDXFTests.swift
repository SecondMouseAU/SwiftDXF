import Testing
import Foundation
@testable import SwiftDXF

@Suite("DXF reading")
struct SwiftDXFTests {

    /// Minimal ASCII-DXF wrapper: header with $ACADVER, then an ENTITIES section holding `body`.
    static func doc(_ body: String, acadver: String = "AC1009") -> String {
        """
        0
        SECTION
        2
        HEADER
        9
        $ACADVER
        1
        \(acadver)
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        \(body)
        0
        ENDSEC
        0
        EOF
        """
    }

    @Test("reads each core entity type with coordinates and counts")
    func coreEntities() throws {
        let body = """
        0
        LINE
        8
        L1
        62
        2
        10
        0.0
        20
        0.0
        11
        10.0
        21
        5.0
        0
        CIRCLE
        8
        0
        10
        3.0
        20
        4.0
        40
        2.0
        0
        ARC
        10
        0.0
        20
        0.0
        40
        5.0
        50
        0.0
        51
        90.0
        0
        ELLIPSE
        10
        1.0
        20
        1.0
        11
        4.0
        21
        0.0
        40
        0.5
        41
        0.0
        42
        6.2831853
        0
        POINT
        10
        2.0
        20
        3.0
        0
        TEXT
        40
        2.5
        10
        0.0
        20
        0.0
        1
        AB
        """
        let dwg = try DXF.read(text: Self.doc(body))
        #expect(dwg.version == "AC1009")
        #expect(dwg.counts.line == 1 && dwg.counts.circle == 1 && dwg.counts.arc == 1)
        #expect(dwg.counts.ellipse == 1 && dwg.counts.point == 1 && dwg.counts.text == 1)
        #expect(dwg.counts.total == 6)

        guard case let .line(a, b, layer, color) = dwg.entities[0] else { Issue.record("not a line"); return }
        #expect(a == DXF.Point(0, 0) && b == DXF.Point(10, 5) && layer == "L1" && color == 2)

        guard case let .circle(c, r, _, col) = dwg.entities[1] else { Issue.record("not a circle"); return }
        #expect(c == DXF.Point(3, 4) && r == 2 && col == 256)   // no group 62 → BYLAYER

        guard case let .arc(ac, ar, s, e, _, _) = dwg.entities[2] else { Issue.record("not an arc"); return }
        #expect(ac == DXF.Point(0, 0) && ar == 5 && s == 0 && e == 90)

        guard case let .ellipse(ec, major, ratio, _, end, _, _) = dwg.entities[3] else { Issue.record("not an ellipse"); return }
        #expect(ec == DXF.Point(1, 1) && major == DXF.Point(4, 0) && ratio == 0.5 && abs(end - 2 * .pi) < 1e-4)

        guard case let .point(p, _, _) = dwg.entities[4] else { Issue.record("not a point"); return }
        #expect(p == DXF.Point(2, 3))

        guard case let .text(tp, h, _, str, _, _) = dwg.entities[5] else { Issue.record("not text"); return }
        #expect(tp == DXF.Point(0, 0) && h == 2.5 && str == "AB")
    }

    @Test("bounds span all geometry")
    func bounds() throws {
        let dwg = try DXF.read(text: Self.doc("""
        0
        LINE
        10
        -5.0
        20
        0.0
        11
        20.0
        21
        7.0
        """))
        let b = try #require(dwg.bounds)
        #expect(b.min.x == -5 && b.max.x == 20 && b.max.y == 7)
    }

    @Test("LWPOLYLINE flattens to vertices with closed flag")
    func lwpolyline() throws {
        let dwg = try DXF.read(text: Self.doc("""
        0
        LWPOLYLINE
        90
        3
        70
        1
        10
        0.0
        20
        0.0
        10
        4.0
        20
        0.0
        10
        4.0
        20
        3.0
        """))
        guard case let .polyline(verts, closed, _, _) = dwg.entities.first else { Issue.record("not a polyline"); return }
        #expect(verts.count == 3 && closed)
        #expect(verts[1].point == DXF.Point(4, 0) && verts[2].point == DXF.Point(4, 3))
    }

    @Test("LWPOLYLINE binds bulge to the right vertex")
    func lwpolylineBulge() throws {
        let dwg = try DXF.read(text: Self.doc("""
        0
        LWPOLYLINE
        90
        3
        70
        0
        10
        0.0
        20
        0.0
        42
        0.5
        10
        4.0
        20
        0.0
        10
        4.0
        20
        3.0
        """))
        guard case let .polyline(verts, _, _, _) = dwg.entities.first else { Issue.record("not a polyline"); return }
        #expect(verts.count == 3)
        #expect(verts[0].bulge == 0.5 && verts[1].bulge == 0 && verts[2].bulge == 0)   // bulge stays on vertex 0
    }

    @Test("header $INSUNITS and $EXTMIN/$EXTMAX are read")
    func headerVars() throws {
        let text = """
        0
        SECTION
        2
        HEADER
        9
        $INSUNITS
        70
        4
        9
        $EXTMIN
        10
        -5.0
        20
        -7.0
        30
        0.0
        9
        $EXTMAX
        10
        100.0
        20
        50.0
        30
        0.0
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        ENDSEC
        0
        EOF
        """
        let dwg = try DXF.read(text: text)
        #expect(dwg.insUnits == 4)   // millimetres
        #expect(dwg.extMin == DXF.Point(-5, -7) && dwg.extMax == DXF.Point(100, 50))
    }

    @Test("old-style POLYLINE consumes VERTEX run and SEQEND")
    func polylineVertices() throws {
        let dwg = try DXF.read(text: Self.doc("""
        0
        POLYLINE
        66
        1
        70
        0
        0
        VERTEX
        10
        0.0
        20
        0.0
        0
        VERTEX
        10
        5.0
        20
        5.0
        0
        SEQEND
        0
        LINE
        10
        0.0
        20
        0.0
        11
        1.0
        21
        1.0
        """))
        // The VERTEX/SEQEND run must not be mistaken for extra entities.
        #expect(dwg.counts.polyline == 1 && dwg.counts.line == 1 && dwg.counts.total == 2)
        guard case let .polyline(verts, _, _, _) = dwg.entities[0] else { Issue.record("not a polyline"); return }
        #expect(verts.map(\.point) == [DXF.Point(0, 0), DXF.Point(5, 5)])
    }

    @Test("unmodelled entities are skipped, not fatal")
    func skipsUnknown() throws {
        let dwg = try DXF.read(text: Self.doc("""
        0
        SPLINE
        10
        0.0
        20
        0.0
        0
        LINE
        10
        0.0
        20
        0.0
        11
        1.0
        21
        1.0
        """))
        #expect(dwg.counts.total == 1 && dwg.counts.line == 1)
    }

    @Test("decodes \\U+XXXX unicode escapes in text")
    func unicodeEscape() throws {
        let dwg = try DXF.read(text: Self.doc("""
        0
        TEXT
        10
        0.0
        20
        0.0
        40
        2.5
        1
        x\\U+00B1y
        """))
        guard case let .text(_, _, _, str, _, _) = dwg.entities.first else { Issue.record("not text"); return }
        #expect(str == "x±y")
    }

    @Test("CRLF line endings and leading-space group codes parse")
    func crlfAndPadding() throws {
        // R12 writers pad group codes ("  0", " 10") and use CRLF.
        let text = "  0\r\nSECTION\r\n  2\r\nENTITIES\r\n  0\r\nLINE\r\n 10\r\n0.0\r\n 20\r\n0.0\r\n 11\r\n2.0\r\n 21\r\n0.0\r\n  0\r\nENDSEC\r\n  0\r\nEOF\r\n"
        let dwg = try DXF.read(text: text)
        #expect(dwg.counts.line == 1)
        guard case let .line(_, b, _, _) = dwg.entities.first else { Issue.record("not a line"); return }
        #expect(b == DXF.Point(2, 0))
    }

    @Test("sniff + errors")
    func sniffAndErrors() {
        #expect(DXF.looksLikeDXF(Data(Self.doc("").utf8)))
        #expect(!DXF.looksLikeDXF(Data("just some text\nnot a drawing".utf8)))
        #expect(DXF.isBinary(Data("AutoCAD Binary DXF\r\n".utf8)))
        #expect(throws: DXF.Error.empty) { try DXF.read(data: Data()) }
        #expect(throws: DXF.Error.notDXF) { try DXF.read(text: "hello\nworld") }
        #expect(throws: DXF.Error.binaryUnsupported) {
            try DXF.read(data: Data("AutoCAD Binary DXF\r\n\u{1a}\u{0}garbage".utf8))
        }
    }
}
