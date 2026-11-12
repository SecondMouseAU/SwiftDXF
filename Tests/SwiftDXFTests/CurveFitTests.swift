import Foundation
import Testing

@testable import SwiftDXF

/// Fitting one SPLINE or ELLIPSE to lines and arcs, outside the contour layer.
@Suite("Fitting a single curve")
struct CurveFitTests {
    typealias S = ContourSupport

    static let root = 0.5.squareRoot()

    /// The unit circle as a closed rational quadratic spline: nine control points, four spans.
    static var unitCircle: DXF.Spline {
        let w = root
        let pts: [(Double, Double)] = [
            (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1), (1, 0),
        ]
        return DXF.Spline(
            degree: 2, flags: 1 | 4 | 8,
            controlPoints: pts.map { DXF.Point($0.0, $0.1) },
            knots: [0, 0, 0, 0.25, 0.25, 0.5, 0.5, 0.75, 0.75, 1, 1, 1],
            weights: [1, w, 1, w, 1, w, 1, w, 1])
    }

    static func quarterArc(reversed: Bool = false) -> DXF.Spline {
        var pts = [DXF.Point(1, 0), DXF.Point(1, 1), DXF.Point(0, 1)]
        var weights = [1, root, 1]
        if reversed {
            pts.reverse()
            weights.reverse()
        }
        return DXF.Spline(
            degree: 2, flags: 12, controlPoints: pts, knots: [0, 0, 0, 1, 1, 1], weights: weights)
    }

    static let cubic = DXF.Spline(
        degree: 3, flags: 8,
        controlPoints: [
            DXF.Point(0, 0), DXF.Point(1, 3), DXF.Point(3, 4), DXF.Point(5, 1), DXF.Point(7, 3),
            DXF.Point(9, 0),
        ],
        knots: [0, 0, 0, 0, 1, 2, 3, 3, 3, 3])

    /// Dense points on the exact curve.
    static func dense(_ s: DXF.Spline, _ n: Int = 4000) -> [DXF.Point2] {
        let domain = s.parameterDomain!
        return (0...n).map {
            let p = s.point(
                at: domain.lowerBound + (domain.upperBound - domain.lowerBound)
                    * Double($0) / Double(n))!
            return DXF.Point2(p.x, p.y)
        }
    }

    static func segments(_ fit: DXF.CurveFit) -> [DXF.Contour.Segment] { fit.pieces.map(\.segment) }

    /// Each piece starts where the one before ends.
    static func chains(_ fit: DXF.CurveFit) -> Bool {
        zip(fit.pieces, fit.pieces.dropFirst()).allSatisfy {
            $0.segment.end.distance(to: $1.segment.start) < 1e-9
        }
    }

    // MARK: Exact recognition

    @Test("a spline that is a straight line comes back as one line")
    func exactLine() {
        let spline = DXF.Spline(
            degree: 2, flags: 8,
            controlPoints: [DXF.Point(0, 0), DXF.Point(1, 1), DXF.Point(4, 4)],
            knots: [0, 0, 0, 1, 1, 1])
        let fit = spline.fitted(tolerance: 0.01)
        #expect(fit.isExact && fit.pieces.count == 1)
        let line = fit.pieces[0].segment
        #expect(!line.isArc && line.start == .init(0, 0) && line.end == .init(4, 4))
        #expect(fit.deviation < 1e-12)
    }

    @Test("a straight spline that doubles back is not one exact line")
    func foldedLineIsNotExact() {
        let spline = DXF.Spline(
            degree: 2, flags: 8,
            controlPoints: [DXF.Point(0, 0), DXF.Point(9, 0), DXF.Point(2, 0)],
            knots: [0, 0, 0, 1, 1, 1])
        let fit = spline.fitted(tolerance: 0.01)
        // It runs out to x = 5.06 and back to 2, so one line from start to end is wrong. The
        // fold's tip falls between the three samples that flattening tests a span with, so this
        // case asserts only what recognition decides, not the deviation.
        #expect(!fit.isExact && fit.pieces.count >= 2)
        #expect(fit.pieces.allSatisfy { !$0.segment.isArc && $0.segment.start.y == 0 })
        #expect(fit.pieces.map(\.segment.end.x).max()! > 4)
    }

    @Test("a rational quarter circle comes back as one exact arc")
    func exactArc() throws {
        let fit = Self.quarterArc().fitted(tolerance: 0.01)
        #expect(fit.isExact && fit.pieces.count == 1)
        let arc = fit.pieces[0].segment
        #expect(arc.start == .init(1, 0) && arc.end.distance(to: .init(0, 1)) < 1e-12)
        #expect(near(try #require(arc.radius), 1, 1e-12))
        #expect(try #require(arc.center).distance(to: .init(0, 0)) < 1e-12)
        #expect(near(arc.sweep, .pi / 2, 1e-12) && arc.bulge > 0)
        #expect(fit.deviation < 1e-12)
    }

    @Test("an arc drawn the other way round is clockwise")
    func clockwiseArc() {
        let fit = Self.quarterArc(reversed: true).fitted(tolerance: 0.01)
        #expect(fit.isExact && fit.pieces.count == 1)
        #expect(fit.pieces[0].segment.bulge < 0)
        #expect(fit.pieces[0].segment.start == .init(0, 1))
    }

    @Test("a closed rational circle comes back as two half turns that close")
    func exactCircle() throws {
        let fit = Self.unitCircle.fitted(tolerance: 0.01)
        #expect(fit.isExact && fit.pieces.count == 2)
        #expect(Self.chains(fit))
        let first = fit.pieces[0].segment
        let last = fit.pieces[1].segment
        #expect(last.end == first.start)
        for p in fit.pieces {
            #expect(near(try #require(p.segment.radius), 1, 1e-12))
            #expect(abs(p.segment.bulge) == 1)
        }
        let turn = fit.pieces.reduce(0) { $0 + abs($1.segment.sweep) }
        #expect(near(turn, 2 * .pi, 1e-12))
    }

    @Test("a 270 degree arc comes back as two pieces of at most a half turn")
    func threeQuarterArc() {
        let w = Self.root
        // Three quarter arcs: seven control points, ten knots for degree 2.
        let spline = DXF.Spline(
            degree: 2, flags: 12,
            controlPoints: [
                .init(1, 0), .init(1, 1), .init(0, 1), .init(-1, 1), .init(-1, 0), .init(-1, -1),
                .init(0, -1),
            ],
            knots: [0, 0, 0, 1, 1, 2, 2, 3, 3, 3], weights: [1, w, 1, w, 1, w, 1])
        let fit = spline.fitted(tolerance: 0.01)
        #expect(fit.isExact && fit.pieces.count == 2 && Self.chains(fit))
        #expect(fit.pieces.allSatisfy { abs($0.segment.bulge) <= 1 })
        #expect(near(fit.pieces.reduce(0) { $0 + $1.segment.sweep }, 1.5 * .pi, 1e-12))
    }

    @Test("an ellipse with equal axes is an exact circle, any other ellipse is fitted")
    func ellipseEntities() throws {
        let circle = DXF.Entity.ellipse(
            center: .init(2, 3), majorAxis: .init(5, 0), ratio: 1, startParam: 0,
            endParam: 2 * .pi, layer: "0", color: 256)
        let exact = try #require(circle.fitted(tolerance: 0.01))
        #expect(exact.isExact && exact.pieces.count == 2 && exact.deviation == 0)
        #expect(near(try #require(exact.pieces[0].segment.radius), 5, 1e-12))

        let ellipse = DXF.Entity.ellipse(
            center: .init(0, 0), majorAxis: .init(6, 0), ratio: 0.5, startParam: 0,
            endParam: 2 * .pi, layer: "0", color: 256)
        let fit = try #require(ellipse.fitted(tolerance: 0.001))
        #expect(!fit.isExact && fit.pieces.count > 4 && fit.deviation <= 0.001)
        #expect(Self.chains(fit))
        // Closed: the last piece ends where the first begins.
        #expect(fit.pieces.last!.segment.end.distance(to: fit.pieces[0].segment.start) < 1e-9)
        let curve = (0...4000).map { k -> DXF.Point2 in
            let t = 2 * Double.pi * Double(k) / 4000
            return DXF.Point2(6 * cos(t), 3 * sin(t))
        }
        #expect(S.deviation(of: curve, from: Self.segments(fit)) <= fit.deviation)
    }

    // MARK: Fitting within a tolerance

    @Test(
        "a general spline fits within each tolerance asked for, with a measured deviation",
        arguments: [0.1, 0.01, 0.001, 0.00001])
    func fitsWithinTolerance(_ tolerance: Double) {
        let fit = Self.cubic.fitted(tolerance: tolerance)
        #expect(!fit.isExact && !fit.pieces.isEmpty && Self.chains(fit))
        #expect(fit.deviation <= tolerance)
        let measured = S.deviation(of: Self.dense(Self.cubic), from: Self.segments(fit))
        #expect(measured <= fit.deviation, "measured \(measured) reported \(fit.deviation)")
        #expect(fit.pieces[0].segment.start == .init(0, 0))
        #expect(fit.pieces.last!.segment.end.distance(to: .init(9, 0)) < 1e-9)
    }

    @Test("a tighter tolerance needs at least as many pieces")
    func tighterNeedsMore() {
        let loose = Self.cubic.fitted(tolerance: 0.1).pieces.count
        let tight = Self.cubic.fitted(tolerance: 0.0001).pieces.count
        #expect(tight >= loose)
    }

    @Test("fit points alone still give a fit")
    func fitPointsOnly() {
        let spline = DXF.Spline(
            degree: 3, flags: 0,
            fitPoints: [.init(0, 0), .init(2, 2), .init(5, 1), .init(8, 3)])
        let fit = spline.fitted(tolerance: 0.01)
        #expect(!fit.pieces.isEmpty && fit.deviation <= 0.01 && Self.chains(fit))
        #expect(fit.pieces.last!.segment.end.distance(to: .init(8, 3)) < 1e-9)
    }

    // MARK: Identity

    @Test("the pieces carry the identity of the entity they came from")
    func identityOnPieces() throws {
        let source = DXF.Identity(handle: "A1", locator: "ENTITIES:3")
        let fit = Self.cubic.fitted(tolerance: 0.01, source: source)
        #expect(fit.source == source && fit.pieces.allSatisfy { $0.source == source })

        let dwg = DXF.Drawing(
            entities: [.point(at: .init(0, 0), layer: "0", color: 256), .spline(Self.cubic)],
            identities: [
                .init(handle: "10", locator: "ENTITIES:0"), source,
            ])
        let named = try #require(dwg.fittedCurve(at: 1, tolerance: 0.01))
        #expect(named.source == source && named.pieces.allSatisfy { $0.source?.handle == "A1" })
        #expect(named.pieces.map(\.segment) == fit.pieces.map(\.segment))
        // Without identities the position names it.
        let bare = DXF.Drawing(entities: [.spline(Self.cubic)])
        #expect(bare.fittedCurve(at: 0, tolerance: 0.01)?.source?.id == "ENTITIES:0")
    }

    @Test("only splines and ellipses fit; out of range and degenerate input never trap")
    func otherEntitiesAndDegenerate() throws {
        let line = DXF.Entity.line(a: .init(0, 0), b: .init(1, 1), layer: "0", color: 256)
        #expect(line.fitted(tolerance: 0.01) == nil)
        let dwg = DXF.Drawing(entities: [line])
        #expect(dwg.fittedCurve(at: 0, tolerance: 0.01) == nil)
        #expect(dwg.fittedCurve(at: 5, tolerance: 0.01) == nil)
        #expect(dwg.fittedCurve(at: -1, tolerance: 0.01) == nil)

        let empty = DXF.Spline(degree: 3, controlPoints: [.init(1, 1)]).fitted(tolerance: 0.01)
        #expect(empty.pieces.isEmpty && !empty.isExact && empty.deviation == 0)
        let flat = DXF.Entity.ellipse(
            center: .init(0, 0), majorAxis: .init(0, 0), ratio: 0.5, startParam: 0,
            endParam: 2 * .pi, layer: "0", color: 256)
        #expect(try #require(flat.fitted(tolerance: 0.01)).pieces.isEmpty)
        // A non-finite or non-positive tolerance is clamped, not trapped on.
        for tolerance in [0, -1, .nan, .infinity] {
            let fit = Self.cubic.fitted(tolerance: tolerance)
            #expect(!fit.pieces.isEmpty && fit.deviation.isFinite)
        }
    }

    @Test("an ellipse too large for the tolerance gives no pieces and does not trap")
    func hugeEllipse() throws {
        // 1e300 and 1e155 overflow when squared; 4e34 would need more samples than an Int holds.
        for axis in [1e300, 1e155, 4e34, 1e12] {
            let huge = DXF.Entity.ellipse(
                center: .init(0, 0), majorAxis: .init(axis, 0), ratio: 0.5, startParam: 0,
                endParam: 2 * .pi, layer: "0", color: 256)
            let fit = try #require(huge.fitted(tolerance: 0.01))
            #expect(fit.pieces.isEmpty && fit.deviation == 0 && !fit.isExact)
        }
        // A large ellipse that is within reach still fits.
        let large = DXF.Entity.ellipse(
            center: .init(0, 0), majorAxis: .init(1e5, 0), ratio: 0.5, startParam: 0,
            endParam: 2 * .pi, layer: "0", color: 256)
        let fit = try #require(large.fitted(tolerance: 0.01))
        #expect(!fit.pieces.isEmpty && fit.deviation <= 0.01)
    }

    // MARK: The contour layer agrees

    @Test("fitted pieces chain into the same regions the contour layer finds")
    func sameRegionsAsContours() throws {
        // A plate: a straight bottom, a cubic spline top, and a spline arc on the right.
        let bump = DXF.Spline(
            degree: 3, flags: 8,
            controlPoints: [.init(0, 10), .init(3, 14), .init(7, 6), .init(10, 10)],
            knots: [0, 0, 0, 0, 1, 1, 1, 1], layer: "CUT")
        let arc = DXF.Spline(
            degree: 2, flags: 12,
            controlPoints: [.init(10, 0), .init(14, 0), .init(14, 4)],
            knots: [0, 0, 0, 1, 1, 1], weights: [1, Self.root, 1], layer: "CUT")
        let others: [DXF.Entity] = [
            S.line(0, 0, 10, 0, layer: "CUT"), S.line(0, 0, 0, 10, layer: "CUT"),
            S.line(10, 0, 10, 10, layer: "CUT"),
        ]
        let original = S.drawing(others + [.spline(bump), .spline(arc)])
        let reference = original.contours()

        var replaced = others
        for case .spline(let s) in original.entities {
            let fit = s.fitted(tolerance: 0.01)
            for piece in fit.pieces {
                replaced.append(
                    .polyline(
                        vertices: [
                            .init(
                                .init(piece.segment.start.x, piece.segment.start.y, 0),
                                bulge: piece.segment.bulge),
                            .init(.init(piece.segment.end.x, piece.segment.end.y, 0)),
                        ], closed: false, layer: "CUT", color: 256))
            }
        }
        let rebuilt = S.drawing(replaced).contours()
        #expect(reference.shapes.count == rebuilt.shapes.count)
        #expect(!reference.shapes.isEmpty)
        for (a, b) in zip(reference.shapes, rebuilt.shapes) {
            #expect(near(a.area, b.area, 1e-9), "\(a.area) != \(b.area)")
            #expect(a.holes.count == b.holes.count)
        }
        #expect(reference.openChains.count == rebuilt.openChains.count)
    }

    @Test("the contour layer uses exact arcs and reports a deviation that is only rounding")
    func contoursUseExactArcs() throws {
        // A half disc: a spline semicircle (two rational quarter arcs) closed by a line.
        let w = Self.root
        let half = DXF.Spline(
            degree: 2, flags: 12,
            controlPoints: [.init(1, 0), .init(1, 1), .init(0, 1), .init(-1, 1), .init(-1, 0)],
            knots: [0, 0, 0, 0.5, 0.5, 1, 1, 1], weights: [1, w, 1, w, 1])
        let result = S.drawing([.spline(half), S.line(-1, 0, 1, 0)]).contours()
        let shape = try #require(result.shapes.first)
        #expect(result.shapes.count == 1 && near(shape.area, .pi / 2, 1e-12))
        #expect(result.maxFitDeviation < 1e-12)
        #expect(
            result.warnings.contains { if case .fittedCurves(1, _) = $0 { true } else { false } })
    }

    // MARK: A real drawing

    /// The drawing named by `DXF_SPLINE_FILE`, when it is set and exists.
    static var splineFile: URL? {
        guard let path = ProcessInfo.processInfo.environment["DXF_SPLINE_FILE"],
            FileManager.default.fileExists(atPath: path)
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// A real drawing with many splines, such as McMaster-Carr 7021N13, named by `DXF_SPLINE_FILE`.
    ///
    /// The test is skipped without it, and a failure inside it is a real failure.
    @Test(
        "every spline in a real drawing fits within a thousandth, and the regions agree",
        .enabled(if: CurveFitTests.splineFile != nil))
    func realDrawing() throws {
        let url = try #require(Self.splineFile)
        let dwg = try DXF.read(contentsOf: url)
        let tolerance = 0.001  // 7021N13 is in millimetres
        var splines = 0
        var exact = 0
        var worst = 0.0
        for (i, entity) in dwg.entities.enumerated() {
            guard case .spline(let s) = entity else { continue }
            splines += 1
            let fit = try #require(dwg.fittedCurve(at: i, tolerance: tolerance))
            #expect(fit.deviation <= tolerance)
            #expect(fit.source == dwg.identity(ofEntityAt: i))
            if fit.isExact { exact += 1 }
            if s.controlPoints.count >= 2, s.parameterDomain != nil {
                let measured = S.deviation(of: Self.dense(s, 800), from: Self.segments(fit))
                worst = max(worst, measured)
                #expect(measured <= tolerance, "spline \(i): \(measured)")
            }
        }
        print("real drawing: \(splines) splines, \(exact) exact, worst measured \(worst)")
        #expect(splines > 0)

        // The fitted pieces close into the same regions as the contour layer finds.
        let options = DXF.Contour.Options(fitTolerance: tolerance)
        let reference = dwg.contours(options)
        var replaced: [DXF.Entity] = []
        for (i, entity) in dwg.entities.enumerated() {
            guard case .spline(let s) = entity,
                let fit = dwg.fittedCurve(at: i, tolerance: tolerance)
            else {
                replaced.append(entity)
                continue
            }
            for piece in fit.pieces {
                let seg = piece.segment
                replaced.append(
                    .polyline(
                        vertices: [
                            .init(.init(seg.start.x, seg.start.y, 0), bulge: seg.bulge),
                            .init(.init(seg.end.x, seg.end.y, 0)),
                        ], closed: false, layer: s.layer, color: s.color))
            }
        }
        var copy = dwg
        copy.entities = replaced
        copy.identities = []
        copy.entityLineTypes = []
        let rebuilt = copy.contours(options)
        #expect(reference.shapes.count == rebuilt.shapes.count)
        #expect(near(reference.area, rebuilt.area, 1e-6 * max(1, reference.area)))
    }
}
