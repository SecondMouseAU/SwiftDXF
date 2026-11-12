import Foundation

/// Recognises a spline that is exactly a straight line or a circular arc.
///
/// Many exporters write simple curves as splines. The curve is sampled on every knot span; it is a
/// line or an arc when all samples lie on one within a billionth of the curve's size.
enum SplineRecognition {
    struct Result {
        var pieces: [RawSegment]
        /// Largest distance from a sample to the line or arc.
        var deviation: Double
    }

    /// The spline as a line or arc in coordinates scaled by `scale`, or `nil` when it is neither.
    static func recognise(_ spline: DXF.Spline, scale: Double) -> Result? {
        guard let curve = spline.curve() else { return nil }
        let pts = samples(curve).map { DXF.Point2($0.x * scale, $0.y * scale) }
        guard pts.count >= 3, pts.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return nil
        }
        let xs = pts.map(\.x)
        let ys = pts.map(\.y)
        let size = hypot(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
        guard size > 1e-12 else { return nil }
        let eps = 1e-9 * size
        return line(pts, eps: eps, size: size) ?? arc(pts, eps: eps, size: size)
    }

    /// Points along the curve: every knot span is sampled, so a span cannot hide a bulge.
    private static func samples(_ curve: DXF.Spline.Curve) -> [DXF.Point] {
        let knots = curve.distinctKnots
        let perSpan = knots.count > 257 ? 2 : 8
        var out: [DXF.Point] = []
        for (a, b) in zip(knots, knots.dropFirst()) {
            for k in 0..<perSpan {
                out.append(curve.point(at: a + (b - a) * Double(k) / Double(perSpan)))
            }
        }
        out.append(curve.point(at: curve.domain.upperBound))
        return out
    }

    private static func line(_ pts: [DXF.Point2], eps: Double, size: Double) -> Result? {
        let a = pts[0]
        let b = pts[pts.count - 1]
        let length = a.distance(to: b)
        guard length > 1e-6 * size else { return nil }
        let ux = (b.x - a.x) / length
        let uy = (b.y - a.y) / length
        var worst = 0.0
        var previous = 0.0
        for p in pts {
            let dx = p.x - a.x
            let dy = p.y - a.y
            let along = dx * ux + dy * uy
            let off = abs(dx * uy - dy * ux)
            // The curve must run along the line without doubling back past either end.
            guard off <= eps, along >= previous - eps, along >= -eps, along <= length + eps
            else { return nil }
            worst = max(worst, off)
            previous = along
        }
        return Result(pieces: [RawSegment(a: a, b: b, bulge: 0, layer: 0)], deviation: worst)
    }

    private static func arc(_ pts: [DXF.Point2], eps: Double, size: Double) -> Result? {
        let last = pts.count - 1
        let closed = pts[0].distance(to: pts[last]) <= 1e-6 * size
        let p0 = pts[0]
        let p1 = pts[closed ? last / 3 : last / 2]
        let p2 = pts[closed ? 2 * last / 3 : last]
        guard let circle = Circumcircle(p0, p1, p2), circle.radius <= 1e4 * size else { return nil }
        let (centre, radius, counterClockwise) = (
            circle.centre, circle.radius, circle.counterClockwise
        )

        func angle(_ p: DXF.Point2) -> Double { atan2(p.y - centre.y, p.x - centre.x) }
        var worst = 0.0
        var total = 0.0
        var previous = angle(p0)
        for k in 0...last {
            let deviation = abs(pts[k].distance(to: centre) - radius)
            guard deviation <= eps else { return nil }
            worst = max(worst, deviation)
            guard k > 0 else { continue }
            let a = angle(pts[k])
            var delta = a - previous
            if delta > .pi { delta -= 2 * .pi }
            if delta <= -.pi { delta += 2 * .pi }
            // Every step must go the same way round.
            guard counterClockwise ? delta >= -1e-9 : delta <= 1e-9 else { return nil }
            total += delta
            previous = a
        }
        let full = 2 * Double.pi
        if closed {
            guard abs(abs(total) - full) < 1e-6 else { return nil }
            total = counterClockwise ? full : -full
        } else {
            guard abs(total) > 1e-9, abs(total) < full - 1e-9 else { return nil }
        }
        let start = angle(p0)
        let pieces = ArcPieces.split(sweep: total, layer: 0) { k, n in
            if k == 0 { return p0 }
            if k == n { return closed ? p0 : pts[last] }
            let (c, s) = ArcPieces.cosSin(radians: start + total * Double(k) / Double(n))
            return DXF.Point2(centre.x + radius * c, centre.y + radius * s)
        }
        return Result(pieces: pieces, deviation: worst)
    }
}
