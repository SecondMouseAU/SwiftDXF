import Foundation

/// Turns drawing entities into line and arc segments in millimetres.
struct SegmentExtractor {
    /// Millimetres per drawing unit.
    let scale: Double
    /// Maximum deviation allowed when a curve is replaced by lines and arcs.
    let fitTolerance: Double

    var segments: [RawSegment] = []
    /// Entities dropped because they were zero-sized or non-finite.
    var degenerate = 0
    /// Ellipses and splines that were replaced by fitted pieces.
    var fittedCurves = 0
    /// Upper bound on the distance between any fitted piece and its true curve.
    var fitDeviation = 0.0

    init(scale: Double, fitTolerance: Double) {
        self.scale = scale
        self.fitTolerance = fitTolerance
    }

    private func pt(_ p: DXF.Point) -> DXF.Point2 { DXF.Point2(p.x * scale, p.y * scale) }

    private static func finite(_ values: Double...) -> Bool { values.allSatisfy { $0.isFinite } }

    mutating func add(_ entity: DXF.Entity, layer: Int) {
        switch entity {
        case .line(let a, let b, _, _):
            addLine(pt(a), pt(b), layer: layer)
        case .circle(let c, let r, _, _):
            addArc(centre: pt(c), radius: r * scale, startDeg: 0, sweepDeg: 360, layer: layer)
        case .arc(let c, let r, let s, let e, _, _):
            guard Self.finite(s, e) else {
                degenerate += 1
                return
            }
            let raw = e - s
            var sweep = raw >= 360 - 1e-9 ? 360 : raw.truncatingRemainder(dividingBy: 360)
            if sweep < 0 { sweep += 360 }
            addArc(centre: pt(c), radius: r * scale, startDeg: s, sweepDeg: sweep, layer: layer)
        case .polyline(let verts, let closed, _, _):
            addPolyline(verts, closed: closed, layer: layer)
        case .ellipse(let c, let m, let ratio, let s, let e, _, _):
            addEllipse(c, m, ratio, s, e, layer: layer)
        case .spline(let sp):
            addSpline(sp, layer: layer)
        case .point, .text, .dimension:
            break
        }
    }

    private mutating func addLine(_ a: DXF.Point2, _ b: DXF.Point2, layer: Int) {
        guard Self.finite(a.x, a.y, b.x, b.y), a.distance(to: b) > 1e-12 else {
            degenerate += 1
            return
        }
        segments.append(RawSegment(a: a, b: b, bulge: 0, layer: layer))
    }

    /// An arc about `centre`; `sweepDeg` of 360 is a full circle.
    private mutating func addArc(
        centre: DXF.Point2, radius: Double, startDeg: Double, sweepDeg: Double, layer: Int
    ) {
        guard Self.finite(centre.x, centre.y, radius, startDeg, sweepDeg), radius > 1e-12,
            sweepDeg > 1e-9
        else {
            degenerate += 1
            return
        }
        let pieces = ArcPieces.split(sweep: sweepDeg * Double.pi / 180, layer: layer) { k, n in
            let (c, s) = ArcPieces.cosSin(degrees: startDeg + sweepDeg * Double(k) / Double(n))
            return DXF.Point2(centre.x + radius * c, centre.y + radius * s)
        }
        segments.append(contentsOf: pieces)
    }

    private mutating func addPolyline(_ verts: [DXF.PolyVertex], closed: Bool, layer: Int) {
        let count = verts.count
        guard count >= 2 else { return }
        for i in 0..<(closed ? count : count - 1) {
            let v = verts[i]
            let p = pt(v.point)
            let q = pt(verts[(i + 1) % count].point)
            guard Self.finite(p.x, p.y, q.x, q.y, v.bulge) else {
                degenerate += 1
                continue
            }
            if p.distance(to: q) <= 1e-12 { continue }
            if abs(v.bulge) < 1e-12 {
                segments.append(RawSegment(a: p, b: q, bulge: 0, layer: layer))
            } else if abs(v.bulge) <= 1 {
                segments.append(RawSegment(a: p, b: q, bulge: v.bulge, layer: layer))
            } else {
                addLargeBulge(p, q, v.bulge, layer: layer)
            }
        }
    }

    /// A bulge above 1 is more than a half turn: split it into half-turn-or-less pieces.
    private mutating func addLargeBulge(
        _ p: DXF.Point2, _ q: DXF.Point2, _ bulge: Double, layer: Int
    ) {
        let whole = DXF.Contour.Segment(start: p, end: q, bulge: bulge)
        guard let c = whole.center, let r = whole.radius, let a0 = whole.startAngle,
            r.isFinite, r > 1e-12
        else {
            degenerate += 1
            return
        }
        let sweep = whole.sweep
        segments.append(
            contentsOf: ArcPieces.split(sweep: sweep, layer: layer) { k, n in
                if k == 0 { return p }
                if k == n { return q }
                let (cs, sn) = ArcPieces.cosSin(radians: a0 + sweep * Double(k) / Double(n))
                return DXF.Point2(c.x + r * cs, c.y + r * sn)
            })
    }

    private mutating func addEllipse(
        _ c: DXF.Point, _ major: DXF.Point, _ ratio: Double, _ start: Double, _ end: Double,
        layer: Int
    ) {
        let a = (major.x * major.x + major.y * major.y).squareRoot() * scale
        guard Self.finite(c.x, c.y, major.x, major.y, ratio, start, end), a > 1e-12, ratio > 0
        else {
            degenerate += 1
            return
        }
        let raw = end - start
        let full = 2 * Double.pi
        var sweep = raw >= full - 1e-9 ? full : raw.truncatingRemainder(dividingBy: full)
        if sweep <= 0 { sweep = raw < 0 ? sweep + full : full }
        if sweep < 1e-9 {
            degenerate += 1
            return
        }
        let tilt = atan2(major.y, major.x)
        let centre = pt(c)
        if abs(ratio - 1) <= 1e-12 {
            let pieces = ArcPieces.split(sweep: sweep, layer: layer) { k, n in
                let (cs, sn) = ArcPieces.cosSin(
                    radians: tilt + start + sweep * Double(k) / Double(n))
                return DXF.Point2(centre.x + a * cs, centre.y + a * sn)
            }
            segments.append(contentsOf: pieces)
            return
        }
        let b = a * ratio
        let (ct, st) = (cos(tilt), sin(tilt))
        func at(_ t: Double) -> DXF.Point2 {
            let (cs, sn) = (cos(t), sin(t))
            return DXF.Point2(
                centre.x + a * cs * ct - b * sn * st, centre.y + a * cs * st + b * sn * ct)
        }
        // |r''| <= a for the parametric ellipse, so a step of sqrt(8 tol / a) keeps every chord
        // within a quarter of the tolerance of the curve.
        let flat = fitTolerance / 4
        let step = (8 * flat / a).squareRoot()
        let count = min(1_000_000, max(16, Int((sweep / step).rounded(.up))))
        var pts: [DXF.Point2] = []
        for k in 0...count {
            pts.append(
                k == count && sweep == full ? pts[0] : at(start + sweep * Double(k) / Double(count))
            )
        }
        addFitted(pts, flatness: flat, layer: layer)
    }

    private mutating func addSpline(_ sp: DXF.Spline, layer: Int) {
        let flat = fitTolerance / 4
        let raw = sp.flattened(tolerance: flat / scale)
        var pts = raw.map { pt($0) }.filter { Self.finite($0.x, $0.y) }
        if sp.isClosed, let first = pts.first, let last = pts.last, first.distance(to: last) < 1e-9
        {
            pts[pts.count - 1] = first
        }
        addFitted(pts, flatness: flat, layer: layer)
    }

    /// Fits a sampled curve whose chords are already within `flatness` of the true curve.
    private mutating func addFitted(_ samples: [DXF.Point2], flatness: Double, layer: Int) {
        var pts: [DXF.Point2] = []
        for p in samples where pts.last.map({ $0.distance(to: p) > 1e-12 }) ?? true {
            pts.append(p)
        }
        guard pts.count >= 2 else {
            degenerate += 1
            return
        }
        let fit = CurveFitter.fit(pts, tolerance: fitTolerance / 2)
        fittedCurves += 1
        fitDeviation = max(fitDeviation, fit.deviation + 2 * flatness)
        for piece in fit.pieces {
            segments.append(RawSegment(a: piece.a, b: piece.b, bulge: piece.bulge, layer: layer))
        }
    }
}
