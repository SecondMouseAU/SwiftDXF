import Foundation
import Testing

@testable import SwiftDXF

@Suite("Fitting splines and ellipses at the entity level")
struct FittedCurveTests {

    static func spline(
        degree: Int, control: [(Double, Double)], knots: [Double], weights: [Double] = [],
        flags: Int = 0
    ) -> DXF.Spline {
        DXF.Spline(
            degree: degree, flags: flags, controlPoints: control.map { DXF.Point($0.0, $0.1) },
            knots: knots, weights: weights)
    }

    @Test("a straight spline is recognised as a line")
    func straightSpline() {
        let s = Self.spline(
            degree: 3, control: [(0, 0), (1, 0), (2, 0), (3, 0)], knots: [0, 0, 0, 0, 1, 1, 1, 1])
        let fit = DXF.Entity.spline(s).fitted(tolerance: 0.01)
        #expect(fit?.recognized == .line)
        #expect(fit?.segments.count == 1)
        if let seg = fit?.segments.first {
            #expect(abs(seg.start.x) < 1e-9 && abs(seg.end.x - 3) < 1e-9)
        }
    }

    @Test("a rational quarter circle is recognised as an arc")
    func rationalArc() {
        let w = 2.0.squareRoot() / 2
        let s = Self.spline(
            degree: 2, control: [(10, 0), (10, 10), (0, 10)], knots: [0, 0, 0, 1, 1, 1],
            weights: [1, w, 1], flags: 4)
        guard let fit = DXF.Entity.spline(s).fitted(tolerance: 0.01) else {
            Issue.record("no fit")
            return
        }
        if case .arc(let c, let r) = fit.recognized {
            #expect(c.distance(to: DXF.Point2(0, 0)) < 0.01 && abs(r - 10) < 0.01)
        } else {
            Issue.record("not recognised as an arc: \(fit.recognized)")
        }
        #expect(fit.deviation <= 0.01 + 1e-9)
    }

    @Test("a free-form spline is fitted within the tolerance and reports its deviation")
    func freeForm() {
        let s = Self.spline(
            degree: 3, control: [(0, 0), (3, 8), (7, -8), (10, 0)], knots: [0, 0, 0, 0, 1, 1, 1, 1])
        guard let fit = DXF.Entity.spline(s).fitted(tolerance: 0.05) else {
            Issue.record("no fit")
            return
        }
        #expect(fit.recognized == .curve)
        #expect(fit.segments.count > 1 && fit.deviation <= 0.05 + 1e-9)
        // The pieces are connected and span the curve.
        for (a, b) in zip(fit.segments, fit.segments.dropFirst()) {
            #expect(a.end.distance(to: b.start) < 1e-9)
        }
        #expect(fit.segments.first?.start.distance(to: DXF.Point2(0, 0)) ?? 1 < 1e-9)
        #expect(fit.segments.last?.end.distance(to: DXF.Point2(10, 0)) ?? 1 < 1e-9)
    }

    @Test("an ellipse is fitted, and a round ellipse is one circle")
    func ellipses() {
        let round = DXF.Entity.ellipse(
            center: DXF.Point(0, 0), majorAxis: DXF.Point(5, 0), ratio: 1, startParam: 0,
            endParam: 2 * .pi, layer: "0", color: 7)
        if case .arc(_, let r)? = round.fitted(tolerance: 0.01)?.recognized {
            #expect(abs(r - 5) < 1e-6)
        } else {
            Issue.record("a ratio 1 ellipse should be a circle")
        }
        let flat = DXF.Entity.ellipse(
            center: DXF.Point(0, 0), majorAxis: DXF.Point(5, 0), ratio: 0.4, startParam: 0,
            endParam: 2 * .pi, layer: "0", color: 7)
        let fit = flat.fitted(tolerance: 0.01)
        #expect(fit?.recognized == .curve)
        #expect((fit?.deviation ?? 1) <= 0.01 + 1e-9)
    }

    @Test("other entities have nothing to fit")
    func notCurves() {
        let line = DXF.Entity.line(a: DXF.Point(0, 0), b: DXF.Point(1, 1), layer: "0", color: 7)
        #expect(line.fitted(tolerance: 0.01) == nil)
    }

    @Test("the drawing's fitted curves remember their entity, identity and layer")
    func drawingLevel() throws {
        let body = """
            0
            LINE
            5
            11
            8
            A
            10
            0
            20
            0
            11
            1
            21
            1
            0
            SPLINE
            5
            2A
            8
            GEOM
            70
            8
            71
            1
            72
            4
            73
            2
            10
            0
            20
            0
            10
            4
            20
            0
            40
            0
            40
            0
            40
            4
            40
            4
            """
        let drawing = try DXF.read(text: SwiftDXFTests.doc(body))
        let fits = drawing.fittedCurves(tolerance: 0.01)
        #expect(fits.count == 1)
        if let fit = fits.first {
            #expect(fit.entityIndex == 1 && fit.identity?.id == "#2A" && fit.layer == "GEOM")
            #expect(fit.recognized == .line)
        }
        #expect(drawing.fittedCurves(tolerance: 0.01, layers: ["geom"]).count == 1)
        #expect(drawing.fittedCurves(tolerance: 0.01, layers: ["other"]).isEmpty)
    }
}
