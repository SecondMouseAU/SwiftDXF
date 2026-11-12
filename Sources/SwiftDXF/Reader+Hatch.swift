import Foundation

extension DXF.Reader {
    typealias Fields = [(code: Int, value: String)]

    func hatch(_ f: Fields) -> DXF.Hatch {
        DXF.Hatch(
            patternName: first(2, f).map(trimmed) ?? "", isSolid: ints(70, f) == 1,
            paths: boundaryPaths(f), layer: layer(f), color: color(f))
    }

    func leader(_ f: Fields) -> DXF.Leader {
        DXF.Leader(
            vertices: splinePoints(10, f), hasArrowhead: (ints(71, f) ?? 1) != 0,
            isSpline: ints(72, f) == 1, annotationHandle: handle(f, code: 340),
            styleName: first(3, f).map(trimmed).flatMap { $0.isEmpty ? nil : $0 },
            layer: layer(f), color: color(f))
    }

    // MARK: boundary paths

    /// The boundary paths that follow group 91 (the path count).
    ///
    /// Group codes repeat between path types and with the seed points further on, so the paths
    /// are read in sequence, each path consuming only the groups it owns.
    private func boundaryPaths(_ f: Fields) -> [DXF.Hatch.BoundaryPath] {
        guard let countAt = f.firstIndex(where: { $0.code == 91 }) else { return [] }
        let count = ints(91, [f[countAt]]) ?? 0
        var paths: [DXF.Hatch.BoundaryPath] = []
        var i = countAt + 1
        while paths.count < count, let at = nextIndex(of: 92, in: f, from: i) {
            let flags = ints(92, [f[at]]) ?? 0
            i = at + 1
            let geometry: DXF.Hatch.Geometry
            if flags & 2 != 0 {
                (geometry, i) = polylinePath(f, from: i)
            } else {
                (geometry, i) = edgePath(f, from: i)
            }
            paths.append(DXF.Hatch.BoundaryPath(flags: flags, geometry: geometry))
        }
        return paths
    }

    private func nextIndex(of code: Int, in f: Fields, from start: Int) -> Int? {
        guard start < f.count else { return nil }
        return f[start...].firstIndex { $0.code == code }
    }

    private func number(_ f: Fields, _ i: Int) -> Double {
        Double(trimmed(f[i].value)) ?? 0
    }

    private func integer(_ f: Fields, _ i: Int) -> Int {
        Int(trimmed(f[i].value)) ?? 0
    }

    /// A polyline path: `72` has-bulge, `73` closed, `93` vertex count, then `10`/`20`/`42` groups.
    private func polylinePath(_ f: Fields, from start: Int) -> (DXF.Hatch.Geometry, Int) {
        var i = start
        var closed = true
        var limit = Int.max
        while i < f.count, f[i].code != 10 {
            if f[i].code == 73 { closed = integer(f, i) != 0 }
            if f[i].code == 92 { break }
            if f[i].code == 93 {
                limit = max(0, integer(f, i))
                // No vertices: stop here, so the scan cannot run on into the seed points.
                if limit == 0 { return (.polyline(vertices: [], closed: closed), i + 1) }
            }
            i += 1
        }
        var vertices: [DXF.PolyVertex] = []
        var x: Double?
        var y = 0.0
        var bulge = 0.0
        func flush() {
            if let x { vertices.append(DXF.PolyVertex(DXF.Point(x, y, 0), bulge: bulge)) }
            x = nil
            y = 0
            bulge = 0
        }
        scan: while i < f.count {
            switch f[i].code {
            case 10:
                flush()
                if vertices.count >= limit { break scan }
                x = number(f, i)
            case 20: y = number(f, i)
            case 42: bulge = number(f, i)
            default: break scan
            }
            i += 1
        }
        flush()
        return (.polyline(vertices: vertices, closed: closed), i)
    }

    /// An edge path: `93` edge count, then each edge opened by `72` (its type).
    private func edgePath(_ f: Fields, from start: Int) -> (DXF.Hatch.Geometry, Int) {
        var i = start
        while i < f.count, f[i].code != 93 {
            if f[i].code == 92 { return (.edges([]), i) }
            i += 1
        }
        guard i < f.count else { return (.edges([]), i) }
        let count = integer(f, i)
        i += 1
        var edges: [DXF.Hatch.Edge] = []
        while edges.count < count, i < f.count, f[i].code == 72 {
            let type = integer(f, i)
            i += 1
            let edge: DXF.Hatch.Edge?
            switch type {
            case 1, 2, 3:
                var tags: [Int: Double] = [:]
                while i < f.count, Self.simpleEdgeCodes.contains(f[i].code) {
                    if tags[f[i].code] == nil { tags[f[i].code] = number(f, i) }
                    i += 1
                }
                edge = Self.simpleEdge(type, tags)
            case 4:
                (edge, i) = splineEdge(f, from: i)
            default:
                edge = nil
                while i < f.count, f[i].code != 72, f[i].code != 92, f[i].code != 97 { i += 1 }
            }
            if let edge { edges.append(edge) }
        }
        return (.edges(edges), i)
    }

    private static let simpleEdgeCodes: Set<Int> = [10, 20, 11, 21, 40, 50, 51, 73]

    /// A line (`1`), circular arc (`2`) or elliptical arc (`3`) from its groups.
    private static func simpleEdge(_ type: Int, _ t: [Int: Double]) -> DXF.Hatch.Edge {
        let p = DXF.Point2(t[10] ?? 0, t[20] ?? 0)
        if type == 1 { return .line(start: p, end: DXF.Point2(t[11] ?? 0, t[21] ?? 0)) }
        let counterClockwise = (t[73] ?? 1) != 0
        // A clockwise edge is stored as the complementary angles, start and end swapped.
        let raw = (t[50] ?? 0, t[51] ?? 360)
        let (startDeg, endDeg) = counterClockwise ? raw : (360 - raw.1, 360 - raw.0)
        if type == 2 {
            return .arc(
                center: p, radius: t[40] ?? 0, startDeg: startDeg, endDeg: endDeg,
                counterClockwise: counterClockwise)
        }
        let ratio = t[40] ?? 1
        return .ellipse(
            center: p, majorAxis: DXF.Point2(t[11] ?? 0, t[21] ?? 0), ratio: ratio,
            startParam: ellipseParameter(degrees: startDeg, ratio: ratio),
            endParam: ellipseParameter(degrees: endDeg, ratio: ratio),
            counterClockwise: counterClockwise)
    }

    /// The ellipse parameter for the point seen at `degrees` from the centre.
    ///
    /// A hatch edge stores true angles, while an `ELLIPSE` entity stores parameters; the two agree
    /// at the axes. The result keeps the full turns of `degrees`, so 360 degrees is `2 pi`.
    static func ellipseParameter(degrees: Double, ratio: Double) -> Double {
        let angle = degrees * .pi / 180
        guard ratio > 0 else { return angle }
        let param = atan2(sin(angle) / ratio, cos(angle))
        return param + 2 * .pi * ((angle - param) / (2 * .pi)).rounded()
    }

    /// A spline edge: degree, flags, counts, knots, control points (with weights), fit points.
    private func splineEdge(_ f: Fields, from start: Int) -> (DXF.Hatch.Edge?, Int) {
        var i = start
        func take(_ code: Int) -> Int? {
            guard i < f.count, f[i].code == code else { return nil }
            defer { i += 1 }
            return integer(f, i)
        }
        let degree = take(94) ?? 3
        let rational = (take(73) ?? 0) != 0
        let periodic = (take(74) ?? 0) != 0
        let knotCount = min(take(95) ?? 0, f.count)
        let pointCount = min(take(96) ?? 0, f.count)

        var knots: [Double] = []
        while knots.count < knotCount, i < f.count, f[i].code == 40 {
            knots.append(number(f, i))
            i += 1
        }
        var control: [DXF.Point] = []
        var weights: [Double] = []
        while control.count < pointCount, i < f.count, f[i].code == 10 {
            let x = number(f, i)
            i += 1
            var y = 0.0
            if i < f.count, f[i].code == 20 {
                y = number(f, i)
                i += 1
            }
            control.append(DXF.Point(x, y, 0))
            if rational, i < f.count, f[i].code == 42 {
                weights.append(number(f, i))
                i += 1
            }
        }
        var fit: [DXF.Point] = []
        let fitCount = min(take(97) ?? 0, f.count)
        while fit.count < fitCount, i < f.count, f[i].code == 11 {
            let x = number(f, i)
            i += 1
            var y = 0.0
            if i < f.count, f[i].code == 21 {
                y = number(f, i)
                i += 1
            }
            fit.append(DXF.Point(x, y, 0))
        }
        // Optional start and end tangents.
        while i < f.count, [12, 22, 13, 23].contains(f[i].code) { i += 1 }

        let flags = (periodic ? 2 : 0) | (rational ? 4 : 0)
        let spline = DXF.Spline(
            degree: degree, flags: flags, controlPoints: control, knots: knots, weights: weights,
            fitPoints: fit)
        return (.spline(spline), i)
    }
}
