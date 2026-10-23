import Foundation
import Testing

@testable import SwiftDXF

/// SPLINE reading and flattening.
///
/// Reference values come from `ezdxf` (`tools/spline_fixtures.py`),
/// which also wrote the DXF files in `Fixtures/`.
@Suite("DXF splines")
struct SplineTests {

    typealias XYZ = (Double, Double, Double)

    struct Reference {
        var file: String
        var degree: Int
        var flags: Int
        var control: [XYZ]
        var knots: [Double]
        var weights: [Double]
        /// Parameters at which ezdxf evaluated the curve, and the points it returned.
        var ts: [Double]
        var points: [XYZ]
    }

    static let cubicClamped = Reference(
        file: "cubic_clamped", degree: 3, flags: 8,
        control: [
            (0.0, 0.0, 0.0),
            (1.0, 3.0, 0.0),
            (3.0, 4.0, 0.0),
            (5.0, 1.0, 0.0),
            (7.0, 3.0, 0.0),
            (9.0, 0.0, 0.0),
        ],
        knots: [0.0, 0.0, 0.0, 0.0, 1.0, 2.0, 3.0, 3.0, 3.0, 3.0], weights: [],
        ts: [0.0, 0.375, 0.75, 1.125, 1.5, 1.875, 2.25, 2.625, 3.0],
        points: [
            (0.0, 0.0, 0.0),
            (1.1162109375, 2.41259765625, 0.0),
            (2.1796875, 3.26953125, 0.0),
            (3.138671875, 3.12451171875, 0.0),
            (4.0, 2.53125, 0.0),
            (4.861328125, 2.04345703125, 0.0),
            (5.8359375, 2.109375, 0.0),
            (7.1279296875, 1.951171875, 0.0),
            (9.0, 0.0, 0.0),
        ])

    static let rationalArc = Reference(
        file: "rational_arc", degree: 2, flags: 12,
        control: [
            (1.0, 0.0, 0.0),
            (1.0, 1.0, 0.0),
            (0.0, 1.0, 0.0),
        ],
        knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0], weights: [1.0, 0.7071067811865476, 1.0],
        ts: [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0],
        points: [
            (1.0, 0.0, 0.0),
            (0.9833053684165743, 0.18196305241214472, 0.0),
            (0.9297883010624304, 0.3680947095618728, 0.0),
            (0.8369955112186513, 0.5472097533851425, 0.0),
            (0.7071067811865476, 0.7071067811865476, 0.0),
            (0.5472097533851425, 0.8369955112186513, 0.0),
            (0.3680947095618728, 0.9297883010624304, 0.0),
            (0.18196305241214472, 0.9833053684165743, 0.0),
            (0.0, 1.0, 0.0),
        ])

    static let rationalCubic3d = Reference(
        file: "rational_cubic_3d", degree: 3, flags: 4,
        control: [
            (0.0, 0.0, 0.0),
            (2.0, 5.0, 1.0),
            (5.0, 5.0, 2.0),
            (8.0, 0.0, 3.0),
            (10.0, 4.0, 1.0),
        ],
        knots: [0.0, 0.0, 0.0, 0.0, 0.4, 1.0, 1.0, 1.0, 1.0], weights: [1.0, 2.5, 0.5, 3.0, 1.0],
        ts: [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0],
        points: [
            (0.0, 0.0, 0.0),
            (1.7702549006489596, 4.0693784705961065, 0.864052987221516),
            (2.5592417061611377, 4.541864139020537, 1.1769352290679305),
            (3.865646132124545, 3.795422456713978, 1.6218325035297614),
            (5.699445983379502, 2.296398891966759, 2.225761772853186),
            (7.060185185185185, 1.191358024691358, 2.6126543209876543),
            (7.844120972300735, 0.8117580553985303, 2.6895138496325606),
            (8.458673950636692, 1.1903002672535765, 2.4340315988052192),
            (10.0, 4.0, 1.0),
        ])

    static let periodicCubic = Reference(
        file: "periodic_cubic", degree: 3, flags: 3,
        control: [
            (0.0, 0.0, 0.0),
            (4.0, 0.0, 0.0),
            (4.0, 4.0, 0.0),
            (0.0, 4.0, 0.0),
            (0.0, 0.0, 0.0),
            (4.0, 0.0, 0.0),
            (4.0, 4.0, 0.0),
        ],
        knots: [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0], weights: [],
        ts: [3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 6.999999999999],
        points: [
            (3.333333333333333, 0.6666666666666666, 0.0),
            (3.833333333333333, 2.0, 0.0),
            (3.333333333333333, 3.333333333333333, 0.0),
            (1.9999999999999998, 3.833333333333333, 0.0),
            (0.6666666666666666, 3.333333333333333, 0.0),
            (0.16666666666666666, 1.9999999999999998, 0.0),
            (0.6666666666666666, 0.6666666666666666, 0.0),
            (2.0, 0.16666666666666666, 0.0),
            (3.333333333331333, 0.6666666666646666, 0.0),
        ])

    static let linear = Reference(
        file: "linear", degree: 1, flags: 8,
        control: [
            (0.0, 0.0, 0.0),
            (2.0, 1.0, 0.0),
            (4.0, 0.0, 0.0),
        ],
        knots: [0.0, 0.0, 1.0, 2.0, 2.0], weights: [],
        ts: [0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0],
        points: [
            (0.0, 0.0, 0.0),
            (0.5, 0.25, 0.0),
            (1.0, 0.5, 0.0),
            (1.5, 0.75, 0.0),
            (2.0, 1.0, 0.0),
            (2.5, 0.75, 0.0),
            (3.0, 0.5, 0.0),
            (3.5, 0.25, 0.0),
            (4.0, 0.0, 0.0),
        ])

    static let all = [cubicClamped, rationalArc, rationalCubic3d, periodicCubic, linear]

    static func load(_ name: String) throws -> DXF.Spline {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "dxf", subdirectory: "Fixtures"))
        let dwg = try DXF.read(contentsOf: url)
        #expect(dwg.counts.spline == 1 && dwg.counts.total == 1 && dwg.skipped.isEmpty)
        guard case .spline(let s) = try #require(dwg.entities.first) else {
            Issue.record("not a spline")
            throw DXF.Error.notDXF
        }
        return s
    }

    static func near(_ p: DXF.Point, _ q: XYZ, _ eps: Double) -> Bool {
        abs(p.x - q.0) <= eps && abs(p.y - q.1) <= eps && abs(p.z - q.2) <= eps
    }

    /// Largest distance from the exact curve (dense sampling) to the polyline.
    static func maxDeviation(_ s: DXF.Spline, _ poly: [DXF.Point]) -> Double {
        guard let c = s.curve() else { return 0 }
        var worst = 0.0
        let spans = zip(c.knots, c.knots.dropFirst()).filter {
            $0 < $1 && $0 >= c.domain.lowerBound && $1 <= c.domain.upperBound
        }
        for (a, b) in spans {
            for i in 0...1000 {
                let p = c.point(at: a + (b - a) * Double(i) / 1000)
                let d = zip(poly, poly.dropFirst()).map { DXF.Spline.segmentDistance(p, $0, $1) }
                worst = max(worst, d.min() ?? 0)
            }
        }
        return worst
    }

    @Test("control data read from ezdxf-written files matches ezdxf", arguments: all)
    func controlData(_ ref: Reference) throws {
        let s = try Self.load(ref.file)
        #expect(s.degree == ref.degree && s.flags == ref.flags)
        #expect(s.layer == "CURVES" && s.color == 5)
        #expect(s.knots == ref.knots && s.weights == ref.weights && s.fitPoints.isEmpty)
        #expect(s.controlPoints.count == ref.control.count)
        for (p, q) in zip(s.controlPoints, ref.control) { #expect(Self.near(p, q, 0)) }
    }

    @Test("NURBS evaluation matches ezdxf at sampled parameters", arguments: all)
    func evaluation(_ ref: Reference) throws {
        let s = try Self.load(ref.file)
        for (t, q) in zip(ref.ts, ref.points) {
            let p = try #require(s.point(at: t))
            #expect(Self.near(p, q, 1e-9), "t=\(t) got \(p) expected \(q)")
        }
    }

    @Test("flag helpers decode group 70")
    func flagBits() throws {
        let s = try Self.load("periodic_cubic")
        #expect(s.isClosed && s.isPeriodic && !s.isRational && !s.isPlanar)
        let r = try Self.load("rational_arc")
        #expect(!r.isClosed && r.isRational && r.isPlanar)
    }

    @Test("flattening stays within tolerance of the exact curve", arguments: all)
    func flatteningDeviation(_ ref: Reference) throws {
        let s = try Self.load(ref.file)
        var previousCount = 0
        for tol in [0.1, 0.01, 0.001, 0.0001] {
            let poly = s.flattened(tolerance: tol)
            let dev = Self.maxDeviation(s, poly)
            print("flatten \(ref.file) tol=\(tol) points=\(poly.count) maxDeviation=\(dev)")
            #expect(dev <= tol, "\(ref.file) tol=\(tol) deviation \(dev)")
            #expect(poly.count >= previousCount)
            previousCount = poly.count
        }
    }

    @Test("flattened endpoints are the curve endpoints; closed splines close")
    func flatteningEnds() throws {
        let c = try Self.load("cubic_clamped")
        let poly = c.flattened(tolerance: 0.01)
        #expect(Self.near(poly[0], (0, 0, 0), 1e-12))
        #expect(Self.near(poly[poly.count - 1], (9, 0, 0), 1e-12))
        let p = try Self.load("periodic_cubic").flattened(tolerance: 0.01)
        #expect(DXF.Spline.distance(p[0], p[p.count - 1]) < 1e-9)
        #expect(Self.near(p[0], (10.0 / 3, 2.0 / 3, 0), 1e-9))
    }

    @Test("a straight degree-1 spline flattens to its control polygon")
    func linearSpline() throws {
        let poly = try Self.load("linear").flattened(tolerance: 0.001)
        #expect(Self.near(poly[0], (0, 0, 0), 1e-12))
        #expect(poly.contains { Self.near($0, (2, 1, 0), 1e-9) })
        #expect(Self.near(poly[poly.count - 1], (4, 0, 0), 1e-12))
    }

    @Test("asPolyline carries layer and colour")
    func asPolyline() throws {
        let s = try Self.load("rational_arc")
        guard
            case .polyline(let v, let closed, let layer, let color) = s.asPolyline(tolerance: 0.01)
        else {
            Issue.record("not a polyline")
            return
        }
        #expect(v.count == s.flattened(tolerance: 0.01).count && !closed)
        #expect(layer == "CURVES" && color == 5)
    }

    // MARK: hand-authored documents

    static func splineBody(
        degree: Int?, flags: Int = 8, knots: [Double] = [], weights: [Double] = [],
        control: [XYZ] = [], fit: [XYZ] = []
    ) -> String {
        var s = "0\nSPLINE\n8\nS\n"
        if let degree { s += "71\n\(degree)\n" }
        s += "70\n\(flags)\n"
        for k in knots { s += "40\n\(k)\n" }
        for w in weights { s += "41\n\(w)\n" }
        for p in control { s += "10\n\(p.0)\n20\n\(p.1)\n30\n\(p.2)\n" }
        for p in fit { s += "11\n\(p.0)\n21\n\(p.1)\n31\n\(p.2)\n" }
        return s
    }

    static func spline(_ body: String) throws -> DXF.Spline {
        let dwg = try DXF.read(text: SwiftDXFTests.doc(body))
        guard case .spline(let s) = try #require(dwg.entities.first) else {
            throw DXF.Error.notDXF
        }
        return s
    }

    @Test("fit points are read; with no control points they drive a Catmull-Rom fallback")
    func fitPointFallback() throws {
        let fit: [XYZ] = [(0, 0, 0), (2, 3, 0), (5, 3, 0), (7, 0, 0)]
        let s = try Self.spline(Self.splineBody(degree: 3, flags: 8, fit: fit))
        #expect(s.controlPoints.isEmpty && s.fitPoints.count == 4)
        let poly = s.flattened(tolerance: 0.01)
        for q in fit { #expect(poly.contains { Self.near($0, q, 1e-12) }) }
        #expect(poly.count > 8)
        #expect(s.parameterDomain == nil && s.point(at: 0) == nil)
    }

    @Test("control points win over fit points when both are present")
    func controlBeatsFit() throws {
        let s = try Self.spline(
            Self.splineBody(
                degree: 1, knots: [0, 0, 1, 1], control: [(0, 0, 0), (1, 0, 0)],
                fit: [(0, 0, 0), (0.5, 9, 0), (1, 0, 0)]))
        let poly = s.flattened(tolerance: 0.01)
        #expect(poly.allSatisfy { $0.y == 0 })
    }

    @Test("a missing 30 tag leaves z at zero and a missing degree defaults to 3")
    func twoDimensional() throws {
        let s = try Self.spline(
            "0\nSPLINE\n10\n1\n20\n2\n10\n3\n20\n4\n10\n5\n20\n6\n10\n7\n20\n8\n")
        #expect(s.degree == 3 && s.controlPoints.map(\.z) == [0, 0, 0, 0])
        #expect(s.controlPoints.map(\.x) == [1, 3, 5, 7])
    }

    @Test("malformed splines never crash and still flatten to finite points")
    func malformed() throws {
        let cp: [XYZ] = [(0, 0, 0), (1, 2, 0), (3, 2, 0), (4, 0, 0)]
        let cases: [(String, String)] = [
            ("too few knots", Self.splineBody(degree: 3, knots: [0, 0, 1, 1], control: cp)),
            ("no knots", Self.splineBody(degree: 3, control: cp)),
            (
                "too many knots",
                Self.splineBody(degree: 3, knots: Array(repeating: 1, count: 20), control: cp)
            ),
            (
                "decreasing knots",
                Self.splineBody(degree: 3, knots: [3, 2, 1, 0, 0, 0, 0, 0], control: cp)
            ),
            (
                "equal knots",
                Self.splineBody(degree: 3, knots: Array(repeating: 2, count: 8), control: cp)
            ),
            (
                "weights short",
                Self.splineBody(
                    degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1], weights: [1, 2], control: cp)
            ),
            (
                "zero weight",
                Self.splineBody(
                    degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1], weights: [1, 0, 1, 1], control: cp)
            ),
            (
                "negative weight",
                Self.splineBody(
                    degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1], weights: [1, -1, 1, 1], control: cp)
            ),
            ("degree 0", Self.splineBody(degree: 0, knots: [0, 0, 1, 2, 3], control: cp)),
            ("negative degree", Self.splineBody(degree: -2, control: cp)),
            ("degree above count", Self.splineBody(degree: 9, control: cp)),
        ]
        for (name, body) in cases {
            let poly = try Self.spline(body).flattened(tolerance: 0.01)
            #expect(poly.count >= 2, "\(name)")
            #expect(poly.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }, "\(name)")
        }
    }

    @Test("zero or non-finite weights fall back to the unweighted curve")
    func badWeightsIgnored() throws {
        let cp: [XYZ] = [(0, 0, 0), (1, 2, 0), (3, 2, 0), (4, 0, 0)]
        let k: [Double] = [0, 0, 0, 0, 1, 1, 1, 1]
        let plain = try Self.spline(Self.splineBody(degree: 3, knots: k, control: cp))
        let zero = try Self.spline(
            Self.splineBody(degree: 3, knots: k, weights: [1, 0, 1, 1], control: cp))
        #expect(plain.flattened(tolerance: 0.01) == zero.flattened(tolerance: 0.01))
    }

    @Test("degenerate point counts and tolerances")
    func degenerate() throws {
        let none = try Self.spline(Self.splineBody(degree: 3))
        #expect(none.flattened(tolerance: 0.1).isEmpty)
        let one = try Self.spline(Self.splineBody(degree: 3, control: [(1, 2, 3)]))
        #expect(one.flattened(tolerance: 0.1).count == 1 && one.point(at: 0) == nil)
        let cp: [XYZ] = [(0, 0, 0), (1, 2, 0), (3, 2, 0), (4, 0, 0)]
        let s = try Self.spline(Self.splineBody(degree: 3, control: cp))
        for tol in [0, -1, .nan, .infinity, 1e-300] {
            let n = s.flattened(tolerance: tol).count
            #expect(n >= 2 && n < 100_000, "tol \(tol)")
        }
        #expect(s.point(at: .nan) != nil && s.point(at: 1e300) != nil)
    }

    @Test("bounds include spline control points; counts include splines")
    func boundsAndCounts() throws {
        let dwg = try DXF.read(
            text: SwiftDXFTests.doc(
                Self.splineBody(degree: 1, knots: [0, 0, 1, 1], control: [(-5, 1, 0), (6, 7, 0)])))
        let b = try #require(dwg.bounds)
        #expect(b.min.x == -5 && b.max.y == 7)
        #expect(dwg.counts.spline == 1 && dwg.counts.total == 1)
    }

    // MARK: skipped-entity report

    @Test("skipped entities are counted per type and layer, and the rest still reads")
    func skippedReport() throws {
        let dwg = try DXF.read(
            text: SwiftDXFTests.doc(
                """
                0
                LINE
                10
                0
                20
                0
                11
                1
                21
                1
                0
                INSERT
                8
                A
                2
                BLK
                0
                HATCH
                8
                B
                0
                SOLID
                8
                B
                0
                SOLID
                0
                POLYLINE
                70
                0
                0
                VERTEX
                10
                0
                20
                0
                0
                VERTEX
                10
                1
                20
                0
                0
                SEQEND
                """))
        #expect(dwg.counts.line == 1 && dwg.counts.polyline == 1)
        #expect(dwg.skipped == ["INSERT": 1, "HATCH": 1, "SOLID": 2])
        #expect(dwg.skippedByLayer["SOLID"] == ["B": 1, "0": 1])
        #expect(dwg.skippedByLayer["INSERT"] == ["A": 1])
    }

    @Test("a drawing of only modelled entities reports nothing skipped")
    func nothingSkipped() throws {
        let dwg = try DXF.read(text: SwiftDXFTests.doc("0\nPOINT\n10\n1\n20\n2\n"))
        #expect(dwg.skipped.isEmpty && dwg.skippedByLayer.isEmpty)
    }
}
