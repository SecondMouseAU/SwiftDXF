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
        case .hatch(var h):
            h.layer = layer
            h.color = color
            return .hatch(h)
        case .leader(var l):
            l.layer = layer
            l.color = color
            return .leader(l)
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
        case .hatch(let h): return h.color
        case .leader(let l): return l.color
        }
    }

    /// The name of the DXF record type, as the reader reports skipped types.
    var typeName: String {
        switch self {
        case .polyline: return "POLYLINE"
        case .line: return "LINE"
        case .circle: return "CIRCLE"
        case .arc: return "ARC"
        case .ellipse: return "ELLIPSE"
        case .point: return "POINT"
        case .text: return "TEXT"
        case .dimension: return "DIMENSION"
        case .spline: return "SPLINE"
        case .hatch: return "HATCH"
        case .leader: return "LEADER"
        }
    }

    /// This entity carried through `t`, or `nil` when `t` cannot carry it exactly: a polyline or
    /// hatch loop with bulges under a non-uniform scale.
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
            // A mirror turns the angle round instead of adding to it.
            let direction = t.isMirrored ? t.directionAngle(degrees: rot) : rot + t.rotationDegrees
            return .text(
                at: t.apply(p), height: h * scaleY, rotationDeg: direction, string: string,
                layer: l, color: c)

        case .polyline(let vertices, let closed, let l, let c):
            guard let moved = t.apply(vertices) else { return nil }
            return .polyline(vertices: moved, closed: closed, layer: l, color: c)

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
            // The stored value is a length: it scales with a uniform scale, and is dropped
            // (the computed value still follows the points) when the scale is not uniform.
            if let m = d.measurement { d.measurement = t.similarity.map { m * $0 } }
            d.carryRotation(through: t)
            return .dimension(d)

        case .hatch(let h):
            return h.transformed(by: t).map { .hatch($0) }

        case .leader(var l):
            l.vertices = l.vertices.map(t.apply)
            return .leader(l)
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

extension DXF.Dimension {
    /// Turns a linear dimension's ``rotation`` into the world direction `t` gives its measuring
    /// axis. A horizontal axis stays `nil` when it was, whichever way it points.
    mutating func carryRotation(through t: DXF.Transform) {
        guard kind == .linear else { return }
        let angle = t.directionAngle(degrees: rotation ?? 0)
        let horizontal = abs(sin(angle * .pi / 180)) < 1e-12
        if rotation != nil || !horizontal { rotation = angle }
    }
}

extension DXF.Transform {
    /// `vertices` carried through this map, or `nil` when a bulge cannot survive it: a bulge is
    /// a circular arc, which a non-uniform scale turns into an ellipse.
    fileprivate func apply(_ vertices: [DXF.PolyVertex]) -> [DXF.PolyVertex]? {
        if vertices.contains(where: { abs($0.bulge) > 1e-12 }), similarity == nil { return nil }
        return vertices.map {
            DXF.PolyVertex(apply($0.point), bulge: isMirrored ? -$0.bulge : $0.bulge)
        }
    }
}

extension DXF.Hatch {
    /// This hatch carried through `t`, or `nil` when `t` cannot carry a bulged polyline path.
    ///
    /// Arc and ellipse edges keep running counter-clockwise from start to end; a mirroring map
    /// reverses which way the path travels them.
    func transformed(by t: DXF.Transform) -> DXF.Hatch? {
        var out = self
        out.paths = []
        for path in paths {
            switch path.geometry {
            case .polyline(let vertices, let closed):
                guard let moved = t.apply(vertices) else { return nil }
                out.paths.append(
                    Path(flags: path.flags, geometry: .polyline(vertices: moved, closed: closed)))
            case .edges(let edges):
                out.paths.append(
                    Path(flags: path.flags, geometry: .edges(edges.map { $0.transformed(by: t) })))
            }
        }
        return out
    }

    private typealias Path = BoundaryPath
}

extension DXF.Hatch.Edge {
    fileprivate func transformed(by t: DXF.Transform) -> DXF.Hatch.Edge {
        let deg = 180 / Double.pi
        switch self {
        case .line(let a, let b):
            return .line(start: t.apply(a), end: t.apply(b))

        case .arc(let center, let r, let s, let e, let ccw):
            let travel = t.isMirrored ? !ccw : ccw
            if let k = t.similarity {
                let phi = t.rotationDegrees
                let (a0, a1) = DXF.Transform.normalizedArc(
                    t.isMirrored ? (phi - e, phi - s) : (s + phi, e + phi))
                return .arc(
                    center: t.apply(center), radius: r * k, startDeg: a0, endDeg: a1,
                    counterClockwise: travel)
            }
            let q = t.ellipse(
                center: center, major: DXF.Point2(r, 0), ratio: 1, start: s / deg,
                end: Self.sweepEnd(s / deg, e / deg))
            return .ellipse(
                center: q.center, majorAxis: q.major, ratio: q.ratio, startParam: q.start,
                endParam: q.end, counterClockwise: travel)

        case .ellipse(let center, let major, let ratio, let s, let e, let ccw):
            let q = t.ellipse(
                center: center, major: major, ratio: ratio, start: s, end: Self.sweepEnd(s, e))
            return .ellipse(
                center: q.center, majorAxis: q.major, ratio: q.ratio, startParam: q.start,
                endParam: q.end, counterClockwise: t.isMirrored ? !ccw : ccw)

        case .spline(var spline):
            spline.controlPoints = spline.controlPoints.map(t.apply)
            spline.fitPoints = spline.fitPoints.map(t.apply)
            return .spline(spline)
        }
    }

    /// `end` raised by a turn when it does not lie past `start`, so the range sweeps forward.
    private static func sweepEnd(_ start: Double, _ end: Double) -> Double {
        end <= start ? end + 2 * .pi : end
    }
}
