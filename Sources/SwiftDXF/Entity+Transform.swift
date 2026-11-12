import Foundation

extension DXF.Entity {
    /// This entity with a different layer and colour.
    func replacing(layer: String, color: Int) -> DXF.Entity {
        switch self {
        case .line(let a, let b, _, _): return .line(a: a, b: b, layer: layer, color: color)
        case .circle(let c, let r, _, _):
            return .circle(center: c, radius: r, layer: layer, color: color)
        case .arc(let c, let r, let s, let e, _, _):
            return .arc(center: c, radius: r, startDeg: s, endDeg: e, layer: layer, color: color)
        case .ellipse(let c, let m, let ratio, let s, let e, _, _):
            return .ellipse(
                center: c, majorAxis: m, ratio: ratio, startParam: s, endParam: e, layer: layer,
                color: color)
        case .point(let p, _, _): return .point(at: p, layer: layer, color: color)
        case .text(let p, let h, let rot, let string, _, _):
            return .text(
                at: p, height: h, rotationDeg: rot, string: string, layer: layer, color: color)
        case .polyline(let v, let closed, _, _):
            return .polyline(vertices: v, closed: closed, layer: layer, color: color)
        case .dimension(var d):
            d.layer = layer
            d.color = color
            return .dimension(d)
        case .spline(var s):
            s.layer = layer
            s.color = color
            return .spline(s)
        }
    }

    /// The colour (AutoCAD Color Index).
    var colorIndex: Int {
        switch self {
        case .line(_, _, _, let c), .circle(_, _, _, let c), .arc(_, _, _, _, _, let c),
            .ellipse(_, _, _, _, _, _, let c), .point(_, _, let c),
            .text(_, _, _, _, _, let c), .polyline(_, _, _, let c):
            return c
        case .dimension(let d): return d.color
        case .spline(let s): return s.color
        }
    }

    /// This entity carried through `t`, or `nil` when `t` cannot carry it exactly: a polyline
    /// with bulges under a non-uniform scale.
    func transformed(by t: DXF.Transform) -> DXF.Entity? {
        let deg = 180 / Double.pi
        switch self {
        case .line(let a, let b, let l, let c):
            return .line(a: t.apply(a), b: t.apply(b), layer: l, color: c)

        case .point(let p, let l, let c):
            return .point(at: t.apply(p), layer: l, color: c)

        case .circle(let center, let r, let l, let c):
            if let s = t.similarity {
                return .circle(center: t.apply(center), radius: r * s, layer: l, color: c)
            }
            let e = t.ellipse(
                center: DXF.Point2(center.x, center.y), major: DXF.Point2(r, 0), ratio: 1,
                start: 0, end: 2 * .pi)
            return Self.ellipseEntity(e, z: t.apply(center).z, layer: l, color: c)

        case .arc(let center, let r, let startDeg, let endDeg, let l, let c):
            if let s = t.similarity {
                let phi = t.rotationDegrees
                let (a0, a1) = DXF.Transform.normalizedArc(
                    t.isMirrored ? (phi - endDeg, phi - startDeg) : (startDeg + phi, endDeg + phi))
                return .arc(
                    center: t.apply(center), radius: r * s, startDeg: a0, endDeg: a1, layer: l,
                    color: c)
            }
            var end = endDeg / deg
            if end <= startDeg / deg { end += 2 * .pi }
            let e = t.ellipse(
                center: DXF.Point2(center.x, center.y), major: DXF.Point2(r, 0), ratio: 1,
                start: startDeg / deg, end: end)
            return Self.ellipseEntity(e, z: t.apply(center).z, layer: l, color: c)

        case .ellipse(let center, let major, let ratio, let s0, let s1, let l, let c):
            let e = t.ellipse(
                center: DXF.Point2(center.x, center.y), major: DXF.Point2(major.x, major.y),
                ratio: ratio, start: s0, end: s1)
            return Self.ellipseEntity(e, z: t.apply(center).z, layer: l, color: c)

        case .text(let p, let h, let rot, let string, let l, let c):
            let scaleY = hypot(t.c, t.d)
            return .text(
                at: t.apply(p), height: h * scaleY, rotationDeg: rot + t.rotationDegrees,
                string: string, layer: l, color: c)

        case .polyline(let vertices, let closed, let l, let c):
            let hasBulge = vertices.contains { abs($0.bulge) > 1e-12 }
            if hasBulge && t.similarity == nil { return nil }
            let out = vertices.map {
                DXF.PolyVertex(t.apply($0.point), bulge: t.isMirrored ? -$0.bulge : $0.bulge)
            }
            return .polyline(vertices: out, closed: closed, layer: l, color: c)

        case .spline(var s):
            s.controlPoints = s.controlPoints.map(t.apply)
            s.fitPoints = s.fitPoints.map(t.apply)
            return .spline(s)

        case .dimension(var d):
            d.textPosition = t.apply(d.textPosition)
            d.defPoint = t.apply(d.defPoint)
            d.defPoint2 = d.defPoint2.map(t.apply)
            d.defPoint3 = d.defPoint3.map(t.apply)
            d.defPoint4 = d.defPoint4.map(t.apply)
            d.defPoint5 = d.defPoint5.map(t.apply)
            if let raw = d.rawMeasurement, raw > 0 {
                d.rawMeasurement = t.similarity.map { raw * $0 }
            }
            if d.kind == .linear {
                let (cs, sn) = ArcPieces.cosSin(degrees: d.rotation ?? 0)
                let v = t.applyVector(cs, sn)
                let angle = atan2(v.y, v.x) * deg
                if d.rotation != nil || abs(angle) > 1e-12 { d.rotation = angle }
            }
            return .dimension(d)
        }
    }

    private static func ellipseEntity(
        _ e: (center: DXF.Point2, major: DXF.Point2, ratio: Double, start: Double, end: Double),
        z: Double, layer: String, color: Int
    ) -> DXF.Entity {
        .ellipse(
            center: DXF.Point(e.center.x, e.center.y, z),
            majorAxis: DXF.Point(e.major.x, e.major.y, 0), ratio: e.ratio, startParam: e.start,
            endParam: e.end, layer: layer, color: color)
    }
}

extension DXF.Hatch {
    /// This hatch carried through `t`, or `nil` when `t` cannot carry a bulged polyline loop.
    ///
    /// Arc and ellipse edges come out counter-clockwise.
    func transformed(by t: DXF.Transform) -> DXF.Hatch? {
        var out = self
        out.loops = []
        let deg = 180 / Double.pi
        for loop in loops {
            switch loop.content {
            case .polyline(let vertices, let closed):
                if vertices.contains(where: { abs($0.bulge) > 1e-12 }) && t.similarity == nil {
                    return nil
                }
                let moved = vertices.map {
                    DXF.PolyVertex(t.apply($0.point), bulge: t.isMirrored ? -$0.bulge : $0.bulge)
                }
                out.loops.append(
                    Loop(flags: loop.flags, content: .polyline(vertices: moved, closed: closed)))
            case .edges(let edges):
                var moved: [Edge] = []
                for edge in edges {
                    switch edge {
                    case .line(let a, let b):
                        moved.append(.line(a: t.apply(a), b: t.apply(b)))
                    case .arc(let center, let r, let s0, let e0, let ccw):
                        let (s, e) = ccw ? (s0, e0) : (e0, s0)
                        if let k = t.similarity {
                            let phi = t.rotationDegrees
                            let (a0, a1) = DXF.Transform.normalizedArc(
                                t.isMirrored ? (phi - e, phi - s) : (s + phi, e + phi))
                            moved.append(
                                .arc(
                                    center: t.apply(center), radius: r * k, startDeg: a0,
                                    endDeg: a1, counterClockwise: true))
                        } else {
                            var end = e / deg
                            if end <= s / deg { end += 2 * .pi }
                            let q = t.ellipse(
                                center: center, major: DXF.Point2(r, 0), ratio: 1, start: s / deg,
                                end: end)
                            moved.append(
                                .ellipse(
                                    center: q.center, majorAxis: q.major, ratio: q.ratio,
                                    startDeg: q.start * deg, endDeg: q.end * deg,
                                    counterClockwise: true))
                        }
                    case .ellipse(let center, let major, let ratio, let s0, let e0, let ccw):
                        let (s, e) = ccw ? (s0, e0) : (e0, s0)
                        var end = e / deg
                        if end <= s / deg { end += 2 * .pi }
                        let q = t.ellipse(
                            center: center, major: major, ratio: ratio, start: s / deg, end: end)
                        moved.append(
                            .ellipse(
                                center: q.center, majorAxis: q.major, ratio: q.ratio,
                                startDeg: q.start * deg, endDeg: q.end * deg,
                                counterClockwise: true))
                    case .spline(let degree, let control, let knots, let weights):
                        moved.append(
                            .spline(
                                degree: degree, controlPoints: control.map(t.apply), knots: knots,
                                weights: weights))
                    }
                }
                out.loops.append(Loop(flags: loop.flags, content: .edges(moved)))
            }
        }
        return out
    }
}

extension DXF.Leader {
    /// This leader carried through `t`.
    func transformed(by t: DXF.Transform) -> DXF.Leader {
        var out = self
        out.vertices = vertices.map(t.apply)
        return out
    }
}
